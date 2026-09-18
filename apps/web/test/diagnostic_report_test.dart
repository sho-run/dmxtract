import 'dart:convert';
import 'package:dmxtract_web/src/diagnostic_report.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FixtureProject buildFixture() => FixtureProject(
    id: 'unknown-par-64',
    manufacturer: 'Unknown manufacturer',
    model: 'Par 64',
    channels: [
      DmxChannel(
        id: 'dimmer',
        name: 'Dimmer',
        kind: 'intensity',
        ranges: [DmxRange(start: 0, end: 255, name: 'Intensity')],
      ),
    ],
    modes: [
      FixtureMode(id: 'mode-1', name: 'Standard', channelIds: ['dimmer']),
    ],
  );

  test('bundles the page-marked text, the fixture JSON, and the source '
      'filename', () {
    final fixture = buildFixture();
    const extractedText = '=== DMXTRACT PAGE 1 ===\nPar 64\n1 000-255 Dimmer';
    final bytes = exportDiagnosticReport(
      extractedText: extractedText,
      fixture: fixture,
      sourceFileName: 'par64_manual.pdf',
    );
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

    expect(json['schemaVersion'], 1);
    expect(json['schema'], contains('diagnostic-report'));
    expect(json['sourceFileName'], 'par64_manual.pdf');
    expect(json['extractedText'], extractedText);
    expect(json['generatedAt'], isA<String>());

    final fixtureJson = json['fixture'] as Map<String, Object?>;
    expect(fixtureJson['schemaVersion'], fixture.toJson()['schemaVersion']);
    final identity = fixtureJson['identity'] as Map;
    expect(identity['manufacturer'], 'Unknown manufacturer');
    expect(identity['model'], 'Par 64');
  });

  test('never includes anything beyond the parsed text and fixture JSON — '
      'no raw-bytes or photo field of any kind', () {
    final bytes = exportDiagnosticReport(
      extractedText: 'irrelevant',
      fixture: buildFixture(),
      sourceFileName: 'x.pdf',
    );
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    expect(json.keys, {
      'schema',
      'schemaVersion',
      'generatedAt',
      'sourceFileName',
      'extractedText',
      'fixture',
    });
  });
}
