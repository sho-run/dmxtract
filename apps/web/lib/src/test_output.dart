// Transport-neutral contract for driving live DMX test output from the Test
// screen (see screens/test_light.dart). Three implementations exist behind
// this interface:
//
//  - [BridgeTestOutput] below, a thin adapter over the existing loopback
//    `BridgeClient` (bridge_client.dart, unchanged).
//  - The in-page Web Serial transport (`webserial_dmx.dart`,
//    `WebSerialDmxTransport`) — zero-install, Chrome/Edge desktop only.
//  - [VirtualTestOutput] below — no real hardware, works in every browser.
//
// All three share the same begin/setChannel/unlock/blackout/end lifecycle so
// the Test screen does not need to know which one is driving the light.

import 'dart:async';
import 'dart:typed_data';

import 'bridge_client.dart';
import 'webserial_frame.dart' show assertRiskyAllowed, assertValidChannelValue;

/// Live connectivity state for a [TestOutput] transport.
enum TestOutputStatus {
  /// No live connection. The initial state, and the state after [end].
  disconnected,

  /// [TestOutput.begin] is in progress.
  connecting,

  /// Output is live: [TestOutput.setChannel] calls are being sent.
  connected,

  /// Output is live but paused because the page is hidden and the browser
  /// throttles/suspends background timers. Only the Web Serial transport can
  /// reach this state — it has no server-side loop to keep sending on its
  /// behalf while the tab is backgrounded.
  blockedHidden,
}

/// Display-only description of the device/output behind a [TestOutput],
/// once known (e.g. after [TestOutput.begin] resolves).
class TestOutputDevice {
  const TestOutputDevice({
    required this.label,
    this.usbVendorId,
    this.usbProductId,
  });

  /// Human-readable label, e.g. "FTDI FT232R (direct)" or "Bridge: Open DMX
  /// /dev/cu.usbserial".
  final String label;

  /// USB vendor id, when the transport can see it (Web Serial only).
  final int? usbVendorId;

  /// USB product id, when the transport can see it (Web Serial only).
  final int? usbProductId;
}

/// Transport-neutral contract for live DMX test output.
///
/// Lifecycle: [begin] once, then any number of [setChannel] calls (and
/// [unlock] at most once, to allow risky-range values), then [blackout]
/// and/or [end]. Implementations must zero-start: the very first frame
/// written to the wire after [begin] resolves is all zeros, before any
/// caller-supplied channel value is honored.
abstract class TestOutput {
  /// Description of the connected device/output, once [begin] has resolved.
  TestOutputDevice? get device;

  /// True once [begin] has resolved and [end] has not yet been called.
  bool get isActive;

  /// True once [unlock] has been called for the current session.
  bool get riskyUnlocked;

  /// Current connectivity state. Starts at [TestOutputStatus.disconnected].
  TestOutputStatus get status;

  /// Fires whenever [status] changes.
  Stream<TestOutputStatus> get statusChanges;

  /// Starts output. Resolves once a live connection exists and the first
  /// (all-zero) frame has been written. Throws on failure; callers must not
  /// treat [isActive] as true unless this completes normally.
  Future<void> begin();

  /// Sets channel [channel] (1-512) to [value] (0-255) in the live frame.
  ///
  /// Pass `risky: true` for a value inside a non-"normal" safety range
  /// (strobe, lamp strike, reset, maintenance). Implementations must reject
  /// risky values until [unlock] has been called for this session — see
  /// crates/dmxtract_bridge/src/api.rs `set_channels` for the rule this
  /// mirrors.
  Future<void> setChannel(int channel, int value, {bool risky = false});

  /// Allows risky-range values for the remainder of this session.
  Future<void> unlock();

  /// Immediately zeros every channel without ending the session.
  Future<void> blackout();

  /// Zeros output and releases the underlying connection. Safe to call more
  /// than once.
  Future<void> end();
}

/// Adapts the existing loopback [BridgeClient] to [TestOutput]. This is a
/// thin wrapper only: it does not change bridge_client.dart's request or
/// response shapes, and it relies entirely on the Bridge server to enforce
/// the risky-range lock (see [TestOutput.setChannel]) — the server rejects
/// `risky: true` writes before `unlock` with a 423, which surfaces here as a
/// thrown [Exception] from [BridgeClient].
class BridgeTestOutput implements TestOutput {
  BridgeTestOutput(
    this._bridge, {
    required String origin,
    required Map<String, Object?> outputConfig,
    this.universe = 1,
    Duration heartbeatInterval = const Duration(milliseconds: 500),
  }) : _origin = origin,
       _outputConfig = outputConfig,
       _heartbeatInterval = heartbeatInterval;

  final BridgeClient _bridge;
  final String _origin;
  final Map<String, Object?> _outputConfig;
  final int universe;
  final Duration _heartbeatInterval;
  final StreamController<TestOutputStatus> _statusController =
      StreamController<TestOutputStatus>.broadcast();

  Timer? _heartbeat;
  TestOutputDevice? _device;
  TestOutputStatus _status = TestOutputStatus.disconnected;
  bool _riskyUnlocked = false;

  @override
  TestOutputDevice? get device => _device;
  @override
  bool get isActive => _status == TestOutputStatus.connected;
  @override
  bool get riskyUnlocked => _riskyUnlocked;
  @override
  TestOutputStatus get status => _status;
  @override
  Stream<TestOutputStatus> get statusChanges => _statusController.stream;

  @override
  Future<void> begin() async {
    _setStatus(TestOutputStatus.connecting);
    try {
      final label = await _bridge.begin(_origin, _outputConfig);
      _device = TestOutputDevice(label: label);
      _riskyUnlocked = false;
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
        unawaited(_bridge.heartbeat().catchError((_) => end()));
      });
      _setStatus(TestOutputStatus.connected);
    } catch (_) {
      _setStatus(TestOutputStatus.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> setChannel(int channel, int value, {bool risky = false}) =>
      _bridge.setChannel(channel, value, universe: universe, risky: risky);

  @override
  Future<void> unlock() async {
    await _bridge.unlock();
    _riskyUnlocked = true;
  }

  @override
  Future<void> blackout() => _bridge.blackout();

  @override
  Future<void> end() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    try {
      await _bridge.blackout();
      await _bridge.end();
    } finally {
      _riskyUnlocked = false;
      _setStatus(TestOutputStatus.disconnected);
    }
  }

  void _setStatus(TestOutputStatus value) {
    _status = value;
    _statusController.add(value);
  }
}

/// Browser-local virtual output for the "Just checking the numbers" card
/// (see screens/test_light.dart): no real hardware, no bridge, no
/// navigator.serial — every channel write only updates an in-memory buffer.
/// Works in every browser, unconditionally, so it is always available as a
/// fallback even when neither Web Serial nor the Bridge is.
///
/// Reuses the same risky-range/channel-bounds rules as the Web Serial
/// transport (`webserial_frame.dart`) rather than re-deriving them, so a
/// value that would be rejected on real hardware is rejected here too.
class VirtualTestOutput implements TestOutput {
  final Uint8List _channels = Uint8List(512);
  bool _riskyUnlocked = false;
  TestOutputDevice? _device;
  TestOutputStatus _status = TestOutputStatus.disconnected;
  final StreamController<TestOutputStatus> _statusController =
      StreamController<TestOutputStatus>.broadcast();

  @override
  TestOutputDevice? get device => _device;
  @override
  bool get isActive => _status == TestOutputStatus.connected;
  @override
  bool get riskyUnlocked => _riskyUnlocked;
  @override
  TestOutputStatus get status => _status;
  @override
  Stream<TestOutputStatus> get statusChanges => _statusController.stream;

  /// Snapshot of the current 512-channel virtual frame, for a preview panel
  /// to render (see screens/test_light.dart).
  Uint8List get currentFrame => Uint8List.fromList(_channels);

  @override
  Future<void> begin() async {
    _setStatus(TestOutputStatus.connecting);
    _channels.fillRange(0, _channels.length, 0); // zero-start
    _riskyUnlocked = false;
    _device = const TestOutputDevice(label: 'Preview only · no hardware');
    _setStatus(TestOutputStatus.connected);
  }

  @override
  Future<void> setChannel(int channel, int value, {bool risky = false}) async {
    assertValidChannelValue(channel, value);
    assertRiskyAllowed(risky: risky, unlocked: _riskyUnlocked);
    _channels[channel - 1] = value;
  }

  @override
  Future<void> unlock() async {
    _riskyUnlocked = true;
  }

  @override
  Future<void> blackout() async {
    _channels.fillRange(0, _channels.length, 0);
  }

  @override
  Future<void> end() async {
    _channels.fillRange(0, _channels.length, 0);
    _riskyUnlocked = false;
    _setStatus(TestOutputStatus.disconnected);
  }

  void _setStatus(TestOutputStatus value) {
    _status = value;
    _statusController.add(value);
  }
}
