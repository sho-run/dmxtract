mod api;
mod mcp;
mod packets;
mod transport;

use api::BridgeState;
use std::{net::SocketAddr, sync::Arc};
use tokio::net::TcpListener;
use tower_http::{cors::CorsLayer, trace::TraceLayer};
use tracing_subscriber::EnvFilter;

pub const BRIDGE_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const DEFAULT_PORT: u16 = 46321;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("dmxtract_bridge=info,tower_http=info")),
        )
        .init();

    if std::env::args().any(|argument| argument == "--mcp") {
        return mcp::serve_stdio().await;
    }

    let port = std::env::var("DMXTRACT_BRIDGE_PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let state = Arc::new(BridgeState::new());
    state.clone().start_watchdog();
    let app = api::router(state)
        .layer(CorsLayer::very_permissive())
        .layer(TraceLayer::new_for_http());
    let listener = TcpListener::bind(address).await?;
    tracing::info!(%address, "DMXtract bridge listening on loopback");
    axum::serve(listener, app).await?;
    Ok(())
}
