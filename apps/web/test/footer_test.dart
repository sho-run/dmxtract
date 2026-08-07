@TestOn('browser')
library;

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/components.dart';
import 'package:dmxtract_web/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpShell(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DmxtractState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: dmxTheme(),
        home: DmxScope(
          state: state,
          child: const BeginnerPageShell(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('footer offers a bug-report link', (tester) async {
    await pumpShell(tester);

    expect(find.text('Report a bug'), findsOneWidget);
  });

  test('bug-report link falls back to the public issue tracker', () {
    // No DMXTRACT_BUG_REPORT_URL define is set under `flutter test`, so the
    // compile-time fallback must point at the repository issue tracker.
    expect(bugReportUrl, 'https://github.com/sho-run/dmxtract/issues');
  });
}
