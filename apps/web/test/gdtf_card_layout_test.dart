// Widget tests for the GDTF Share lookup card's position on the Check step
// (lib/src/screens/review.dart) and its status row. Runs on the browser
// platform because review.dart imports package:web transitively.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/components.dart';
import 'package:dmxtract_web/src/gdtf_lookup.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:dmxtract_web/src/screens/review.dart';
import 'package:dmxtract_web/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Mirrors the private literals in _GdtfLookupStatusRow.build (review.dart),
// which this test file can't import.
const _pendingLabel = 'Checking GDTF Share…';
const _matchLabel = 'Possible match below';
const _noMatchLabel = 'No match on GDTF Share';
const _notCheckedLabel = 'GDTF Share not checked';

// Verbatim contents of golden/simple-rgbw.dmxtract.json — embedded because
// browser-platform tests have no dart:io/File access.
const _goldenSimpleRgbwJson = r'''
{
  "schema": "https://dmxtract.sho.run/schemas/fixture-v1.json",
  "schemaVersion": 1,
  "id": "dmxtract-simple-rgbw",
  "identity": {
    "manufacturer": "DMXtract Test",
    "model": "Simple RGBW",
    "shortName": "RGBW",
    "categories": ["Color Changer"],
    "confidence": { "score": 1, "reason": "Synthetic test fixture" }
  },
  "physical": { "powerW": 40 },
  "provenance": {
    "sourceType": "synthetic",
    "sourceName": "simple-rgbw",
    "importedAt": "2026-08-03T00:00:00Z",
    "notes": ["Synthetic fixture for format validation"]
  },
  "channels": [
    { "id": "red", "name": "Red", "kind": "colorIntensity", "color": "RED", "fineOf": null, "wheelId": null, "ranges": [{ "start": 0, "end": 255, "name": "Red intensity", "capability": null, "wheelSlot": null, "safety": "normal", "confidence": { "score": 1, "reason": "" }, "source": null }], "confidence": { "score": 1, "reason": "" }, "source": null },
    { "id": "green", "name": "Green", "kind": "colorIntensity", "color": "GREEN", "fineOf": null, "wheelId": null, "ranges": [{ "start": 0, "end": 255, "name": "Green intensity", "capability": null, "wheelSlot": null, "safety": "normal", "confidence": { "score": 1, "reason": "" }, "source": null }], "confidence": { "score": 1, "reason": "" }, "source": null },
    { "id": "blue", "name": "Blue", "kind": "colorIntensity", "color": "BLUE", "fineOf": null, "wheelId": null, "ranges": [{ "start": 0, "end": 255, "name": "Blue intensity", "capability": null, "wheelSlot": null, "safety": "normal", "confidence": { "score": 1, "reason": "" }, "source": null }], "confidence": { "score": 1, "reason": "" }, "source": null },
    { "id": "white", "name": "White", "kind": "colorIntensity", "color": "WHITE", "fineOf": null, "wheelId": null, "ranges": [{ "start": 0, "end": 255, "name": "White intensity", "capability": null, "wheelSlot": null, "safety": "normal", "confidence": { "score": 1, "reason": "" }, "source": null }], "confidence": { "score": 1, "reason": "" }, "source": null }
  ],
  "modes": [{
    "id": "4ch",
    "name": "4-channel",
    "shortName": "4ch",
    "breaks": 1,
    "channels": [
      { "channelId": "red", "offset": 1, "dmxBreak": 1 },
      { "channelId": "green", "offset": 2, "dmxBreak": 1 },
      { "channelId": "blue", "offset": 3, "dmxBreak": 1 },
      { "channelId": "white", "offset": 4, "dmxBreak": 1 }
    ],
    "confidence": { "score": 1, "reason": "" }
  }],
  "wheels": [],
  "matrix": null,
  "geometry": { "body": true, "yoke": false, "head": false, "beam": true, "pixelEmitters": false }
}
''';

// The golden project's provenance carries no identityFromManual, so
// FixtureProject.fromJson defaults it false — appliesTo requires it true,
// so this fixture as-is never triggers a lookup.
FixtureProject _goldenFixture() => FixtureProject.fromJson(
  jsonDecode(_goldenSimpleRgbwJson) as Map<String, Object?>,
);

// Real POST /api/fixture-matches response recorded from the live site on
// 2026-09-24 for ADJ Encore LP12Z IP (id 80671), reused verbatim.
const _liveFixtureMatchesResponseJson = r'''
{"enabled":true,"matches":[{"id":"80671","manufacturer":"ADJ","fixture":"Encore LP12Z IP","revision":"24-11-12 Release","source":"manufacturer","score":1,"url":"https://gdtf-share.com/share.php","rating":null,"version":"1.2","modeFootprints":[18,15,12,10,9,6]}]}
''';

// Parses _liveFixtureMatchesResponseJson the way search() parses a response.
GdtfLookupResult _liveFixtureMatchesResult() {
  final body =
      jsonDecode(_liveFixtureMatchesResponseJson) as Map<String, Object?>;
  return GdtfLookupResult(
    enabled: body['enabled'] == true,
    matches: (body['matches'] as List)
        .whereType<Map>()
        .map(
          (item) => GdtfProfileMatch.fromJson(Map<String, Object?>.from(item)),
        )
        .toList(growable: false),
  );
}

/// A GdtfLookupClient whose [search] result the test completes directly.
/// [appliesTo] is the real, inherited implementation.
class _FakeGdtfLookupClient extends GdtfLookupClient {
  final _completer = Completer<GdtfLookupResult>();

  @override
  Future<GdtfLookupResult> search(FixtureProject fixture) => _completer.future;

  void complete(GdtfLookupResult result) => _completer.complete(result);
}

/// Pumps the Check step at the mobile_layout_test.dart viewport (390×844 @
/// 1x). Assigns [fixture] directly rather than through DmxtractState.ingest:
/// ingest's _save() writes to a real, page-lifetime IndexedDB store
/// (project_store_web.dart) that isn't reset between the testWidgets below.
/// gdtfLookupPending mirrors _queueFixtureLookup's own synchronous setup
/// (private, so not callable here); [lookupClient].search is overridden to
/// return a Future the test controls, while appliesTo stays the real,
/// inherited implementation.
Future<DmxtractState> _pumpCheckStep(
  WidgetTester tester, {
  required FixtureProject fixture,
  required _FakeGdtfLookupClient lookupClient,
  double width = 390,
  double height = 844,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state = DmxtractState(lookupClient: lookupClient)
    ..fixture = fixture
    ..step = 1
    ..gdtfLookupPending = lookupClient.appliesTo(fixture);
  addTearDown(state.dispose);
  if (state.gdtfLookupPending) {
    unawaited(
      lookupClient.search(fixture).then((result) {
        state.gdtfMatches = result.matches;
        state.gdtfLookupEnabled = result.enabled;
        state.gdtfLookupPending = false;
        state.notifyListeners();
      }),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: dmxTheme(),
      home: DmxScope(
        state: state,
        child: const BeginnerPageShell(child: ReviewScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a late-arriving match never moves the mode card or the primary '
      'button, and the card lands after both', (tester) async {
    final fixture = _goldenFixture()..identityFromManual = true;
    final lookupClient = _FakeGdtfLookupClient();
    final state = await _pumpCheckStep(
      tester,
      fixture: fixture,
      lookupClient: lookupClient,
    );

    expect(state.gdtfLookupApplies, isTrue);
    expect(state.gdtfLookupPending, isTrue);
    expect(find.text(_pendingLabel), findsOneWidget);
    expect(find.text('This light may already have a profile'), findsNothing);

    final buttonRectBefore = tester.getRect(find.text('Test your light'));
    final modeCardRectBefore = tester.getRect(find.text('4-channel'));

    lookupClient.complete(_liveFixtureMatchesResult());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(state.gdtfLookupPending, isFalse);
    expect(state.gdtfMatches, hasLength(1));
    expect(
      tester.getRect(find.text('Test your light')),
      equals(buttonRectBefore),
    );
    expect(tester.getRect(find.text('4-channel')), equals(modeCardRectBefore));
    expect(find.text(_pendingLabel), findsNothing);
    expect(find.text(_matchLabel), findsOneWidget);

    final cardTitleRect = tester.getTopLeft(
      find.text('This light may already have a profile'),
    );
    expect(cardTitleRect.dy, greaterThan(buttonRectBefore.bottom));
    expect(cardTitleRect.dy, greaterThan(modeCardRectBefore.bottom));

    // Scrollable.ensureVisible needs a Scrollable ancestor; confirms one
    // exists (BeginnerPageShell's SingleChildScrollView) rather than throwing.
    await tester.tap(find.text(_matchLabel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('no-match result settles the row without moving anything', (
    tester,
  ) async {
    final fixture = _goldenFixture()..identityFromManual = true;
    final lookupClient = _FakeGdtfLookupClient();
    final state = await _pumpCheckStep(
      tester,
      fixture: fixture,
      lookupClient: lookupClient,
    );

    expect(state.gdtfLookupPending, isTrue);
    final buttonRectBefore = tester.getRect(find.text('Test your light'));
    final modeCardRectBefore = tester.getRect(find.text('4-channel'));

    lookupClient.complete(const GdtfLookupResult(enabled: true, matches: []));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(state.gdtfLookupPending, isFalse);
    expect(state.gdtfMatches, isEmpty);
    expect(find.text(_noMatchLabel), findsOneWidget);
    expect(find.text('This light may already have a profile'), findsNothing);
    expect(
      tester.getRect(find.text('Test your light')),
      equals(buttonRectBefore),
    );
    expect(tester.getRect(find.text('4-channel')), equals(modeCardRectBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a disabled or failed lookup reads as "not checked", not "no match"',
    (tester) async {
      final fixture = _goldenFixture()..identityFromManual = true;
      final lookupClient = _FakeGdtfLookupClient();
      await _pumpCheckStep(
        tester,
        fixture: fixture,
        lookupClient: lookupClient,
      );

      lookupClient.complete(const GdtfLookupResult(enabled: false));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text(_notCheckedLabel), findsOneWidget);
      expect(find.text(_noMatchLabel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no status row at all when no lookup applies to the fixture', (
    tester,
  ) async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await _pumpCheckStep(
      tester,
      fixture: _goldenFixture(), // identityFromManual false by default
      lookupClient: lookupClient,
    );

    expect(state.gdtfLookupApplies, isFalse);
    expect(state.gdtfLookupPending, isFalse);
    expect(find.textContaining('GDTF Share'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every status row label fits on one line at 375px', (
    tester,
  ) async {
    // find.text alone would still match a clipped/ellipsized string, since
    // Text.data isn't what overflows — didExceedMaxLines is the real proof.
    // BeginnerPageShell's SelectionArea puts a MouseRegion between Text and
    // its RichText, so tester.renderObject(find.text(...)) resolves to that
    // MouseRegion instead — find the RichText descendant explicitly.
    bool exceedsOneLine(String text) => tester
        .renderObject<RenderParagraph>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        )
        .didExceedMaxLines;

    final pendingClient = _FakeGdtfLookupClient();
    await _pumpCheckStep(
      tester,
      fixture: _goldenFixture()..identityFromManual = true,
      lookupClient: pendingClient,
      width: 375,
    );
    expect(exceedsOneLine(_pendingLabel), isFalse);

    pendingClient.complete(_liveFixtureMatchesResult());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(exceedsOneLine(_matchLabel), isFalse);

    final noMatchClient = _FakeGdtfLookupClient();
    await _pumpCheckStep(
      tester,
      fixture: _goldenFixture()..identityFromManual = true,
      lookupClient: noMatchClient,
      width: 375,
    );
    noMatchClient.complete(const GdtfLookupResult(enabled: true, matches: []));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(exceedsOneLine(_noMatchLabel), isFalse);

    final notCheckedClient = _FakeGdtfLookupClient();
    await _pumpCheckStep(
      tester,
      fixture: _goldenFixture()..identityFromManual = true,
      lookupClient: notCheckedClient,
      width: 375,
    );
    notCheckedClient.complete(const GdtfLookupResult(enabled: false));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(exceedsOneLine(_notCheckedLabel), isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the status row scales with the text-scale setting', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final originalOnError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = originalOnError);

    // At this scale the header and step indicator overflow whether or not
    // the row is shown; collect those errors instead of failing on them.
    // The row's own fit is checked by geometry below.
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    await _pumpCheckStep(
      tester,
      fixture: _goldenFixture()..identityFromManual = true,
      lookupClient: _FakeGdtfLookupClient(),
    );
    FlutterError.onError = originalOnError; // restore before any expect()

    final rowFinder = find
        .ancestor(of: find.text(_pendingLabel), matching: find.byType(SizedBox))
        .first;
    expect(tester.getSize(rowFinder).height, 48); // 24 * textScaleFactor 2

    // The label must not paint past the row's right edge (it ellipsizes);
    // the tolerance is for sub-pixel rounding.
    expect(
      tester.getRect(find.text(_pendingLabel)).right,
      lessThanOrEqualTo(tester.getRect(rowFinder).right + 0.5),
    );
  });
}
