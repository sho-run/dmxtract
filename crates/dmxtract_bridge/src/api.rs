use crate::{
    BRIDGE_VERSION,
    transport::{self, OutputConfig, OutputDriver},
};
use axum::{
    Json, Router,
    extract::{
        Path, Query, State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use futures_util::{SinkExt, StreamExt};
use rand::RngCore;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::time::interval;

pub struct BridgeState {
    pairs: Mutex<HashMap<String, PendingPair>>,
    sessions: Mutex<HashMap<String, Session>>,
    lease: Mutex<Option<Lease>>,
    output: Mutex<Option<Box<dyn OutputDriver>>>,
    frames: Mutex<HashMap<u16, [u8; 512]>>,
}
struct PendingPair {
    origin: String,
    code: String,
    expires: Instant,
}
struct Session {
    origin: String,
    expires: Instant,
}
struct Lease {
    id: String,
    token: String,
    last_seen: Instant,
    safety_unlocked: bool,
}

impl BridgeState {
    pub fn new() -> Self {
        Self {
            pairs: Mutex::new(HashMap::new()),
            sessions: Mutex::new(HashMap::new()),
            lease: Mutex::new(None),
            output: Mutex::new(None),
            frames: Mutex::new(HashMap::new()),
        }
    }
    pub fn start_watchdog(self: Arc<Self>) {
        tokio::spawn(async move {
            let mut timer = interval(Duration::from_millis(250));
            loop {
                timer.tick().await;
                let expired = self
                    .lease
                    .lock()
                    .expect("lease lock")
                    .as_ref()
                    .is_some_and(|lease| lease.last_seen.elapsed() > Duration::from_millis(1500));
                if expired {
                    self.blackout(true);
                    *self.lease.lock().expect("lease lock") = None;
                    tracing::warn!("output lease expired; sent zero frames");
                }
            }
        });
    }
    fn blackout(&self, terminated: bool) {
        let universes: Vec<u16> = self
            .frames
            .lock()
            .expect("frame lock")
            .keys()
            .copied()
            .collect();
        if let Some(output) = self.output.lock().expect("output lock").as_mut() {
            for universe in universes {
                let _ = output.send(universe, &[0; 512], terminated);
            }
        }
        self.frames
            .lock()
            .expect("frame lock")
            .values_mut()
            .for_each(|frame| frame.fill(0));
    }
}

pub fn router(state: Arc<BridgeState>) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/outputs", get(outputs))
        .route("/v1/discovery/artnet", get(discover_artnet))
        .route("/v1/pair/request", post(pair_request))
        .route("/v1/pair/confirm", post(pair_confirm))
        .route("/v1/test/begin", post(begin_test))
        .route("/v1/test/{lease_id}/channels", post(set_channels))
        .route("/v1/test/{lease_id}/heartbeat", post(heartbeat))
        .route("/v1/test/{lease_id}/unlock", post(unlock))
        .route("/v1/test/{lease_id}/blackout", post(blackout))
        .route("/v1/test/{lease_id}/end", post(end_test))
        .route("/v1/test/{lease_id}/ws", get(websocket))
        .with_state(state)
}

async fn health() -> Json<Value> {
    Json(
        json!({ "ok": true, "name": "DMXtract Bridge", "version": BRIDGE_VERSION, "apiVersion": 1, "loopbackOnly": true }),
    )
}

async fn outputs() -> Json<Value> {
    Json(json!({ "network": [
        { "kind": "artNet", "label": "Network DMX · Art-Net" },
        { "kind": "sacn", "label": "Network DMX · sACN" }
    ], "usb": transport::serial_outputs() }))
}

async fn discover_artnet() -> Result<Json<Value>, ApiError> {
    let nodes =
        tokio::task::spawn_blocking(|| transport::discover_artnet(Duration::from_millis(3000)))
            .await
            .map_err(|_| ApiError::bad("Art-Net discovery stopped unexpectedly."))?
            .map_err(|error| ApiError::bad(&error.to_string()))?;
    Ok(Json(json!({ "nodes": nodes, "maximumScanMs": 3000 })))
}

#[derive(Deserialize)]
struct PairRequest {
    origin: String,
}
async fn pair_request(
    State(state): State<Arc<BridgeState>>,
    headers: HeaderMap,
    Json(request): Json<PairRequest>,
) -> Result<Json<Value>, ApiError> {
    if !valid_origin(&request.origin) {
        return Err(ApiError::bad(
            "Use the HTTPS DMXtract site or a localhost development origin.",
        ));
    }
    require_matching_origin(&headers, &request.origin)?;
    let request_id = random_token(18);
    let code = format!("{:06}", rand::random::<u32>() % 1_000_000);
    state.pairs.lock().unwrap().insert(
        request_id.clone(),
        PendingPair {
            origin: request.origin.clone(),
            code: code.clone(),
            expires: Instant::now() + Duration::from_secs(120),
        },
    );
    // The pairing code must be visible for terminal builds. Do not print the
    // requesting origin or attach the code to structured logs.
    eprintln!("DMXTRACT_PAIRING\t{}", code);
    tracing::warn!("pairing requested; confirm the code shown in the bridge");
    Ok(Json(
        json!({ "requestId": request_id, "expiresInSeconds": 120, "message": "Check the DMXtract Bridge tray or terminal for a six-digit code." }),
    ))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairConfirm {
    request_id: String,
    code: String,
}
async fn pair_confirm(
    State(state): State<Arc<BridgeState>>,
    Json(request): Json<PairConfirm>,
) -> Result<Json<Value>, ApiError> {
    let pending = state
        .pairs
        .lock()
        .unwrap()
        .remove(&request.request_id)
        .ok_or_else(|| ApiError::bad("That pairing request is no longer available."))?;
    if pending.expires < Instant::now() || pending.code != request.code {
        return Err(ApiError::unauthorized(
            "The pairing code is incorrect or expired.",
        ));
    }
    let token = random_token(32);
    state.sessions.lock().unwrap().insert(
        token.clone(),
        Session {
            origin: pending.origin,
            expires: Instant::now() + Duration::from_secs(12 * 60 * 60),
        },
    );
    Ok(Json(
        json!({ "token": token, "expiresWhenBridgeExits": true }),
    ))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BeginRequest {
    origin: String,
    output: OutputConfig,
}
async fn begin_test(
    State(state): State<Arc<BridgeState>>,
    headers: HeaderMap,
    Json(request): Json<BeginRequest>,
) -> Result<Json<Value>, ApiError> {
    require_matching_origin(&headers, &request.origin)?;
    let token = authorize(&state, &headers, &request.origin)?;
    if state.lease.lock().unwrap().is_some() {
        return Err(ApiError::conflict(
            "Another controller is already testing output.",
        ));
    }
    let mut output = transport::open_output(&request.output)
        .map_err(|error| ApiError::bad(&error.to_string()))?;
    output
        .send(1, &[0; 512], false)
        .map_err(|error| ApiError::bad(&error.to_string()))?;
    let label = output.label();
    *state.output.lock().unwrap() = Some(output);
    state.frames.lock().unwrap().insert(1, [0; 512]);
    let id = random_token(18);
    *state.lease.lock().unwrap() = Some(Lease {
        id: id.clone(),
        token,
        last_seen: Instant::now(),
        safety_unlocked: false,
    });
    Ok(Json(
        json!({ "leaseId": id, "heartbeatMs": 500, "output": label, "startsBlackedOut": true }),
    ))
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChannelRequest {
    #[serde(default = "one")]
    universe: u16,
    channels: Vec<ChannelValue>,
    #[serde(default)]
    risky: bool,
}
#[derive(Debug, Deserialize)]
struct ChannelValue {
    channel: u16,
    value: u8,
}
fn one() -> u16 {
    1
}

async fn set_channels(
    State(state): State<Arc<BridgeState>>,
    Path(lease_id): Path<String>,
    headers: HeaderMap,
    Json(request): Json<ChannelRequest>,
) -> Result<Json<Value>, ApiError> {
    let token = bearer(&headers)?;
    with_lease(&state, &lease_id, &token, |lease| {
        if request.risky && !lease.safety_unlocked {
            return Err(ApiError::locked(
                "Unlock risky ranges before sending strobe, lamp, reset, or maintenance values.",
            ));
        }
        lease.last_seen = Instant::now();
        Ok(())
    })?;
    let mut frames = state.frames.lock().unwrap();
    let frame = frames.entry(request.universe).or_insert([0; 512]);
    for value in &request.channels {
        if value.channel == 0 || value.channel > 512 {
            return Err(ApiError::bad("Channel must be between 1 and 512."));
        }
        frame[usize::from(value.channel - 1)] = value.value;
    }
    state
        .output
        .lock()
        .unwrap()
        .as_mut()
        .ok_or_else(|| ApiError::bad("No output is connected."))?
        .send(request.universe, frame, false)
        .map_err(|error| ApiError::bad(&error.to_string()))?;
    Ok(Json(json!({ "ok": true })))
}

async fn heartbeat(
    State(state): State<Arc<BridgeState>>,
    Path(lease_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let token = bearer(&headers)?;
    with_lease(&state, &lease_id, &token, |lease| {
        lease.last_seen = Instant::now();
        Ok(())
    })?;
    Ok(Json(json!({ "ok": true })))
}
async fn unlock(
    State(state): State<Arc<BridgeState>>,
    Path(lease_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let token = bearer(&headers)?;
    with_lease(&state, &lease_id, &token, |lease| {
        lease.safety_unlocked = true;
        lease.last_seen = Instant::now();
        Ok(())
    })?;
    Ok(Json(json!({ "unlocked": true })))
}
async fn blackout(
    State(state): State<Arc<BridgeState>>,
    Path(lease_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let token = bearer(&headers)?;
    with_lease(&state, &lease_id, &token, |lease| {
        lease.last_seen = Instant::now();
        Ok(())
    })?;
    state.blackout(false);
    Ok(Json(json!({ "ok": true })))
}
async fn end_test(
    State(state): State<Arc<BridgeState>>,
    Path(lease_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let token = bearer(&headers)?;
    with_lease(&state, &lease_id, &token, |_| Ok(()))?;
    state.blackout(true);
    *state.lease.lock().unwrap() = None;
    *state.output.lock().unwrap() = None;
    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
struct WsQuery {
    token: String,
}
async fn websocket(
    State(state): State<Arc<BridgeState>>,
    Path(lease_id): Path<String>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<Response, ApiError> {
    with_lease(&state, &lease_id, &query.token, |_| Ok(()))?;
    Ok(ws
        .on_upgrade(move |socket| websocket_session(socket, state, lease_id, query.token))
        .into_response())
}
async fn websocket_session(
    socket: WebSocket,
    state: Arc<BridgeState>,
    lease_id: String,
    token: String,
) {
    let (mut sender, mut receiver) = socket.split();
    while let Some(Ok(message)) = receiver.next().await {
        let result = match message {
            Message::Text(text) if text == "heartbeat" => {
                with_lease(&state, &lease_id, &token, |lease| {
                    lease.last_seen = Instant::now();
                    Ok(())
                })
                .map(|_| json!({"ok":true}))
            }
            Message::Text(text) => serde_json::from_str::<ChannelRequest>(&text)
                .map_err(|_| ApiError::bad("Malformed channel frame."))
                .and_then(|request| {
                    with_lease(&state, &lease_id, &token, |lease| {
                        if request.risky && !lease.safety_unlocked {
                            return Err(ApiError::locked("Risky output is locked."));
                        }
                        lease.last_seen = Instant::now();
                        Ok(())
                    })?;
                    let mut frames = state.frames.lock().unwrap();
                    let frame = frames.entry(request.universe).or_insert([0; 512]);
                    for item in request.channels {
                        if item.channel == 0 || item.channel > 512 {
                            return Err(ApiError::bad("Channel must be 1-512."));
                        }
                        frame[usize::from(item.channel - 1)] = item.value;
                    }
                    state
                        .output
                        .lock()
                        .unwrap()
                        .as_mut()
                        .ok_or_else(|| ApiError::bad("No output."))?
                        .send(request.universe, frame, false)
                        .map_err(|error| ApiError::bad(&error.to_string()))?;
                    Ok(json!({"ok":true}))
                }),
            Message::Close(_) => break,
            _ => Ok(json!({"ok":true})),
        };
        let response = match result {
            Ok(value) => value,
            Err(error) => json!({"ok":false,"error":error.message}),
        };
        if sender
            .send(Message::Text(response.to_string().into()))
            .await
            .is_err()
        {
            break;
        }
    }
    state.blackout(true);
    if state
        .lease
        .lock()
        .unwrap()
        .as_ref()
        .is_some_and(|lease| lease.id == lease_id)
    {
        *state.lease.lock().unwrap() = None;
    }
}

fn authorize(state: &BridgeState, headers: &HeaderMap, origin: &str) -> Result<String, ApiError> {
    let token = bearer(headers)?;
    let sessions = state.sessions.lock().unwrap();
    let session = sessions
        .get(&token)
        .ok_or_else(|| ApiError::unauthorized("Pair this browser with the bridge first."))?;
    if session.expires < Instant::now() || session.origin != origin {
        return Err(ApiError::unauthorized(
            "This token belongs to a different site or has expired.",
        ));
    }
    Ok(token)
}
fn with_lease<F>(
    state: &BridgeState,
    lease_id: &str,
    token: &str,
    operation: F,
) -> Result<(), ApiError>
where
    F: FnOnce(&mut Lease) -> Result<(), ApiError>,
{
    let mut guard = state.lease.lock().unwrap();
    let lease = guard
        .as_mut()
        .ok_or_else(|| ApiError::conflict("There is no active output test."))?;
    if lease.id != lease_id || lease.token != token {
        return Err(ApiError::unauthorized(
            "This output lease belongs to another controller.",
        ));
    }
    operation(lease)
}
fn bearer(headers: &HeaderMap) -> Result<String, ApiError> {
    headers
        .get("authorization")
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .map(str::to_owned)
        .ok_or_else(|| ApiError::unauthorized("Missing bridge token."))
}
fn valid_origin(origin: &str) -> bool {
    origin.starts_with("https://")
        || origin.starts_with("http://localhost")
        || origin.starts_with("http://127.0.0.1")
}
fn require_matching_origin(headers: &HeaderMap, claimed_origin: &str) -> Result<(), ApiError> {
    let actual_origin = headers
        .get("origin")
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| ApiError::unauthorized("The browser Origin header is missing."))?;
    if actual_origin != claimed_origin {
        return Err(ApiError::unauthorized(
            "The requesting site does not match the claimed pairing origin.",
        ));
    }
    Ok(())
}
fn random_token(length: usize) -> String {
    let mut bytes = vec![0_u8; length];
    rand::rng().fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

struct ApiError {
    status: StatusCode,
    message: String,
}
impl ApiError {
    fn bad(message: &str) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message: message.to_owned(),
        }
    }
    fn unauthorized(message: &str) -> Self {
        Self {
            status: StatusCode::UNAUTHORIZED,
            message: message.to_owned(),
        }
    }
    fn conflict(message: &str) -> Self {
        Self {
            status: StatusCode::CONFLICT,
            message: message.to_owned(),
        }
    }
    fn locked(message: &str) -> Self {
        Self {
            status: StatusCode::LOCKED,
            message: message.to_owned(),
        }
    }
}
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(json!({"ok":false,"error":self.message}))).into_response()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    #[test]
    fn claimed_pairing_origin_must_match_browser_header() {
        let mut headers = HeaderMap::new();
        headers.insert("origin", HeaderValue::from_static("https://evil.example"));
        assert!(require_matching_origin(&headers, "https://dmxtract.sho.run").is_err());
        assert!(require_matching_origin(&headers, "https://evil.example").is_ok());
    }
}
