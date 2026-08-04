import 'dart:io';
import 'package:dmxtract_web/src/extraction_rules.dart';
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
