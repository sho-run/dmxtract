// Exercises the real DmxtractState._queueFixtureLookup wiring through
// ingest, editFixtureName, and undo/redo — not a hand-set copy of it (see
// gdtf_card_layout_test.dart for the widget-level coverage that does copy
// it). Runs on the VM, where the project store is the SharedPreferences
// stub, reset by setMockInitialValues between tests.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/gdtf_lookup.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each [search] call gets its own Completer, resolved independently and in
/// any order by the test. [appliesTo] always returns true: the golden
/// project has no manual behind it, so its real identityFromManual is
/// false, and this suite is about the pending/key/generation wiring, not
/// the applicability check (covered by gdtf_lookup_test.dart and
/// gdtf_card_layout_test.dart).
class _FakeGdtfLookupClient extends GdtfLookupClient {
  _FakeGdtfLookupClient()
    : super(client: MockClient((_) async => http.Response('', 404)));

  final calls = <Completer<GdtfLookupResult>>[];

  @override
  bool appliesTo(FixtureProject fixture) => true;

  @override
  Future<GdtfLookupResult> search(FixtureProject fixture) {
    final completer = Completer<GdtfLookupResult>();
    calls.add(completer);
    return completer.future;
  }
}

/// Same as [_FakeGdtfLookupClient], but leaves [appliesTo] as the real,
/// inherited implementation — needed for the one test below where
/// applicability itself, not just the search result, is what changes.
class _RealAppliesFakeClient extends GdtfLookupClient {
  _RealAppliesFakeClient()
    : super(client: MockClient((_) async => http.Response('', 404)));

  final calls = <Completer<GdtfLookupResult>>[];

  @override
  Future<GdtfLookupResult> search(FixtureProject fixture) {
    final completer = Completer<GdtfLookupResult>();
    calls.add(completer);
    return completer.future;
  }
}

// Real responses from POST https://dmxtract.sho.run/api/fixture-matches,
// recorded 2026-09-24. All four are ADJ fixtures, so the tests tell results
// apart by `fixture`. Each comment gives the model the request named.
const _encoreResponseJson = // "Encore LP12Z IP", as in gdtf_card_layout_test
    r'''{"enabled":true,"matches":[{"id":"80671","manufacturer":"ADJ","fixture":"Encore LP12Z IP","revision":"24-11-12 Release","source":"manufacturer","score":1,"url":"https://gdtf-share.com/share.php","rating":null,"version":"1.2","modeFootprints":[18,15,12,10,9,6]}]}''';
const _focusCmyResponseJson = // "FOCUS CMY COMPACT"
    r'''{"enabled":true,"matches":[{"id":"121705","manufacturer":"ADJ","fixture":"Focus CMY Compact","revision":"25-18-12 Release","source":"manufacturer","score":1,"url":"https://gdtf-share.com/share.php","rating":null,"version":"1.2","modeFootprints":[40,31,26]}]}''';
const _hydroBeamResponseJson = // "HYDRO BEAM CMY"
    r'''{"enabled":true,"matches":[{"id":"148136","manufacturer":"ADJ","fixture":"Hydro Beam CMY","revision":"Release 26-23-06","source":"manufacturer","score":1,"url":"https://gdtf-share.com/share.php","rating":null,"version":"1.2","modeFootprints":[24,20]}]}''';
const _strykerSpotResponseJson = // "STRYKER SPOT"
    r'''{"enabled":true,"matches":[{"id":"73806","manufacturer":"ADJ","fixture":"Stryker Spot","revision":"24-17-09 First Release","source":"manufacturer","score":1,"url":"https://gdtf-share.com/share.php","rating":null,"version":"1.2","modeFootprints":[18,16]}]}''';

GdtfLookupResult _parseResponse(String json) {
  final body = jsonDecode(json) as Map<String, Object?>;
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

/// Maps each test's distinguishing fixture-name label to one of the real
/// responses above — arbitrary but fixed, so a test can tell which
/// search's result landed without inventing match content.
GdtfLookupResult _resultFor(String label) => switch (label) {
  'DMXtract Test' => _parseResponse(_encoreResponseJson),
  'New Maker' || 'Edited Maker' => _parseResponse(_focusCmyResponseJson),
  'Second Maker' ||
  'Second Golden Maker' => _parseResponse(_hydroBeamResponseJson),
  _ => _parseResponse(_strykerSpotResponseJson),
};

/// The `fixture` (model name) of the real match [_resultFor] returns for
/// [label] — what a test asserts against instead of `manufacturer`, which
/// is "ADJ" for all four recorded responses.
String _fixtureNameFor(String label) =>
    _resultFor(label).matches.single.fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final offlineHttp = MockClient((_) async => http.Response('', 404));
  final goldenBytes = File(
    '../../golden/simple-rgbw.dmxtract.json',
  ).readAsBytesSync();
  final goldenText = utf8.decode(goldenBytes);

  Future<DmxtractState> reopenGolden(_FakeGdtfLookupClient lookupClient) async {
    SharedPreferences.setMockInitialValues({});
    final state = DmxtractState(
      lookupClient: lookupClient,
      httpClient: offlineHttp,
    );
    // Let the constructor's autosave restore finish first — otherwise it
    // can read back what ingest() is about to save and replace the
    // fixture again.
    await pumpEventQueue();
    await state.ingest(
      goldenBytes,
      'simple-rgbw.dmxtract.json',
      'application/json',
    );
    expect(state.error, isNull);
    return state;
  }

  test('ingest leaves the lookup pending, then a result fills it in', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);

    expect(state.gdtfLookupPending, isTrue);
    expect(state.gdtfMatches, isEmpty);
    expect(lookupClient.calls, hasLength(1));

    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    expect(state.gdtfLookupPending, isFalse);
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('DMXtract Test'));
    state.dispose();
  });

  test(
    'a stale lookup finishing after a newer one does not overwrite it',
    () async {
      final lookupClient = _FakeGdtfLookupClient();
      final state = await reopenGolden(lookupClient);
      expect(lookupClient.calls, hasLength(1)); // queued by ingest

      // editFixtureName changes the lookup key (manufacturer), so this
      // queues a second, independent search rather than reusing the first.
      state.editFixtureName('New Maker', '');
      expect(lookupClient.calls, hasLength(2));
      expect(state.gdtfLookupPending, isTrue);

      // Resolve the newer lookup first, then the stale one.
      lookupClient.calls[1].complete(_resultFor('New Maker'));
      await pumpEventQueue();
      expect(state.gdtfLookupPending, isFalse);
      expect(state.gdtfMatches.single.fixture, _fixtureNameFor('New Maker'));

      lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
      await pumpEventQueue();

      expect(state.gdtfLookupPending, isFalse);
      expect(state.gdtfMatches, hasLength(1));
      expect(state.gdtfMatches.single.fixture, _fixtureNameFor('New Maker'));
      state.dispose();
    },
  );

  test(
    'pending stays true across a requeue until the newest lookup settles',
    () async {
      final lookupClient = _FakeGdtfLookupClient();
      final state = await reopenGolden(lookupClient);

      state.editFixtureName('Second Maker', '');
      expect(state.gdtfLookupPending, isTrue);

      // The stale lookup settling must not clear pending — the newer one
      // queued by editFixtureName is still outstanding.
      lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
      await pumpEventQueue();
      expect(state.gdtfLookupPending, isTrue);

      lookupClient.calls[1].complete(_resultFor('Second Maker'));
      await pumpEventQueue();
      expect(state.gdtfLookupPending, isFalse);
      expect(state.gdtfMatches.single.fixture, _fixtureNameFor('Second Maker'));
      state.dispose();
    },
  );

  test('undo after a name edit requeues, and the final matches belong to '
      'the restored name', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);
    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    state.editFixtureName('New Maker', '');
    lookupClient.calls[1].complete(_resultFor('New Maker'));
    await pumpEventQueue();
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('New Maker'));

    state.undo();
    expect(state.fixture!.manufacturer, 'DMXtract Test');
    // The restored name's key differs from what was last queued (New
    // Maker's), so undo() requeues under it.
    expect(lookupClient.calls, hasLength(3));
    expect(state.gdtfLookupPending, isTrue);

    lookupClient.calls[2].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    expect(state.gdtfLookupPending, isFalse);
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('DMXtract Test'));
    state.dispose();
  });

  test('redo after undoing a name edit requeues, and the final matches '
      'belong to the redone name', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);
    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    state.editFixtureName('New Maker', '');
    lookupClient.calls[1].complete(_resultFor('New Maker'));
    await pumpEventQueue();

    state.undo();
    lookupClient.calls[2].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('DMXtract Test'));

    state.redo();
    expect(state.fixture!.manufacturer, 'New Maker');
    // The redone name's key differs from what was last queued (the
    // restored DMXtract Test's), so redo() requeues under it.
    expect(lookupClient.calls, hasLength(4));
    expect(state.gdtfLookupPending, isTrue);

    lookupClient.calls[3].complete(_resultFor('New Maker'));
    await pumpEventQueue();

    expect(state.gdtfLookupPending, isFalse);
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('New Maker'));
    state.dispose();
  });

  test('a mode-footprint change alone requeues the lookup', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);
    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    // Same manufacturer and model — drop a mode channel so the sorted
    // distinct footprint (part of the key) changes from [4] to [3].
    // editFixtureName with the fixture's own unchanged name is otherwise a
    // no-op (see the no-op-save test below), so it isolates the footprint
    // as the only thing that changed.
    state.fixture!.modes.first.channelIds.removeLast();
    state.editFixtureName('DMXtract Test', 'Simple RGBW');

    expect(lookupClient.calls, hasLength(2));
    expect(state.gdtfLookupPending, isTrue);
    lookupClient.calls[1].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();
    expect(state.gdtfLookupPending, isFalse);
    state.dispose();
  });

  test('applicability is part of the key: turning a fixture applicable '
      'requeues even though its names and footprints are unchanged', () async {
    final lookupClient = _RealAppliesFakeClient();
    SharedPreferences.setMockInitialValues({});
    final state = DmxtractState(
      lookupClient: lookupClient,
      httpClient: offlineHttp,
    );
    await pumpEventQueue();
    await state.ingest(
      goldenBytes,
      'simple-rgbw.dmxtract.json',
      'application/json',
    );
    // ingest always searches (force: true) regardless of applicability,
    // but the golden project's provenance has no identityFromManual, so
    // it defaults false and gdtfLookupApplies (the real, inherited
    // appliesTo) reports false.
    expect(state.gdtfLookupApplies, isFalse);
    expect(lookupClient.calls, hasLength(1));

    // Same manufacturer/model/footprints; only identityFromManual (part
    // of appliesTo) changes. editFixtureName with the fixture's own
    // unchanged name is otherwise a no-op (see the no-op-save test
    // below), so a second call here proves only applicability made the
    // key change.
    state.fixture!.identityFromManual = true;
    state.editFixtureName('DMXtract Test', 'Simple RGBW');

    expect(state.gdtfLookupApplies, isTrue);
    expect(state.gdtfLookupPending, isTrue);
    expect(lookupClient.calls, hasLength(2));
    state.dispose();
  });

  test('undo after a later, unrelated ingest still reverts to the earlier '
      'edit, and requeues under it', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);
    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    // An edit records an undo step for this project...
    state.editFixtureName('Edited Maker', '');
    lookupClient.calls[1].complete(_resultFor('Edited Maker'));
    await pumpEventQueue();

    // ...then a second, distinct project is ingested. ingest() never
    // touches the undo stack, so the edit's undo step survives it.
    final second = jsonDecode(goldenText) as Map<String, Object?>;
    second['identity'] = {
      ...second['identity'] as Map<String, Object?>,
      'manufacturer': 'Second Golden Maker',
    };
    await state.ingest(
      Uint8List.fromList(utf8.encode(jsonEncode(second))),
      'second.dmxtract.json',
      'application/json',
    );
    expect(state.canUndo, isTrue);
    lookupClient.calls[2].complete(_resultFor('Second Golden Maker'));
    await pumpEventQueue();

    state.undo();

    expect(state.fixture!.manufacturer, 'DMXtract Test');
    expect(state.gdtfLookupPending, isTrue);
    lookupClient.calls[3].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('DMXtract Test'));
    state.dispose();
  });

  test('a no-op save does not requeue the lookup', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);
    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();

    // Re-submitting the fixture's own current name: the key is unchanged.
    state.editFixtureName('DMXtract Test', 'Simple RGBW');
    await pumpEventQueue();

    expect(lookupClient.calls, hasLength(1));
    expect(state.gdtfLookupPending, isFalse);
    state.dispose();
  });

  test('a load always searches again under the same key, so a failed search '
      'can be retried', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient);
    lookupClient.calls[0].complete(const GdtfLookupResult(enabled: false));
    await pumpEventQueue();
    expect(state.gdtfLookupEnabled, isFalse);
    expect(state.gdtfMatches, isEmpty);

    // Re-ingesting the exact same bytes (same key) must still search
    // again: ingest is a load, so it calls _queueFixtureLookup(force:
    // true), which is unconditional.
    await state.ingest(
      goldenBytes,
      'simple-rgbw.dmxtract.json',
      'application/json',
    );
    expect(lookupClient.calls, hasLength(2));

    lookupClient.calls[1].complete(_resultFor('DMXtract Test'));
    await pumpEventQueue();
    expect(state.gdtfLookupEnabled, isTrue);
    expect(state.gdtfMatches.single.fixture, _fixtureNameFor('DMXtract Test'));
    state.dispose();
  });

  test("a fixture's search settling while the next load's save is still "
      'pending does not land on the fixture that replaced it', () async {
    final lookupClient = _FakeGdtfLookupClient();
    final state = await reopenGolden(lookupClient); // A: "DMXtract Test"
    expect(lookupClient.calls, hasLength(1));

    // Start loading a second, distinct project without awaiting yet.
    // ingest() now calls _queueFixtureLookup(force: true) for the new
    // fixture before its own `await _save()`, so it runs synchronously
    // up through that call and suspends on the save, handing control
    // back here — B's own search is queued before this line returns.
    final second = jsonDecode(goldenText) as Map<String, Object?>;
    second['identity'] = {
      ...second['identity'] as Map<String, Object?>,
      'manufacturer': 'Second Golden Maker',
    };
    final ingestB = state.ingest(
      Uint8List.fromList(utf8.encode(jsonEncode(second))),
      'second.dmxtract.json',
      'application/json',
    );
    expect(lookupClient.calls, hasLength(2)); // B already queued its own
    expect(state.fixture!.manufacturer, 'Second Golden Maker');

    // A's search settles while B's ingest is still suspended on _save().
    lookupClient.calls[0].complete(_resultFor('DMXtract Test'));

    await ingestB;
    await pumpEventQueue();

    // A's result must not have landed on B.
    expect(state.fixture!.manufacturer, 'Second Golden Maker');
    expect(state.gdtfMatches, isEmpty);
    expect(state.gdtfLookupPending, isTrue); // B's own search still out

    lookupClient.calls[1].complete(_resultFor('Second Golden Maker'));
    await pumpEventQueue();
    expect(state.gdtfLookupPending, isFalse);
    expect(
      state.gdtfMatches.single.fixture,
      _fixtureNameFor('Second Golden Maker'),
    );
    state.dispose();
  });
}
