import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:dmxtract_web/src/export_service.dart';
import 'package:dmxtract_web/src/extraction_rules.dart';
import 'package:dmxtract_web/src/gdtf_attribute_catalog.dart';
import 'package:dmxtract_web/src/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = fixtureFromManualText(
    'BETOPPER Model: LB150 12CH Pan Pan fine Tilt Tilt fine PAN/TILT speed Dimming Light switch/strobe Color wheel Gobo wheel Prism Reserved Channel Reset/Function Channel',
    'LB150.pdf',
  ).fixture;
  test('exports OFL-shaped JSON', () {
    final json = jsonDecode(utf8.decode(exportOfl(fixture))) as Map;
    expect(json['name'], 'LB150');
    expect(json, isNot(contains(r'$dmxtract')));
    expect(json['categories'], isNotEmpty);
    expect((json['modes'] as List).single['channels'], hasLength(12));
    final firstChannel =
        ((json['availableChannels'] as Map).values.first as Map);
    expect(firstChannel, contains('capability'));
    expect(firstChannel, isNot(contains('capabilities')));
    expect(firstChannel['capability'], isNot(contains('dmxRange')));
  });

  test('exports 16-bit OFL ranges at 16-bit resolution', () {
    final sixteenBit = FixtureProject(
      id: 'sixteen-bit-test',
      manufacturer: 'Generic',
      model: '16-bit test',
      channels: [
        DmxChannel(
          id: 'Red',
          name: 'Red',
          kind: 'colorIntensity',
          color: 'RED',
          ranges: [DmxRange(start: 0, end: 127, name: 'Low red')],
        ),
        DmxChannel(id: 'Red fine', name: 'Red fine', fineOf: 'Red'),
      ],
      modes: [
        FixtureMode(
          id: 'mode',
          name: 'Mode',
          shortName: 'Mode',
          channelIds: ['Red', 'Red fine'],
        ),
      ],
    );

    final json = jsonDecode(utf8.decode(exportOfl(sixteenBit))) as Map;
    final channel = (json['availableChannels'] as Map)['Red'] as Map;
    expect(channel['dmxValueResolution'], '16bit');
    expect(channel['fineChannelAliases'], ['Red fine']);
    final capabilities = (channel['capabilities'] as List).cast<Map>();
    expect(capabilities.first['dmxRange'], [0, 32895]);
    expect(capabilities.last['dmxRange'], [32896, 65535]);
    expect(capabilities.first['type'], 'ColorIntensity');
    expect(capabilities.first['color'], 'Red');
  });
  test('exports GDTF 1.2 archive', () {
    fixture.channels.first.gdtfAttribute = 'ColorAdd_R';
    fixture.channels.first.gdtfFeature = 'Color.RGB';
    final archive = ZipDecoder().decodeBytes(exportGdtf(fixture));
    final description = archive.findFile('description.xml');
    expect(description, isNotNull);
    final xml = utf8.decode(description!.content as List<int>);
    expect(xml, contains('DataVersion="1.2"'));
    expect(xml, contains('Attribute Name="ColorAdd_R"'));
    expect(xml, contains('Feature="Color.RGB"'));
    expect(xml, contains('LogicalChannel Attribute="ColorAdd_R"'));
    expect(xml, contains('Position="{1,0,0,0}{0,1,0,0}{0,0,1,0}{0,0,0,1}"'));
  });

  test('links GDTF wheel ranges to declared wheel slots', () {
    final wheelFixture = FixtureProject(
      id: 'wheel-test',
      manufacturer: 'Generic',
      model: 'Wheel test',
      channels: [
        DmxChannel(
          id: 'Color wheel',
          name: 'Color wheel',
          kind: 'colorWheel',
          wheelId: 'color-wheel',
          ranges: [
            DmxRange(start: 0, end: 127, name: 'Open'),
            DmxRange(start: 128, end: 255, name: 'Red'),
          ],
        ),
      ],
      modes: [
        FixtureMode(
          id: 'mode',
          name: 'Mode',
          shortName: 'Mode',
          channelIds: ['Color wheel'],
        ),
      ],
      wheels: [
        {
          'id': 'color-wheel',
          'name': 'Color wheel',
          'kind': 'color',
          'slots': [
            {'number': 1, 'name': 'Open'},
            {'number': 2, 'name': 'Red', 'color': '#ff0000'},
          ],
        },
      ],
    );

    final archive = ZipDecoder().decodeBytes(exportGdtf(wheelFixture));
    final xml = utf8.decode(
      archive.findFile('description.xml')!.content as List<int>,
    );
    expect(xml, contains('<Wheel Name="Color wheel">'));
    expect(RegExp('Wheel="Color wheel"').allMatches(xml), hasLength(2));
    expect(xml, contains('WheelSlotIndex="1"'));
    expect(xml, contains('WheelSlotIndex="2"'));
  });

  test('ships the searchable GDTF 1.2 attribute catalog', () {
    expect(gdtfAttributeCatalog, hasLength(279));
    expect(gdtfDefinitionFor('Gobo1')?.name, 'Gobo(n)');
    expect(gdtfDefinitionFor('ColorAdd_R')?.beginnerLabel, 'Red intensity');
  });

  test('exports distinct same-size personalities to OFL and GDTF', () {
    final multiMode = fixtureFromManualText('''BETOPPER Model: COMPLEX
49AC Channel Table
1 000-255 Pan
49BC Channel Table
1 000-255 Tilt
''', 'complex.pdf').fixture;

    final ofl = jsonDecode(utf8.decode(exportOfl(multiMode))) as Map;
    final oflModes = (ofl['modes'] as List).cast<Map>();
    expect(oflModes.map((mode) => mode['name']), ['49AC', '49BC']);
    expect(
      oflModes.every((mode) => (mode['channels'] as List).length == 49),
      isTrue,
    );
    expect(
      (oflModes.first['channels'] as List).toSet().intersection(
        (oflModes.last['channels'] as List).toSet(),
      ),
      isEmpty,
    );

    final archive = ZipDecoder().decodeBytes(exportGdtf(multiMode));
    final xml = utf8.decode(
      archive.findFile('description.xml')!.content as List<int>,
    );
    expect(xml, contains('DMXMode Name="49AC"'));
    expect(xml, contains('DMXMode Name="49BC"'));
  });

  test('exports a mode over 512 channels across two DMX breaks', () {
    final manual = StringBuffer('''Martin TEST User Manual
Base DMX Mode
149 DMX channels
''');
    for (var channel = 1; channel <= 149; channel++) {
      manual.writeln('$channel Control $channel');
    }
    manual.write('''Plaid DMX Mode
851 DMX channels
Channels 1 – 149 as in Base Mode
702 channels for individual RGB control of all 234 Aura pixels
''');
    final large = fixtureFromManualText(
      manual.toString(),
      'martin-test.pdf',
    ).fixture;

    final assignments =
        ((large.toJson()['modes'] as List).last as Map)['channels'] as List;
    expect((assignments[511] as Map)['dmxBreak'], 1);
    expect((assignments[511] as Map)['offset'], 512);
    expect((assignments[512] as Map)['dmxBreak'], 2);
    expect((assignments[512] as Map)['offset'], 1);
    expect((assignments[850] as Map)['dmxBreak'], 2);
    expect((assignments[850] as Map)['offset'], 339);

    final ofl = jsonDecode(utf8.decode(exportOfl(large))) as Map;
    final oflModes = (ofl['modes'] as List).cast<Map>();
    expect(oflModes.map((mode) => mode['name']), [
      'Base',
      'Plaid — Universe 1',
      'Plaid — Universe 2',
    ]);
    expect((oflModes[1]['channels'] as List), hasLength(512));
    expect((oflModes[2]['channels'] as List), hasLength(339));

    final archive = ZipDecoder().decodeBytes(exportGdtf(large));
    final xml = utf8.decode(
      archive.findFile('description.xml')!.content as List<int>,
    );
    expect(xml, contains('DMXMode Name="Plaid"'));
    expect(xml, contains('DMXBreak="2" Offset="1"'));
    expect(xml, contains('DMXBreak="2" Offset="339"'));
  });
}
