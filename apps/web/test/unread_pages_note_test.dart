// The Check-step note for pages manual_extractor.js could not OCR
// (unreadPagesNote in lib/src/app_state.dart). The page lists are the ones
// extractPdf() reported with OCR forced to fail in headless Chrome.
import 'package:dmxtract_web/src/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no note when every OCR read worked', () {
    expect(unreadPagesNote(const []), isNull);
  });

  test('names a single page', () {
    // ADJ 7P Hex IP with every OCR read failing.
    expect(
      unreadPagesNote(const [1]),
      'We could not fully read page 1, so anything printed only there may '
      'be missing. Choosing the manual again may fix this.',
    );
  });

  test('shows consecutive pages as ranges', () {
    // Betopper LM3715R with only the detailed table reads failing.
    expect(
      unreadPagesNote([7, 8, for (var page = 10; page <= 21; page++) page]),
      startsWith('We could not fully read pages 7–8 and 10–21, '),
    );
    // ADJ 7PZ IP with every OCR read failing.
    expect(
      unreadPagesNote(const [1, 6, 24, 25, 26]),
      startsWith('We could not fully read pages 1, 6 and 24–26, '),
    );
  });
}
