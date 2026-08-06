// Tests for the Web Serial DMX transport's protocol logic
// (lib/src/webserial_frame.dart). This is the pure-logic half of
// lib/src/webserial_dmx.dart, split out specifically so frame encoding,
// widget-mode detection, risky-range gating, and zero-start/blackout
// ordering are testable on the Dart VM without a browser or js_interop.

import 'dart:typed_data';

import 'package:dmxtract_web/src/webserial_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Enttec widget probe', () {
    test('GET_WIDGET_PARAMS request has exact bytes', () {
      expect(enttecGetWidgetParamsRequest(), [
        0x7E,
        0x03,
        0x02,
        0x00,
        0x00,
        0x00,
        0xE7,
      ]);
    });

    test('a well-formed GET_WIDGET_PARAMS reply means a buffered widget', () {
      // Realistic reply: firmware version lo/hi, break time, MAB time, DMX
      // speed — 5 data bytes, matching the declared length.
      expect(
        detectWidgetMode([
          0x7E, 0x03, 0x05, 0x00, // header, declared length 5
          0x01, 0x00, 0x09, 0x01, 0x28, // firmware, break, MAB, speed
          0xE7,
        ]),
        WidgetMode.buffered,
      );
    });

    test('an empty/timed-out reply means a direct/Open DMX cable', () {
      expect(detectWidgetMode(const []), WidgetMode.direct);
    });

    test('a single stray byte does not count as a widget reply', () {
      expect(detectWidgetMode([0x00]), WidgetMode.direct);
    });

    test('an Open DMX cable that echoes the probe verbatim is not mistaken for '
        'a widget reply', () {
      // What a receive-enable-tied-low cable bounces straight back: this
      // app's own request bytes. Structurally well-framed, but a
      // 2-byte-body request, not a >=4-byte-body reply.
      expect(
        detectWidgetMode(enttecGetWidgetParamsRequest()),
        WidgetMode.direct,
      );
    });

    test(
      'a truncated reply (declared length not yet fully read) is not a widget',
      () {
        expect(
          detectWidgetMode([0x7E, 0x03, 0x05, 0x00, 0x01, 0x00]),
          WidgetMode.direct,
        );
      },
    );

    test('a reply missing the terminator byte is not a widget', () {
      expect(
        detectWidgetMode([
          0x7E,
          0x03,
          0x05,
          0x00,
          0x01,
          0x00,
          0x09,
          0x01,
          0x28,
          0x00,
        ]),
        WidgetMode.direct,
      );
    });
  });

  group('buffered (Enttec Pro) frame encoding', () {
    test('all-zero channels produce the exact expected byte layout', () {
      final frame = encodeBufferedFrame(Uint8List(dmxChannelCount));

      expect(frame.length, 518);
      // Header: start byte, label 0x06, length 513 little-endian.
      expect(frame.sublist(0, 5), [0x7E, 0x06, 0x01, 0x02, 0x00]);
      // Body: 512 channel bytes, all zero.
      expect(frame.sublist(5, 5 + dmxChannelCount), List.filled(512, 0));
      // Footer.
      expect(frame.last, 0xE7);
    });

    test('non-zero channel values land at the right offsets', () {
      final channels = Uint8List(dmxChannelCount);
      channels[0] = 0xFF; // DMX channel 1
      channels[511] = 0x01; // DMX channel 512

      final frame = encodeBufferedFrame(channels);

      expect(frame.length, 518);
      expect(frame[4], 0x00, reason: 'DMX start code precedes channel data');
      expect(frame[5], 0xFF, reason: 'channel 1 is the first data byte');
      expect(frame[5 + 511], 0x01, reason: 'channel 512 is the last');
      expect(frame[frame.length - 1], 0xE7);
    });

    test('rejects a channel buffer of the wrong length', () {
      expect(
        () => encodeBufferedFrame(Uint8List(511)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => encodeBufferedFrame(Uint8List(513)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('direct (Open DMX) frame encoding', () {
    test('produces a 513-byte start-code-prefixed frame', () {
      final channels = Uint8List(dmxChannelCount);
      channels[0] = 0x7F;
      channels[511] = 0x80;

      final frame = encodeDirectFrame(channels);

      expect(frame.length, 513);
      expect(frame[0], 0x00, reason: 'DMX start code, no Enttec framing');
      expect(frame[1], 0x7F);
      expect(frame[512], 0x80);
    });

    test('rejects a channel buffer of the wrong length', () {
      expect(
        () => encodeDirectFrame(Uint8List(10)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('risky-range gating', () {
    // Parity target: crates/dmxtract_bridge/src/api.rs `set_channels`
    // (`with_lease` closure) — "if request.risky && !lease.safety_unlocked"
    // rejects the write. This transport has no server to enforce that for
    // it, so it must reject on the client identically.
    test('a risky value is rejected before unlock', () {
      expect(
        () => assertRiskyAllowed(risky: true, unlocked: false),
        throwsA(isA<RiskyLockedException>()),
      );
    });

    test('a risky value is allowed once unlocked', () {
      expect(
        () => assertRiskyAllowed(risky: true, unlocked: true),
        returnsNormally,
      );
    });

    test('a normal (non-risky) value is always allowed', () {
      expect(
        () => assertRiskyAllowed(risky: false, unlocked: false),
        returnsNormally,
      );
    });

    test('the exception message matches the Bridge lock message', () {
      expect(
        const RiskyLockedException().toString(),
        'Unlock risky ranges before sending strobe, lamp, reset, or maintenance values.',
      );
    });
  });

  group('channel/value bounds', () {
    test('rejects channel 0 and channel 513', () {
      expect(
        () => assertValidChannelValue(0, 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => assertValidChannelValue(513, 0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects values outside 0-255', () {
      expect(
        () => assertValidChannelValue(1, -1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => assertValidChannelValue(1, 256),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts the full valid range', () {
      expect(() => assertValidChannelValue(1, 0), returnsNormally);
      expect(() => assertValidChannelValue(512, 255), returnsNormally);
    });
  });

  group('DmxFrameState zero-start ordering', () {
    test('setChannel before goLive throws', () {
      final frame = DmxFrameState();
      expect(() => frame.setChannel(1, 255), throwsA(isA<StateError>()));
    });

    test(
      'the buffer stays all-zero until goLive, even after a rejected set',
      () {
        final frame = DmxFrameState();
        expect(() => frame.setChannel(1, 255), throwsA(isA<StateError>()));
        expect(frame.snapshot(), List.filled(512, 0));
        expect(frame.isLive, isFalse);
      },
    );

    test('setChannel works once live, and writes to the right offset', () {
      final frame = DmxFrameState()..goLive();

      frame.setChannel(1, 200);
      frame.setChannel(512, 42);

      final snapshot = frame.snapshot();
      expect(snapshot[0], 200);
      expect(snapshot[511], 42);
    });

    test('snapshot is a defensive copy', () {
      final frame = DmxFrameState()..goLive();
      frame.setChannel(1, 10);
      final snapshot = frame.snapshot();
      snapshot[0] = 99;
      expect(frame.snapshot()[0], 10);
    });

    test('reset zeros the buffer and revokes goLive', () {
      final frame = DmxFrameState()..goLive();
      frame.setChannel(1, 255);

      frame.reset();

      expect(frame.snapshot(), List.filled(512, 0));
      expect(frame.isLive, isFalse);
      expect(
        () => frame.setChannel(1, 1),
        throwsA(isA<StateError>()),
        reason:
            'a stale value must not be replayable without a fresh zero-start',
      );
    });
  });

  group('blackout sequence', () {
    test('zeroChannelFrame is 512 all-zero bytes', () {
      final zero = zeroChannelFrame();
      expect(zero.length, dmxChannelCount);
      expect(zero, everyElement(0));
    });

    test('blackoutFrames sends several consecutive all-zero frames', () {
      final frames = blackoutFrames();
      expect(frames.length, greaterThanOrEqualTo(2));
      for (final frame in frames) {
        expect(frame.length, dmxChannelCount);
        expect(frame, everyElement(0));
      }
    });

    test('blackoutFrames honors an explicit count', () {
      expect(blackoutFrames(count: 5).length, 5);
    });

    test('zeroAll resets a live buffer back to all-zero', () {
      final frame = DmxFrameState()..goLive();
      frame.setChannel(1, 255);
      frame.setChannel(2, 128);

      frame.zeroAll();

      expect(frame.snapshot(), List.filled(512, 0));
      expect(frame.isLive, isTrue, reason: 'zeroAll does not end the session');
    });
  });
}
