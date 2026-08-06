import 'dart:async';
import 'dart:typed_data';

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

bool phoneLinkBrowserSupported() => false;

String randomBase64UrlToken(int byteLength) =>
    throw UnsupportedError('Phone hand-off runs in a browser.');

class PhoneLinkSession {
  Stream<PhoneLinkEvent> get events => const Stream.empty();
  Stream<ReceivedPhoto> get photos => const Stream.empty();
  void stop() {}
}

PhoneLinkSession startPhoneLinkSession({
  required String sessionId,
  required String keyBase64Url,
}) => throw UnsupportedError('Phone hand-off runs in a browser.');
