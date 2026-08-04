import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'model.dart';

Uint8List exportProject(FixtureProject fixture) =>
    Uint8List.fromList(utf8.encode(fixture.encode()));

Uint8List exportOfl(FixtureProject fixture) {
  final channels = <String, Object?>{};
  for (final channel in fixture.channels.where((item) => item.fineOf == null)) {
    channels[channel.id] = {
      'capabilities': channel.ranges
          .map(
            (range) => {
              'dmxRange': [range.start, range.end],
              'type': _oflType(channel.kind),
              'comment': range.name,
            },
          )
          .toList(),
      if (fixture.channels.any((item) => item.fineOf == channel.id))
        'fineChannelAliases': [
          fixture.channels.firstWhere((item) => item.fineOf == channel.id).id,
        ],
    };
  }
  final now = DateTime.now().toIso8601String().substring(0, 10);
  final json = {
    r'$schema':
        'https://raw.githubusercontent.com/OpenLightingProject/open-fixture-library/master/schemas/fixture.json',
    'name': fixture.model,
    'shortName': fixture.model,
    'categories': <String>[],
    'meta': {
      'authors': ['DMXtract'],
      'createDate': now,
      'lastModifyDate': now,
    },
    'availableChannels': channels,
    'modes': [
      for (final mode in fixture.modes)
        {
          'name': mode.name,
          'shortName': mode.shortName,
          'channels': mode.channelIds,
        },
    ],
    r'$dmxtract': {
      'manufacturer': fixture.manufacturer,
      'source': fixture.sourceName,
      'verification': 'extracted from manual',
      'schemaVersion': 1,
    },
    if (fixture.physical.isNotEmpty)
      'physical': {
        'dimensions': [
          fixture.physical['widthMm'],
          fixture.physical['heightMm'],
          fixture.physical['depthMm'],
        ],
        'weight': fixture.physical['weightKg'],
        'power': fixture.physical['powerW'],
      },
  };
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
  );
}

Uint8List exportGdtf(FixtureProject fixture) {
  final xml = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>\n<GDTF DataVersion="1.2">\n',
  );
  xml.writeln(
    '  <FixtureType Name="${_x(fixture.model)}" ShortName="${_x(fixture.model)}" LongName="${_x('${fixture.manufacturer} ${fixture.model}')}" Manufacturer="${_x(fixture.manufacturer)}" Description="Generated locally by DMXtract; extracted from manual" FixtureTypeID="${_fixtureUuid(fixture.id)}" RefFT="">',
  );
  final features = <String, Set<String>>{};
  for (final channel in fixture.channels.where((item) => item.fineOf == null)) {
    final parts = _channelFeature(channel).split('.');
    features
        .putIfAbsent(parts.first, () => <String>{})
        .add(parts.length > 1 ? parts[1] : 'Control');
  }
  xml.writeln('    <AttributeDefinitions><ActivationGroups/><FeatureGroups>');
  for (final entry in features.entries) {
    xml.write(
      '      <FeatureGroup Name="${_x(entry.key)}" Pretty="${_x(entry.key)}">',
    );
    for (final feature in entry.value) {
      xml.write('<Feature Name="${_x(feature)}"/>');
    }
    xml.writeln('</FeatureGroup>');
  }
  xml.writeln('    </FeatureGroups><Attributes>');
  final declaredAttributes = <String>{};
  for (final channel in fixture.channels.where((item) => item.fineOf == null)) {
    final attribute = _channelAttribute(channel);
    if (!declaredAttributes.add(attribute)) continue;
    xml.writeln(
      '      <Attribute Name="${_x(attribute)}" Pretty="${_x(channel.name)}" Feature="${_x(_channelFeature(channel))}" PhysicalUnit="None" Color="0.3127,0.3290,100.0"/>',
    );
  }
  xml.writeln('    </Attributes></AttributeDefinitions><Wheels>');
  for (final wheel in fixture.wheels) {
    xml.writeln('      <Wheel Name="${_x(wheel['name'] as String)}">');
    for (final slot in wheel['slots'] as List) {
      xml.writeln(
        '        <Slot Name="${_x((slot as Map)['name'] as String)}" Color="0.3127,0.3290,100.0" MediaFileName=""/>',
      );
    }
    xml.writeln('      </Wheel>');
  }
  xml.writeln(
    '    </Wheels><PhysicalDescriptions><Emitters/><Filters/><ColorSpace Mode="sRGB" Description="Generic sRGB"/><DMXProfiles/><CRIs/><Connectors/></PhysicalDescriptions>',
  );
  xml.writeln(
    '    <Models><Model Name="GenericBody" Length="0.3" Width="0.3" Height="0.3" PrimitiveType="Cube" File=""/></Models>',
  );
  xml.writeln(
    '    <Geometries><Geometry Name="Body" Model="GenericBody" Position="1,0,0,0,1,0,0,0,1,0,0,0"><Beam Name="Beam" Model="" Position="1,0,0,0,1,0,0,0,1,0,0,0" LampType="LED" PowerConsumption="${fixture.physical['powerW'] ?? 0}" LuminousFlux="0" ColorTemperature="6500" BeamAngle="${fixture.physical['lensMaxDegrees'] ?? 25}" FieldAngle="${fixture.physical['lensMaxDegrees'] ?? 25}" BeamRadius="0.05" BeamType="Wash" ColorRenderingIndex="90" EmitterSpectrum=""/></Geometry></Geometries><DMXModes>',
  );
  for (final mode in fixture.modes) {
    xml.writeln(
      '      <DMXMode Name="${_x(mode.name)}" Description="${mode.channelIds.length} controls" Geometry="Body"><DMXChannels>',
    );
    for (var index = 0; index < mode.channelIds.length; index++) {
      final channel = fixture.channels.firstWhere(
        (item) => item.id == mode.channelIds[index],
      );
      if (channel.fineOf != null) continue;
      final fine = fixture.channels
          .where((item) => item.fineOf == channel.id)
          .firstOrNull;
      final offset = fine == null
          ? '${index + 1}'
          : '${index + 1},${mode.channelIds.indexOf(fine.id) + 1}';
      xml.writeln(
        '        <DMXChannel DMXBreak="1" Offset="$offset" Default="0/1" Highlight="None" Geometry="Beam" InitialFunction="${_x(mode.name)}.${_x(channel.name)}.${_x(channel.name)}"><LogicalChannel Attribute="${_x(_channelAttribute(channel))}" Snap="No" Master="None" MibFade="0" DMXChangeTimeLimit="0">',
      );
      final ranges = channel.ranges.isEmpty
          ? [DmxRange(start: 0, end: 255, name: channel.name)]
          : channel.ranges;
      for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
        final range = ranges[rangeIndex];
        xml.writeln(
          '          <ChannelFunction Name="${_x(range.name)}" Attribute="${_x(_channelAttribute(channel))}" OriginalAttribute="${_x(channel.name)}" DMXFrom="${range.start}/1" Default="0/1" PhysicalFrom="0" PhysicalTo="1" RealFade="0" RealAcceleration="0" Wheel="" Emitter="" Filter="" ColorSpace="" Gamut="" ModeMaster="None" ModeFrom="0/1" ModeTo="255/1"><ChannelSet Name="${_x(range.name)}" DMXFrom="${range.start}/1" PhysicalFrom="${range.start}" PhysicalTo="${range.end}" WheelSlotIndex="${rangeIndex + 1}"/></ChannelFunction>',
        );
      }
      xml.writeln('        </LogicalChannel></DMXChannel>');
    }
    xml.writeln('      </DMXChannels><Relations/><FTMacros/></DMXMode>');
  }
  xml.writeln(
    '    </DMXModes><Revisions/><Presets/><Protocols/></FixtureType></GDTF>',
  );
  final content = utf8.encode(xml.toString());
  final archive = Archive()
    ..addFile(ArchiveFile('description.xml', content.length, content));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _oflType(String kind) => switch (kind) {
  'intensity' => 'Intensity',
  'pan' => 'Pan',
  'tilt' => 'Tilt',
  'strobe' => 'ShutterStrobe',
  'colorWheel' || 'goboWheel' || 'prism' => 'WheelSlot',
  'speed' => 'Speed',
  'maintenance' => 'Maintenance',
  _ => 'Generic',
};
String _feature(String kind) => switch (kind) {
  'intensity' => 'Dimmer.Dimmer',
  'pan' || 'tilt' => 'Position.PanTilt',
  'colorIntensity' => 'Color.RGB',
  'colorWheel' => 'Color.Color',
  'goboWheel' => 'Gobo.Gobo',
  'prism' => 'Beam.Beam',
  'focus' || 'zoom' => 'Focus.Focus',
  _ => 'Control.Control',
};
String _attr(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
String _channelAttribute(DmxChannel channel) {
  final value = channel.gdtfAttribute?.trim();
  return value == null || value.isEmpty ? _attr(channel.name) : value;
}

String _channelFeature(DmxChannel channel) {
  final value = channel.gdtfFeature?.trim();
  return value == null || value.isEmpty ? _feature(channel.kind) : value;
}

String _x(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
String _fixtureUuid(String id) {
  final hash = id.codeUnits.fold<int>(
    0x811c9dc5,
    (value, unit) => ((value ^ unit) * 0x01000193) & 0xffffffff,
  );
  return '${hash.toRadixString(16).padLeft(8, '0')}-d4d8-5a1c-8f11-${(hash * 2654435761 & 0xffffffffffff).toRadixString(16).padLeft(12, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
