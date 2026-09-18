import 'dart:convert';
import 'dart:typed_data';
import 'model.dart';

/// Builds the "share what we read" diagnostic bundle: a small JSON file the
/// user can download and choose to attach to a bug report when an
/// extraction is wrong or fails, so it becomes a corpus contribution
/// instead of a bad review.
///
/// Privacy-first by construction — it contains only what the parser already
/// produced locally:
///  - the page-marked text [fixtureFromManualText] actually saw
///    ("=== DMXTRACT PAGE N ===" markers and all, matching the app's own
///    extraction pipeline),
///  - the canonical fixture JSON that text produced,
///  - the source file's name, and
///  - this bundle's own schema/version identifiers.
///
/// It never includes the original manual bytes, a photo, or anything else
/// that did not already pass through the local parser. Nothing is
/// transmitted by the app — the caller triggers a normal browser download,
/// and sending the file anywhere is a separate, manual act by the user.
Uint8List exportDiagnosticReport({
  required String extractedText,
  required FixtureProject fixture,
  required String sourceFileName,
}) {
  final json = {
    'schema': 'https://dmxtract.sho.run/schemas/diagnostic-report-v1.json',
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sourceFileName': sourceFileName,
    'extractedText': extractedText,
    'fixture': fixture.toJson(),
  };
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
  );
}
