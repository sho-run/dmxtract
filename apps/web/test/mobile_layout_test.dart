@TestOn('browser')
library;

import 'dart:convert';

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/components.dart';
import 'package:dmxtract_web/src/screens/add_manual.dart';
import 'package:dmxtract_web/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<DmxtractState> pumpPhone(
    WidgetTester tester, {
    List<ManualPhoto> photos = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DmxtractState()..addPhotos(photos);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: dmxTheme(),
        home: DmxScope(
          state: state,
          child: const BeginnerPageShell(child: AddManualScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('phone shell is compact and keeps both input paths visible', (
    tester,
  ) async {
    await pumpPhone(tester);

    expect(
      find.text('Build a fixture profile from the manual you already have.'),
      findsNothing,
    );
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Take or add photos'), findsOneWidget);
    expect(find.text('Choose PDF or project'), findsOneWidget);
    expect(find.text('By sho.run'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone photo tray shows ordered local controls', (tester) async {
    final pixel = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await pumpPhone(
      tester,
      photos: [
        ManualPhoto(bytes: pixel, name: 'one.png', mime: 'image/png'),
        ManualPhoto(bytes: pixel, name: 'two.png', mime: 'image/png'),
      ],
    );

    expect(find.text('2 photos ready'), findsOneWidget);
    expect(find.text('Add more'), findsOneWidget);
    expect(find.text('Read 2 photos'), findsOneWidget);
    expect(find.byTooltip('Remove photo 1'), findsOneWidget);
    expect(find.byTooltip('Move photo 2 earlier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
