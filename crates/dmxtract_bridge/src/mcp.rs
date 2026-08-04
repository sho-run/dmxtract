use std::collections::HashMap;

use base64::{Engine, engine::general_purpose::STANDARD};
use dmxtract_core::{export_gdtf_bytes, export_ofl_json, validate_fixture_json};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::transport::{self, OutputConfig, OutputDriver};

pub async fn serve_stdio() -> Result<(), Box<dyn std::error::Error>> {
    let stdin = tokio::io::stdin();
    let mut lines = BufReader::new(stdin).lines();
    let mut stdout = tokio::io::stdout();
    let mut hardware = McpHardware::default();
    while let Some(line) = lines.next_line().await? {
        let request: Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            Err(_) => continue,
        };
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        let response = match request.get("method").and_then(Value::as_str).unwrap_or("") {
            "initialize" => {
                json!({"jsonrpc":"2.0","id":id,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"dmxtract-bridge","version":env!("CARGO_PKG_VERSION")}}})
            }
            "tools/list" => json!({"jsonrpc":"2.0","id":id,"result":{"tools":tools()}}),
            "tools/call" => call_tool(
                id,
                request.get("params").cloned().unwrap_or_default(),
                &mut hardware,
            ),
            _ => {
                json!({"jsonrpc":"2.0","id":id,"error":{"code":-32601,"message":"Method not found"}})
            }
        };
        stdout.write_all(response.to_string().as_bytes()).await?;
        stdout.write_all(b"\n").await?;
        stdout.flush().await?;
    }
    hardware.blackout(true);
    Ok(())
}

fn tools() -> Value {
    let fixture_schema =
        json!({"type":"object","properties":{"fixture":{"type":"object"}},"required":["fixture"]});
    let mut tools = vec![
        json!({"name":"fixture_validate","description":"Validate canonical dmxtract.fixture/v1 JSON.","inputSchema":fixture_schema}),
        json!({"name":"fixture_export_ofl","description":"Export canonical fixture JSON as an OFL-compatible fixture.","inputSchema":fixture_schema}),
        json!({"name":"fixture_export_gdtf","description":"Export canonical fixture JSON as a base64 GDTF 1.2 ZIP.","inputSchema":fixture_schema}),
        json!({"name":"bridge_status","description":"Report bridge capabilities and hardware-approval state.","inputSchema":{"type":"object"}}),
        json!({"name":"bridge_list_outputs","description":"List serial outputs visible to the local bridge.","inputSchema":{"type":"object"}}),
    ];
    if hardware_approved() {
        tools.extend([
            json!({"name":"bridge_begin_test","description":"Begin approved hardware output at zero.","inputSchema":{"type":"object","required":["output"],"properties":{"output":{"type":"object"},"unlockRisky":{"type":"boolean","default":false}}}}),
            json!({"name":"bridge_set_channels","description":"Set 1-based DMX channel values on an approved output.","inputSchema":{"type":"object","required":["channels"],"properties":{"universe":{"type":"integer","minimum":1,"default":1},"risky":{"type":"boolean","default":false},"channels":{"type":"array","items":{"type":"object","required":["channel","value"],"properties":{"channel":{"type":"integer","minimum":1,"maximum":512},"value":{"type":"integer","minimum":0,"maximum":255}}}}}}}),
            json!({"name":"bridge_blackout","description":"Immediately send zero to every active universe.","inputSchema":{"type":"object"}}),
            json!({"name":"bridge_end_test","description":"Black out and release hardware output.","inputSchema":{"type":"object"}}),
        ]);
    }
    Value::Array(tools)
}

fn call_tool(id: Value, params: Value, hardware: &mut McpHardware) -> Value {
    let name = params.get("name").and_then(Value::as_str).unwrap_or("");
    let arguments = params.get("arguments").cloned().unwrap_or_default();
    let result = match name {
        "fixture_validate" => fixture_string(&arguments).and_then(|input| {
            validate_fixture_json(&input).map_err(|error| error.to_string())
        }),
        "fixture_export_ofl" => fixture_string(&arguments)
            .and_then(|input| export_ofl_json(&input).map_err(|error| error.to_string())),
        "fixture_export_gdtf" => fixture_string(&arguments).and_then(|input| {
            export_gdtf_bytes(&input)
                .map(|bytes| STANDARD.encode(bytes))
                .map_err(|error| error.to_string())
        }),
        "bridge_status" => Ok(json!({"running":true,"loopbackOnly":true,"hardwareMcpApproved":hardware_approved(),"outputActive":hardware.output.is_some()}).to_string()),
        "bridge_list_outputs" => {
            Ok(serde_json::to_string(&transport::serial_outputs()).expect("serial outputs serialize"))
        }
        "bridge_begin_test" if hardware_approved() => hardware.begin(&arguments),
        "bridge_set_channels" if hardware_approved() => hardware.set_channels(&arguments),
        "bridge_blackout" if hardware_approved() => {
            hardware.blackout(false);
            Ok(json!({"ok":true}).to_string())
        }
        "bridge_end_test" if hardware_approved() => {
            hardware.blackout(true);
            hardware.output = None;
            Ok(json!({"ok":true}).to_string())
        }
        _ => Err(format!("Unknown or unapproved tool: {name}")),
    };
    match result {
        Ok(text) => {
            json!({"jsonrpc":"2.0","id":id,"result":{"content":[{"type":"text","text":text}]}})
        }
        Err(message) => {
            json!({"jsonrpc":"2.0","id":id,"result":{"isError":true,"content":[{"type":"text","text":message}]}})
        }
    }
}

#[derive(Default)]
struct McpHardware {
    output: Option<Box<dyn OutputDriver>>,
    frames: HashMap<u16, [u8; 512]>,
    risky_unlocked: bool,
}

impl McpHardware {
    fn begin(&mut self, arguments: &Value) -> Result<String, String> {
        self.blackout(true);
        let config: OutputConfig = serde_json::from_value(
            arguments
                .get("output")
                .cloned()
                .ok_or_else(|| "Pass an output configuration.".to_owned())?,
        )
        .map_err(|error| format!("Invalid output configuration: {error}"))?;
        let mut output = transport::open_output(&config).map_err(|error| error.to_string())?;
        output
            .send(1, &[0; 512], false)
            .map_err(|error| error.to_string())?;
        let label = output.label();
        self.output = Some(output);
        self.frames.insert(1, [0; 512]);
        self.risky_unlocked = arguments
            .get("unlockRisky")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        Ok(json!({"ok":true,"output":label,"startsBlackedOut":true}).to_string())
    }

    fn set_channels(&mut self, arguments: &Value) -> Result<String, String> {
        let universe = arguments
            .get("universe")
            .and_then(Value::as_u64)
            .unwrap_or(1);
        let universe = u16::try_from(universe).map_err(|_| "Universe is too large.".to_owned())?;
        let risky = arguments
            .get("risky")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        if risky && !self.risky_unlocked {
            return Err("Risky output is locked for this MCP test.".to_owned());
        }
        let channels = arguments
            .get("channels")
            .and_then(Value::as_array)
            .ok_or_else(|| "Pass a channels array.".to_owned())?;
        let frame = self.frames.entry(universe).or_insert([0; 512]);
        for item in channels {
            let channel = item
                .get("channel")
                .and_then(Value::as_u64)
                .ok_or_else(|| "Each channel needs a 1-based channel number.".to_owned())?;
            let value = item
                .get("value")
                .and_then(Value::as_u64)
                .ok_or_else(|| "Each channel needs a value from 0 to 255.".to_owned())?;
            if !(1..=512).contains(&channel) || value > 255 {
                return Err("Channel must be 1-512 and value must be 0-255.".to_owned());
            }
            frame[channel as usize - 1] = value as u8;
        }
        self.output
            .as_mut()
            .ok_or_else(|| "Begin a test before setting channels.".to_owned())?
            .send(universe, frame, false)
            .map_err(|error| error.to_string())?;
        Ok(json!({"ok":true}).to_string())
    }

    fn blackout(&mut self, terminated: bool) {
        if let Some(output) = self.output.as_mut() {
            for (universe, frame) in &mut self.frames {
                frame.fill(0);
                let _ = output.send(*universe, frame, terminated);
            }
        }
    }
}

impl Drop for McpHardware {
    fn drop(&mut self) {
        self.blackout(true);
    }
}

fn fixture_string(arguments: &Value) -> Result<String, String> {
    arguments
        .get("fixture")
        .map(Value::to_string)
        .ok_or_else(|| "Pass a fixture object.".to_owned())
}

fn hardware_approved() -> bool {
    std::env::var("DMXTRACT_MCP_HARDWARE").as_deref() == Ok("1")
}
