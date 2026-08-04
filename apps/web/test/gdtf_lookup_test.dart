import 'dart:convert';

import 'package:dmxtract_web/src/extraction_rules.dart';
import 'package:dmxtract_web/src/gdtf_lookup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final fixture = fixtureFromManualText(
    'Chauvet DJ COLORpalette User Manual DMX Channel Assignments 3CH 6CH 9CH 15CH 27CH',
    'private-person-name-manual.pdf',
  ).fixture;

  test('lookup sends only fixture identity and mode footprints', () async {
    late Map<String, Object?> sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, Object?>;
      return http.Response(
        jsonEncode({
          'enabled': true,
          'matches': [
            {
              'id': 'revision-42',
              'manufacturer': 'Chauvet DJ',
              'fixture': 'COLORpalette',
              'revision': 'Manufacturer release',
              'source': 'manufacturer',
              'score': .96,
              'url': 'https://gdtf-share.com/',
              'rating': 4.7,
              'version': '1.2',
              'modeFootprints': [3, 6, 9, 15, 27],
              'creator': 'must not be consumed',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await GdtfLookupClient(
      client: client,
      endpoint: Uri.parse('https://dmxtract.test/api/fixture-matches'),
    ).search(fixture);

    expect(
      sent.keys,
      unorderedEquals(['manufacturer', 'model', 'modeFootprints']),
    );
    expect(jsonEncode(sent), isNot(contains('private-person-name')));
    expect(jsonEncode(sent), isNot(contains('channels')));
    expect(result.enabled, isTrue);
    expect(result.matches.single.source, 'manufacturer');
    expect(result.matches.single.modeFootprints, [3, 6, 9, 15, 27]);
  });

  test(
    'lookup fails closed when its same-origin endpoint is unavailable',
    () async {
      final client = MockClient((_) async => http.Response('Not found', 404));
      final result = await GdtfLookupClient(
        client: client,
        endpoint: Uri.parse('https://dmxtract.test/api/fixture-matches'),
      ).search(fixture);
      expect(result.enabled, isFalse);
      expect(result.matches, isEmpty);
    },
  );

  test('filename-derived fixture identity never leaves the browser', () async {
    final filenameFixture = fixtureFromManualText(
      'DMX Channel Assignments 6CH',
      'private-person-name-manual.pdf',
    ).fixture;
    var contacted = false;
    final client = MockClient((_) async {
      contacted = true;
      return http.Response('{}', 200);
    });
    final result = await GdtfLookupClient(
      client: client,
      endpoint: Uri.parse('https://dmxtract.test/api/fixture-matches'),
    ).search(filenameFixture);
    expect(contacted, isFalse);
    expect(result.enabled, isFalse);
  });
}
