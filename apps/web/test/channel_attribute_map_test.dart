@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('channel attribute map generator determinism', () {
    test('regenerating from the same database twice produces byte-identical '
        'output, and curates the way the docstring promises', () {
      final tmp = Directory.systemTemp.createTempSync('channel_attr_det_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final dbPath = '${tmp.path}/sample.db';
      // A small, fixed sample standing in for unified.db's `channel` table
      // shape:
      //  - 'Dimmer' -> 'Dimmer': a strong, unzoned majority (kept as-is).
      //  - 'Gobo 1'/'Gobo 2' -> 'Gobo1'/'Gobo2': a zoned pair that should
      //    template onto ONE shared 'Gobo{n}' entry rather than splitting
      //    the vote between a concrete and a templated form.
      //  - 'Ambiguous' -> 'FooBar' (40) vs 'BazQux' (20): total clears
      //    MIN_TOTAL but no majority clears MIN_RATIO - dropped as
      //    unresolved.
      //  - 'Rare' -> 'Rare1' (10): below MIN_TOTAL - dropped, not enough
      //    evidence either way.
      //  - 'Junk' -> 'Main <> FX' (50): not a plausible bare attribute
      //    token - dropped regardless of volume.
      //  - 'Reserved' -> 'NoFeature' (60): a clean majority, but dropped
      //    because the app's own default already returns NoFeature for
      //    anything unclassified, so the entry would change nothing.
      final rows = <String>[
        for (var i = 0; i < 60; i++) "('Dimmer', 'Dimmer')",
        for (var i = 0; i < 10; i++) "('Gobo 1', 'Gobo1')",
        for (var i = 0; i < 40; i++) "('Gobo 2', 'Gobo2')",
        for (var i = 0; i < 40; i++) "('Ambiguous', 'FooBar')",
        for (var i = 0; i < 20; i++) "('Ambiguous', 'BazQux')",
        for (var i = 0; i < 10; i++) "('Rare', 'Rare1')",
        for (var i = 0; i < 50; i++) "('Junk', 'Main <> FX')",
        for (var i = 0; i < 60; i++) "('Reserved', 'NoFeature')",
      ];
      final createSql =
          '''
CREATE TABLE channel (channel_id INTEGER PRIMARY KEY, pretty TEXT, attribute TEXT);
INSERT INTO channel (pretty, attribute) VALUES
  ${rows.join(',\n  ')};
''';
      final create = Process.runSync('sqlite3', [dbPath, createSql]);
      expect(
        create.exitCode,
        0,
        reason:
            'sqlite3 CLI must be available to build the sample db: '
            '${create.stderr}',
      );

      final scriptPath = '../../scripts/update_channel_attribute_map.py';
      final out1 = '${tmp.path}/run1.g.dart';
      final out2 = '${tmp.path}/run2.g.dart';
      final run1 = Process.runSync('python3', [scriptPath, dbPath, out1]);
      final run2 = Process.runSync('python3', [scriptPath, dbPath, out2]);
      expect(run1.exitCode, 0, reason: run1.stderr.toString());
      expect(run2.exitCode, 0, reason: run2.stderr.toString());

      final text1 = File(out1).readAsStringSync();
      final text2 = File(out2).readAsStringSync();
      expect(text1, text2);

      expect(text1.contains("'dimmer': 'Dimmer'"), isTrue);
      expect(text1.contains("'gobo': 'Gobo{n}'"), isTrue);
      expect(text1.contains("'Gobo1'"), isFalse);
      expect(text1.contains("'Gobo2'"), isFalse);
      expect(text1.contains('ambiguous'), isFalse);
      expect(text1.contains('rare'), isFalse);
      expect(text1.contains('junk'), isFalse);
      expect(text1.contains('Main'), isFalse);
      expect(text1.contains('reserved'), isFalse);
      expect(text1.contains('NoFeature'), isFalse);
    });
  });
}
