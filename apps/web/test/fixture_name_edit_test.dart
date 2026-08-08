// Widget tests for the fixture-name pencil affordance on the Check step's
// header card (lib/src/screens/review.dart + lib/src/fixture_name_editor.dart).
// Runs on the browser platform because review.dart pulls in package:web
// transitively (the "Get from GDTF Share" link opener), same reasoning as
// test/test_connection_chooser_test.dart.
@TestOn('browser')
library;

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/components.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:dmxtract_web/src/screens/review.dart';
import 'package:dmxtract_web/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FixtureProject buildFixture() {
    final channel = DmxChannel(
      id: 'dimmer',
      name: 'Dimmer',
      kind: 'intensity',
      ranges: [DmxRange(start: 0, end: 255, name: 'Intensity')],
    );
    return FixtureProject(
      id: 'unknown-par-64',
      manufacturer: 'Unknown manufacturer',
      model: 'Par 64',
      channels: [channel],
      modes: [
        FixtureMode(id: 'mode-1', name: 'Standard', channelIds: ['dimmer']),
      ],
    );
  }

  Future<DmxtractState> pumpReview(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DmxtractState()
      ..fixture = buildFixture()
      ..questions = ['We could not find the maker name.']
      ..step = 1;
    addTearDown(state.dispose);
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

  testWidgets('pencil on the fixture-name card opens the name editor', (
    tester,
  ) async {
    await pumpReview(tester);

    expect(find.text('Unknown manufacturer Par 64'), findsOneWidget);
    expect(find.text('Edit fixture name'), findsNothing);

    await tester.tap(find.byTooltip('Edit fixture name'));
    await tester.pumpAndSettle();

    expect(find.text('Edit fixture name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Manufacturer'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Model'), findsOneWidget);
    // Manufacturer started with "Unknown" so the field starts blank with a
    // hint, rather than prefilled with the placeholder text itself.
    final manufacturerField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Manufacturer'),
    );
    expect(manufacturerField.initialValue, isEmpty);
    // Model was a real extracted value, so it stays prefilled.
    final modelField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Model'),
    );
    expect(modelField.initialValue, 'Par 64');

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entering names updates the header and clears the maker help item',
    (tester) async {
      final state = await pumpReview(tester);

      expect(
        find.textContaining('We could not find the maker name.'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Edit fixture name'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Manufacturer'),
        'Generic',
      );
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Edit fixture name'), findsNothing);
      expect(find.text('Generic Par 64'), findsOneWidget);
      expect(find.textContaining('We found a Generic Par 64'), findsOneWidget);
      expect(
        find.textContaining('We could not find the maker name.'),
        findsNothing,
      );
      expect(state.fixture!.manufacturer, 'Generic');
      expect(state.questions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling the editor makes no changes', (tester) async {
    final state = await pumpReview(tester);

    await tester.tap(find.byTooltip('Edit fixture name'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Manufacturer'),
      'Should not be saved',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Edit fixture name'), findsNothing);
    expect(state.fixture!.manufacturer, 'Unknown manufacturer');
    expect(
      find.textContaining('We could not find the maker name.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
