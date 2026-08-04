import 'dart:typed_data';

import 'export_service.dart';
import 'model.dart';

Future<Uint8List> exportOflShared(FixtureProject fixture) async =>
    exportOfl(fixture);

Future<Uint8List> exportGdtfShared(FixtureProject fixture) async =>
    exportGdtf(fixture);
