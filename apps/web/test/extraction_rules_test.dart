@TestOn('vm')
library;

import 'dart:convert';
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

  test('parses an ADJ/Eliminator "<N>-CH MODE" DMX Traits table whose '
      'smaller mode is a reordered subset (Eliminator Furious Five RG)', () {
    // See _modeColumnTraitsTables in extraction_rules.dart for the layout:
    // blank cells rather than dashes where a mode lacks a function, position
    // numbers vertically centered in merged cells (mid-list, alone, or only
    // beside each other), "(cont'd from prev page)" continuations wrapped
    // across several lines, and an 11-channel mode that is not the first 11
    // channels of the 24-channel one. Before this grammar, every parser
    // missed the table and the fallback produced "Dimmer", "Light switch /
    // strobe" and 22 "Channel N" placeholders, with the 11-channel mode as
    // the first 11 of them.
    // A text-layer PDF arrives with every blank cell printed as "–"; a photo
    // or a scan arrives with the cells blank. Both must read the same table.
    final blankCells = _furiousFiveTraitsManual.replaceAll(
      RegExp(r'^–   |   –(?=   |$)', multiLine: true),
      '',
    );
    expect(blankCells, isNot(_furiousFiveTraitsManual));
    final fromBlank = fixtureFromManualText(blankCells, 'Furious Five RG.pdf');
    final result = fixtureFromManualText(
      _furiousFiveTraitsManual,
      'Furious Five RG.pdf',
    );
    expect(
      [for (final channel in fromBlank.fixture.channels) channel.toJson()],
      [for (final channel in result.fixture.channels) channel.toJson()],
    );
    final fixture = result.fixture;
    List<DmxChannel> channelsOf(String modeName) {
      final mode = fixture.modes.singleWhere((mode) => mode.name == modeName);
      return [
        for (final id in mode.channelIds)
          fixture.channels.singleWhere((channel) => channel.id == id),
      ];
    }

    String ranges(DmxChannel channel) => channel.ranges
        .map((range) => '${range.start}-${range.end} ${range.name}')
        .join(' | ');

    final full = channelsOf('24Ch');
    final simple = channelsOf('11Ch');
    expect(fixture.modes.map((mode) => mode.name), ['11Ch', '24Ch']);
    expect(full.map((channel) => channel.name), [
      'Master Dimmer',
      'UV Strobe',
      'UV Dimmer',
      'Left-side 4-in-1 LED Color',
      'Right-side 4-in-1 LED Color',
      '4-in-1 LED + UV Show Mode',
      '4-in-1 LED + UV Show Speed',
      'White LED Dimmer',
      'White LED Strobe',
      'White LED Show Mode',
      'White LED Auto Show Speed',
      'LED Spot Dimmer',
      'LED Spot Strobe',
      'Left LED Spot, Outboard Color',
      'Left LED Spot, Inboard Color',
      'Right LED Spot, Inboard Color',
      'Right LED Spot, Outboard Color',
      'LED Spot Show Mode',
      'Auto LED Spot Show Speed',
      'Red Laser',
      'Green Laser',
      'Laser Movement',
      'Laser Show Mode',
      'Auto Laser Show Speed',
    ]);
    expect(simple.map((channel) => channel.name), [
      '4-in-1 LED + UV Show Mode',
      '4-in-1 LED + UV Show Speed',
      '4-in-1 LED + UV Strobe',
      'White LED Show Mode',
      'White LED Auto Show Speed',
      'White LED Strobe',
      'LED Spot Show Mode',
      'Auto LED Spot Show Speed',
      'LED Spot Strobe',
      'Laser Show Mode',
      'Auto Laser Show Speed',
    ]);
    // Cut by a page break and rejoined by the position the halves share.
    expect(
      ranges(full[4]),
      '0-7 Off | 8-24 Red | 25-41 Green | 42-58 Blue | 59-75 White | 76-92 Yellow | 93-109 Magenta | 110-126 Pink | 127-143 Cyan | 144-160 Light Green | 161-177 Lavender | 178-194 Mauve | 195-211 Peach | 212-228 Light Magenta | 229-245 Ice Blue | 246-255 Light Pink',
    );
    expect(
      ranges(full[15]),
      '0-7 Off | 8-24 Red | 25-41 Green | 42-58 Blue | 59-75 White | 76-92 Red + Green | 93-109 Red + Blue | 110-126 Red + White | 127-143 Green + Blue | 144-160 Green + White | 161-177 Blue + White | 178-194 Red + Green + Blue | 195-211 Red + Green + White | 212-228 Red + Blue + White | 229-245 Green + Blue + White | 246-255 Red + Green + Blue + White',
    );
    // Descriptions that wrapped, with their value centered between the
    // halves - one of them also across a page break.
    expect(
      ranges(full[17]),
      '0-7 Off | 8-34 Both LED Spots, Single Color Full Display | 35-61 Both LED Spots, Single Color Half Display | 62-88 Both LED Spots, Contrasting Single Color Half Display | 89-115 Alternating LED Spots, Single Color Half Display | 116-142 Alternating LED Spots, Single Color Full Display | 143-160 Alternating LED Spots, Pinwheel | 161-178 Both LED Spots, Pinwheel | 179-187 Both LED Spots, Single/Dual/Triple/All Color Spin | 188-200 Both LED Spots, All Color Spin | 201-255 Sound Show',
    );
    expect(ranges(simple[6]), ranges(full[17]));
    // A one-range function names itself at the head of its only range.
    expect(ranges(full[0]), '0-255 0 to 100%');
    expect(ranges(simple[1]), '0-255 Slow to Fast');
    expect(
      ranges(full[21]),
      '0-10 Off | 11-120 Counter Clockwise, Fast to Slow | 121-134 Off | 135-245 Clockwise, Slow to Fast | 246-255 Off',
    );
    // The prose page after the table stays out of its last channel.
    expect(ranges(full[23]), '0-255 Slow to Fast');
    // The 11-channel mode's own strobe, which the 24-channel mode lacks;
    // "No strobe" is a steady setting, not a strobe range.
    expect(simple[2].kind, 'strobe');
    expect(simple[2].ranges.map((range) => range.safety), ['normal', 'strobe']);
    expect(full[1].ranges.map((range) => range.safety), ['normal', 'strobe']);
    // A laser's on/off control is not a color-mixing component.
    expect(full[19].kind, isNot('colorIntensity'));
    expect(full[20].kind, isNot('colorIntensity'));
    expect(
      fixture.channels
          .map((channel) => channel.kind)
          .toSet()
          .difference(schemaChannelKinds),
      isEmpty,
    );
    expect(
      result.questions.where((question) => question.contains('channel rows')),
      isEmpty,
    );
  });

  test('keeps page footers out of an ADJ "<N>-CH MODE" table', () {
    // A web address printed under each page number must not merge into the
    // next page's first function name, and the page number must not claim a
    // mode position ahead of the row that really holds it.
    final withFooters = _furiousFiveTraitsManual.replaceAllMapped(
      RegExp(r'^(1[5-9]|20)$', multiLine: true),
      (match) => '${match[1]}\nwww.eliminatorlighting.com',
    );
    expect(withFooters, isNot(_furiousFiveTraitsManual));
    final plain = fixtureFromManualText(
      _furiousFiveTraitsManual,
      'Furious Five RG.pdf',
    ).fixture;
    final footed = fixtureFromManualText(
      withFooters,
      'Furious Five RG.pdf',
    ).fixture;
    expect(
      [for (final channel in footed.channels) channel.toJson()],
      [for (final channel in plain.channels) channel.toJson()],
    );
    expect(
      footed.modes.map((mode) => mode.channelIds),
      plain.modes.map((mode) => mode.channelIds),
    );
  });

  List<DmxChannel> modeChannels(FixtureProject fixture, String modeName) {
    final mode = fixture.modes.singleWhere((mode) => mode.name == modeName);
    return [
      for (final id in mode.channelIds)
        fixture.channels.singleWhere((channel) => channel.id == id),
    ];
  }

  test('places blank-cell rows of an ADJ "<N> Ch" traits table by their '
      'printed column (Eliminator FLUX FX)', () {
    // Rows that only some personalities have: "11   –   –   000-255 Amber
    // All" is 24 Ch's alone, "–   11   11   000-255 Amber Intensity 1" is
    // 34 Ch's and 64 Ch's. Without the "–" cells both read "11 ...", and
    // continuing each column's count can't tell them apart.
    final fixture = fixtureFromManualText(
      _fluxFxTraitsManual,
      'FLUX FX.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), ['24Ch', '34Ch', '64Ch']);
    final small = modeChannels(fixture, '24Ch');
    final medium = modeChannels(fixture, '34Ch');
    final large = modeChannels(fixture, '64Ch');
    expect(small[10].name, 'Amber All');
    expect(medium[10].name, 'Amber Intensity 1');
    expect(large[10].name, 'Amber Intensity 1');
    expect(small[13].name, 'RGB Color Macro');
    expect(medium[19].name, 'RGB Background All Red');
    expect(large[19].name, 'RGB Background 1 red');
    expect(medium[26].name, 'Halo Strip is red');
    expect(large[41].name, 'Halo Strip 1 is red');
    for (final mode in [small, medium, large]) {
      expect(mode.last.name, 'Macro');
      expect(mode.last.ranges.length, 5);
      expect(
        mode.where((channel) => channel.name.startsWith('Channel ')),
        isEmpty,
      );
    }
  });

  test('fills in pixel blocks an ADJ traits table skips with a "…" row, and '
      'reads single DMX values (ADJ VIZI FX7)', () {
    final fixture = fixtureFromManualText(
      _viziFx7TraitsExcerpt,
      'VIZI FX7.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '31Ch',
      '55Ch',
      '57Ch',
      '60Ch',
      '237Ch',
    ]);
    // "Red 2".."Lime 2", "…", "Red 6".."Lime 6": pixels 3 to 5 come back.
    expect(modeChannels(fixture, '55Ch').sublist(12, 24).map((c) => c.name), [
      for (final pixel in [3, 4, 5])
        for (final color in ['Red', 'Green', 'Blue', 'Lime']) '$color $pixel',
    ]);
    final full = modeChannels(fixture, '237Ch');
    expect(full[50].name, 'Ring Red 3');
    expect(full[220].name, 'Ring Blue 59');
    expect(full[221].name, 'Ring Red 60');
    expect(modeChannels(fixture, '31Ch')[2].name, 'All Main Red');
    // "000   No Function" is a single value, not position 0.
    expect(modeChannels(fixture, '55Ch')[28].ranges.first.start, 0);
    expect(modeChannels(fixture, '55Ch')[28].ranges.first.end, 0);
    // Two name rows in one merged cell are one channel; "141   0.1 s" is a
    // single value, and the table's own stray "55   55" row is dropped.
    final dimming = modeChannels(fixture, '57Ch')[53];
    expect(dimming.name, 'Dim Modes / Dimming Speed');
    expect(
      dimming.ranges.where((range) => range.start == 141).single.name,
      '0.1 s',
    );
    expect(dimming.ranges.where((range) => range.name == '55'), isEmpty);
    expect(modeChannels(fixture, '31Ch')[27].name, 'Internal Progrms');
    expect(modeChannels(fixture, '60Ch')[55].name, 'Internal Progrms');
    expect(full[232].name, 'Internal Progrms');
  });

  test('keeps a channel whole across name rows and pages in an ADJ traits '
      'table (ADJ Protégé XL)', () {
    final fixture = fixtureFromManualText(
      _protegeXlTraitsExcerpt,
      'Protege XL.pdf',
    ).fixture;
    final full = modeChannels(fixture, '45Ch');
    expect(full.take(15).map((channel) => channel.name), [
      'Pan',
      'Pan Fine',
      'Tilt',
      'Tilt Fine',
      'Continuous Pan',
      'Cyan',
      'Cyan Fine',
      'Magenta',
      'Magenta Fine',
      'Yellow',
      'Yellow Fine',
      'CTO',
      'CTO Fine',
      'White Color Temp Presets',
      'Color Wheel',
    ]);
    expect(modeChannels(fixture, '36Ch')[1].fineOf, isNotNull);
    // Special Functions, then "LED Refresh Rate (Hz)", "Internal Programs"
    // and "CT Mode" name rows over three pages, the numbers beside only some
    // of them - one of those rows ending in its own value ("30   36   45
    // 237   6000").
    final special = full[44];
    expect(special.name, startsWith('Special Functions'));
    expect(modeChannels(fixture, '36Ch')[35].name, special.name);
    expect(modeChannels(fixture, '30Ch')[29].name, special.name);
    String at(int value) =>
        special.ranges.singleWhere((range) => range.start == value).name;
    expect(at(173), '900');
    expect(at(237), '6000');
    expect(at(242), 'Internal Program 1');
    expect(at(250), 'Enable CT Mode');
    final values = [...special.ranges]
      ..sort((a, b) => a.start.compareTo(b.start));
    expect(values.first.start, 0);
    expect(values.last.end, 255);
    for (var i = 1; i < values.length; i++) {
      expect(values[i].start, values[i - 1].end + 1, reason: values[i].name);
    }
  });

  test('reads an ADJ traits table whose header misprints one count on its '
      'first page (ADJ Encore LP12Z IP)', () {
    // Page one of the table reads "6Ch 9Ch 10Ch 12Ch 15Ch 16Ch", the next
    // two "... 18Ch": one table, an 18-channel personality. One-range rows
    // wrap their descriptions too ("Auto Programs Fade, minimum to maximum"
    // / "000 - 255" / "fade").
    final fixture = fixtureFromManualText(
      _encoreLp12zTraitsExcerpt,
      'Encore LP12Z IP.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '6Ch',
      '9Ch',
      '10Ch',
      '12Ch',
      '15Ch',
      '18Ch',
    ]);
    expect(modeChannels(fixture, '18Ch').skip(12).map((c) => c.name), [
      'Auto Programs',
      'Auto Programs Speed',
      'Auto Programs Fade',
      'Dim Mode',
      'Dim Curves',
      'Special Functions',
    ]);
    expect(modeChannels(fixture, '15Ch').skip(12).map((c) => c.name), [
      'Dim Mode',
      'Dim Curves',
      'Special Functions',
    ]);
    expect(modeChannels(fixture, '10Ch')[1].name, 'Red Fine');
    for (final mode in fixture.modes) {
      expect(
        modeChannels(
          fixture,
          mode.name,
        ).where((c) => c.name.startsWith('Channel ')),
        isEmpty,
      );
    }
  });

  test('reads a name that starts with a number, and a "..." pixel run, in an '
      'ADJ traits table (Eliminator Fantasy FX)', () {
    final fixture = fixtureFromManualText(
      _fantasyFxTraitsExcerpt,
      'Fantasy FX.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), ['7Ch', '16Ch', '152Ch']);
    // "64 Color Macros" is a name row, not the single DMX value 64.
    final macros = modeChannels(fixture, '16Ch')[11];
    expect(macros.name, '64 Color Macros');
    expect(macros.ranges.single.start, 0);
    expect(macros.ranges.single.end, 255);
    final pixels = modeChannels(fixture, '152Ch');
    expect(pixels[6].name, 'Background 1 Red');
    expect(pixels[9].name, 'Background 2 Red');
    expect(pixels[146].name, 'Background 47 Blue');
    expect(pixels[147].name, 'Background 48 Red');
    expect(modeChannels(fixture, '7Ch').map((c) => c.name), [
      'Main Red',
      'Main Green',
      'Main Blue',
      'Main White',
      'Background Red All',
      'Background Green All',
      'Background Blue All',
    ]);
  });

  test('reads lettered personalities, and keeps one misprinted position from '
      'resizing its mode, in an ADJ traits table (COB Cannon LP200X)', () {
    final result = fixtureFromManualText(
      _cobCannonTraitsExcerpt,
      'COB Cannon LP200X.pdf',
    );
    final fixture = result.fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '5Ch',
      '8Ch-A',
      '8Ch-B',
      '9Ch',
      '10Ch-A',
      '10Ch-B',
      '12Ch',
      '13Ch',
      '16Ch',
      '20Ch',
    ]);
    expect(modeChannels(fixture, '8Ch-B').take(5).map((c) => c.name), [
      'Color Macros',
      'Color Temperature',
      'Shutter, Strobe',
      'Dimmer (Intensity)',
      'Dimmer Fine 16-bit',
    ]);
    // The manual prints "166" for Auto Programs Speed in the 20Ch column,
    // between its 15 and 17: that position is left for the user to check
    // rather than stretching the mode to 166 channels. This page holds 16
    // of the mode's 20 rows; the rest are on the next.
    final wide = modeChannels(fixture, '20Ch');
    expect(wide, hasLength(20));
    expect(wide[14].name, 'Auto programs');
    expect(wide[15].name, 'Channel 16');
    expect(wide[16].name, 'Auto Programs Fade');
    expect(
      result.questions,
      contains(
        '20Ch: we read 16 of 20 channel rows. Check the highlighted controls.',
      ),
    );
    // A description printed on the line under its value row is that
    // value's, not the next function's name.
    expect(wide[10].name, 'Color Macros');
    expect(wide[10].ranges.single.name, '(See Color Macros)');
    expect(wide[11].name, 'Color Temperature');
  });

  test('reads spaced lettered personalities, and position numbers printed on '
      'a line of a description, in an ADJ traits table (Mirage Par H IP)', () {
    final fixture = fixtureFromManualText(
      _mirageParHTraitsExcerpt,
      'Mirage Par H IP.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '5Ch',
      '6Ch',
      '9Ch A',
      '9Ch B',
      '15Ch',
      '17Ch',
    ]);
    expect(modeChannels(fixture, '5Ch').map((c) => c.name), [
      'Color Temperature',
      'White Color Temperature Presets',
      'Shutter',
      'Dimmer',
      'Dimmer Fine',
    ]);
    expect(modeChannels(fixture, '9Ch B').take(7).map((c) => c.name), [
      'Colors Macros',
      'Color Temperature',
      'White Color Temperature Presets',
      'Shutter',
      'Dimmer',
      'Dimmer Fine',
      'Internal Programs',
    ]);
    // "2   –   9   3   9   9   White Color Temperature Presets," carries
    // the presets channel's numbers on the first line of its 23 - 99
    // description, not on a value.
    final presets = modeChannels(fixture, '17Ch')[8];
    expect(presets.name, 'White Color Temperature Presets');
    expect(
      presets.ranges.map((range) => (range.start, range.end, range.name)),
      [
        (0, 22, 'Open'),
        (
          23,
          99,
          'White Color Temperature Presets, refer to Color Temperature Chart',
        ),
        (100, 255, 'No Function'),
      ],
    );
  });

  test('reads counts printed over their units, and a dotted row that skips '
      'pixels, in an ADJ traits table (ElectraPix Bar 16)', () {
    final fixture = fixtureFromManualText(
      _electraPixBar16TraitsExcerpt,
      'ElectraPix Bar 16.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '5Ch',
      '6Ch',
      '7Ch',
      '9Ch',
      '12Ch',
      '13Ch',
      '22Ch',
      '24Ch',
      '96Ch',
      '99Ch',
      '114Ch',
    ]);
    // "..   ...   ...   0-255 ..." skips pixels 2 to 15, and the first
    // pixel is printed "Red1" where the last is "Red 16".
    final pixels = modeChannels(fixture, '96Ch');
    expect(pixels.where((c) => c.name.startsWith('Channel ')), isEmpty);
    expect(pixels[7].name, 'Green 2');
    expect(pixels[89].name, 'UV 15');
    expect(pixels[90].name, 'Red 16');
    expect(modeChannels(fixture, '99Ch').skip(96).map((c) => c.name), [
      'Background Red',
      'Background Green',
      'Background Blue',
    ]);
    // "RGBAL+UV Programs Speed : Slow to" / "0-255" / "Fast speed".
    expect(
      modeChannels(fixture, '13Ch')[8].name,
      'RGBAL+UV Programs Speed : Slow to Fast speed',
    );
  });

  test('reads fourteen stacked counts, a name broken by a hyphen on its '
      'position row, and a description wrapped after "0 to", in an ADJ '
      'traits table (Jolt Panel FX2)', () {
    final fixture = fixtureFromManualText(
      _joltPanelFx2TraitsExcerpt,
      'Jolt Panel FX2.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '6Ch',
      '9Ch',
      '13Ch',
      '18Ch',
      '20Ch',
      '36Ch',
      '41Ch',
      '43Ch',
      '51Ch',
      '81Ch',
      '83Ch',
      '126Ch',
      '141Ch',
      '143Ch',
    ]);
    for (final mode in fixture.modes) {
      expect(
        modeChannels(
          fixture,
          mode.name,
        ).where((c) => c.name.startsWith('Channel ')),
        isEmpty,
        reason: mode.name,
      );
    }
    final thirteen = modeChannels(fixture, '13Ch');
    expect(thirteen.map((c) => c.name), [
      'Outer Red',
      'Outer Green',
      'Outer Blue',
      'Inner White',
      'Outer Color Macros',
      'Dimmer',
      'Dimmer Fine',
      'Outer Strobe Effect',
      'Outer Strobe Rate',
      'Outer Strobe Duration',
      'Outer Program Macro',
      'Inner Program Macro',
      'In/Out Program',
    ]);
    expect(thirteen[1].ranges.single.name, '0 to 100%');
    // "Inner Program Macro" / "... 000-255" / "Speed", right after the
    // Inner Program Macro channel itself: one name wrapped around its value.
    expect(modeChannels(fixture, '18Ch').skip(16).map((c) => c.name), [
      'Inner Program Macro',
      'Inner Program Macro Speed',
    ]);
  });

  test('keeps names whole where they wrap around their values in an ADJ '
      'traits table (ElectraPix Par 7)', () {
    final fixture = fixtureFromManualText(
      _electraPixPar7TraitsExcerpt,
      'ElectraPix Par 7.pdf',
    ).fixture;
    final wide = modeChannels(fixture, '60Ch');
    expect(wide.where((c) => c.name.startsWith('Channel ')), isEmpty);
    // "RGB Background" / "Color Macros ," is one name above its value, not
    // a description of Background Blue; "White Color Temper -" / "ature
    // Presets" is one word; "RGBAL+UV Pro -" / "... 000-255 grams Speed ," /
    // "slow to fast" finishes its name on the value row; "RGB Background" /
    // "... 000-255 Program Fade , least" / "to most" does too.
    expect(wide.sublist(44, 58).map((c) => c.name), [
      'Background Green',
      'Background Blue',
      'RGB Background Color Macros',
      'Color Temperature',
      'White Color Temperature Presets',
      'Shutter, Strobe',
      'Dimmer (Intensity )',
      'Dimmer Fine (Intensity)',
      'RGBAL+UV Programs',
      'RGBAL+UV Programs Speed',
      'RGBAL+UV Programs Fade',
      'RGB Background Programs',
      'RGB Background Programs Speed',
      'RGB Background Program Fade',
    ]);
    expect(wide[46].ranges.single.name, 'see Color Macros section');
    // "2300–9900K Linear," / "0–100%" is a description wrapped at a comma.
    expect(wide[47].ranges.single.name, '2300–9900K Linear');
    expect(wide[57].ranges.single.name, 'least to most');
  });

  test('reads an ADJ traits table whose header ends in "FUNCTIONS" '
      '(ADJ Element Hex IP)', () {
    final fixture = fixtureFromManualText(
      _elementHexIpTraitsExcerpt,
      'Element Hex IP.pdf',
    ).fixture;
    expect(fixture.modes.map((mode) => mode.name), [
      '6Ch',
      '7Ch',
      '8Ch',
      '11Ch',
      '12Ch',
    ]);
    final twelve = modeChannels(fixture, '12Ch').map((c) => c.name);
    expect(twelve.take(9), [
      'RED',
      'GREEN',
      'BLUE',
      'WHITE',
      'AMBER',
      'UV',
      'MASTER DIMMER',
      'STROBING/SHUTTER',
      'PROGRAM SELECTION MODE',
    ]);
    // Channel 10 is PROGRAMS: four 0-255 tables, one per program mode,
    // under one merged "10" cell. Only the table beside the number is read,
    // a known gap left out of this test.
    expect(twelve.skip(10), [
      'PROGRAM SPEED/SOUND SENSITIVITY',
      'DIMMER CURVES',
    ]);
  });

  test('keeps a one-range name rule off a list of values in an ADJ traits '
      'table (Eliminator LP 8R)', () {
    final fixture = fixtureFromManualText(
      _lp8rTraitsExcerpt,
      'LP 8R.pdf',
    ).fixture;
    // "Auto Run" / "000-029 Empty , No Function" names a value, not the rest
    // of the function's name: the comma rule is for a single 0-255 value.
    expect(modeChannels(fixture, '3Ch').map((c) => c.name), [
      'Auto Run',
      'Color macro function',
      'Speed / Sound sensitivity',
    ]);
  });

  test('names the model the way the text layer spells it when OCR misread '
      'an image-only cover (ADJ Encore LP12Z IP)', () {
    // OCR read the cover's artwork as "AwAs", right above "User Manual", and
    // its title as "ENCORE LPIeZ IP"; page 4 thanks the reader for the
    // "Encore LP12Z IP".
    final fixture = fixtureFromManualText(
      _encoreLp12zCoverExcerpt,
      'Encore LP12Z IP.pdf',
    ).fixture;
    expect(fixture.model, 'Encore LP12Z IP');
    expect(fixture.manufacturer, 'ADJ');
  });

  test('respells an OCR-misread cover title from the text layer, and keeps '
      'one the text layer only spaces differently', () {
    // "HYDRO SPOT |" on the image cover; "The Hydro Spot 1 carries..." inside.
    expect(
      fixtureFromManualText(
        _hydroSpot1CoverExcerpt,
        'Hydro Spot 1.pdf',
      ).fixture.model,
      'Hydro Spot 1',
    );
    // "FUZE WASH Z350" on the cover is "FUZEWASH Z350" inside: the same
    // letters, so the cover's spelling stands.
    expect(
      fixtureFromManualText(
        _fuzeWashZ350CoverExcerpt,
        'Fuze Wash Z350.pdf',
      ).fixture.model,
      'FUZE WASH Z350',
    );
  });

  test('folds extraction-only channel kinds onto the fixture schema', () {
    // The Rust core rejects a kind outside schemas/fixture-v1.json's
    // ChannelKind enum as invalid JSON, which used to fail validation and
    // both exports for any fixture with a "... Mode" or CTC channel.
    final schema =
        jsonDecode(File('../../schemas/fixture-v1.json').readAsStringSync())
            as Map<String, Object?>;
    final channelKind =
        (schema[r'$defs']! as Map<String, Object?>)['ChannelKind']!
            as Map<String, Object?>;
    expect(schemaChannelKinds, (channelKind['enum']! as List).toSet());
    final show = DmxChannel(id: 'show', name: 'Show Mode', kind: 'mode');
    expect(show.kind, 'effect');
    expect(show.gdtfAttribute, 'Effects1');
    final ctc = DmxChannel(
      id: 'ctc',
      name: 'Color temperature',
      kind: 'colorTemperature',
    );
    expect(ctc.kind, 'generic');
    expect(ctc.gdtfAttribute, 'CTC');
    // A project saved before the fold reloads as an exportable one.
    expect(
      DmxChannel.fromJson({
        'id': 'show',
        'name': 'Show Mode',
        'kind': 'mode',
      }).kind,
      'effect',
    );
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

/// The Eliminator Furious Five RG manual's cover and its whole DMX Traits
/// table (pages 15-20), verbatim from this app's own PDF.js text pass
/// (manual_extractor.js's positionedText(), blank position cells printed as
/// "–" by table_columns.js) - including the per-page title lines, "CONTINUED
/// ON NEXT PAGE" footers and page numbers - followed by the first lines of
/// the prose page after the table.
const _furiousFiveTraitsManual = r'''
=== DMXTRACT PAGE 1 ===
Furious Five RG
User Manual
SKU#:   Furious Five RG
UPC#:   818651028096
ITF-14#:   10818651028093

=== DMXTRACT PAGE 15 ===
D M X T R A I T S
Eliminator Furious Five RG - DMX Traits
Software Version 2.0
CHANNEL
DMX VALUE DESCRIPTION
11-CH MODE 24-CH MODE
–   1   000 - 255   Master Dimmer , 0 to 100%
UV Strobe
–   2   000 - 007   No strobe
008 - 255   Strobe, slow to fast
UV Dimmer
–   3   000 - 007   Off
008 - 255   Dimmer, 0% to 100%
Left-side 4-in-1 LED Color
000 - 007   Off
008 - 024   Red
025 - 041   Green
042 - 058   Blue
059 - 075   White
076 - 092   Yellow
093 - 109   Magenta
–   4   110 - 126   Pink
127 - 143   Cyan
144 - 160   Light Green
161 - 177   Lavender
178 - 194   Mauve
195 - 211   Peach
212 - 228   Light Magenta
229 - 245   Ice Blue
246 - 255   Light Pink
Right-side 4-in-1 LED Color
000 - 007   Off
008 - 024   Red
–   5
025 - 041   Green
042 - 058   Blue
059 - 075   White
CONTINUED ON NEXT PAGE
15

=== DMXTRACT PAGE 16 ===
D M X T R A I T S
Eliminator Furious Five RG - DMX Traits
Software Version 2.0
CHANNEL
DMX VALUE DESCRIPTION
11-CH MODE 24-CH MODE
Right-side 4-in-1 LED Color ( cont’d from prev
page)
076 - 092   Yellow
093 - 109   Magenta
110 - 126   Pink
127 - 143   Cyan
5 ( cont’d from
144 - 160   Light Green
prev page )
161 - 177   Lavender
178 - 194   Mauve
195 - 211   Peach
212 - 228   Light Magenta
229 - 245   Ice Blue
246 - 255   Light Pink
4-in-1 LED + UV Show Mode
000 - 007   Off
008 - 045   Jump
046 - 064   Smooth Fade
065 - 083   Fast Pulse
1   6   084 - 102   Slow Pulse
103 - 121   Left/Right Jump
122 - 140   Flash
141 - 159   Left/Right Flash
160 - 200   Left/Right Fade
201 - 255   Sound Show
2   7   000 - 255   4-in-1 LED + UV Show Speed , Slow to Fast
4-in-1 LED + UV Strobe
3   –   000 - 007   Off
008 - 255   Strobe, Slow to Fast
–   8   000 - 255   White LED Dimmer , 0% to 100%
CONTINUED ON NEXT PAGE
16

=== DMXTRACT PAGE 17 ===
D M X T R A I T S
Eliminator Furious Five RG - DMX Traits
Software Version 2.0
CHANNEL
DMX VALUE DESCRIPTION
11-CH MODE 24-CH MODE
White LED Strobe
6   9   000 - 007   Off
008 - 255   Strobe, Slow to Fast
White LED Show Mode
000 - 007   Off
4   10
008 - 200   Auto Show
201 - 255   Sound Show
5   11   000 - 255   White LED Auto Show Speed , Slow to Fast
–   12   000 - 255   LED Spot Dimmer , 0% to 100%
LED Spot Strobe
9   13   000 - 007   Off
008 - 255   Strobe, Slow to Fast
Left LED Spot, Outboard Color
000 - 007   Off
008 - 024   Red
025 - 041   Green
042 - 058   Blue
059 - 075   White
076 - 092   Red + Green
093 - 109   Red + Blue
–   14   110 - 126   Red + White
127 - 143   Green + Blue
144 - 160   Green + White
161 - 177   Blue + White
178 - 194   Red + Green + Blue
195 - 211   Red + Green + White
212 - 228   Red + Blue + White
229 - 245   Green + Blue + White
246 - 255   Red + Green + Blue + White
CONTINUED ON NEXT PAGE
17

=== DMXTRACT PAGE 18 ===
D M X T R A I T S
Eliminator Furious Five RG - DMX Traits
Software Version 2.0
CHANNEL
DMX VALUE DESCRIPTION
11-CH MODE 24-CH MODE
Left LED Spot, Inboard Color
000 - 007   Off
008 - 024   Red
025 - 041   Green
042 - 058   Blue
059 - 075   White
076 - 092   Red + Green
093 - 109   Red + Blue
–   15   110 - 126   Red + White
127 - 143   Green + Blue
144 - 160   Green + White
161 - 177   Blue + White
178 - 194   Red + Green + Blue
195 - 211   Red + Green + White
212 - 228   Red + Blue + White
229 - 245   Green + Blue + White
246 - 255   Red + Green + Blue + White
Right LED Spot, Inboard Color
000 - 007   Off
008 - 024   Red
025 - 041   Green
042 - 058   Blue
059 - 075   White
–   16   076 - 092   Red + Green
093 - 109   Red + Blue
110 - 126   Red + White
127 - 143   Green + Blue
144 - 160   Green + White
161 - 177   Blue + White
178 - 194   Red + Green + Blue
CONTINUED ON NEXT PAGE
18

=== DMXTRACT PAGE 19 ===
D M X T R A I T S
Eliminator Furious Five RG - DMX Traits
Software Version 2.0
CHANNEL
DMX VALUE DESCRIPTION
11-CH MODE 24-CH MODE
Right LED Spot, Inboard Color (cont’d from
prev page)
16 (cont’d   195 - 211   Red + Green + White
from prev
212 - 228   Red + Blue + White
page)
229 - 245   Green + Blue + White
246 - 255   Red + Green + Blue + White
Right LED Spot, Outboard Color
000 - 007   Off
008 - 024   Red
025 - 041   Green
042 - 058   Blue
059 - 075   White
076 - 092   Red + Green
093 - 109   Red + Blue
–   17   110 - 126   Red + White
127 - 143   Green + Blue
144 - 160   Green + White
161 - 177   Blue + White
178 - 194   Red + Green + Blue
195 - 211   Red + Green + White
212 - 228   Red + Blue + White
229 - 245   Green + Blue + White
246 - 255   Red + Green + Blue + White
LED Spot Show Mode
000 - 007   Off
008 - 034   Both LED Spots, Single Color Full Display
035 - 061   Both LED Spots, Single Color Half Display
7   18
Both LED Spots, Contrasting Single Color Half
062 - 088
Display
089 - 115   Alternating LED Spots, Single Color Half Display
116 - 142   Alternating LED Spots, Single Color Full Display
CONTINUED ON NEXT PAGE
19

=== DMXTRACT PAGE 20 ===
D M X T R A I T S
Eliminator Furious Five RG - DMX Traits
Software Version 2.0
CHANNEL
DMX VALUE DESCRIPTION
11-CH MODE 24-CH MODE
LED Spot Show Mode (cont’d from prev page)
143 - 160   Alternating LED Spots, Pinwheel
18 (cont’d   161 - 178   Both LED Spots, Pinwheel
7 (cont’d from
from prev   Both LED Spots, Single/Dual/Triple/All Color
prev page)   179 - 187
page)   Spin
188 - 200   Both LED Spots, All Color Spin
201 - 255   Sound Show
8   19   000 - 255   Auto LED Spot Show Speed , Slow to Fast
Red Laser
–   20   000 - 127   Off
128 - 255   On
Green Laser
–   21   000 - 127   Off
128 - 255   On
Laser Movement
000 - 010   Off
011 - 120   Counter Clockwise, Fast to Slow
–   22
121 - 134   Off
135 - 245   Clockwise, Slow to Fast
246 - 255   Off
Laser Show Mode
000 - 007   Off
10   23
008 - 200   Auto
201 - 255   Sound Show
11   24   000 - 255   Auto Laser Show Speed , Slow to Fast
20

=== DMXTRACT PAGE 21 ===
I R R E M O T E O P E R A T I O N
0: Switches fixture to AUT1 Mode (Red/Green Laser Auto Show).
1-9 NUMBER PAD: Switches 4-in-1 LEDs to one of nine color presets. Note that the display color
''';

/// The Eliminator FLUX FX manual's whole DMX Traits table (pages 17-19),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _fluxFxTraitsManual = r'''
=== DMXTRACT PAGE 17 ===
D M X T R A I T S
CHANNEL MODE   DMX
FUNCTION
24 Ch 34 Ch 64 Ch VALUES
1   1   1   000-255 All Heads Tilt
All Heads Continuous Rotation
000-049 0~360 degrees enabled (speed from fast to slow)
2   2   2   050-151 Counterclockwise infinite rotation (speed from fast to slow)
152-153 Stop
154-255 Clockwise infinite rotation (speed from slow to fast)
3   3   3   000-255 Head 1 Tilt
Head 1 Continuous Rotation
000-049 0~360 degrees enabled (speed from fast to slow)
4   4   4   050-151 Counterclockwise infinite rotation (speed from fast to slow)
152-153 Stop
154-255 Clockwise infinite rotation (speed from slow to fast)
5   5   5   000-255 Head 2 Tilt
Head 2 Continuous Rotation
000-049 0~360 degrees enabled (speed from fast to slow)
6   6   6   050-151 Counterclockwise infinite rotation (speed from fast to slow)
152-153 Stop
154-255 Clockwise infinite rotation (speed from slow to fast)
7   7   7   000-255 Head 3 Tilt
Head 3 Continuous Rotation
000-049 0~360 degrees enabled (speed from fast to slow)
8   8   8   050-151 Counterclockwise infinite rotation (speed from fast to slow)
152-153 Stop
154-255 Clockwise infinite rotation (speed from slow to fast)
9   9   9   000-255 Master Dimmer
Amber Strobe
10   10   10   000-004 No Function
005-255 The flicker speed is from slow to fast (0.5HZ~25HZ)
11   –   –   000-255 Amber All
–   11   11   000-255 Amber Intensity 1
–   12   12   000-255 Amber Intensity 2
–   13   13   000-255 Amber Intensity 3
–   14   14   000-255 Amber Intensity 4
–   15   15   000-255 Amber Intensity 5
–   16   16   000-255 Amber Intensity 6
12   17   17   000-255 Amber Effect
13   18   18   000-255 Amber Effect Speed
14   –   –   000-255 RGB Color Macro
RGB Background Strobe
–   19   19   000-004 No Function
005-255 Strobe speed is from slow to fast (0.5HZ~25HZ)
–   20   –   000-255 RGB Background All Red
–   21   –   000-255 RGB Background All Green
–   22   –   000-255 RGB Background All Blue
17

=== DMXTRACT PAGE 18 ===
D M X T R A I T S
CHANNEL MODE   DMX
FUNCTION
24 Ch 34 Ch 64 Ch VALUES
–   –   20   000-255 RGB Background 1 red
–   –   21   000-255 RGB Background 1 green
–   –   22   000-255 RGB Background 1 blue
–   –   23   000-255 RGB Background 2 red
–   –   24   000-255 RGB Background 2 green
–   –   25   000-255 RGB Background 2 blue
–   –   26   000-255 RGB Background 3 red
–   –   27   000-255 RGB Background 3 green
–   –   28   000-255 RGB Background 3 blue
–   –   29   000-255 RGB Background 4 red
–   –   30   000-255 RGB Background 4 green
–   –   31   000-255 RGB Background 4 blue
–   –   32   000-255 RGB Background 5 red
–   –   33   000-255 RGB Background 5 green
–   –   34   000-255 RGB Background 5 blue
–   –   35   000-255 RGB Background 6 red
–   –   36   000-255 RGB Background 6 green
–   –   37   000-255 RGB Background 6 blue
15   23   38   000-255 RGB Background Effect
16   24   39   000-255 RGB Background Effect Speed
17   25   40   000-255 Background color for fill effect
18   26   41   000-255 RGB Background Color Intensity
19   –   –   000-255 Halo Strip Color Macro
–   27   –   000-255 Halo Strip is red
–   28   –   000-255 Halo Strip is green
–   29   –   000-255 Halo Strip is blue
–   –   42   000-255 Halo Strip 1 is red
–   –   43   000-255 Halo Strip 1 is green
–   –   44   000-255 Halo Strip 1 is blue
–   –   45   000-255 Halo Strip 2 is red
–   –   46   000-255 Halo Strip 2 is green
–   –   47   000-255 Halo Strip 2 is blue
–   –   48   000-255 Halo Strip 3 is red
–   –   49   000-255 Halo Strip 3 is green
–   –   50   000-255 Halo Strip 3 is blue
–   –   51   000-255 Halo Strip 4 is red
–   –   52   000-255 Halo Strip 4 is green
–   –   53   000-255 Halo Strip 4 is blue
–   –   54   000-255 Halo Strip 5 is red
–   –   55   000-255 Halo Strip 5 is green
–   –   56   000-255 Halo Strip 5 is blue
–   –   57   000-255 Halo Strip 6 is red
–   –   58   000-255 Halo Strip 6 is green
–   –   59   000-255 Halo Strip 6 is blue
18

=== DMXTRACT PAGE 19 ===
D M X T R A I T S
CHANNEL MODE   DMX
FUNCTION
24 Ch 34 Ch 64 Ch VALUES
20   30   60   000-255 Halo Strip Effect
21   31   61   000-255 Halo Strip Effect Speed
22   32   62   000-255 Halo Strip Background Color
23   33   63   000-255 Halo Strip Background Color Intensity
Macro
000-014 No Function
015-199 Auto mode
24   34   64
200-229 Sound active mode
230-240 The motor resets and remains reset for 3 seconds
241-255 No Function
19
''';

/// Three of the six DMX Traits pages of ADJ's VIZI FX7 manual (19, 21, 22),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _viziFx7TraitsExcerpt = r'''
=== DMXTRACT PAGE 19 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
31Ch   55Ch   57Ch   60Ch 237Ch VALUES
1   1   1   1   1   000-255 Pan , 0-540, 8-bit Pan
–   2   2   2   2   000-255 Pan Fine , 16-bit Pan
2   3   3   3   3   000-255 Tilt , 0-270, 8-bit Tilt
–   4   4   4   4   000-255 Tilt Fine , 16-bit Tilt
3   –   –   –   –   000-255 All Main Red , All Main Red
4   –   –   –   –   000-255 All Main Green , All Main Green
5   –   –   –   –   000-255 All Main Blue , All Main Blue
6   –   –   –   –   000-255 All Main Lime , All Main Lime
–   5   5   5   5   000-255 Red 1 , Red 1
–   6   6   6   6   000-255 Green 1 , Green 1
–   7   7   7   7   000-255 Blue 1 , Blue 1
–   8   8   8   8   000-255 Lime 1 , Lime 1
–   9   9   9   9   000-255 Red 2 , Red 2
–   10   10   10   10   000-255 Green 2 , Green 2
–   11   11   11   11   000-255 Blue 2 , Blue 2
–   12   12   12   12   000-255 Lime 2 , Lime 2
…   …   …   …   …   …   … , ...
–   25   25   25   25   000-255 Red 6 , Red 6
–   26   26   26   26   000-255 Green 6 , Green 6
–   27   27   27   27   000-255 Blue 6 , Blue 6
–   28   28   28   28   000-255 Lime 6 , Lime 6
CCT Presets
000   No Function
001-060 2700K
061-179 3000K
180-201 3200K
202-207 4000K
–   29   29   29   29
208-229 4500K
230-234 5000K
235-239 5600K
240-244 6500K
245-249 8000K
250-255 10000K
Color Macros
–   30   30   30   30   000   Off
001-255 64 Color Macros
RGBL Program
000-000 RGBL Color Chase Off (Reference Color Macro Chart)
7   31   31   31   31   001-100 RGBL Color Chase 1 Slow-Fast
101-200 RGBL Color Chase 2 Slow-Fast
201-255 RGBL Color Chase 3 Slow-Fast
RGBL Shutter
000-031 Shutter Closed (LEDs OFF)
032-063 Shutter OPEN (LEDs ON)
064-095 Strobe effect slow to fast
8   32   32   32   32   096-127 Shutter OPEN (LEDs ON)
128-159 Pulse effect in sequences
160-191 Shutter OPEN (LEDs ON)
192-223 Random strobe effect slow to fast
224-255 Shutter OPEN (LEDs ON)
9   33   33   33   33   000-255 RGBL Dimmer , 0-100% Dimmer
–   34   34   34   34   000-255 RGBL Dimmer Fine , 16 Bit Dimming
19

=== DMXTRACT PAGE 21 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
31Ch   55Ch   57Ch   60Ch 237Ch VALUES
19   45   45   45   –   000-255 All Ring Red , All Ring Red
20   46   46   46   –   000-255 All Ring Green , All Ring Green
21   47   47   47   –   000-255 All Ring Blue , All Ring Blue
–   –   –   –   45   000-255 Ring Red 1 , Ring Red 1
–   –   –   –   46   000-255 Ring Green 1 , Ring Green 1
–   –   –   –   47   000-255 Ring Blue 1 , Ring Blue 1
–   –   –   –   48   000-255 Ring Red 2 , Ring Red 2
–   –   –   –   49   000-255 Ring Green 2 , Ring Green 2
–   –   –   –   50   000-255 Ring Blue 2 , Ring Blue 2
…   …   …   …   …   …   …
–   –   –   –   222   000-255 Ring Red 60 , Ring Red 60
–   –   –   –   223   000-255 Ring Green 60 , Ring Green 60
–   –   –   –   224   000-255 Ring Blue 60 , Ring Blue 60
Ring FX
000-015 FX Effect close
016-035 FX single led effect
036-055 FX 3pcs leds effect
056-075 FX 6pcs leds effect
076-095 FX 12pcs leds effect
096-115 FX 3pcs leds-4 modules effect
22   48   48   48   225
116-135 FX 6pcs leds-4 modules effect
136-155 FX 4 modules effect
156-175 FX loop fill effect
176-195 RGB 3 colors rainbow effect
196-215 RGB 3 colors effect
216-235 FX rainbow effect
236-255 FX segment effect
23   49   49   49   226   000-255 Ring FX Speed , FX Speed
Ring Shutter
000-031 Shutter Closed (LEDs OFF)
032-063 Shutter OPEN (LEDs ON)
064-095 Strobe effect slow to fast
24   50   50   50   227   096-127 Shutter OPEN (LEDs ON)
128-159 Pulse effect in sequences
160-191 Shutter OPEN (LEDs ON)
192-223 Random strobe effect slow to fast
224-255 Shutter OPEN (LEDs ON)
25   51   51   51   228   000-255 Ring Dimmer , RGB Ring Dimmer
26   52   52   52   229   000-255 Zoom , Min to Max (Narrow to Wide)
Rotation Effect
000-000 Rotation Effect Off
001-127 Rotation Index
27   53   53   53   230
128-190 CW Fast to Slow
191-192 Stop
193-255 CCW Slow to Fast
21

=== DMXTRACT PAGE 22 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
31Ch   55Ch   57Ch   60Ch 237Ch VALUES
Dim Modes
000-020 Default to Unit Setting
021-040 Standard
041-060 Stage
061-080 TV
081-100 Architectural
101-120 Theatre
121-140 Stage 2
Dimming Speed
141   0.1 s
142   0.2 s
143   0.3 s
144   0.4 s
145   0.5 s
146   0.6 s
–   –   54   54   231
147   0.7 s
148   0.8 s
149   0.9 s
150   1 s
151   1.5 s
152   2 s
153   3 s
154   4 s
155   5 s
156   6 s
157   7 s
158   8 s
159   9 s
160   10 s
55   55
Dim Curves
000-020 Square
021-040 Linear
–   –   55   55   232
041-060 Inv. Squa
061-080 S. Curve
081-255 No Function
Internal Progrms
000-009 No Function
010-019 Program 1
020-029 Program 2
030-039 Program 3
28   –   –   56   233   040-049 Program 4
050-059 Program 5
060-069 Program 6
070-079 Program 7
080-089 Program 8
90-255 No Function
29   –   –   57   234   000-255 Internal Programs Speed , Slow → Fast
30   –   –   58   235   000-255 Internal Programs Fade , Min → Max
31   54   56   59   236   000-255 Pan/Tilt Speed , Fast → slow
22
''';

/// Five of the nine DMX Traits pages of ADJ's Protégé XL manual (32, 37-40),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _protegeXlTraitsExcerpt = r'''
=== DMXTRACT PAGE 32 ===
D M X T R A I T S
MODE / CHANNELS
VALUES   FUNCTION
30ch   36ch   45ch
Pan
1   1   1
000 - 255   Pan Movement, 540/630
Pan Fine
–   2   2
000 - 255   Pan Fine Adjustment
Tilt
2   3   3
000 - 255   Tilt Movement, 270
Tilt Fine
–   4   4
000 - 255   Tilt Fine Adjustment
Continuous Pan
000 - 127   No Function
3   5   5   128 - 190   Clockwise Rotation, slow to fast
191 - 192   Stop
193 - 255   Counter-clockwise Rotation, fast to slow
Cyan
4   6   6
000 - 255   0% to 100%
Cyan Fine
–   –   7
000 - 255   0% to 100%
Magenta
5   7   8
000 - 255   0% to 100%
Magenta Fine
–   –   9
000 - 255   0% to 100%
Yellow
6   8   10
000 - 255   0% to 100%
Yellow Fine
–   –   11
000 - 255   0% to 100%
CTO
7   9   12
000 - 255   0% to 100%
CTO Fine
–   –   13
000 - 255   0% to 100%
White Color Temp Presets
000 - 023   Standard (7500K)
8   10   14
024 - 071   See WCT Preset Chart
072 - 255   7500K
Color Wheel
000 - 008   Open
009 - 017   Open / Red
018 - 026   Red
9   11   15   027 - 035   Red / Blue
036 - 044   Blue
045 - 053   Blue / Green
054 - 062   Green
063 - 071   Green / Orange
32

=== DMXTRACT PAGE 37 ===
D M X T R A I T S
MODE / CHANNELS
VALUES   FUNCTION
30ch   36ch   45ch
Zoom
22   27   35
000 - 255   Narrow to Wide
Zoom Fine
–   –   36
000 - 255   Narrow to Wide, 16-bit
Medium Frost
23   28   37
000 - 255   0% to 100%
Heavy Frost
24   29   38
000 - 255   0% to 100%
Animation
000 - 019   No Function
020 - 127   Enter in Proportion
25   30   39
128 - 170   All on - All in - All out, fast to slow
171 - 213   Half open - Full access - Half open, fast to slow
214 - 255   Half open - All out - Half open, fast to slow
Animation Rotation
000   No Function
26   31   40   001 - 127   Clockwise, fast to slow
128   Stop
129 - 255   Counter-clockwise, slow to fast
Dimmer Mode
000 - 020   Default to Unit Setting
021 - 040   Standard
041 - 060   Stage
061 - 080   TV
27   32   41
081 - 100   Architectural
101 - 120   Theater
121 - 140   Stage 2
141 - 160   Dim Speed, fast to slow (0.1s - 10s)
161 - 255   Default to Unit Setting
Dim Curves
000 - 020   No Function
021 - 040   Linear
–   33   42   041 - 060   Square
061 - 080   Inv. Squa
081 - 100   S. Curve
101 - 255   No Function
CMY and Color Macro Speed
28   34   43
000 - 255   Maximum to minimum
37

=== DMXTRACT PAGE 38 ===
D M X T R A I T S
MODE / CHANNELS
VALUES   FUNCTION
30ch   36ch   45ch
Pan/Tilt Speed
000 - 225   Pan/Tilt, fast to slow
29   35   44   226 - 235   Blackout by movement
236 - 245   Blackout by all wheel changing
246 - 255   No Function
Special Functions
000 - 029   No Function
030 - 039   Fan Control - Mute (hold 3s)
040 - 049   Fan Control - Low (hold 3s)
050 - 059   Fan Control - High (hold 3s)
060 - 069   Fan Control - Auto (hold 3s)
070 - 074   All Motor Reset
075 - 079   Pan/Tilt Reset
080 - 084   CMY Reset
085 - 089   No Function
090 - 094   Effect Reset 1 (Color, Gobo, Animation)
095 - 099   Effect Reset 2 (Prism, Frost, Focus, Zoom)
100 - 142   No Function
143 - 144   Pan/Tilt Speed Standard (hold 3s)
145 - 146   Pan/Tilt Speed Fast (hold 3s)
147 - 148   No Function
149 - 150   Aria On (hold 3s)
151 - 152   Aria Off (hold 3s)
30   36   45
153 - 154   Hibernation Enable (hold 3s)
155 - 156   Hibernation Off (hold 3s)
157 - 158   Display Backlight On (hold 3s)
159 - 160   Display Backlight Off (hold 3s)
161 - 164   No Function
165 - 166   Invert Pan On (hold 3s)
167 - 168   Invert Pan Off (hold 3s)
169 - 170   Invert Tilt On (hold 3s)
171 - 172   Invert Tilt Off (hold 3s)
LED Refresh Rate (Hz)
173   900
174   910
175   920
176   930
177   940
178   950
179   960
180   970
38

=== DMXTRACT PAGE 39 ===
D M X T R A I T S
MODE / CHANNELS
VALUES   FUNCTION
30ch   36ch   45ch
LED Refresh Rate (Hz) (continued)
181   980
182   990
183   1000
184   1010
185   1020
186   1030
187   1040
188   1050
189   1060
190   1070
191   1080
192   1090
193   1100
194   1110
195   1120
196   1130
197   1140
198   1150
199   1160
200   1170
30   36   45
201   1180
202   1190
203   1200
204   1210
205   1220
206   1230
207   1240
208   1250
209   1260
210   1270
211   1280
212   1290
213   1300
214   1310
215   1320
216   1330
217   1340
218   1350
219   1360
220   1370
221   1380
39

=== DMXTRACT PAGE 40 ===
D M X T R A I T S
MODE / CHANNELS
VALUES   FUNCTION
30ch   36ch   45ch
LED Refresh Rate (Hz) (continued)
222   1390
223   1400
224   1410
225   1420
226   1430
227   1440
228   1450
229   1460
230   1470
231   1480
232   1490
233   1500
234   2500
235   4000
236   5000
30   36   45   237   6000
238   10,000
239   15,000
240   20,000
241   25,000
Internal Programs
242   Internal Program 1
243   Internal Program 2
244   Internal Program 3
245   Internal Program 4
246   Internal Program 5
247   Internal Program 6
248   Internal Program 7
249   Internal Programs Off
CT Mode
250 - 252   Enable CT Mode
253 - 255   Disable CT Mode
40
''';

/// The three DMX Traits pages of ADJ's Encore LP12Z IP manual, verbatim from
/// this app's PDF.js text pass with blank cells as "–".
const _encoreLp12zTraitsExcerpt = r'''
=== DMXTRACT PAGE 27 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
6Ch 9Ch 10Ch 12Ch 15Ch 16Ch VALUES
1   1   1   1   1   1   000 - 255 Red, 0% to 100%
–   –   2   –   –   –   000 - 255 Red Fine
2   2   3   2   2   2   000 - 255 Green, 0% to 100%
–   –   4   –   –   –   000 - 255 Green Fine
3   3   5   3   3   3   000 - 255 Blue, 0% to 100%
–   –   6   –   –   –   000 - 255 Blue Fine
4   4   7   4   4   4   000 - 255 Lime, 0% to 100%
–   –   8   –   –   –   000 - 255 Lime Fine
Color Macros, see Color Macros Chart section
–   –   –   5   5   5   000 - 255
of this manual
–   –   –   6   6   6   000 - 255 Color Temperature, 2700K - 7000K Linear
Color Temperature Macros
000   Off
001 - 054 2700K
–   –   –   7   7   7   055 - 109 3200K
110 - 164 4000K
165 - 219 5600K
220 - 255 6500K
Shutter, Strobe
000 - 031 LEDs Off
032 - 063 LEDs On
064 - 095 Strobe Effect, slow to fast
–   5   –   8   8   8   096 - 127 LEDs On
128 - 159 Pulse Effect in Sequences
160 - 191 LEDs On
192 - 223 Random Strobe Effect, slow to fast
224 - 255 LEDs On
–   6   –   9   9   9   000 - 255 Dimmer Intensity, 0% to 100%
–   7   –   10   10   10   000 - 255 Dimmer Fine
Zoom Linear, minimum to maximum beam
5   8   9   11   11   11   000 - 255
angle
Zoom Presets
000 - 020 Normal (5 ° )
021 - 040 Very Narrow Spot (6 ° )
6   9   10   12   12   12   041 - 060 Narrow (10 ° )
061 - 080 Medium Flood (30 ° )
081 - 100 Wide Flood (40 ° )
101 - 255 Very Wide Flood (50 ° )
27

=== DMXTRACT PAGE 28 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
6Ch 9Ch 10Ch 12Ch 15Ch 18Ch VALUES
Auto Programs
000 - 031 Off
032 - 063 Auto Program 1
064 - 095 Auto Program 2
–   –   –   –   –   13   096 - 127 Auto Program 3
128 - 159 Auto Program 4
160 - 191 Auto Program 5
192 - 223 Auto Program 6
224 - 255 Auto Program 7
–   –   –   –   –   14   000 - 255 Auto Programs Speed, slow to fast
Auto Programs Fade, minimum to maximum
–   –   –   –   –   15   000 - 255
fade
Dim Mode
000 - 020 Default to unit setting
021 - 040 Standard
041 - 060 Stage
061 - 080 TV
–   –   –   –   13   16
081 - 100 Architectural
101 - 120 Theatre
121 - 140 Stage 2
141 - 160 Dim Speed, fast to slow (0.1s - 10s)
161 - 255 Default to unit setting
Dim Curves
000 - 020 Square
021 - 040 Linear
–   –   –   –   14   17
041 - 060 Inv Squa
061 - 080 S Curve
081 - 255 No function
Special Functions
000 - 015 Default to unit setting
016 - 030 900 Hz
031 - 045 1000 Hz
046 - 060 1100 Hz
–   –   –   –   15   18   061 - 075 1200 Hz
076 - 090 1300 Hz
091 - 105 1400 Hz
106 - 120 1500 Hz
121 - 135 2500 Hz
136 - 150 4000 Hz
28

=== DMXTRACT PAGE 29 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
6Ch 9Ch 10Ch 12Ch 15Ch 18Ch VALUES
Special Functions (continued)
151 - 165 5000 Hz
166 - 180 10000 Hz
181 - 195 15000 Hz
196 - 210 20000 Hz
–   –   –   –   15   18
211 - 225 25000 Hz
226 - 229 Enable Zoom Mode 1 (hold 3s)
230 - 233 Enable Zoom Mode 2 (hold 3s)
234 - 238 Zoom Reset
239 - 255 No function
29
''';

/// Two of the seven DMX Traits pages of the Eliminator Fantasy FX manual (18,
/// 19), verbatim from this app's PDF.js text pass with blank cells as "–".
const _fantasyFxTraitsExcerpt = r'''
=== DMXTRACT PAGE 18 ===
D M X T R A I T S
Features subject to change without notice
MODE/CHANNELS
VALUES   FUNCTION
7ch   16ch 152ch
Main Red
1   1   1
000 - 255   0% - 100%
Main Green
2   2   2
000 - 255   0% - 100%
Main Blue
3   3   3
000 - 255   0% - 100%
Main White
4   4   4
000 - 255   0% - 100%
Main Shutter
000 - 031   Shutter Closed (LEDs Off)
032 - 063   Shutter Open (LEDs On)
064 - 095   Strobe Effect, slow to fast
–   5   5   096 - 127   Shutter Open (LEDs On)
128 - 159   Pulse Effect in Sequences
160 - 191   Shutter Open (LEDs On)
192 - 223   Random Strobe Effect, slow to fast
224 - 255   Shutter Open (LEDs On)
Main Dimmer
–   6   6
000 - 255   0% - 100%
Background Red All
5   7   –
000 - 255   0% - 100%
Background Green All
6   8   –
000 - 255   0% - 100%
Background Blue All
7   9   –
000 - 255   0% - 100%
Background 1 Red
–   –   7
000 - 255   0% - 100%
Background 1 Green
–   –   8
000 - 255   0% - 100%
Background 1 Blue
–   –   9
000 - 255   0% - 100%
...   ...   ...   ...   ...
Background 48 Red
–   –   148
000 - 255   0% - 100%
Background 48 Green
–   –   149
000 - 255   0% - 100%
18

=== DMXTRACT PAGE 19 ===
D M X T R A I T S
Features subject to change without notice
MODE/CHANNELS
VALUES   FUNCTION
7ch   16ch 152ch
Background 48 Blue
–   –   150
000 - 255   0% - 100%
Background Shutter
000 - 031   Shutter Closed (LEDs Off)
032 - 063   Shutter Open (LEDs On)
064 - 095   Strobe Effect, slow to fast
–   10   151   096 - 127   Shutter Open (LEDs On)
128 - 159   Pulse Effect in Sequences
160 - 191   Shutter Open (LEDs On)
192 - 223   Random Strobe Effect, slow to fast
224 - 255   Shutter Open (LEDs On)
Background Dimmer
–   11   152
000 - 255   0% - 100%
64 Color Macros
–   12   –
000 - 255   See Color Macros Chart
Inner Programs
000 - 005   Program 0
006 - 010   Program 1
011 - 015   Program 2
016 - 021   Program 3
022 - 026   Program 4
027 - 031   Program 5
032 - 037   Program 6
038 - 042   Program 7
043 - 047   Program 8
–   13   –   048 - 053   Program 9
054 - 058   Program 10
059 - 063   Program 11
064 - 069   Program 12
070 - 074   Program 13
075 - 079   Program 14
080 - 085   Program 15
086 - 090   Program 16
091 - 095   Program 17
096 - 101   Program 18
102 - 106   Program 19
19
''';

/// The first DMX Traits page of the ADJ COB Cannon LP200X manual (21),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _cobCannonTraitsExcerpt = r'''
=== DMXTRACT PAGE 21 ===
D M X T R A I T S
DMX
5Ch 8Ch-A 8Ch-B 9Ch 10Ch-A 10Ch-B 12Ch 13Ch 16Ch 20Ch   FUNCTION
VALUES
Red
1   1   –   1   1   1   1   1   1   1   0-255
0~100%
–   –   –   –   2   –   –   –   –   2   0-255 Red Fine 16-bit
Green
2   2   –   2   3   2   2   2   2   3   0-255
0~100%
–   –   –   –   4   –   –   –   –   4   0-255 Green Fine 16-bit
Blue
3   3   –   3   5   3   3   3   3   5   0-255
0~100%
–   –   –   –   6   –   –   –   –   6   0-255 Blue 1 Fine 16-bit
Amber
4   4   –   4   7   4   4   4   4   7   0-255
1~100%
–   –   –   –   8   –   –   –   –   8   0-255 Amber Fine 16-bit
Lime
5   5   –   5   9   5   5   5   5   9   0-255
0~100%
–   –   –   –   10   –   –   –   –   10   0-255 Lime Fine 16-bit
Color Macros
–   –   1   –   –   6   6   6   6   11   0-255
(See Color Macros)
Color Temperature
–   –   2   6   –   7   –   7   7   12   0-255
2300-9900K Linear , 0~100%
Shutter, Strobe
0-31 LEDs Off
32-63 LEDs On
64-95 Strobe effect, slow to fast
–   6   3   7   –   8   7   8   8   13   96-127 LEDs On
128-159 Pulse effect in sequences
160-191 LEDs On
192-223 Random strobe effect, slow to fast
224-255 LEDs On
Dimmer (Intensity)
–   7   4   8   –   9   8   9   9   14   0-255
Intensity, 0 to 100%
–   8   5   9   –   10   9   10   10   –   0-255 Dimmer Fine 16-bit
Auto programs:
0-10 Off
11-26 Auto Program 1
27-43 Auto Program 2
44-60 Auto Program 3
61-76 Auto Program 4
77-93 Auto Program 5
94-110 Auto Program 6
–   –   –   –   –   –   10   –   11   15
111-126 Auto Program 7
127-143 Auto Program 8
144-160 Auto Program 9
161-176 Auto Program 10
177-193 Auto Program 11
194-210 Auto Program 12
211-226 Auto Program 13
227-255 No Function
Auto Programs Speed:
–   –   –   –   –   –   11   –   12   166   0-255
Slow to Fast speed
Auto Programs Fade:
–   –   –   –   –   –   12   –   13   17   0-255
Less to More
–   –   –   –   –   –   –   21   –   –
''';

/// The first DMX Traits page of the ADJ Mirage Par H IP manual (27), verbatim
/// from this app's PDF.js text pass with blank cells as "–".
const _mirageParHTraitsExcerpt = r'''
=== DMXTRACT PAGE 27 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
5Ch   6Ch   9Ch A 9Ch B   15 Ch   17 Ch VALUES
Red
–   1   1   –   1   1
0 - 255 0 - 100%
Green
–   2   2   –   2   2
0 - 255 0 - 100%
Blue
–   3   3   –   3   3
0 - 255 0 - 100%
Amber
–   4   4   –   4   4
0 - 255 0 - 100%
Lime
–   5   5   –   5   5
0 - 255 0 - 100%
UV
–   6   6   –   6   6
0 - 255 0 - 100%
Colors Macros
–   –   7   1   7   7
0 - 255 Refer to Color Macros Chart
Color Temperature
1   –   8   2   8   8
0 - 255 2300K - 9900K Linear
White Color Temperature Presets
0 - 22 Open
2   –   9   3   9   9   White Color Temperature Presets,
23 - 99
refer to Color Temperature Chart
100 - 255 No Function
Shutter
0 - 31 LEDs Off
32 - 63 LEDs On
64 - 95 Strobe effect, slow to fast
3   –   –   4   10   10   96 - 127 LEDs On
128 - 159 Pulse Effect in sequences
160 - 191 LEDs On
192 - 223 Random Strobe Effect, slow to fast
224 - 255 LEDs On
Dimmer
4   –   –   5   11   11
0 - 255 Intensity, 0 - 100%
Dimmer Fine
5   –   –   6   12   12
0 - 255 Dimmer fine adjustment
Internal Programs
0 - 10 Off
11 - 26 Auto Program 1
27 - 43 Auto Program 2
44 - 60 Auto Program 3
61 - 76 Auto Program 4
77 - 93 Auto Program 5
94 - 110 Auto Program 6
–   –   –   7   13   13
111 - 126 Auto Program 7
127 - 143 Auto Program 8
144 - 160 Auto Program 9
161 - 176 Auto Program 10
177 - 193 Auto Program 11
194 - 210 Auto Program 12
211 - 226 Auto Program 13
227 - 255 No Function
–   –   –   –   –   27
''';

/// Two of the DMX Traits pages of the ADJ ElectraPix Bar 16 manual (33, 34),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _electraPixBar16TraitsExcerpt = r'''
=== DMXTRACT PAGE 33 ===
D M X T R A I T S
CHANNEL
DMX
5   6   7   9   12 13 22 24 96 99 114   FUNCTION
VALUES
CH CH CH CH CH CH CH CH CH CH CH
–   1   1   1   1   –   1   1   –   –   –   0-255 All Red , 0~100%
–   2   2   2   2   –   2   2   –   –   –   0-255 All Green , 0~100%
–   3   3   3   3   –   3   3   –   –   –   0-255 All Blue , 0~100%
–   4   4   4   4   –   4   4   –   –   –   0-255 All Amber , 0~100%
–   5   5   5   5   –   5   5   –   –   –   0-255 All Lime , 0~100%
–   6   6   6   6   –   6   6   –   –   –   0-255 All UV , 0~100%
–   –   –   –   –   –   –   –   1   1   1   0-255 Red1 , 0~100%
–   –   –   –   –   –   –   –   2   2   2   0-255 Green 1 , 0~100%
–   –   –   –   –   –   –   –   3   3   3   0-255 Blue 1 , 0~100%
–   –   –   –   –   –   –   –   4   4   4   0-255 Amber 1 , 0~100%
–   –   –   –   –   –   –   –   5   5   5   0-255 Lime 1 , 0~100%
–   –   –   –   –   –   –   –   6   6   6   0-255 UV 1 , 0~100%
..   ...   ...   0-255 ...
–   –   –   –   –   –   –   –   91   91   91   0-255 Red 16 , 0~100%
–   –   –   –   –   –   –   –   92   92   92   0-255 Green 16 , 0~100%
–   –   –   –   –   –   –   –   93   93   93   0-255 Blue 16 , 0~100%
–   –   –   –   –   –   –   –   94   94   94   0-255 Amber 16 , 0~100%
–   –   –   –   –   –   –   –   95   95   95   0-255 Lime 16 , 0~100%
–   –   –   –   –   –   –   –   96   96   96   0-255 UV 16 , 0~100%
–   –   –   –   –   1   7   7   –   –   97   0-255 RGBAL+UV Color Macros
–   –   –   7   7   –   8   8   –   97   98   0-255 Background Red , 0~100%
–   –   –   8   8   –   9   9   –   98   99   0-255 Background Green , 0~100%
–   –   –   9   9   –   10   10   –   99   100   0-255 Background Blue , 0~100%
–   –   –   –   –   2   11   11   –   –   101   0-255 RGB Background Color Macros
Color Temperature 2300-9900K
1   –   –   –   10   3   12   12   –   –   102   0-255
Linear , 0~100%
White Color Temperature Presets
0-22 Open
2   –   –   –   –   4   13   13   –   –   103
23-99 See WCT Preset Chart
100-255 No Function
Shutter, Strobe
0-31 Led’s Off
32-63 Led’s On
64-95 Strobe effect slow to fast
3   –   –   –   11   5   14   14   –   –   104   96-127 Led’s On
128-159 Pulse-effect in sequences
160-191 Led’s On
192-223 Random strobe effect slow to fast
224-255 Led’s On
4   –   7   –   12   6   15   15   –   –   105   0-255 Dimmer (Intensity) , Intensity 0~100%
5   –   –   –   –   7   16   16   –   –   106   0-255 Dimmer Fine (Intensity)
–   –   –   –   –   –   –   –   –   33   –


=== DMXTRACT PAGE 34 ===
D M X T R A I T S
CHANNEL
DMX
5   6   7   9   12 13 22 24 96 99 114   FUNCTION
VALUES
CH CH CH CH CH CH CH CH CH CH CH
RGBAL+UV programs:
0-10 Off
11-26 Auto Program 1
27-43 Auto Program 2
44-60 Auto Program 3
61-76 Auto Program 4
77-93 Auto Program 5
94-110 Auto Program 6
–   –   –   –   –   8   17   17   –   –   107
111-126 Auto Program 7
127-143 Auto Program 8
144-160 Auto Program 9
161-176 Auto Program 10
177-193 Auto Program 11
194-210 Auto Program 12
211-226 Auto Program 13
227-255 No Function
RGBAL+UV Programs Speed : Slow to
–   –   –   –   –   9   18   18   –   –   108   0-255
Fast speed
RGBAL+UV Programs Fade : Less to
–   –   –   –   –   10   19   19   –   –   109   0-255
More
RGB Background Programs:
0-10 Off
11-26 Auto Program 1
27-43 Auto Program 2
44-60 Auto Program 3
61-76 Auto Program 4
77-93 Auto Program 5
94-110 Auto Program 6
–   –   –   –   –   11   20   20   –   –   110
111-126 Auto Program 7
127-143 Auto Program 8
144-160 Auto Program 9
161-176 Auto Program 10
177-193 Auto Program 11
194-210 Auto Program 12
211-226 Auto Program 13
227-255 No Function
RGB Background Programs Speed : Slow
–   –   –   –   –   12   21   21   –   –   111   0-255
to Fast speed
RGB Background Programs Fade : Less
–   –   –   –   –   13   22   22   –   –   112   0-255
to More
–   –   –   –   –   –   –   –   –   34   –
''';

/// The six DMX Traits pages of the ADJ Jolt Panel FX2 manual (21-26),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _joltPanelFx2TraitsExcerpt = r'''
=== DMXTRACT PAGE 21 ===
D M X T R A I T S
CHANNEL
DMX
6   9   13 18 20 36 41 43 51 81 83 126 141 143   FUNCTION
VALUES
CH CH CH CH CH CH CH CH CH CH CH CH CH CH
1   1   1   1   1   –   –   –   –   –   –   –   –   –   000-255 Outer Red, 0 to 100%
Outer Green, 0 to
2   2   2   2   2   –   –   –   –   –   –   –   –   –   000-255
100%
3   3   3   3   3   –   –   –   –   –   –   –   –   –   000-255 Outer Blue, 0 to 100%
Inner White, 0 to
4   4   4   –   –   –   –   –   –   –   –   –   –   –   000-255
100%
5   5   6   –   –   –   –   –   –   –   –   –   –   –   000-255 Dimmer, 0 to 100%
Dimmer Fine, 0 to
6   6   7   –   –   –   –   –   –   –   –   –   –   –   000-255
100%
Strobe Effect
000-002 Open
003-005 Strobe
006-050 Ramp up
–   7   –   –   –   –   –   –   –   –   –   –   –   –
051-100 Ramp down
101-150 Ramp up-down
151-200 Lightning
201-255 Random
Strobe Rate
–   8   –   –   –   –   –   –   –   –   –   –   –   –
000-255 Speed, slow to fast
Strobe Duration
–   9   –   –   –   –   –   –   –   –   –   –   –   –
000-255 Duration, slow to fast
–   –   –   –   –   1   1   1   1   1   1   1   1   1   000-255 Red 1
–   –   –   –   –   2   2   2   2   2   2   2   2   2   000-255 Green 1
–   –   –   –   –   3   3   3   3   3   3   3   3   3   000-255 Blue 1
–   –   –   –   –   4   4   4   4   4   4   4   4   4   000-255 Red 2
–   –   –   –   –   5   5   5   5   5   5   5   5   5   000-255 Green 2
–   –   –   –   –   6   6   6   6   6   6   6   6   6   000-255 Blue 2
–   –   –   –   –   7   7   7   7   7   7   7   7   7   000-255 Red 3
–   –   –   –   –   8   8   8   8   8   8   8   8   8   000-255 Green 3
–   –   –   –   –   9   9   9   9   9   9   9   9   9   000-255 Blue 3
–   –   –   –   –   10   10   10   10   10   10   10   10   10   000-255 Red 4
–   –   –   –   –   11   11   11   11   11   11   11   11   11   000-255 Green 4
–   –   –   –   –   12   12   12   12   12   12   12   12   12   000-255 Blue 4
–   –   –   –   –   13   13   13   13   13   13   13   13   13   000-255 Red 5
–   –   –   –   –   14   14   14   14   14   14   14   14   14   000-255 Green 5
–   –   –   –   –   15   15   15   15   15   15   15   15   15   000-255 Blue 5
–   –   –   –   –   16   16   16   16   16   16   16   16   16   000-255 Red 6
–   –   –   –   –   17   17   17   17   17   17   17   17   17   000-255 Green 6
–   –   –   –   –   18   18   18   18   18   18   18   18   18   000-255 Blue 6
–   –   –   –   –   19   19   19   19   19   19   19   19   19   000-255 Red 7
–   –   –   –   –   20   20   20   20   20   20   20   20   20   000-255 Green 7
–   –   –   –   –   21   21   21   21   21   21   21   21   21   000-255 Blue 7
–   –   –   –   –   22   22   22   22   22   22   22   22   22   000-255 Red 8
–   –   –   –   –   23   23   23   23   23   23   23   23   23   000-255 Green 8
–   –   –   –   –   24   24   24   24   24   24   24   24   24   000-255 Blue 8
–   –   –   –   –   –   –   –   25   25   25   25   25   25   000-255 Red 9
–   –   –   –   –   –   –   –   26   26   26   26   26   26   000-255 Green 9
–   –   –   –   –   –   –   –   27   27   27   27   27   27   000-255 Blue 9
–   –   –   –   –   –   –   –   28   28   28   28   28   28   000-255 Red 10
–   –   –   –   –   –   –   –   29   29   29   29   29   29   000-255 Green 10
–   –   –   –   –   –   –   –   30   30   30   30   30   30   000-255 Blue 10
21


=== DMXTRACT PAGE 22 ===
D M X T R A I T S
CHANNEL
DMX
6   9   13 18 20 36 41 43 51 81 83 126 141 143 VALUES   FUNCTION
CH CH CH CH CH CH CH CH CH CH CH CH CH CH
–   –   –   –   –   –   –   –   –   31   31   31   31   31   000-255 Red 11
–   –   –   –   –   –   –   –   –   32   32   32   32   32   000-255 Green 11
–   –   –   –   –   –   –   –   –   33   33   33   33   33   000-255 Blue 11
–   –   –   –   –   –   –   –   –   34   34   34   34   34   000-255 Red 12
–   –   –   –   –   –   –   –   –   35   35   35   35   35   000-255 Green 12
–   –   –   –   –   –   –   –   –   36   36   36   36   36   000-255 Blue 12
–   –   –   –   –   –   –   –   –   37   37   37   37   37   000-255 Red 13
–   –   –   –   –   –   –   –   –   38   38   38   38   38   000-255 Green 13
–   –   –   –   –   –   –   –   –   39   39   39   39   39   000-255 Blue 13
–   –   –   –   –   –   –   –   –   40   40   40   40   40   000-255 Red 14
–   –   –   –   –   –   –   –   –   41   41   41   41   41   000-255 Green 14
–   –   –   –   –   –   –   –   –   42   42   42   42   42   000-255 Blue 14
–   –   –   –   –   –   –   –   –   43   43   43   43   43   000-255 Red 15
–   –   –   –   –   –   –   –   –   44   44   44   44   44   000-255 Green 15
–   –   –   –   –   –   –   –   –   45   45   45   45   45   000-255 Blue 15
–   –   –   –   –   –   –   –   –   46   46   46   46   46   000-255 Red 16
–   –   –   –   –   –   –   –   –   47   47   47   47   47   000-255 Green 16
–   –   –   –   –   –   –   –   –   48   48   48   48   48   000-255 Blue 16
–   –   –   –   –   –   –   –   –   49   49   49   49   49   000-255 Red 17
–   –   –   –   –   –   –   –   –   50   50   50   50   50   000-255 Green 17
–   –   –   –   –   –   –   –   –   51   51   51   51   51   000-255 Blue 17
–   –   –   –   –   –   –   –   –   52   52   52   52   52   000-255 Red 18
–   –   –   –   –   –   –   –   –   53   53   53   53   53   000-255 Green 18
–   –   –   –   –   –   –   –   –   54   54   54   54   54   000-255 Blue 18
–   –   –   –   –   –   –   –   –   55   55   55   55   55   000-255 Red 19
–   –   –   –   –   –   –   –   –   56   56   56   56   56   000-255 Green 19
–   –   –   –   –   –   –   –   –   57   57   57   57   57   000-255 Blue 19
–   –   –   –   –   –   –   –   –   58   58   58   58   58   000-255 Red 20
–   –   –   –   –   –   –   –   –   59   59   59   59   59   000-255 Green 20
–   –   –   –   –   –   –   –   –   60   60   60   60   60   000-255 Blue 20
–   –   –   –   –   –   –   –   –   –   –   61   61   61   000-255 Red 21
–   –   –   –   –   –   –   –   –   –   –   62   62   62   000-255 Green 21
–   –   –   –   –   –   –   –   –   –   –   63   63   63   000-255 Blue 21
–   –   –   –   –   –   –   –   –   –   –   64   64   64   000-255 Red 22
–   –   –   –   –   –   –   –   –   –   –   65   65   65   000-255 Green 22
–   –   –   –   –   –   –   –   –   –   –   66   66   66   000-255 Blue 22
–   –   –   –   –   –   –   –   –   –   –   67   67   67   000-255 Red 23
–   –   –   –   –   –   –   –   –   –   –   68   68   68   000-255 Green 23
–   –   –   –   –   –   –   –   –   –   –   69   69   69   000-255 Blue 23
–   –   –   –   –   –   –   –   –   –   –   70   70   70   000-255 Red 24
–   –   –   –   –   –   –   –   –   –   –   71   71   71   000-255 Green 24
–   –   –   –   –   –   –   –   –   –   –   72   72   72   000-255 Blue 24
–   –   –   –   –   –   –   –   –   –   –   73   73   73   000-255 Red 25
–   –   –   –   –   –   –   –   –   –   –   74   74   74   000-255 Green 25
–   –   –   –   –   –   –   –   –   –   –   75   75   75   000-255 Blue 25
22


=== DMXTRACT PAGE 23 ===
D M X T R A I T S
CHANNEL
DMX
6   9   13 18 20 36 41 43 51 81 83 126 141 143 VALUES   FUNCTION
CH CH CH CH CH CH CH CH CH CH CH CH CH CH
–   –   –   –   –   –   –   –   –   –   –   76   76   76   000-255 Red 26
–   –   –   –   –   –   –   –   –   –   –   77   77   77   000-255 Green 26
–   –   –   –   –   –   –   –   –   –   –   78   78   78   000-255 Blue 26
–   –   –   –   –   –   –   –   –   –   –   79   79   79   000-255 Red 27
–   –   –   –   –   –   –   –   –   –   –   80   80   80   000-255 Green 27
–   –   –   –   –   –   –   –   –   –   –   81   81   81   000-255 Blue 27
–   –   –   –   –   –   –   –   –   –   –   82   82   82   000-255 Red 28
–   –   –   –   –   –   –   –   –   –   –   83   83   83   000-255 Green 28
–   –   –   –   –   –   –   –   –   –   –   84   84   84   000-255 Blue 28
–   –   –   –   –   –   –   –   –   –   –   85   85   85   000-255 Red 29
–   –   –   –   –   –   –   –   –   –   –   86   86   86   000-255 Green 29
–   –   –   –   –   –   –   –   –   –   –   87   87   87   000-255 Blue 29
–   –   –   –   –   –   –   –   –   –   –   88   88   88   000-255 Red 30
–   –   –   –   –   –   –   –   –   –   –   89   89   89   000-255 Green 30
–   –   –   –   –   –   –   –   –   –   –   90   90   90   000-255 Blue 30
–   –   –   –   –   –   –   –   –   –   –   91   91   91   000-255 Red 31
–   –   –   –   –   –   –   –   –   –   –   92   92   92   000-255 Green 31
–   –   –   –   –   –   –   –   –   –   –   93   93   93   000-255 Blue 31
–   –   –   –   –   –   –   –   –   –   –   94   94   94   000-255 Red 32
–   –   –   –   –   –   –   –   –   –   –   95   95   95   000-255 Green 32
–   –   –   –   –   –   –   –   –   –   –   96   96   96   000-255 Blue 32
–   –   –   –   –   –   –   –   –   –   –   97   97   97   000-255 Red 33
–   –   –   –   –   –   –   –   –   –   –   98   98   98   000-255 Green 33
–   –   –   –   –   –   –   –   –   –   –   99   99   99   000-255 Blue 33
–   –   –   –   –   –   –   –   –   –   –   100   100   100   000-255 Red 34
–   –   –   –   –   –   –   –   –   –   –   101   101   101   000-255 Green 34
–   –   –   –   –   –   –   –   –   –   –   102   102   102   000-255 Blue 34
–   –   –   –   –   –   –   –   –   –   –   103   103   103   000-255 Red 35
–   –   –   –   –   –   –   –   –   –   –   104   104   104   000-255 Green 35
–   –   –   –   –   –   –   –   –   –   –   105   105   105   000-255 Blue 35
–   –   –   –   –   –   –   –   –   –   –   106   106   106   000-255 Red 36
–   –   –   –   –   –   –   –   –   –   –   107   107   107   000-255 Green 36
–   –   –   –   –   –   –   –   –   –   –   108   108   108   000-255 Blue 36
–   –   –   –   –   –   –   –   –   –   –   109   109   109   000-255 Red 37
–   –   –   –   –   –   –   –   –   –   –   110   110   110   000-255 Green 37
–   –   –   –   –   –   –   –   –   –   –   111   111   111   000-255 Blue 37
–   –   –   –   –   –   –   –   –   –   –   112   112   112   000-255 Red 38
–   –   –   –   –   –   –   –   –   –   –   113   113   113   000-255 Green 38
–   –   –   –   –   –   –   –   –   –   –   114   114   114   000-255 Blue 38
–   –   –   –   –   –   –   –   –   –   –   115   115   115   000-255 Red 39
–   –   –   –   –   –   –   –   –   –   –   116   116   116   000-255 Green 39
–   –   –   –   –   –   –   –   –   –   –   117   117   117   000-255 Blue 39
–   –   –   –   –   –   –   –   –   –   –   118   118   118   000-255 Red 40
–   –   –   –   –   –   –   –   –   –   –   119   119   119   000-255 Green 40
–   –   –   –   –   –   –   –   –   –   –   120   120   120   000-255 Blue 40
23


=== DMXTRACT PAGE 24 ===
D M X T R A I T S
CHANNEL
DMX
6   9   13 18 20 36 41 43 51 81 83 126 141 143 VALUES   FUNCTION
CH CH CH CH CH CH CH CH CH CH CH CH CH CH
CT Presets
000-022 Open
–   –   –   –   4   –   –   25   –   –   61   –   –   121
023-089 CTO 2300K - 8900K
090-255 9000K
–   –   –   –   5   –   –   26   –   –   62   –   –   122   000-255 Green Shift
–   –   5   4   6   –   25   27   31   61   63   –   121   123   000-255 Outer Color Macros
Outer Dimmer, 0 to
–   –   –   5   7   25   26   28   32   62   64   –   122   124   000-255
100%
Outer Dimmer Fine, 0
–   –   –   6   8   26   27   29   33   63   65   –   123   125   000-255
to 100%
Outer Strobe Effect
000-002 Open
003-005 Strobe
006-050 Ramp up
–   –   8   7   9   27   28   30   34   64   66   –   124   126
051-100 Ramp down
101-150 Ramp up-down
151-200 Lightning
201-255 Random
Outer Strobe Rate
–   –   9   8   10   28   29   31   35   65   67   –   125   127
000-255 Speed, slow to fast
Outer Strobe Dura -
–   –   10   9   11   29   30   32   36   66   68   –   126   128   tion
000-255 Duration, slow to fast
Outer Program
Macro
000-005 No function
006-015 Macro 1
016-025 Macro 2
026-035 Macro 3
036-045 Macro 4
046-055 Macro 5
056-065 Macro 6
066-075 Macro 7
076-085 Macro 8
–   –   11   10   12   –   31   33   37   67   69   –   127   129
086-095 Macro 9
096-105 Macro 10
106-115 Macro 11
116-125 Macro 12
126-135 Macro 13
136-145 Macro 14
146-155 Macro 15
156-165 Macro 16
166-175 Macro 17
176-185 Macro 18
186-195 Macro 19
24


=== DMXTRACT PAGE 25 ===
D M X T R A I T S
CHANNEL
DMX
6   9   13 18 20 36 41 43 51 81 83 126 141 143 VALUES   FUNCTION
CH CH CH CH CH CH CH CH CH CH CH CH CH CH
Outer Program
Macro (continued)
196-205 Macro 20
206-215 Macro 21
–   –   11   10   12   –   31   33   37   67   69   –   127   129
216-225 Macro 22
226-235 Macro 23
236-245 Macro 24
246-255 Macro 25
Outer Program
–   –   –   11   13   –   32   34   38   68   70   –   128   130   000-255
Macro Speed
–   –   –   –   –   –   –   –   39   69   71   121   129   131   000-255 White 1
–   –   –   –   –   –   –   –   40   70   72   122   130   132   000-255 White 2
–   –   –   –   –   –   –   –   41   71   73   123   131   133   000-255 White 3
–   –   –   –   –   –   –   –   42   72   74   124   132   134   000-255 White 4
–   –   –   –   –   –   –   –   43   73   75   125   133   135   000-255 White 5
–   –   –   –   –   –   –   –   44   74   76   126   134   136   000-255 White 6
–   –   –   –   –   30   33   35   –   –   –   –   –   –   000-255 Inner White Group 1
–   –   –   –   –   31   34   36   –   –   –   –   –   –   000-255 Inner White Group 2
Inner Dimmer, 0 to
–   –   –   12   14   32   35   37   45   75   77   –   135   137   000-255
100%
Inner Dimmer Fine, 0
–   –   –   13   15   33   36   38   46   76   78   –   136   138   000-255
to 100%
Inner Strobe Effect
000-002 Open
003-005 Strobe
006-050 Ramp up
–   –   –   14   16   34   37   39   47   77   79   –   137   139
051-100 Ramp down
101-150 Ramp up-down
151-200 Lightning
201-255 Random
Inner Strobe Rate
–   –   –   15   17   35   38   40   48   78   80   –   138   140
000-255 Speed, slow to fast
Inner Strobe Dura -
–   –   –   16   18   36   39   41   49   79   81   –   139   141   tion
000-255 Duration, slow to fast
Inner Program Macro
000-005 No Function
006-033 Macro 1
034-060 Macro 2
061-088 Macro 3
–   –   12   17   19   –   40   42   50   80   82   –   140   142   089-116 Macro 4
117-144 Macro 5
145-172 Macro 6
173-200 Macro 7
201-228 Macro 8
229-255 Macro 9
Inner Program Macro
–   –   –   18   20   –   41   43   51   81   83   –   141   143   000-255
Speed
In/Out Program
–   –   13   –   –   –   –   –   –   –   –   –   –   –   000-255 Macro Speed, slow
to fast
25


=== DMXTRACT PAGE 26 ===
R E M O T E D E V I C E M A N A G E M E N T ( R D M )
NOTE: for RDM to work properly, RDM enabled equipment must be used throughout the entire
system, including DMX data splitters and wireless systems.
Remote Device Management (RDM) is a protocol that sits on top of the DMX512 data standard for
lighting, allowing the DMX systems of the fixtures to be modified and monitored remotely. This protocol
is ideal for instances in which a unit is installed in a location that is not easily accessible.
With RDM, the DMX512 system becomes bi-directional, allowing a compatible RDM enabled controller
to send out a signal to devices on the wire, as well as allowing the fixture to respond (known as a GET
command). The controller can then use its SET command to modify settings that would typically have to
be changed or viewed directly via the unit’s display screen, including the DMX Address, DMX Channel
Mode, and Temperature Sensors.
FIXTURE RDM INFORMATION:
RDM Code   Device ID   Device Model ID   Personality ID
6CH, 9CH, 13CH, 18CH, 36CH, 41CH, 51CH,
1900   0000-FFFF   79
81CH, 126CH, 141CHLK
Please be aware that not all RDM devices support all RDM features, and therefore it is important
to check beforehand to ensure that the equipment that you are considering includes all of the features
that you require.
The following parameters are accessible in RDM on this device:
Parameter ID   Code
Sensor Definition   [0x0200]
Sensor Value   [0x0201]
Device Model Description   [0x0080]
Manufacturer Label   [0x0081]
Device Label   [0x0082]
DMX Personality   [0x00E0]
DMX Personality Description   [0x00E1]
Device Hours   [0x0400]
Comms Status   [0x0015]
Status ID Description   [0x0031]
Clear Status ID   [0x0032]
Device Power Cycles   [0x0405]
Display Invert   [0x0500]
Display Level   [0x0501]
Realtime Clock   [0x0603]
Power State   [0x1010]
Preset Playback   [0x1031]
Slot Information   [0x0120]
Slot Description   [0x0122]
Default Slot Value   [0x0122]
Language   [0x00B0]
Language Capabilities   [0x00A0]
Boot Software Version Label   [0x00C2]
Boot Software Version ID   [0x00C1]
Product Detail ID List   [0x0070]
Status Messages   [0x0030]
26
''';

/// The four DMX Traits pages of the ADJ ElectraPix Par 7 manual (32-35),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _electraPixPar7TraitsExcerpt = r'''
=== DMXTRACT PAGE 32 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
5Ch 6Ch 7Ch 9Ch 12Ch 13Ch 22Ch 24Ch 42Ch 45Ch 60Ch VALUES
–   1   1   1   1   –   1   1   –   –   –   000-255 All Red , 0–100%
–   2   2   2   2   –   2   2   –   –   –   000-255 All Green , 0–100%
–   3   3   3   3   –   3   3   –   –   –   000-255 All Blue , 0–100%
–   4   4   4   4   –   4   4   –   –   –   000-255 All Amber , 0–100%
–   5   5   5   5   –   5   5   –   –   –   000-255 All Lime , 0–100%
–   6   6   6   6   –   6   6   –   –   –   000-255 All UV , 0–100%
–   –   –   –   –   –   –   –   1   1   1   000-255 Red 1 , 0–100%
–   –   –   –   –   –   –   –   2   2   2   000-255 Green 1 , 0–100%
–   –   –   –   –   –   –   –   3   3   3   000-255 Blue 1 , 0–100%
–   –   –   –   –   –   –   –   4   4   4   000-255 Amber 1 , 0–100%
–   –   –   –   –   –   –   –   5   5   5   000-255 Lime 1 , 0–100%
–   –   –   –   –   –   –   –   6   6   6   000-255 UV 1 , 0–100%
–   –   –   –   –   –   –   –   7   7   7   000-255 Red 2 , 0–100%
–   –   –   –   –   –   –   –   8   8   8   000-255 Green 2 , 0–100%
–   –   –   –   –   –   –   –   9   9   9   000-255 Blue 2 , 0–100%
–   –   –   –   –   –   –   –   10   10   10   000-255 Amber 2 , 0–100%
–   –   –   –   –   –   –   –   11   11   11   000-255 Lime 2 , 0–100%
–   –   –   –   –   –   –   –   12   12   12   000-255 UV 2 , 0–100%
–   –   –   –   –   –   –   –   13   13   13   000-255 Red 3 , 0–100%
–   –   –   –   –   –   –   –   14   14   14   000-255 Green 3 , 0–100%
–   –   –   –   –   –   –   –   15   15   15   000-255 Blue 3 , 0–100%
–   –   –   –   –   –   –   –   16   16   16   000-255 Amber 3 , 0–100%
–   –   –   –   –   –   –   –   17   17   17   000-255 Lime 3 , 0–100%
–   –   –   –   –   –   –   –   18   18   18   000-255 UV 3 , 0–100%
...   ...   ...   ...   ...
–   –   –   –   –   –   –   –   37   37   37   000-255 Red 7 , 0–100%
–   –   –   –   –   –   –   –   38   38   38   000-255 Green 7 , 0–100%
–   –   –   –   –   –   –   –   39   39   39   000-255 Blue 7 , 0–100%
–   –   –   –   –   –   –   –   40   40   40   000-255 Amber 7 , 0–100%
–   –   –   –   –   –   –   –   41   41   41   000-255 Lime 7 , 0–100%
–   –   –   –   –   –   –   –   42   42   42   000-255 UV 7 , 0–100%
RGBAL+UV Color
Macros ,
–   –   –   –   –   1   7   7   –   –   43   000-255
see Color Macros
section
Background Red ,
–   –   –   7   7   –   8   8   –   43   44   000-255
0–100%
Background Green ,
–   –   –   8   8   –   9   9   –   44   45   000-255
0–100%
Background Blue ,
–   –   –   9   9   –   10   10   –   45   46   000-255
0–100%
RGB Background
Color Macros ,
–   –   –   –   –   2   11   11   –   –   47   000-255
see Color Macros
section
Color Temperature
1   –   –   –   10   3   12   12   –   –   48   000-255 2300–9900K Linear,
0–100%
–   –   –   –   –   –   –   32   –   –   –


=== DMXTRACT PAGE 33 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
5Ch 6Ch 7Ch 9Ch 12Ch 13Ch 22Ch 24Ch 42Ch 45Ch 60Ch VALUES
White Color Temper -
ature Presets
2   –   –   –   –   4   13   13   –   –   49   0-22   Open
23-99 See WCT Preset Chart
100-255 No Function
Shutter, Strobe
0-31   LEDs Off
32-63 LEDs On
Strobe effect slow to
64-95
fast
96-127 LEDs On
3   –   –   –   11   5   14   14   –   –   50
Pulse-effect in se -
128-159
quences
160-191 LEDs On
Random strobe effect
192-223
slow to fast
224-255 LEDs On
Dimmer (Intensity ) ,
4   –   7   –   12   6   15   15   –   –   51   000-255
0–100%
Dimmer Fine (Inten -
5   –   –   –   –   7   16   16   –   –   52   000-255
sity)
RGBAL+UV Pro -
grams
000-010 Off
011-026 Auto Program 1
027-043 Auto Program 2
044-060 Auto Program 3
061-076 Auto Program 4
077-093 Auto Program 5
–   –   –   –   –   8   17   17   –   –   53   094-110 Auto Program 6
111-126 Auto Program 7
127-143 Auto Program 8
144-160 Auto Program 9
161-176 Auto Program 10
177-193 Auto Program 11
194-210 Auto Program 12
211-226 Auto Program 13
227-255 No Function
RGBAL+UV Pro -
–   –   –   –   –   9   18   18   –   –   54   000-255 grams Speed ,
slow to fast
RGBAL+UV Pro -
–   –   –   –   –   10   19   19   –   –   55   000-255 grams Fade ,
least to most
RGB Background
Programs
000-010 Off
011-026 Auto Program 1
–   –   –   –   –   11   20   20   –   –   56
027-043 Auto Program 2
044-060 Auto Program 3
061-076 Auto Program 4
077-093 Auto Program 5
–   –   –   –   –   –   –   33   –   –   –


=== DMXTRACT PAGE 34 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
5Ch 6Ch 7Ch 9Ch 12Ch 13Ch 22Ch 24Ch 42Ch 45Ch 60Ch VALUES
RGB Background
Programs (contin -
ued)
094-110 Auto Program 6
111-126 Auto Program 7
127-143 Auto Program 8
144-160 Auto Program 9
–   –   –   –   –   11   20   20   –   –   56   161-176 Auto Program 10
177-193 Auto Program 11
194-210 Auto Program 12
211-226 Auto Program 13
227-255 No Function
RGB Background
–   –   –   –   –   12   21   21   –   –   57   000-255 Programs Speed ,
slow to fast
RGB Background
–   –   –   –   –   13   22   22   –   –   58   000-255 Program Fade , least
to most
Dim Mode
000-020 Default to Unit Setting
021-040 Standard
041-060 Stage
061-080 TV
081-100 Architectural
101-120 Theatre
121-140 Stage 2
Dim Speed
141   0.1s
142   0.2s
143   0.3s
144   0.4s
145   0.5s
146   0.6s
–   –   –   –   –   –   –   23   –   –   59
147   0.7s
148   0.8s
149   0.9s
150   1.0s
151   1.5s
152   2.0s
153   3.0s
154   4.0s
155   5.0s
156   6.0s
157   7.0s
158   8.0s
159   9.0s
160   10.0s
161-255 Default to Unit Setting
–   –   –   –   –   –   –   34   –   –   –


=== DMXTRACT PAGE 35 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
5Ch 6Ch 7Ch 9Ch 12Ch 13Ch 22Ch 24Ch 42Ch 45Ch 60Ch VALUES
Dim Curves
000-020 Square
021-040 Linear
–   –   –   –   –   –   –   24   –   –   60
041-060 Inv Squa
061-080 S Curve
081-255 No Function
–   –   –   –   –   –   –   35   –   –   –
''';

/// The three DMX Traits pages of the ADJ Element Hex IP manual (14-16),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _elementHexIpTraitsExcerpt = r'''
=== DMXTRACT PAGE 14 ===
Element HEXIP   DMX Modes
6 CH 7 CH 8 CH 11 CH 12 CH   VALUES   FUNCTIONS
RED
1   1   1   1   1
000-255 0~100%
GREEN
2   2   2   2   2
000-255 0~100%
BLUE
3   3   3   3   3
000-255 0~100%
WHITE
4   4   4   4   4
000-255 0~100%
AMBER
5   5   5   5   5
000-255 0~100%
UV
6   6   6   6   6
000-255 0~100%
MASTER DIMMER
–   7   7   7   7
000-255 0~100%
STROBING/SHUTTER
000-031 LED OFF
032-063 LED ON
064-095 STROBING SLOW-FAST
–   –   8   8   8   096-127 LED ON
128-159 PULSE STROBING SLOW-FAST
160-191 LED ON
192-223 RANDOM STROBING SLOW-FAST
224-255 LED ON
PROGRAM SELECTION MODE
000-051 RGBWA+UV DIMMING MODE
052-102 COLOR MACRO MODE
–   –   –   9   9
103-153 COLOR CHANGE MODE
154-204 COLOR FADE MODE
205-255 SOUND ACTIVE MODE
NOTE: 11 CHANNEL DMX MODE & 12 CHANNEL DMX MODE:
When Channel 9 is between the values of 0-51, Channels 1-6 are used, and Channel 8 will control
strobing.
When Channel 9 is between the values of 52-102, Channel 10 is in Color Macros Mode, and
Channel 8 will control strobing.
When Channel 9 is between the values of 103-153, Channel 10 is in Color Change Mode, and
Channel 11 will control the color change speed.
When Channel 9 is between the values of 154-204, Channel 10 is in Color Fade Mode, and
Channel 11 will control the color fade speed.
When Channel 9 is between the values of 205-255, Channel 10 is in Sound Active Mode, and
Channel 11 will control the sound sensitivity.
ADJ Products, LLC - www.adj.com - Element HEXIP User Manual Page 13


=== DMXTRACT PAGE 15 ===
Element HEXIP   DMX Modes
6 CH 7 CH 8 CH 11 CH 12 CH VALUES   FUNCTIONS
PROGRAMS
COLOR MACRO MODE
000-255 SEE THE COLOR MACRO CHART ON PAGE 15
COLOR CHANGE MODE
000-015 COLOR CHANGE 1
016-031 COLOR CHANGE 2
032-047 COLOR CHANGE 3
048-063 COLOR CHANGE 4
064-079 COLOR CHANGE 5
080-095 COLOR CHANGE 6
096-111 COLOR CHANGE 7
112-127 COLOR CHANGE 8
128-143 COLOR CHANGE 9
144-159 COLOR CHANGE 10
160-175 COLOR CHANGE 11
176-191 COLOR CHANGE 12
192-207 COLOR CHANGE 13
208-223 COLOR CHANGE 14
224-239 COLOR CHANGE 15
240-255 COLOR CHANGE 16
COLOR FADE MODE
000-015 COLOR FADE 1
–   –   –   10   10   016-031 COLOR FADE 2
032-047 COLOR FADE 3
048-063 COLOR FADE 4
064-079 COLOR FADE 5
080-095 COLOR FADE 6
096-111 COLOR FADE 7
112-127 COLOR FADE 8
128-143 COLOR FADE 9
144-159 COLOR FADE 10
160-175 COLOR FADE 11
176-191 COLOR FADE 12
192-207 COLOR FADE 13
208-223 COLOR FADE 14
224-239 COLOR FADE 15
240-255 COLOR FADE 16
SOUND ACTIVE MODE
000-015 SOUND ACTIVE MODE 1
016-031 SOUND ACTIVE MODE 2
032-047 SOUND ACTIVE MODE 3
048-063 SOUND ACTIVE MODE 4
064-079 SOUND ACTIVE MODE 5
080-095 SOUND ACTIVE MODE 6
096-111 SOUND ACTIVE MODE 7
112-127 SOUND ACTIVE MODE 8
128-143 SOUND ACTIVE MODE 9
144-159 SOUND ACTIVE MODE 10
160-175 SOUND ACTIVE MODE 11
176-191 SOUND ACTIVE MODE 12
192-207 SOUND ACTIVE MODE 13
208-223 SOUND ACTIVE MODE 14
224-239 SOUND ACTIVE MODE 15
240-255 SOUND ACTIVE MODE 16
ADJ Products, LLC - www.adj.com - Element HEXIP User Manual Page 14


=== DMXTRACT PAGE 16 ===
Element HEXIP   DMX Modes
6 CH 7 CH 8 CH 11 CH 12 CH   VALUES   FUNCTIONS
PROGRAM SPEED/SOUND SENSITIVITY
–   –   –   11   11   000-255 PROGRAM SPEED SLOW-FAST
000-255 LEAST SENSITIVE-MOST SENSITIVE
DIMMER CURVES
000-020 STANDARD
021-040 STAGE
–   –   –   –   12
041-060 TV
061-080 ARCHITECTURAL
081-100 THEATRE
101-255 DEFAULT TO UNIT SETTING
Element HEXIP   Color Macro Chart
0-3=Off   64-67=B+W   128-131=G+B+W   192-195=R+B+W+A
4-7=Red   68-71=B+A   132-135=G+B+A   196-199=R+B+W+UV
8-11=Green   72-75=B+UV   136-139=G+B+UV   200-203=R+B+A+UV
12-15=Blue   76-79=W+A   140-143=G+W+A   204-207=R+W+A+UV
16-19=White   80-83=W+UV   144-147=G+W+UV   208-211=G+B+W+A
20-23=Amber   84-87=A+UV   148-151=G+A+UV   212-215=G+B+W+UV
24-27=UV   88-91=R+G+B   152-155=B+W+A   216-219=G+B+A+UV
28-31=R+G   92-95=R+G+W   156-159=B+W+UV   220-223=G+W+A+UV
32-35=R+B   96-99=R+G+A   160-163=B+A+UV   224-227=B+W+A+UV
36-39=R+W   100-103=R+G+UV   164-167=W+A+UV   228-231=R+G+B+W+A
40-43=R+A   104-107=R+B+W   168-171=R+G+B+W   232-235=R+G+B+W+UV
44-47=R+UV   108-111=R+B+A   172-175=R+G+B+A   236-239=R+G+B+A+UV
48-51=G+B   112-115=R+B+UV   176-179=R+G+B+UV   240-243=R+G+W+A+UV
52-55=G+W   116-119=R+W+A   180-183=R+G+W+A   244-247=R+B+W+A=UV
56-59=G+A   120-123=R+W+UV   184-187=R+G+W+UV   248-251=G+B+W+A+UV
60-63=G+UV   124-127=R+A+UV   188-191=R+G+A+UV   252-255=R+G+B+W+A+UV
ADJ Products, LLC - www.adj.com - Element HEXIP User Manual Page 15
''';

/// The two DMX Traits pages of the Eliminator LP 8R manual (19, 20),
/// verbatim from this app's PDF.js text pass with blank cells as "–".
const _lp8rTraitsExcerpt = r'''
=== DMXTRACT PAGE 19 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION   LEDS
3Ch 6Ch 13Ch 38Ch VALUES
–   1   1   1   000-255 Main Dimming
Strobe / Shutter
000-031 Shutter Closed (LEDs OFF)
032-063 Shutter OPEN (LEDS ON)
064-095 Strobe effect slow to fast
–   –   2   2   096-127 Shutter OPEN(LEDS ON)
128-159 Pulse effect in sequences
160-191 Shutter OPEN(LEDS ON)
192-223 Random strobe effect slow to fast
224-255 Shutter OPEN(LEDS ON)   Middle 7 LEDs
–   2   –   3   000-255 Color macro function , from dark to bright
–   –   3   4   000-255 Red dimming , from dark to bright
–   –   4   5   000-255 Green dimming , from dark to bright
–   –   5   6   000-255 Blue dimming , from dark to bright
–   –   6   7   000-255 White dimming , from dark to bright
–   3   7   8   000-255 Main dimming
Strobe / Shutter
000-031 Shutter Closed (LEDs OFF)
032-063 Shutter OPEN (LEDS ON)
064-095 Strobe effect slow to fast
–   –   2   2   096-127 Shutter OPEN(LEDS ON)
128-159 Pulse effect in sequences
160-191 Shutter OPEN(LEDS ON)
192-223 Random strobe effect slow to fast
224-255 Shutter OPEN(LEDS ON)
2   4   –   10   000-255 Color macro function
–   5   –   11   000-255 Macro function auto-run
–   6   –   12   000-255 Macro function auto-run speed , Slow to Fast
–   –   9   13   000-255 Red 1 dimming , from dark to bright
–   –   10   14   000-255 Green 1 dimming , from dark to bright
–   –   11   15   000-255 Blue 1 dimming , from dark to bright   LED Strip
–   –   –   16   000-255 Red 2 dimming , from dark to bright
–   –   –   17   000-255 Green 2 dimming , from dark to bright
–   –   –   18   000-255 Blue 2 dimming , from dark to bright
–   –   –   19   000-255 Red 3 dimming , from dark to bright
–   –   –   20   000-255 Green 3 dimming , from dark to bright
–   –   –   21   000-255 Blue 3 dimming , from dark to bright
–   –   –   22   000-255 Red 4 dimming , from dark to bright
–   –   –   23   000-255 Green 4 dimming , from dark to bright
–   –   –   24   000-255 Blue 4 dimming , from dark to bright
–   –   –   25   000-255 Red 5 dimming , from dark to bright
–   –   –   26   000-255 Green 5 dimming , from dark to bright
–   –   –   27   000-255 Blue 5 dimming , from dark to bright
19


=== DMXTRACT PAGE 20 ===
D M X T R A I T S
CHANNEL   DMX
FUNCTION
3Ch 6Ch 13Ch 38Ch VALUES
–   –   –   28   000-255 Red 6 dimming , from dark to bright
–   –   –   29   000-255 Green 6 dimming , from dark to bright
–   –   –   30   000-255 Blue6 dimming , from dark to bright
–   –   –   31   000-255 Red 7 dimming , from dark to bright
–   –   –   32   000-255 Green 7 dimming , from dark to bright
–   –   –   33   000-255 Blue 7 dimming , from dark to bright
LED Strip
–   –   –   34   000-255 Red 8 dimming , from dark to bright
–   –   –   35   000-255 Green 8 dimming , from dark to bright
–   –   –   36   000-255 Blue 8 dimming , from dark to bright
Auto Run
000-029 Empty , No Function
Auto run 1 , Color fade-in and fade-out
030-054
(3 colors: red, green, and blue )
Auto run 2 , Color fade-in and fade-out
055-079
(7 colors: red, green, blue, cyan, magenta, yellow, and white
080-104 Auto run 3 , Color dimming
1   –   12   37   105-129 Auto run 4 , Red fade-in and fade-out
130-154 Auto run 5 , Green fade-in and fade-out
155-179 Auto run 6 , Blue fade-in and fade-out
180-204 Auto run 7 , White fade-in and fade-out
205-229 Auto run 8 , Color changes (3 colors: red, green, and blue)
Auto run 9 , Color changes
230-255
(7 colors: red, green, blue, cyan, magenta, yellow, and white)
Speed / Sound sensitivity , Speed adjustment (when sound
3   –   13   38   000-255
control is off) / Sound control sensitivity (when sound control is on)
20
''';

/// The ADJ Encore LP12Z IP manual's cover (page 1, an image read by OCR) and
/// page 4, verbatim from this app's text pass.
const _encoreLp12zCoverExcerpt = r'''
=== DMXTRACT PAGE 1 ===
s>~
ADS
VY
ENCORE LPIeZ IP
Kath ys
AwAs
User Manual


=== DMXTRACT PAGE 4 ===
I N T R O D U C T I O N
Unpacking: Thank you for purchasing the Encore LP12Z IP by ADJ Products, LLC. Every device has
been thoroughly tested and has been shipped in perfect operating condition. Carefully check the ship -
ping carton for damage that may have occurred during shipping. If the carton appears to have been
damaged, carefully inspect your fixture for any damage and be sure all accessories necessary to oper -
ate the unit have arrived intact. In the event that damage has been found or parts are missing, please
contact our toll free customer support number for further instructions. Do not return this unit to your
dealer without first contacting customer support.
Introduction: The ADJ Encore LP12Z IP is an IP65-rated wash fixture with motorized zoom, wireless
DMX and a variety of useful professional control tools for staging and event application. Its twelve 20W
Quad RGBL (Red, Green, Blue and Lime) LEDs allow for a wide array of colors to be produced, tunable
white color control from 2700K to 6500K and an attractive CRI output. This product is intended to be
used by professionally trained personnel only and is not suitable for private use.
Customer Support: Contact ADJ Service for any product related service and support needs. Also visit
forums.adj.com with questions, comments or suggestions.
Parts: To purchase parts online visit:
http://parts.adj.com (US)
http://www.adjparts.eu (EU)
ADJ SERVICE USA - Monday - Friday 8:00am to 4:30pm PST
Voice: 800-322-6337 | Fax: 323-582-2941 | support@adj.com
ADJ SERVICE EUROPE - Monday - Friday 08:30 to 17:00 CET
Voice: +31 45 546 85 60 | Fax: +31 45 546 85 96 | support@adj.eu
ADJ PRODUCTS LLC USA
6122 S. Eastern Ave. Los Angeles, CA. 90040
323-582-2650 | Fax 323-532-2941 | www.adj.com | info@adj. com
ADJ SUPPLY Europe B.V
Junostraat 2 6468 EW Kerkrade, The Netherlands
+31 (0)45 546 85 00 | Fax +31 45 546 85 99
www.americandj.eu | info@americandj.eu
ADJ PRODUCTS GROUP Mexico
AV Santa Ana 30 Parque Industrial Lerma, Lerma, Mexico 52000
+52 (728) 282-7070
CAUTION ! There are no user serviceable parts inside this unit. Do not attempt any repairs yourself,
as doing so will void your manufacturer’s warranty. In the unlikely event your unit may require service,
please contact ADJ Products, LLC.
Do not discard the shipping cartoon in the trash. Please recycle when ever possible.
4
''';

/// The ADJ Hydro Spot 1 manual's cover (page 1, an image read by OCR) and
/// page 6, verbatim from this app's text pass.
const _hydroSpot1CoverExcerpt = r'''
=== DMXTRACT PAGE 1 ===
S—~.
ADS
ar
HYDRO SPOT |
User Manual


=== DMXTRACT PAGE 6 ===
WA R R A N T Y R E G I S T R AT I O N
The Hydro Spot 1 carries a 2 year limited warranty. Please fill out the enclosed warranty card to
validate your purchase. All returned service items, whether under warranty or not, must be freight
pre-paid and accompanied by a return authorization (R.A.) number. The R.A. number must be clearly
written on the outside of the return package. A brief description of the problem as well as the R.A.
number must also be written down on a piece of paper included in the shipping carton. If the unit is
under warranty, you must provide a copy of your proof of purchase invoice. You may obtain an R.A.
number by contacting our customer support team on our customer support number. All packages
returned to the service department not displaying an R.A. number on the outside of the package will
be returned to the shipper.
F E AT U R E S
• Motorized Focus
• Motorized Zoom: 12° ~ 23°
• 2 Frost Filters (Heavy and Medium)
• 2 Prism FX: Rotating 5-facet Linear & rotating 6-facet Circular
• 0-100% smooth dimming
• Various strobe speeds
• 2 cooling fans
INCLUDED ITEMS
• Omega Bracket (x1)
• Locking Power Cable (x1)
IP RATING
An IP rated lighting fixture is commonly installed in outdoor environments and has been designed with
an enclosure that effectively protects the ingress (entry) of external foreign objects such as dust and
water. The Ingress Protection (IP) rating system is commonly expressed as “IP” followed by two num -
bers (i.e. IP65), where the numbers define the degree of protection. The first digit (Foreign Bodies
Protection) indicates the extent of protection against particles entering the fixture and the second digit
(Water Protection) indicates the extent of protection against water entering the fixture. An IP65 rated
lighting fixture, such as this one, has been designed and tested to protect against the ingress
of dust (6) and low-pressure water jets from any direction (5). INTENDED FOR TEMPORARY
OUTDOOR USE ONLY!
6
''';

/// The Elation Fuze Wash Z350 manual's cover (page 1) and page 10,
/// verbatim from this app's text pass.
const _fuzeWashZ350CoverExcerpt = r'''
=== DMXTRACT PAGE 1 ===
FT ATION
FUZE WASH Z350
User Manual


=== DMXTRACT PAGE 10 ===
OVERVIEW
Ecatio®, @®
FUZEWASH Z350 COMOMC)
www.elationlighting.com err ENTER RIGHT
en ®
A a
lj] | (Q2SQQ@O 0}
— Se) o ‘MXN ‘OM IN ‘bMx our ‘omex our —
|_lo \ = Cex |_|
10
''';
