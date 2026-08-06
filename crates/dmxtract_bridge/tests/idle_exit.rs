use std::{
    io::Read,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

/// Spawns the real bridge binary with a near-zero idle timeout and no
/// activity, and asserts it exits on its own well within a generous bound.
/// This exercises the actual CLI-flag wiring and process::exit path, not
/// just the pure decision logic covered by unit tests in src/api.rs.
#[test]
fn bridge_exits_on_its_own_when_idle_and_untouched() {
    let binary = env!("CARGO_BIN_EXE_dmxtract_bridge");
    // Bind to an ephemeral bridge port so this can't collide with a
    // developer's already-running bridge on the default port.
    let mut child = Command::new(binary)
        .args(["--idle-timeout", "1"])
        .env("DMXTRACT_BRIDGE_PORT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn bridge binary");

    let deadline = Instant::now() + Duration::from_secs(20);
    let status = loop {
        if let Some(status) = child.try_wait().expect("poll child status") {
            break status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            panic!("bridge did not self-exit within 20s of a 1s idle timeout");
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    assert!(status.success(), "idle self-exit should exit cleanly");
}

/// A 0-second idle timeout disables self-exit entirely; the process must
/// still be running after a window well past what a positive timeout would
/// have allowed.
#[test]
fn idle_timeout_zero_keeps_the_bridge_running() {
    let binary = env!("CARGO_BIN_EXE_dmxtract_bridge");
    let mut child = Command::new(binary)
        .args(["--idle-timeout", "0"])
        .env("DMXTRACT_BRIDGE_PORT", "0")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn bridge binary");

    std::thread::sleep(Duration::from_secs(3));
    let still_running = child.try_wait().expect("poll child status").is_none();
    let _ = child.kill();
    let mut stderr = String::new();
    if let Some(mut handle) = child.stderr.take() {
        let _ = handle.read_to_string(&mut stderr);
    }
    assert!(
        still_running,
        "idle-timeout=0 must disable self-exit; stderr: {stderr}"
    );
}
