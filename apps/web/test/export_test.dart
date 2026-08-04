import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:dmxtract_web/src/export_service.dart';
import 'package:dmxtract_web/src/extraction_rules.dart';
import 'package:dmxtract_web/src/gdtf_attribute_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = fixtureFromManualText(
    'BETOPPER Model: LB150 12CH Pan Pan fine Tilt Tilt fine PAN/TILT speed Dimming Light switch/strobe Color wheel Gobo wheel Prism Reserved Channel Reset/Function Channel',
    'LB150.pdf',
  ).fixture;
  test('exports OFL-shaped JSON', () {
    final json = jsonDecode(utf8.decode(exportOfl(fixture))) as Map;
    expect(json['name'], 'LB150');
    expect((json['modes'] as List).single['channels'], hasLength(12));
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
}
