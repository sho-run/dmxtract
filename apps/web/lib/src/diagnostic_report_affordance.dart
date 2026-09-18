import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'app_state.dart';
import 'components.dart';
import 'diagnostic_report.dart';
import 'download.dart';
import 'model.dart';
import 'theme.dart';

/// A low-key "share what we read" affordance for turning a wrong or failed
/// extraction into a corpus contribution instead of a bad review, in line
/// with the "Stays on this device" ethos: nothing is sent by the app
/// itself, the person explicitly downloads a file and separately chooses to
/// attach it to a bug report.
///
/// Mounted from two unpatched spots: the Check step's help-items area
/// (screens/review.dart) and the "we could not find a DMX table" card
/// (screens/add_manual.dart). Kept as its own widget rather than inlined in
/// either screen so it stays out of the private deployment overlay's
/// exact-string patch regions in add_manual.dart.
class DiagnosticReportAffordance extends StatelessWidget {
  const DiagnosticReportAffordance({super.key, required this.state});
  final DmxtractState state;

  @override
  Widget build(BuildContext context) {
    final fixture = state.fixture;
    if (fixture == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          const Text(
            'Not what the manual says?',
            style: TextStyle(color: DmxColors.muted, fontSize: 13),
          ),
          _InlineLinkButton(
            label: 'Download what we read',
            onPressed: () => _download(fixture),
          ),
          const Text(
            'and attach it to a bug report.',
            style: TextStyle(color: DmxColors.muted, fontSize: 13),
          ),
          _InlineLinkButton(label: 'Report a bug', onPressed: _openBugReport),
        ],
      ),
    );
  }

  void _download(FixtureProject fixture) => downloadBytes(
    '${slug(fixture.manufacturer)}-${slug(fixture.model)}.dmxtract-report.json',
    'application/json',
    exportDiagnosticReport(
      extractedText: state.manualText,
      fixture: fixture,
      sourceFileName: state.manualName ?? 'unknown',
    ),
  );

  void _openBugReport() {
    if (bugReportUrl.startsWith('mailto:')) {
      // Same reasoning as components.dart's footer link: opening a mailto:
      // in a new tab leaves an empty tab behind in Chrome.
      web.window.location.href = bugReportUrl;
    } else {
      web.window.open(bugReportUrl, '_blank', 'noopener,noreferrer');
    }
  }
}

class _InlineLinkButton extends StatelessWidget {
  const _InlineLinkButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}
