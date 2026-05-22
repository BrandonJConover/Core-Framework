pub mod quic;
pub mod tcp;
pub mod ws;

use anyhow::Result;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tokio::sync::RwLock;
use tracing::{error, info};

use crate::game::server::ServerState;
use crate::infrastructure::config::ServerConfig;

/// Start all network listeners.
pub async fn start_server(
    config: &ServerConfig,
    server_state: Arc<RwLock<ServerState>>,
) -> Result<()> {
    let tcp_addr: SocketAddr = format!("0.0.0.0:{}", config.server_port).parse()?;

    // Start TCP listener
    let tcp_listener = TcpListener::bind(tcp_addr).await?;
    info!("TCP server listening on {}", tcp_addr);

    // Start QUIC listener in background (optional)
    let quic_addr: SocketAddr = format!("0.0.0.0:{}", config.quic_port).parse()?;
    tokio::spawn(async move {
        if let Err(e) = quic::start_quic_server(quic_addr).await {
            error!("QUIC server error: {}", e);
        }
    });

    // Start WebSocket listener (web client transport via Caddy reverse proxy).
    // ws_port = 0 is the explicit "disabled" sentinel; useful for benches that
    // want the raw TCP path only.
    if config.ws_port != 0 {
        let ws_addr: SocketAddr = format!("0.0.0.0:{}", config.ws_port).parse()?;
        let ws_state = server_state.clone();
        tokio::spawn(async move {
            if let Err(e) = ws::start_ws_server(ws_addr, ws_state).await {
                error!("WebSocket server error: {}", e);
            }
        });
    }

    // Accept TCP connections
    loop {
        match tcp_listener.accept().await {
            Ok((socket, addr)) => {
                info!("New TCP connection from {}", addr);
                let state = server_state.clone();
                tokio::spawn(async move {
                    if let Err(e) = tcp::handle_connection(socket, addr, state).await {
                        error!("Connection handler error for {}: {}", addr, e);
                    }
                });
            }
            Err(e) => {
                error!("Failed to accept connection: {}", e);
            }
        }
    }
}
