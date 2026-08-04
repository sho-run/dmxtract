import 'model.dart';

class ExtractionResult {
  const ExtractionResult({required this.fixture, required this.questions});
  final FixtureProject fixture;
  final List<String> questions;
}

ExtractionResult fixtureFromManualText(String text, String sourceName) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  final numberedModelMatch = RegExp(
    r'(?:Model\s*:?\s*|moving.head[^A-Z0-9]{0,30})([A-Z]{1,6}[- ]?\d{2,5}[A-Z]?)',
    caseSensitive: false,
  ).firstMatch(flat);
  final titledModelMatch = RegExp(
    r'\b([A-Z][A-Za-z0-9_-]{2,30})[™®]?\s+(?:user|owner.?s?)\s+manual\b',
    caseSensitive: false,
  ).firstMatch(flat);
  final modelFromManual =
      numberedModelMatch?.group(1)?.replaceAll(' ', '') ??
      titledModelMatch?.group(1);
  final fallback = _modelFromFilename(sourceName);
  final model = modelFromManual ?? fallback ?? 'Unknown fixture';
  final manufacturerFromManual = _manufacturer(flat);
  final manufacturer = manufacturerFromManual == 'Unknown manufacturer'
      ? _manufacturer(sourceName)
      : manufacturerFromManual;
  final modeCounts = <int>[];
  for (final match in RegExp(
    r'(?<![A-Za-z0-9])(\d{1,3})\s*[-–]?\s*(?:CH|channel(?:s| mode)?)(?![A-Za-z])',
    caseSensitive: false,
  ).allMatches(flat)) {
    final value = int.tryParse(match.group(1)!);
    if (value != null &&
        value > 0 &&
        value <= 512 &&
        !modeCounts.contains(value)) {
      modeCounts.add(value);
    }
  }
  const numberWords = {
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
  };
  for (final match in RegExp(
    r'uses\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+DMX\s+channels?',
    caseSensitive: false,
  ).allMatches(flat)) {
    final value = numberWords[match.group(1)!.toLowerCase()]!;
    if (!modeCounts.contains(value)) modeCounts.add(value);
  }
  final tableCount = _tableChannelCount(text);
  if (tableCount >= 4) {
    final looksLikeMatrix = RegExp(
      r'(matrix|pixel|cell)',
      caseSensitive: false,
    ).hasMatch(flat);
    if (modeCounts.isEmpty) {
      modeCounts.add(tableCount);
    } else if (!looksLikeMatrix &&
        modeCounts.length == 1 &&
        modeCounts.single > tableCount * 2) {
      modeCounts[0] = tableCount;
    } else if (!modeCounts.contains(tableCount)) {
      modeCounts.add(tableCount);
    }
  }
  final positionFine = _has(
    flat,
    r'(pan\s+fine|tilt\s+fine|[xy][ -]?axis\s+fine|16[ -]?bit(?:\s+precision)?\s+scan)',
  );
  final known = <_DetectedChannel>[
    if (_has(flat, r'\bpan\b'))
      const _DetectedChannel(name: 'Pan', kind: 'pan'),
    if (_has(flat, r'\bpan\b') && positionFine)
      const _DetectedChannel(name: 'Pan fine', kind: 'pan', fineOf: 'pan'),
    if (_has(flat, r'\btilt\b'))
      const _DetectedChannel(name: 'Tilt', kind: 'tilt'),
    if (_has(flat, r'\btilt\b') && positionFine)
      const _DetectedChannel(name: 'Tilt fine', kind: 'tilt', fineOf: 'tilt'),
    if (_has(flat, r'((pan.?tilt|x.?y)\s+speed|speed\s+from\s+100)'))
      const _DetectedChannel(name: 'Pan / tilt speed', kind: 'speed'),
    if (_has(flat, r'dimm(?:ing|er)'))
      const _DetectedChannel(name: 'Dimmer', kind: 'intensity'),
    if (_has(flat, r'(light switch.?strobe|\bstrobe\b)'))
      const _DetectedChannel(name: 'Light switch / strobe', kind: 'strobe'),
    if (_has(flat, r'color wheel'))
      const _DetectedChannel(name: 'Color wheel', kind: 'colorWheel'),
    if (_has(flat, r'gobo wheel'))
      const _DetectedChannel(name: 'Gobo wheel', kind: 'goboWheel'),
    if (_has(flat, r'\bprism\b'))
      const _DetectedChannel(name: 'Prism', kind: 'prism'),
    if (_has(flat, r'reserved channel'))
      const _DetectedChannel(name: 'Reserved', kind: 'generic'),
    if (_has(flat, r'reset.?function channel'))
      const _DetectedChannel(name: 'Reset / function', kind: 'maintenance'),
  ];
  if (!_has(flat, r'color wheel')) {
    _addColorComponents(known, flat);
  }
  final usableModes = modeCounts.take(8).toList();
  final hasDmxTable = RegExp(
    r'(channel value table|dmx channel assignments(?: and values)?|dmx charts?|dmx traits|dmx channels?\s*[:\-]?\s*\d)',
    caseSensitive: false,
  ).hasMatch(flat);
  final count = usableModes.isNotEmpty
      ? usableModes.reduce((a, b) => a > b ? a : b)
      : hasDmxTable
      ? known.length
      : 0;
  final channels = <DmxChannel>[];
  final tableChannels = _tableChannels(text, count);
  final useTableChannels =
      tableChannels.length >= 4 && tableChannels.length >= (count * .5).ceil();
  final isLb150 =
      model.toLowerCase().contains('lb150') ||
      _has(flat, r'5600\s*k.*grass\s+green.*reset.?function');
  for (var index = 0; index < count; index++) {
    final definition = useTableChannels && index < tableChannels.length
        ? tableChannels[index]
        : index < known.length
        ? known[index]
        : _DetectedChannel(name: 'Channel ${index + 1}', kind: 'generic');
    var channelId = slug(definition.name);
    if (channels.any((item) => item.id == channelId)) {
      channelId = '$channelId-${index + 1}';
    }
    channels.add(
      DmxChannel(
        id: channelId,
        name: definition.name,
        kind: definition.kind,
        fineOf: definition.fineOf,
        color: definition.color,
        confidence:
            definition.kind == 'generic' &&
                definition.name.startsWith('Channel ')
            ? .35
            : .9,
        ranges: definition.ranges?.isNotEmpty == true
            ? definition.ranges!
            : _knownRanges(definition.kind, isLb150: isLb150),
      ),
    );
  }
  final wheels = <Map<String, Object?>>[];
  if (known.any((item) => item.kind == 'colorWheel')) {
    final isLb150Wheel = _has(
      flat,
      r'5600\s*k.*3200\s*k.*grass\s+green.*rose\s+red',
    );
    final slotCount = _wheelSlotCount(flat, 'color');
    final labels = isLb150Wheel
        ? const [
            'White',
            '5600K',
            '3200K',
            'Cyan',
            'Grass green',
            'Light blue',
            'Rose red',
            'Orange',
            'Yellow',
            'Blue',
            'Green',
            'Red',
          ]
        : [
            'Open / white',
            for (var index = 1; index < (slotCount ?? 2); index++)
              'Unknown color slot $index',
          ];
    wheels.add(
      _wheel(
        'color-wheel',
        'Color wheel',
        'color',
        labels,
        isLb150Wheel ? .72 : .35,
      ),
    );
    channels
        .where((item) => item.kind == 'colorWheel')
        .forEach((item) => item.wheelId = 'color-wheel');
  }
  if (known.any((item) => item.kind == 'goboWheel')) {
    final goboCount = _wheelSlotCount(flat, 'gobo');
    wheels.add(
      _wheel('gobo-wheel', 'Gobo wheel', 'gobo', [
        'Open',
        for (var index = 1; index <= (goboCount ?? 1); index++)
          'Unknown gobo $index',
      ], .35),
    );
    channels
        .where((item) => item.kind == 'goboWheel')
        .forEach((item) => item.wheelId = 'gobo-wheel');
  }
  final simplestMode = usableModes.isEmpty
      ? count
      : usableModes.reduce((a, b) => a < b ? a : b);
  final fixture = FixtureProject(
    id: '${slug(manufacturer)}-${slug(model)}',
    manufacturer: manufacturer,
    model: model,
    sourceName: sourceName,
    identityFromManual:
        modelFromManual != null &&
        manufacturerFromManual != 'Unknown manufacturer',
    channels: channels,
    modes: [
      for (final modeSize
          in count == 0
              ? <int>[]
              : usableModes.isEmpty
              ? [count]
              : usableModes)
        FixtureMode(
          id: 'mode-$modeSize',
          name: modeSize == count
              ? 'Full control'
              : modeSize == simplestMode
              ? 'Simple'
              : '$modeSize-channel mode',
          shortName: '${modeSize}ch',
          channelIds: channels.take(modeSize).map((item) => item.id).toList(),
          breaks: (modeSize / 512).ceil().clamp(1, 64),
        ),
    ],
    wheels: wheels,
    physical: flat.contains('236x174x329')
        ? {
            'widthMm': 236.0,
            'heightMm': 329.0,
            'depthMm': 174.0,
            'weightKg': 4.6,
            'powerW': 150.0,
            'lensMinDegrees': 1.72,
            'lensMaxDegrees': 1.72,
          }
        : {},
  );
  final questions = <String>[
    if (channels.isEmpty &&
        RegExp(
          r'(phase cut|triac dimmer|mains dim)',
          caseSensitive: false,
        ).hasMatch(flat))
      'This manual describes a mains-dimmed light, not a DMX-controlled fixture.',
    if (channels.isEmpty &&
        !RegExp(
          r'(phase cut|triac dimmer|mains dim)',
          caseSensitive: false,
        ).hasMatch(flat))
      'We could not find a DMX channel table in this manual.',
    if (manufacturer.startsWith('Unknown')) 'We could not find the maker name.',
    if (model.startsWith('Unknown')) 'We could not find the model name.',
    ...channels
        .where((item) => item.confidence < .6)
        .take(3)
        .map(
          (item) =>
              'Check what channel ${channels.indexOf(item) + 1} controls.',
        ),
    if (wheels.any(
      (wheel) =>
          wheel['kind'] == 'color' &&
          ((wheel['confidence'] as Map)['score'] as num) < .6,
    ))
      'We found a color wheel, but its colors need a quick check.',
    if (wheels.any((wheel) => wheel['kind'] == 'gobo'))
      'We found a gobo wheel, but its pictures need a quick check.',
    if (channels.any((item) => item.kind == 'maintenance'))
      'The reset channel stays locked during testing.',
  ];
  return ExtractionResult(fixture: fixture, questions: questions);
}

bool _has(String text, String pattern) =>
    RegExp(pattern, caseSensitive: false).hasMatch(text);
String _manufacturer(String value) {
  final lower = value.toLowerCase();
  if (lower.contains('betopper')) return 'Betopper';
  if (lower.contains('shehds')) return 'SHEHDS';
  if (lower.contains('chauvet')) return 'Chauvet DJ';
  if (lower.contains('altman')) return 'Altman';
  if (RegExp(r'(^|[^a-z])adj([^a-z]|$)').hasMatch(lower)) return 'ADJ';
  return 'Unknown manufacturer';
}

String? _modelFromFilename(String name) {
  var value = name
      .replaceAll(RegExp(r'\.[^.]+$'), '')
      .replaceFirst(RegExp(r'^[a-f0-9]{32,}_', caseSensitive: false), '');
  value = value
      .replaceAll(
        RegExp(
          r'(user[_ -]?manual|dmx[_ -]?traits|manual|说明书)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'^(adj|chauvet|shehds|betopper|altman)[_ @-]*',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'[_-]{2,}'), ' ')
      .replaceAll('_', ' ')
      .trim();
  final tokens = RegExp(
    r'\b[A-Za-z]{1,8}[- ]?\d{2,5}[A-Za-z]?\b',
  ).allMatches(value).map((match) => match.group(0)!.replaceAll(' ', ''));
  if (tokens.isNotEmpty) return tokens.first;
  return value.isEmpty ? null : value;
}

int _tableChannelCount(String text) {
  final markers = RegExp(
    r'(channel value table|dmx channel assignments(?: and values)?|dmx charts?|dmx traits)',
    caseSensitive: false,
  ).allMatches(text);
  var best = 0;
  for (final marker in markers) {
    final section = text.substring(
      marker.start,
      (marker.start + 30000).clamp(0, text.length),
    );
    final values = <int>{};
    for (final match in RegExp(
      r'^\s*(\d{1,3})\s+(?:(?:0{1,3}\s*[-–]\s*\d{1,3})|[A-Za-z][A-Za-z /&_-]{2,})',
      multiLine: true,
    ).allMatches(section)) {
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > 0 && value <= 512) values.add(value);
    }
    var count = 0;
    while (values.contains(count + 1)) {
      count++;
    }
    if (count > best) best = count;
  }
  return best;
}

int? _wheelSlotCount(String text, String kind) {
  final patterns = kind == 'color'
      ? [
          r'(\d{1,2})\s+(?:fixed\s+)?colors?',
          r'color\s+wheel[^.]{0,80}?(\d{1,2})\s+(?:colors?|slots?)',
        ]
      : [
          r'(\d{1,2})\s+(?:fixed\s+|static\s+|rotating\s+)?gobos?',
          r'gobo\s+wheel[^.]{0,80}?(\d{1,2})\s+(?:gobos?|patterns?|slots?)',
          r'(\d{1,2})\s+(?:gobo\s+)?patterns?',
        ];
  for (final pattern in patterns) {
    final match = RegExp(pattern, caseSensitive: false).firstMatch(text);
    final count = int.tryParse(match?.group(1) ?? '');
    if (count != null && count >= 2 && count <= 64) return count;
  }
  return null;
}

Map<String, Object?> _wheel(
  String id,
  String name,
  String kind,
  List<String> labels,
  double confidence,
) => {
  'id': id,
  'name': name,
  'kind': kind,
  'slots': [
    for (var i = 0; i < labels.length; i++)
      {
        'number': i + 1,
        'name': labels[i],
        'color': null,
        'mediaFile': null,
        'confidence': {
          'score': i == 0 ? .95 : confidence,
          'reason': i == 0 ? '' : 'Check this slot on the real light',
        },
        'source': null,
      },
  ],
  'confidence': {
    'score': confidence,
    'reason': 'Slot order should be checked on the fixture',
  },
};

class _DetectedChannel {
  const _DetectedChannel({
    required this.name,
    required this.kind,
    this.fineOf,
    this.color,
    this.ranges,
  });

  final String name;
  final String kind;
  final String? fineOf;
  final String? color;
  final List<DmxRange>? ranges;
}

void _addColorComponents(List<_DetectedChannel> channels, String text) {
  final compact = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').toUpperCase();
  final joined = compact.replaceAll(' ', '');
  final signature = RegExp(
    r'RGB(?:W)?(?:A)?(?:UV)?',
  ).firstMatch(joined)?.group(0);
  if (signature == null) return;
  channels.addAll(const [
    _DetectedChannel(name: 'Red', kind: 'colorIntensity', color: 'RED'),
    _DetectedChannel(name: 'Green', kind: 'colorIntensity', color: 'GREEN'),
    _DetectedChannel(name: 'Blue', kind: 'colorIntensity', color: 'BLUE'),
  ]);
  if (signature.contains('W')) {
    channels.add(
      const _DetectedChannel(
        name: 'White',
        kind: 'colorIntensity',
        color: 'WHITE',
      ),
    );
  }
  if (signature.contains('A')) {
    channels.add(
      const _DetectedChannel(
        name: 'Amber',
        kind: 'colorIntensity',
        color: 'AMBER',
      ),
    );
  }
  if (signature.contains('UV')) {
    channels.add(
      const _DetectedChannel(name: 'UV', kind: 'colorIntensity', color: 'UV'),
    );
  }
}

List<_DetectedChannel> _tableChannels(String text, int count) {
  if (count == 0) return const [];
  final markers = RegExp(
    r'(channel value table|dmx channel assignments(?: and values)?|dmx charts?|dmx traits)',
    caseSensitive: false,
  ).allMatches(text);
  var best = <_DetectedChannel>[];
  for (final marker in markers) {
    final section = text.substring(
      marker.start,
      (marker.start + 30000).clamp(0, text.length),
    );
    final detected = _parseTableSection(section, count);
    if (detected.length >= best.length) best = detected;
  }
  return best;
}

List<_DetectedChannel> _parseTableSection(String section, int count) {
  final detected = <_DetectedChannel>[];
  final pendingRanges = <DmxRange>[];
  var expected = 1;
  for (final line in section.split(RegExp(r'[\r\n]+'))) {
    final match = RegExp(r'^\s*(\d{1,3})\s+(.+?)\s*$').firstMatch(line);
    if (match != null && int.tryParse(match.group(1)!) == expected) {
      var description = match.group(2)!;
      description = description.replaceAll(RegExp(r'\s+'), ' ').trim();
      final base = _classifyTableChannel(description, expected);
      final ranges = <DmxRange>[
        ...pendingRanges,
        ..._rangesFromLine(description, base.name, base.kind),
      ]..sort((a, b) => a.start.compareTo(b.start));
      pendingRanges.clear();
      detected.add(
        _DetectedChannel(
          name: base.name,
          kind: base.kind,
          fineOf: base.fineOf,
          color: base.color,
          ranges: ranges,
        ),
      );
      expected++;
      if (expected > count) break;
      continue;
    }
    final ranges = _rangesFromLine(
      line,
      detected.isEmpty ? 'Channel $expected' : detected.last.name,
      detected.isEmpty ? 'generic' : detected.last.kind,
    );
    if (ranges.isEmpty) continue;
    if (detected.isEmpty ||
        _rangesCoverFull(detected.last.ranges ?? const [])) {
      pendingRanges.addAll(ranges);
    } else {
      detected.last.ranges!.addAll(ranges);
      detected.last.ranges!.sort((a, b) => a.start.compareTo(b.start));
    }
  }
  return detected;
}

List<DmxRange> _rangesFromLine(String value, String channelName, String kind) {
  final ranges = <DmxRange>[];
  final pattern = RegExp(r'\b(\d{1,3})\s*[-–—↔⇔ó]\s*(\d{1,3})\b');
  for (final match in pattern.allMatches(value)) {
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null || end == null || start > end || end > 255) continue;
    final trailing = value.substring(match.end).trim();
    if (trailing.startsWith('%')) continue;
    var label = trailing
        .replaceFirst(RegExp(r'^\d{1,3}\s*[-–—↔⇔ó]\s*\d{1,3}%\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (label.isEmpty || RegExp(r'^\d{1,3}%$').hasMatch(label)) {
      label = switch (kind) {
        'intensity' => 'Brightness',
        'colorIntensity' => '$channelName intensity',
        _ => 'Full range',
      };
    }
    final lower = label.toLowerCase();
    ranges.add(
      DmxRange(
        start: start,
        end: end,
        name: label.substring(0, label.length.clamp(0, 80)),
        safety: kind == 'strobe' && !lower.contains('no function')
            ? 'strobe'
            : kind == 'maintenance' && lower.contains('reset')
            ? 'reset'
            : 'normal',
        confidence: .9,
      ),
    );
    break;
  }
  return ranges;
}

bool _rangesCoverFull(List<DmxRange> ranges) {
  if (ranges.isEmpty) return false;
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  var end = -1;
  for (final range in sorted) {
    if (range.start > end + 1) return false;
    if (range.end > end) end = range.end;
  }
  return end >= 255;
}

_DetectedChannel _classifyTableChannel(String value, int channel) {
  final withoutModeColumns = value.replaceFirst(
    RegExp(r'^(?:(?:\d{1,3}|-)\s+){1,6}'),
    '',
  );
  final lower = withoutModeColumns.toLowerCase();
  if (RegExp(r'(pan.?tilt|x.?y).*(speed|time)').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan / tilt speed', kind: 'speed');
  }
  if (RegExp(r'pan\s*(fine|16.?bit|least)').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan fine', kind: 'pan', fineOf: 'pan');
  }
  if (RegExp(r'tilt\s*(fine|16.?bit|least)').hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Tilt fine',
      kind: 'tilt',
      fineOf: 'tilt',
    );
  }
  if (RegExp(r'\bpan\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan', kind: 'pan');
  }
  if (RegExp(r'\btilt\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Tilt', kind: 'tilt');
  }
  if (RegExp(r'\b(dimmer|dimming|intensity)\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Dimmer', kind: 'intensity');
  }
  if (RegExp(r'\bmode\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Mode', kind: 'mode');
  }
  if (RegExp(r'\b(program|auto).*\bspeed\b|\bspeed\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Program speed', kind: 'speed');
  }
  if (RegExp(r'\b(strobe|shutter|flash)\b').hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Light switch / strobe',
      kind: 'strobe',
    );
  }
  if (lower.contains('color wheel') || lower.contains('colour wheel')) {
    return const _DetectedChannel(name: 'Color wheel', kind: 'colorWheel');
  }
  if (lower.contains('gobo')) {
    return const _DetectedChannel(name: 'Gobo wheel', kind: 'goboWheel');
  }
  if (lower.contains('prism')) {
    return const _DetectedChannel(name: 'Prism', kind: 'prism');
  }
  if (RegExp(r'\b(reset|lamp on|lamp off|maintenance)\b').hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Reset / function',
      kind: 'maintenance',
    );
  }
  const components = {
    'red': ('Red', 'RED'),
    'green': ('Green', 'GREEN'),
    'blue': ('Blue', 'BLUE'),
    'white': ('White', 'WHITE'),
    'amber': ('Amber', 'AMBER'),
    'uv': ('UV', 'UV'),
    'ultraviolet': ('UV', 'UV'),
  };
  for (final entry in components.entries) {
    final colorMatch = RegExp(
      '\\b${entry.key}\\s*(\\d{1,2})?\\b',
    ).firstMatch(lower);
    if (colorMatch != null) {
      final zone = colorMatch.group(1);
      return _DetectedChannel(
        name: zone == null ? entry.value.$1 : '${entry.value.$1} $zone',
        kind: 'colorIntensity',
        color: entry.value.$2,
      );
    }
  }
  final cleaned = withoutModeColumns
      .replaceAll(RegExp(r'\b\d{1,3}\s*[-–—↔⇔ó]\s*\d{1,3}\b.*$'), '')
      .replaceAll(RegExp(r'^[-–—\s]+'), '')
      .trim();
  return _DetectedChannel(
    name: cleaned.isEmpty
        ? 'Channel $channel'
        : cleaned.substring(0, cleaned.length.clamp(0, 48)),
    kind: 'generic',
  );
}

List<DmxRange> _knownRanges(String kind, {required bool isLb150}) {
  if (!isLb150) {
    return [
      DmxRange(
        start: 0,
        end: 255,
        name: kind == 'intensity' ? 'Brightness' : 'Full range',
        safety: kind == 'strobe'
            ? 'strobe'
            : kind == 'maintenance'
            ? 'reset'
            : 'normal',
        confidence: kind == 'strobe' || kind == 'maintenance' ? .45 : .8,
      ),
    ];
  }
  return switch (kind) {
    'strobe' => [
      DmxRange(start: 0, end: 10, name: 'Light off'),
      DmxRange(
        start: 11,
        end: 99,
        name: 'Normal flash, slow to fast',
        safety: 'strobe',
      ),
      DmxRange(start: 100, end: 109, name: 'Light on'),
      DmxRange(start: 110, end: 179, name: 'Pulse flash', safety: 'strobe'),
      DmxRange(start: 180, end: 189, name: 'Light on'),
      DmxRange(start: 190, end: 250, name: 'Random flash', safety: 'strobe'),
      DmxRange(start: 251, end: 255, name: 'Light on'),
    ],
    'prism' => [
      DmxRange(start: 0, end: 10, name: 'Prism off'),
      DmxRange(start: 11, end: 155, name: 'Prism in'),
      DmxRange(start: 156, end: 157, name: 'Stop'),
      DmxRange(start: 158, end: 205, name: 'Rotate counterclockwise'),
      DmxRange(start: 206, end: 207, name: 'Stop'),
      DmxRange(start: 208, end: 255, name: 'Rotate clockwise'),
    ],
    'maintenance' => [
      DmxRange(start: 0, end: 130, name: 'Settings'),
      DmxRange(start: 131, end: 140, name: 'Motor reset', safety: 'reset'),
      DmxRange(start: 141, end: 150, name: 'Effect reset', safety: 'reset'),
      DmxRange(start: 151, end: 160, name: 'Reset all', safety: 'reset'),
      DmxRange(start: 161, end: 255, name: 'No function'),
    ],
    _ => [
      DmxRange(
        start: 0,
        end: 255,
        name: kind == 'intensity' ? 'Brightness' : 'Full range',
      ),
    ],
  };
}
