pub mod quic;
pub mod tcp;

use anyhow::Result;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{info, error};

use crate::infrastructure::config::ServerConfig;

/// Start all network listeners.
pub async fn start_server(config: &ServerConfig) -> Result<()> {
    let tcp_addr: SocketAddr = format!("0.0.0.0:{}", config.server_port).parse()?;
    let quic_addr: SocketAddr = format!("0.0.0.0:{}", config.quic_port).parse()?;

    // Start TCP listener
    let tcp_listener = TcpListener::bind(tcp_addr).await?;
    info!("TCP server listening on {}", tcp_addr);

    // Start QUIC listener (if certificates are configured)
    let quic_handle = tokio::spawn(async move {
        if let Err(e) = quic::start_quic_server(quic_addr).await {
            error!("QUIC server error: {}", e);
        }
    });

    // Accept TCP connections
    loop {
        match tcp_listener.accept().await {
            Ok((socket, addr)) => {
                info!("New TCP connection from {}", addr);
                tokio::spawn(tcp::handle_connection(socket, addr));
            }
            Err(e) => {
                error!("Failed to accept connection: {}", e);
            }
        }
    }
}
