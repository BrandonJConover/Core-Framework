//! Connection-storm benchmark: spin up N concurrent WebSocket *or* TCP sessions,
//! send a synthetic LOGIN then a stream of HEARTBEAT packets, and measure
//! throughput and per-tick latency.
//!
//! Usage:
//!   cargo run --bin conn_storm -- --mode ws  --addr 127.0.0.1:43494 --connections 200 --ticks 100
//!   cargo run --bin conn_storm -- --mode tcp --addr 127.0.0.1:43594 --connections 200 --ticks 100
//!   cargo run --bin conn_storm -- --mode tcp --connections 1 --ticks 1 --expect-bootstrap
//!   cargo run --bin conn_storm -- --mode ws --connections 1 --ticks 1 --expect-playable
//!   cargo run --bin conn_storm -- --mode tcp --connections 1 --ticks 1 --expect-reconnect
//!
//! Output: p50 / p95 / p99 tick RTT in µs, total throughput in packets/s.

use std::net::SocketAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use bytes::{BufMut, Bytes, BytesMut};
use futures_util::{SinkExt, StreamExt};
use rsa::pkcs8::DecodePrivateKey;
use rsa::traits::PublicKeyParts;
use rsa::{BigUint, RsaPrivateKey};
use sqlx::{sqlite::SqlitePoolOptions, Row};
use std::collections::HashSet;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::Barrier;
use tokio_tungstenite::{connect_async, tungstenite::Message};

/// Wire opcode for LOGIN in v177.
const LOGIN_WIRE_BYTE: u8 = 0;
/// Wire opcode for HEARTBEAT in v177.
const PING_WIRE_BYTE: u8 = 5;
const LOGOUT_WIRE_BYTE: u8 = 6;
const CONFIRM_LOGOUT_WIRE_BYTE: u8 = 1;
const COMMAND_WIRE_BYTE: u8 = 7;
const SERVER_CONFIG_REQUEST_WIRE_BYTE: u8 = 19;
const BANK_DEPOSIT_WIRE_BYTE: u8 = 205;
const BANK_WITHDRAW_WIRE_BYTE: u8 = 206;
const BANK_CLOSE_WIRE_BYTE: u8 = 207;
const SHOP_SELL_WIRE_BYTE: u8 = 216;
const SHOP_BUY_WIRE_BYTE: u8 = 217;
const SHOP_CLOSE_WIRE_BYTE: u8 = 218;
const WALK_TO_POINT_WIRE_BYTE: u8 = 194;
const CHAT_WIRE_BYTE: u8 = 3;
const GAME_SETTINGS_CHANGED_WIRE_BYTE: u8 = 213;
const COMBAT_STYLE_CHANGED_WIRE_BYTE: u8 = 231;
const NPC_COMMAND_WIRE_BYTE: u8 = 195;
const OBJECT_COMMAND_WIRE_BYTE: u8 = 242;
const PRAYER_ACTIVATED_WIRE_BYTE: u8 = 212;
const PRAYER_DEACTIVATED_WIRE_BYTE: u8 = 211;
const PLAYER_APPEARANCE_CHANGE_WIRE_BYTE: u8 = 236;
const PRIVACY_SETTINGS_CHANGED_WIRE_BYTE: u8 = 31;
const GROUND_ITEM_TAKE_WIRE_BYTE: u8 = 252;
const ITEM_DROP_WIRE_BYTE: u8 = 251;
const SEND_SERVER_CONFIGS: u8 = 19;
const SEND_WORLD_INFO: u8 = 25;
const SEND_BANK_OPEN: u8 = 42;
const SEND_INVENTORY: u8 = 53;
const SEND_NPC_COORDS: u8 = 79;
const SEND_SHOP_OPEN: u8 = 101;
const SEND_GROUND_ITEM_HANDLER: u8 = 99;
const SEND_SERVER_MESSAGE: u8 = 131;
const SEND_COMBAT_STYLE: u8 = 129;
const SEND_STATS: u8 = 156;
const SEND_PLAYER_COORDS: u8 = 191;
const SEND_BANK_CLOSE: u8 = 203;
const SEND_PRAYERS_ACTIVE: u8 = 206;
const SEND_UPDATE_PLAYERS: u8 = 234;
const SEND_GAME_SETTINGS: u8 = 240;
const SEND_BANK_UPDATE: u8 = 249;
const SEND_EQUIPMENT: u8 = 254;

/// Build a minimal RSC-framed packet (2-byte big-endian length prefix).
/// The `length` field encodes (payload_len + 1) for RSC: it includes the
/// opcode byte but NOT the 2-byte length header itself.
fn frame(opcode: u8, payload: &[u8]) -> Bytes {
    let total_len = (payload.len() + 1) as u16; // +1 for opcode
    let mut b = BytesMut::with_capacity(2 + 1 + payload.len());
    b.put_u16(total_len);
    b.put_u8(opcode);
    b.put_slice(payload);
    b.freeze()
}

fn login_packet(username: &str, password: &str, custom_rsa_login: bool) -> Bytes {
    if custom_rsa_login {
        custom_rsa_login_packet(username, password, false)
    } else {
        legacy_login_packet_with_opcode(username, password, LOGIN_WIRE_BYTE, false)
    }
}

fn reconnect_login_packet(username: &str, password: &str, custom_rsa_login: bool) -> Bytes {
    if custom_rsa_login {
        custom_rsa_login_packet(username, password, true)
    } else {
        legacy_login_packet_with_opcode(username, password, 19, true)
    }
}

fn server_config_request_packet() -> Bytes {
    frame(SERVER_CONFIG_REQUEST_WIRE_BYTE, &[])
}

/// Minimal LOGIN packet for bench mode (accept-all, no DB).
/// Format: reconnecting(1) version(4) username(cstring) password(cstring)
fn legacy_login_packet_with_opcode(
    username: &str,
    password: &str,
    opcode: u8,
    reconnecting: bool,
) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u8(if reconnecting { 1 } else { 0 });
    payload.put_u32(177); // client_version
                          // username as null-terminated
    payload.put_slice(username.as_bytes());
    payload.put_u8(0);
    payload.put_slice(password.as_bytes());
    payload.put_u8(0);
    frame(opcode, &payload)
}

/// Java custom desktop LOGIN shape:
/// reconnecting(1), client_version(4), username(lf-string), encryption=1,
/// RSA password block, RSA client details block, uid(8).
fn custom_rsa_login_packet(username: &str, password: &str, reconnecting: bool) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u8(if reconnecting { 1 } else { 0 });
    payload.put_u32(10010);
    payload.put_slice(username.as_bytes());
    payload.put_u8(10);
    payload.put_u8(1);
    write_client_rsa_block(&mut payload, padded_login_password(password).as_bytes());
    write_client_rsa_block(&mut payload, b"conn_storm");
    payload.put_u64(0x0102_0304_0506_0708);
    frame(LOGIN_WIRE_BYTE, &payload)
}

fn padded_login_password(password: &str) -> String {
    let mut padded = String::with_capacity(20);
    for index in 0..20 {
        let Some(c) = password.chars().nth(index) else {
            padded.push(' ');
            continue;
        };
        padded.push(if c.is_ascii_alphanumeric() { c } else { '_' });
    }
    padded
}

fn write_client_rsa_block(payload: &mut BytesMut, plaintext: &[u8]) {
    let pem = include_str!("../../../server-java-modern/server.pem");
    let key = RsaPrivateKey::from_pkcs8_pem(pem).expect("Java server.pem must parse");
    let encrypted = encrypt_like_java_client(plaintext, key.n());
    payload.put_u16(encrypted.len() as u16);
    payload.put_slice(&encrypted);
}

fn encrypt_like_java_client(plaintext: &[u8], modulus: &BigUint) -> Vec<u8> {
    let public_exponent = BigUint::from(65_537u32);
    let encrypted = BigUint::from_bytes_be(plaintext).modpow(&public_exponent, modulus);
    signed_positive_bytes(&encrypted)
}

fn signed_positive_bytes(value: &BigUint) -> Vec<u8> {
    if *value == BigUint::from(0u32) {
        return vec![0];
    }
    let mut bytes = value.to_bytes_be();
    if bytes[0] & 0x80 != 0 {
        bytes.insert(0, 0);
    }
    bytes
}

/// Single-byte PING packet.
fn ping_packet() -> Bytes {
    frame(PING_WIRE_BYTE, &[])
}

fn logout_packet() -> Bytes {
    frame(LOGOUT_WIRE_BYTE, &[])
}

fn confirm_logout_packet() -> Bytes {
    frame(CONFIRM_LOGOUT_WIRE_BYTE, &[])
}

fn walk_one_tile_packet() -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(122);
    payload.put_u16(647);
    payload.put_i8(1);
    payload.put_i8(0);
    frame(WALK_TO_POINT_WIRE_BYTE, &payload)
}

fn chat_packet(message: &str) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_slice(message.as_bytes());
    payload.put_u8(0);
    frame(CHAT_WIRE_BYTE, &payload)
}

fn command_packet(command: &str) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_slice(command.as_bytes());
    payload.put_u8(0);
    frame(COMMAND_WIRE_BYTE, &payload)
}

fn bank_item_amount_packet(opcode: u8, item_id: u16, amount: u32) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(item_id);
    payload.put_u32(amount);
    frame(opcode, &payload)
}

fn bank_close_packet() -> Bytes {
    frame(BANK_CLOSE_WIRE_BYTE, &[])
}

fn shop_item_amount_packet(opcode: u8, item_id: u16, stock_amount: u16, amount: u16) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(item_id);
    payload.put_u16(stock_amount);
    payload.put_u16(amount);
    frame(opcode, &payload)
}

fn shop_close_packet() -> Bytes {
    frame(SHOP_CLOSE_WIRE_BYTE, &[])
}

fn npc_command_packet(npc_index: u16) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(npc_index);
    frame(NPC_COMMAND_WIRE_BYTE, &payload)
}

fn object_command_packet(x: u16, y: u16) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(x);
    payload.put_u16(y);
    frame(OBJECT_COMMAND_WIRE_BYTE, &payload)
}

fn combat_style_packet(style: u8) -> Bytes {
    frame(COMBAT_STYLE_CHANGED_WIRE_BYTE, &[style])
}

fn prayer_toggle_packet(opcode: u8, prayer_id: u8) -> Bytes {
    frame(opcode, &[prayer_id])
}

fn game_setting_packet(index: u8, value: u8) -> Bytes {
    frame(GAME_SETTINGS_CHANGED_WIRE_BYTE, &[index, value])
}

fn privacy_settings_packet(
    block_chat: bool,
    block_private: bool,
    block_trade: bool,
    block_duel: bool,
) -> Bytes {
    frame(
        PRIVACY_SETTINGS_CHANGED_WIRE_BYTE,
        &[
            block_chat as u8,
            block_private as u8,
            block_trade as u8,
            block_duel as u8,
        ],
    )
}

fn appearance_change_packet() -> Bytes {
    frame(
        PLAYER_APPEARANCE_CHANGE_WIRE_BYTE,
        &[1, 3, 4, 2, 5, 6, 7, 1, 0, 0],
    )
}

fn take_ground_item_packet(x: u16, y: u16, item_id: u16) -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(x);
    payload.put_u16(y);
    payload.put_u16(item_id);
    frame(GROUND_ITEM_TAKE_WIRE_BYTE, &payload)
}

fn playable_pickup_packets() -> [Bytes; 3] {
    [
        take_ground_item_packet(123, 648, 10),
        take_ground_item_packet(123, 647, 10),
        take_ground_item_packet(121, 646, 20),
    ]
}

fn drop_first_inventory_slot_packet() -> Bytes {
    let mut payload = BytesMut::new();
    payload.put_u16(0);
    payload.put_u32(1);
    frame(ITEM_DROP_WIRE_BYTE, &payload)
}

#[tokio::main(flavor = "multi_thread")]
async fn main() {
    let args = parse_args();

    println!(
        "conn_storm: mode={} addr={} connections={} ticks={}",
        args.mode, args.addr, args.connections, args.ticks
    );

    let barrier = Arc::new(Barrier::new(args.connections));
    let latencies: Arc<std::sync::Mutex<Vec<u64>>> = Arc::new(std::sync::Mutex::new(
        Vec::with_capacity(args.connections * args.ticks),
    ));
    let errors = Arc::new(AtomicU64::new(0));

    let start = Instant::now();
    let mut handles = Vec::with_capacity(args.connections);

    if args.expect_db_reconnect {
        if args.connections != 1 {
            eprintln!("--expect-db-reconnect requires --connections 1");
            return;
        }
        if let Err(e) = prepare_db_smoke(&args).await {
            eprintln!("DB smoke setup error: {e}");
            return;
        }
    }

    for i in 0..args.connections {
        let addr = args.addr;
        let mode = args.mode.clone();
        let ticks = args.ticks;
        let expect_bootstrap = args.expect_bootstrap;
        let expect_playable = args.expect_playable;
        let expect_reconnect = args.expect_reconnect;
        let expect_db_reconnect = args.expect_db_reconnect;
        let custom_rsa_login = args.custom_rsa_login;
        let db_sqlite = args.db_sqlite.clone();
        let password = args.password.clone().unwrap_or_default();
        let barrier = barrier.clone();
        let latencies = latencies.clone();
        let errors = errors.clone();
        let username = args
            .username
            .clone()
            .unwrap_or_else(|| format!("bench{:04}", i));

        handles.push(tokio::spawn(async move {
            // Wait for all connections to be spawned.
            barrier.wait().await;

            let result = if mode == "ws" {
                run_ws_session(
                    addr,
                    &username,
                    &password,
                    ticks,
                    expect_bootstrap || expect_playable || expect_reconnect || expect_db_reconnect,
                    expect_playable,
                    expect_reconnect,
                    expect_db_reconnect,
                    custom_rsa_login,
                    db_sqlite.as_deref(),
                )
                .await
            } else {
                run_tcp_session(
                    addr,
                    &username,
                    &password,
                    ticks,
                    expect_bootstrap || expect_playable || expect_reconnect || expect_db_reconnect,
                    expect_playable,
                    expect_reconnect,
                    expect_db_reconnect,
                    custom_rsa_login,
                    db_sqlite.as_deref(),
                )
                .await
            };

            match result {
                Ok(rtt_us) => {
                    let mut lats = latencies.lock().unwrap();
                    lats.extend(rtt_us);
                }
                Err(e) => {
                    eprintln!("session {} error: {}", username, e);
                    errors.fetch_add(1, Ordering::Relaxed);
                }
            }
        }));
    }

    for h in handles {
        let _ = h.await;
    }

    let elapsed = start.elapsed();
    let total_errors = errors.load(Ordering::Relaxed);
    let mut lats = latencies.lock().unwrap();
    lats.sort_unstable();

    let n = lats.len();
    if n == 0 {
        if total_errors == 0 {
            println!("=== Results ===");
            println!("  Connections: {} (0 errors)", args.connections);
            println!("  Total elapsed: {:.2?}", elapsed);
            return;
        }
        println!("No successful measurements. Errors: {}", total_errors);
        return;
    }

    let total_packets = n + (args.connections - total_errors as usize); // +logins
    let throughput = total_packets as f64 / elapsed.as_secs_f64();
    println!("=== Results ===");
    println!(
        "  Connections: {} ({} errors)",
        args.connections, total_errors
    );
    println!("  Total elapsed: {:.2?}", elapsed);
    println!("  Throughput: {:.0} packets/s", throughput);
    println!("  RTT p50: {}µs", lats[n / 2]);
    println!("  RTT p95: {}µs", lats[n * 95 / 100]);
    println!("  RTT p99: {}µs", lats[n * 99 / 100]);
    println!("  RTT max: {}µs", lats[n - 1]);
}

/// Run one WS session: connect, login, send `ticks` pings, collect RTTs.
async fn run_ws_session(
    addr: SocketAddr,
    username: &str,
    password: &str,
    ticks: usize,
    expect_bootstrap: bool,
    expect_playable: bool,
    expect_reconnect: bool,
    expect_db_reconnect: bool,
    custom_rsa_login: bool,
    db_sqlite: Option<&str>,
) -> anyhow::Result<Vec<u64>> {
    let url = format!("ws://{}/", addr);

    if expect_bootstrap {
        expect_ws_server_configs(&url).await?;
    }

    let (mut ws, _) = connect_async(&url).await?;

    // Send LOGIN.
    ws.send(Message::Binary(
        login_packet(username, password, custom_rsa_login).to_vec(),
    ))
    .await?;

    // Read login response (1 raw byte: 0 = success).
    let resp = ws
        .next()
        .await
        .ok_or_else(|| anyhow::anyhow!("no login response"))??;
    validate_ws_login_response(resp)?;

    let bootstrap_frames = if expect_bootstrap {
        Some(expect_ws_bootstrap(&mut ws).await?)
    } else {
        None
    };
    if expect_db_reconnect {
        expect_bootstrap_persisted_state(
            bootstrap_frames.as_deref().unwrap_or(&[]),
            122,
            647,
            &[1, 1, 1],
            30,
        )?;
        expect_ws_db_reconnect(ws, addr, username, password, custom_rsa_login, db_sqlite).await?;
        return Ok(Vec::new());
    }
    if expect_playable {
        expect_ws_playable_actions(&mut ws).await?;
    }

    let mut rtts = Vec::with_capacity(ticks);
    for _ in 0..ticks {
        let t0 = Instant::now();
        ws.send(Message::Binary(ping_packet().to_vec())).await?;
        // Server sends entity-update packets every tick; we just time the send latency here.
        rtts.push(t0.elapsed().as_micros() as u64);
        tokio::time::sleep(Duration::from_millis(640)).await; // one RSC tick
    }
    if expect_reconnect {
        expect_ws_logout_reconnect(ws, addr, username, password, custom_rsa_login).await?;
        return Ok(rtts);
    }
    let _ = ws.close(None).await;
    Ok(rtts)
}

/// Run one TCP session: same flow as WS but over raw TCP with RSC framing.
async fn run_tcp_session(
    addr: SocketAddr,
    username: &str,
    password: &str,
    ticks: usize,
    expect_bootstrap: bool,
    expect_playable: bool,
    expect_reconnect: bool,
    expect_db_reconnect: bool,
    custom_rsa_login: bool,
    db_sqlite: Option<&str>,
) -> anyhow::Result<Vec<u64>> {
    if expect_bootstrap {
        expect_tcp_server_configs(addr).await?;
    }

    let mut stream = TcpStream::connect(addr).await?;

    // Send LOGIN.
    stream
        .write_all(&login_packet(username, password, custom_rsa_login))
        .await?;

    // Read login response byte.
    let mut resp = [0u8; 1];
    stream.read_exact(&mut resp).await?;
    if resp[0] != 0 {
        anyhow::bail!("login rejected: code {}", resp[0]);
    }

    let bootstrap_frames = if expect_bootstrap {
        Some(expect_tcp_bootstrap(&mut stream).await?)
    } else {
        None
    };
    if expect_db_reconnect {
        expect_bootstrap_persisted_state(
            bootstrap_frames.as_deref().unwrap_or(&[]),
            122,
            647,
            &[1, 1, 1],
            30,
        )?;
        expect_tcp_db_reconnect(
            stream,
            addr,
            username,
            password,
            custom_rsa_login,
            db_sqlite,
        )
        .await?;
        return Ok(Vec::new());
    }
    if expect_playable {
        expect_tcp_playable_actions(&mut stream).await?;
    }

    let mut rtts = Vec::with_capacity(ticks);
    for _ in 0..ticks {
        let t0 = Instant::now();
        stream.write_all(&ping_packet()).await?;
        rtts.push(t0.elapsed().as_micros() as u64);
        tokio::time::sleep(Duration::from_millis(640)).await;
    }
    if expect_reconnect {
        expect_tcp_logout_reconnect(stream, addr, username, password, custom_rsa_login).await?;
    }
    Ok(rtts)
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ServerFrame {
    opcode: u8,
    payload_len: usize,
    payload: Vec<u8>,
}

fn try_decode_server_frame(buffer: &mut BytesMut) -> anyhow::Result<Option<ServerFrame>> {
    if buffer.len() < 2 {
        return Ok(None);
    }

    let frame_size = u16::from_be_bytes([buffer[0], buffer[1]]) as usize;
    if frame_size < 3 {
        anyhow::bail!("invalid server frame size {frame_size}");
    }
    if buffer.len() < frame_size {
        return Ok(None);
    }

    let frame = buffer.split_to(frame_size);
    Ok(Some(ServerFrame {
        opcode: frame[2],
        payload_len: frame_size - 3,
        payload: frame[3..].to_vec(),
    }))
}

fn collect_decoded_frames(
    buffer: &mut BytesMut,
    seen: &mut HashSet<u8>,
) -> anyhow::Result<Vec<ServerFrame>> {
    let mut frames = Vec::new();
    while let Some(frame) = try_decode_server_frame(buffer)? {
        seen.insert(frame.opcode);
        frames.push(frame);
    }
    Ok(frames)
}

fn required_bootstrap_opcodes() -> HashSet<u8> {
    [
        SEND_WORLD_INFO,
        SEND_STATS,
        SEND_INVENTORY,
        SEND_EQUIPMENT,
        SEND_GAME_SETTINGS,
        SEND_PRAYERS_ACTIVE,
        SEND_SERVER_MESSAGE,
        SEND_PLAYER_COORDS,
        SEND_NPC_COORDS,
    ]
    .into_iter()
    .collect()
}

fn missing_required(seen: &HashSet<u8>) -> Vec<u8> {
    let mut missing: Vec<u8> = required_bootstrap_opcodes()
        .difference(seen)
        .copied()
        .collect();
    missing.sort_unstable();
    missing
}

fn has_frame(frames: &[ServerFrame], opcode: u8) -> bool {
    frames.iter().any(|f| f.opcode == opcode)
}

fn assert_frame_seen(frames: &[ServerFrame], opcode: u8, action: &str) -> anyhow::Result<()> {
    if has_frame(frames, opcode) {
        Ok(())
    } else {
        let seen: Vec<u8> = frames.iter().map(|f| f.opcode).collect();
        anyhow::bail!("{action} did not receive opcode {opcode}; saw {seen:?}")
    }
}

fn assert_frame_payload(
    frames: &[ServerFrame],
    opcode: u8,
    payload: &[u8],
    action: &str,
) -> anyhow::Result<()> {
    if frames
        .iter()
        .any(|f| f.opcode == opcode && f.payload.as_slice() == payload)
    {
        Ok(())
    } else {
        let seen: Vec<(u8, Vec<u8>)> = frames
            .iter()
            .map(|f| (f.opcode, f.payload.clone()))
            .collect();
        anyhow::bail!("{action} did not receive opcode {opcode} payload {payload:?}; saw {seen:?}")
    }
}

fn assert_server_message_contains(
    frames: &[ServerFrame],
    expected: &str,
    action: &str,
) -> anyhow::Result<()> {
    if frames.iter().any(|f| {
        f.opcode == SEND_SERVER_MESSAGE && String::from_utf8_lossy(&f.payload).contains(expected)
    }) {
        Ok(())
    } else {
        let seen: Vec<(u8, String)> = frames
            .iter()
            .map(|f| (f.opcode, String::from_utf8_lossy(&f.payload).to_string()))
            .collect();
        anyhow::bail!(
            "{action} did not receive server message containing {expected:?}; saw {seen:?}"
        )
    }
}

fn assert_prayer_state(
    frames: &[ServerFrame],
    prayer_id: usize,
    active: bool,
) -> anyhow::Result<()> {
    if frames.iter().any(|f| {
        f.opcode == SEND_PRAYERS_ACTIVE
            && f.payload.len() > prayer_id
            && f.payload[prayer_id] == active as u8
    }) {
        Ok(())
    } else {
        let seen: Vec<(u8, Vec<u8>)> = frames
            .iter()
            .map(|f| (f.opcode, f.payload.clone()))
            .collect();
        anyhow::bail!(
            "prayer {prayer_id} active={active} did not receive matching opcode {SEND_PRAYERS_ACTIVE}; saw {seen:?}"
        )
    }
}

fn frame_payload<'a>(
    frames: &'a [ServerFrame],
    opcode: u8,
    action: &str,
) -> anyhow::Result<&'a [u8]> {
    frames
        .iter()
        .find(|f| f.opcode == opcode)
        .map(|f| f.payload.as_slice())
        .ok_or_else(|| anyhow::anyhow!("{action} did not receive opcode {opcode}"))
}

fn expect_bootstrap_persisted_state(
    frames: &[ServerFrame],
    expected_x: u16,
    expected_y: u16,
    expected_settings: &[u8; 3],
    expected_coin_amount: u32,
) -> anyhow::Result<()> {
    let world = frame_payload(frames, SEND_WORLD_INFO, "DB bootstrap world info")?;
    if world.len() < 4 {
        anyhow::bail!("DB bootstrap world info payload too short: {}", world.len());
    }
    let x = u16::from_be_bytes([world[0], world[1]]);
    let y = u16::from_be_bytes([world[2], world[3]]);
    if (x, y) != (expected_x, expected_y) {
        anyhow::bail!("expected position ({expected_x},{expected_y}), got ({x},{y})");
    }

    let stats = frame_payload(frames, SEND_STATS, "DB bootstrap stats")?;
    if stats.len() < 18 {
        anyhow::bail!("DB bootstrap stats payload too short: {}", stats.len());
    }
    if stats[0] != 4 || stats[1] != 5 || stats[2] != 6 {
        anyhow::bail!(
            "expected persisted combat levels attack/def/str 4/5/6, got {}/{}/{}",
            stats[0],
            stats[1],
            stats[2]
        );
    }

    expect_inventory_payload(
        frame_payload(frames, SEND_INVENTORY, "DB bootstrap inventory")?,
        expected_coin_amount,
    )?;

    expect_settings_payload(
        frame_payload(frames, SEND_GAME_SETTINGS, "DB bootstrap settings")?,
        expected_settings,
    )
}

fn expect_settings_payload(payload: &[u8], expected: &[u8; 3]) -> anyhow::Result<()> {
    if payload != expected {
        anyhow::bail!("expected settings payload {expected:?}, got {payload:?}");
    }
    Ok(())
}

fn expect_inventory_payload(payload: &[u8], expected_coin_amount: u32) -> anyhow::Result<()> {
    if payload.is_empty() {
        anyhow::bail!("inventory payload empty");
    }
    let count = payload[0] as usize;
    let mut offset = 1usize;
    let mut items = Vec::new();
    for _ in 0..count {
        if payload.len() < offset + 8 {
            anyhow::bail!("inventory payload truncated at item {offset}");
        }
        let item_id = u16::from_be_bytes([payload[offset], payload[offset + 1]]);
        let wielded = payload[offset + 2] != 0;
        let noted = payload[offset + 3] != 0;
        let amount = u32::from_be_bytes([
            payload[offset + 4],
            payload[offset + 5],
            payload[offset + 6],
            payload[offset + 7],
        ]);
        items.push((item_id, amount, wielded, noted));
        offset += 8;
    }

    if !items.contains(&(10, expected_coin_amount, false, false)) {
        anyhow::bail!("missing seeded inventory item 10x{expected_coin_amount}; saw {items:?}");
    }
    if !items.contains(&(20, 1, true, true)) {
        anyhow::bail!("missing seeded wielded/noted inventory item 20x1; saw {items:?}");
    }
    Ok(())
}

fn expect_bank_open_payload(payload: &[u8]) -> anyhow::Result<()> {
    if payload.len() < 2 {
        anyhow::bail!("bank open payload too short: {}", payload.len());
    }
    let count = payload[0] as usize;
    let capacity = payload[1];
    if capacity != 192 {
        anyhow::bail!("expected member bank capacity 192, got {capacity}");
    }

    let mut offset = 2usize;
    let mut items = Vec::new();
    for _ in 0..count {
        if payload.len() < offset + 4 {
            anyhow::bail!("bank open payload truncated at item offset {offset}");
        }
        let item_id = u16::from_be_bytes([payload[offset], payload[offset + 1]]);
        offset += 2;
        let (amount, consumed) = read_unsigned_short_int(&payload[offset..])?;
        offset += consumed;
        items.push((item_id, amount));
    }
    if offset != payload.len() {
        anyhow::bail!(
            "bank open payload had {} trailing byte(s)",
            payload.len() - offset
        );
    }

    if !items.contains(&(10, 5)) {
        anyhow::bail!("missing seeded bank item 10x5; saw {items:?}");
    }
    if !items.contains(&(20, 32_768)) {
        anyhow::bail!("missing seeded bank item 20x32768; saw {items:?}");
    }
    Ok(())
}

fn expect_shop_stock_payload(
    payload: &[u8],
    expected_item_id: u16,
    expected_amount: u16,
) -> anyhow::Result<()> {
    if payload.len() < 5 {
        anyhow::bail!("shop open payload too short: {}", payload.len());
    }
    let count = payload[0] as usize;
    let mut offset = 5usize;
    let mut items = Vec::new();
    for _ in 0..count {
        if payload.len() < offset + 6 {
            anyhow::bail!("shop open payload truncated at item offset {offset}");
        }
        let item_id = u16::from_be_bytes([payload[offset], payload[offset + 1]]);
        let amount = u16::from_be_bytes([payload[offset + 2], payload[offset + 3]]);
        let base_amount = u16::from_be_bytes([payload[offset + 4], payload[offset + 5]]);
        items.push((item_id, amount, base_amount));
        offset += 6;
    }
    if offset != payload.len() {
        anyhow::bail!(
            "shop open payload had {} trailing byte(s)",
            payload.len() - offset
        );
    }
    if !items
        .iter()
        .any(|(item_id, amount, _)| *item_id == expected_item_id && *amount == expected_amount)
    {
        anyhow::bail!("missing shop item {expected_item_id}x{expected_amount}; saw {items:?}");
    }
    Ok(())
}

fn expect_shop_stock_payload_with_modifiers(
    payload: &[u8],
    expected_item_id: u16,
    expected_amount: u16,
    expected_general_flag: u8,
    expected_sell_modifier: u8,
    expected_buy_modifier: u8,
    expected_price_modifier: u8,
) -> anyhow::Result<()> {
    expect_shop_stock_payload(payload, expected_item_id, expected_amount)?;
    if payload[1] != expected_general_flag
        || payload[2] != expected_sell_modifier
        || payload[3] != expected_buy_modifier
        || payload[4] != expected_price_modifier
    {
        anyhow::bail!(
            "unexpected shop modifiers general/sell/buy/price = {}/{}/{}/{}",
            payload[1],
            payload[2],
            payload[3],
            payload[4]
        );
    }
    Ok(())
}

fn read_unsigned_short_int(payload: &[u8]) -> anyhow::Result<(u32, usize)> {
    if payload.len() < 2 {
        anyhow::bail!("unsigned-short-int payload too short");
    }
    let short = u16::from_be_bytes([payload[0], payload[1]]);
    if short < 0x8000 {
        return Ok((short as u32, 2));
    }
    if payload.len() < 4 {
        anyhow::bail!("large unsigned-short-int payload too short");
    }
    let encoded = i32::from_be_bytes([payload[0], payload[1], payload[2], payload[3]]);
    Ok((encoded.wrapping_sub(i32::MIN) as u32, 4))
}

fn read_config_string(payload: &[u8], offset: &mut usize, field: &str) -> anyhow::Result<String> {
    let start = *offset;
    let Some(relative_end) = payload[start..].iter().position(|b| *b == 10) else {
        anyhow::bail!("server config field {field} missing line-feed terminator");
    };
    let end = start + relative_end;
    *offset = end + 1;
    String::from_utf8(payload[start..end].to_vec())
        .map_err(|e| anyhow::anyhow!("server config field {field} was not UTF-8: {e}"))
}

fn skip_config_bytes(payload: &[u8], offset: &mut usize, count: usize) -> anyhow::Result<()> {
    if payload.len() < *offset + count {
        anyhow::bail!(
            "server config payload truncated: need {count} byte(s) at offset {}, len {}",
            *offset,
            payload.len()
        );
    }
    *offset += count;
    Ok(())
}

fn expect_server_configs_payload(payload: &[u8]) -> anyhow::Result<()> {
    let mut offset = 0usize;

    let server_name = read_config_string(payload, &mut offset, "server name")?;
    let welcome_name = read_config_string(payload, &mut offset, "welcome server name")?;
    if server_name != "OpenRSC Rust" || welcome_name != "OpenRSC Rust" {
        anyhow::bail!(
            "unexpected server config names: server={server_name:?} welcome={welcome_name:?}"
        );
    }

    skip_config_bytes(payload, &mut offset, 39)?;
    let welcome_text = read_config_string(payload, &mut offset, "welcome text")?;
    if welcome_text != "Welcome to OpenRSC Rust" {
        anyhow::bail!("unexpected welcome text {welcome_text:?}");
    }

    skip_config_bytes(payload, &mut offset, 2)?;
    let logo_sprite_id = read_config_string(payload, &mut offset, "logo sprite id")?;
    if !logo_sprite_id.is_empty() {
        anyhow::bail!("expected empty logo sprite id, got {logo_sprite_id:?}");
    }

    skip_config_bytes(payload, &mut offset, 41)?;
    let exponent = read_config_string(payload, &mut offset, "rsa public exponent")?;
    let modulus = read_config_string(payload, &mut offset, "rsa public modulus")?;
    if exponent != "010001" {
        anyhow::bail!("unexpected RSA public exponent {exponent:?}");
    }
    if modulus.is_empty() || modulus.len() % 2 != 0 {
        anyhow::bail!("unexpected RSA public modulus length {}", modulus.len());
    }
    if offset != payload.len() {
        anyhow::bail!(
            "server config payload had {} trailing byte(s)",
            payload.len() - offset
        );
    }

    Ok(())
}

fn expect_server_configs_frame(frames: &[ServerFrame]) -> anyhow::Result<()> {
    let payload = frame_payload(frames, SEND_SERVER_CONFIGS, "server config request")?;
    expect_server_configs_payload(payload)
}

fn expect_bank_open(frames: &[ServerFrame], action: &str) -> anyhow::Result<()> {
    expect_bank_open_payload(frame_payload(frames, SEND_BANK_OPEN, action)?)
}

fn expect_varrock_sword_shop_stock(
    frames: &[ServerFrame],
    item_id: u16,
    amount: u16,
    action: &str,
) -> anyhow::Result<()> {
    expect_shop_stock_payload_with_modifiers(
        frame_payload(frames, SEND_SHOP_OPEN, action)?,
        item_id,
        amount,
        0,
        60,
        100,
        2,
    )
}

fn expect_bank_update(
    frames: &[ServerFrame],
    item_id: u16,
    amount: u32,
    action: &str,
) -> anyhow::Result<()> {
    for frame in frames.iter().filter(|f| f.opcode == SEND_BANK_UPDATE) {
        if frame.payload.len() < 3 {
            continue;
        }
        let got_item_id = u16::from_be_bytes([frame.payload[1], frame.payload[2]]);
        let Ok((got_amount, consumed)) = read_unsigned_short_int(&frame.payload[3..]) else {
            continue;
        };
        if got_item_id == item_id && got_amount == amount && frame.payload.len() == 3 + consumed {
            return Ok(());
        }
    }
    let seen: Vec<(u8, Vec<u8>)> = frames
        .iter()
        .map(|f| (f.opcode, f.payload.clone()))
        .collect();
    anyhow::bail!(
        "{action} did not receive bank update for item {item_id} amount {amount}; saw {seen:?}"
    )
}

async fn expect_tcp_bank_movement(stream: &mut TcpStream) -> anyhow::Result<()> {
    stream
        .write_all(&bank_item_amount_packet(BANK_WITHDRAW_WIRE_BYTE, 20, 1))
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "DB smoke bank withdraw")?;
    expect_bank_update(&frames, 20, 32_767, "DB smoke bank withdraw")?;

    stream
        .write_all(&bank_item_amount_packet(BANK_DEPOSIT_WIRE_BYTE, 20, 1))
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "DB smoke bank deposit")?;
    expect_bank_update(&frames, 20, 32_768, "DB smoke bank deposit")?;

    stream.write_all(&bank_close_packet()).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_BANK_CLOSE, "DB smoke bank close")
}

async fn expect_tcp_shop_movement(stream: &mut TcpStream) -> anyhow::Result<()> {
    stream.write_all(&command_packet("shop 2")).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    expect_varrock_sword_shop_stock(&frames, 66, 5, "DB smoke shop command")?;

    stream
        .write_all(&shop_item_amount_packet(SHOP_BUY_WIRE_BYTE, 66, 5, 1))
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "DB smoke shop buy")?;
    expect_inventory_payload(
        frame_payload(&frames, SEND_INVENTORY, "DB smoke shop buy inventory")?,
        6,
    )?;
    expect_varrock_sword_shop_stock(&frames, 66, 4, "DB smoke shop buy")?;

    stream
        .write_all(&shop_item_amount_packet(SHOP_SELL_WIRE_BYTE, 66, 4, 1))
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "DB smoke shop sell")?;
    expect_inventory_payload(
        frame_payload(&frames, SEND_INVENTORY, "DB smoke shop sell inventory")?,
        20,
    )?;
    expect_varrock_sword_shop_stock(&frames, 66, 5, "DB smoke shop sell")?;

    stream.write_all(&shop_close_packet()).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_BANK_CLOSE, "DB smoke shop close")
}

async fn expect_ws_bank_movement(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
) -> anyhow::Result<()> {
    ws.send(Message::Binary(
        bank_item_amount_packet(BANK_WITHDRAW_WIRE_BYTE, 20, 1).to_vec(),
    ))
    .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "WS DB smoke bank withdraw")?;
    expect_bank_update(&frames, 20, 32_767, "WS DB smoke bank withdraw")?;

    ws.send(Message::Binary(
        bank_item_amount_packet(BANK_DEPOSIT_WIRE_BYTE, 20, 1).to_vec(),
    ))
    .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "WS DB smoke bank deposit")?;
    expect_bank_update(&frames, 20, 32_768, "WS DB smoke bank deposit")?;

    ws.send(Message::Binary(bank_close_packet().to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_BANK_CLOSE, "WS DB smoke bank close")
}

async fn expect_ws_shop_movement(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
) -> anyhow::Result<()> {
    ws.send(Message::Binary(command_packet("shop 2").to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    expect_varrock_sword_shop_stock(&frames, 66, 5, "WS DB smoke shop command")?;

    ws.send(Message::Binary(
        shop_item_amount_packet(SHOP_BUY_WIRE_BYTE, 66, 5, 1).to_vec(),
    ))
    .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "WS DB smoke shop buy")?;
    expect_inventory_payload(
        frame_payload(&frames, SEND_INVENTORY, "WS DB smoke shop buy inventory")?,
        6,
    )?;
    expect_varrock_sword_shop_stock(&frames, 66, 4, "WS DB smoke shop buy")?;

    ws.send(Message::Binary(
        shop_item_amount_packet(SHOP_SELL_WIRE_BYTE, 66, 4, 1).to_vec(),
    ))
    .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "WS DB smoke shop sell")?;
    expect_inventory_payload(
        frame_payload(&frames, SEND_INVENTORY, "WS DB smoke shop sell inventory")?,
        20,
    )?;
    expect_varrock_sword_shop_stock(&frames, 66, 5, "WS DB smoke shop sell")?;

    ws.send(Message::Binary(shop_close_packet().to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_BANK_CLOSE, "WS DB smoke shop close")
}

async fn expect_tcp_server_configs(addr: SocketAddr) -> anyhow::Result<()> {
    let mut stream = TcpStream::connect(addr).await?;
    stream.write_all(&server_config_request_packet()).await?;
    let frames = read_tcp_frames_for(&mut stream, Duration::from_millis(900)).await?;
    expect_server_configs_frame(&frames)
}

async fn expect_tcp_bootstrap(stream: &mut TcpStream) -> anyhow::Result<Vec<ServerFrame>> {
    let mut buffer = BytesMut::with_capacity(4096);
    let mut seen = HashSet::new();
    let mut frames = Vec::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);

    loop {
        frames.extend(collect_decoded_frames(&mut buffer, &mut seen)?);
        if missing_required(&seen).is_empty() {
            return Ok(frames);
        }

        let now = tokio::time::Instant::now();
        if now >= deadline {
            anyhow::bail!(
                "bootstrap timeout; missing opcodes {:?}, saw {:?}",
                missing_required(&seen),
                sorted_seen(&seen)
            );
        }

        let read = tokio::time::timeout_at(deadline, stream.read_buf(&mut buffer)).await??;
        if read == 0 {
            anyhow::bail!(
                "connection closed during bootstrap; missing opcodes {:?}, saw {:?}",
                missing_required(&seen),
                sorted_seen(&seen)
            );
        }
    }
}

async fn read_tcp_frames_for(
    stream: &mut TcpStream,
    duration: Duration,
) -> anyhow::Result<Vec<ServerFrame>> {
    let mut buffer = BytesMut::with_capacity(4096);
    let mut seen = HashSet::new();
    let mut frames = Vec::new();
    let deadline = tokio::time::Instant::now() + duration;

    loop {
        frames.extend(collect_decoded_frames(&mut buffer, &mut seen)?);
        if tokio::time::Instant::now() >= deadline {
            return Ok(frames);
        }

        match tokio::time::timeout_at(deadline, stream.read_buf(&mut buffer)).await {
            Ok(Ok(0)) => return Ok(frames),
            Ok(Ok(_)) => {}
            Ok(Err(e)) => return Err(e.into()),
            Err(_) => return Ok(frames),
        }
    }
}

async fn read_ws_frames_for(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
    duration: Duration,
) -> anyhow::Result<Vec<ServerFrame>> {
    let mut buffer = BytesMut::with_capacity(4096);
    let mut seen = HashSet::new();
    let mut frames = Vec::new();
    let deadline = tokio::time::Instant::now() + duration;

    loop {
        frames.extend(collect_decoded_frames(&mut buffer, &mut seen)?);
        if tokio::time::Instant::now() >= deadline {
            return Ok(frames);
        }

        match tokio::time::timeout_at(deadline, ws.next()).await {
            Ok(Some(Ok(Message::Binary(bytes)))) => buffer.extend_from_slice(&bytes),
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) => return Ok(frames),
            Ok(Some(Ok(_))) => {}
            Ok(Some(Err(e))) => return Err(e.into()),
            Err(_) => return Ok(frames),
        }
    }
}

async fn expect_tcp_playable_actions(stream: &mut TcpStream) -> anyhow::Result<()> {
    stream.write_all(&walk_one_tile_packet()).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(1_500)).await?;
    assert_frame_seen(&frames, SEND_PLAYER_COORDS, "walk")?;

    stream.write_all(&chat_packet("smoke")).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_UPDATE_PLAYERS, "chat")?;

    stream.write_all(&command_packet("online")).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_server_message_contains(&frames, "Players online:", "command online")?;

    stream.write_all(&command_packet("pos")).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_server_message_contains(&frames, "Position:", "command pos")?;

    stream.write_all(&combat_style_packet(1)).await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_frame_payload(&frames, SEND_COMBAT_STYLE, &[1], "combat style")?;

    stream
        .write_all(&prayer_toggle_packet(PRAYER_ACTIVATED_WIRE_BYTE, 0))
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_prayer_state(&frames, 0, true)?;

    stream
        .write_all(&prayer_toggle_packet(PRAYER_DEACTIVATED_WIRE_BYTE, 0))
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
    assert_prayer_state(&frames, 0, false)?;

    expect_tcp_pickup_inventory(stream).await?;

    stream
        .write_all(&drop_first_inventory_slot_packet())
        .await?;
    let frames = read_tcp_frames_for(stream, Duration::from_millis(1_500)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "item drop")?;
    assert_frame_seen(&frames, SEND_GROUND_ITEM_HANDLER, "item drop")?;

    Ok(())
}

async fn expect_ws_playable_actions(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
) -> anyhow::Result<()> {
    ws.send(Message::Binary(walk_one_tile_packet().to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(1_500)).await?;
    assert_frame_seen(&frames, SEND_PLAYER_COORDS, "WS walk")?;

    ws.send(Message::Binary(chat_packet("smoke").to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_seen(&frames, SEND_UPDATE_PLAYERS, "WS chat")?;

    ws.send(Message::Binary(command_packet("online").to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_server_message_contains(&frames, "Players online:", "WS command online")?;

    ws.send(Message::Binary(command_packet("pos").to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_server_message_contains(&frames, "Position:", "WS command pos")?;

    ws.send(Message::Binary(combat_style_packet(1).to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_frame_payload(&frames, SEND_COMBAT_STYLE, &[1], "WS combat style")?;

    ws.send(Message::Binary(
        prayer_toggle_packet(PRAYER_ACTIVATED_WIRE_BYTE, 0).to_vec(),
    ))
    .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_prayer_state(&frames, 0, true)?;

    ws.send(Message::Binary(
        prayer_toggle_packet(PRAYER_DEACTIVATED_WIRE_BYTE, 0).to_vec(),
    ))
    .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
    assert_prayer_state(&frames, 0, false)?;

    expect_ws_pickup_inventory(ws).await?;

    ws.send(Message::Binary(drop_first_inventory_slot_packet().to_vec()))
        .await?;
    let frames = read_ws_frames_for(ws, Duration::from_millis(1_500)).await?;
    assert_frame_seen(&frames, SEND_INVENTORY, "WS item drop")?;
    assert_frame_seen(&frames, SEND_GROUND_ITEM_HANDLER, "WS item drop")?;

    Ok(())
}

async fn expect_tcp_pickup_inventory(stream: &mut TcpStream) -> anyhow::Result<()> {
    let mut all_seen = Vec::new();
    for packet in playable_pickup_packets() {
        stream.write_all(&packet).await?;
        let frames = read_tcp_frames_for(stream, Duration::from_millis(900)).await?;
        if has_frame(&frames, SEND_INVENTORY) {
            return Ok(());
        }
        all_seen.extend(frames.into_iter().map(|f| f.opcode));
    }

    anyhow::bail!("ground item pickup did not receive opcode {SEND_INVENTORY}; saw {all_seen:?}")
}

async fn expect_tcp_logout_reconnect(
    mut stream: TcpStream,
    addr: SocketAddr,
    username: &str,
    password: &str,
    custom_rsa_login: bool,
) -> anyhow::Result<()> {
    stream.write_all(&logout_packet()).await?;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut discard = [0u8; 512];
    loop {
        match tokio::time::timeout_at(deadline, stream.read(&mut discard)).await {
            Ok(Ok(0)) => break,
            Ok(Ok(_)) => continue,
            Ok(Err(e)) => return Err(e.into()),
            Err(_) => anyhow::bail!("logout timed out waiting for disconnect"),
        }
    }
    drop(stream);

    let mut reconnect = TcpStream::connect(addr).await?;
    reconnect
        .write_all(&reconnect_login_packet(
            username,
            password,
            custom_rsa_login,
        ))
        .await?;
    let mut resp = [0u8; 1];
    reconnect.read_exact(&mut resp).await?;
    if resp[0] != 0 {
        anyhow::bail!("reconnect rejected: code {}", resp[0]);
    }
    expect_tcp_bootstrap(&mut reconnect).await.map(|_| ())
}

async fn expect_tcp_db_reconnect(
    mut stream: TcpStream,
    addr: SocketAddr,
    username: &str,
    password: &str,
    custom_rsa_login: bool,
    db_sqlite: Option<&str>,
) -> anyhow::Result<()> {
    stream.write_all(&walk_one_tile_packet()).await?;
    let frames = read_tcp_frames_for(&mut stream, Duration::from_millis(1_500)).await?;
    assert_frame_seen(&frames, SEND_PLAYER_COORDS, "DB smoke walk")?;

    stream.write_all(&appearance_change_packet()).await?;
    stream.write_all(&combat_style_packet(1)).await?;
    let frames = read_tcp_frames_for(&mut stream, Duration::from_millis(900)).await?;
    assert_frame_payload(&frames, SEND_COMBAT_STYLE, &[1], "DB smoke combat style")?;

    stream.write_all(&game_setting_packet(0, 0)).await?;
    stream.write_all(&game_setting_packet(2, 0)).await?;
    stream.write_all(&game_setting_packet(3, 0)).await?;
    let frames = read_tcp_frames_for(&mut stream, Duration::from_millis(900)).await?;
    assert_frame_payload(
        &frames,
        SEND_GAME_SETTINGS,
        &[0, 0, 0],
        "DB smoke game settings",
    )?;

    stream
        .write_all(&privacy_settings_packet(true, false, true, false))
        .await?;

    stream.write_all(&object_command_packet(124, 647)).await?;
    let frames = read_tcp_frames_for(&mut stream, Duration::from_millis(900)).await?;
    expect_bank_open(&frames, "DB smoke bank booth object command")?;
    expect_tcp_bank_movement(&mut stream).await?;
    expect_tcp_shop_movement(&mut stream).await?;

    stream.write_all(&logout_packet()).await?;
    drain_tcp_until_close(&mut stream).await?;
    assert_db_smoke_after_logout(db_sqlite, username).await?;
    drop(stream);

    let mut reconnect = TcpStream::connect(addr).await?;
    reconnect
        .write_all(&reconnect_login_packet(
            username,
            password,
            custom_rsa_login,
        ))
        .await?;
    let mut resp = [0u8; 1];
    reconnect.read_exact(&mut resp).await?;
    if resp[0] != 0 {
        anyhow::bail!("DB reconnect rejected: code {}", resp[0]);
    }
    let frames = expect_tcp_bootstrap(&mut reconnect).await?;
    expect_bootstrap_persisted_state(&frames, 123, 647, &[0, 0, 0], 20)?;
    reconnect.write_all(&npc_command_packet(5)).await?;
    let frames = read_tcp_frames_for(&mut reconnect, Duration::from_millis(900)).await?;
    expect_bank_open(&frames, "DB reconnect banker NPC command")
}

async fn drain_tcp_until_close(stream: &mut TcpStream) -> anyhow::Result<()> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    let mut discard = [0u8; 512];
    loop {
        match tokio::time::timeout_at(deadline, stream.read(&mut discard)).await {
            Ok(Ok(0)) => return Ok(()),
            Ok(Ok(_)) => continue,
            Ok(Err(e)) => return Err(e.into()),
            Err(_) => anyhow::bail!("logout timed out waiting for disconnect"),
        }
    }
}

async fn expect_ws_pickup_inventory(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
) -> anyhow::Result<()> {
    let mut all_seen = Vec::new();
    for packet in playable_pickup_packets() {
        ws.send(Message::Binary(packet.to_vec())).await?;
        let frames = read_ws_frames_for(ws, Duration::from_millis(900)).await?;
        if has_frame(&frames, SEND_INVENTORY) {
            return Ok(());
        }
        all_seen.extend(frames.into_iter().map(|f| f.opcode));
    }

    anyhow::bail!("WS ground item pickup did not receive opcode {SEND_INVENTORY}; saw {all_seen:?}")
}

async fn expect_ws_logout_reconnect(
    mut ws: tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
    addr: SocketAddr,
    username: &str,
    password: &str,
    custom_rsa_login: bool,
) -> anyhow::Result<()> {
    ws.send(Message::Binary(confirm_logout_packet().to_vec()))
        .await?;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    loop {
        match tokio::time::timeout_at(deadline, ws.next()).await {
            Ok(None) | Ok(Some(Ok(Message::Close(_)))) => break,
            Ok(Some(Ok(_))) => continue,
            Ok(Some(Err(_))) => break,
            Err(_) => anyhow::bail!("WS logout timed out waiting for close"),
        }
    }

    let url = format!("ws://{}/", addr);
    let (mut reconnect, _) = connect_async(&url).await?;
    reconnect
        .send(Message::Binary(
            reconnect_login_packet(username, password, custom_rsa_login).to_vec(),
        ))
        .await?;
    let resp = reconnect
        .next()
        .await
        .ok_or_else(|| anyhow::anyhow!("no reconnect response"))??;
    validate_ws_login_response(resp)?;
    expect_ws_bootstrap(&mut reconnect).await.map(|_| ())
}

async fn expect_ws_db_reconnect(
    mut ws: tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
    addr: SocketAddr,
    username: &str,
    password: &str,
    custom_rsa_login: bool,
    db_sqlite: Option<&str>,
) -> anyhow::Result<()> {
    ws.send(Message::Binary(walk_one_tile_packet().to_vec()))
        .await?;
    let frames = read_ws_frames_for(&mut ws, Duration::from_millis(1_500)).await?;
    assert_frame_seen(&frames, SEND_PLAYER_COORDS, "WS DB smoke walk")?;

    ws.send(Message::Binary(appearance_change_packet().to_vec()))
        .await?;
    ws.send(Message::Binary(combat_style_packet(1).to_vec()))
        .await?;
    let frames = read_ws_frames_for(&mut ws, Duration::from_millis(900)).await?;
    assert_frame_payload(&frames, SEND_COMBAT_STYLE, &[1], "WS DB smoke combat style")?;

    ws.send(Message::Binary(game_setting_packet(0, 0).to_vec()))
        .await?;
    ws.send(Message::Binary(game_setting_packet(2, 0).to_vec()))
        .await?;
    ws.send(Message::Binary(game_setting_packet(3, 0).to_vec()))
        .await?;
    let frames = read_ws_frames_for(&mut ws, Duration::from_millis(900)).await?;
    assert_frame_payload(
        &frames,
        SEND_GAME_SETTINGS,
        &[0, 0, 0],
        "WS DB smoke game settings",
    )?;

    ws.send(Message::Binary(
        privacy_settings_packet(true, false, true, false).to_vec(),
    ))
    .await?;

    ws.send(Message::Binary(object_command_packet(124, 647).to_vec()))
        .await?;
    let frames = read_ws_frames_for(&mut ws, Duration::from_millis(900)).await?;
    expect_bank_open(&frames, "WS DB smoke bank booth object command")?;
    expect_ws_bank_movement(&mut ws).await?;
    expect_ws_shop_movement(&mut ws).await?;

    ws.send(Message::Binary(confirm_logout_packet().to_vec()))
        .await?;
    drain_ws_until_close(&mut ws).await?;
    assert_db_smoke_after_logout(db_sqlite, username).await?;

    let url = format!("ws://{}/", addr);
    let (mut reconnect, _) = connect_async(&url).await?;
    reconnect
        .send(Message::Binary(
            reconnect_login_packet(username, password, custom_rsa_login).to_vec(),
        ))
        .await?;
    let resp = reconnect
        .next()
        .await
        .ok_or_else(|| anyhow::anyhow!("no DB reconnect response"))??;
    validate_ws_login_response(resp)?;
    let frames = expect_ws_bootstrap(&mut reconnect).await?;
    expect_bootstrap_persisted_state(&frames, 123, 647, &[0, 0, 0], 20)?;
    reconnect
        .send(Message::Binary(npc_command_packet(5).to_vec()))
        .await?;
    let frames = read_ws_frames_for(&mut reconnect, Duration::from_millis(900)).await?;
    expect_bank_open(&frames, "WS DB reconnect banker NPC command")
}

async fn drain_ws_until_close(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
) -> anyhow::Result<()> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);
    loop {
        match tokio::time::timeout_at(deadline, ws.next()).await {
            Ok(None) | Ok(Some(Ok(Message::Close(_)))) => return Ok(()),
            Ok(Some(Ok(_))) => continue,
            Ok(Some(Err(_))) => return Ok(()),
            Err(_) => anyhow::bail!("WS logout timed out waiting for close"),
        }
    }
}

async fn expect_ws_server_configs(url: &str) -> anyhow::Result<()> {
    let (mut ws, _) = connect_async(url).await?;
    ws.send(Message::Binary(server_config_request_packet().to_vec()))
        .await?;
    let frames = read_ws_frames_for(&mut ws, Duration::from_millis(900)).await?;
    expect_server_configs_frame(&frames)
}

async fn expect_ws_bootstrap(
    ws: &mut tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<TcpStream>>,
) -> anyhow::Result<Vec<ServerFrame>> {
    let mut buffer = BytesMut::with_capacity(4096);
    let mut seen = HashSet::new();
    let mut frames = Vec::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(3);

    loop {
        frames.extend(collect_decoded_frames(&mut buffer, &mut seen)?);
        if missing_required(&seen).is_empty() {
            return Ok(frames);
        }

        let now = tokio::time::Instant::now();
        if now >= deadline {
            anyhow::bail!(
                "WS bootstrap timeout; missing opcodes {:?}, saw {:?}",
                missing_required(&seen),
                sorted_seen(&seen)
            );
        }

        let msg = tokio::time::timeout_at(deadline, ws.next())
            .await?
            .ok_or_else(|| anyhow::anyhow!("WS closed during bootstrap"))??;
        match msg {
            Message::Binary(bytes) => buffer.extend_from_slice(&bytes),
            Message::Close(_) => anyhow::bail!("WS closed during bootstrap"),
            _ => {}
        }
    }
}

fn validate_ws_login_response(msg: Message) -> anyhow::Result<()> {
    match msg {
        Message::Binary(bytes) if bytes.as_ref() == [0] => Ok(()),
        Message::Binary(bytes) => {
            anyhow::bail!("login rejected or framed incorrectly: {:?}", bytes)
        }
        other => anyhow::bail!("expected binary login response, got {other:?}"),
    }
}

fn sorted_seen(seen: &HashSet<u8>) -> Vec<u8> {
    let mut seen: Vec<u8> = seen.iter().copied().collect();
    seen.sort_unstable();
    seen
}

async fn sqlite_pool(path: &str) -> anyhow::Result<sqlx::Pool<sqlx::Sqlite>> {
    let url = format!("sqlite://{path}?mode=rwc");
    Ok(SqlitePoolOptions::new()
        .max_connections(1)
        .connect(&url)
        .await?)
}

async fn prepare_db_smoke(args: &ParsedArgs) -> anyhow::Result<()> {
    let path = args
        .db_sqlite
        .as_deref()
        .ok_or_else(|| anyhow::anyhow!("--expect-db-reconnect requires --db-sqlite <path>"))?;
    let username = args
        .username
        .as_deref()
        .ok_or_else(|| anyhow::anyhow!("--expect-db-reconnect requires --username <name>"))?;
    let password = args.password.as_deref().unwrap_or_default();
    let pool = sqlite_pool(path).await?;

    init_db_smoke_schema(&pool).await?;
    let hash = bcrypt::hash(password, 4)?;

    sqlx::query("DELETE FROM player_inventory WHERE player_id IN (SELECT id FROM players WHERE username = ?)")
        .bind(username)
        .execute(&pool)
        .await?;
    sqlx::query(
        "DELETE FROM player_bank WHERE player_id IN (SELECT id FROM players WHERE username = ?)",
    )
    .bind(username)
    .execute(&pool)
    .await?;
    sqlx::query(
        "DELETE FROM player_skills WHERE player_id IN (SELECT id FROM players WHERE username = ?)",
    )
    .bind(username)
    .execute(&pool)
    .await?;
    sqlx::query(
        "DELETE FROM player_settings WHERE player_id IN (SELECT id FROM players WHERE username = ?)",
    )
    .bind(username)
    .execute(&pool)
    .await?;
    sqlx::query("DELETE FROM players WHERE username = ?")
        .bind(username)
        .execute(&pool)
        .await?;

    let result = sqlx::query(
        r#"
        INSERT INTO players (
            username, password_hash, creation_date, group_id, combat_style, x, y,
            appearance_hair, appearance_top, appearance_bottom, appearance_skin,
            appearance_head, appearance_body, male
        ) VALUES (?, ?, 1, 10, 0, 122, 647, 2, 8, 14, 0, 1, 2, TRUE)
        "#,
    )
    .bind(username)
    .bind(hash)
    .execute(&pool)
    .await?;
    let player_id = result.last_insert_rowid();

    sqlx::query(
        r#"
        INSERT INTO player_skills (
            player_id, attack_xp, defense_xp, strength_xp, hits_xp, ranged_xp,
            prayer_xp, magic_xp, attack_cur, defense_cur, strength_cur, hits_cur,
            ranged_cur, prayer_cur, magic_cur
        ) VALUES (?, 388, 512, 650, 1154, 801, 969, 1154, 4, 5, 6, 10, 7, 8, 9)
        "#,
    )
    .bind(player_id)
    .execute(&pool)
    .await?;

    sqlx::query(
        "INSERT INTO player_inventory (player_id, slot, item_id, amount, equipped, noted) VALUES (?, 3, 10, 30, FALSE, FALSE)",
    )
    .bind(player_id)
    .execute(&pool)
    .await?;
    sqlx::query(
        "INSERT INTO player_inventory (player_id, slot, item_id, amount, equipped, noted) VALUES (?, 7, 20, 1, TRUE, TRUE)",
    )
    .bind(player_id)
    .execute(&pool)
    .await?;
    sqlx::query("INSERT INTO player_bank (player_id, slot, item_id, amount) VALUES (?, 0, 10, 5)")
        .bind(player_id)
        .execute(&pool)
        .await?;
    sqlx::query(
        "INSERT INTO player_bank (player_id, slot, item_id, amount) VALUES (?, 1, 20, 32768)",
    )
    .bind(player_id)
    .execute(&pool)
    .await?;

    sqlx::query(
        "INSERT INTO player_settings (player_id, camera_auto, one_mouse_button, sound_off, block_chat, block_private, block_trade, block_duel) VALUES (?, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)",
    )
    .bind(player_id)
    .execute(&pool)
    .await?;

    pool.close().await;
    Ok(())
}

async fn init_db_smoke_schema(pool: &sqlx::Pool<sqlx::Sqlite>) -> anyhow::Result<()> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS players (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username VARCHAR(12) NOT NULL UNIQUE,
            password_hash VARCHAR(255) NOT NULL,
            email VARCHAR(255),
            creation_date BIGINT NOT NULL,
            last_login BIGINT,
            login_ip VARCHAR(45),
            banned BOOLEAN DEFAULT FALSE,
            muted BOOLEAN DEFAULT FALSE,
            group_id INTEGER DEFAULT 10,
            combat_style INTEGER DEFAULT 0,
            x INTEGER DEFAULT 122,
            y INTEGER DEFAULT 647,
            fatigue INTEGER DEFAULT 0,
            appearance_hair INTEGER DEFAULT 2,
            appearance_top INTEGER DEFAULT 8,
            appearance_bottom INTEGER DEFAULT 14,
            appearance_skin INTEGER DEFAULT 0,
            appearance_head INTEGER DEFAULT 1,
            appearance_body INTEGER DEFAULT 2,
            male BOOLEAN DEFAULT TRUE,
            skull INTEGER DEFAULT 0,
            online BOOLEAN DEFAULT FALSE
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS player_skills (
            player_id INTEGER PRIMARY KEY,
            attack_xp INTEGER DEFAULT 0,
            defense_xp INTEGER DEFAULT 0,
            strength_xp INTEGER DEFAULT 0,
            hits_xp INTEGER DEFAULT 1154,
            ranged_xp INTEGER DEFAULT 0,
            prayer_xp INTEGER DEFAULT 0,
            magic_xp INTEGER DEFAULT 0,
            cooking_xp INTEGER DEFAULT 0,
            woodcutting_xp INTEGER DEFAULT 0,
            fletching_xp INTEGER DEFAULT 0,
            fishing_xp INTEGER DEFAULT 0,
            firemaking_xp INTEGER DEFAULT 0,
            crafting_xp INTEGER DEFAULT 0,
            smithing_xp INTEGER DEFAULT 0,
            mining_xp INTEGER DEFAULT 0,
            herblaw_xp INTEGER DEFAULT 0,
            agility_xp INTEGER DEFAULT 0,
            thieving_xp INTEGER DEFAULT 0,
            attack_cur INTEGER DEFAULT 1,
            defense_cur INTEGER DEFAULT 1,
            strength_cur INTEGER DEFAULT 1,
            hits_cur INTEGER DEFAULT 10,
            ranged_cur INTEGER DEFAULT 1,
            prayer_cur INTEGER DEFAULT 1,
            magic_cur INTEGER DEFAULT 1
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS player_inventory (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            slot INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            amount INTEGER DEFAULT 1,
            equipped BOOLEAN DEFAULT FALSE,
            noted BOOLEAN DEFAULT FALSE
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS player_bank (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            player_id INTEGER NOT NULL,
            slot INTEGER NOT NULL,
            item_id INTEGER NOT NULL,
            amount INTEGER DEFAULT 1
        )
        "#,
    )
    .execute(pool)
    .await?;
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS player_settings (
            player_id INTEGER PRIMARY KEY,
            camera_auto BOOLEAN DEFAULT TRUE,
            one_mouse_button BOOLEAN DEFAULT FALSE,
            sound_off BOOLEAN DEFAULT FALSE,
            block_chat BOOLEAN DEFAULT FALSE,
            block_private BOOLEAN DEFAULT FALSE,
            block_trade BOOLEAN DEFAULT FALSE,
            block_duel BOOLEAN DEFAULT FALSE
        )
        "#,
    )
    .execute(pool)
    .await?;
    Ok(())
}

async fn assert_db_smoke_after_logout(
    db_sqlite: Option<&str>,
    username: &str,
) -> anyhow::Result<()> {
    let path = db_sqlite
        .ok_or_else(|| anyhow::anyhow!("--expect-db-reconnect requires --db-sqlite <path>"))?;
    let pool = sqlite_pool(path).await?;

    let player = sqlx::query(
        "SELECT id, x, y, appearance_hair, appearance_top, appearance_bottom, appearance_skin, appearance_head, appearance_body, male, combat_style FROM players WHERE username = ?",
    )
    .bind(username)
    .fetch_one(&pool)
    .await?;
    let player_id: i64 = player.get("id");
    let x: i32 = player.get("x");
    let y: i32 = player.get("y");
    if (x, y) != (123, 647) {
        anyhow::bail!("expected DB position (123,647), got ({x},{y})");
    }
    let expected = [
        ("appearance_hair", 5),
        ("appearance_top", 6),
        ("appearance_bottom", 7),
        ("appearance_skin", 1),
        ("appearance_head", 4),
        ("appearance_body", 5),
        ("combat_style", 1),
    ];
    for (column, value) in expected {
        let actual: i32 = player.get(column);
        if actual != value {
            anyhow::bail!("expected {column}={value}, got {actual}");
        }
    }
    let male: bool = player.get("male");
    if !male {
        anyhow::bail!("expected male appearance flag to persist");
    }

    let skills = sqlx::query(
        "SELECT attack_cur, defense_cur, strength_cur FROM player_skills WHERE player_id = ?",
    )
    .bind(player_id)
    .fetch_one(&pool)
    .await?;
    if skills.get::<i32, _>("attack_cur") != 4
        || skills.get::<i32, _>("defense_cur") != 5
        || skills.get::<i32, _>("strength_cur") != 6
    {
        anyhow::bail!("persisted skills changed unexpectedly");
    }

    let inventory = sqlx::query(
        "SELECT slot, item_id, amount, equipped, noted FROM player_inventory WHERE player_id = ? ORDER BY slot",
    )
    .bind(player_id)
    .fetch_all(&pool)
    .await?;
    if inventory.len() != 2 {
        anyhow::bail!(
            "expected 2 persisted inventory rows, got {}",
            inventory.len()
        );
    }
    let first = &inventory[0];
    let second = &inventory[1];
    if first.get::<i32, _>("slot") != 3
        || first.get::<i32, _>("item_id") != 10
        || first.get::<i32, _>("amount") != 20
        || first.get::<bool, _>("equipped")
        || first.get::<bool, _>("noted")
    {
        anyhow::bail!("first inventory row did not persist as seeded");
    }
    if second.get::<i32, _>("slot") != 7
        || second.get::<i32, _>("item_id") != 20
        || second.get::<i32, _>("amount") != 1
        || !second.get::<bool, _>("equipped")
        || !second.get::<bool, _>("noted")
    {
        anyhow::bail!("second inventory row did not persist as seeded");
    }

    let bank = sqlx::query(
        "SELECT slot, item_id, amount FROM player_bank WHERE player_id = ? ORDER BY slot",
    )
    .bind(player_id)
    .fetch_all(&pool)
    .await?;
    if bank.len() != 2 {
        anyhow::bail!("expected 2 persisted bank rows, got {}", bank.len());
    }
    if bank[0].get::<i32, _>("slot") != 0
        || bank[0].get::<i32, _>("item_id") != 10
        || bank[0].get::<i32, _>("amount") != 5
    {
        anyhow::bail!("first bank row did not persist as seeded");
    }
    if bank[1].get::<i32, _>("slot") != 1
        || bank[1].get::<i32, _>("item_id") != 20
        || bank[1].get::<i32, _>("amount") != 32_768
    {
        anyhow::bail!("second bank row did not persist as seeded");
    }

    let settings = sqlx::query(
        "SELECT camera_auto, one_mouse_button, sound_off, block_chat, block_private, block_trade, block_duel FROM player_settings WHERE player_id = ?",
    )
    .bind(player_id)
    .fetch_one(&pool)
    .await?;
    if settings.get::<bool, _>("camera_auto")
        || settings.get::<bool, _>("one_mouse_button")
        || settings.get::<bool, _>("sound_off")
        || !settings.get::<bool, _>("block_chat")
        || settings.get::<bool, _>("block_private")
        || !settings.get::<bool, _>("block_trade")
        || settings.get::<bool, _>("block_duel")
    {
        anyhow::bail!("settings row did not persist expected game/privacy values");
    }

    pool.close().await;
    Ok(())
}

/// Minimal arg parser (no clap dependency at runtime).
struct ParsedArgs {
    mode: String,
    addr: SocketAddr,
    connections: usize,
    ticks: usize,
    expect_bootstrap: bool,
    expect_playable: bool,
    expect_reconnect: bool,
    expect_db_reconnect: bool,
    custom_rsa_login: bool,
    username: Option<String>,
    password: Option<String>,
    db_sqlite: Option<String>,
}

fn parse_args() -> ParsedArgs {
    let args: Vec<String> = std::env::args().collect();
    let mut mode = "ws".to_string();
    let mut addr: SocketAddr = "127.0.0.1:43494".parse().unwrap();
    let mut connections = 100usize;
    let mut ticks = 50usize;
    let mut expect_bootstrap = false;
    let mut expect_playable = false;
    let mut expect_reconnect = false;
    let mut expect_db_reconnect = false;
    let mut custom_rsa_login = false;
    let mut username = None;
    let mut password = None;
    let mut db_sqlite = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--mode" => {
                i += 1;
                mode = args[i].clone();
            }
            "--addr" => {
                i += 1;
                addr = args[i].parse().expect("invalid addr");
            }
            "--connections" => {
                i += 1;
                connections = args[i].parse().expect("invalid connections");
            }
            "--ticks" => {
                i += 1;
                ticks = args[i].parse().expect("invalid ticks");
            }
            "--expect-bootstrap" => {
                expect_bootstrap = true;
            }
            "--expect-playable" => {
                expect_playable = true;
            }
            "--expect-reconnect" => {
                expect_reconnect = true;
            }
            "--expect-db-reconnect" => {
                expect_db_reconnect = true;
            }
            "--custom-rsa-login" => {
                custom_rsa_login = true;
            }
            "--username" => {
                i += 1;
                username = Some(args[i].clone());
            }
            "--password" => {
                i += 1;
                password = Some(args[i].clone());
            }
            "--db-sqlite" => {
                i += 1;
                db_sqlite = Some(args[i].clone());
            }
            _ => {}
        }
        i += 1;
    }

    // Default port based on mode.
    if args.iter().all(|a| a != "--addr") {
        addr = if mode == "tcp" {
            "127.0.0.1:43594".parse().unwrap()
        } else {
            "127.0.0.1:43494".parse().unwrap()
        };
    }

    ParsedArgs {
        mode,
        addr,
        connections,
        ticks,
        expect_bootstrap,
        expect_playable,
        expect_reconnect,
        expect_db_reconnect,
        custom_rsa_login,
        username,
        password,
        db_sqlite,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_server_frame_with_length_including_header() {
        let mut buffer = BytesMut::from(&[0, 5, SEND_SERVER_MESSAGE, b'O', b'K'][..]);
        let mut seen = HashSet::new();
        let frames = collect_decoded_frames(&mut buffer, &mut seen).unwrap();

        assert_eq!(
            frames,
            vec![ServerFrame {
                opcode: SEND_SERVER_MESSAGE,
                payload_len: 2,
                payload: vec![b'O', b'K'],
            }]
        );
        assert!(seen.contains(&SEND_SERVER_MESSAGE));
        assert!(buffer.is_empty());
    }

    #[test]
    fn waits_for_incomplete_server_frame() {
        let mut buffer = BytesMut::from(&[0, 5, SEND_SERVER_MESSAGE][..]);

        assert!(try_decode_server_frame(&mut buffer).unwrap().is_none());
        assert_eq!(buffer.as_ref(), &[0, 5, SEND_SERVER_MESSAGE]);
    }

    #[test]
    fn detects_missing_bootstrap_opcodes() {
        let seen = HashSet::from([SEND_WORLD_INFO, SEND_STATS]);
        let missing = missing_required(&seen);

        assert!(missing.contains(&SEND_PLAYER_COORDS));
        assert!(missing.contains(&SEND_NPC_COORDS));
    }

    #[test]
    fn builds_v177_playable_action_packets() {
        assert_eq!(server_config_request_packet().as_ref(), &[0, 1, 19]);
        assert_eq!(
            walk_one_tile_packet().as_ref(),
            &[0, 7, 194, 0, 122, 2, 135, 1, 0]
        );
        assert_eq!(chat_packet("hi").as_ref(), &[0, 4, 3, b'h', b'i', 0]);
        assert_eq!(
            command_packet("pos").as_ref(),
            &[0, 5, 7, b'p', b'o', b's', 0]
        );
        assert_eq!(
            bank_item_amount_packet(BANK_WITHDRAW_WIRE_BYTE, 20, 1).as_ref(),
            &[0, 7, 206, 0, 20, 0, 0, 0, 1]
        );
        assert_eq!(bank_close_packet().as_ref(), &[0, 1, 207]);
        assert_eq!(
            shop_item_amount_packet(SHOP_BUY_WIRE_BYTE, 66, 5, 1).as_ref(),
            &[0, 7, 217, 0, 66, 0, 5, 0, 1]
        );
        assert_eq!(
            shop_item_amount_packet(SHOP_SELL_WIRE_BYTE, 66, 4, 1).as_ref(),
            &[0, 7, 216, 0, 66, 0, 4, 0, 1]
        );
        assert_eq!(shop_close_packet().as_ref(), &[0, 1, 218]);
        assert_eq!(npc_command_packet(5).as_ref(), &[0, 3, 195, 0, 5]);
        assert_eq!(
            object_command_packet(124, 647).as_ref(),
            &[0, 5, 242, 0, 124, 2, 135]
        );
        assert_eq!(game_setting_packet(2, 1).as_ref(), &[0, 3, 213, 2, 1]);
        assert_eq!(combat_style_packet(1).as_ref(), &[0, 2, 231, 1]);
        assert_eq!(
            prayer_toggle_packet(PRAYER_ACTIVATED_WIRE_BYTE, 0).as_ref(),
            &[0, 2, 212, 0]
        );
        assert_eq!(
            prayer_toggle_packet(PRAYER_DEACTIVATED_WIRE_BYTE, 0).as_ref(),
            &[0, 2, 211, 0]
        );
        assert_eq!(
            privacy_settings_packet(true, false, true, false).as_ref(),
            &[0, 5, 31, 1, 0, 1, 0]
        );
        assert_eq!(logout_packet().as_ref(), &[0, 1, 6]);
        assert_eq!(confirm_logout_packet().as_ref(), &[0, 1, 1]);
        assert_eq!(
            reconnect_login_packet("a", "", false).as_ref(),
            &[0, 9, 19, 1, 0, 0, 0, 177, b'a', 0, 0]
        );
        assert_eq!(
            take_ground_item_packet(123, 648, 10).as_ref(),
            &[0, 7, 252, 0, 123, 2, 136, 0, 10]
        );
        assert_eq!(
            drop_first_inventory_slot_packet().as_ref(),
            &[0, 7, 251, 0, 0, 0, 0, 0, 1]
        );
    }

    #[test]
    fn builds_custom_rsa_login_packet_shape() {
        let login = custom_rsa_login_packet("alice", "secret", false);
        let bytes = login.as_ref();
        let length = u16::from_be_bytes([bytes[0], bytes[1]]) as usize;

        assert_eq!(bytes.len(), length + 2);
        assert_eq!(bytes[2], LOGIN_WIRE_BYTE);
        assert_eq!(bytes[3], 0);
        assert_eq!(&bytes[4..8], &10010u32.to_be_bytes());
        assert_eq!(&bytes[8..14], b"alice\n");
        assert_eq!(bytes[14], 1);

        let password_len = u16::from_be_bytes([bytes[15], bytes[16]]) as usize;
        assert!(password_len > 0);
        let details_offset = 17 + password_len;
        let details_len =
            u16::from_be_bytes([bytes[details_offset], bytes[details_offset + 1]]) as usize;
        assert!(details_len > 0);
        assert_eq!(bytes.len(), details_offset + 2 + details_len + 8);

        let reconnect = custom_rsa_login_packet("alice", "secret", true);
        assert_eq!(reconnect.as_ref()[2], LOGIN_WIRE_BYTE);
        assert_eq!(reconnect.as_ref()[3], 1);
    }

    #[test]
    fn decodes_java_bank_open_payload() {
        let payload = [2, 192, 0, 10, 0, 5, 0, 20, 0x80, 0x00, 0x80, 0x00];

        expect_bank_open_payload(&payload).unwrap();
    }

    #[test]
    fn decodes_java_shop_open_payload() {
        let payload = [
            2, 0, 40, 100, 2, // count, general flag, sell/buy/price modifiers
            0, 66, 0, 9, 0, 10, // bronze sword current/base stock
            0, 67, 0, 5, 0, 5,
        ];

        expect_shop_stock_payload(&payload, 66, 9).unwrap();
        assert!(expect_shop_stock_payload(&payload, 66, 10).is_err());
    }

    #[test]
    fn reports_missing_action_frame() {
        let frames = vec![ServerFrame {
            opcode: SEND_PLAYER_COORDS,
            payload_len: 1,
            payload: vec![0],
        }];

        assert!(assert_frame_seen(&frames, SEND_PLAYER_COORDS, "walk").is_ok());
        assert!(assert_frame_seen(&frames, SEND_INVENTORY, "pickup").is_err());
    }
}
