// In-page Web Serial DMX output transport: lets a user test their light
// through a USB-DMX cable with zero installed software, straight from
// Chrome/Edge desktop. See test_output.dart for the transport-neutral
// contract this implements, and webserial_frame.dart for the pure protocol
// logic (frame encoding, risky-range gating, zero-start buffer) that this
// file drives.
//
// `package:web` does not generate bindings for the Serial API — it isn't
// part of the stable WebIDL corpus the package is built from — so the
// `_Serial`/`_SerialPort`/`_SerialPortInfo` extension types below are
// hand-written against the W3C Serial API spec
// (https://wicg.github.io/serial/). Everything else (streams, wake lock,
// document/window events) already has bindings in `package:web`.

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'test_output.dart';
import 'webserial_frame.dart';

// ---------------------------------------------------------------------------
// Minimal Web Serial API bindings.
// ---------------------------------------------------------------------------

extension type _Serial._(JSObject _) implements JSObject {
  external JSPromise<JSArray<_SerialPort>> getPorts();
  external JSPromise<_SerialPort> requestPort([JSObject options]);
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _SerialPort._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(JSObject options);
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> forget();
  external JSPromise<JSAny?> setSignals(JSObject signals);
  external _SerialPortInfo getInfo();
  external web.ReadableStream? get readable;
  external web.WritableStream? get writable;
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

extension type _SerialPortInfo._(JSObject _) implements JSObject {
  external int? get usbVendorId;
  external int? get usbProductId;
}

@JS('navigator.serial')
external _Serial? get _navigatorSerial;

/// True when this browser exposes `navigator.serial` at all. Web Serial is
/// Chromium-only (Chrome/Edge/Opera desktop) — Firefox and Safari never set
/// this.
bool get isWebSerialSupported => _navigatorSerial != null;

const List<int> _knownVendorIds = [
  0x0403, // FTDI
  0x1a86, // CH340
  0x10c4, // CP210x
];

JSObject _mapToJs(Map<String, Object?> value) => value.jsify() as JSObject;

// ---------------------------------------------------------------------------
// Transport.
// ---------------------------------------------------------------------------

/// Drives live DMX output over a USB-DMX cable via the Web Serial API.
///
/// Usage: call [requestPort] (or, if it returns false because the user
/// canceled or no device matched the FTDI/CH340/CP210x filter,
/// [requestAnyPort] as a "show all devices" retry) from a user gesture such
/// as a button press — Chrome requires this. Then call [begin] as normal
/// [TestOutput] usage.
class WebSerialDmxTransport implements TestOutput {
  static bool get isSupported => isWebSerialSupported;

  /// Wall-clock floor between successive frame writes. DMX widgets expect a
  /// steady refresh; this also keeps the widget's own watchdog (if any) fed.
  static const Duration _sendFloor = Duration(milliseconds: 30);

  /// How long to wait for a GET_WIDGET_PARAMS reply before assuming the
  /// widget is a silent, direct/Open DMX cable.
  static const Duration _probeTimeout = Duration(milliseconds: 300);

  _SerialPort? _port;
  web.WritableStreamDefaultWriter? _writer;
  WidgetMode? _mode;
  final DmxFrameState _frame = DmxFrameState();
  bool _riskyUnlocked = false;

  Timer? _sendTimer;
  DateTime _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Chains every [_writeChannels] call onto the previous one, so a
  /// break-then-data sequence can never interleave with another concurrent
  /// caller's break-then-data sequence. `_writeChannels` has several
  /// concurrent callers (the send loop, `blackout`, `end`) and the break
  /// signal (a control transfer, effective immediately) is otherwise
  /// unsynchronized with the queued `WritableStream` write that follows it.
  Future<void> _writeLock = Future<void>.value();

  web.WakeLockSentinel? _wakeLockSentinel;
  JSFunction? _visibilityListener;
  JSFunction? _beforeUnloadListener;
  JSFunction? _portDisconnectListener;
  JSFunction? _serialConnectListener;

  TestOutputDevice? _device;
  TestOutputStatus _status = TestOutputStatus.disconnected;
  final StreamController<TestOutputStatus> _statusController =
      StreamController<TestOutputStatus>.broadcast();

  @override
  TestOutputDevice? get device => _device;
  @override
  bool get isActive =>
      _status == TestOutputStatus.connected ||
      _status == TestOutputStatus.blockedHidden;
  @override
  bool get riskyUnlocked => _riskyUnlocked;
  @override
  TestOutputStatus get status => _status;
  @override
  Stream<TestOutputStatus> get statusChanges => _statusController.stream;

  /// Widget protocol detected during [begin] (buffered widget vs. bare
  /// direct/Open DMX cable). Null until [begin] has run once.
  WidgetMode? get widgetMode => _mode;

  /// True once a device has been chosen via [requestPort]/[requestAnyPort]
  /// or reused via [useGrantedPort].
  bool get hasSelectedPort => _port != null;

  /// Snapshot of the 512-channel frame currently being written to the wire,
  /// for the transparency/frame-inspector panel on the Test screen (see
  /// screens/test_light.dart). Reflects [setChannel] calls immediately —
  /// it does not wait for the next send tick.
  Uint8List get currentFrame => _frame.snapshot();

  /// True if the browser already has at least one previously granted port
  /// matching a known USB-DMX chipset (FTDI/CH340/CP210x) that can be
  /// reused without prompting the user again. Backs the "your cable from
  /// last time is ready" fast path on the Test screen (see
  /// screens/test_light.dart) — check this before offering [requestPort].
  /// Filtered by vendor id so a port this origin was granted for an
  /// unrelated device (e.g. an Arduino, from some other web tool) never
  /// counts as "your cable" here.
  static Future<bool> hasGrantedPort() async {
    final serial = _navigatorSerial;
    if (serial == null) return false;
    final ports = (await serial.getPorts().toDart).toDart;
    return ports.any(_isKnownDmxVendor);
  }

  /// Selects a previously granted port matching a known USB-DMX chipset
  /// without prompting the user again, for the "your cable from last time
  /// is ready" fast path. Returns false if there is nothing to reuse —
  /// offer [requestPort] instead. See [hasGrantedPort] for why this is
  /// vendor-filtered rather than reusing whatever `getPorts()` happens to
  /// return first (the Serial API specifies no ordering there).
  Future<bool> useGrantedPort() async {
    final serial = _navigatorSerial;
    if (serial == null) return false;
    final ports = (await serial.getPorts().toDart).toDart;
    for (final candidate in ports) {
      if (_isKnownDmxVendor(candidate)) {
        _port = candidate;
        return true;
      }
    }
    return false;
  }

  static bool _isKnownDmxVendor(_SerialPort port) {
    final vendorId = port.getInfo().usbVendorId;
    return vendorId != null && _knownVendorIds.contains(vendorId);
  }

  /// Opens the browser's device picker filtered to the common USB-DMX
  /// chipsets (FTDI, CH340, CP210x). Must be called from a user gesture.
  /// Returns false if the user canceled the picker or no matching device was
  /// available — offer [requestAnyPort] next in that case.
  Future<bool> requestPort() => _requestPort(
    _mapToJs({
      'filters': [
        for (final vendorId in _knownVendorIds) {'usbVendorId': vendorId},
      ],
    }),
  );

  /// Retries the device picker with no vendor/product filter, for widgets
  /// not covered by the FTDI/CH340/CP210x allowlist ("show all devices").
  /// Must be called from a user gesture.
  Future<bool> requestAnyPort() => _requestPort(null);

  Future<bool> _requestPort(JSObject? filterOptions) async {
    final serial = _navigatorSerial;
    if (serial == null) {
      throw StateError('Web Serial is not supported in this browser.');
    }
    try {
      _port = filterOptions == null
          ? await serial.requestPort().toDart
          : await serial.requestPort(filterOptions).toDart;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> begin() async {
    final port = _port;
    if (port == null) {
      throw StateError(
        'Call requestPort() (or requestAnyPort()) before begin().',
      );
    }
    _setStatus(TestOutputStatus.connecting);
    try {
      await port
          .open(
            _mapToJs({
              'baudRate': 250000,
              'dataBits': 8,
              'stopBits': 2,
              'parity': 'none',
            }),
          )
          .toDart;
      final writable = port.writable;
      if (writable == null) throw StateError('Port has no writable stream.');
      final writer = writable.getWriter();
      _writer = writer;
      // Provisional zero-start, before anything else touches the wire: on a
      // bare Open DMX/FTDI cable, the widget-detection probe below would
      // otherwise be the first bytes ever sent — non-zero data, with no
      // break, on a line that might already be attached to a fixture. A
      // buffered widget's firmware waits for a 0x7E-prefixed packet before
      // acting on anything, so an all-zero body is inert for it too.
      await port.setSignals(_mapToJs({'break': true})).toDart;
      await port.setSignals(_mapToJs({'break': false})).toDart;
      await writer.write(encodeDirectFrame(zeroChannelFrame()).toJS).toDart;
      _mode = await _detectWidgetMode(port);
      // Zero-start: write the all-zero frame, now correctly encoded for the
      // detected widget mode, before marking the buffer live, so no
      // caller-supplied channel value can reach the wire first.
      await _writeChannels(zeroChannelFrame());
      _frame.goLive();
      _lastSendAt = DateTime.now();
      _device = _describeDevice(port);
      await _acquireWakeLock();
      _attachListeners(port);
      _setStatus(TestOutputStatus.connected);
      _scheduleSend();
    } catch (error) {
      await _releaseConnection();
      _setStatus(TestOutputStatus.disconnected);
      rethrow;
    }
  }

  @override
  Future<void> setChannel(int channel, int value, {bool risky = false}) async {
    // Mirrors crates/dmxtract_bridge/src/api.rs `set_channels`: reject risky
    // values until unlock() has been called for this session.
    assertRiskyAllowed(risky: risky, unlocked: _riskyUnlocked);
    _frame.setChannel(channel, value);
    // The continuous send loop (see _scheduleSend) picks up the new value on
    // its next tick, within _sendFloor.
  }

  @override
  Future<void> unlock() async {
    _riskyUnlocked = true;
  }

  @override
  Future<void> blackout() async {
    _frame.zeroAll();
    for (final frame in blackoutFrames()) {
      await _writeChannels(frame);
    }
  }

  @override
  Future<void> end() async {
    // Cleanup runs unconditionally, even when _status is already
    // disconnected: a Web Serial session that dropped to `disconnected`
    // (cable unplugged) still holds a live port, document listeners, and an
    // armed reconnect listener — an early return here on status alone used
    // to leave all of that behind, since every UI teardown path gates
    // calling end() on `isActive`/`outputActive`, which is false in exactly
    // that state. `_releaseConnection` and `_cancelReconnectListener` are
    // themselves idempotent, so calling this more than once stays safe per
    // the TestOutput.end contract.
    if (_status != TestOutputStatus.disconnected) {
      try {
        await blackout();
      } catch (_) {
        // Best effort — still tear down the connection below.
      }
    }
    await _releaseConnection();
    _frame.reset();
    _riskyUnlocked = false;
    _setStatus(TestOutputStatus.disconnected);
  }

  /// Revokes the browser's remembered permission for the selected port
  /// (`SerialPort.forget()`). Call [end] first if output is live.
  Future<void> revokeAccess() async {
    final port = _port;
    if (port == null) return;
    try {
      await port.forget().toDart;
    } catch (_) {
      // Forget is best-effort; nothing else to do if it fails.
    }
    _port = null;
    _device = null;
  }

  // -- widget detection -------------------------------------------------

  /// Probes for a buffered widget, retrying once before falling back to
  /// direct/Open DMX: a real widget's reply can be lost to line noise on
  /// power-up, and a single dropped probe shouldn't misclassify the cable.
  Future<WidgetMode> _detectWidgetMode(_SerialPort port) async {
    final first = await _probeWidgetMode(port);
    if (first == WidgetMode.buffered) return first;
    return _probeWidgetMode(port);
  }

  Future<WidgetMode> _probeWidgetMode(_SerialPort port) async {
    final writer = _writer;
    final readable = port.readable;
    if (writer == null || readable == null) return WidgetMode.direct;
    await writer.write(enttecGetWidgetParamsRequest().toJS).toDart;
    final reader = readable.getReader() as web.ReadableStreamDefaultReader;
    // A serial read can return the reply split across arbitrarily many
    // chunks (even one byte at a time) — accumulate until detectWidgetMode
    // sees a plausible terminator or the probe timeout runs out, rather
    // than judging widget-vs-direct from whatever the first single read
    // happened to contain.
    final buffer = <int>[];
    try {
      final deadline = DateTime.now().add(_probeTimeout);
      while (true) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) break;
        final result = await reader.read().toDart.timeout(remaining);
        final raw = result.value;
        if (raw != null) buffer.addAll((raw as JSUint8Array).toDart);
        if (result.done) break;
        // Stop as soon as the declared body length (header bytes 2-3, per
        // the Enttec framing detectWidgetMode validates) is satisfied,
        // rather than always waiting out the full probe timeout.
        if (buffer.length >= 4) {
          final dataLength = buffer[2] | (buffer[3] << 8);
          if (buffer.length >= 4 + dataLength + 1) break;
        }
      }
    } catch (_) {
      // Timeout or read error: whatever was accumulated (if anything)
      // still goes through detectWidgetMode's format check below.
    } finally {
      reader.releaseLock();
    }
    return detectWidgetMode(buffer);
  }

  TestOutputDevice _describeDevice(_SerialPort port) {
    final info = port.getInfo();
    final vendorId = info.usbVendorId;
    final productId = info.usbProductId;
    final chip = switch (vendorId) {
      0x0403 => 'FTDI',
      0x1a86 => 'CH340',
      0x10c4 => 'CP210x',
      _ => 'USB-serial',
    };
    final modeLabel = _mode == WidgetMode.buffered
        ? 'buffered'
        : 'direct/Open DMX';
    final idLabel = vendorId != null && productId != null
        ? ' (${vendorId.toRadixString(16).padLeft(4, '0')}:'
              '${productId.toRadixString(16).padLeft(4, '0')})'
        : '';
    return TestOutputDevice(
      label: '$chip$idLabel · $modeLabel',
      usbVendorId: vendorId,
      usbProductId: productId,
    );
  }

  // -- writing ------------------------------------------------------------

  Future<void> _writeChannels(Uint8List channels) {
    final previous = _writeLock;
    final result = previous.then((_) => _writeChannelsUnlocked(channels));
    // Keep the chain alive even if this write throws, so a failure doesn't
    // permanently wedge every write queued behind it.
    _writeLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _writeChannelsUnlocked(Uint8List channels) async {
    final writer = _writer;
    if (writer == null) return;
    if (_mode == WidgetMode.buffered) {
      await writer.write(encodeBufferedFrame(channels).toJS).toDart;
      return;
    }
    // Direct/Open DMX: the host bit-bangs break / mark-after-break itself by
    // toggling the line break signal before each frame.
    final port = _port;
    if (port != null) {
      await port.setSignals(_mapToJs({'break': true})).toDart;
      await port.setSignals(_mapToJs({'break': false})).toDart;
    }
    await writer.write(encodeDirectFrame(channels).toJS).toDart;
  }

  void _scheduleSend() {
    _sendTimer?.cancel();
    if (_status != TestOutputStatus.connected) return;
    final elapsed = DateTime.now().difference(_lastSendAt);
    final delay = elapsed >= _sendFloor ? Duration.zero : _sendFloor - elapsed;
    _sendTimer = Timer(delay, () => unawaited(_sendTick()));
  }

  Future<void> _sendTick() async {
    if (_status != TestOutputStatus.connected) return;
    _lastSendAt = DateTime.now();
    try {
      await _writeChannels(_frame.snapshot());
    } catch (_) {
      // A write failure doesn't always mean the port's own 'disconnect'
      // event will fire (that only covers physical USB removal, not a
      // driver-level or stream-level write rejection) — treat it as a
      // disconnect ourselves so status/isActive/outputActive stop claiming
      // a healthy live session that is no longer sending anything.
      unawaited(_handlePortDisconnect());
      return;
    }
    _scheduleSend();
  }

  // -- lifecycle plumbing ---------------------------------------------------

  Future<void> _acquireWakeLock() async {
    try {
      final sentinel = await web.window.navigator.wakeLock
          .request('screen')
          .toDart;
      _wakeLockSentinel = sentinel;
      // The spec has the browser auto-release the sentinel when the
      // document goes hidden, without reinstating it when it comes back —
      // that's on this app to do (see _handleVisibilityChange). Null out
      // our reference on that auto-release too, so _releaseWakeLock never
      // operates on an already-dead sentinel.
      sentinel.addEventListener(
        'release',
        ((web.Event _) {
          if (identical(_wakeLockSentinel, sentinel)) _wakeLockSentinel = null;
        }).toJS,
      );
    } catch (_) {
      // Wake lock is a best-effort enhancement (denied by policy,
      // unsupported, battery saver, etc.) — output still works without it.
    }
  }

  Future<void> _releaseWakeLock() async {
    final sentinel = _wakeLockSentinel;
    _wakeLockSentinel = null;
    if (sentinel == null) return;
    try {
      await sentinel.release().toDart;
    } catch (_) {}
  }

  void _attachListeners(_SerialPort port) {
    // Idempotent: a caller that begin()s more than once on this transport
    // (e.g. the Test screen after a manual reconnect) must not accumulate a
    // second set of document listeners on top of the first.
    _detachDocumentListeners();
    _visibilityListener = _handleVisibilityChange.toJS;
    web.document.addEventListener('visibilitychange', _visibilityListener);
    _beforeUnloadListener = ((web.Event _) => _bestEffortZero()).toJS;
    web.window.addEventListener('beforeunload', _beforeUnloadListener);
    // pagehide also covers bfcache navigation and mobile tab eviction,
    // which beforeunload does not reliably fire for. Same handler, same
    // best-effort teardown.
    web.window.addEventListener('pagehide', _beforeUnloadListener);
    final stalePortListener = _portDisconnectListener;
    if (stalePortListener != null) {
      port.removeEventListener('disconnect', stalePortListener);
    }
    _portDisconnectListener = ((web.Event _) => unawaited(
      _handlePortDisconnect(),
    )).toJS;
    port.addEventListener('disconnect', _portDisconnectListener!);
  }

  void _detachDocumentListeners() {
    final visibility = _visibilityListener;
    if (visibility != null) {
      web.document.removeEventListener('visibilitychange', visibility);
      _visibilityListener = null;
    }
    final beforeUnload = _beforeUnloadListener;
    if (beforeUnload != null) {
      web.window.removeEventListener('beforeunload', beforeUnload);
      web.window.removeEventListener('pagehide', beforeUnload);
      _beforeUnloadListener = null;
    }
  }

  /// Best-effort zero-frame write for page teardown (`beforeunload` /
  /// `pagehide`). Those handlers cannot reliably await a promise before the
  /// browsing context is torn down — awaiting between the break signal and
  /// the data write (as the normal, serialized [_writeChannels] does) loses
  /// everything after the first awaited call once the page starts
  /// unloading. So unlike [blackout], this fires every write without
  /// awaiting any of them: dispatching them all synchronously and
  /// back-to-back gives the browser the best chance of having queued each
  /// one before the page goes away.
  void _bestEffortZero() {
    _frame.zeroAll();
    final writer = _writer;
    if (writer == null) return;
    if (_mode == WidgetMode.buffered) {
      for (final frame in blackoutFrames()) {
        unawaited(writer.write(encodeBufferedFrame(frame).toJS).toDart);
      }
      return;
    }
    final port = _port;
    if (port != null) {
      unawaited(port.setSignals(_mapToJs({'break': true})).toDart);
      unawaited(port.setSignals(_mapToJs({'break': false})).toDart);
    }
    for (final frame in blackoutFrames()) {
      unawaited(writer.write(encodeDirectFrame(frame).toJS).toDart);
    }
  }

  // Chrome throttles/suspends timers in hidden tabs, which would otherwise
  // silently stretch the DMX refresh interval well past _sendFloor. Zero
  // the line before pausing — otherwise a buffered widget keeps
  // retransmitting whatever was last sent for as long as the tab stays
  // hidden — and surface the pause in status rather than let frames stall
  // invisibly.
  void _handleVisibilityChange(web.Event _) {
    if (web.document.hidden) {
      if (_status != TestOutputStatus.connected) return;
      _sendTimer?.cancel();
      _sendTimer = null;
      _setStatus(TestOutputStatus.blockedHidden);
      unawaited(blackout());
      return;
    }
    if (_status != TestOutputStatus.blockedHidden) return;
    _lastSendAt = DateTime.fromMillisecondsSinceEpoch(0);
    _setStatus(TestOutputStatus.connected);
    _scheduleSend();
    // The Wake Lock spec has the browser silently drop the sentinel when
    // the document went hidden; it is not reinstated automatically.
    unawaited(_acquireWakeLock());
  }

  Future<void> _handlePortDisconnect() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    _detachDocumentListeners();
    await _releaseWakeLock();
    final writer = _writer;
    _writer = null;
    if (writer != null) {
      try {
        writer.releaseLock();
      } catch (_) {}
    }
    // Drop the live buffer and the risky-unlock acknowledgement with it:
    // without this, a later reconnect would mark the same stale (possibly
    // risky) buffer live again and start resending it within one send-floor
    // tick, before any caller-supplied value had a chance to reach the
    // wire — the exact case the zero-start contract exists to prevent.
    _frame.reset();
    _riskyUnlocked = false;
    _setStatus(TestOutputStatus.disconnected);
    _listenForReconnect();
  }

  void _listenForReconnect() {
    final serial = _navigatorSerial;
    if (serial == null) return;
    final stale = _serialConnectListener;
    if (stale != null) serial.removeEventListener('connect', stale);
    _serialConnectListener = ((web.Event _) => unawaited(
      _attemptReconnect(),
    )).toJS;
    serial.addEventListener('connect', _serialConnectListener!);
  }

  void _cancelReconnectListener() {
    final serial = _navigatorSerial;
    final listener = _serialConnectListener;
    if (serial != null && listener != null) {
      serial.removeEventListener('connect', listener);
    }
    _serialConnectListener = null;
  }

  /// Re-acquires the port reference when the same physical cable
  /// reappears, so a manual "Start at zero" retry works — but does not
  /// resume output itself. Silently reopening a live DMX line because a
  /// USB connector was re-seated (or because some other device sharing the
  /// same vendor/product id was plugged in) is a stronger grant than
  /// choosing a cable once implies; resuming output stays a user gesture
  /// (the Test screen's "Start at zero" button), same as the very first
  /// connection.
  Future<void> _attemptReconnect() async {
    final serial = _navigatorSerial;
    _cancelReconnectListener();
    final vendorId = _device?.usbVendorId;
    final productId = _device?.usbProductId;
    if (serial == null || vendorId == null || productId == null) return;
    final ports = (await serial.getPorts().toDart).toDart;
    for (final candidate in ports) {
      final info = candidate.getInfo();
      if (info.usbVendorId == vendorId && info.usbProductId == productId) {
        _port = candidate;
        return;
      }
    }
  }

  Future<void> _releaseConnection() async {
    _sendTimer?.cancel();
    _sendTimer = null;
    _detachDocumentListeners();
    _cancelReconnectListener();
    await _releaseWakeLock();
    final writer = _writer;
    _writer = null;
    if (writer != null) {
      try {
        writer.releaseLock();
      } catch (_) {}
    }
    final port = _port;
    final portListener = _portDisconnectListener;
    if (port != null && portListener != null) {
      port.removeEventListener('disconnect', portListener);
    }
    _portDisconnectListener = null;
    if (port != null) {
      try {
        await port.close().toDart;
      } catch (_) {}
    }
  }

  void _setStatus(TestOutputStatus value) {
    _status = value;
    _statusController.add(value);
  }
}
