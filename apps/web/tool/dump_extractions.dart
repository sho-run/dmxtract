// Batch-runs the extractor over a directory of page-marked manual text files
// and writes one full serialized fixture JSON per input, using the exact
// same encode() the app uses for .dmxtract.json export. This is the
// offline half of the scripts/eval/ benchmark: it produces the "extracts"
// dir that scripts/eval/score_extraction.py scores against GDTF ground
// truth.
//
// Deliberately a plain Dart entry point (no Flutter, no test harness):
// lib/src/extraction_rules.dart and lib/src/model.dart only import
// dart:convert and lib/src/gdtf_attribute_catalog.dart, so `dart run` works
// directly against the package's existing .dart_tool/package_config.json
// (no `flutter pub get` / test-harness bootstrap needed).
//
// Usage:
//   dart run tool/dump_extractions.dart <input-text-dir> <output-dir>
//
// Input: a directory of *.txt files, each page-marked the way the app's own
// PDF/OCR pipeline marks them ("=== DMXTRACT PAGE N ===" before each page's
// text) - see lib/src/manual_extractor_web.dart.
//
// Output: for every <name>.txt, writes <output-dir>/<name>.json (the
// FixtureProject's encode() output) plus a SUMMARY.txt with one line per
// fixture (identity + mode footprint list) for a quick human scan.
import 'dart:io';

import 'package:dmxtract_web/src/extraction_rules.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/dump_extractions.dart <input-text-dir> <output-dir>',
    );
    exit(2);
  }
  final inputDir = Directory(args[0]);
  final outputDir = Directory(args[1]);
  if (!inputDir.existsSync()) {
    stderr.writeln('input dir not found: ${inputDir.path}');
    exit(2);
  }
  outputDir.createSync(recursive: true);

  final txtFiles =
      inputDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.txt'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  if (txtFiles.isEmpty) {
    stderr.writeln('no .txt files found in ${inputDir.path}');
    exit(2);
  }

  final summary = StringBuffer();
  var ok = 0;
  var failed = 0;
  for (final file in txtFiles) {
    final base = _basenameWithoutExtension(file.path);
    final sourceName = '$base.pdf';
    try {
      final text = file.readAsStringSync();
      final result = fixtureFromManualText(text, sourceName);
      final fixture = result.fixture;
      final outFile = File('${outputDir.path}/$base.json');
      outFile.writeAsStringSync(fixture.encode());
      final modeSummary = fixture.modes
          .map((m) => '${m.name}:${m.channelIds.length}')
          .join(',');
      summary.writeln(
        '$base || ${fixture.manufacturer} | ${fixture.model} || '
        'modes [$modeSummary]',
      );
      ok++;
    } catch (e, st) {
      summary.writeln('$base || EXTRACTION_FAILED: $e');
      stderr.writeln('FAILED $base: $e\n$st');
      failed++;
    }
  }
  File('${outputDir.path}/SUMMARY.txt').writeAsStringSync(summary.toString());
  stdout.writeln(
    'dumped $ok fixture(s), $failed failure(s), to ${outputDir.path}',
  );
  if (failed > 0) exit(1);
}

String _basenameWithoutExtension(String path) {
  final base = path.split(Platform.pathSeparator).last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? base : base.substring(0, dot);
}
