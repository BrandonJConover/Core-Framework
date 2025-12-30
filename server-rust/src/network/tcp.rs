use anyhow::Result;
use bytes::{Buf, BytesMut};
use std::net::SocketAddr;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tracing::{debug, error, warn};

use crate::infrastructure::serialization::{Packet, ProtocolAdapter, SerializationFormat};

/// Handle a TCP connection.
pub async fn handle_connection(mut socket: TcpStream, addr: SocketAddr) -> Result<()> {
    let mut buffer = BytesMut::with_capacity(65536);
    let mut protocol_detected = false;
    let mut protocol_format = SerializationFormat::RscBinary;

    loop {
        // Read data into buffer
        let bytes_read = socket.read_buf(&mut buffer).await?;

        if bytes_read == 0 {
            debug!("Connection closed by {}", addr);
            break;
        }

        // Detect protocol on first packet
        if !protocol_detected && buffer.len() > 0 {
            protocol_format = ProtocolAdapter::detect_protocol(&buffer);
            protocol_detected = true;
            debug!("Client {} using {:?} protocol", addr, protocol_format);
        }

        // Process complete packets
        while let Some(packet) = try_decode_packet(&mut buffer, protocol_format)? {
            debug!(
                "Received packet opcode={} size={} from {}",
                packet.opcode,
                packet.payload.len(),
                addr
            );

            // Process packet
            match process_packet(&packet).await {
                Ok(response) => {
                    let response_bytes = ProtocolAdapter::encode(&response, protocol_format)?;
                    socket.write_all(&response_bytes).await?;
                }
                Err(e) => {
                    warn!("Failed to process packet from {}: {}", addr, e);
                }
            }
        }
    }

    Ok(())
}

/// Try to decode a complete packet from the buffer.
fn try_decode_packet(buffer: &mut BytesMut, format: SerializationFormat) -> Result<Option<Packet>> {
    match format {
        SerializationFormat::RscBinary => try_decode_rsc_packet(buffer),
        SerializationFormat::MessagePack => try_decode_msgpack_packet(buffer),
        _ => Err(anyhow::anyhow!("Unsupported protocol")),
    }
}

/// Try to decode an RSC binary packet.
fn try_decode_rsc_packet(buffer: &mut BytesMut) -> Result<Option<Packet>> {
    if buffer.len() < 3 {
        return Ok(None); // Need at least length (2) + opcode (1)
    }

    // Peek at length
    let length = ((buffer[0] as u16) << 8 | buffer[1] as u16) as usize;
    let total_length = 2 + length;

    if buffer.len() < total_length {
        return Ok(None); // Incomplete packet
    }

    // Extract and decode packet
    let packet_data = buffer.split_to(total_length);
    let packet = Packet::decode_rsc(&packet_data)?;

    Ok(Some(packet))
}

/// Try to decode a MessagePack packet.
fn try_decode_msgpack_packet(buffer: &mut BytesMut) -> Result<Option<Packet>> {
    if buffer.len() < 6 {
        return Ok(None); // Need header
    }

    // Check magic byte
    if buffer[0] != ProtocolAdapter::MSGPACK_MAGIC {
        return Err(anyhow::anyhow!("Invalid MessagePack magic byte"));
    }

    // Get length
    let length = ((buffer[2] as u32) << 24
        | (buffer[3] as u32) << 16
        | (buffer[4] as u32) << 8
        | buffer[5] as u32) as usize;

    let total_length = 6 + length;

    if buffer.len() < total_length {
        return Ok(None); // Incomplete packet
    }

    // Extract and decode packet
    let packet_data = buffer.split_to(total_length);
    let packet = Packet::decode_msgpack(&packet_data)?;

    Ok(Some(packet))
}

/// Process a game packet and generate response.
async fn process_packet(packet: &Packet) -> Result<Packet> {
    // Placeholder - actual game logic would go here
    match packet.opcode {
        0 => {
            // Ping/pong
            Ok(Packet::new(0, bytes::Bytes::from_static(b"pong")))
        }
        1 => {
            // Login request (placeholder)
            Ok(Packet::new(1, bytes::Bytes::from_static(&[0]))) // Success
        }
        _ => {
            // Echo back for unknown opcodes
            Ok(Packet::new(packet.opcode, packet.payload.clone()))
        }
    }
}

/// TCP connection state for a client.
pub struct ConnectionState {
    pub addr: SocketAddr,
    pub protocol: SerializationFormat,
    pub authenticated: bool,
    pub username: Option<String>,
    pub session_id: Option<String>,
}

impl ConnectionState {
    pub fn new(addr: SocketAddr) -> Self {
        Self {
            addr,
            protocol: SerializationFormat::RscBinary,
            authenticated: false,
            username: None,
            session_id: None,
        }
    }
}
