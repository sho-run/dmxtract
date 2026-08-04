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
  final structuredModes = _codedChannelTables(text);
  final usableModes = modeCounts.toList();
  final hasDmxTable = RegExp(
    r'(channel value table|dmx channel assignments(?: and values)?|dmx charts?|dmx traits|dmx channels?\s*[:\-]?\s*\d)',
    caseSensitive: false,
  ).hasMatch(flat);
  final count = structuredModes.isNotEmpty
      ? structuredModes
            .map((mode) => mode.channelCount)
            .reduce((a, b) => a > b ? a : b)
      : usableModes.isNotEmpty
      ? usableModes.reduce((a, b) => a > b ? a : b)
      : hasDmxTable
      ? known.length
      : 0;
  final channels = <DmxChannel>[];
  final modes = <FixtureMode>[];
  final tableChannels = structuredModes.isEmpty
      ? _tableChannels(text, count)
      : const <_DetectedChannel>[];
  final useTableChannels =
      tableChannels.length >= 4 && tableChannels.length >= (count * .5).ceil();
  final isLb150 =
      model.toLowerCase().contains('lb150') ||
      _has(flat, r'5600\s*k.*grass\s+green.*reset.?function');
  if (structuredModes.isNotEmpty) {
    for (final detectedMode in structuredModes) {
      final modeChannelIds = <String>[];
      final coarseIds = <String, String>{};
      for (var index = 0; index < detectedMode.channelCount; index++) {
        final definition = detectedMode.channels[index];
        final channelId =
            '${slug(detectedMode.code)}-${(index + 1).toString().padLeft(3, '0')}-${slug(definition.name)}';
        final relationshipKey = _relationshipKey(definition);
        final fineOf = definition.fineOf == null
            ? null
            : coarseIds[definition.fineOf];
        if (definition.fineOf == null) {
          coarseIds[relationshipKey] = channelId;
        }
        channels.add(
          DmxChannel(
            id: channelId,
            name: definition.name,
            kind: definition.kind,
            fineOf: fineOf,
            color: definition.color,
            confidence: definition.confidence,
            ranges: definition.ranges?.isNotEmpty == true
                ? definition.ranges!
                : _knownRanges(definition.kind, isLb150: isLb150),
          ),
        );
        modeChannelIds.add(channelId);
      }
      modes.add(
        FixtureMode(
          id: 'mode-${slug(detectedMode.code)}',
          name: detectedMode.code,
          shortName: detectedMode.code,
          channelIds: modeChannelIds,
          breaks: (detectedMode.channelCount / 512).ceil().clamp(1, 64),
        ),
      );
    }
  } else {
    for (var index = 0; index < count; index++) {
      final definition = useTableChannels && index < tableChannels.length
          ? tableChannels[index]
          : index < known.length
          ? known[index]
          : _DetectedChannel(
              name: 'Channel ${index + 1}',
              kind: 'generic',
              confidence: .35,
            );
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
          confidence: definition.confidence,
          ranges: definition.ranges?.isNotEmpty == true
              ? definition.ranges!
              : _knownRanges(definition.kind, isLb150: isLb150),
        ),
      );
    }
    final simplestMode = usableModes.isEmpty
        ? count
        : usableModes.reduce((a, b) => a < b ? a : b);
    for (final modeSize
        in count == 0
            ? <int>[]
            : usableModes.isEmpty
            ? [count]
            : usableModes) {
      modes.add(
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
      );
    }
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
  final fixture = FixtureProject(
    id: '${slug(manufacturer)}-${slug(model)}',
    manufacturer: manufacturer,
    model: model,
    sourceName: sourceName,
    identityFromManual:
        modelFromManual != null &&
        manufacturerFromManual != 'Unknown manufacturer',
    channels: channels,
    modes: modes,
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
    if (structuredModes.isNotEmpty)
      ...structuredModes
          .where((mode) => mode.parsedCount < mode.channelCount)
          .take(6)
          .map(
            (mode) =>
                '${mode.code}: we read ${mode.parsedCount} of ${mode.channelCount} channel rows. Check the highlighted controls.',
          )
    else
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
    this.confidence = .9,
  });

  final String name;
  final String kind;
  final String? fineOf;
  final String? color;
  final List<DmxRange>? ranges;
  final double confidence;
}

class _DetectedModeTable {
  const _DetectedModeTable({
    required this.code,
    required this.channelCount,
    required this.channels,
    required this.parsedCount,
  });

  final String code;
  final int channelCount;
  final List<_DetectedChannel> channels;
  final int parsedCount;
}

List<_DetectedModeTable> _codedChannelTables(String text) {
  final heading = RegExp(
    r'^\s*([A-Z]{0,3}\s*\d{1,3}\s*[A-Z]{0,3})\s+(Channel|Ch[a-z!]{2,10})\s+(Table|[TVLI]able|Tab[a-z])\b',
    caseSensitive: false,
    multiLine: true,
  );
  final matches = heading.allMatches(text).toList();
  if (matches.isEmpty) return const [];

  final sections = <String, List<String>>{};
  final counts = <String, int>{};
  final exactCodes = <String>{};
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final code = _normalizeModeCode(match.group(1)!);
    final digits = RegExp(r'\d{1,3}').firstMatch(code)?.group(0);
    final count = int.tryParse(digits ?? '');
    if (count == null || count < 1 || count > 512) continue;
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : text.length;
    sections
        .putIfAbsent(code, () => <String>[])
        .add(text.substring(match.end, end));
    counts[code] = count;
    if (match.group(2)!.toLowerCase() == 'channel' &&
        match.group(3)!.toLowerCase() == 'table') {
      exactCodes.add(code);
    }
  }

  for (final numericCode
      in sections.keys
          .where((code) => RegExp(r'^\d+$').hasMatch(code))
          .toList()) {
    final count = counts[numericCode];
    final codedMatch = sections.keys.where(
      (code) =>
          code != numericCode &&
          counts[code] == count &&
          code.replaceAll(RegExp(r'[^0-9]'), '') == numericCode,
    );
    if (codedMatch.length != 1) continue;
    final preferred = codedMatch.single;
    sections[preferred]!.addAll(sections.remove(numericCode)!);
    counts.remove(numericCode);
  }

  // A high-resolution pass can turn the same printed heading into a nearby
  // alias (AC37 -> AG37, BC37 -> BG37, CH58 -> C58). Collapse only aliases
  // with the same advertised size and either a dropped character or the
  // common C/G substitution. Equal-length ordinary codes such as 49AC and
  // 49BC remain distinct personalities.
  for (final alias in sections.keys.toList()) {
    final candidates = sections.keys.where((candidate) {
      if (candidate == alias || counts[candidate] != counts[alias]) {
        return false;
      }
      if (exactCodes.contains(alias) || !exactCodes.contains(candidate)) {
        return false;
      }
      final droppedCharacter = candidate.length == alias.length + 1;
      final cToG = _isSingleGToCSubstitution(alias, candidate);
      return droppedCharacter && _oneEditApart(alias, candidate) || cToG;
    }).toList();
    if (candidates.length != 1) continue;
    final preferred = candidates.single;
    sections[preferred]!.addAll(sections.remove(alias)!);
    counts.remove(alias);
  }

  return [
    for (final entry in sections.entries)
      _parseCodedMode(entry.key, counts[entry.key]!, entry.value),
  ];
}

bool _isSingleGToCSubstitution(String alias, String candidate) {
  if (alias.length != candidate.length) return false;
  final differences = <(String, String)>[
    for (var index = 0; index < alias.length; index++)
      if (alias[index] != candidate[index]) (alias[index], candidate[index]),
  ];
  return differences.length == 1 &&
      differences.single.$1 == 'G' &&
      differences.single.$2 == 'C';
}

bool _oneEditApart(String left, String right) {
  if ((left.length - right.length).abs() > 1) return false;
  final shorter = left.length <= right.length ? left : right;
  final longer = left.length <= right.length ? right : left;
  var shortIndex = 0;
  var longIndex = 0;
  var edits = 0;
  while (shortIndex < shorter.length && longIndex < longer.length) {
    if (shorter[shortIndex] == longer[longIndex]) {
      shortIndex++;
      longIndex++;
      continue;
    }
    edits++;
    if (edits > 1) return false;
    if (shorter.length == longer.length) shortIndex++;
    longIndex++;
  }
  if (longIndex < longer.length) edits++;
  return edits == 1;
}

String _normalizeModeCode(String raw) {
  var value = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  value = value.replaceFirst(RegExp(r'^[IL](?=\d{2,3}[A-Z]+$)'), '');
  value = value.replaceFirst(RegExp(r'^CHH(?=\d)'), 'CH');
  value = value.replaceFirst(RegExp(r'^4S(?=[A-Z]+$)'), '49');
  if (RegExp(r'^A\d[A-Z]{1,3}$').hasMatch(value)) {
    value = '4${value.substring(1)}';
  }
  return value;
}

_DetectedModeTable _parseCodedMode(
  String code,
  int channelCount,
  List<String> sections,
) {
  final parsed = <int, _DetectedChannel>{};
  final row = RegExp(
    r'^\s*(\d{1,3})\s+(\d{1,3})\s*[-–—↔⇔ó]\s*(\d{1,3})\s+(.+?)\s*$',
  );
  final rowWithoutRange = RegExp(r'^\s*(\d{1,3})\s+([A-Za-z].+?)\s*$');
  final continuation = RegExp(
    r'^\s*(\d{1,3})\s*[-–—↔⇔ó]\s*(\d{1,3})\s+(.+?)\s*$',
  );

  for (final section in sections) {
    int? currentChannel;
    var nextPosition = 1;
    for (final rawLine in section.split(RegExp(r'[\r\n]+'))) {
      final line = _normalizeTableLine(rawLine);
      if (line.isEmpty || line.startsWith('=== DMXTRACT PAGE')) continue;
      final match = row.firstMatch(line);
      if (match != null) {
        final position = int.parse(match.group(1)!);
        final start = _normalizeDmxValue(int.parse(match.group(2)!));
        final end = _normalizeDmxValue(int.parse(match.group(3)!));
        if (position < 1 ||
            position > channelCount ||
            start > end ||
            end > 255) {
          continue;
        }
        final description = _cleanFunction(match.group(4)!);
        final definition = _classifyTableChannel(description, position);
        final range = _rangeFromParts(start, end, description, definition.kind);
        parsed[position] = _mergeDetectedChannel(
          parsed[position],
          definition,
          range,
        );
        currentChannel = position;
        nextPosition = position + 1;
        continue;
      }

      final simple = rowWithoutRange.firstMatch(line);
      if (simple != null) {
        final position = int.parse(simple.group(1)!);
        if (position >= 1 && position <= channelCount) {
          final recoveredFunction = _fuzzyTableFunction(rawLine);
          final description =
              recoveredFunction ?? _cleanFunction(simple.group(2)!);
          if (!_looksLikePageFurniture(description)) {
            final definition = recoveredFunction == null
                ? _classifyTableChannel(description, position)
                : _withConfidence(
                    _classifyTableChannel(description, position),
                    .6,
                  );
            parsed[position] = _mergeDetectedChannel(
              parsed[position],
              definition,
              recoveredFunction == null
                  ? null
                  : _rangeFromParts(
                      0,
                      255,
                      description,
                      definition.kind,
                      confidence: .45,
                    ),
            );
            currentChannel = position;
            nextPosition = position + 1;
            continue;
          }
        }
      }

      final extra = continuation.firstMatch(line);
      if (extra != null && currentChannel != null) {
        final start = _normalizeDmxValue(int.parse(extra.group(1)!));
        final end = _normalizeDmxValue(int.parse(extra.group(2)!));
        if (start <= end && end <= 255) {
          final description = _cleanFunction(extra.group(3)!);
          final definition = _classifyTableChannel(description, currentChannel);
          parsed[currentChannel] = _mergeDetectedChannel(
            parsed[currentChannel],
            definition,
            _rangeFromParts(start, end, description, definition.kind),
          );
        }
        continue;
      }

      // Scanned grid tables often preserve the function column but OCR the
      // narrow row-number and value columns as punctuation. Positioned OCR
      // leaves a wider whitespace gap between columns, which lets us recover
      // the row by its order without pretending the damaged value was read.
      final fuzzy = _fuzzyTableFunction(rawLine);
      if (fuzzy == null || nextPosition > channelCount) continue;
      final definition = _withConfidence(
        _classifyTableChannel(fuzzy, nextPosition),
        .6,
      );
      parsed[nextPosition] = _mergeDetectedChannel(
        parsed[nextPosition],
        definition,
        _rangeFromParts(0, 255, fuzzy, definition.kind, confidence: .45),
      );
      currentChannel = nextPosition;
      nextPosition++;
    }
  }

  return _DetectedModeTable(
    code: code,
    channelCount: channelCount,
    parsedCount: parsed.length,
    channels: [
      for (var position = 1; position <= channelCount; position++)
        parsed[position] ??
            _DetectedChannel(
              name: 'Channel $position',
              kind: 'generic',
              confidence: .25,
            ),
    ],
  );
}

int _normalizeDmxValue(int value) => value >= 256 && value <= 269 ? 255 : value;

String _normalizeTableLine(String value) {
  var normalized = value
      .replaceAll(RegExp(r'[|\[\]{}]'), ' ')
      .replaceAll(RegExp(r'(?<=\d)[._~](?=\d)'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  normalized = normalized.replaceAllMapped(
    RegExp(r'\b(0{1,3})(2\d{2})\b'),
    (match) => '${match.group(1)}-${match.group(2)}',
  );
  return normalized;
}

_DetectedChannel _mergeDetectedChannel(
  _DetectedChannel? existing,
  _DetectedChannel incoming,
  DmxRange? range,
) {
  final ranges = <DmxRange>[...?existing?.ranges, ?range];
  final preferIncoming =
      existing == null ||
      existing.kind == 'generic' && incoming.kind != 'generic';
  final chosen = preferIncoming ? incoming : existing;
  return _DetectedChannel(
    name: chosen.name,
    kind: chosen.kind,
    fineOf: chosen.fineOf,
    color: chosen.color,
    confidence: chosen.confidence,
    ranges: ranges,
  );
}

_DetectedChannel _withConfidence(_DetectedChannel channel, double confidence) {
  return _DetectedChannel(
    name: channel.name,
    kind: channel.kind,
    fineOf: channel.fineOf,
    color: channel.color,
    ranges: channel.ranges,
    confidence: confidence,
  );
}

DmxRange _rangeFromParts(
  int start,
  int end,
  String description,
  String kind, {
  double confidence = .9,
}) {
  final lower = description.toLowerCase();
  return DmxRange(
    start: start,
    end: end,
    name: description.isEmpty ? 'Full range' : description,
    safety:
        kind == 'strobe' &&
            !lower.contains('void') &&
            !lower.contains('no function')
        ? 'strobe'
        : kind == 'maintenance' && lower.contains('reset')
        ? 'reset'
        : 'normal',
    confidence: confidence,
  );
}

String? _fuzzyTableFunction(String rawLine) {
  final columns = rawLine
      .trim()
      .split(RegExp(r'\s{2,}'))
      .map(_cleanFunction)
      .toList();
  if (columns.length < 2) return null;
  if (columns.length == 2 && !_looksLikeFixtureFunction(columns.last)) {
    return null;
  }
  final description = _cleanFunction(
    columns
        .sublist(columns.length >= 3 ? 2 : 1)
        .where((column) => column.isNotEmpty)
        .join(' '),
  );
  if (description.isEmpty || _looksLikePageFurniture(description)) return null;
  if (RegExp(
    r'^(function|value|channel|no\.?|dmx|mode\s+channel)$',
    caseSensitive: false,
  ).hasMatch(description)) {
    return null;
  }
  return description;
}

bool _looksLikeFixtureFunction(String value) => RegExp(
  r'\b(?:x.?axis|y.?axis|xy\s+speed|pan|tilt|reset|[rgbw]\s*\d{1,2}|ct\d*|mode|focus|focusing|shutter|dimmer|dimming|void|strobe|speed|accelerated|complementary|supplementary|assist|light\s+(?:strip|band)|color|colour|gobo|prism|control)\b',
  caseSensitive: false,
).hasMatch(value);

String _cleanFunction(String value) {
  var cleaned = value
      .replaceAll(RegExp(r'''^[|:;.,\-_~“”‘’'"`§\s]+|[|:;.,\s]+$'''), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const repairs = <String, String>{
    r'^eset\b': 'Reset',
    r'^ocusing\b': 'Focusing',
    r'^hutter\b': 'Shutter',
    r'^imming\b': 'Dimming',
  };
  for (final repair in repairs.entries) {
    cleaned = cleaned.replaceFirst(
      RegExp(repair.key, caseSensitive: false),
      repair.value,
    );
  }
  cleaned = cleaned.replaceFirstMapped(
    RegExp(r'^ight\s+(strip|band)\b', caseSensitive: false),
    (match) => 'Light ${match.group(1)}',
  );
  cleaned = cleaned.replaceFirst(
    RegExp(r'^[mv]ode[_\s-]*table\w*', caseSensitive: false),
    'Mode table',
  );
  return cleaned;
}

bool _looksLikePageFurniture(String value) => RegExp(
  r'^(page|p\.?\s*\d|rev(?:ision)?|user manual|contents?)\b',
  caseSensitive: false,
).hasMatch(value);

String _relationshipKey(_DetectedChannel channel) {
  if (channel.kind == 'colorIntensity') {
    final zone = RegExp(r'\d+').firstMatch(channel.name)?.group(0) ?? '';
    return 'colorIntensity:${channel.color ?? ''}:$zone';
  }
  if (channel.kind == 'intensity') return 'intensity:dimmer';
  if (channel.kind == 'focus') return 'focus';
  return channel.kind;
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
  final withoutModeColumns = value
      .replaceFirst(RegExp(r'^\d{1,3}\s*[-–—↔⇔ó]\s*\d{1,3}\s+'), '')
      .replaceFirst(RegExp(r'^(?:(?:\d{1,3}|-)\s+){1,6}'), '');
  final lower = withoutModeColumns.toLowerCase();
  if (RegExp(r'(pan.?tilt|x.?y|xy).*(speed|time)').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan / tilt speed', kind: 'speed');
  }
  if (RegExp(r'(pan|x.?axis)\s*(fine|16.?bit|least)').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan fine', kind: 'pan', fineOf: 'pan');
  }
  if (RegExp(r'(tilt|y.?axis)\s*(fine|16.?bit|least)').hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Tilt fine',
      kind: 'tilt',
      fineOf: 'tilt',
    );
  }
  if (RegExp(r'\bpan\b|\bx.?axis\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan', kind: 'pan');
  }
  if (RegExp(r'\btilt\b|\by.?axis\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Tilt', kind: 'tilt');
  }
  if (RegExp(
    r'\b(dimmer|dimming|intensity)\b.*\b(fine|fine.?tuning)\b',
  ).hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Dimmer fine',
      kind: 'intensity',
      fineOf: 'intensity:dimmer',
    );
  }
  if (RegExp(r'\b(dimmer|dimming|intensity)\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Dimmer', kind: 'intensity');
  }
  if (RegExp(
    r'\b(focus|focusing)\b.*\b(fine|fine.?tuning)\b',
  ).hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Focus fine',
      kind: 'focus',
      fineOf: 'focus',
    );
  }
  if (RegExp(r'\b(focus|focusing)\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Focus', kind: 'focus');
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
  final abbreviatedColor = RegExp(
    r'^([rgbw])\s*(\d{1,2})(?:\s+(fine|fine.?tuning))?\b',
  ).firstMatch(lower);
  if (abbreviatedColor != null) {
    const colors = {
      'r': ('Red', 'RED'),
      'g': ('Green', 'GREEN'),
      'b': ('Blue', 'BLUE'),
      'w': ('White', 'WHITE'),
    };
    final color = colors[abbreviatedColor.group(1)]!;
    final zone = abbreviatedColor.group(2)!;
    final fine = abbreviatedColor.group(3) != null;
    return _DetectedChannel(
      name: fine ? '${color.$1} $zone fine' : '${color.$1} $zone',
      kind: 'colorIntensity',
      color: color.$2,
      fineOf: fine ? 'colorIntensity:${color.$2}:$zone' : null,
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
      '\\b${entry.key}\\s*(\\d{1,2})?(?:\\s+(fine|fine.?tuning))?\\b',
    ).firstMatch(lower);
    if (colorMatch != null) {
      final zone = colorMatch.group(1);
      final fine = colorMatch.group(2) != null;
      return _DetectedChannel(
        name: zone == null
            ? entry.value.$1
            : fine
            ? '${entry.value.$1} $zone fine'
            : '${entry.value.$1} $zone',
        kind: 'colorIntensity',
        color: entry.value.$2,
        fineOf: fine ? 'colorIntensity:${entry.value.$2}:${zone ?? ''}' : null,
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
