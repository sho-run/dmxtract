use crate::{
    BRIDGE_VERSION,
    transport::{self, OutputConfig, OutputDriver},
};
use axum::{
    Json, Router,
    extract::{
        Form, Path, Query, State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode, header},
    response::{Html, IntoResponse, Response},
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
    control_token: String,
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
    decision: PairDecision,
}
enum PairDecision {
    Pending,
    Approved(String),
    Denied,
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
            control_token: random_token(24),
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
        .route("/", get(control_page))
        .route("/v1/health", get(health))
        .route("/v1/outputs", get(outputs))
        .route("/v1/discovery/artnet", get(discover_artnet))
        .route("/v1/pair/request", post(pair_request))
        .route("/v1/pair/confirm", post(pair_confirm))
        .route("/v1/pair/{request_id}/status", get(pair_status))
        .route("/v1/pair/{request_id}/approve", post(pair_approve))
        .route("/v1/pair/{request_id}/deny", post(pair_deny))
        .route("/v1/control/blackout", post(control_blackout))
        .route("/v1/test/begin", post(begin_test))
        .route("/v1/test/{lease_id}/channels", post(set_channels))
        .route("/v1/test/{lease_id}/heartbeat", post(heartbeat))
        .route("/v1/test/{lease_id}/unlock", post(unlock))
        .route("/v1/test/{lease_id}/blackout", post(blackout))
        .route("/v1/test/{lease_id}/end", post(end_test))
        .route("/v1/test/{lease_id}/ws", get(websocket))
        .with_state(state)
}

async fn control_page(State(state): State<Arc<BridgeState>>) -> Response {
    let now = Instant::now();
    let requests = state
        .pairs
        .lock()
        .expect("pair lock")
        .iter()
        .filter(|(_, pair)| pair.expires > now)
        .map(|(id, pair)| {
            let origin = html_escape(&pair.origin);
            let id = html_escape(id);
            let control_token = html_escape(&state.control_token);
            match pair.decision {
                PairDecision::Pending => format!(
                    r#"<section class="request">
                      <p class="eyebrow">ACCESS REQUEST</p>
                      <h2>{origin}</h2>
                      <p>wants to control DMX output through this bridge.</p>
                      <div class="actions">
                        <form method="post" action="/v1/pair/{id}/approve"><input type="hidden" name="control_token" value="{control_token}"><button class="allow" type="submit">Allow this site</button></form>
                        <form method="post" action="/v1/pair/{id}/deny"><input type="hidden" name="control_token" value="{control_token}"><button class="deny" type="submit">Deny</button></form>
                      </div>
                    </section>"#
                ),
                PairDecision::Approved(_) => format!(
                    r#"<section class="request approved"><h2>Approved</h2><p>{origin} can finish connecting. You can return to DMXtract.</p></section>"#
                ),
                PairDecision::Denied => format!(
                    r#"<section class="request denied"><h2>Denied</h2><p>{origin} was not given access.</p></section>"#
                ),
            }
        })
        .collect::<Vec<_>>()
        .join("\n");

    let (active, controller, safety_unlocked, heartbeat_age) = state
        .lease
        .lock()
        .expect("lease lock")
        .as_ref()
        .map(|lease| {
            let controller = state
                .sessions
                .lock()
                .expect("session lock")
                .get(&lease.token)
                .map(|session| session.origin.clone())
                .unwrap_or_else(|| "Unknown controller".to_owned());
            (
                true,
                controller,
                lease.safety_unlocked,
                lease.last_seen.elapsed().as_millis(),
            )
        })
        .unwrap_or((false, "No site has output control".to_owned(), false, 0));
    let output = state
        .output
        .lock()
        .expect("output lock")
        .as_ref()
        .map(|output| output.label())
        .unwrap_or_else(|| "Output stopped".to_owned());
    let (universes, nonzero_channels, active_levels) = {
        let frames = state.frames.lock().expect("frame lock");
        let mut summaries = Vec::new();
        for (universe, frame) in frames.iter() {
            let values = frame
                .iter()
                .enumerate()
                .filter(|(_, value)| **value > 0)
                .map(|(index, value)| format!("{}={value}", index + 1))
                .collect::<Vec<_>>();
            if !values.is_empty() {
                let visible = values
                    .iter()
                    .take(16)
                    .cloned()
                    .collect::<Vec<_>>()
                    .join(", ");
                let more = if values.len() > 16 {
                    format!(" · +{} more", values.len() - 16)
                } else {
                    String::new()
                };
                summaries.push(format!("Universe {universe} · CH {visible}{more}"));
            }
        }
        (
            frames.len(),
            frames
                .values()
                .map(|frame| frame.iter().filter(|value| **value > 0).count())
                .sum::<usize>(),
            if summaries.is_empty() {
                "All channels at zero".to_owned()
            } else {
                summaries.join("<br>")
            },
        )
    };
    let requests = if requests.is_empty() {
        "<section class=\"empty\"><h2>No access request</h2><p>Return to DMXtract and choose Connect. This page will update automatically.</p></section>".to_owned()
    } else {
        requests
    };
    let status_class = if active { "active" } else { "stopped" };
    let status_label = if active {
        "OUTPUT ACTIVE"
    } else {
        "OUTPUT STOPPED"
    };
    let safety = if safety_unlocked {
        "Unlocked"
    } else {
        "Locked"
    };
    let heartbeat = if active {
        format!("{heartbeat_age} ms ago")
    } else {
        "Not active".to_owned()
    };
    let body = format!(
        r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="2"><title>DMXtract Bridge controls</title><style>
        :root{{color-scheme:dark;font-family:system-ui,sans-serif;background:#171310;color:#f4ede4}}*{{box-sizing:border-box}}body{{margin:0;padding:28px;background:linear-gradient(135deg,#171310,#241d18);min-height:100vh}}main{{max-width:760px;margin:auto}}header{{border-bottom:1px solid #70442f;padding-bottom:18px;margin-bottom:22px}}h1{{margin:0;color:#efaa38}}h2{{overflow-wrap:anywhere}}p{{color:#c9bdb2;line-height:1.5}}.status,.request,.empty{{background:#29231f;border:1px solid #70442f;border-radius:16px;padding:20px;margin:16px 0;box-shadow:0 10px 28px #0006}}.status.{status_class}{{border-color:#efaa38}}.eyebrow,.readout{{font:700 12px ui-monospace,monospace;letter-spacing:.12em;color:#efaa38}}.levels{{font:600 12px ui-monospace,monospace;color:#f0c679;line-height:1.6}}dl{{display:grid;grid-template-columns:minmax(120px,1fr) 2fr;gap:10px;margin:18px 0}}dt{{color:#9f9185}}dd{{margin:0;overflow-wrap:anywhere}}.actions{{display:flex;gap:12px;flex-wrap:wrap}}form{{margin:0}}button{{border:0;border-radius:11px;padding:12px 18px;font-weight:800;font-size:16px;cursor:pointer}}.allow{{background:#efaa38;color:#19120a}}.deny{{background:#53443a;color:#fff}}.blackout{{background:#b73532;color:#fff}}footer{{color:#8f8277;font-size:13px;margin-top:24px}}@media(max-width:560px){{body{{padding:16px}}dl{{grid-template-columns:1fr}}}}
        </style></head><body><main><header><h1>DMXtract Bridge</h1><p>Visible controls for the DMX helper running only on this computer.</p></header>
        <section class="status {status_class}"><p class="eyebrow">{status_label}</p><dl><dt>Controlled by</dt><dd>{controller}</dd><dt>Destination</dt><dd>{output}</dd><dt>Universes</dt><dd>{universes}</dd><dt>Non-zero channels</dt><dd>{nonzero_channels}</dd><dt>Active levels</dt><dd class="levels">{active_levels}</dd><dt>Safety ranges</dt><dd>{safety}</dd><dt>Last heartbeat</dt><dd>{heartbeat}</dd></dl>
        <form method="post" action="/v1/control/blackout"><input type="hidden" name="control_token" value="{control_token}"><button class="blackout" type="submit">Blackout and stop output</button></form></section>
        {requests}<footer>This page is served by the bridge at 127.0.0.1. It does not leave your computer.</footer></main></body></html>"#,
        controller = html_escape(&controller),
        output = html_escape(&output),
        control_token = html_escape(&state.control_token),
    );
    local_html(body)
}

async fn pair_status(
    State(state): State<Arc<BridgeState>>,
    Path(request_id): Path<String>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let mut pairs = state.pairs.lock().expect("pair lock");
    let pair = pairs
        .get(&request_id)
        .ok_or_else(|| ApiError::bad("That pairing request is no longer available."))?;
    require_matching_origin(&headers, &pair.origin)?;
    if pair.expires < Instant::now() {
        pairs.remove(&request_id);
        return Err(ApiError::bad("That pairing request expired."));
    }
    match &pair.decision {
        PairDecision::Pending => Ok(Json(json!({ "status": "pending" }))),
        PairDecision::Denied => Ok(Json(json!({ "status": "denied" }))),
        PairDecision::Approved(token) => {
            let token = token.clone();
            Ok(Json(
                json!({ "status": "approved", "token": token, "expiresWhenBridgeExits": true }),
            ))
        }
    }
}

async fn pair_approve(
    State(state): State<Arc<BridgeState>>,
    Path(request_id): Path<String>,
    Form(action): Form<ControlAction>,
) -> Result<Response, ApiError> {
    require_control_token(&state, &action)?;
    let mut pairs = state.pairs.lock().expect("pair lock");
    let pair = pairs
        .get_mut(&request_id)
        .ok_or_else(|| ApiError::bad("That pairing request is no longer available."))?;
    if pair.expires < Instant::now() {
        return Err(ApiError::bad("That pairing request expired."));
    }
    let token = random_token(32);
    state.sessions.lock().expect("session lock").insert(
        token.clone(),
        Session {
            origin: pair.origin.clone(),
            expires: Instant::now() + Duration::from_secs(12 * 60 * 60),
        },
    );
    pair.decision = PairDecision::Approved(token);
    Ok(local_html(message_page(
        "Access allowed",
        "Return to DMXtract. It will finish connecting automatically.",
    )))
}

async fn pair_deny(
    State(state): State<Arc<BridgeState>>,
    Path(request_id): Path<String>,
    Form(action): Form<ControlAction>,
) -> Result<Response, ApiError> {
    require_control_token(&state, &action)?;
    let mut pairs = state.pairs.lock().expect("pair lock");
    let pair = pairs
        .get_mut(&request_id)
        .ok_or_else(|| ApiError::bad("That pairing request is no longer available."))?;
    pair.decision = PairDecision::Denied;
    Ok(local_html(message_page(
        "Access denied",
        "No DMX control was granted. You can close this tab.",
    )))
}

async fn control_blackout(
    State(state): State<Arc<BridgeState>>,
    Form(action): Form<ControlAction>,
) -> Result<Response, ApiError> {
    require_control_token(&state, &action)?;
    state.blackout(true);
    *state.lease.lock().expect("lease lock") = None;
    *state.output.lock().expect("output lock") = None;
    Ok(local_html(message_page(
        "Output stopped",
        "Every tracked universe was sent a zero frame. You can close this tab.",
    )))
}

#[derive(Deserialize)]
struct ControlAction {
    control_token: String,
}

fn require_control_token(state: &BridgeState, action: &ControlAction) -> Result<(), ApiError> {
    if action.control_token != state.control_token {
        return Err(ApiError::unauthorized(
            "Open Bridge controls on this computer before approving or stopping output.",
        ));
    }
    Ok(())
}

fn local_html(body: String) -> Response {
    (
        [
            (header::CACHE_CONTROL, "no-store"),
            (
                header::CONTENT_SECURITY_POLICY,
                "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
            ),
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
        ],
        Html(body),
    )
        .into_response()
}

fn message_page(title: &str, message: &str) -> String {
    format!(
        r#"<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title><style>:root{{color-scheme:dark;font-family:system-ui,sans-serif;background:#171310;color:#f4ede4}}body{{display:grid;place-items:center;min-height:100vh;margin:0;padding:20px}}main{{max-width:560px;background:#29231f;border:1px solid #efaa38;border-radius:16px;padding:28px}}h1{{color:#efaa38}}p{{color:#c9bdb2;line-height:1.5}}</style></head><body><main><h1>{title}</h1><p>{message}</p></main></body></html>"#,
        title = html_escape(title),
        message = html_escape(message),
    )
}

fn html_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
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
            decision: PairDecision::Pending,
        },
    );
    // The pairing code must be visible for terminal builds. Do not print the
    // requesting origin or attach the code to structured logs.
    eprintln!("DMXTRACT_PAIRING\t{}", code);
    tracing::warn!("pairing requested; confirm the code shown in the bridge");
    Ok(Json(
        json!({ "requestId": request_id, "expiresInSeconds": 120, "controlsUrl": "http://127.0.0.1:46321/", "message": "Approve the requesting site in the visible Bridge controls." }),
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
    let mut pairs = state.pairs.lock().unwrap();
    let pending = pairs
        .get(&request.request_id)
        .ok_or_else(|| ApiError::bad("That pairing request is no longer available."))?;
    if pending.expires < Instant::now() || pending.code != request.code {
        return Err(ApiError::unauthorized(
            "The pairing code is incorrect or expired.",
        ));
    }
    let pending = pairs.remove(&request.request_id).expect("checked pair");
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

#[derive(Debug)]
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
    use axum::body::to_bytes;
    use axum::http::HeaderValue;

    #[test]
    fn claimed_pairing_origin_must_match_browser_header() {
        let mut headers = HeaderMap::new();
        headers.insert("origin", HeaderValue::from_static("https://evil.example"));
        assert!(require_matching_origin(&headers, "https://dmxtract.sho.run").is_err());
        assert!(require_matching_origin(&headers, "https://evil.example").is_ok());
    }

    #[tokio::test]
    async fn local_control_page_escapes_requesting_origin() {
        let state = Arc::new(BridgeState::new());
        state.pairs.lock().unwrap().insert(
            "request".to_owned(),
            PendingPair {
                origin: "https://example.test/<script>".to_owned(),
                code: "123456".to_owned(),
                expires: Instant::now() + Duration::from_secs(120),
                decision: PairDecision::Pending,
            },
        );

        let response = control_page(State(state)).await;
        let body = to_bytes(response.into_body(), usize::MAX).await.unwrap();
        let html = String::from_utf8(body.to_vec()).unwrap();
        assert!(html.contains("https://example.test/&lt;script&gt;"));
        assert!(!html.contains("https://example.test/<script>"));
    }

    #[tokio::test]
    async fn approval_requires_the_secret_from_the_local_control_page() {
        let state = Arc::new(BridgeState::new());
        state.pairs.lock().unwrap().insert(
            "request".to_owned(),
            PendingPair {
                origin: "https://dmxtract.sho.run".to_owned(),
                code: "123456".to_owned(),
                expires: Instant::now() + Duration::from_secs(120),
                decision: PairDecision::Pending,
            },
        );

        let denied = pair_approve(
            State(state.clone()),
            Path("request".to_owned()),
            Form(ControlAction {
                control_token: "known-to-the-requesting-site".to_owned(),
            }),
        )
        .await;
        assert_eq!(denied.unwrap_err().status, StatusCode::UNAUTHORIZED);
        assert!(state.sessions.lock().unwrap().is_empty());

        pair_approve(
            State(state.clone()),
            Path("request".to_owned()),
            Form(ControlAction {
                control_token: state.control_token.clone(),
            }),
        )
        .await
        .unwrap();
        assert_eq!(state.sessions.lock().unwrap().len(), 1);

        let mut wrong_origin = HeaderMap::new();
        wrong_origin.insert("origin", HeaderValue::from_static("https://evil.example"));
        let denied = pair_status(
            State(state.clone()),
            Path("request".to_owned()),
            wrong_origin,
        )
        .await;
        assert_eq!(denied.unwrap_err().status, StatusCode::UNAUTHORIZED);

        let mut matching_origin = HeaderMap::new();
        matching_origin.insert(
            "origin",
            HeaderValue::from_static("https://dmxtract.sho.run"),
        );
        let Json(approved) = pair_status(State(state), Path("request".to_owned()), matching_origin)
            .await
            .unwrap();
        assert_eq!(approved["status"], "approved");
        assert!(
            approved["token"]
                .as_str()
                .is_some_and(|token| !token.is_empty())
        );
    }
}
