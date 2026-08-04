use std::{
    io::Write,
    process::{Command, Stdio},
};

#[test]
fn bridge_binary_exposes_mcp_tools() {
    let binary = env!("CARGO_BIN_EXE_dmxtract_bridge");
    let mut child = Command::new(binary)
        .arg("--mcp")
        .env("DMXTRACT_FIXTURE_LOOKUP_TOKEN", "must-not-escape")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    stdin
        .write_all(b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}\n")
        .unwrap();
    drop(stdin);
    let output = child.wait_with_output().unwrap();
    let body = String::from_utf8(output.stdout).unwrap();
    let logs = String::from_utf8(output.stderr).unwrap();
    assert!(body.contains("fixture_validate"));
    assert!(!body.contains("bridge_blackout"));
    assert!(!body.contains("must-not-escape"));
    assert!(!logs.contains("must-not-escape"));
}

#[test]
fn approved_mcp_exposes_and_runs_preview_hardware_tools() {
    let binary = env!("CARGO_BIN_EXE_dmxtract_bridge");
    let mut child = Command::new(binary)
        .arg("--mcp")
        .env("DMXTRACT_MCP_HARDWARE", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    stdin.write_all(b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}\n{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"bridge_begin_test\",\"arguments\":{\"output\":{\"kind\":\"preview\"}}}}\n{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"bridge_set_channels\",\"arguments\":{\"channels\":[{\"channel\":512,\"value\":255}]}}}\n").unwrap();
    drop(stdin);
    let output = child.wait_with_output().unwrap();
    let body = String::from_utf8(output.stdout).unwrap();
    assert!(body.contains("bridge_blackout"));
    assert!(body.contains("startsBlackedOut"));
    assert!(!body.contains("isError"));
}
