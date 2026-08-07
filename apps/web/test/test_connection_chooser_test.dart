// Widget tests for the "How is your light connected?" chooser on the Test
// step (lib/src/screens/test_light.dart): capability gating for the USB
// Web Serial card and card-selection navigation between the four connection
// options. Runs on the browser platform because test_light.dart pulls in
// package:web transitively (via components.dart and webserial_dmx.dart),
// same as test/mobile_layout_test.dart.
@TestOn('browser')
library;

import 'package:dmxtract_web/src/app_state.dart';
import 'package:dmxtract_web/src/components.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:dmxtract_web/src/screens/test_light.dart';
import 'package:dmxtract_web/src/theme.dart';
import 'package:dmxtract_web/src/webserial_dmx.dart';
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
      id: 'test-fixture',
      manufacturer: 'Acme',
      model: 'Par 64',
      channels: [channel],
      modes: [
        FixtureMode(id: 'mode-1', name: 'Standard', channelIds: ['dimmer']),
      ],
    );
  }

  Future<DmxtractState> pumpTestStep(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = DmxtractState()
      ..fixture = buildFixture()
      ..step = 2;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: dmxTheme(),
        home: DmxScope(
          state: state,
          child: const BeginnerPageShell(child: TestLightScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  group('connection chooser', () {
    testWidgets('shows all four cards, none pre-selected', (tester) async {
      await pumpTestStep(tester);

      expect(find.text('How is your light connected?'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('USB DMX cable or dongle'), findsOneWidget);
      expect(find.text('Network node (Art-Net / sACN)'), findsOneWidget);
      expect(find.text('My own lighting software or console'), findsOneWidget);
      expect(find.text('Just checking the numbers'), findsOneWidget);
      // The guided tester and "Change connection" only appear once a card
      // is picked.
      expect(find.text('Change connection'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'USB DMX card capability gating matches navigator.serial support',
      (tester) async {
        await pumpTestStep(tester);
        final usbCard = find.text('USB DMX cable or dongle');
        expect(usbCard, findsOneWidget);

        if (isWebSerialSupported) {
          await tester.tap(usbCard);
          await tester.pumpAndSettle();
          expect(find.text('Connect your USB DMX cable'), findsOneWidget);
        } else {
          expect(find.textContaining('needs Chrome or Edge'), findsOneWidget);
          await tester.tap(usbCard);
          await tester.pumpAndSettle();
          // A disabled card must not navigate away from the chooser.
          expect(find.text('How is your light connected?'), findsOneWidget);
          expect(find.text('Connect your USB DMX cable'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('selecting Network node opens the existing bridge flow', (
      tester,
    ) async {
      await pumpTestStep(tester);

      await tester.tap(find.text('Network node (Art-Net / sACN)'));
      await tester.pumpAndSettle();

      expect(find.text('Connect your DMX output'), findsOneWidget);
      expect(find.text('Bridge not running'), findsOneWidget);
      expect(find.text('Change connection'), findsOneWidget);
      // The guided tester (address checklist) is present behind this card
      // too, same as every other connection option.
      expect(
        find.text('Where your light listens — DMX address'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Network node not-running state offers a "Launch bridge" affordance',
      (tester) async {
        await pumpTestStep(tester);

        await tester.tap(find.text('Network node (Art-Net / sACN)'));
        await tester.pumpAndSettle();

        expect(find.text('Bridge not running'), findsOneWidget);
        expect(find.text('Launch bridge'), findsOneWidget);
        // Quiet fallback line only shows after polling gives up, not up
        // front — the browser can never confirm the custom scheme is
        // registered, so nothing here may claim failure before the health
        // check has even had a chance to see the bridge come up.
        expect(find.textContaining('Nothing happened?'), findsNothing);

        await tester.ensureVisible(find.text('Launch bridge'));
        await tester.tap(find.text('Launch bridge'));
        await tester.pump();

        // Immediately after the click it's still just "waiting" — the
        // "nothing happened" line only appears once the affordance's
        // polling gives up (see below), not on the same frame as the click.
        expect(find.textContaining('Waiting for the bridge'), findsOneWidget);
        expect(find.textContaining('Nothing happened?'), findsNothing);
        expect(tester.takeException(), isNull);

        // Leave the card before the affordance's polling Timer.periodic
        // (first tick at 2s) ever fires, so its dispose() cancels the timer
        // instead of this test making a real network call to the bridge
        // health check or leaving a pending timer at teardown.
        await tester.ensureVisible(find.text('Change connection'));
        await tester.tap(find.text('Change connection'));
        await tester.pumpAndSettle();
        expect(find.text('How is your light connected?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    group('manual console flow (card 3)', () {
      testWidgets('starts with the download-profile prompt', (tester) async {
        await pumpTestStep(tester);

        await tester.tap(find.text('My own lighting software or console'));
        await tester.pumpAndSettle();

        expect(find.text('Download OFL'), findsOneWidget);
        expect(find.text('Download GDTF'), findsOneWidget);
        expect(find.text("I've loaded it — continue"), findsOneWidget);
        // Neither the checklist nor the guided tester show until the
        // download + software steps are done.
        expect(
          find.text('Where your light listens — DMX address'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('then a short, neutral software picker', (tester) async {
        await pumpTestStep(tester);

        await tester.tap(find.text('My own lighting software or console'));
        await tester.pumpAndSettle();
        await tester.tap(find.text("I've loaded it — continue"));
        await tester.pumpAndSettle();

        expect(
          find.text('Which software or console are you using?'),
          findsOneWidget,
        );
        expect(find.text('QLC+'), findsOneWidget);
        expect(find.text('Console or other software'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'then the shared checklist + guided tester, instruction-driven and with zero output',
        (tester) async {
          final state = await pumpTestStep(tester);

          await tester.tap(find.text('My own lighting software or console'));
          await tester.pumpAndSettle();
          await tester.tap(find.text("I've loaded it — continue"));
          await tester.pumpAndSettle();
          await tester.tap(find.text('QLC+'));
          await tester.pumpAndSettle();

          // Shared checklist card, same as every other connection option.
          expect(
            find.text('Where your light listens — DMX address'),
            findsOneWidget,
          );
          // Shared guided tester, reworded for instruction-driven testing.
          expect(find.text('Dimmer'), findsOneWidget);
          expect(find.textContaining('Set this in QLC+'), findsOneWidget);
          expect(find.text('You should expect'), findsNothing);
          // No transport was ever attached: zero DMX from this browser.
          expect(state.outputActive, isFalse);
          expect(state.output, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    });

    testWidgets(
      'selecting "just checking the numbers" starts the virtual output and works in every browser',
      (tester) async {
        await pumpTestStep(tester);

        await tester.tap(find.text('Just checking the numbers'));
        await tester.pumpAndSettle();

        expect(find.text('Preview channel values'), findsOneWidget);
        await tester.tap(find.text('Preview channel values'));
        await tester.pumpAndSettle();

        expect(find.text('Previewing only'), findsOneWidget);
        // The shared guided tester renders on top of the virtual output too.
        expect(find.text('Dimmer'), findsOneWidget);
        expect(find.text('You should expect'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Change connection returns to the chooser', (tester) async {
      await pumpTestStep(tester);

      await tester.tap(find.text('Just checking the numbers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview channel values'));
      await tester.pumpAndSettle();

      // "Change connection" is intentionally replaced by "Stop output"
      // while a session is live (_Header in test_light.dart) — stop it
      // first, same as a real user would have to.
      await tester.tap(find.text('Stop output'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change connection'));
      await tester.pumpAndSettle();

      expect(find.text('How is your light connected?'), findsOneWidget);
      expect(find.text('Change connection'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  test('TestConnectionOption has a stable, enumerable member set', () {
    expect(TestConnectionOption.values, [
      TestConnectionOption.usbSerial,
      TestConnectionOption.networkNode,
      TestConnectionOption.manualConsoleTest,
      TestConnectionOption.virtual,
    ]);
  });
}
