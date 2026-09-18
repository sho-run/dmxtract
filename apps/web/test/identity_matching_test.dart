@TestOn('vm')
library;

// Unit tests for the identity pack: evidence-based manufacturer matching
// (glyph tolerance, honorific/role-title rejection, no-evidence rejection),
// the resulting confidence tiers, and the brand catalog generator's
// determinism. All matcher tests go through the public
// `fixtureFromManualText` API, same as the rest of extraction_rules_test.dart
// - the matcher itself is private, so this exercises it the same way real
// manuals do.

import 'dart:io';

import 'package:dmxtract_web/src/extraction_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('glued trademark glyph tolerance', () {
    test('matches a brand with a ® glued directly onto it with no space '
        '(real corpus shape: "BRITEQ®" on every running-header page)', () {
      final result = fixtureFromManualText(
        'BRITEQ®                                             1/16'
            '                              BTI-BLIZZARD PROFILE\n'
            'Thank you for buying this Briteq® product. 6CH mode Pan Tilt Dimmer',
        'BTIBlizzardProfile_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Briteq');
    });

    test('matches a brand with a © glued directly in front of it with no '
        'space', () {
      // Real corpus shape (ADJ_Elektron_Bar_FX_UM.txt, filed under an ADJ
      // filename but actually made by Eliminator): the glued "©Eliminator"
      // mention plus enough repeated Eliminator mentions through the
      // manual's own legal boilerplate to clear the minimum-evidence bar
      // - a single glued mention alone isn't enough real-world signal to
      // safely trust over an honest "Unknown manufacturer".
      final result = fixtureFromManualText(
        '©Eliminator all rights reserved. Information, specifications, '
            'diagrams, images, and instructions herein are subject to '
            'change without notice. Eliminator logo and identifying '
            'product names and numbers herein are trademarks of Eliminator '
            'Lighting. All non-Eliminator brands and product names are '
            'trademarks or registered trademarks of their respective '
            'companies. Eliminator Lighting and all affiliated companies '
            'hereby disclaim any and all liabilities for property, '
            'equipment, building, and electrical damages. Eliminator '
            'Lighting reserves the right to change specifications. 6CH '
            'mode Pan Tilt Dimmer Strobe',
        'ADJ_Elektron_Bar_FX_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Eliminator');
    });
  });

  group('person-name / role-title context rejection', () {
    // Real corpus shape (Laserworld_ScanBar10RGb_UM.txt): a Swiss legal
    // imprint page names the CEO "Martin Werner". A bare `.contains
    // ('martin')` substring check (the pre-identity-pack behavior)
    // hallucinated manufacturer "Martin" here, even though "Martin" the
    // brand appears nowhere in the document - only a person surnamed
    // Martin does.
    const laserworldImprint = '''
=== DMXTRACT PAGE 1 ===
ScanBar 10RGB
=== DMXTRACT PAGE 2 ===
Legal notice:
Thank you for purchasing this Laserworld product. Due to continual product
developments and technical improvements, Laserworld AG reserves the right
to make modifications to its products. Laserworld AG cannot however, take
any responsibility for any errors, omissions or any resulting damages.
=== DMXTRACT PAGE 3 ===
Registered office: 8574 Lengwil-Oberhofen / Switzerland
Commercial Registry Kanton Thurgau
CEO: Martin Werner
6CH mode Pan Tilt Dimmer
''';

    test('does not attribute manufacturer "Martin" to a legal-imprint '
        '"CEO: Martin Werner" line with no other Martin-brand evidence', () {
      final result = fixtureFromManualText(
        laserworldImprint,
        'Laserworld_ScanBar10RGb_UM.pdf',
      );
      expect(result.fixture.manufacturer, isNot('Martin'));
    });

    test('recovers the real manufacturer (Laserworld) via the catalog scan '
        'once the person-name-only "Martin" hit is rejected', () {
      final result = fixtureFromManualText(
        laserworldImprint,
        'Laserworld_ScanBar10RGb_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Laserworld');
    });

    test('an honorific ("Mr") immediately in front of a brand word also '
        'blocks the match', () {
      final result = fixtureFromManualText(
        'This manual was reviewed by Mr Martin Beckmann on behalf of the '
            'distributor. 6CH mode Pan Tilt Dimmer',
        'unbranded_manual.pdf',
      );
      expect(result.fixture.manufacturer, isNot('Martin'));
    });

    // Real corpus shape (Laserworld_ScanBar10RGb_UM.txt,
    // Laserworld_DS1000RGBShowNet_UM.txt): both manuals name the CEO
    // "Martin Werner" under *four* different role titles across their
    // English/German/French legal-imprint pages, including a French
    // "Conseil d'administration:" line whose apostrophe splits into a
    // separate word token ("administration") that the honorific list
    // originally missed - "Martin" survived on those two occurrences
    // alone even with "CEO:" and "Verwaltungsrat:" correctly blocked.
    test('a French "Conseil d\'administration:" role title also blocks the '
        'match, even when the English/German honorifics on the same page '
        'are already handled', () {
      final result = fixtureFromManualText(
        '=== DMXTRACT PAGE 1 ===\n'
            'ScanBar 10RGB\n'
            '=== DMXTRACT PAGE 2 ===\n'
            'Thank you for purchasing this Laserworld product. Laserworld AG '
            'reserves the right to make modifications to its products.\n'
            '=== DMXTRACT PAGE 3 ===\n'
            'CEO: Martin Werner\n'
            'Verwaltungsrat: Martin Werner\n'
            'Conseil d‘administration: Martin Werner\n'
            '6CH mode Pan Tilt Dimmer\n',
        'Laserworld_ScanBar10RGb_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Laserworld');
    });
  });

  group('no-evidence rejection (never hallucinate a brand)', () {
    test('a manual naming no catalog brand anywhere in its body stays '
        '"Unknown manufacturer" even when the filename names one', () {
      // The filename claims ADJ; the body text - the only place identity
      // evidence is allowed to come from - never mentions it. This is the
      // shape of defect the pack's brief calls out by name (a filename-only
      // "ADJ" attribution with the string appearing nowhere in the
      // document): the fix is a structural one (the filename is never
      // consulted for manufacturer at all), not a per-brand special case.
      final result = fixtureFromManualText(
        'SixPar 200 RGBW Wash Light. 6CH mode Pan Tilt Dimmer Strobe Color',
        'SixPar200_ADJ_repack.pdf',
      );
      expect(result.fixture.manufacturer, 'Unknown manufacturer');
    });
  });

  group('minimum-evidence gate (a frequent incidental word must not '
      'outrank an honest "Unknown manufacturer")', () {
    test('a manual that never names its own maker stays "Unknown '
        'manufacturer" even though an unrelated catalog word (its own '
        'product line name) repeats throughout the text', () {
      // Real corpus shape (Equinox_HelixXPFlower_UM.txt): "Equinox" the
      // actual manufacturer never appears in the manual's body text at
      // all, but "Helix" - the product line's own name, and also a
      // standalone manufacturer row in the source database - repeats
      // constantly because it's the product being described, not a
      // separate brand mention.
      final result = fixtureFromManualText(
        'Gobo Flower fixture with Helix XP optics. The Helix pattern '
            'creates unique effects. Helix rotation speed is adjustable. '
            'This Helix-based design improves on earlier Helix models. '
            '6CH mode Pan Tilt Dimmer Strobe',
        'Equinox_HelixXPFlower_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Unknown manufacturer');
    });

    // Real corpus shape (Elation_PlatinumSpot15RPro_UM.txt): a menu-table
    // OCR line break splits "Adjust" into a standalone "Adj" token
    // ("Adj Calibrate Values" / "ust ..."), the manual's only occurrence
    // of the word "Adj" anywhere - it never mentions Elation at all. A
    // single "ADJ" hit is not enough evidence to prefer over an honest
    // "Unknown manufacturer".
    test('a single OCR-split "Adj" (from "Adjust") does not attribute '
        'manufacturer "ADJ" when the document never otherwise mentions it', () {
      final result = fixtureFromManualText(
        'Platinum Spot 15R Pro. Effect Manual Control PAN =XXX Fine '
            'adjustment of the lamp: Adj Calibrate Values Calibrate '
            'Password "050" ust Color wheel=XXX Calibrate and adjust the '
            'effects. 6CH mode Pan Tilt Dimmer Strobe',
        'Elation_PlatinumSpot15RPro_UM.pdf',
      );
      expect(result.fixture.manufacturer, isNot('ADJ'));
    });

    // Real corpus shape (Equinox_Fusion200ZoomSpot_UM.txt): "Equinox" is
    // named only twice, but both times directly beside the fixture's own
    // model name ("The Equinox Fusion 200 Zoom Spot can be operated...",
    // "...the display will show \"Equinox Fusion 200 Zoom Spot\"") - real,
    // load-bearing evidence a flat >=6-occurrence bar was discarding.
    test('a brand mentioned only twice, both directly beside the detected '
        'model name, still clears the minimum-evidence gate', () {
      final result = fixtureFromManualText(
        // Matches the real corpus file's actual shape: the cover title is
        // "Fusion 200 Zoom Spot" alone (no "Equinox" prefix - the brand
        // only shows up in the body), so the detected model hint is
        // exactly "Fusion 200 Zoom Spot", and "Equinox" sits directly
        // beside it wherever it's mentioned.
        '=== DMXTRACT PAGE 1 ===\n'
            'Fusion 200 Zoom Spot\n'
            '        User Manual\n'
            '=== DMXTRACT PAGE 2 ===\n'
            'The Equinox Fusion 200 Zoom Spot can be operated in several '
            'DMX modes. On power-up, the display will show "Equinox Fusion '
            '200 Zoom Spot" briefly. 6CH mode Pan Tilt Dimmer Strobe Color',
        'Equinox_Fusion200ZoomSpot_UM.pdf',
      );
      expect(result.fixture.model, 'Fusion 200 Zoom Spot');
      expect(result.fixture.manufacturer, 'Equinox');
    });
  });

  group('confidence tiers', () {
    test('a known high-precision brand with an in-document model title '
        'scores high confidence', () {
      final result = fixtureFromManualText(
        // Two "ADJ" mentions, not one - real ADJ-branded manuals in the
        // GDTF benchmark corpus (scripts/eval) print the brand a dozen-
        // plus times minimum; a single occurrence is exactly the shape
        // of a false positive (see the minimum-evidence-gate group
        // below and the extractor's own comment on why "ADJ" specifically
        // requires >=2 real mentions).
        'ADJ VIZI XTREME DMX TRAITS 28Ch 40Ch CHANNEL DMX VALUES FUNCTION '
            'Pan Tilt Dimmer Color Wheel. ADJ reserves the right to change '
            'specifications without notice.',
        'ADJ_VIZI_XTREME_DMX_TRAITS.pdf',
      );
      expect(result.fixture.manufacturer, 'ADJ');
      expect(result.fixture.identityConfidence, greaterThanOrEqualTo(.8));
    });

    test('a model that is only a filename echo scores low confidence, even '
        'when the manufacturer is confidently known', () {
      final result = fixtureFromManualText(
        'Altman PHX LVD LED employs dimming technology. Phase Cut or Triac '
            'Dimmer. True mains dim luminaire.',
        'PHX_LVD_USER_MANUAL.pdf',
      );
      expect(result.fixture.model.toLowerCase(), contains('phx'));
      expect(result.fixture.identityConfidence, lessThan(.5));
    });

    test('no manufacturer and no model evidence at all scores the lowest '
        'confidence tier', () {
      final result = fixtureFromManualText(
        '6CH mode Pan Tilt Dimmer Strobe Color',
        '9e48fa0ab3c982dff2a2841efb795bbeb4e99334.pdf',
      );
      expect(result.fixture.manufacturer, 'Unknown manufacturer');
      expect(result.fixture.model, 'Unknown fixture');
      expect(result.fixture.identityConfidence, lessThan(.35));
    });

    test('low identity confidence surfaces a help question even when '
        'neither field literally starts with "Unknown"', () {
      final result = fixtureFromManualText(
        'Altman PHX LVD LED employs dimming technology. Phase Cut or Triac '
            'Dimmer. True mains dim luminaire.',
        'PHX_LVD_USER_MANUAL.pdf',
      );
      expect(result.fixture.manufacturer.startsWith('Unknown'), isFalse);
      expect(result.fixture.model.startsWith('Unknown'), isFalse);
      expect(
        result.questions,
        contains(contains('not fully confident about the maker or model')),
      );
    });
  });

  group('title/model self-collision guard', () {
    test('a brand named in the title stays a candidate when it also '
        'repeats independently throughout the body, instead of being '
        'excluded outright as if it were only the model name repeating', () {
      final result = fixtureFromManualText(
        '=== DMXTRACT PAGE 1 ===\n'
            'ROBE Robin Spikie / User Manual\n'
            '=== DMXTRACT PAGE 2 ===\n'
            'Thank you for purchasing this Robe product. The Robe Robin '
            'Spikie is a compact moving head. Robe products are designed '
            'and manufactured in the Czech Republic. Robe recommends '
            'regular maintenance. Contact your Robe dealer for service. '
            '6CH mode Pan Tilt Dimmer Strobe Color',
        'Robe_RobinSpikie_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Robe');
    });

    test('an unrelated brand whose letters merely line up inside the title '
        "word (normalized \"probeam\" containing \"robe\") is not excluded "
        'as a false self-collision', () {
      final result = fixtureFromManualText(
        '=== DMXTRACT PAGE 1 ===\n'
            'ProBeam 300 User Manual\n'
            '=== DMXTRACT PAGE 2 ===\n'
            'Thank you for purchasing this Robe product. Robe recommends '
            'regular maintenance. Contact your Robe dealer for service. '
            'Robe products are covered by warranty. 6CH mode Pan Tilt '
            'Dimmer Strobe Color',
        'ProBeam300_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Robe');
    });
  });

  group('occurrence dedup across case-variant aliases', () {
    test("a brand's real mention count is not inflated by how many case "
        'variants the catalog happens to carry for it - a brand genuinely '
        'named more often must still outrank one named less often', () {
      // "Showtec" has 3 case-variant spellings in the catalog and
      // "Rainbow" has 1; before the dedup fix, 6 real "Showtec" mentions
      // scored 18 (3x inflated) while "Rainbow" scored its true 8, so
      // the inflation alone decided the winner rather than the real
      // counts. With real counts compared, "Rainbow" (a colour-effect
      // word, not a brand, with no self-identification) must lose on the
      // minimum-evidence gate while "Showtec" - genuinely mentioned 6
      // times - still passes.
      final result = fixtureFromManualText(
        'Phantom Zoom Bar. Showtec products are built to last. Showtec '
            'recommends regular maintenance. Contact your Showtec dealer. '
            'This Showtec fixture supports DMX. Showtec warranty terms '
            'apply. Showtec reserves the right to change specifications. '
            'Rainbow effect: cycles through the colour Rainbow. Rainbow '
            'speed adjustable. Rainbow mode 2. Rainbow selection via DMX. '
            'Rainbow chase pattern. Rainbow fade time. Rainbow reverse. '
            'Rainbow macro. 6CH mode Pan Tilt Dimmer',
        'Showtec_PhantomZoomBar_UM.pdf',
      );
      expect(result.fixture.manufacturer, 'Showtec');
    });
  });

  group('strong-signal-only catalog entries', () {
    test('a common-English-word brand name (ETC) is not attributed from '
        'occurrence count alone, even when it appears many times', () {
      final result = fixtureFromManualText(
        'Weight, size, power draw, etc. are listed in the appendix. See '
            'the specification table, etc. Additional accessories, etc. '
            'are sold separately. Refer to the addendum, etc. for details. '
            '6CH mode Pan Tilt Dimmer Strobe Color, etc.',
        'unbranded_manual.pdf',
      );
      expect(result.fixture.manufacturer, 'Unknown manufacturer');
    });

    test('the same strong-signal brand (ETC) is attributed once it '
        'self-identifies explicitly', () {
      final result = fixtureFromManualText(
        'Thank you for purchasing this ETC product. Weight, size, etc. '
            'are listed in the appendix. 6CH mode Pan Tilt Dimmer Strobe',
        'unbranded_manual.pdf',
      );
      expect(result.fixture.manufacturer, 'ETC');
    });
  });

  group('brand catalog generator determinism', () {
    test('regenerating from the same database twice produces byte-identical '
        'output', () {
      final tmp = Directory.systemTemp.createTempSync('brand_catalog_det_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final dbPath = '${tmp.path}/sample.db';
      // A small, fixed sample standing in for unified.db's shape: case
      // variants to collapse (Laserworld/LaserWorld/laserworld), a
      // denylist hit (Test), a too-short row (Q), and one plain brand.
      final createSql = '''
CREATE TABLE fixture (fixture_id INTEGER PRIMARY KEY, manufacturer TEXT);
INSERT INTO fixture (manufacturer) VALUES
  ('Laserworld'), ('Laserworld'), ('LaserWorld'), ('laserworld'),
  ('ADJ'), ('ADJ'), ('ADJ'),
  ('Chauvet DJ'),
  ('Test'), ('Q');
''';
      final create = Process.runSync('sqlite3', [dbPath, createSql]);
      expect(
        create.exitCode,
        0,
        reason:
            'sqlite3 CLI must be available to build the sample db: '
            '${create.stderr}',
      );

      final scriptPath = '../../scripts/update_brand_catalog.py';
      final out1 = '${tmp.path}/run1.g.dart';
      final out2 = '${tmp.path}/run2.g.dart';
      final run1 = Process.runSync('python3', [scriptPath, dbPath, out1]);
      final run2 = Process.runSync('python3', [scriptPath, dbPath, out2]);
      expect(run1.exitCode, 0, reason: run1.stderr.toString());
      expect(run2.exitCode, 0, reason: run2.stderr.toString());

      final text1 = File(out1).readAsStringSync();
      final text2 = File(out2).readAsStringSync();
      expect(text1, text2);

      // And it actually did the curation work: case variants collapsed to
      // one entry, the denylist/short-row entries dropped.
      expect('Laserworld'.allMatches(text1).length, greaterThan(0));
      expect(text1.contains("canonical: 'LaserWorld'"), isFalse);
      expect(text1.contains("canonical: 'laserworld'"), isFalse);
      expect(text1.contains("'Test'"), isFalse);
      expect(text1.contains("canonical: 'Q'"), isFalse);
    });
  });
}
