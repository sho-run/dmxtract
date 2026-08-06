import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Status updates from an in-progress phone hand-off. `type` mirrors the
/// events emitted by web/phone_link.js: waiting, phoneJoined, connected,
/// closed, error.
class PhoneLinkEvent {
  const PhoneLinkEvent(this.type, [this.message]);
  final String type;
  final String? message;
}

/// A photo received from the phone over the WebRTC data channel.
class ReceivedPhoto {
  const ReceivedPhoto(this.name, this.mime, this.bytes);
  final String name;
  final String mime;
  final Uint8List bytes;
}

@JS('dmxtractPhoneLink.supported')
external JSBoolean _supported();

@JS('dmxtractPhoneLink.start')
external void _start(
  JSString sessionId,
  JSString keyBase64Url,
  JSFunction onEvent,
  JSFunction onPhoto,
);

@JS('dmxtractPhoneLink.stop')
external void _stop();

bool phoneLinkBrowserSupported() {
  try {
    return _supported().toDart;
  } catch (_) {
    return false;
  }
}

/// Generates a URL-safe token from real browser CSPRNG entropy
/// (`crypto.getRandomValues`), used for both the session id and the AES-GCM
/// key. The key is embedded only in the caller's URL fragment; it is never
/// passed to this module again after that, so it never reaches the network.
String randomBase64UrlToken(int byteLength) {
  final bytes = Uint8List(byteLength);
  web.window.crypto.getRandomValues(bytes.toJS);
  return base64Url.encode(bytes).replaceAll('=', '');
}

class PhoneLinkSession {
  PhoneLinkSession._();
  final _events = StreamController<PhoneLinkEvent>.broadcast();
  final _photos = StreamController<ReceivedPhoto>.broadcast();

  Stream<PhoneLinkEvent> get events => _events.stream;
  Stream<ReceivedPhoto> get photos => _photos.stream;

  void stop() {
    _stop();
    unawaited(_events.close());
    unawaited(_photos.close());
  }
}

/// Starts the desktop (offering) side of the hand-off: creates a
/// RTCPeerConnection and DataChannel in JS, posts an encrypted offer to the
/// signaling relay, and waits for the phone to answer. See
/// web/phone_link.js for the WebRTC and signaling implementation.
PhoneLinkSession startPhoneLinkSession({
  required String sessionId,
  required String keyBase64Url,
}) {
  final session = PhoneLinkSession._();
  final onEvent = ((JSString json) {
    final map = jsonDecode(json.toDart) as Map<String, Object?>;
    session._events.add(
      PhoneLinkEvent(map['type']! as String, map['message'] as String?),
    );
  }).toJS;
  final onPhoto = ((JSString name, JSString mime, JSUint8Array bytes) {
    session._photos.add(ReceivedPhoto(name.toDart, mime.toDart, bytes.toDart));
  }).toJS;
  _start(sessionId.toJS, keyBase64Url.toJS, onEvent, onPhoto);
  return session;
}
