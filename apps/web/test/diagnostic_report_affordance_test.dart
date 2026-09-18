// Widget test for the "share what we read" diagnostic-export affordance on
// the Check step (lib/src/screens/review.dart +
// lib/src/diagnostic_report_affordance.dart). Runs on the browser platform
// for the same reason as test/fixture_name_edit_test.dart: review.dart pulls
// in package:web transitively.
@TestOn('browser')
library;

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/components.dart';
import 'package:dmxtract_web/src/diagnostic_report_affordance.dart';
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

  testWidgets('Check step offers to download what we read and report a bug', (
    tester,
  ) async {
    await pumpReview(tester);

    final affordance = find.byType(DiagnosticReportAffordance);
    expect(affordance, findsOneWidget);
    expect(find.text('Not what the manual says?'), findsOneWidget);
    expect(find.text('Download what we read'), findsOneWidget);
    // The page footer (BeginnerPageShell) already has its own "Report a
    // bug" link, so scope this finder to the affordance itself rather than
    // asserting there is exactly one on the whole page.
    expect(
      find.descendant(of: affordance, matching: find.text('Report a bug')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the affordance renders nothing before a fixture exists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = DmxtractState();
    addTearDown(state.dispose);
    expect(state.fixture, isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: dmxTheme(),
        home: Scaffold(body: DiagnosticReportAffordance(state: state)),
      ),
    );

    expect(find.text('Not what the manual says?'), findsNothing);
    expect(find.text('Download what we read'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
