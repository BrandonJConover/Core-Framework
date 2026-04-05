//! TCP connection handler.
//! Manages individual TCP connections, packet framing, and routing to the server state.

use anyhow::Result;
use bytes::BytesMut;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, RwLock};
use tracing::{debug, error, info, warn};

use crate::game::server::{HandleResult, ServerState};
use crate::protocol::Packet;

/// Handle a TCP connection with full session lifecycle.
pub async fn handle_connection(
    mut socket: TcpStream,
    addr: SocketAddr,
    server_state: Arc<RwLock<ServerState>>,
) -> Result<()> {
    let mut buffer = BytesMut::with_capacity(4096);

    // Create session with outgoing packet channel
    let (tx, mut rx) = mpsc::channel::<Packet>(256);

    let session_id = {
        let mut state = server_state.write().await;
        match state.sessions.create_session(addr, tx).await {
            Some(session) => {
                let s = session.read().await;
                s.id
            }
            None => {
                warn!("Failed to create session for {} (rate limited)", addr);
                return Ok(());
            }
        }
    };

    info!("Session {} created for {}", session_id, addr);

    // Split socket for concurrent read/write
    let (mut reader, mut writer) = socket.into_split();

    // Spawn outgoing packet writer
    let write_handle = tokio::spawn(async move {
        while let Some(packet) = rx.recv().await {
            let encoded = encode_outgoing(&packet);
            if let Err(e) = writer.write_all(&encoded).await {
                debug!("Write error for session: {}", e);
                break;
            }
        }
    });

    // Read incoming packets
    loop {
        let bytes_read = match reader.read_buf(&mut buffer).await {
            Ok(0) => {
                debug!("Connection closed by {}", addr);
                break;
            }
            Ok(n) => n,
            Err(e) => {
                debug!("Read error from {}: {}", addr, e);
                break;
            }
        };

        // Process all complete packets in buffer
        while let Some(packet) = try_decode_rsc_packet(&mut buffer)? {
            debug!(
                "Session {} packet opcode={} size={}",
                session_id,
                packet.opcode,
                packet.payload.len()
            );

            // Route packet to server state handler
            let result = {
                let mut state = server_state.write().await;
                state.handle_packet(session_id, packet).await
            };

            match result {
                HandleResult::Continue => {}
                HandleResult::Disconnect => {
                    info!("Session {} disconnecting (handler requested)", session_id);
                    // Clean up session
                    let mut state = server_state.write().await;
                    state.sessions.remove_session(session_id).await;
                    write_handle.abort();
                    return Ok(());
                }
            }
        }
    }

    // Connection closed — clean up
    info!("Session {} disconnected", session_id);
    {
        let mut state = server_state.write().await;
        // Unregister player from game if logged in
        if let Some(session) = state.sessions.get_session(session_id) {
            let s = session.read().await;
            if s.state == crate::session::SessionState::LoggedIn {
                state.game.unregister_player(session_id).await;
            }
        }
        state.sessions.remove_session(session_id).await;
    }
    write_handle.abort();

    Ok(())
}

/// Try to decode an RSC binary packet from the buffer.
/// RSC client->server format: 2-byte length (excludes length field) + 1-byte opcode + payload
fn try_decode_rsc_packet(buffer: &mut BytesMut) -> Result<Option<Packet>> {
    if buffer.len() < 2 {
        return Ok(None);
    }

    // Read 2-byte length (big-endian, excludes the 2 length bytes)
    let length = ((buffer[0] as u16) << 8 | buffer[1] as u16) as usize;

    if length == 0 {
        // Empty packet, skip
        buffer.split_to(2);
        return Ok(None);
    }

    let total_length = 2 + length; // 2 length bytes + payload (which includes opcode)

    if buffer.len() < total_length {
        return Ok(None); // Incomplete packet, wait for more data
    }

    // Extract packet data
    let packet_data = buffer.split_to(total_length);

    // First byte after length is opcode
    let opcode = packet_data[2];
    let payload = if length > 1 {
        bytes::Bytes::copy_from_slice(&packet_data[3..total_length])
    } else {
        bytes::Bytes::new()
    };

    Ok(Some(Packet::new(opcode, payload)))
}

/// Encode an outgoing packet for the RSC client.
/// RSC server->client format: 2-byte length (includes length field) + opcode + payload
fn encode_outgoing(packet: &Packet) -> Vec<u8> {
    let payload_len = packet.payload.len();
    let total_len = 2 + 1 + payload_len; // length field + opcode + payload
    let length_value = total_len as u16; // includes the 2 length bytes

    let mut buf = Vec::with_capacity(total_len);
    buf.push((length_value >> 8) as u8);
    buf.push((length_value & 0xFF) as u8);
    buf.push(packet.opcode);
    buf.extend_from_slice(&packet.payload);
    buf
}
