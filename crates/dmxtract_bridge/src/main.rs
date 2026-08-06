mod api;
mod mcp;
mod packets;
mod transport;

use api::{BridgeState, DEFAULT_IDLE_TIMEOUT_SECS};
use std::{net::SocketAddr, sync::Arc, time::Duration};
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

    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|argument| argument == "--mcp") {
        return mcp::serve_stdio().await;
    }

    let port = std::env::var("DMXTRACT_BRIDGE_PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let idle_timeout = match parse_idle_timeout(&args) {
        Ok(value) => value,
        Err(message) => {
            eprintln!("dmxtract_bridge: {message}");
            std::process::exit(2);
        }
    };
    let state = Arc::new(BridgeState::with_idle_timeout(idle_timeout));
    state.clone().start_watchdog();
    state.clone().start_idle_watchdog();
    // allow_private_network answers Chrome's public-site-to-loopback preflight
    // (Access-Control-Allow-Private-Network); without it a deployed HTTPS page
    // may be blocked from reaching the loopback bridge as enforcement rolls out.
    let app = api::router(state)
        .layer(CorsLayer::very_permissive().allow_private_network(true))
        .layer(TraceLayer::new_for_http());
    let listener = TcpListener::bind(address).await?;
    tracing::info!(%address, ?idle_timeout, "DMXtract bridge listening on loopback");
    axum::serve(listener, app).await?;
    Ok(())
}

/// `--idle-timeout <seconds>` / `--idle-timeout=<seconds>` takes priority
/// over `DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS`, which takes priority over the
/// default. A value of 0 disables idle self-exit (`None`). A value that
/// fails to parse as a whole number of seconds is a startup error rather
/// than a silent fallback to the default — a typo in a launcher script or
/// env var should not quietly disable a shorter idle timeout the operator
/// actually asked for.
fn parse_idle_timeout(args: &[String]) -> Result<Option<Duration>, String> {
    let flag_value = args
        .iter()
        .position(|argument| argument == "--idle-timeout")
        .and_then(|index| args.get(index + 1))
        .cloned()
        .or_else(|| {
            args.iter()
                .find_map(|argument| argument.strip_prefix("--idle-timeout=").map(str::to_owned))
        });
    let (source, raw) = match flag_value {
        Some(value) => ("--idle-timeout", value),
        None => match std::env::var("DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS") {
            Ok(value) => ("DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS", value),
            Err(_) => return Ok(Some(Duration::from_secs(DEFAULT_IDLE_TIMEOUT_SECS))),
        },
    };
    let seconds: u64 = raw.parse().map_err(|_| {
        format!("{source} must be a non-negative whole number of seconds, got {raw:?}")
    })?;
    Ok(if seconds == 0 {
        None
    } else {
        Some(Duration::from_secs(seconds))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_timeout_flag_takes_priority_and_parses_seconds() {
        let args = vec![
            "dmxtract_bridge".to_owned(),
            "--idle-timeout".to_owned(),
            "45".to_owned(),
        ];
        assert_eq!(parse_idle_timeout(&args), Ok(Some(Duration::from_secs(45))));
    }

    #[test]
    fn idle_timeout_flag_accepts_equals_syntax() {
        let args = vec!["dmxtract_bridge".to_owned(), "--idle-timeout=90".to_owned()];
        assert_eq!(parse_idle_timeout(&args), Ok(Some(Duration::from_secs(90))));
    }

    #[test]
    fn idle_timeout_zero_disables_self_exit() {
        let args = vec!["dmxtract_bridge".to_owned(), "--idle-timeout=0".to_owned()];
        assert_eq!(parse_idle_timeout(&args), Ok(None));
    }

    #[test]
    fn idle_timeout_falls_back_to_default_with_no_flag_or_env() {
        // SAFETY: single-threaded within this test; no other test in this
        // binary reads or writes DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS.
        unsafe {
            std::env::remove_var("DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS");
        }
        let args = vec!["dmxtract_bridge".to_owned()];
        assert_eq!(
            parse_idle_timeout(&args),
            Ok(Some(Duration::from_secs(DEFAULT_IDLE_TIMEOUT_SECS)))
        );

        // Same env-var ownership as above, exercised in the same test to
        // avoid a second test racing on this process-global var.
        unsafe {
            std::env::set_var("DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS", "-5");
        }
        let error = parse_idle_timeout(&args).unwrap_err();
        unsafe {
            std::env::remove_var("DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS");
        }
        assert!(error.contains("DMXTRACT_BRIDGE_IDLE_TIMEOUT_SECS"));
        assert!(error.contains("-5"));
    }

    #[test]
    fn idle_timeout_flag_rejects_malformed_value() {
        let args = vec![
            "dmxtract_bridge".to_owned(),
            "--idle-timeout=not-a-number".to_owned(),
        ];
        let error = parse_idle_timeout(&args).unwrap_err();
        assert!(error.contains("--idle-timeout"));
        assert!(error.contains("not-a-number"));
    }
}
