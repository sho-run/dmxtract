import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'model.dart';

Uint8List exportProject(FixtureProject fixture) =>
    Uint8List.fromList(utf8.encode(fixture.encode()));

Uint8List exportOfl(FixtureProject fixture) {
  final channels = <String, Object?>{};
  for (final channel in fixture.channels.where((item) => item.fineOf == null)) {
    final fine = fixture.channels
        .where((item) => item.fineOf == channel.id)
        .firstOrNull;
    final ranges = _completeOflRanges(channel.ranges);
    final capabilities = <Map<String, Object?>>[
      for (final item in ranges)
        _oflCapability(
          fixture,
          channel,
          item.range,
          item.sourceIndex,
          sixteenBit: fine != null,
        ),
    ];
    final object = <String, Object?>{};
    if (capabilities.length == 1) {
      final capability = capabilities.single..remove('dmxRange');
      object['capability'] = capability;
    } else {
      object['capabilities'] = capabilities;
    }
    if (fine != null) {
      object['fineChannelAliases'] = [fine.id];
      object['dmxValueResolution'] = '16bit';
    }
    channels[channel.id] = object;
  }
  final now = DateTime.now().toIso8601String().substring(0, 10);
  final json = {
    r'$schema':
        'https://raw.githubusercontent.com/OpenLightingProject/open-fixture-library/master/schemas/fixture.json',
    'name': fixture.model,
    'shortName': fixture.model,
    'categories': [
      fixture.channels.any(
            (channel) =>
                channel.kind == 'colorIntensity' ||
                channel.kind == 'colorWheel',
          )
          ? 'Color Changer'
          : 'Other',
    ],
    'meta': {
      'authors': ['DMXtract'],
      'createDate': now,
      'lastModifyDate': now,
    },
    'availableChannels': channels,
    'modes': [
      for (final mode in fixture.modes)
        for (var dmxBreak = 1; dmxBreak <= mode.breaks; dmxBreak++)
          if (mode.channelIds.skip((dmxBreak - 1) * 512).take(512).isNotEmpty)
            {
              'name': mode.breaks == 1
                  ? mode.name
                  : '${mode.name} — Universe $dmxBreak',
              'shortName': mode.breaks == 1
                  ? mode.shortName
                  : '${mode.shortName} U$dmxBreak',
              'channels': mode.channelIds
                  .skip((dmxBreak - 1) * 512)
                  .take(512)
                  .toList(),
            },
    ],
    if (fixture.wheels.isNotEmpty) 'wheels': _oflWheels(fixture.wheels),
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

List<({DmxRange range, int? sourceIndex})> _completeOflRanges(
  List<DmxRange> source,
) {
  if (source.isEmpty) {
    return [
      (
        range: DmxRange(start: 0, end: 255, name: 'Full range'),
        sourceIndex: null,
      ),
    ];
  }
  final indexed = source.indexed.toList()
    ..sort((left, right) => left.$2.start.compareTo(right.$2.start));
  final output = <({DmxRange range, int? sourceIndex})>[];
  var next = 0;
  for (final item in indexed) {
    if (item.$2.end < next || item.$2.start > 255) continue;
    final start = item.$2.start.clamp(next, 255);
    final end = item.$2.end.clamp(start, 255);
    if (start > next) {
      output.add((
        range: DmxRange(start: next, end: start - 1, name: 'Unspecified'),
        sourceIndex: null,
      ));
    }
    output.add((
      range: DmxRange(
        start: start,
        end: end,
        name: item.$2.name,
        safety: item.$2.safety,
        confidence: item.$2.confidence,
      ),
      sourceIndex: item.$1,
    ));
    next = end + 1;
    if (next > 255) break;
  }
  if (next <= 255) {
    output.add((
      range: DmxRange(start: next, end: 255, name: 'Unspecified'),
      sourceIndex: null,
    ));
  }
  return output;
}

Map<String, Object?> _oflCapability(
  FixtureProject fixture,
  DmxChannel channel,
  DmxRange range,
  int? sourceIndex, {
  required bool sixteenBit,
}) {
  final dmxRange = sixteenBit
      ? [
          range.start * 257,
          range.end == 255 ? 65535 : (range.end + 1) * 257 - 1,
        ]
      : [range.start, range.end];
  final capability = <String, Object?>{
    'dmxRange': dmxRange,
    'type': 'Generic',
    'comment': range.name.isEmpty ? channel.name : range.name,
  };
  if (channel.kind == 'intensity') {
    capability['type'] = 'Intensity';
  } else if (channel.kind == 'colorIntensity') {
    capability['type'] = 'ColorIntensity';
    capability['color'] = _oflColor(channel.color);
  } else if (channel.kind == 'strobe' &&
      (channel.ranges.length > 1 ||
          channel.ranges.any((item) => item.start > 0 || item.end < 255))) {
    capability['type'] = 'ShutterStrobe';
    capability['shutterEffect'] = sourceIndex == null
        ? 'Closed'
        : _oflShutterEffect(range.name);
  } else if (channel.kind == 'maintenance') {
    capability['type'] = 'Maintenance';
  } else if (channel.kind == 'prism') {
    capability['type'] = 'Prism';
  } else if ((channel.kind == 'colorWheel' || channel.kind == 'goboWheel') &&
      channel.wheelId != null &&
      sourceIndex != null) {
    final wheel = fixture.wheels
        .where((item) => item['id'] == channel.wheelId)
        .firstOrNull;
    final slots = wheel?['slots'] as List?;
    if (slots != null && sourceIndex < slots.length) {
      capability['type'] = 'WheelSlot';
      capability['wheel'] = channel.wheelId;
      capability['slotNumber'] = sourceIndex + 1;
    }
  }
  return capability;
}

String _oflColor(String? color) => switch (color) {
  'RED' => 'Red',
  'GREEN' => 'Green',
  'BLUE' => 'Blue',
  'CYAN' => 'Cyan',
  'MAGENTA' => 'Magenta',
  'YELLOW' => 'Yellow',
  'AMBER' => 'Amber',
  'UV' => 'UV',
  'LIME' => 'Lime',
  'INDIGO' => 'Indigo',
  _ => 'White',
};

String _oflShutterEffect(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('off') ||
      lower.contains('closed') ||
      lower.contains('void') ||
      lower.contains('no function')) {
    return 'Closed';
  }
  if (lower.contains('on') || lower.contains('open')) return 'Open';
  return 'Strobe';
}

Map<String, Object?> _oflWheels(List<Map<String, Object?>> wheels) => {
  for (final wheel in wheels)
    wheel['id'] as String: {
      'slots': [
        for (final rawSlot in wheel['slots'] as List)
          _oflWheelSlot(
            Map<String, Object?>.from(rawSlot as Map),
            wheel['kind'] as String,
          ),
      ],
    },
};

Map<String, Object?> _oflWheelSlot(Map<String, Object?> slot, String kind) {
  final name = slot['name'] as String? ?? 'Unknown';
  if ((slot['number'] == 1 || name.toLowerCase().contains('open')) &&
      name.toLowerCase().contains(RegExp(r'open|white'))) {
    return {'type': 'Open'};
  }
  return {
    'type': kind == 'color'
        ? 'Color'
        : kind == 'prism'
        ? 'Prism'
        : 'Gobo',
    'name': name,
    if (kind == 'color' && slot['color'] != null) 'colors': [slot['color']],
  };
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
    '    <Geometries><Geometry Name="Body" Model="GenericBody" Position="{1,0,0,0}{0,1,0,0}{0,0,1,0}{0,0,0,1}"><Beam Name="Beam" Model="" Position="{1,0,0,0}{0,1,0,0}{0,0,1,0}{0,0,0,1}" LampType="LED" PowerConsumption="${fixture.physical['powerW'] ?? 0}" LuminousFlux="0" ColorTemperature="6500" BeamAngle="${fixture.physical['lensMaxDegrees'] ?? 25}" FieldAngle="${fixture.physical['lensMaxDegrees'] ?? 25}" BeamRadius="0.05" BeamType="Wash" ColorRenderingIndex="90" EmitterSpectrum=""/></Geometry></Geometries><DMXModes>',
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
      final dmxBreak = index ~/ 512 + 1;
      final localOffset = index % 512 + 1;
      final fineIndex = fine == null ? -1 : mode.channelIds.indexOf(fine.id);
      final fineIsOnSameBreak =
          fineIndex >= 0 && fineIndex ~/ 512 + 1 == dmxBreak;
      final offset = fineIsOnSameBreak
          ? '$localOffset,${fineIndex % 512 + 1}'
          : '$localOffset';
      xml.writeln(
        '        <DMXChannel DMXBreak="$dmxBreak" Offset="$offset" Default="0/1" Highlight="None" Geometry="Beam" InitialFunction="${_x(mode.name)}.${_x(channel.name)}.${_x(channel.name)}"><LogicalChannel Attribute="${_x(_channelAttribute(channel))}" Snap="No" Master="None" MibFade="0" DMXChangeTimeLimit="0">',
      );
      final ranges = channel.ranges.isEmpty
          ? [DmxRange(start: 0, end: 255, name: channel.name)]
          : channel.ranges;
      final wheel = channel.wheelId == null
          ? null
          : fixture.wheels
                .where((item) => item['id'] == channel.wheelId)
                .firstOrNull;
      final wheelSlots = wheel?['slots'] as List?;
      for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
        final range = ranges[rangeIndex];
        final hasWheelSlot =
            wheel != null &&
            wheelSlots != null &&
            rangeIndex < wheelSlots.length;
        final wheelName = hasWheelSlot ? wheel['name'] as String : '';
        final wheelSlotAttribute = hasWheelSlot
            ? ' WheelSlotIndex="${rangeIndex + 1}"'
            : '';
        xml.writeln(
          '          <ChannelFunction Name="${_x(range.name)}" Attribute="${_x(_channelAttribute(channel))}" OriginalAttribute="${_x(channel.name)}" DMXFrom="${range.start}/1" Default="0/1" PhysicalFrom="0" PhysicalTo="1" RealFade="0" RealAcceleration="0" Wheel="${_x(wheelName)}" Emitter="" Filter="" ColorSpace="" Gamut="" ModeMaster="None" ModeFrom="0/1" ModeTo="255/1"><ChannelSet Name="${_x(range.name)}" DMXFrom="${range.start}/1" PhysicalFrom="${range.start}" PhysicalTo="${range.end}"$wheelSlotAttribute/></ChannelFunction>',
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
