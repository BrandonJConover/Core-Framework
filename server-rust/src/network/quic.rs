use anyhow::Result;
use std::net::SocketAddr;

use crate::infrastructure::serialization::Packet;

/// Start QUIC server for modern clients.
/// Currently stubbed out pending quinn/rustls/rcgen API stabilization.
pub async fn start_quic_server(addr: SocketAddr) -> Result<()> {
    tracing::info!("QUIC server not yet implemented, skipping");
    Ok(())
}

/// QUIC client for connecting to other servers.
/// Currently stubbed out pending quinn/rustls/rcgen API stabilization.
pub struct QuicClient;

impl QuicClient {
    /// Create a new QUIC client.
    pub fn new() -> Result<Self> {
        Ok(Self)
    }

    /// Connect to a QUIC server.
    pub async fn connect(&self, addr: SocketAddr, _server_name: &str) -> Result<quinn::Connection> {
        Err(anyhow::anyhow!("QUIC client not yet implemented"))
    }

    /// Send a packet and receive response.
    pub async fn send_packet(
        &self,
        _connection: &quinn::Connection,
        _packet: &Packet,
    ) -> Result<Packet> {
        Err(anyhow::anyhow!("QUIC client not yet implemented"))
    }
}
