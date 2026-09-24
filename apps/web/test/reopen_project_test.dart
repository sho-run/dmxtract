// Editing a project reopened from its .dmxtract.json file. The project is
// the repository's golden fixture, golden/simple-rgbw.dmxtract.json.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/gdtf_lookup.dart';
import 'package:dmxtract_web/src/project_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // No network in tests: every request answers 404, which the app treats as
  // "no fixture lookup" and "no phone link".
  final offline = MockClient((_) async => http.Response('', 404));

  Future<DmxtractState> reopenGolden() async {
    SharedPreferences.setMockInitialValues({});
    final state = DmxtractState(
      lookupClient: GdtfLookupClient(client: offline),
      httpClient: offline,
    );
    // Let the constructor's autosave restore finish first. Otherwise it
    // reads back the project ingest() has just saved, replaces the fixture
    // and resets the status.
    await pumpEventQueue();
    await state.ingest(
      File('../../golden/simple-rgbw.dmxtract.json').readAsBytesSync(),
      'simple-rgbw.dmxtract.json',
      'application/json',
    );
    expect(state.error, isNull);
    expect(state.status, 'Opened your editable project');
    return state;
  }

  test('a channel of a reopened project can be edited and is saved', () async {
    final state = await reopenGolden();
    var notified = 0;
    state.addListener(() => notified++);
    final channel = state.fixture!.channels.first;

    state.editChannel(
      0,
      'Red LED',
      channel.gdtfAttribute ?? '',
      channel.gdtfFeature ?? '',
      channel.kind,
      channel.ranges,
    );

    expect(state.fixture!.channels.first.name, 'Red LED');
    expect(notified, greaterThan(0));
    final saved = jsonDecode((await loadProject())!) as Map<String, Object?>;
    expect(((saved['channels'] as List).first as Map)['name'], 'Red LED');
    state.dispose();
  });

  test('the name of a reopened project can be edited and is saved', () async {
    final state = await reopenGolden();
    var notified = 0;
    state.addListener(() => notified++);

    state.editFixtureName('DMXtract Test', 'Simple RGBW 2');

    expect(state.fixture!.model, 'Simple RGBW 2');
    expect(notified, greaterThan(0));
    final saved = jsonDecode((await loadProject())!) as Map<String, Object?>;
    expect((saved['identity'] as Map)['model'], 'Simple RGBW 2');
    state.dispose();
  });
}
