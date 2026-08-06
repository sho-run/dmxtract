// Pure DMX/Enttec protocol logic for the in-page Web Serial transport.
//
// This file has no dart:js_interop dependency on purpose: it holds every
// piece of `webserial_dmx.dart` that can be expressed as plain byte math or
// state transitions, so it can be exercised directly by `flutter test` (a VM
// test target) without a browser. `webserial_dmx.dart` calls into these
// functions rather than re-deriving frame bytes inline.

import 'dart:typed_data';

/// Number of DMX512 data channels in a universe (excludes the start code).
const int dmxChannelCount = 512;

/// Enttec USB DMX PRO packet framing bytes (start-of-message / end-of-message).
const int enttecStart = 0x7E;
const int enttecEnd = 0xE7;

/// How a connected widget is driven, decided once per [begin] by probing for
/// an Enttec-style reply.
enum WidgetMode {
  /// A microcontroller-based widget (Enttec USB DMX PRO and compatible
  /// clones) that accepts a framed packet and owns DMX break/MAB timing.
  buffered,

  /// A bare "Open DMX" FTDI/CH340/CP210x cable with no onboard widget
  /// firmware; the host must toggle break/mark-after-break itself via
  /// `SerialPort.setSignals`.
  direct,
}

/// Enttec USB DMX PRO "Get Widget Parameters Request" (label 3): a 2-byte,
/// all-zero body asking for no user-configuration bytes back. Any reply
/// bytes read within the probe timeout identify a buffered widget; silence
/// identifies a direct/Open DMX cable. See [WidgetMode].
Uint8List enttecGetWidgetParamsRequest() => Uint8List.fromList(const [
  enttecStart,
  0x03, // label: GET_WIDGET_PARAMS_REQUEST
  0x02, // data length lo (2 bytes follow)
  0x00, // data length hi
  0x00, // user configuration size lsb (unused; request base params only)
  0x00, // user configuration size msb
  enttecEnd,
]);

/// Classifies a widget probe response. Only bytes that actually look like
/// an Enttec GET_WIDGET_PARAMS *reply* — start byte, the reply label, a
/// plausible reply-sized body, and a matching terminator at the declared
/// position — count as a buffered widget; anything else (including a
/// non-empty but malformed read) is treated as a silent direct/Open DMX
/// cable.
///
/// This matters because many cheap FTDI/CH340 + MAX485 "Open DMX" cables
/// tie the transceiver's receive-enable low, so the probe bytes this app
/// just wrote are echoed straight back on RX. An "any bytes at all" check
/// would misclassify that echo as a widget reply; even a generic
/// envelope-shape check is not enough on its own, since
/// [enttecGetWidgetParamsRequest] is itself a validly-framed 2-byte-body
/// packet and would pass a bare start/label/terminator check when echoed
/// verbatim. A genuine reply always carries at least 4 data bytes
/// (firmware version lo/hi, break time, mark-after-break time), so this
/// also rejects anything with a shorter declared body — which the request's
/// own echo always has.
WidgetMode detectWidgetMode(List<int> probeResponse) {
  // Header (start, label, length lo/hi) + at least the terminator.
  if (probeResponse.length < 5) return WidgetMode.direct;
  if (probeResponse[0] != enttecStart) return WidgetMode.direct;
  if (probeResponse[1] != 0x03) {
    return WidgetMode.direct; // GET_WIDGET_PARAMS reply label
  }
  final dataLength = probeResponse[2] | (probeResponse[3] << 8);
  if (dataLength < 4) return WidgetMode.direct;
  final totalLength = 4 + dataLength + 1; // header + body + terminator
  if (probeResponse.length < totalLength) return WidgetMode.direct;
  if (probeResponse[totalLength - 1] != enttecEnd) return WidgetMode.direct;
  return WidgetMode.buffered;
}

void _checkChannelBytes(Uint8List channels) {
  if (channels.length != dmxChannelCount) {
    throw ArgumentError(
      'channels must have exactly $dmxChannelCount bytes, got ${channels.length}',
    );
  }
}

/// Enttec USB DMX PRO "Output Only Send DMX Packet" (label 6) frame: DMX
/// start code (0x00) followed by all 512 channel bytes, length-prefixed
/// little-endian. Total length is always 518 bytes: 4-byte header + 513-byte
/// body (start code + channels) + 1-byte footer.
Uint8List encodeBufferedFrame(Uint8List channels) {
  _checkChannelBytes(channels);
  final frame = Uint8List(4 + 1 + dmxChannelCount + 1);
  frame[0] = enttecStart;
  frame[1] = 0x06; // label: OUTPUT_ONLY_SEND_DMX_PACKET
  frame[2] = 0x01; // data length lo (513 & 0xFF)
  frame[3] = 0x02; // data length hi (513 >> 8)
  frame[4] = 0x00; // DMX start code
  frame.setRange(5, 5 + dmxChannelCount, channels);
  frame[frame.length - 1] = enttecEnd;
  return frame;
}

/// Direct/Open DMX mode frame body: DMX start code followed by all 512
/// channel bytes. The break / mark-after-break signal toggle that must
/// precede this write on the wire is not representable as bytes — see
/// `WebSerialDmxTransport._writeChannels` for the `setSignals` sequence.
Uint8List encodeDirectFrame(Uint8List channels) {
  _checkChannelBytes(channels);
  final frame = Uint8List(1 + dmxChannelCount);
  frame[0] = 0x00; // DMX start code
  frame.setRange(1, 1 + dmxChannelCount, channels);
  return frame;
}

/// An all-zero 512-channel frame body.
Uint8List zeroChannelFrame() => Uint8List(dmxChannelCount);

/// Consecutive all-zero frames to send for a blackout/shutdown sequence, so
/// a single dropped USB write cannot leave a widget holding a stale
/// non-zero level.
List<Uint8List> blackoutFrames({int count = 3}) =>
    List.generate(count, (_) => zeroChannelFrame(), growable: false);

/// Thrown when [assertRiskyAllowed] rejects a risky-range value because the
/// session has not been unlocked yet.
///
/// The message and the rule it enforces intentionally match the Bridge's
/// lease gate exactly: crates/dmxtract_bridge/src/api.rs `set_channels`
/// rejects any request with `risky: true` until `unlock` has been called for
/// that lease. The Web Serial transport has no server to enforce this for
/// it, so it re-implements the identical client-side rule here rather than
/// relying on a network round trip.
class RiskyLockedException implements Exception {
  const RiskyLockedException();
  @override
  String toString() =>
      'Unlock risky ranges before sending strobe, lamp, reset, or maintenance values.';
}

/// Mirrors the Bridge's `if request.risky && !lease.safety_unlocked { reject }`
/// check (crates/dmxtract_bridge/src/api.rs, `set_channels`).
void assertRiskyAllowed({required bool risky, required bool unlocked}) {
  if (risky && !unlocked) throw const RiskyLockedException();
}

/// Mirrors the Bridge's channel/value bounds checks
/// (crates/dmxtract_bridge/src/api.rs `set_channels`: "Channel must be
/// between 1 and 512."; DMX values are inherently a single byte, 0-255).
void assertValidChannelValue(int channel, int value) {
  if (channel < 1 || channel > 512) {
    throw ArgumentError('Channel must be between 1 and 512.');
  }
  if (value < 0 || value > 255) {
    throw ArgumentError('Value must be between 0 and 255.');
  }
}

/// Holds the live 512-channel DMX universe buffer for the Web Serial
/// transport and enforces zero-start: no caller-supplied channel value is
/// honored until [goLive] has been called, which the transport only does
/// after it has successfully written the first all-zero frame to the port.
class DmxFrameState {
  final Uint8List _channels = Uint8List(dmxChannelCount);
  bool _live = false;

  /// True once the initial zero frame has been written and [goLive] called.
  bool get isLive => _live;

  /// Marks the buffer live. Call only after the first all-zero frame has
  /// actually been written to the port.
  void goLive() => _live = true;

  /// Sets channel [channel] (1-512) to [value] (0-255) in the live buffer.
  /// Throws [StateError] if called before [goLive] — callers must not be
  /// able to smuggle a non-zero value into the very first frame sent.
  void setChannel(int channel, int value) {
    if (!_live) {
      throw StateError(
        'Cannot set a channel before output is live (zero-start frame not yet sent).',
      );
    }
    assertValidChannelValue(channel, value);
    _channels[channel - 1] = value;
  }

  /// Defensive copy of the current 512-byte frame.
  Uint8List snapshot() => Uint8List.fromList(_channels);

  /// Zeros the in-memory buffer. Does not itself write to the port — pair
  /// with [blackoutFrames] to also push the zeros out over the wire.
  void zeroAll() => _channels.fillRange(0, _channels.length, 0);

  /// Zeros the buffer and revokes [isLive], so a stale (possibly risky)
  /// value from a previous session cannot be replayed the moment a new
  /// session calls [goLive] again — e.g. after a USB disconnect/reconnect,
  /// where the old buffer would otherwise still hold whatever was live when
  /// the cable dropped. Call on every session teardown, not just [zeroAll]
  /// alone.
  void reset() {
    zeroAll();
    _live = false;
  }
}
