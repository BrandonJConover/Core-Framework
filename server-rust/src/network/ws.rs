//! WebSocket transport for the web client.
//!
//! Caddy fronts the public deployment by reverse-proxying `/rsc-ws` and
//! `/rsc21-ws` to this port (default 43494). Each binary WS message carries a
//! single RSC packet wrapped in the same framing as the TCP path:
//!   `[u16 length, u8 opcode, payload...]` — length is the body byte count
//!   (opcode + payload), excluding the length field itself.
//!
//! Outgoing packets use the existing TCP encoder convention (length value
//! INCLUDES the 2 length bytes). The mismatch is intentional and historical;
//! the rsc-c WASM client and the Java reference server agree on it.

use anyhow::Result;
use bytes::{Bytes, BytesMut};
use futures_util::{SinkExt, StreamExt};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, RwLock};
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, error, info, warn};

use crate::game::server::{HandleResult, ServerState};
use crate::protocol::Packet;
use crate::session;

/// Bind a WebSocket listener and accept incoming WS connections.
///
/// The handshake is performed by `tokio-tungstenite` regardless of the URI
/// path — Caddy strips the `/rsc-ws` or `/rsc21-ws` prefix before reverse-
/// proxying, so this listener sees a bare `/` upgrade and doesn't need to
/// inspect the request path.
pub async fn start_ws_server(
    addr: SocketAddr,
    server_state: Arc<RwLock<ServerState>>,
) -> Result<()> {
    let listener = TcpListener::bind(addr).await?;
    info!("WebSocket server listening on {}", addr);

    loop {
        match listener.accept().await {
            Ok((socket, peer)) => {
                let state = server_state.clone();
                tokio::spawn(async move {
                    if let Err(e) = handle_ws_connection(socket, peer, state).await {
                        debug!("WS connection from {} ended: {}", peer, e);
                    }
                });
            }
            Err(e) => {
                error!("WS accept error: {}", e);
            }
        }
    }
}

/// Handle a single WebSocket connection: perform the upgrade, register a
/// session, then pump frames in both directions until the client closes or
/// the handler asks us to disconnect.
async fn handle_ws_connection(
    stream: TcpStream,
    peer: SocketAddr,
    server_state: Arc<RwLock<ServerState>>,
) -> Result<()> {
    let ws_stream = tokio_tungstenite::accept_async(stream).await?;
    info!("WebSocket upgrade from {}", peer);

    // Outgoing channel: ServerState pushes Packets here, this task encodes
    // them as binary WS frames. 256 matches the TCP path's mpsc capacity.
    let (tx, mut rx) = mpsc::channel::<Packet>(256);

    let session_id = {
        let mut state = server_state.write().await;
        match state.sessions.create_session(peer, tx).await {
            Some(s) => {
                let r = s.read().await;
                r.id
            }
            None => {
                warn!("WS rejected from {} (session limit)", peer);
                return Ok(());
            }
        }
    };

    let (mut ws_tx, mut ws_rx) = ws_stream.split();
    let mut inbound_buffer = BytesMut::with_capacity(4096);

    // Outgoing pump: drain the mpsc and forward each Packet as one WS binary
    // message. Spawned so the inbound loop never blocks waiting for sends.
    let writer = tokio::spawn(async move {
        while let Some(packet) = rx.recv().await {
            let bytes = encode_outgoing(&packet);
            if let Err(e) = ws_tx.send(Message::Binary(bytes.into())).await {
                debug!("WS send failed: {}", e);
                break;
            }
        }
    });

    // Inbound loop: every binary WS frame is appended to a small accumulator
    // and parsed greedily — if a client ever sends two RSC packets in one
    // WS frame (or splits one across frames), we still recover.
    let result: Result<()> = async {
        while let Some(msg) = ws_rx.next().await {
            let msg = msg?;
            match msg {
                Message::Binary(data) => {
                    inbound_buffer.extend_from_slice(&data);
                    while let Some(packet) = try_decode_ws_packet(&mut inbound_buffer) {
                        let result = {
                            let mut state = server_state.write().await;
                            state.handle_packet(session_id, packet).await
                        };
                        if matches!(result, HandleResult::Disconnect) {
                            info!("WS session {} disconnecting (handler request)", session_id);
                            return Ok(());
                        }
                    }
                }
                Message::Close(_) => {
                    debug!("WS close frame from session {}", session_id);
                    break;
                }
                Message::Ping(p) => {
                    // tungstenite auto-pongs by default; nothing to do.
                    debug!("WS ping from session {} ({} bytes)", session_id, p.len());
                }
                Message::Text(_) | Message::Pong(_) | Message::Frame(_) => {}
            }
        }
        Ok(())
    }
    .await;

    // Cleanup: unregister player + remove session, mirroring tcp::handle_connection.
    info!("WS session {} disconnected", session_id);
    {
        let mut state = server_state.write().await;
        if let Some(sess) = state.sessions.get_session(session_id) {
            let s = sess.read().await;
            if s.state == session::SessionState::LoggedIn {
                state.game.unregister_player(session_id).await;
            }
        }
        state.sessions.remove_session(session_id).await;
    }
    writer.abort();
    result
}

/// Same wire framing as the TCP decoder: `u16 length | u8 opcode | payload`
/// where `length` is the body byte count (opcode + payload). Returns None if
/// the buffer is incomplete.
fn try_decode_ws_packet(buffer: &mut BytesMut) -> Option<Packet> {
    if buffer.len() < 2 {
        return None;
    }
    let length = ((buffer[0] as u16) << 8 | buffer[1] as u16) as usize;
    if length == 0 {
        let _ = buffer.split_to(2);
        return None;
    }
    let total = 2 + length;
    if buffer.len() < total {
        return None;
    }
    let frame = buffer.split_to(total);
    let opcode = frame[2];
    let payload = if length > 1 {
        Bytes::copy_from_slice(&frame[3..total])
    } else {
        Bytes::new()
    };
    Some(Packet::new(opcode, payload))
}

/// Outgoing framing: `u16 length | u8 opcode | payload` where `length`
/// INCLUDES the 2 length bytes. Matches `network::tcp::encode_outgoing` so
/// the same Packet payload is byte-identical on either transport.
fn encode_outgoing(packet: &Packet) -> Vec<u8> {
    if is_raw_login_response(packet) {
        return vec![packet.payload[0]];
    }

    let payload_len = packet.payload.len();
    let total_len = 2 + 1 + payload_len;
    let length_value = total_len as u16;
    let mut buf = Vec::with_capacity(total_len);
    buf.push((length_value >> 8) as u8);
    buf.push((length_value & 0xFF) as u8);
    buf.push(packet.opcode);
    buf.extend_from_slice(&packet.payload);
    buf
}

fn is_raw_login_response(packet: &Packet) -> bool {
    packet.opcode == 0 && packet.payload.len() == 1
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::packets::LoginResponse;

    #[test]
    fn encodes_login_response_as_raw_byte() {
        assert_eq!(
            encode_outgoing(&LoginResponse::Success.encode()),
            vec![LoginResponse::Success as u8]
        );
        assert_eq!(
            encode_outgoing(&LoginResponse::AlreadyLoggedIn.encode()),
            vec![LoginResponse::AlreadyLoggedIn as u8]
        );
    }

    #[test]
    fn frames_regular_game_packets() {
        let encoded = encode_outgoing(&Packet::new(32, vec![b'O', b'K']));

        assert_eq!(encoded, vec![0, 5, 32, b'O', b'K']);
    }

    #[test]
    fn decodes_ws_client_frame_shape() {
        let mut buffer = BytesMut::from(&[0, 3, 216, b'h', b'i'][..]);
        let packet = try_decode_ws_packet(&mut buffer).unwrap();

        assert_eq!(packet.opcode, 216);
        assert_eq!(packet.payload.as_ref(), b"hi");
        assert!(buffer.is_empty());
    }
}
