@TestOn('vm')
library;

import 'dart:io';
import 'package:dmxtract_web/src/extraction_rules.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds multiple fixture modes in common manual layouts', () {
    final adj = fixtureFromManualText(
      // Two "ADJ" mentions: real ADJ-branded manuals print the brand a
      // dozen-plus times minimum (see the identity pack's minimum-evidence
      // gate in extraction_rules.dart, and apps/web/test/
      // identity_matching_test.dart), so a single occurrence alone is not
      // trusted.
      'ADJ VIZI XTREME DMX TRAITS 28Ch 40Ch 73Ch 54Ch 63Ch CHANNEL DMX VALUES FUNCTION Pan Tilt Dimmer Color Wheel Gobo Wheel. ADJ reserves the right to change specifications without notice.',
      'ADJ_VIZI_XTREME_DMX_TRAITS.pdf',
    );
    expect(adj.fixture.manufacturer, 'ADJ');
    expect(
      adj.fixture.modes.map((mode) => mode.channelIds.length),
      containsAll([28, 40, 73, 54, 63]),
    );
    final chauvet = fixtureFromManualText(
      'CHAUVET DJ FXpar 6 Personality 3CH 6CH 11CH DMX Charts Function Value Dimmer Strobe',
      'FXpar_6_UM_Rev1.pdf',
    );
    expect(chauvet.fixture.manufacturer, 'Chauvet DJ');
    expect(
      chauvet.fixture.modes.map((mode) => mode.channelIds.length),
      containsAll([3, 6, 11]),
    );
  });

  test('recognizes high-channel matrix personalities', () {
    final result = fixtureFromManualText(
      'SHEHDS DMX Channel 6CH / 19CH / 302CH Pan Tilt Dimmer Strobe Color wheel',
      'shehds@200w846strobe.pdf',
    );
    expect(result.fixture.manufacturer, 'SHEHDS');
    expect(
      result.fixture.modes.map((mode) => mode.channelIds.length),
      contains(302),
    );
    expect(result.fixture.channels.length, 302);
  });

  test('builds ordinary RGBW channels without cloud inference', () {
    final result = fixtureFromManualText('''CHAUVET DJ COLORband RGBW 4CH
DMX Chart
1 Red 000-255
2 Green 000-255
3 Blue 000-255
4 White 000-255''', 'COLORband_RGBW_UM.pdf');
    expect(result.fixture.channels.map((item) => item.name), [
      'Red',
      'Green',
      'Blue',
      'White',
    ]);
    expect(result.fixture.channels.map((item) => item.color), [
      'RED',
      'GREEN',
      'BLUE',
      'WHITE',
    ]);
    expect(result.fixture.modes.single.channelIds, hasLength(4));
  });

  test('does not invent LB150 wheel slot counts for other movers', () {
    final result = fixtureFromManualText(
      'ADJ HYDRO 12CH DMX Traits Pan Tilt Color Wheel Gobo Wheel',
      'ADJ_Hydro.pdf',
    );
    final color = result.fixture.wheels.firstWhere(
      (wheel) => wheel['kind'] == 'color',
    );
    final gobo = result.fixture.wheels.firstWhere(
      (wheel) => wheel['kind'] == 'gobo',
    );
    expect(color['slots'] as List, hasLength(2));
    expect(gobo['slots'] as List, hasLength(2));
  });

  test('handles Altman personality language and mains-dim negative example', () {
    final spectra = fixtureFromManualText(
      'Altman Spectra Series Personality Settings Personality 1 Uses four DMX channels 8-bit RGBA Personality 3 Uses five DMX Channels Personality 5 Uses eight DMX Channels Personality 7 Uses ten DMX Channels',
      'SPECTRA_MANUAL_REV0_20210204.pdf',
    );
    expect(spectra.fixture.manufacturer, 'Altman');
    expect(
      spectra.fixture.modes.map((mode) => mode.channelIds.length),
      containsAll([4, 5, 8, 10]),
    );
    final phx = fixtureFromManualText(
      'Altman PHX LVD LED employs dimming technology. Phase Cut or Triac Dimmer. True mains dim luminaire.',
      'PHX_LVD_USER_MANUAL.pdf',
    );
    expect(phx.fixture.channels, isEmpty);
    // The model here falls through to a filename echo ("PHX LVD USER
    // MANUAL" has no in-document title match), which now also surfaces a
    // low-confidence prompt alongside the mains-dimmed one - both are
    // legitimate, so this checks membership rather than exact count.
    expect(phx.questions, contains(contains('mains-dimmed')));
  });

  test('canonical project round trips', () {
    final original = fixtureFromManualText(
      'BETOPPER Model: LB150 12CH Pan Pan fine Tilt Tilt fine PAN/TILT speed Dimming Light switch/strobe Color wheel Gobo wheel Prism Reserved Channel Reset/Function Channel',
      'LB150.pdf',
    ).fixture;
    expect(original.toJson()['schemaVersion'], 1);
    expect(original.channels.length, 12);
    expect(original.channels.last.kind, 'maintenance');
  });

  test('uses sequential table rows to correct a noisy mode label', () {
    final result = fixtureFromManualText('''BETOPPER Model: LB150 42CH
Channel value table
1 000-255 Pan
2 000-255 Pan fine
3 000-255 Tilt
4 000-255 Tilt fine
5 000-255 PAN/TILT speed
6 000-255 Dimming
7 Light switch/strobe
8 Color wheel
9 Gobo wheel
10 Prism
11 Reserved Channel
12 Reset/Function Channel''', '406-15012-002D_LB150_BETOPPER_1.pdf');
    expect(result.fixture.model, 'LB150');
    expect(result.fixture.modes.single.channelIds, hasLength(12));
  });

  test('preserves Chauvet-style channel names and value ranges', () {
    final table = StringBuffer('''CHAUVET DJ COLORpalette RGB
Contents: DMX Channel Assignments and Values ........ 10
1 The COLORpalette works with a DMX controller.
DMX Channel Assignments and Values
27-CH 15-CH 9-CH 6-CH 3-CH
000 ⇔ 019 27 channel mode
1 Mode
020 ⇔ 255 DMX personalities 15-CH – 3-CH
2 No Function 000 ⇔ 255 No function
000 ⇔ 002 No function
3 Strobe
003 ⇔ 249 Slow to fast
250 ⇔ 255 Sound-Active
''');
    const colors = ['Red', 'Green', 'Blue'];
    for (var channel = 4; channel <= 27; channel++) {
      final color = colors[(channel - 4) % 3];
      final zone = (channel - 4) ~/ 3 + 1;
      table.writeln('$channel $color $zone 000 ⇔ 255 0–100%');
    }
    final result = fixtureFromManualText(
      table.toString(),
      'COLORpalette_UM_Rev4_WO.pdf',
    );
    expect(
      result.fixture.modes.map((mode) => mode.channelIds.length),
      containsAll([27, 15, 9, 6, 3]),
    );
    expect(result.fixture.channels, hasLength(27));
    expect(result.fixture.channels[0].name, 'Mode');
    expect(result.fixture.channels[0].ranges, hasLength(2));
    expect(result.fixture.channels[1].name, 'No Function');
    expect(result.fixture.channels[2].name, 'Light switch / strobe');
    expect(result.fixture.channels[2].ranges, hasLength(3));
    expect(result.fixture.channels[3].name, 'Red 1');
    expect(result.fixture.channels[4].name, 'Green 1');
    expect(result.fixture.channels[26].name, 'Blue 8');
    expect(result.fixture.channels[26].ranges.single.name, 'Blue 8 intensity');
    expect(result.questions.where((item) => item.contains('channel')), isEmpty);
  });

  test('preserves coded personalities with repeated channel counts', () {
    final manual = StringBuffer('''BETOPPER Model: LM3715R
37x15W RGBW 4-in-1 LEDs
''');
    const personalities = <(String, int)>[
      ('49AC', 49),
      ('CH33', 33),
      ('CH27', 27),
      ('CH22', 22),
      ('49BC', 49),
      ('AC37', 37),
      ('CH30', 30),
      ('BC37', 37),
      ('CH58', 58),
      ('C162', 162),
    ];
    for (final personality in personalities) {
      manual.writeln(
        '=== DMXTRACT PAGE ${personalities.indexOf(personality) + 8} ===',
      );
      manual.writeln('${personality.$1} Channel Table');
      for (var channel = 1; channel <= personality.$2; channel++) {
        final function = personality.$1 == 'CH33'
            ? switch (channel) {
                1 => 'X-axis',
                2 => 'X-axis fine-tuning',
                3 => 'Y-axis',
                4 => 'Y-axis fine-tuning',
                5 => 'XY speed',
                6 => 'Reset (200-209 is the reset value)',
                7 => 'R1',
                8 => 'R1 fine-tuning',
                19 => 'Shutter',
                20 => 'Dimming',
                21 => 'Dimming fine-tuning',
                22 => 'Void',
                _ => 'Control $channel',
              }
            : 'Control $channel';
        if (personality.$1 == 'CH33' && channel == 22) {
          manual.writeln('22 0-9 $function');
          manual.writeln('10-255 Auxiliary light strobe (slow to fast)');
        } else {
          manual.writeln('$channel 000-255 $function');
        }
      }
    }

    final result = fixtureFromManualText(
      manual.toString(),
      'Betopper_LM3715R_User_Manual.pdf',
    );
    final fixture = result.fixture;
    expect(fixture.model, 'LM3715R');
    expect(fixture.modes.map((mode) => mode.name), [
      '49AC',
      'CH33',
      'CH27',
      'CH22',
      '49BC',
      'AC37',
      'CH30',
      'BC37',
      'CH58',
      'C162',
    ]);
    expect(fixture.modes.map((mode) => mode.channelIds.length), [
      49,
      33,
      27,
      22,
      49,
      37,
      30,
      37,
      58,
      162,
    ]);
    expect(fixture.channels, hasLength(504));
    expect(fixture.maxModeChannelCount, 162);
    expect(
      fixture.modes[0].channelIds.toSet().intersection(
        fixture.modes[4].channelIds.toSet(),
      ),
      isEmpty,
    );

    final ch33 = fixture.modes[1];
    final ch33Channels = ch33.channelIds
        .map((id) => fixture.channels.firstWhere((item) => item.id == id))
        .toList();
    expect(ch33Channels.take(8).map((channel) => channel.name), [
      'Pan',
      'Pan fine',
      'Tilt',
      'Tilt fine',
      'Pan / tilt speed',
      'Reset / function',
      'Red 1',
      'Red 1 fine',
    ]);
    expect(ch33Channels[1].fineOf, ch33Channels[0].id);
    expect(ch33Channels[7].fineOf, ch33Channels[6].id);
    expect(ch33Channels[21].name, 'Light switch / strobe');
    expect(ch33Channels[21].ranges, hasLength(2));
    expect(ch33Channels[21].ranges.last.safety, 'strobe');
    expect(result.questions, isNot(contains(contains('channel rows'))));
  });

  test('recovers missing scanned row numbers and repeated color blocks', () {
    const manual = '''BETOPPER Model: Scan Grid
CH8 Channel Table
NO.   Value   Function
1   000-255   LED1 red
2   000-255   LED1 green
5   000-255   LED3 red
6   000-255   LED3 green
7   0-9   Void
10-255   Strobe (slow to fast)
000-255   R1
Color Temperature
NO.   Value   Function
5   112-127   This is an appendix row, not channel five
''';

    final result = fixtureFromManualText(manual, 'scan-grid.pdf');
    final fixture = result.fixture;
    final mode = fixture.modes.single;
    final channels = mode.channelIds
        .map((id) => fixture.channels.firstWhere((item) => item.id == id))
        .toList();

    expect(channels.map((item) => item.name), [
      'LED 1 red',
      'LED 1 green',
      'LED 2 red',
      'LED 2 green',
      'LED 3 red',
      'LED 3 green',
      'Light switch / strobe',
      'Red 1',
    ]);
    expect(channels[4].ranges, hasLength(1));
    expect(channels.where((item) => item.confidence < .5), isEmpty);
  });

  test('reports incomplete coded tables by personality', () {
    final result = fixtureFromManualText('''BETOPPER Model: TEST100
CH12 Channel Table
1 000-255 Pan
2 000-255 Tilt
3 000-255 Dimmer
''', 'test100.pdf');
    expect(result.fixture.modes.single.name, 'CH12');
    expect(result.fixture.modes.single.channelIds, hasLength(12));
    expect(
      result.questions,
      contains(
        'CH12: we read 3 of 12 channel rows. Check the highlighted controls.',
      ),
    );
  });

  test('normalizes common OCR mistakes in personality codes', () {
    final result = fixtureFromManualText('''BETOPPER Model: TEST200
A9AC Channel Table
1 000-255 Pan
I49BC Channel Table
1 000-255 Tilt
C162 Channel Table
1 000-255 Dimmer
162 Channel Table
CHH27 Chine! lable
1 000-255 Pan
4SAC Chait Tabi
1 000-255 Tilt
AC37 Channel Table
1 000-255 Dimmer
AG37 Chaiinel Table
1 000-255 Dimmer
BC37 Channel Table
1 000-255 Strobe
BG37 Chaiinel Table
1 000-255 Strobe
CH58 Channel Table
1 000-255 Focus
C58 Chainel Vable
1 000-255 Focus
''', 'test200.pdf');
    expect(result.fixture.modes.map((mode) => mode.name), [
      '49AC',
      '49BC',
      'C162',
      'CH27',
      'AC37',
      'BC37',
      'CH58',
    ]);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      49,
      49,
      162,
      27,
      37,
      37,
      58,
    ]);
  });

  test('keeps similar exact same-size personality codes distinct', () {
    final result = fixtureFromManualText('''BETOPPER Model: EXACT58
C58 Channel Table
1 000-255 Pan
CH58 Channel Table
1 000-255 Tilt
''', 'exact58.pdf');
    expect(result.fixture.modes.map((mode) => mode.name), ['C58', 'CH58']);
    expect(result.fixture.channels, hasLength(116));
  });

  test('removes scanned table grid artifacts and repairs 255 values', () {
    final result = fixtureFromManualText('''BETOPPER Model: GRID6
CH6 Channel Table
[1 | 000.255 | X-axis
[2 [000-265 | Y-axis
[3 | 000255 | Dimming
''', 'grid6.pdf');
    final mode = result.fixture.modes.single;
    final channels = mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(channels.take(3).map((channel) => channel.name), [
      'Pan',
      'Tilt',
      'Dimmer',
    ]);
    expect(channels.take(3).map((channel) => channel.ranges.single.end), [
      255,
      255,
      255,
    ]);
    // "GRID6" has only one trailing digit, so the in-document model
    // pattern doesn't match it and the model falls through to the
    // filename echo ("grid6.pdf") - that now also surfaces a
    // low-confidence prompt alongside the incomplete-table one.
    expect(result.questions, contains(contains('we read 3 of 6')));
  });

  test('recovers ordered channel functions when narrow OCR columns fail', () {
    final result = fixtureFromManualText('''BETOPPER Model: SCAN6
CH6 Channel Table
.   DI0-2:.   X-axis
2   Ili-2h:   X-axis fine-tuning
a   Iii-2cs   Y-axis
4   lll-@E   Y-axis fine-tuning
§   lll-Z.   XY speed
6   Ili-2   eset (200-209 is the reset value)
''', 'scan6.pdf');
    final mode = result.fixture.modes.single;
    final channels = mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(channels.map((channel) => channel.name), [
      'Pan',
      'Pan fine',
      'Tilt',
      'Tilt fine',
      'Pan / tilt speed',
      'Reset / function',
    ]);
    expect(channels.first.ranges.single.confidence, .45);
    expect(channels.last.ranges.single.safety, 'reset');
    expect(result.questions, isNot(contains(contains('channel rows'))));
  });

  test('preserves contextual Chauvet personalities with duplicate sizes', () {
    final manual = StringBuffer('''CHAUVET PROFESSIONAL
COLORado PXL Curve 12 User Manual Rev. 9
Single Control Mode
Basic (20CH)
''');
    for (var channel = 1; channel <= 20; channel++) {
      manual.writeln('$channel Control $channel 000 ↔ 255 Full range');
    }
    void parallel(List<int> counts, List<String> names) {
      manual.writeln(
        [
          for (var index = 0; index < counts.length; index++)
            '${names[index]} (${counts[index]}CH)',
        ].join(' / '),
      );
      final largest = counts.reduce((a, b) => a > b ? a : b);
      for (var channel = 1; channel <= largest; channel++) {
        manual.writeln(
          '${[for (final count in counts) channel <= count ? '$channel' : '–'].join(' ')} Control $channel 000 ↔ 255 Full range',
        );
      }
    }

    parallel([169, 169], ['Advanced2', 'Full PXL']);
    parallel([53, 101, 155, 179], ['Basic2', 'Standard', 'Advanced', 'Tour']);
    manual.writeln('Dual Control Mode - Movement\nBasic (8CH)');
    for (var channel = 1; channel <= 8; channel++) {
      manual.writeln('$channel Control $channel 000 ↔ 255 Full range');
    }
    parallel([41, 53, 59], ['Basic2', 'Standard', 'Advanced']);
    manual.writeln('Dual Control Mode - Pixels');
    parallel([36, 48, 96], ['Basic', 'Standard', 'Advanced']);

    final result = fixtureFromManualText(
      manual.toString(),
      'COLORado-PXL-Curve-12_UM_Rev9.pdf',
    );
    expect(result.fixture.manufacturer, 'Chauvet Professional');
    expect(result.fixture.model, 'COLORado PXL Curve 12');
    expect(result.fixture.modes.map((mode) => mode.name), [
      'Single · Basic',
      'Single · Advanced2',
      'Single · Full PXL',
      'Single · Basic2',
      'Single · Standard',
      'Single · Advanced',
      'Single · Tour',
      'Movement · Basic',
      'Movement · Basic2',
      'Movement · Standard',
      'Movement · Advanced',
      'Pixels · Basic',
      'Pixels · Standard',
      'Pixels · Advanced',
    ]);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      20,
      169,
      169,
      53,
      101,
      155,
      179,
      8,
      41,
      53,
      59,
      36,
      48,
      96,
    ]);
    expect(
      result.fixture.modes[1].channelIds.toSet().intersection(
        result.fixture.modes[2].channelIds.toSet(),
      ),
      isEmpty,
    );
    expect(
      result.questions.where((item) => item.contains('channel rows')),
      isEmpty,
    );
  });

  test('maps stacked parallel headers back to the named personality', () {
    const manual = '''CHAUVET PROFESSIONAL
COLORado Header Test User Manual Rev. 1
Single Control Mode
Advanced2 (6CH) / Full PXL (6CH)
  Full Advanced
  PXL      2    Function
  1       –    Tilt 1       000 ↔ 255 Full range
  2       –    Fine tilt 1  000 ↔ 255 Full range
  3       –    Red 1        000 ↔ 255 Full range
  4       –    Fine red 1   000 ↔ 255 Full range
  5       –    Green 1      000 ↔ 255 Full range
  6       –    Fine green   000 ↔ 255 Full range
  –       1    Control      000 ↔ 255 Full range
  –       2    Red          000 ↔ 255 Full range
  –       3    Fine red     000 ↔ 255 Full range
  –       4    Green        000 ↔ 255 Full range
  –       5    Fine green   000 ↔ 255 Full range
  –       6    Blue         000 ↔ 255 Full range
Dual Control Mode - Movement
''';

    final result = fixtureFromManualText(manual, 'stacked-header.pdf');
    final advanced = result.fixture.modes.first;
    final fullPxl = result.fixture.modes.last;
    List<DmxChannel> channels(FixtureMode mode) => mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();

    expect(advanced.name, 'Single · Advanced2');
    expect(channels(advanced).first.name, 'Control');
    expect(fullPxl.name, 'Single · Full PXL');
    expect(channels(fullPxl).first.name, 'Tilt 1');
    expect(channels(fullPxl).last.name, 'Green 1 fine');
    expect(channels(fullPxl).last.fineOf, channels(fullPxl)[4].id);
  });

  test('attaches coded appendix value tables to their controls', () {
    const manual = '''BETOPPER Model: APPENDIX5
CH5 Channel Table
1 000-255 Color_Temperature
2 000-255 Mode_tableI
3 000-255 Mode table 2
4 000-255 Shutter
5 000-255 Background color
Color Temperature
1 0-9 Void
2 10-13 Color temperature 1
61 246-249 Color temperature 60
63 254-255 Color temperature 62
Mode table I
10 17-55 Mode 9
12 57-95 Mode 11
16 136-174 Mode 15
18 176-214 Mode 17
Shutter
1 0-31 Strobe off
2 32-63 Strobe 1
3 64-95 Strobe 2
4 96-111 Strobe 3
5 112-127 Strobe 4
6 128-143 Strobe 5
7 144-159 Strobe 6
8 160-175 Strobe 7
9 176-191 Strobe 8
10 192-223 Strobe 9
11 224-255 Strobe on
Mode table 2
2 4-10 Mode 1
35 235-241 Mode 34
37 249-255 Mode 36
Background color
1 0-7 Color 0
62 248-251 Color 61
63 252-255 Color 62
''';

    final result = fixtureFromManualText(manual, 'appendix.pdf');
    expect(result.fixture.channels.map((item) => item.name), [
      'Color temperature',
      'Mode table 1',
      'Mode table 2',
      'Shutter / strobe',
      'Background color',
    ]);
    expect(result.fixture.channels.map((item) => item.ranges.length), [
      63,
      29,
      37,
      11,
      63,
    ]);
    expect(result.fixture.channels[3].ranges[1].safety, 'strobe');
  });

  test('expands inherited Martin pixel modes through multiple universes', () {
    final manual = StringBuffer(
      '''Martin MAC Aura Raven XIP User Manual Revision C
Compact DMX Mode
22 DMX channels
1 Shutter/strobe
2 Dimmer
3 0–65535 Closed to open
4 Red
5 0–65535 Intensity
6 Green
7 0–65535 Intensity
8 Blue
9 0–65535 Intensity
10 CTC
11 Green/Magenta shift (tint)
12 Virtual color wheel
13 Zoom
14 0–65535 Narrow to wide
15 Beamshaper
16 0–65535 Index
17 Pan
18 0–65535 Left to right
19 Tilt
20 0–65535 Forward to backward
21 Fixture Control/Settings
22 LED PWM frequency
Basic DMX Mode
38 DMX channels
Channels 1 – 22 as in Compact Mode
''',
    );
    for (var channel = 23; channel <= 38; channel++) {
      manual.writeln('$channel Effect $channel');
    }
    manual.write('''Extended DMX Mode
149 DMX channels
Channels 1 – 38 as in Basic Mode
37 x RGB channels = 111 channels for individual RGB Beam pixel control
Ludicrous DMX Mode
266 DMX channels
Channels 1 – 149 as in Extended Mode
117 channels for Aura control in segments
Plaid DMX Mode
851 DMX channels
Channels 1 – 149 as in Extended Mode
702 channels for individual RGB control of all 234 Aura pixels
Compact Direct DMX Mode
22 DMX channels
''');
    for (var channel = 1; channel <= 22; channel++) {
      manual.writeln('$channel Direct control $channel');
    }
    manual.writeln('Virtual color wheel*');
    manual.writeln('0–10 Open');
    for (var preset = 1; preset <= 48; preset++) {
      final start = 9 + preset * 2;
      manual.writeln('$start–${start + 1} Preset $preset');
    }
    manual.writeln('107–190 No function');
    manual.writeln('13 Zoom');

    final result = fixtureFromManualText(
      manual.toString(),
      'UM-SFTY_MACAuraRavenXIP_EN_C.pdf',
    );
    expect(result.fixture.manufacturer, 'Martin');
    expect(result.fixture.model, 'MAC Aura Raven XIP');
    expect(result.fixture.modes.map((mode) => mode.name), [
      'Compact',
      'Basic',
      'Extended',
      'Ludicrous',
      'Plaid',
      'Compact Direct',
    ]);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      22,
      38,
      149,
      266,
      851,
      22,
    ]);
    expect(result.fixture.modes[4].breaks, 2);
    final plaid = result.fixture.modes[4].channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(plaid[149].name, 'Aura pixel 1 Red');
    expect(plaid[850].name, 'Aura pixel 234 Blue');
    expect(plaid.where((channel) => channel.confidence < .5), isEmpty);
    expect(result.fixture.wheels.single['slots'], hasLength(49));
    final wheelChannel = result.fixture.channels.firstWhere(
      (channel) => channel.kind == 'colorWheel',
    );
    expect(wheelChannel.ranges, hasLength(50));
    expect(
      result.questions.where((question) => question.contains('color wheel')),
      isEmpty,
    );
  });

  test('parses a Chauvet mode-matrix table across a page break', () {
    // A trimmed but real excerpt of the Chauvet DJ Rotosphere HP manual's
    // "DMX Channel Assignments and Values" table, matching what this file's
    // own vendored PDF.js pipeline (apps/web/web/vendor/pdfjs/pdf.min.mjs,
    // via manual_extractor.js's positionedText()) actually produces for
    // testcorpus/Rotosphere_HP_UM_Rev1.pdf: a header naming three modes by
    // their channel count (3Ch/12Ch/28Ch), a dash meaning a function does
    // not exist in that mode, a channel whose function is a conditional
    // alternative printed on its own lines ("Program speed" / "Sound
    // sensitivity", chosen by channel 1's value) with the row's own number
    // line sandwiched between them, the table continuing on a second page
    // behind footer/header furniture and a repeated header row, and — after
    // the table's real last row — a page footer and the start of the next
    // section, to confirm neither leaks into the table as bogus ranges.
    //
    // U+F0F3 (`sep` below) is the private-use codepoint PDF.js's text layer
    // resolves this PDF's value-range separator glyph to. `pdftotext`
    // (poppler) leaves the same glyph unresolved as a *different* private-use
    // codepoint instead, so a `pdftotext -layout` dump and the in-app PDF.js
    // pipeline can disagree about which character sits between a range's
    // start and end for the very same PDF — using 'ó' here (as earlier
    // versions of this test did) tests neither of those and silently passes
    // even when the real separator isn't recognized.
    const sep = '';
    final manual = StringBuffer('''CHAUVET DJ
Rotosphere HP User Manual Rev. 1
The Rotosphere HP works with a DMX controller. Information about DMX is in
the CHAUVET DMX Primer, available from chauvetlighting.com/downloads.
DMX Channel Assignments and Values
 3Ch 12Ch 28Ch Function                           Value   Percent/Setting
                                                   000    No function
  1     1     –   Program                       001 $sep 250 Automatic program
                                                251 $sep 255 Sound-active program
                  Program speed
                                                000 $sep 255 Automatic program speed, slow to fast
                  (when Ch. 1 is 001 250)
  2     2     –
                  Sound sensitivity
                                                000 $sep 255 Sound sensitivity, low to high
                  (when Ch. 1 is 251 255)
''');
    const colors = [
      'Red',
      'Green',
      'Blue',
      'White',
      'Cyan',
      'Magenta',
      'Yellow',
      'Orange',
    ];
    var channel28 = 1;
    for (var zone = 1; zone <= 3; zone++) {
      for (var index = 0; index < colors.length; index++) {
        final ch12 = zone == 1 ? '${index + 3}' : '–';
        manual.writeln(
          '  –    $ch12    $channel28   ${colors[index]} $zone'
          '                       000 $sep 255 0–100%',
        );
        channel28++;
      }
    }
    manual.write(
      '''                                                000 $sep 005 No function
  –    11    25   Strobe
                                                006 $sep 255 Strobe, slow to fast


Rotosphere HP User Manual Rev. 1                                          7
=== DMXTRACT PAGE 8 ===
Operation
 3Ch 12Ch 28Ch Function                                Value   Percent/Setting
                                                        000    No function
    –    –     26   Program                          001 $sep 250 Automatic program
                                                     251 $sep 255 Sound-active program
                    Program speed
                                                     000 $sep 255 Automatic program speed, slow to fast
                    (when Ch. 26 is 001 250)
    –    –     27
                    Sound sensitivity
                                                     000 $sep 255 Sound sensitivity, low to high
                    (when Ch. 26 is 251 255)
                                                     000 $sep 127 Motor indexing
                                                     128 $sep 189 Motor rotation, fast to slow
    3   12     28   Motor rotation
                                                     190 $sep 193 Stop
                                                     194 $sep 255 Reverse motor rotation, slow to fast
Configuration (Standalone)
Set the product in one of the standalone modes to control without a DMX
controller.
8   Rotosphere HP User Manual Rev. 1
=== DMXTRACT PAGE 11 ===
Automatic Programs
To run the Rotosphere HP with an automatic program, follow the instructions
below.
''',
    );

    final result = fixtureFromManualText(
      manual.toString(),
      'CHV-Rotosphere-HP_UM_Rev1.pdf',
    );
    expect(result.fixture.manufacturer, 'Chauvet DJ');
    expect(result.fixture.model, 'Rotosphere HP');

    List<DmxChannel> channelsOf(FixtureMode mode) => mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();

    expect(result.fixture.modes.map((mode) => mode.name), [
      '3Ch',
      '12Ch',
      '28Ch',
    ]);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      3,
      12,
      28,
    ]);

    final threeCh = channelsOf(result.fixture.modes[0]);
    expect(threeCh[0].name, 'Program');
    expect(
      threeCh[0].ranges.map((range) => (range.start, range.end, range.name)),
      [
        (0, 0, 'No function'),
        (1, 250, 'Automatic program'),
        (251, 255, 'Sound-active program'),
      ],
    );
    expect(threeCh[1].name, 'Program speed / Sound sensitivity');
    expect(threeCh[2].name, 'Motor rotation');
    // The table's real last row (28Ch's 28th channel, shared by all three
    // modes) has exactly these four ranges — not a fifth one named after
    // the page footer or the "Configuration (Standalone)" section that
    // follows it in the source text.
    expect(
      threeCh[2].ranges.map((range) => (range.start, range.end, range.name)),
      [
        (0, 127, 'Motor indexing'),
        (128, 189, 'Motor rotation, fast to slow'),
        (190, 193, 'Stop'),
        (194, 255, 'Reverse motor rotation, slow to fast'),
      ],
    );

    final twelveCh = channelsOf(result.fixture.modes[1]);
    expect(twelveCh[2].name, 'Red 1');
    // The reported bug: only channels 1-3 were ever extracted. Channels
    // beyond that must exist and carry their real names, not placeholders.
    expect(twelveCh[3].name, 'Green 1');
    // A bare-percentage range description ("0-100%") is normalized to a
    // neutral "Full range" name rather than kept literally — see
    // `_matrixRange`.
    expect(
      twelveCh[2].ranges.map((range) => (range.start, range.end, range.name)),
      [(0, 255, 'Full range')],
    );
    expect(twelveCh.last.name, 'Motor rotation');
    expect(
      twelveCh.map((channel) => channel.name.startsWith('Channel ')),
      everyElement(isFalse),
    );
    final strobe = twelveCh.firstWhere(
      (channel) => channel.name.contains('strobe'),
    );
    expect(
      strobe.ranges.map((range) => (range.start, range.end, range.safety)),
      [(0, 5, 'normal'), (6, 255, 'strobe')],
    );

    final twentyEightCh = channelsOf(result.fixture.modes[2]);
    expect(twentyEightCh[8].name, 'Red 2');
    expect(
      twentyEightCh.map((channel) => channel.name.startsWith('Channel ')),
      everyElement(isFalse),
    );

    expect(
      result.questions.where((item) => item.contains('channel rows')),
      isEmpty,
    );
  });

  test(
    'rejoins a matrix row whose position token was split onto its own line',
    () {
      // Chauvet DJ Sentinel Wash Q7Z ILS, "DMX Charts" table (9CH/14CH): the
      // real extraction shape (running the vendored pdf.min.mjs over
      // testcorpus/Sentinel_Wash_Q7Z_ILS_UM_Rev2-1.pdf) has channel 14's
      // row split across two physical lines — a lone "–" (this function
      // doesn't exist in the 9CH mode) on one line, then
      // "14 Movement macros ..." on the next — because positionedText()'s
      // y-tolerance row grouping puts that cell at a slightly different
      // vertical center than the rest of the row. Without rejoining the two
      // lines, this channel came out as a placeholder "Channel 14" with a
      // synthetic 0-255 range, its real ranges got misattributed to
      // channel 13, and a "we read 13 of 14 channel rows" question fired.
      // The full 9CH/14CH table, real content, so every declared channel
      // is actually present and the parser's own "we read N of M channel
      // rows" completeness check can't mask the split-row bug behind an
      // unrelated incompleteness question.
      const sep = '';
      final manual =
          '''CHAUVET DJ
Sentinel Wash Q7Z ILS User Manual Rev. 2
The Sentinel Wash Q7Z ILS works with a DMX controller.
DMX Channel Assignments and Values
DMX Charts
9CH 14CH Function   Value Percent/Setting
1   1 Pan   000 $sep 255 0–540°
-   2 Pan Fine   000 $sep 255 Fine control of panning
2   3 Tilt   000 $sep 255 0–225°
-   4 Tilt Fine   000 $sep 255 Fine control of tilting
-   5 Pan/Tilt speed   000 $sep 255 Pan/tilt speed (fast to slow)
3   6 Dimmer   000 $sep 255 0-100%
4   7 Red   000 $sep 255 0-100%
5   8 Green   000 $sep 255 0-100%
6   9 Blue   000 $sep 255 0-100%
7   10 White   000 $sep 255 0-100%
000 $sep 005 No function
8   11 Strobe
006 $sep 255 Strobe (slow to fast)
9   12 Zoom   000 $sep 255 Wide to narrow
000 $sep 007 No function
008 $sep 015 Black out on pan/tilt movement
016 $sep 095 No function
096 $sep 103 Pan reset
-   13 Function   104 $sep 111 Tilt reset
112 $sep 143 No function
144 $sep 151 Zoom reset
152 $sep 159 All reset
160 $sep 255 No function
000 $sep 007 No function
008 $sep 023 Movement macro 1
024 $sep 039 Movement macro 2
040 $sep 055 Movement macro 3
056 $sep 071 Movement macro 4
072 $sep 087 Movement macro 5
088 $sep 103 Movement macro 6
104 $sep 119 Movement macro 7
-
14 Movement macros   120 $sep 135 Movement macro 8
136 $sep 151 Sound-active movement macro 1
152 $sep 167 Sound-active movement macro 2
168 $sep 183 Sound-active movement macro 3
184 $sep 199 Sound-active movement macro 4
200 $sep 215 Sound-active movement macro 5
216 $sep 231 Sound-active movement macro 6
232 $sep 247 Sound-active movement macro 7
248 $sep 255 Sound-active movement macro 8
''';
      final result = fixtureFromManualText(
        manual,
        'Sentinel_Wash_Q7Z_ILS_UM_Rev2-1.pdf',
      );
      final fourteenCh = result.fixture.modes.firstWhere(
        (mode) => mode.name == '14Ch',
      );
      expect(fourteenCh.channelIds.length, 14);
      final channel14 = result.fixture.channels.firstWhere(
        (channel) => channel.id == fourteenCh.channelIds[13],
      );
      // The reported bug: without rejoining, this channel came out as a
      // placeholder "Channel 14" with a synthetic 0-255 range, and its real
      // name/ranges were misattributed to channel 13 ("Function").
      expect(channel14.name, isNot(startsWith('Channel ')));
      expect(channel14.name, contains('Movement macros'));
      expect(channel14.ranges.map((range) => (range.start, range.end)), [
        (0, 7),
        (8, 23),
        (24, 39),
        (40, 55),
        (56, 71),
        (72, 87),
        (88, 103),
        (104, 119),
        (120, 135),
        (136, 151),
        (152, 167),
        (168, 183),
        (184, 199),
        (200, 215),
        (216, 231),
        (232, 247),
        (248, 255),
      ]);
      final channel13 = result.fixture.channels.firstWhere(
        (channel) => channel.id == fourteenCh.channelIds[12],
      );
      expect(channel13.name, 'Function');
      expect(channel13.ranges.length, 9);
      expect(
        result.questions.where((item) => item.contains('channel rows')),
        isEmpty,
      );
    },
  );

  test('does not mistake a value line for a channel row when the separator '
      'is a plain dash', () {
    // `_rangeSeparatorClass` treats dash variants as legitimate
    // value-range separators (some Chauvet manuals do print a plain
    // dash there instead of the symbol-font glyph), but the mode-matrix
    // row grammar's position-token class also treats a bare dash as
    // "this channel doesn't exist in this mode". A value line like
    // "001 - 250 Automatic program" therefore tokenizes exactly like a
    // real channel row would for a 3Ch/12Ch/28Ch header ([1, null, 250]),
    // and 250 as a channel position doesn't exceed Dart's int range or
    // any obviously-wrong bound — only checking it against each mode's
    // *declared* channel count catches it.
    final manual = '''CHAUVET DJ
Rotosphere HP User Manual Rev. 1
DMX Channel Assignments and Values
 3Ch 12Ch 28Ch Function                           Value   Percent/Setting
                                                   000    No function
  1     1     –   Program                       001 - 250 Automatic program
                                                251 - 255 Sound-active program
''';
    final result = fixtureFromManualText(manual, 'Rotosphere_HP_UM_Rev1.pdf');
    final threeCh = result.fixture.modes.firstWhere(
      (mode) => mode.name == '3Ch',
    );
    final program = result.fixture.channels.firstWhere(
      (channel) => channel.id == threeCh.channelIds.first,
    );
    expect(program.name, 'Program');
    expect(
      program.ranges.map((range) => (range.start, range.end, range.name)),
      [
        (0, 0, 'No function'),
        (1, 250, 'Automatic program'),
        (251, 255, 'Sound-active program'),
      ],
    );
  });

  test('local PDF corpus or public golden corpus remains discoverable', () {
    final corpus = Directory('../../testcorpus');
    expect(corpus.existsSync(), isTrue);
    final names = corpus
        .listSync()
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.pdf'))
        .map((file) => file.path)
        .toList();

    // Manufacturer manuals are useful local regression inputs, but they are
    // intentionally gitignored because their copyrights do not belong to us.
    // A clean public clone still has to prove that its redistributable corpus
    // documentation and synthetic fixture survived packaging.
    if (names.isEmpty) {
      expect(File('../../testcorpus/README.md').existsSync(), isTrue);
      expect(File('../../golden/manuals/simple-rgbw.txt').existsSync(), isTrue);
      expect(
        File('../../golden/simple-rgbw.dmxtract.json').existsSync(),
        isTrue,
      );
      return;
    }

    expect(names.length, greaterThanOrEqualTo(8));
    expect(names.any((name) => name.toLowerCase().contains('adj')), isTrue);
    expect(names.any((name) => name.toLowerCase().contains('shehds')), isTrue);
    expect(names.any((name) => name.contains('FXpar')), isTrue);
  });

  test('parses sequential "<N>-channel mode" tables with multi-range channels '
      'and an ellipsis-expanded RGBW zone run', () {
    final result = fixtureFromManualText(
      _sequentialModeManual(noisy: false),
      'noname_moving_effect_light.pdf',
    );
    final fixture = result.fixture;
    expect(fixture.modes.map((mode) => mode.channelIds.length).toList(), [
      30,
      42,
      58,
    ]);

    DmxChannel channelAt(String modeName, int position) {
      final mode = fixture.modes.firstWhere((m) => m.name == modeName);
      final id = mode.channelIds[position - 1];
      return fixture.channels.firstWhere((c) => c.id == id);
    }

    final rotation = channelAt('30-channel mode', 7);
    expect(rotation.name, 'Rotation');
    expect(rotation.ranges.map((r) => (r.start, r.end)), [
      (0, 127),
      (128, 190),
      (191, 192),
      (193, 255),
    ]);

    final strobe = channelAt('30-channel mode', 9);
    expect(strobe.kind, 'strobe');
    expect(strobe.ranges, hasLength(9));
    expect(strobe.ranges.first, isA<DmxRange>());
    expect(strobe.ranges.map((r) => (r.start, r.end)), [
      (0, 3),
      (4, 103),
      (104, 107),
      (108, 207),
      (208, 212),
      (213, 225),
      (226, 238),
      (239, 251),
      (252, 255),
    ]);

    // The manual's own "0 - 256"/"0 - 257" typos normalize to 255.
    final xAxis = channelAt('30-channel mode', 1);
    expect(xAxis.ranges.single.end, 255);
    final totalDimming30 = channelAt('30-channel mode', 8);
    expect(totalDimming30.ranges.single.end, 255);

    final red = channelAt('42-channel mode', 1);
    expect(red.name, 'Red');
    expect(red.kind, 'colorIntensity');
    expect(red.color, 'RED');
    final totalDimming42 = channelAt('42-channel mode', 12);
    expect(totalDimming42.ranges.single.end, 255);

    final w1 = channelAt('58-channel mode', 34);
    expect(w1.name, 'White 1');
    expect(w1.kind, 'colorIntensity');
    expect(w1.color, 'WHITE');

    // Synthesized from the ellipsis run between explicit zone 1 (31-34)
    // and zone 7 (55-58): zone 4 starts at channel 43.
    final zone4Red = channelAt('58-channel mode', 43);
    expect(zone4Red.name, 'Red 4');
    expect(zone4Red.kind, 'colorIntensity');
    expect(zone4Red.confidence, lessThan(w1.confidence));

    final r7 = channelAt('58-channel mode', 55);
    expect(r7.name, 'Red 7');
    expect(r7.kind, 'colorIntensity');
    expect(r7.color, 'RED');

    // Filler rows whose function name ends in a digit ("Control 10") must
    // not have that trailing digit absorbed into the DMX value by the
    // digit-split-OCR rejoin: every one of these reads as a plain 0-255
    // range, never a corrupted sub-range like "10-255" or a dropped row
    // that falls back to a "Channel N" placeholder.
    for (var position = 10; position <= 29; position++) {
      final channel = channelAt('30-channel mode', position);
      expect(channel.name, 'Control $position');
      expect(channel.ranges.single.start, 0);
      expect(channel.ranges.single.end, 255);
    }
    for (var position = 21; position <= 42; position++) {
      final channel = channelAt('42-channel mode', position);
      expect(channel.name, 'Control $position');
      expect(channel.ranges.single.start, 0);
      expect(channel.ranges.single.end, 255);
    }
  });

  test('survives OCR noise in sequential mode tables: digit-split values, '
      'manual typo values, and a garbled description', () {
    final result = fixtureFromManualText(
      _sequentialModeManual(noisy: true),
      'noname_moving_effect_light_ocr.pdf',
    );
    final fixture = result.fixture;
    expect(fixture.modes.map((mode) => mode.channelIds.length).toList(), [
      30,
      42,
      58,
    ]);

    DmxChannel channelAt(String modeName, int position) {
      final mode = fixture.modes.firstWhere((m) => m.name == modeName);
      final id = mode.channelIds[position - 1];
      return fixture.channels.firstWhere((c) => c.id == id);
    }

    final rotation = channelAt('30-channel mode', 7);
    // "128-19 0" (digit-split OCR) still resolves to 128-190.
    expect(rotation.ranges.map((r) => (r.start, r.end)), [
      (0, 127),
      (128, 190),
      (191, 192),
      (193, 255),
    ]);

    final strobe = channelAt('30-channel mode', 9);
    expect(strobe.ranges, hasLength(9));

    final red = channelAt('42-channel mode', 1);
    expect(red.name, 'Red');
    expect(red.kind, 'colorIntensity');

    final w1 = channelAt('58-channel mode', 34);
    expect(w1.name, 'White 1');
    final zone4Red = channelAt('58-channel mode', 43);
    expect(zone4Red.name, 'Red 4');
    final r7 = channelAt('58-channel mode', 55);
    expect(r7.name, 'Red 7');
  });

  test('guard: a Chauvet mode-matrix manual still parses via the matrix path '
      'after adding the sequential "<N>-channel mode" table dialect', () {
    // Same shape as the "preserves Chauvet-style channel names and value
    // ranges" test above, plus mid-value prose that says "27 channel
    // mode" without being a real heading — proving the new sequential-mode
    // detector (anchored to the start of a line) doesn't hijack the
    // matrix-table parser's input.
    final table = StringBuffer('''CHAUVET DJ COLORpalette RGB
DMX Channel Assignments and Values
27-CH 15-CH 9-CH 6-CH 3-CH
000 ⇔ 019 27 channel mode
1 Mode
020 ⇔ 255 DMX personalities 15-CH – 3-CH
2 No Function 000 ⇔ 255 No function
000 ⇔ 002 No function
3 Strobe
003 ⇔ 249 Slow to fast
250 ⇔ 255 Sound-Active
''');
    for (var channel = 4; channel <= 27; channel++) {
      const colors = ['Red', 'Green', 'Blue'];
      final color = colors[(channel - 4) % 3];
      final zone = (channel - 4) ~/ 3 + 1;
      table.writeln('$channel $color $zone 000 ⇔ 255 0–100%');
    }
    final result = fixtureFromManualText(
      table.toString(),
      'COLORpalette_UM_Rev4_WO.pdf',
    );
    expect(
      result.fixture.modes.map((mode) => mode.channelIds.length),
      containsAll([27, 15, 9, 6, 3]),
    );
    expect(result.fixture.channels, hasLength(27));
    expect(result.fixture.channels[0].name, 'Mode');
    expect(result.fixture.channels[3].name, 'Red 1');
  });

  test('single-letter "R/G/B/W Dimming" and "Light strip R/G/B" sequential '
      'rows resolve to distinct colors instead of a generic Dimmer', () {
    final b = StringBuffer()
      ..writeln('4. DMX Channel Table')
      ..writeln()
      ..writeln('9-channel mode')
      ..writeln('Channel Function DMX Value Functional Description')
      ..writeln('1 R Dimming 0-255 Red intensity')
      ..writeln('2 G Dimming 0-255 Green intensity')
      ..writeln('3 B Dimming 0-255 Blue intensity')
      ..writeln('4 W Dimming 0-255 White intensity')
      ..writeln('5 Light strip R 0-255 Red')
      ..writeln('6 Light strip G 0-255 Green')
      ..writeln('7 Light strip B 0-255 Blue')
      ..writeln('8 Total dimming 0-255 Brightness');
    final result = fixtureFromManualText(b.toString(), 'letter_colors.pdf');
    final mode = result.fixture.modes.firstWhere(
      (m) => m.name == '9-channel mode',
    );
    DmxChannel channelAt(int position) => result.fixture.channels.firstWhere(
      (c) => c.id == mode.channelIds[position - 1],
    );

    final r = channelAt(1);
    expect(r.name, 'Red');
    expect(r.kind, 'colorIntensity');
    expect(r.color, 'RED');
    final g = channelAt(2);
    expect(g.kind, 'colorIntensity');
    expect(g.color, 'GREEN');
    final blue = channelAt(3);
    expect(blue.kind, 'colorIntensity');
    expect(blue.color, 'BLUE');
    final w = channelAt(4);
    expect(w.kind, 'colorIntensity');
    expect(w.color, 'WHITE');

    final stripR = channelAt(5);
    expect(stripR.kind, 'colorIntensity');
    expect(stripR.color, 'RED');
    final stripG = channelAt(6);
    expect(stripG.kind, 'colorIntensity');
    expect(stripG.color, 'GREEN');
    final stripB = channelAt(7);
    expect(stripB.kind, 'colorIntensity');
    expect(stripB.color, 'BLUE');

    // The master dimmer stays generic and distinct from all of the above.
    final total = channelAt(8);
    expect(total.kind, 'intensity');
    expect(total.color, isNull);
  });

  test('recovers a sequential-mode heading that OCR ran onto the end of the '
      'previous line, as happens on a photographed two-column spread', () {
    // Modeled on the real no-name moving-effect-light corpus photos: a
    // wide two-page spread OCRs with both columns merged onto one physical
    // line, so the second and third mode headings land mid-line right
    // after whatever column-gutter glyph the OCR engine inserted ("|" or
    // ";") instead of opening their own line the way the first heading did.
    final manual =
        '4. DMX Channel Table\n'
        '30-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 X-axis 0-255 0-540 degrees\n'
        '193-255 Counterclockwise infinite rotation | 42-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 Red Dimming 0-255 Red intensity\n'
        '15 tal 0-255 ; 58-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 X-axis 0-255 0-540 degrees\n';
    final result = fixtureFromManualText(manual, 'noname_two_column.pdf');
    expect(
      result.fixture.modes.map((mode) => mode.channelIds.length).toList(),
      [30, 42, 58],
    );
  });

  test('recovers a sequential-mode heading with no gutter glyph at all, '
      'just a plain space, as browser-side Tesseract actually read it', () {
    // The "| " / "; " gutter glyph the previous test models is what the
    // reference OCR harness (tesseract.js@5.1.1 in Node) happened to
    // produce for this exact corpus photo. The live site's vendored
    // Tesseract.js build read the very same two-column gutter as nothing
    // more than an ordinary single space — no glyph survives to anchor a
    // heading-position regex on at all:
    //   "...infinite rotation 42-channel mode"   (captured from IMG_9381)
    //   "...adjust 58-channel mode"               (captured from IMG_9382)
    // Both excerpts below are short, hand-trimmed snippets of those real
    // captures, not bulk OCR dumps.
    final manual =
        '4. DMX Channel Table\n'
        '30-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 X-axis 0-255 0-540 degrees\n'
        '193-255 Counterclockwise infinite rotation 42-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 Red Dimming 0-255 Red intensity\n'
        '15 Horizontal fine adjust 58-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 X-axis 0-255 0-540 degrees\n';
    final result = fixtureFromManualText(manual, 'noname_no_gutter_glyph.pdf');
    expect(
      result.fixture.modes.map((mode) => mode.channelIds.length).toList(),
      [30, 42, 58],
    );
  });

  test('does not double a channel range when the same row is read twice '
      '(extractImage() now keeps both of a photo\'s OCR passes instead of '
      'discarding one, so duplicate rows are expected input)', () {
    final manual =
        '4. DMX Channel Table\n'
        '30-channel mode\n'
        'Channel Function DMX Value Functional Description\n'
        '1 X-axis 0-255 0-540 degrees\n'
        '1 X-axis 0-255 0-540 degrees\n'
        '2 Y-axis 0-255 0-270 degrees\n';
    final result = fixtureFromManualText(manual, 'noname_duplicated_pass.pdf');
    final mode = result.fixture.modes.single;
    final xAxis = result.fixture.channels.firstWhere(
      (c) => c.id == mode.channelIds[0],
    );
    expect(xAxis.ranges, hasLength(1));
    expect(xAxis.ranges.single.end, 255);
  });

  test('merges a sequential-mode table whose heading repeats on a '
      'continuation page instead of dropping the rows that follow it', () {
    final b = StringBuffer()
      ..writeln('4. DMX Channel Table')
      ..writeln()
      ..writeln('30-channel mode')
      ..writeln('Channel Function DMX Value Functional Description');
    for (var channel = 1; channel <= 15; channel++) {
      b.writeln('$channel Control $channel 0-255 Function $channel');
    }
    b
      ..writeln('=== DMXTRACT PAGE 2 ===')
      ..writeln('30-channel mode')
      ..writeln('Channel Function DMX Value Functional Description');
    for (var channel = 16; channel <= 30; channel++) {
      b.writeln('$channel Control $channel 0-255 Function $channel');
    }
    final result = fixtureFromManualText(b.toString(), 'split_table.pdf');
    expect(result.fixture.modes, hasLength(1));
    final mode = result.fixture.modes.single;
    expect(mode.name, '30-channel mode');
    expect(mode.channelIds, hasLength(30));
    for (var position = 16; position <= 30; position++) {
      final channel = result.fixture.channels.firstWhere(
        (c) => c.id == mode.channelIds[position - 1],
      );
      expect(channel.name, 'Control $position');
      expect(channel.confidence, greaterThan(0.5));
    }
  });

  test('does not mistake "READ THIS USER MANUAL" filler text for the model', () {
    // Corpus regression: 1920W_RGBWAUV-.txt / LED120W.txt / shehds200w846strobe.txt
    // all open with this exact safety boilerplate and no other "Model:" or
    // title line, so the titled-model fallback used to capture "THIS" (the
    // word right before "USER MANUAL") as the model.
    final result = fixtureFromManualText(
      '''LED Beam+Wash 19x20W RGBWAUV Zoom Light
CAUTION! Keep this device away from rain and moisture!
FOR YOUR OWN SAFETY, PLEASE READ THIS USER MANUAL CAREFULLY
BEFORE YOU INITIAL START - UP!
DMX Channel Table
1 000-255 Pan
2 000-255 Tilt
3 000-255 Dimmer
4 000-255 Strobe''',
      '1920W_RGBWAUV-.pdf',
    );
    expect(result.fixture.model, isNot('THIS'));
    expect(result.fixture.model, isNot(contains('READ THIS')));
  });

  test('does not turn a descriptive adjective or lowercase prose word in front '
      'of "instruction/programming/owner manual" into the model', () {
    // The "THIS USER MANUAL" fix above replaced a bare firstMatch with an
    // allMatches + stopword-filtered scan, but that scan bypassed the
    // safety/user/owner reject entirely (it returned the raw captured
    // word straight to the caller instead of routing it through
    // _modelFromManualTitle like every other title candidate), and its
    // caseSensitive: false pattern meant an ordinary lowercase prose word
    // satisfied the same "[A-Z]" capture group as a real product name.
    for (final line in const [
      'READ THE SAFETY INSTRUCTION MANUAL FIRST',
      'Refer to the SERVICE instruction manual for repairs',
      'Consult the ADVANCED programming manual for macros',
      'This IMPORTANT instruction manual must be kept',
      'See the GENERAL owner manual for details',
      'Please follow these user instructions carefully',
      'Keep all user instructions for future reference',
    ]) {
      final result = fixtureFromManualText(
        '$line\nDMX Channel Table\n1 000-255 Pan\n2 000-255 Tilt',
        'LM3715R.pdf',
      );
      expect(
        result.fixture.model,
        'LM3715R',
        reason: 'for manual text "$line"',
      );
    }
  });

  test('reads the model from a "<Title> - DMX Traits" cover line on one '
      'physical line', () {
    // Corpus regression: 15a2a6ff....txt opens with "ADJ VIZI XTREME -
    // DMX TRAITS" instead of "... User Manual"; the manual-title pattern
    // used to only recognize "User Manual"/"Owner's Manual" suffixes, so
    // this fell through to the hash-named source file as the model.
    final result = fixtureFromManualText(
      '''ADJ VIZI XTREME - DMX TRAITS
CHANNEL DMX FUNCTION
28Ch 40Ch VALUES
1 1 000-255 Pan Movement
ADJ reserves the right to change specifications without notice.''',
      '15a2a6ff145475d6dd14364285982a4a87a4129d.pdf',
    );
    expect(result.fixture.manufacturer, 'ADJ');
    expect(result.fixture.model, 'VIZI XTREME');
  });

  test('reads the model from a two-line "<Title>\\nUser Instructions" cover '
      'page', () {
    // Corpus regression: a623026....txt opens with " VIZI XTREME" on one
    // line and "User Instructions" on the next; neither "User
    // Instructions" nor a two-physical-line title were recognized, so
    // this also fell back to the hash-named source file.
    final result = fixtureFromManualText(''' VIZI XTREME
User Instructions

DMX Channel Table
1 000-255 Pan
2 000-255 Tilt''', 'a623026b9d58cf797618e8003a458e390cd49754.pdf');
    expect(result.fixture.model, 'VIZI XTREME');
  });

  test('reads the full two-word model from a two-line "<Title>\\nUser Manual" '
      'cover page', () {
    // Corpus regression: 8cc4abe....txt opens with "HYDRO HYBRID" on one
    // line and "User Manual" (indented) on the next. The old titled-model
    // fallback only captured a single token directly before "User
    // Manual" on the same line, so it returned "HYBRID" and silently
    // dropped "HYDRO".
    final result = fixtureFromManualText('''HYDRO HYBRID
   User Manual

DMX Channel Table
1 000-255 Pan
2 000-255 Tilt''', '8cc4abe74ab952c51489d1eb55d4f2e0458ded65.pdf');
    expect(result.fixture.model, 'HYDRO HYBRID');
  });

  test('does not read a revision-history table row above a running "DMX '
      'Traits" heading as the model', () {
    // Corpus regression class (8cc4abe74ab...txt, page 2): a document-
    // version table has a date/revision-number row directly above a
    // running "DMX Traits" section heading — "<data row>\nDMX Traits" is
    // exactly the same two-physical-line shape as a real cover title
    // above a doc-type suffix. The two-line title scan used to run
    // unconditionally over the *whole* document, so on a manual whose
    // real cover title is unreadable (an image), firstMatch would land on
    // this row instead of falling through to the filename.
    final result = fixtureFromManualText(
      '=== DMXTRACT PAGE 1 ===\n'
          'CAUTION! Keep this device away from rain and moisture!\n'
          '=== DMXTRACT PAGE 2 ===\n'
          ' 09/09/2024  1.3  N/C  No Changes\n'
          '                                    DMX Traits\n'
          'DMX Channel Table\n'
          '1 000-255 Pan\n'
          '2 000-255 Tilt',
      'LM3715R.pdf',
    );
    expect(result.fixture.model, isNot(contains('09/09/2024')));
    expect(result.fixture.model, isNot(contains('Changes')));
    expect(result.fixture.model, 'LM3715R');
  });

  test('does not read a table-of-contents dot-leader line or a "Field: value" '
      'spec line above a doc-type suffix as the model', () {
    // Same defect class as the revision-history case above, reproduced
    // with the other two boilerplate shapes the two-line scan can land
    // on once a manual has more than a cover page: a TOC entry
    // ("Troubleshooting ..... 14") and a spec line ("Weight: 12.5 kg").
    final toc = fixtureFromManualText(
      'Troubleshooting ..................... 14\nUser Instructions\n'
          'DMX Channel Table\n1 000-255 Pan\n2 000-255 Tilt',
      'LM3715R.pdf',
    );
    expect(toc.fixture.model, isNot(contains('Troubleshooting')));
    expect(toc.fixture.model, 'LM3715R');

    final spec = fixtureFromManualText(
      'Weight: 12.5 kg\nUser Manual\n'
          'DMX Channel Table\n1 000-255 Pan\n2 000-255 Tilt',
      'LM3715R.pdf',
    );
    expect(spec.fixture.model, isNot(contains('Weight')));
    expect(spec.fixture.model, 'LM3715R');
  });

  test(
    'strips revision and date stamps out of the filename fallback model',
    () {
      // Corpus regression: SPECTRA_MANUAL_REV0_20210204.txt's real title is
      // unreadable (a garbled subset-font cover page), so extraction falls
      // back to the source filename, which used to surface verbatim as
      // "SPECTRA REV0 20210204" instead of just "SPECTRA".
      final result = fixtureFromManualText(
        '''Have a question regarding this manual?
DMX Channel Table
1 000-255 Pan
2 000-255 Tilt''',
        'SPECTRA_MANUAL_REV0_20210204.pdf',
      );
      expect(result.fixture.model, 'SPECTRA');
    },
  );

  test('does not delete an 8-digit part number or leave a dangling separator '
      'when stripping filename revision/date markers', () {
    // The date strip above used an unanchored \b\d{8}\b, which deletes
    // ANY 8-digit run, date-shaped or not — including a genuine 8-digit
    // OEM/rebadge part number, which is common on this app's audience of
    // rebadged fixtures. And neither strip re-trimmed the separator it
    // left behind, so a leading "Rev-" or "Rev_" surfaced as punctuation
    // stuck to the front of the model.
    final noTitleText =
        'Have a question regarding this manual?\n'
        'DMX Channel Table\n1 000-255 Pan\n2 000-255 Tilt';

    // A real 8-digit part number is not a YYYYMMDD date stamp and must
    // survive.
    expect(
      fixtureFromManualText(noTitleText, 'LED-12345678.pdf').fixture.model,
      contains('12345678'),
    );

    // A leading "Rev-" strips to just its separator; that separator must
    // not surface as part of the model.
    expect(
      fixtureFromManualText(noTitleText, 'Rev-Party-Bar.pdf').fixture.model,
      'Party-Bar',
    );

    // A short revision index directly after "Rev" is still removed
    // ("Rev0"/"Rev. 2"), but a longer number after "Rev " is a model
    // number, not a revision index, and must not be deleted with it.
    expect(
      fixtureFromManualText(noTitleText, 'MAC_Rev_2000.pdf').fixture.model,
      contains('2000'),
    );
  });

  test('rejects a bare content-hash filename as the model', () {
    // Corpus regression: a623026b....txt and 15a2a6ff....txt both arrive
    // named after their content hash with no other filename clue, and used
    // to surface that 40-character hex string verbatim as the model when
    // no in-document title matched.
    final result = fixtureFromManualText(
      '''Some unrelated body text with no title or manual marker.
DMX Channel Table
1 000-255 Pan
2 000-255 Tilt''',
      '9e48fa0ab3c982dff2a2841efb795bbeb4e99334.pdf',
    );
    expect(result.fixture.model, 'Unknown fixture');
  });

  test('recovers a model from a glyph-tracked "<Title> - DMX Traits" cover '
      'line', () {
    // Corpus regression: 9e48fa0a....txt's cover line renders as
    // "E L I M I N AT O R L P H E X 1 2 P L U S - D M X T R A I T S"
    // (the title font tracks every glyph apart, so pdftotext prints one
    // token per glyph with no way to tell a within-word gap from a
    // between-word gap) and used to fall through to the hash filename as
    // the model. Only the letter/digit boundary survives as an
    // unambiguous split point, so "ELIMINATOR" (a recognized brand
    // prefix, stripped like "Chauvet"/"Martin" elsewhere) can be
    // separated out, but "LP" and "HEX" can't be told apart from plain
    // text alone.
    final result = fixtureFromManualText(
      '''E L I M I N AT O R L P H E X 1 2 P L U S - D M X T R A I T S
CHANNEL
6Ch 10Ch
1 2 000-255 Total Dimmer''',
      '9e48fa0ab3c982dff2a2841efb795bbeb4e99334.pdf',
    );
    expect(result.fixture.model, 'LPHEX 12 PLUS');
  });

  test('does not read a channel-menu row\'s value label ("...Mode 1 CH9...") '
      'as a bogus 1-channel/2-channel mode', () {
    // Corpus regression: shehds200w846strobe.txt's control-menu table
    // describes channel 8's function as "RGB TXT Mode 1" immediately
    // followed by channel 9's row ("CH9 RGB Dual-Sign R..."). Read
    // together that's "Mode 1 CH9" / "Mode 2 CH10", which the mode-count
    // scan used to misread as declarations of a 1-channel and a
    // 2-channel mode alongside the real 6CH/19CH modes.
    final result = fixtureFromManualText('''
DMX Channel Table
DMX Channel 6CH / 19CH
1.Channel 6CH Set the DMX channel mode to 6CH mode
19CH Set the DMX channel mode to 19CH mode
CH8 RGB Dual-Sign L 000-255 RGB TXT Mode 1
CH9 RGB Dual-Sign R 000-255 RGB TXT Mode 2
1 1 000-255 Tilt
2 2 000-255 Pan
''', 'shehds_test.pdf');
    final sizes = result.fixture.modes
        .map((mode) => mode.channelIds.length)
        .toList();
    expect(sizes, isNot(contains(1)));
    expect(sizes, isNot(contains(2)));
    expect(sizes, containsAll([6, 19]));
  });

  test('reads all three modes of a "Basic/Standard/Extended NCh" table '
      'instead of stopping at a value sub-table with no position column', () {
    // Corpus regression: 8cc4abe....txt (ADJ Hydro Hybrid) declares
    // "Basic 24CH", "Standard 27CH" and "Extended 32CH" modes via a
    // multi-column DMX Traits table, but two other bugs used to hide
    // all but one of them: (1) a "UNIT 1 UNIT 2 UNIT 3 UNIT 4" table's
    // last column ran into an unrelated "CHANNEL MODE" heading right
    // after it (on the flattened text), misread as a bogus 4-channel
    // mode; (2) once modeCounts held 2+ real counts already, a
    // sequential-position scan of the DMX Traits table's own leftmost
    // ("Basic") column — interrupted mid-table by a Color Macro value
    // list with no position number of its own — landed on a stray
    // partial count (6) that got appended as a bogus extra mode.
    final result = fixtureFromManualText('''
See the chart below for more details.
                                     UNIT 1        UNIT 2         UNIT 3        UNIT 4
              CHANNEL MODE
                                    ADDRESS       ADDRESS        ADDRESS       ADDRESS
                     24Ch              1             25             49            73
                     27Ch              1             28             55            82
                     32Ch              1             33             65            97

DMX TRAITS
               CHANNEL                    DMX                             FUNCTION
Basic 24CH   Standard 27CH Extended 32CH VALUES
     1             1              1       0-255 Pan
                   2              2       0-255 Pan Fine
    2              3              3       0-255 Tilt
    3              5              5       0-255 Cyan
                                          0-4   Color (open)
                                          5-9   Red
                                         10-14 Blue
    6              8             11      110-114 Amber
''', '8cc4abe7test.pdf');
    final sizes =
        result.fixture.modes.map((mode) => mode.channelIds.length).toList()
          ..sort();
    expect(sizes, [24, 27, 32]);
  });

  test('PHX_LVD-style installation manual with no DMX channels stays at 0 '
      'modes and is still recognized as Altman', () {
    // Regression floor: PHX_LVD_USER_MANUAL_49-0216_20230116.txt genuinely
    // has no DMX channel table at all (it's an installation guide for a
    // non-DMX luminaire series) — 0 modes is the correct answer for this
    // fixture, not a defect, and must not start producing modes as a
    // side effect of loosening the title/mode-count heuristics above.
    final result = fixtureFromManualText('''
PHX LVD Series                                                          Installation & Users Manual
 The material in this manual is for information purposes only and is subject to change without notice. Altman Lighting assumes no
 responsibility for any errors or omissions which may appear in this manual.
''', 'PHX_LVD_USER_MANUAL_49-0216_20230116.pdf');
    expect(result.fixture.modes, isEmpty);
    expect(result.fixture.manufacturer, 'Altman');
  });

  test('does not bleed a Color Macros Chart\'s value columns into channel '
      'names on the generic table fallback', () {
    // Real corpus shape (ADJ_Encore_LP12Z_IP_UM, ADJ_Focus_Wash_400_UM):
    // once every structured-mode detector (named/matrix/sequential/
    // contextual/coded) comes up empty, `_tableChannels`'s generic "DMX
    // TRAITS" fallback scans every "N <description>" line for a
    // sequential N = 1, 2, 3... regardless of which page it is on. A
    // later "COLOR MACROS CHART" also numbers its rows 1..N but every
    // column past the row number is a plain DMX value (RED/GREEN/BLUE/
    // LIME intensities, no function name at all) — the same grammar
    // matches it, and the leading-mode-column stripping in
    // `_classifyTableChannel` mis-anchors on it, leaving one stray macro
    // value ("80", "77", "0"...) standing in as the channel name for
    // every position instead of a real function name.
    final manual = StringBuffer()
      ..writeln('ADJ Encore LP12Z IP User Manual')
      ..writeln('ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ ADJ')
      ..writeln('Thank you for purchasing this ADJ product.')
      ..writeln('This fixture operates in an 18Ch mode.')
      ..writeln('DMX TRAITS')
      ..writeln('COLOR MACROS CHART')
      ..writeln('MACRO NUMBER    DMX VALUE     RED   GREEN   BLUE   LIME');
    const red = [
      80, 80, 77, 117, 160, 223, 255, 255, 255, 255, //
      234, 197, 160, 122, 85, 47, 10, 0,
    ];
    for (var i = 1; i <= 18; i++) {
      final start = (i - 1) * 4 + 1;
      final end = i * 4;
      final startLabel = start.toString().padLeft(3, '0');
      final endLabel = end.toString().padLeft(3, '0');
      manual.writeln(
        '$i   $startLabel - $endLabel   ${red[i - 1]}  255  164  80',
      );
    }
    final result = fixtureFromManualText(
      manual.toString(),
      'ADJ_Encore_LP12Z_IP_UM.pdf',
    );
    final mode18 = result.fixture.modes.firstWhere(
      (mode) => mode.channelIds.length == 18,
    );
    for (final id in mode18.channelIds) {
      final name = result.fixture.channels
          .firstWhere((channel) => channel.id == id)
          .name;
      expect(
        RegExp(r'^\d+$').hasMatch(name),
        isFalse,
        reason: 'channel name "$name" leaked a bare Color Macro value',
      );
    }
  });

  test('reads MSB/LSB and bare-marker rows as fine companions, not '
      'standalone channels', () {
    // Real corpus shape (Martin_MAC700Profile_UM): "the main control
    // channel sets the ... most significant byte (MSB), and the fine
    // channel[] set[s] the ... least significant byte (LSB)" — printed
    // in the channel table as "Dimmer (MSB)" for the coarse row and
    // "Dimmer, fine (LSB)" for its fine byte, and (synthesized here from
    // the same notation) a bare "LSB" continuation row with no attribute
    // word of its own, the way a fixture that never repeats the coarse
    // name prints its fine byte.
    final manual = '''Martin MAC 700 Profile DMX Mode
6 DMX channels
1 Dimmer (MSB)
2 Dimmer, fine (LSB)
3 Pan MSB
4 Pan LSB
5 Tilt
6 LSB
Simple DMX Mode
2 DMX channels
1 Dimmer
2 Strobe
''';
    final result = fixtureFromManualText(manual, 'Martin_MAC700Profile_UM.pdf');
    final mode = result.fixture.modes.firstWhere(
      (mode) => mode.channelIds.length == 6,
    );
    final channels = mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(channels[0].name, 'Dimmer');
    expect(channels[0].kind, 'intensity');
    expect(channels[0].fineOf, isNull);
    expect(channels[1].kind, 'intensity');
    expect(channels[1].fineOf, isNotNull);
    expect(channels[2].name, 'Pan');
    expect(channels[2].fineOf, isNull);
    expect(channels[3].kind, 'pan');
    expect(channels[3].fineOf, isNotNull);
    expect(channels[4].name, 'Tilt');
    expect(channels[5].kind, 'tilt');
    expect(channels[5].fineOf, isNotNull);
  });

  test('reads a per-cell "XY | Ext. Function" repeated block table instead '
      'of falling back to generic "Channel N" placeholders', () {
    // Real corpus shape (ChauvetPro_COLORadoSOLOBar4_UM's 16-cell XY
    // personality): each cell repeats an 8-channel block (Dimmer/Fine
    // dimmer/X coordinate/Fine X coordinate/Y coordinate/Fine Y
    // coordinate/Strobe/Virtual Color Wheel), but the table's true
    // sequential position lives in a SECOND column ("Ext. Function");
    // the first column ("XY") is sparse, printing a bare "–" for every
    // row except a cell's first. `_parseTableSection`'s single-leading-
    // number row grammar only ever looked at the first column, so it
    // matched cell 1's "Dimmer 1" row (position 1 in both columns) and
    // then stalled forever on "– 2 Fine dimmer 1..." — reproducing the
    // benchmark's "142 of 147 slots come back 'Channel N'/NoFeature".
    const v = '000  255'; // this table family's value-range glyph
    final manual =
        '''Chauvet Professional COLORado Solo Bar 4 User Manual
This personality uses 16 channels.
DMX Channel Assignments and Values
Operation
2 Cell Personalities
XY
 XY   Ext. Function                        Value    Percent/Setting
  1    1   Dimmer 1                      $v 0-100%
  –    2   Fine dimmer 1                 $v 0-100%
  2    3   X coordinate 1                $v 0-100%
  –    4   Fine X coordinate 1           $v 0-100%
  3    5   Y coordinate 1                $v 0-100%
  –    6   Fine Y coordinate 1           $v 0-100%
  –    7   Strobe 1                      $v See the Strobe Chart
  –    8   Virtual Color Wheel 1         $v See the Virtual Color Wheel Chart
  4    9   Dimmer 2                      $v 0-100%
  –   10   Fine dimmer 2                 $v 0-100%
  5   11   X coordinate 2                $v 0-100%
  –   12   Fine X coordinate 2           $v 0-100%
  6   13   Y coordinate 2                $v 0-100%
  –   14   Fine Y coordinate 2           $v 0-100%
  –   15   Strobe 2                      $v See the Strobe Chart
  –   16   Virtual Color Wheel 2         $v See the Virtual Color Wheel Chart
''';
    final result = fixtureFromManualText(
      manual,
      'ChauvetPro_COLORadoSOLOBar4_UM.pdf',
    );
    final mode = result.fixture.modes.firstWhere(
      (mode) => mode.channelIds.length == 16,
    );
    final channels = mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(channels[0].name, 'Dimmer 1');
    expect(channels[1].fineOf, isNotNull);
    expect(channels[1].kind, 'intensity');
    expect(channels[2].name, 'X coordinate 1');
    expect(channels[4].name, 'Y coordinate 1');
    expect(channels[6].name, 'Light switch / strobe');
    expect(channels[7].name, 'Color wheel');
    expect(channels[8].name, 'Dimmer 2');
    expect(channels[9].fineOf, isNotNull);
    for (final channel in channels) {
      expect(
        RegExp(r'^Channel \d+$').hasMatch(channel.name),
        isFalse,
        reason:
            '"${channel.name}" fell back to a generic placeholder instead '
            'of reading the per-cell block',
      );
    }
  });

  test('reads a per-cell table with up to seven throwaway leading '
      'personality columns ahead of the real position number', () {
    // Real corpus shape (ChauvetPro_COLORadoSOLOBar4_UM's 259-channel
    // "RGBWL Full 259ch" mode, straight off the manual): up to SEVEN
    // other-personality columns lead the row, not the one throwaway
    // column the "XY | Ext. Function" table above has - the real text
    // this fixture prints is "– – – – 1 1 1 1 Dimmer 1 000 255 0–100%"
    // for channel 1 and "– – – – – – – 2 Fine dimmer 1 000 255 0–100%"
    // for channel 2, i.e. the sequential "Ext. Function" number is the
    // LAST of eight leading digit/dash tokens, not the second.
    // Every leading-column count from 1 (the "XY | Ext. Function" shape
    // above) through 7 has to keep working, and the true sequential
    // position has to advance one at a time with no gaps for
    // [_parseTableSection]'s "N <description>" grammar to keep matching -
    // so this reproduces the real table's actual interleaving of "Ext.
    // Function"-numbered rows (coarse channels matching the PLAIN
    // single-leading-number grammar directly, e.g. "1 1 1 1 Red 1 ...")
    // with sparse, up-to-seven-throwaway-column rows (fine bytes, e.g.
    // "– – – 2 – – – 4 Fine red 1 ..."), rather than only the sparse rows
    // in isolation.
    const v = '000  255';
    final manual =
        '''Chauvet Professional COLORado Solo Bar 4 User Manual
This personality uses 5 channels.
DMX Channel Assignments and Values
Operation
16 Cell Personalities
XY
 –  –  –  –  1  1  1  1   Dimmer 1               $v 0–100%
 –  –  –  –  –  –  –  2   Fine dimmer 1          $v 0–100%
  1  1  1  1  2  2  2  3   Red 1                  $v 0–100%
 –  –  –  2  –  –  –  4   Fine red 1             $v 0–100%
 –  –  –  –  5  6  7  5   Color temperature 1    $v See the Color Temperature Chart
''';
    final result = fixtureFromManualText(
      manual,
      'ChauvetPro_COLORadoSOLOBar4_UM.pdf',
    );
    final mode = result.fixture.modes.firstWhere(
      (mode) => mode.channelIds.length >= 5,
    );
    final channels = mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(channels[0].name, 'Dimmer 1');
    expect(channels[1].fineOf, isNotNull);
    expect(channels[2].name, 'Red 1');
    expect(channels[3].fineOf, isNotNull);
    for (final channel in channels) {
      expect(
        RegExp(r'^Channel \d+$').hasMatch(channel.name),
        isFalse,
        reason:
            '"${channel.name}" fell back to a generic placeholder instead '
            'of reading the eight-leading-column per-cell block',
      );
    }
  });

  test('classifies a channel name no hand-written heuristic recognizes via '
      'the mined unified.db name-to-attribute table', () {
    // "Frost"/"Iris" have no dedicated branch in [_classifyTableChannel] at
    // all (unlike "gobo"/"prism"/"zoom", which do) — before the mined
    // fallback, these fell all the way through to a bare `kind: 'generic'`
    // channel, which defaults to the GDTF attribute "NoFeature" regardless
    // of what the channel actually does.
    final manual = '''Test Fixture DMX Mode
3 DMX channels
1 Dimmer
2 Frost
3 Iris
Simple DMX Mode
1 DMX channels
1 Dimmer
''';
    final result = fixtureFromManualText(manual, 'Test_Fixture_UM.pdf');
    final mode = result.fixture.modes.firstWhere(
      (mode) => mode.channelIds.length == 3,
    );
    final channels = mode.channelIds
        .map(
          (id) => result.fixture.channels.firstWhere((item) => item.id == id),
        )
        .toList();
    expect(channels[1].name, 'Frost');
    expect(channels[1].gdtfAttribute, 'Frost1');
    expect(channels[2].name, 'Iris');
    expect(channels[2].gdtfAttribute, 'Iris');
  });

  test('parses a sparse 8-column mode-matrix header with no "Ch" unit '
      '(Chauvet Pro COLORado Solo Bar 4)', () {
    // A trimmed but real excerpt of the COLORado Solo Bar 4 manual's "RGB
    // 48ch - RGBWL Full 259ch" table (testcorpus/
    // ChauvetPro_COLORadoSOLOBar4_UM.pdf): eight parallel personality
    // columns (48/64/80/160/115/131/147/259 channels) sharing one
    // Function/Value column, header declared as bare channel-count
    // numbers with no "Ch" suffix (unlike the 3-column Chauvet DJ
    // grammar [_labeledModeMatrixTables] already handles), and a dash
    // meaning a function doesn't exist in that mode. The smaller modes
    // (48/64/80/160ch) skip "Dimmer 1"/"Fine dimmer 1" entirely and pick
    // up at "Red 1" as their own first channel - exercising the sparse,
    // not-just-narrower relationship between columns this dialect needs.
    const manual = '''CHAUVET Professional
COLORado Solo Bar 4 User Manual Rev. 1
Operation
RGB 48ch - RGBWL Full 259ch
259: RGBWL Full 259ch, 147: RGBWL Ext. 147ch, 131: RGBW Ext. 131ch, 115: RGB Ext. 115ch,
160:RGBWL 16-bit 160ch, 80: RGBWL 80ch, 64: RGBW 64ch, 48: RGB 48ch
48 64 80 160 115 131 147 259 Function                Value   Percent/Setting
 – – – –      1   1   1   1 Dimmer 1               000  255 0-100%
 – – – –      –   –   –   2 Fine dimmer 1          000  255 0-100%
 1 1 1 1      2   2   2   3 Red 1                  000  255 0-100%
 – – – 2      –   –   –   4 Fine red 1             000  255 0-100%
''';
    final result = fixtureFromManualText(
      manual,
      'ChauvetPro_COLORadoSOLOBar4_UM.pdf',
    );
    expect(result.fixture.modes.map((mode) => mode.name), [
      '48Ch',
      '64Ch',
      '80Ch',
      '160Ch',
      '115Ch',
      '131Ch',
      '147Ch',
      '259Ch',
    ]);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      48,
      64,
      80,
      160,
      115,
      131,
      147,
      259,
    ]);

    DmxChannel channelAt(String modeName, int position) {
      final mode = result.fixture.modes.firstWhere(
        (mode) => mode.name == modeName,
      );
      final id = mode.channelIds[position - 1];
      return result.fixture.channels.firstWhere((item) => item.id == id);
    }

    // The widest mode (259Ch) has all four rows as its own channels 1-4.
    expect(channelAt('259Ch', 1).name, 'Dimmer 1');
    expect(channelAt('259Ch', 2).fineOf, channelAt('259Ch', 1).id);
    expect(channelAt('259Ch', 3).name, 'Red 1');
    expect(channelAt('259Ch', 4).fineOf, channelAt('259Ch', 3).id);

    // The smallest mode (48Ch) skips both dimmer channels (dash in every
    // one of its rows) and starts directly at "Red 1" as channel 1 - the
    // sparse-column mapping the task exists to fix.
    expect(channelAt('48Ch', 1).name, 'Red 1');
    expect(channelAt('48Ch', 1).name.startsWith('Channel '), isFalse);

    // Every mode's channel ids are unique even though several modes
    // share the same channel count elsewhere in a real manual (see the
    // idPrefix-collision fix this table family exposed) - a smoke check
    // that lookups above actually resolved distinct channels, not one
    // channel aliased across modes.
    final allIds = result.fixture.channels.map((c) => c.id).toList();
    expect(allIds.toSet().length, allIds.length);
  });

  test('parses Robe\'s "Mode/Total channels" DMX protocol table with an '
      'asterisk absent-marker (Robin Footsie)', () {
    // A trimmed but real excerpt of the Robin Footsie1/Footsie1 Slim
    // manual's "DMX protocol" table (testcorpus/Robe_Footsie1_UM.pdf):
    // three parallel mode columns declared as "<mode>/<total-channels>"
    // pairs (1/5, 2/28, 3/35 - matching this fixture's real GDTF truth
    // footprints), an asterisk (not a dash) meaning a function doesn't
    // exist in that mode, and every range on its own line below the row
    // rather than inline with the function name.
    const manual = '''ROBE LIGHTING
Robin Footsie1 User Manual
DMX protocol
Robin Footsie1TM/Robin Footsie1TM Slim - DMX protocol
Version: 1.4 Mode 1-Simple mode, Mode 2 -Standard 16-bit, Mode 3-Standard 16-bit & PIP
Mode/Total channels             DMX                                             Type of
                                                     Function
   1/5          2/28        3/35         Value                                  control
     *            1            1                   Power/Special functions
                                          0-9      Reserved (0=default)
                                         10-255    Reserved
     *            2            2                   LED frequency selection
                                          0-255     PWM frequency
     1            3            3                   Dimmer
                                          0-255     Dimmer intensity from 0% to 100%
''';
    final result = fixtureFromManualText(manual, 'Robe_Footsie1_UM.pdf');
    expect(result.fixture.modes.map((mode) => mode.name), [
      '5Ch',
      '28Ch',
      '35Ch',
    ]);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      5,
      28,
      35,
    ]);

    DmxChannel channelAt(String modeName, int position) {
      final mode = result.fixture.modes.firstWhere(
        (mode) => mode.name == modeName,
      );
      final id = mode.channelIds[position - 1];
      return result.fixture.channels.firstWhere((item) => item.id == id);
    }

    // Mode 1 (5Ch) skips "Power/Special functions" and "LED frequency
    // selection" entirely (asterisk in both) and starts at "Dimmer" -
    // the same sparse-column mapping as the Chauvet dialect above, this
    // time keyed off "*" instead of a dash.
    expect(channelAt('5Ch', 1).name, 'Dimmer');
    expect(
      channelAt(
        '5Ch',
        1,
      ).ranges.map((range) => (range.start, range.end, range.name)),
      [(0, 255, 'Dimmer intensity from 0% to 100%')],
    );

    // Mode 2 (28Ch) has all three rows as its own channels 1-3.
    expect(channelAt('28Ch', 1).name, 'Power/Special functions');
    expect(
      channelAt('28Ch', 1).ranges.map((range) => (range.start, range.end)),
      [(0, 9), (10, 255)],
    );
    expect(channelAt('28Ch', 2).name, 'LED frequency selection');
    expect(channelAt('28Ch', 3).name, 'Dimmer');
  });

  test('infers a Robe "Mode/channel" table\'s per-mode channel count from '
      'the highest row position observed (Robin LEDBeam)', () {
    // A trimmed but real excerpt of the Robin LEDBeam 150 FW manual's
    // "DMX protocol" table (testcorpus/Robe_LEDBeam150FW_UM.pdf): two
    // parallel mode columns declared only by their bare mode index (no
    // "/<total>" - unlike the Footsie excerpt above), so each mode's
    // real channel count (this fixture's GDTF truth: 22 and 16) has to
    // come from the highest position actually printed for that column,
    // not from the header. Mode 2's own ranges use a plain dash
    // ("0 - 255") - the reason [_robeMatrixTokenPattern] (asterisk-only)
    // exists as a distinct token pattern from the Chauvet family's
    // dash-based one: accepting a dash as an absent-marker here too
    // would misread a value line such as "20-24 ..." as a channel row.
    const manual = '''ROBE LIGHTING
Robin LEDBeam 150 FW User Manual
DMX protocol
Robin LEDdBeam 150/LEDBeam 150 FW/LEDBeam 150Q/LEDBeam 150 FWQ - DMX protocol
Version: 1.7 Mode 1-Standard 16-bit, Mode 2 -Reduced 8-bit
Mode/channel    DMX                                               Type of
                                       Function
 1      2       Value                                             control
 1      1                 Pan (8 bit)
                0 - 255   Pan movement by 450 degrees (128=default)
 2      2                 Pan Fine (16 bit)
                0 - 255   Fine control of pan movement (0=default)
 21     16                    Dimmer intensity (8 bit)
                 0 - 255     Dimmer intensity from 0% to 100% (0=default)
 22     *                    Dimmer intensity - fine (16 bit)
                 0 - 255     Fine dimming (0=default)
''';
    final result = fixtureFromManualText(manual, 'Robe_LEDBeam150FW_UM.pdf');
    expect(result.fixture.modes.map((mode) => mode.name), ['22Ch', '16Ch']);
    expect(result.fixture.modes.map((mode) => mode.channelIds.length), [
      22,
      16,
    ]);

    DmxChannel channelAt(String modeName, int position) {
      final mode = result.fixture.modes.firstWhere(
        (mode) => mode.name == modeName,
      );
      final id = mode.channelIds[position - 1];
      return result.fixture.channels.firstWhere((item) => item.id == id);
    }

    expect(channelAt('22Ch', 1).name, contains('Pan'));
    expect(channelAt('22Ch', 21).name, contains('Dimmer'));
    expect(channelAt('22Ch', 22).fineOf, channelAt('22Ch', 21).id);
    // Mode 2 (16Ch) has no 22nd channel at all - the fine dimmer byte
    // (asterisk in mode 2's column) doesn't exist in this mode, and its
    // *own* real last channel is position 16 ("Dimmer intensity"), not a
    // placeholder padded out to mode 1's width.
    expect(channelAt('16Ch', 16).name, contains('Dimmer'));
    expect(channelAt('16Ch', 16).name.startsWith('Channel '), isFalse);
  });

  test('reads a front-panel menu\'s "CH: N, N, N, N" field as mode-count '
      'evidence (Elation SIXPAR 200)', () {
    // A trimmed but real excerpt of the Elation SIXPAR 200 manual
    // (corpus_probe/Elation_SixPar200_UM.pdf), stripped down to just its
    // menu-navigation prose and menu-reference table row - no DMX
    // channel table at all - so this exercises the "CH:" mode-count
    // scan on its own, not in combination with the numeric "6 CH 7 CH
    // 8 CH 12 CH" table header elsewhere in the real manual (which the
    // generic "<N> CH" scan already picks up independently).
    const manual = '''ELATION SIXPAR 200
SIXPAR 200 User Manual
FIXTURE MENU
During normal operation, pressing the MODE button will navigate through the
different function menus. For example, the CHANNEL CH: menu variable field can
be set to 06, 07, 08, or 12. Pressing the ENTER button once will confirm your
selected value.

    MENU               OPTIONS / VALUES                       DESCRIPTION
CHANNEL      CH: 06, 07, 08, 12                       DMX Channel Mode
''';
    final result = fixtureFromManualText(manual, 'Elation_SixPar200_UM.pdf');
    expect(result.fixture.modes.map((mode) => mode.channelIds.length).toSet(), {
      6,
      7,
      8,
      12,
    });
  });
}

/// Builds a synthetic "N-channel mode" manual excerpt modeled on a
/// no-name moving-effect-light manual's "4. DMX Channel Table" section
/// (three modes: 30/42/58 channels). When [noisy] is true, a handful of
/// rows are rewritten the way OCR mangles them: a value split by a stray
/// inner space ("128-19 0", "200-2 50", "2 51-255") and a missing/garbled
/// description cell — on top of the manual's own "0 - 256"/"0 - 257"/
/// "0 - 258" typos, which are present either way.
String _sequentialModeManual({required bool noisy}) {
  final b = StringBuffer()
    ..writeln('NONAME MOVING EFFECT LIGHT')
    ..writeln('User Manual')
    ..writeln('4. DMX Channel Table')
    ..writeln()
    ..writeln('30-channel mode')
    ..writeln('Channel Function DMX Value Functional Description')
    ..writeln('1 X-axis 0-256 0-540 degrees')
    ..writeln('2 X-axis fine adjustment 0-255 16bit')
    ..writeln('3 Y-axis 0-205 0-270 degrees')
    ..writeln('4 Y-axis fine adjustment 0-255 16bit')
    ..writeln('5 XY Speed 0-255 fast to slow')
    ..writeln('6 Focusing 0-255 angle small to large')
    ..writeln('7 Rotation 0-127 Indexed positioning')
    ..writeln(
      noisy
          ? '128-19 0 Rotate clockwise infinitely'
          : '128-190 Rotate clockwise infinitely',
    )
    ..writeln('191-192 Stop')
    ..writeln('193-255 Rotate counterclockwise infinitely')
    ..writeln('8 Total dimming 0-257 Brightness')
    ..writeln('9 Strobe 0-3 Turn off')
    ..writeln('4-103 Synchronous flash, slow to fast')
    ..writeln('104-107 Light up')
    ..writeln('108-207 Even frequency flash, slow to fast')
    ..writeln('208-212 Light up')
    ..writeln('213-225 Slow random strobe')
    ..writeln('226-238 Medium speed random strobe')
    ..writeln('239-251 High-speed random strobe')
    ..writeln('252-255 Light up');
  for (var channel = 10; channel <= 29; channel++) {
    b.writeln('$channel Control $channel 0-255 Function $channel');
  }
  b
    ..writeln(noisy ? '30 Reset 0-250' : '30 Reset 0-250 No function')
    ..writeln(
      noisy
          ? '2 51-255 R3s3t ~5 s3conds (garbled)'
          : '251-255 Reset about 5 seconds',
    )
    ..writeln()
    ..writeln('42-channel mode')
    ..writeln('Channel Function DMX Value Functional Description')
    ..writeln('1 Red Dimming 0-255 Red intensity')
    ..writeln('2 Red fine tuning 0-255 Red fine')
    ..writeln('3 Green Dimming 0-255 Green intensity')
    ..writeln('4 Green fine tuning 0-255 Green fine')
    ..writeln('5 Blue Dimming 0-255 Blue intensity')
    ..writeln('6 Blue Fine Tuning 0-255 Blue fine')
    ..writeln('7 White Dimming 0-255 White intensity')
    ..writeln('8 White fine tuning 0-255 White fine')
    ..writeln('9 Linear color temperature adjustment 0-255 Warm to cool')
    ..writeln('10 Color Macros 0-255 Presets')
    ..writeln('11 Strobe 0-255 Slow to fast')
    ..writeln('12 Total dimming 0-258 Brightness')
    ..writeln('13 Dimming fine-tuning 0-255 Fine')
    ..writeln('14 Level horizontal 0-255 Pan')
    ..writeln('15 Horizontal fine-tuning 0-255 Pan fine')
    ..writeln('16 Vertical 0-255 Tilt')
    ..writeln('17 Vertical fine adjustment 0-255 Tilt fine')
    ..writeln('18 Function reserve 0-255 Reserved')
    ..writeln('19 Reset 0-199 No function')
    ..writeln(noisy ? '200-2 50 Reserved' : '200-250 Reserved')
    ..writeln('251-255 Reset 5 seconds')
    ..writeln('20 Focusing 0-255 Focus');
  for (var channel = 21; channel <= 42; channel++) {
    b.writeln('$channel Control $channel 0-255 Function $channel');
  }
  b
    ..writeln()
    ..writeln('58-channel mode')
    ..writeln('Channel Function DMX Value Functional Description');
  for (var channel = 1; channel <= 30; channel++) {
    b.writeln('$channel Control $channel 0-255 Function $channel');
  }
  b
    ..writeln('31 R1 LED Dimming 0-255 Red zone 1 brightness')
    ..writeln('32 G1 LED Dimming 0-255 Green zone 1 brightness')
    ..writeln('33 B1 LED Dimming 0-255 Blue zone 1 brightness')
    ..writeln('34 W1 LED Dimming 0-255 White zone 1 brightness')
    ..writeln('...... ...... ...... ......')
    ..writeln('55 R7 LED Dimming 0-255 Red zone 7 brightness')
    ..writeln('56 G7 LED Dimming 0-255 Green zone 7 brightness')
    ..writeln('57 B7 LED Dimming 0-255 Blue zone 7 brightness')
    ..writeln('58 W7 LED Dimming 0-255 White zone 7 brightness');
  return b.toString();
}
