import 'dart:io';
import 'package:dmxtract_web/src/extraction_rules.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds multiple fixture modes in common manual layouts', () {
    final adj = fixtureFromManualText(
      'ADJ VIZI XTREME DMX TRAITS 28Ch 40Ch 73Ch 54Ch 63Ch CHANNEL DMX VALUES FUNCTION Pan Tilt Dimmer Color Wheel Gobo Wheel',
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
    expect(phx.questions.single, contains('mains-dimmed'));
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
    expect(result.questions.single, contains('we read 3 of 6'));
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
}
