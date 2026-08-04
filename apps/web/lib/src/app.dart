import 'package:flutter/material.dart';
import 'app_state.dart';
import 'components.dart';
import 'screens/add_manual.dart';
import 'screens/download_profile.dart';
import 'screens/review.dart';
import 'screens/test_light.dart';
import 'theme.dart';

class DmxtractApp extends StatefulWidget {
  const DmxtractApp({super.key});
  @override
  State<DmxtractApp> createState() => _DmxtractAppState();
}

class _DmxtractAppState extends State<DmxtractApp> {
  late final DmxtractState state = DmxtractState();
  @override
  void dispose() {
    if (state.outputActive) state.stopOutput();
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DmxScope(
    state: state,
    child: MaterialApp(
      title: 'DMXtract',
      debugShowCheckedModeBanner: false,
      theme: dmxTheme(),
      home: const BeginnerPageShell(child: _CurrentScreen()),
    ),
  );
}

class _CurrentScreen extends StatelessWidget {
  const _CurrentScreen();
  @override
  Widget build(BuildContext context) {
    final state = DmxScope.of(context);
    final screen = switch (state.step) {
      0 => const AddManualScreen(),
      1 =>
        state.fixture == null ? const AddManualScreen() : const ReviewScreen(),
      2 =>
        state.fixture == null
            ? const AddManualScreen()
            : const TestLightScreen(),
      _ =>
        state.fixture == null
            ? const AddManualScreen()
            : const DownloadProfileScreen(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(key: ValueKey(state.step), child: screen),
    );
  }
}
