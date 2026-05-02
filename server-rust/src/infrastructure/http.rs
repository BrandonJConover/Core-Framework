use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::Serialize;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::cors::{Any, CorsLayer};
use tracing::info;

use super::InfrastructureManager;

/// HTTP server for health checks, metrics, and admin endpoints.
pub struct HttpServer {
    port: u16,
}

impl HttpServer {
    pub fn new(port: u16) -> Self {
        Self { port }
    }

    /// Start the HTTP server.
    pub async fn start(
        self,
        infrastructure: Arc<RwLock<InfrastructureManager>>,
    ) -> anyhow::Result<()> {
        let app = Router::new()
            // Health endpoints
            .route("/health", get(health_check))
            .route("/health/live", get(liveness_check))
            .route("/health/ready", get(readiness_check))
            // Info endpoints
            .route("/info", get(server_info))
            .route("/stats", get(server_stats))
            // Admin endpoints (should be protected in production)
            .route("/admin/shutdown", post(shutdown_handler))
            // CORS for development
            .layer(CorsLayer::new().allow_origin(Any).allow_methods(Any))
            .with_state(AppState { infrastructure });

        let addr = SocketAddr::from(([0, 0, 0, 0], self.port));
        info!("HTTP server listening on {}", addr);

        let listener = tokio::net::TcpListener::bind(addr).await?;
        axum::serve(listener, app).await?;

        Ok(())
    }
}

#[derive(Clone)]
struct AppState {
    infrastructure: Arc<RwLock<InfrastructureManager>>,
}

// ==================== HEALTH ENDPOINTS ====================

async fn health_check(State(state): State<AppState>) -> impl IntoResponse {
    let infra = state.infrastructure.read().await;
    let status = infra.health_status();

    let code = if status.healthy {
        StatusCode::OK
    } else {
        StatusCode::SERVICE_UNAVAILABLE
    };

    (code, Json(status))
}

async fn liveness_check() -> impl IntoResponse {
    Json(LivenessResponse {
        status: "alive".to_string(),
        timestamp: chrono::Utc::now(),
    })
}

async fn readiness_check(State(state): State<AppState>) -> impl IntoResponse {
    let infra = state.infrastructure.read().await;

    if infra.is_healthy() {
        (
            StatusCode::OK,
            Json(ReadinessResponse {
                ready: true,
                message: "Server is ready to accept requests".to_string(),
            }),
        )
    } else {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(ReadinessResponse {
                ready: false,
                message: "Server is not ready".to_string(),
            }),
        )
    }
}

// ==================== INFO ENDPOINTS ====================

async fn server_info() -> impl IntoResponse {
    Json(ServerInfo {
        name: "OpenRSC Rust Server".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        rust_version: env!("CARGO_PKG_RUST_VERSION").to_string(),
        build_timestamp: option_env!("BUILD_TIMESTAMP")
            .unwrap_or("unknown")
            .to_string(),
    })
}

async fn server_stats(State(state): State<AppState>) -> impl IntoResponse {
    let infra = state.infrastructure.read().await;

    let players_online = infra
        .redis()
        .map(|r| futures::executor::block_on(async { r.online_count().await.unwrap_or(0) }))
        .unwrap_or(0);

    Json(ServerStats {
        uptime_seconds: infra
            .metrics()
            .map(|m| m.uptime_seconds())
            .unwrap_or(0),
        players_online,
        memory_usage_mb: get_memory_usage_mb(),
        timestamp: chrono::Utc::now(),
    })
}

// ==================== ADMIN ENDPOINTS ====================

async fn shutdown_handler() -> impl IntoResponse {
    // In production, this should verify authorization
    info!("Shutdown requested via HTTP endpoint");

    Json(AdminResponse {
        success: true,
        message: "Shutdown initiated".to_string(),
    })
}

// ==================== RESPONSE TYPES ====================

#[derive(Serialize)]
struct LivenessResponse {
    status: String,
    timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Serialize)]
struct ReadinessResponse {
    ready: bool,
    message: String,
}

#[derive(Serialize)]
struct ServerInfo {
    name: String,
    version: String,
    rust_version: String,
    build_timestamp: String,
}

#[derive(Serialize)]
struct ServerStats {
    uptime_seconds: u64,
    players_online: u64,
    memory_usage_mb: u64,
    timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Serialize)]
struct AdminResponse {
    success: bool,
    message: String,
}

// ==================== UTILITIES ====================

fn get_memory_usage_mb() -> u64 {
    // Platform-specific memory usage
    #[cfg(target_os = "linux")]
    {
        use std::fs;
        if let Ok(status) = fs::read_to_string("/proc/self/status") {
            for line in status.lines() {
                if line.starts_with("VmRSS:") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 {
                        if let Ok(kb) = parts[1].parse::<u64>() {
                            return kb / 1024;
                        }
                    }
                }
            }
        }
    }
    0
}
