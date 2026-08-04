import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'model.dart';

@JS('dmxtractCore.exportOfl')
external JSPromise<JSString> _exportOfl(JSString fixtureJson);

@JS('dmxtractCore.exportGdtf')
external JSPromise<JSUint8Array> _exportGdtf(JSString fixtureJson);

Future<Uint8List> exportOflShared(FixtureProject fixture) async {
  final json = (await _exportOfl(fixture.encode().toJS).toDart).toDart;
  return Uint8List.fromList(utf8.encode(json));
}

Future<Uint8List> exportGdtfShared(FixtureProject fixture) async =>
    (await _exportGdtf(fixture.encode().toJS).toDart).toDart;
