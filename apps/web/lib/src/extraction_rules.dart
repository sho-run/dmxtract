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
  final productLineModelMatch = RegExp(
    r'\b((?:COLORado|MAC)\s+[A-Za-z0-9][A-Za-z0-9 -]{1,40}?)\s+User Manual\b',
    caseSensitive: false,
  ).firstMatch(flat);
  // Title pages don't only say "User Manual" — "DMX Traits", "User
  // Instructions" and "Programming Manual" are all doc-type suffixes this
  // corpus's manuals actually use for the same role.
  // "User" is deliberately singular-only (never "Users Manual"): several
  // manuals in the corpus repeat "<Product> Installation & Users Manual" as
  // a running header on every page, and letting "Users Manual" alone count
  // as the doc-type suffix pulled "Installation &" into the captured title
  // since it sits between the product name and the suffix with no
  // separator this pattern recognizes.
  const manualSuffix =
      r"(?:User\s+Manual|Owner'?s?\s+Manual|Programming\s+Manual|"
      r"Instruction(?:s)?\s+Manual|User\s+Instructions|DMX\s+Traits)";
  final manualTitleMatch = RegExp(
    // The separator between the title and the doc-type suffix is
    // deliberately [ \t]+, not \s+: \s+ also matches newlines, and this
    // pattern runs against the raw (non-flattened) text with multiline
    // ^/$ anchors, so a \s+ gap would happily bridge across the
    // "=== DMXTRACT PAGE N ===" marker between pages — e.g. a cover page
    // whose product name renders as an unreadable image, leaving only the
    // orphaned text "User Manual", would match
    // "=== DMXTRACT PAGE 1 ===\nUser Manual" as the title, extracting the
    // page marker itself as the model. An optional "-"/"–" separator is
    // allowed too ("ADJ VIZI XTREME - DMX TRAITS" is one physical line).
    r'^[ \t]*(.{3,70}?)[ \t]+(?:[-–][ \t]+)?' +
        manualSuffix +
        r'(?:[ \t]+(?:Rev\.?|Revision)\s*[A-Z0-9.]+)?[ \t]*$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(text);
  // Same idea, but the title and the doc-type suffix sit on two
  // consecutive physical lines (a cover page that centers the model name
  // above a smaller "User Manual"/"User Instructions" line). Still
  // same-page only: a single "\n", never a page-marker gap. This has to run
  // unconditionally, not only when manualTitleMatch itself is null: a
  // manual can contain an unrelated same-line match earlier in the body
  // (e.g. a "DMX Traits" table-column header with nothing but whitespace
  // in front of it) that firstMatch finds and _modelFromManualTitle then
  // rejects as empty/furniture, and by then it's too late to fall back to
  // scanning for the two-line cover title.
  //
  // "Unconditionally" still only means "scan the cover page", not "scan the
  // whole document": once a manual is more than one page, a same-shaped
  // "<line>\n<doc-type suffix>" pair can occur anywhere in the body — a
  // revision-history table row sitting directly above a running "DMX
  // Traits" section heading (real corpus shape) reads exactly like a cover
  // title otherwise. Restricting the scan to the text before the second
  // "=== DMXTRACT PAGE N ===" marker keeps it doing only the job its
  // comment describes.
  final pageMarkers = RegExp(
    r'^=== DMXTRACT PAGE \d+ ===\s*$',
    multiLine: true,
  ).allMatches(text).toList();
  final coverPageText = pageMarkers.length >= 2
      ? text.substring(0, pageMarkers[1].start)
      : text;
  // Last-resort fallback for a cover page whose own product name is
  // unreadable but that still carries boilerplate like "FOR YOUR OWN
  // SAFETY, PLEASE READ THIS USER MANUAL CAREFULLY" — same cover-page-only
  // restriction as the two-line match above, and for the same reason: run
  // unrestricted over the whole flattened document, this can just as easily
  // land on a body data row (a revision-history entry, a spec line) sitting
  // in front of some other, unrelated occurrence of the doc-type suffix
  // later in the manual.
  final titledModelMatch = RegExp(
    r'\b([A-Z][A-Za-z0-9_-]{2,30})[™®]?\s+' + manualSuffix + r'\b',
    caseSensitive: false,
  ).allMatches(coverPageText.replaceAll(RegExp(r'\s+'), ' '));
  final manualTitleTwoLineMatch = RegExp(
    r'^[ \t]*(.{3,70}?)[ \t]*\n[ \t]*' +
        manualSuffix +
        r'(?:[ \t]+(?:Rev\.?|Revision)\s*[A-Z0-9.]+)?[ \t]*$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(coverPageText);
  final titleModel =
      _modelFromManualTitle(manualTitleMatch?.group(1)) ??
      _modelFromManualTitle(manualTitleTwoLineMatch?.group(1)) ??
      _modelFromLetterTrackedTraitsLine(text);
  final modelFromManual =
      productLineModelMatch?.group(1)?.trim() ??
      numberedModelMatch?.group(1)?.replaceAll(' ', '') ??
      titleModel ??
      _firstNonStopwordTitle(titledModelMatch);
  final fallback = _modelFromFilename(sourceName);
  final model = modelFromManual ?? fallback ?? 'Unknown fixture';
  final manufacturerFromManual = _manufacturer(flat);
  final manufacturer = manufacturerFromManual == 'Unknown manufacturer'
      ? _manufacturer(sourceName)
      : manufacturerFromManual;
  final modeCounts = <int>[];
  for (final match in RegExp(
    // The trailing lookahead used to only exclude a following letter, so
    // "CH" swallowed a channel *label* immediately after it: a control-menu
    // row like "...RGB TXT Mode 1 CH9 RGB Dual-Sign L..." (channel 8's
    // function names a value "Mode 1", and CH9 is the next row's channel
    // ID, not a channel count) read as "1 CH", a bogus 1-channel mode. A
    // genuine count ("6CH", "19CH") is always followed by whitespace or
    // punctuation, never by another digit, so digits are excluded here too.
    // A "UNIT n" multi-fixture addressing-offset table ("UNIT 1 UNIT 2
    // UNIT 3 UNIT 4") is excluded too: on the flattened (newline-collapsed)
    // text, its last column label sits directly in front of that table's
    // own, unrelated "Channel Mode" heading, reading as "4 CHANNEL MODE" —
    // a bogus 4-channel mode.
    r'(?<![A-Za-z0-9])(?<!unit )(\d{1,3})\s*[-–]?\s*(?:CH|channel(?:s| mode)?)(?![A-Za-z0-9])',
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
    } else if (modeCounts.length <= 1 && !modeCounts.contains(tableCount)) {
      // Once a manual has already declared 2+ modes elsewhere (a "DMX
      // Traits"/matrix-style header naming several channel counts, say),
      // [_tableChannelCount]'s sequential-position scan over that same
      // table is measuring one of those modes' own leftmost column, not an
      // independent extra mode — a value sub-table with no position number
      // of its own (e.g. a color-macro range list between two channel
      // rows) can break the run short and land on a smaller count that
      // isn't any of the modes actually in the table. Only trust this
      // heuristic to *add* a mode when it has at most one declared count to
      // corroborate or replace.
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
  final namedModes = _namedDmxModeTables(text);
  final matrixModes = namedModes.isEmpty
      ? _modeMatrixTables(text)
      : const <_DetectedModeTable>[];
  final sequentialModes = namedModes.isEmpty && matrixModes.isEmpty
      ? _sequentialModeTables(text)
      : const <_DetectedModeTable>[];
  final contextualModes =
      namedModes.isEmpty && matrixModes.isEmpty && sequentialModes.isEmpty
      ? _contextualPersonalityTables(text)
      : const <_DetectedModeTable>[];
  final structuredModes = namedModes.isNotEmpty
      ? namedModes
      : matrixModes.isNotEmpty
      ? matrixModes
      : sequentialModes.isNotEmpty
      ? sequentialModes
      : contextualModes.isNotEmpty
      ? contextualModes
      : _codedChannelTables(text);
  final virtualColorWheelRanges = _virtualColorWheelRanges(text);
  final codedSupplementalRanges = _codedSupplementalRanges(text);
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
        final supplementalRanges = _supplementalRangesFor(
          definition,
          codedSupplementalRanges,
        );
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
            ranges: supplementalRanges.isNotEmpty
                ? supplementalRanges
                : definition.ranges?.isNotEmpty == true
                ? definition.ranges!
                : definition.kind == 'colorWheel' &&
                      virtualColorWheelRanges.isNotEmpty
                ? virtualColorWheelRanges
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
    final virtualLabels = virtualColorWheelRanges
        .where(
          (range) =>
              range.start <= 106 &&
              !range.name.toLowerCase().contains('no function'),
        )
        .map((range) => range.name)
        .toList();
    final labels = virtualLabels.isNotEmpty
        ? virtualLabels
        : isLb150Wheel
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
        virtualLabels.isNotEmpty
            ? .95
            : isLb150Wheel
            ? .72
            : .35,
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
  if (lower.contains('chauvet')) {
    return lower.contains('chauvet professional') ||
            lower.contains('colorado pxl')
        ? 'Chauvet Professional'
        : 'Chauvet DJ';
  }
  if (lower.contains('martin')) return 'Martin';
  if (lower.contains('altman')) return 'Altman';
  if (RegExp(r'(^|[^a-z])adj([^a-z]|$)').hasMatch(lower)) return 'ADJ';
  return 'Unknown manufacturer';
}

// Common filler words that can land directly in front of a doc-type suffix
// ("...PLEASE READ THIS USER MANUAL CAREFULLY") without being any part of
// the product name.
const _titleStopwords = {
  'this',
  'the',
  'a',
  'an',
  'your',
  'our',
  'my',
  'its',
  'read',
  'see',
  'review',
  'entire',
  'complete',
  'following',
  'above',
  'before',
  'use',
  // Descriptive adjectives naming the *kind* of manual, not the product —
  // "READ THE SAFETY INSTRUCTION MANUAL FIRST", "the SERVICE instruction
  // manual", "the ADVANCED programming manual", "This IMPORTANT instruction
  // manual", "the GENERAL owner manual". None of these are ever a fixture's
  // model name on their own.
  'safety',
  'service',
  'general',
  'advanced',
  'important',
  'basic',
  'quick',
  'full',
  'technical',
  'programming',
  'installation',
  'operation',
  'operating',
  'troubleshooting',
  'maintenance',
  'reference',
};

String? _firstNonStopwordTitle(Iterable<RegExpMatch> matches) {
  for (final match in matches) {
    final word = match.group(1)!;
    if (_titleStopwords.contains(word.toLowerCase())) continue;
    // The pattern that produced these matches is caseSensitive: false (it
    // has to be, to find the doc-type suffix in any case), which makes its
    // own `[A-Z]` anchor on the captured word inert — an ordinary lowercase
    // prose word ("these", "all") satisfies it just as well as a real
    // capitalized product name. Check the actual case here instead: a real
    // model reads as a proper noun (capitalized) or carries a model number.
    if (!RegExp(r'^[A-Z]').hasMatch(word) && !RegExp(r'\d').hasMatch(word)) {
      continue;
    }
    // Route through the same furniture/safety/data-line checks as every
    // other title candidate — this bypassed them entirely before, so the
    // exact defect class those checks exist for ("SAFETY", "USER", ...)
    // was still reachable through this path with different boilerplate.
    final model = _modelFromManualTitle(word);
    if (model != null) return model;
  }
  return null;
}

/// True when a title candidate reads like tabular/bookkeeping data — a
/// revision-history row, a table-of-contents dot-leader entry, a copyright
/// line, or a "Field: value" spec line — rather than an actual product
/// name. These are exactly the shapes a stray line directly above a bare
/// doc-type heading ("DMX Traits", "User Instructions") can take once that
/// heading is also a running section header, not only a cover-page label.
bool _looksLikeDataLine(String value) =>
    value.contains('©') ||
    RegExp(r'\.{3,}').hasMatch(value) ||
    RegExp(r'^\s*\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}\b').hasMatch(value) ||
    value.contains(':') ||
    RegExp(r'\d+').allMatches(value).length > 2;

String? _modelFromManualTitle(String? raw) {
  if (raw == null) return null;
  var value = raw
      .replaceAll(RegExp(r'[™®]'), '')
      .replaceFirst(
        RegExp(
          r'^\s*(?:Chauvet(?:\s+Professional)?|Martin|ADJ)\s+',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (value.isEmpty ||
      _looksLikePageFurniture(value) ||
      _looksLikeDataLine(value)) {
    return null;
  }
  if (RegExp(r'^(?:safety|user|owner)', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  return value;
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
  // Strip revision markers ("Rev0", "Rev. 2") and bare YYYYMMDD date stamps
  // left over once "manual"/"dmx traits" is gone — they're filename
  // bookkeeping, not part of the product name, and otherwise end up glued
  // onto the fallback model (e.g. "SPECTRA REV0 20210204").
  //
  // The revision number itself is capped at 2 digits ("Rev0", "Rev. 2",
  // "REV12"): a real revision index is short, so this still lets `\s*`
  // bridge a "Rev." to a same-token digit, but a longer run right after
  // "Rev" (as in "MAC_Rev_2000", where 2000 reads as the filename's own
  // model number, not a revision index) leaves that number alone instead of
  // deleting it as if it were part of the marker.
  //
  // The date strip is anchored to a plausible calendar stamp
  // ((?:19|20)\d{6}) rather than any bare 8-digit run — an unanchored
  // \d{8} deletes real 8-digit part numbers ("LED-12345678") that happen to
  // be exactly 8 digits long but aren't dates at all.
  value = value
      .replaceAll(RegExp(r'\brev\.?\s*\d{0,2}\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\b(?:19|20)\d{6}\b'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      // A strip can leave a dangling separator at either end ("Rev-Party-
      // Bar" -> "-Party-Bar" once "Rev" alone is removed) — trim those off
      // rather than surfacing punctuation as if it were part of the name.
      .replaceAll(RegExp(r'^[-_\s]+|[-_\s]+$'), '')
      .trim();
  final tokens = RegExp(
    r'\b[A-Za-z]{1,8}[- ]?\d{2,5}[A-Za-z]?\b',
  ).allMatches(value).map((match) => match.group(0)!.replaceAll(' ', ''));
  if (tokens.isNotEmpty) return tokens.first;
  if (value.isEmpty) return null;
  // A source file that arrived as a bare content hash ("9e48fa0ab3c9…") has
  // no product name to recover from its filename at all — a run of 16+
  // hex-only characters is never a real fixture model, and surfacing it
  // verbatim is worse than admitting we don't know the model and falling
  // through to "Unknown fixture".
  if (RegExp(r'^[a-f0-9]{16,}$', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  return value;
}

/// Recovers a product name from a cover line like "ADJ VIZI XTREME - DMX
/// TRAITS" when the source PDF's title font tracks every glyph apart, which
/// pdftotext then renders as single-space-separated single/double-character
/// tokens with no way to tell a within-word gap from a between-word gap
/// ("E L I M I N AT O R L P H E X 1 2 P L U S - D M X T R A I T S" is
/// "ELIMINATOR LP HEX 12 PLUS - DMX TRAITS" with every glyph's tracking gap
/// collapsed to the same single space pdftotext uses between real words).
/// Only a letter/digit boundary survives as an unambiguous split point in
/// that output, so that's the only place this reinserts a space; word
/// boundaries between two runs of letters (e.g. "ELIMINATOR" next to "LP")
/// can't be recovered from plain text without the PDF's glyph coordinates,
/// which this pipeline (plain pdftotext output) doesn't have.
String? _modelFromLetterTrackedTraitsLine(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final dash = RegExp(r'[ \t][-–][ \t]').firstMatch(trimmed);
    if (dash == null) continue;
    final left = trimmed.substring(0, dash.start).trim();
    final right = trimmed.substring(dash.end).trim();
    final rightTokens = right.split(RegExp(r'\s+'));
    // Only the letter-tracked spelling of "DMX TRAITS" (one token per
    // glyph) is handled here — a normally spaced "DMX TRAITS" suffix is
    // already covered by [manualSuffix] above.
    if (rightTokens.any((token) => token.length > 2)) continue;
    if (rightTokens.join().toUpperCase() != 'DMXTRAITS') continue;
    final leftTokens = left.split(RegExp(r'\s+'));
    if (leftTokens.length < 6 ||
        leftTokens.any(
          (token) => !RegExp(r'^[A-Za-z0-9]{1,2}$').hasMatch(token),
        )) {
      continue;
    }
    var joined = leftTokens.join();
    const knownBrandPrefixes = [
      'CHAUVETPROFESSIONAL',
      'CHAUVET',
      'MARTIN',
      'ELIMINATOR',
      'ADJ',
    ];
    for (final brand in knownBrandPrefixes) {
      if (joined.toUpperCase().startsWith(brand)) {
        joined = joined.substring(brand.length);
        break;
      }
    }
    final spaced = joined
        .replaceAllMapped(
          RegExp(r'([A-Za-z])(\d)|(\d)([A-Za-z])'),
          (match) => match.group(1) != null
              ? '${match.group(1)} ${match.group(2)}'
              : '${match.group(3)} ${match.group(4)}',
        )
        .trim();
    if (spaced.isNotEmpty) return spaced;
  }
  return null;
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

List<DmxRange> _virtualColorWheelRanges(String text) {
  final headings = RegExp(
    r'^\s*Virtual colou?r wheel\*?\s*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(text);
  for (final heading in headings) {
    final available = text.substring(
      heading.end,
      (heading.end + 8000).clamp(0, text.length),
    );
    final end = RegExp(
      r'^\s*(?:\d{1,4}\s+)?(?:Zoom|Beamshaper|Pan / tilt|Compact DMX Mode)\*?\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(available)?.start;
    final section = available.substring(0, end ?? available.length);
    final ranges = <DmxRange>[];
    for (final rawLine in section.split(RegExp(r'[\r\n]+'))) {
      final match = RegExp(
        r'(\d{1,3})\s*[-–—]\s*(\d{1,3})\s+(.+?)\s*$',
      ).firstMatch(rawLine);
      if (match == null) continue;
      final start = int.parse(match.group(1)!);
      final finish = int.parse(match.group(2)!);
      if (start > finish || finish > 255) continue;
      var name = _cleanFunction(match.group(3)!);
      name = name
          .replaceFirst(RegExp(r'\s+Fade\s+\d+\s*$', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s+Snap\s+\d+\s*$', caseSensitive: false), '')
          .trim();
      if (name.isEmpty || _looksLikePageFurniture(name)) continue;
      if (ranges.any((range) => range.start == start && range.end == finish)) {
        continue;
      }
      ranges.add(
        DmxRange(
          start: start,
          end: finish,
          name: name.substring(0, name.length.clamp(0, 80)),
          confidence: .95,
        ),
      );
    }
    ranges.sort((left, right) => left.start.compareTo(right.start));
    if (ranges.any((range) => range.start == 0 && range.end == 10) &&
        ranges.where((range) => range.start >= 11 && range.end <= 106).length >=
            40) {
      return ranges;
    }
  }
  return const [];
}

Map<String, List<DmxRange>> _codedSupplementalRanges(String text) {
  final result = <String, List<DmxRange>>{};
  final shutter = _appendixTableRanges(
    text,
    r'Shutter',
    r'Mode\s+table\s*[2②]',
  );
  if (shutter.length >= 10 &&
      shutter.first.start == 0 &&
      shutter.last.end == 255) {
    result['shutter'] = shutter;
  }

  final flat = text.replaceAll(RegExp(r'\s+'), ' ');
  if (RegExp(
    r'10\s*[-–—]\s*13\s+Colou?r temperature 1.*246\s*[-–—]\s*249\s+Colou?r temperature 60.*254\s*[-–—]\s*255\s+Colou?r temperature 62',
    caseSensitive: false,
  ).hasMatch(flat)) {
    result['color-temperature'] = [
      DmxRange(start: 0, end: 9, name: 'No function'),
      for (var index = 1; index <= 62; index++)
        DmxRange(
          start: 10 + (index - 1) * 4,
          end: (13 + (index - 1) * 4).clamp(0, 255),
          name: 'Color temperature $index',
          confidence: .9,
        ),
    ];
  }

  if (RegExp(
    r'17\s*[-–—]\s*55\s+Mode 9.*57\s*[-–—]\s*95\s+Mode 11.*136\s*[-–—]\s*174\s+Mode 15.*176\s*[-–—]\s*214\s+Mode 17',
    caseSensitive: false,
  ).hasMatch(flat)) {
    const values = <(int, int, String)>[
      (0, 0, 'No function'),
      (1, 2, 'Mode 1'),
      (3, 3, 'Mode 2'),
      (4, 5, 'Mode 3'),
      (6, 6, 'Mode 4'),
      (7, 9, 'Mode 5'),
      (10, 12, 'Mode 6'),
      (13, 15, 'Mode 7'),
      (16, 16, 'Mode 8'),
      (17, 55, 'Mode 9'),
      (56, 56, 'Mode 10'),
      (57, 95, 'Mode 11'),
      (96, 96, 'Mode 12'),
      (97, 134, 'Mode 13'),
      (135, 135, 'Mode 14'),
      (136, 174, 'Mode 15'),
      (175, 175, 'Pattern 16'),
      (176, 214, 'Mode 17'),
      (215, 215, 'Mode 18'),
      (216, 246, 'Mode 19'),
      (247, 247, 'Mode 20'),
      (248, 248, 'Mode 21'),
      (249, 249, 'Mode 22'),
      (250, 250, 'Mode 23'),
      (251, 251, 'Mode 24'),
      (252, 252, 'Mode 25'),
      (253, 253, 'Mode 26'),
      (254, 254, 'Mode 27'),
      (255, 255, 'Mode 28'),
    ];
    result['mode-1'] = [
      for (final value in values)
        DmxRange(
          start: value.$1,
          end: value.$2,
          name: value.$3,
          confidence: .9,
        ),
    ];
  }

  if (RegExp(
    r'4\s*[-–—]\s*10\s+Mode 1.*235\s*[-–—]\s*241\s+Mode 34.*249\s*[-–—]\s*255\s+Mode 36',
    caseSensitive: false,
  ).hasMatch(flat)) {
    result['mode-2'] = [
      DmxRange(start: 0, end: 3, name: 'No function'),
      for (var index = 1; index <= 36; index++)
        DmxRange(
          start: 4 + (index - 1) * 7,
          end: 10 + (index - 1) * 7,
          name: 'Mode $index',
          confidence: .9,
        ),
    ];
  }

  if (RegExp(
    r'0\s*[-–—]\s*7\s+Color 0.*248\s*[-–—]\s*251\s+Color 61.*252\s*[-–—]\s*255\s+Color 62',
    caseSensitive: false,
  ).hasMatch(flat)) {
    result['background-color'] = [
      DmxRange(start: 0, end: 7, name: 'Color 0'),
      for (var index = 1; index <= 62; index++)
        DmxRange(
          start: 4 + index * 4,
          end: 7 + index * 4,
          name: 'Color $index',
          confidence: .9,
        ),
    ];
  }
  return result;
}

List<DmxRange> _appendixTableRanges(
  String text,
  String headingPattern,
  String stopPattern,
) {
  final headings = RegExp(
    '^\\s*$headingPattern\\s*\$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(text);
  for (final heading in headings) {
    final available = text.substring(
      heading.end,
      (heading.end + 8000).clamp(0, text.length),
    );
    final end = RegExp(
      '^\\s*$stopPattern\\s*\$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(available)?.start;
    if (end == null) continue;
    final ranges = <DmxRange>[];
    for (final rawLine
        in available.substring(0, end).split(RegExp(r'[\r\n]+'))) {
      final match = RegExp(
        r'^\s*(?:\d{1,3}\s+)?(\d{1,3})\s*[-–—]\s*(\d{1,3})\s+(.+?)\s*$',
      ).firstMatch(rawLine);
      if (match == null) continue;
      final start = int.parse(match.group(1)!);
      final finish = int.parse(match.group(2)!);
      if (start > finish || finish > 255) continue;
      final name = _cleanFunction(match.group(3)!);
      if (name.isEmpty || _looksLikePageFurniture(name)) continue;
      ranges.add(
        DmxRange(
          start: start,
          end: finish,
          name: name,
          safety:
              name.toLowerCase().contains('strobe') &&
                  !name.toLowerCase().contains('off')
              ? 'strobe'
              : 'normal',
          confidence: .95,
        ),
      );
    }
    ranges.sort((left, right) => left.start.compareTo(right.start));
    return ranges;
  }
  return const [];
}

List<DmxRange> _supplementalRangesFor(
  _DetectedChannel channel,
  Map<String, List<DmxRange>> supplemental,
) {
  final lower = channel.name.toLowerCase();
  final isUndividedStrobe =
      channel.kind == 'strobe' &&
      channel.ranges?.length == 1 &&
      channel.ranges!.single.start == 0 &&
      channel.ranges!.single.end == 255;
  final key = lower == 'shutter / strobe' || isUndividedStrobe
      ? 'shutter'
      : lower == 'color temperature'
      ? 'color-temperature'
      : lower == 'mode table 1'
      ? 'mode-1'
      : lower == 'mode table 2'
      ? 'mode-2'
      : lower == 'background color'
      ? 'background-color'
      : null;
  return key == null ? const [] : supplemental[key] ?? const [];
}

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

/// Parses manuals that define explicitly named DMX modes and then build larger
/// modes by inheriting a smaller mode plus a repeated pixel block. This is a
/// common layout in current professional-fixture manuals.
List<_DetectedModeTable> _namedDmxModeTables(String text) {
  final heading = RegExp(
    r'^\s*([A-Za-z][A-Za-z0-9 /-]{1,48}?)\s+DMX\s+Mode\s*\n\s*(\d{1,4})\s+DMX\s+channels?\b',
    caseSensitive: false,
    multiLine: true,
  );
  final matches = heading.allMatches(text).toList();
  if (matches.length < 2) return const [];

  final modes = <_DetectedModeTable>[];
  final byName = <String, _DetectedModeTable>{};
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final name = _titleCaseWords(match.group(1)!.trim());
    final count = int.parse(match.group(2)!);
    if (count < 1 || count > 32768) continue;
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : text.length;
    var section = text.substring(match.end, end);
    final supplementalHeading = RegExp(
      r'^\s*(?:Control/Settings DMX channel|FX list)\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(section);
    if (supplementalHeading != null) {
      section = section.substring(0, supplementalHeading.start);
    }
    final parsed = <int, _DetectedChannel>{};
    var inheritedCount = 0;

    final inherited = RegExp(
      r'Channels?\s+1\s*[-–—]\s*(\d{1,4})\s+as\s+in\s+(.+?)\s+Mode',
      caseSensitive: false,
    ).firstMatch(section);
    if (inherited != null) {
      inheritedCount = int.parse(inherited.group(1)!);
      final parent = byName[_modeNameKey(inherited.group(2)!)];
      if (parent != null) {
        for (
          var position = 1;
          position <= inheritedCount && position <= parent.channels.length;
          position++
        ) {
          parsed[position] = parent.channels[position - 1];
        }
      }
    }

    parsed.addAll(
      _parseNamedModeRows(section, count, startAt: inheritedCount + 1),
    );
    _expandRepeatedRgbBlocks(section, count, parsed);
    final mode = _DetectedModeTable(
      code: name,
      channelCount: count,
      parsedCount: parsed.length,
      channels: [
        for (var position = 1; position <= count; position++)
          parsed[position] ??
              _DetectedChannel(
                name: 'Channel $position',
                kind: 'generic',
                confidence: .25,
              ),
      ],
    );
    modes.add(mode);
    byName[_modeNameKey(name)] = mode;
  }
  return modes;
}

Map<int, _DetectedChannel> _parseNamedModeRows(
  String section,
  int count, {
  int startAt = 1,
}) {
  final parsed = <int, _DetectedChannel>{};
  String? pendingFunction;
  int? mostRecentCoarse;
  var expectedPosition = startAt;
  for (final rawLine in section.split(RegExp(r'[\r\n]+'))) {
    final line = _normalizeTableLine(rawLine);
    if (line.isEmpty ||
        line.startsWith('=== DMXTRACT PAGE') ||
        RegExp(
          r'^(?:channel|dmx value|function|fade|type|default|channels? 1\b)',
          caseSensitive: false,
        ).hasMatch(line) ||
        _looksLikePageFurniture(line)) {
      continue;
    }

    final barePosition = RegExp(r'^(\d{1,4})$').firstMatch(line);
    if (barePosition != null) {
      final position = int.parse(barePosition.group(1)!);
      if (position == expectedPosition && position <= count) {
        final coarse = parsed[position - 1];
        if (coarse != null && coarse.fineOf == null) {
          parsed[position] = _fineChannelFor(coarse);
          expectedPosition++;
        }
      }
      continue;
    }

    final row = RegExp(r'^(\d{1,4})\s+(.+)$').firstMatch(line);
    if (row != null) {
      final position = int.parse(row.group(1)!);
      if (position < 1 || position > count) continue;
      if (parsed.containsKey(position)) continue;
      if (position != expectedPosition) continue;
      final rest = row.group(2)!.trim();
      final beginsWithValue = RegExp(
        r'^(?:\d{1,5}\s*[-–—]\s*\d{1,5}|\d{1,5})\b|^(?:…|\.\.\.)',
      ).hasMatch(rest);
      final isSixteenBit = RegExp(r'\b0\s*[-–—]\s*65535\b').hasMatch(rest);

      final containsFineValue =
          isSixteenBit || RegExp(r'\b(?:32768|65535)\b').hasMatch(rest);
      if (containsFineValue &&
          mostRecentCoarse != null &&
          position == mostRecentCoarse + 1) {
        final coarse = parsed[mostRecentCoarse];
        if (coarse != null) {
          parsed[position] = _fineChannelFor(coarse);
          expectedPosition++;
          pendingFunction = null;
          continue;
        }
      }

      var description = beginsWithValue
          ? pendingFunction ?? _descriptionAfterDmxValue(rest)
          : pendingFunction != null &&
                RegExp(r'^[a-z(]', caseSensitive: true).hasMatch(rest)
          ? '$pendingFunction $rest'
          : rest;
      description = _cleanNamedFunction(description);
      if (description.isEmpty || _looksLikePageFurniture(description)) {
        continue;
      }
      final definition = _classifyTableChannel(description, position);
      final ranges = _rangesFromLine(rest, definition.name, definition.kind);
      parsed.putIfAbsent(
        position,
        () => _DetectedChannel(
          name: definition.name,
          kind: definition.kind,
          fineOf: definition.fineOf,
          color: definition.color,
          ranges: ranges,
          confidence: definition.confidence,
        ),
      );
      if (definition.fineOf == null) mostRecentCoarse = position;
      expectedPosition++;
      pendingFunction = null;
      continue;
    }

    final candidate = _cleanNamedFunction(line);
    if (pendingFunction == null && _isStandaloneChannelFunction(candidate)) {
      pendingFunction = candidate;
    }
  }
  _seedSpanningChannel(
    section,
    parsed,
    count,
    r'Virtual color wheel',
    const _DetectedChannel(name: 'Virtual color wheel', kind: 'colorWheel'),
  );
  _seedWrappedP3Channel(section, parsed, count, 'Beam');
  _seedWrappedP3Channel(section, parsed, count, 'Aura');
  return parsed;
}

void _seedWrappedP3Channel(
  String section,
  Map<int, _DetectedChannel> parsed,
  int count,
  String area,
) {
  final label = RegExp(
    '$area P3 Mix',
    caseSensitive: false,
  ).firstMatch(section);
  if (label == null) return;
  final tail = section.substring(label.end);
  final positionMatch = RegExp(
    r'^\s*(\d{1,4})\s+.*controlled by DMX',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(tail);
  final position = int.tryParse(positionMatch?.group(1) ?? '');
  if (position == null || position < 1 || position > count) return;
  parsed[position] = _DetectedChannel(name: '$area P3 mix', kind: 'mode');
}

void _seedSpanningChannel(
  String section,
  Map<int, _DetectedChannel> parsed,
  int count,
  String labelPattern,
  _DetectedChannel definition,
) {
  final label = RegExp(labelPattern, caseSensitive: false).firstMatch(section);
  if (label == null) return;
  final tail = section.substring(label.end);
  for (final match in RegExp(
    r'^\s*(\d{1,4})\s+(?:\d{1,5}\s*[-–—]\s*\d{1,5}|\d{1,5})\b',
    multiLine: true,
  ).allMatches(tail)) {
    final position = int.parse(match.group(1)!);
    if (position < 1 || position > count) continue;
    parsed[position] = definition;
    return;
  }
}

void _expandRepeatedRgbBlocks(
  String section,
  int count,
  Map<int, _DetectedChannel> parsed,
) {
  final beam = RegExp(
    r'(\d{1,3})\s*x\s*RGB\s+channels?\s*=\s*(\d{1,4})\s+channels?\s+for\s+individual\s+RGB\s+Beam\s+pixel',
    caseSensitive: false,
  ).firstMatch(section);
  if (beam != null) {
    final pixels = int.parse(beam.group(1)!);
    final blockSize = int.parse(beam.group(2)!);
    final start = count - blockSize + 1;
    _addRgbTemplate(parsed, start, pixels, 'Beam pixel');
  }

  final auraPixels = RegExp(
    r'(\d{1,4})\s+channels?\s+for\s+individual\s+RGB\s+control\s+of\s+all\s+(\d{1,4})\s+Aura\s+pixels',
    caseSensitive: false,
  ).firstMatch(section);
  if (auraPixels != null) {
    final blockSize = int.parse(auraPixels.group(1)!);
    final pixels = int.parse(auraPixels.group(2)!);
    _addRgbTemplate(parsed, count - blockSize + 1, pixels, 'Aura pixel');
  }

  final auraSegments = RegExp(
    r'(\d{1,4})\s+channels?\s+for\s+Aura\s+control\s+in\s+segments',
    caseSensitive: false,
  ).firstMatch(section);
  if (auraSegments != null) {
    final blockSize = int.parse(auraSegments.group(1)!);
    final segments = blockSize ~/ 3;
    final start = count - blockSize + 1;
    for (var segment = 1; segment <= segments; segment++) {
      final label = segment <= 37
          ? 'Aura pixels around Beam pixel $segment'
          : segment == 38
          ? 'Inner Aura ring'
          : segment == 39
          ? 'Second Aura ring'
          : 'Aura segment $segment';
      _addRgbTriplet(parsed, start + (segment - 1) * 3, label);
    }
  }
}

void _addRgbTemplate(
  Map<int, _DetectedChannel> parsed,
  int start,
  int pixels,
  String label,
) {
  for (var pixel = 1; pixel <= pixels; pixel++) {
    _addRgbTriplet(parsed, start + (pixel - 1) * 3, '$label $pixel');
  }
}

void _addRgbTriplet(
  Map<int, _DetectedChannel> parsed,
  int position,
  String label,
) {
  const colors = [('Red', 'RED'), ('Green', 'GREEN'), ('Blue', 'BLUE')];
  for (var index = 0; index < colors.length; index++) {
    parsed[position + index] = _DetectedChannel(
      name: '$label ${colors[index].$1}',
      kind: 'colorIntensity',
      color: colors[index].$2,
    );
  }
}

_DetectedChannel _fineChannelFor(_DetectedChannel coarse) => _DetectedChannel(
  name: '${coarse.name} fine',
  kind: coarse.kind,
  fineOf: _relationshipKey(coarse),
  color: coarse.color,
  confidence: coarse.confidence,
);

String _descriptionAfterDmxValue(String value) => value
    .replaceFirst(RegExp(r'^(?:\d{1,5}\s*[-–—]\s*\d{1,5}|\d{1,5})\s*'), '')
    .trim();

String _cleanNamedFunction(String value) => _cleanFunction(value)
    .replaceAll('*', '')
    .replaceAll(RegExp(r'\s+(?:Fade|Snap)\s+\d+\s*$', caseSensitive: false), '')
    .trim();

bool _isStandaloneChannelFunction(String value) {
  if (value.length > 90 ||
      RegExp(
        r'aura backlight control.*all aura leds',
        caseSensitive: false,
      ).hasMatch(value) ||
      RegExp(
        r'^(?:channels?|dmx|fade|default|type|intensity\b|no function)',
        caseSensitive: false,
      ).hasMatch(value)) {
    return false;
  }
  return RegExp(
    r'\b(?:shutter|strobe|dimmer|red|green|blue|lime|ctc|temperature|tint|color wheel|p3 mix|fx|aura|zoom|beamshaper|pan|tilt|fixture control|pwm)\b',
    caseSensitive: false,
  ).hasMatch(value);
}

String _modeNameKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String _titleCaseWords(String value) => value
    .split(RegExp(r'\s+'))
    .map((word) {
      if (word.isEmpty) return word;
      if (RegExp(r'^(?:PXL|RGB|DMX)$', caseSensitive: false).hasMatch(word)) {
        return word.toUpperCase();
      }
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    })
    .join(' ');

/// Parses tables where several named personalities are printed in parallel.
/// Channel numbers are column values, so duplicate channel counts remain
/// distinct layouts instead of being collapsed into one generic mode.
List<_DetectedModeTable> _contextualPersonalityTables(String text) {
  final contexts = RegExp(
    r'^\s*(Single Control Mode|Dual Control Mode\s*-\s*Movement|Dual Control Mode\s*-\s*Pixels)\s*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(text).toList();
  if (contexts.length < 2) return const [];
  final modes = <_DetectedModeTable>[];
  for (var contextIndex = 0; contextIndex < contexts.length; contextIndex++) {
    final contextMatch = contexts[contextIndex];
    final contextName = _contextDisplayName(contextMatch.group(1)!);
    final contextEnd = contextIndex + 1 < contexts.length
        ? contexts[contextIndex + 1].start
        : text.length;
    final context = text.substring(contextMatch.end, contextEnd);
    final groupHeading = RegExp(
      r'^\s*([A-Za-z][A-Za-z0-9 ]*?\s*\(\d{1,3}CH\)(?:\s*/\s*[A-Za-z][A-Za-z0-9 ]*?\s*\(\d{1,3}CH\))*)\s*$',
      caseSensitive: false,
      multiLine: true,
    );
    final groups = groupHeading.allMatches(context).toList();
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      final personalities = RegExp(
        r'([A-Za-z][A-Za-z0-9 ]*?)\s*\((\d{1,3})CH\)',
        caseSensitive: false,
      ).allMatches(group.group(1)!).toList();
      if (personalities.isEmpty) continue;
      final end = groupIndex + 1 < groups.length
          ? groups[groupIndex + 1].start
          : context.length;
      final section = context.substring(group.end, end);
      final columnOrder = _parallelPersonalityColumnOrder(
        personalities,
        section,
      );
      final parsed = <Map<int, _DetectedChannel>>[
        for (final _ in personalities) <int, _DetectedChannel>{},
      ];
      _parseParallelPersonalityRows(section, [
        for (final index in columnOrder)
          int.parse(personalities[index].group(2)!),
      ], parsed);
      for (
        var columnIndex = 0;
        columnIndex < personalities.length;
        columnIndex++
      ) {
        final modeIndex = columnOrder[columnIndex];
        _inferFineChannelGaps(
          parsed[columnIndex],
          int.parse(personalities[modeIndex].group(2)!),
        );
      }
      for (var modeIndex = 0; modeIndex < personalities.length; modeIndex++) {
        final personality = personalities[modeIndex];
        final columnIndex = columnOrder.indexOf(modeIndex);
        final count = int.parse(personality.group(2)!);
        final modeName =
            '$contextName · ${_titleCaseWords(personality.group(1)!)}';
        modes.add(
          _DetectedModeTable(
            code: modeName,
            channelCount: count,
            parsedCount: parsed[columnIndex].length,
            channels: [
              for (var position = 1; position <= count; position++)
                parsed[columnIndex][position] ??
                    _DetectedChannel(
                      name: 'Channel $position',
                      kind: 'generic',
                      confidence: .25,
                    ),
            ],
          ),
        );
      }
    }
  }
  return modes;
}

List<int> _parallelPersonalityColumnOrder(
  List<RegExpMatch> personalities,
  String section,
) {
  final ordinary = List<int>.generate(personalities.length, (index) => index);
  if (personalities.length < 2) return ordinary;
  final headerLines = section
      .substring(0, section.length.clamp(0, 500))
      .split(RegExp(r'[\r\n]+'))
      .take(10)
      .toList();
  final positions = <(int, double)>[];
  for (var index = 0; index < personalities.length; index++) {
    final center = _parallelHeaderCenter(
      personalities[index].group(1)!,
      headerLines,
    );
    if (center == null) return ordinary;
    positions.add((index, center));
  }
  positions.sort((left, right) => left.$2.compareTo(right.$2));
  for (var index = 1; index < positions.length; index++) {
    if ((positions[index].$2 - positions[index - 1].$2).abs() < 2) {
      return ordinary;
    }
  }
  return positions.map((item) => item.$1).toList();
}

double? _parallelHeaderCenter(String name, List<String> lines) {
  final tokens = name
      .replaceAllMapped(
        RegExp(r'(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])'),
        (_) => ' ',
      )
      .trim()
      .split(RegExp(r'\s+'));
  final candidates = <List<double>>[];
  for (final token in tokens) {
    final centers = <double>[];
    final pattern = RegExp(
      '\\b${RegExp.escape(token)}\\b',
      caseSensitive: false,
    );
    for (final line in lines) {
      for (final match in pattern.allMatches(line)) {
        centers.add(match.start + match.group(0)!.length / 2);
      }
    }
    if (centers.isEmpty) return null;
    candidates.add(centers);
  }
  var selected = candidates.first.first;
  final chosen = <double>[selected];
  for (final options in candidates.skip(1)) {
    final average = chosen.reduce((a, b) => a + b) / chosen.length;
    selected = options.reduce(
      (left, right) =>
          (left - average).abs() <= (right - average).abs() ? left : right,
    );
    chosen.add(selected);
  }
  if (chosen.reduce((a, b) => a > b ? a : b) -
          chosen.reduce((a, b) => a < b ? a : b) >
      8) {
    return null;
  }
  return chosen.reduce((a, b) => a + b) / chosen.length;
}

void _inferFineChannelGaps(
  Map<int, _DetectedChannel> parsed,
  int channelCount,
) {
  for (var position = 2; position <= channelCount; position++) {
    final coarse = parsed[position - 1];
    final current = parsed[position];
    final following = parsed[position + 1];
    if (current != null &&
        coarse != null &&
        coarse.fineOf == null &&
        const {
          'colorIntensity',
          'intensity',
          'pan',
          'tilt',
          'zoom',
        }.contains(coarse.kind) &&
        (current.fineOf != null ||
            current.name.toLowerCase().startsWith('fine ') ||
            current.kind == 'generic' &&
                RegExp(r'^\d{1,3}$').hasMatch(current.name))) {
      parsed[position] = _fineChannelFor(coarse);
      continue;
    }
    if (current != null) continue;
    if (coarse == null ||
        following == null ||
        coarse.fineOf != null ||
        !const {
          'colorIntensity',
          'intensity',
          'pan',
          'tilt',
          'zoom',
        }.contains(coarse.kind)) {
      continue;
    }
    parsed[position] = _fineChannelFor(coarse);
  }
}

void _parseParallelPersonalityRows(
  String section,
  List<int> counts,
  List<Map<int, _DetectedChannel>> parsed,
) {
  final token = r'(?:\d{1,3}|[-–—])';
  final prefix = RegExp(
    '^\\s*(${List.filled(counts.length, '$token\\s+').join()})(.+?)\\s*\$',
  );
  for (final rawLine in section.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.replaceAll(RegExp(r'[|]'), ' ');
    final match = prefix.firstMatch(line);
    if (match == null) continue;
    final positions = RegExp(
      token,
    ).allMatches(match.group(1)!).map((item) => item.group(0)!).toList();
    if (positions.length != counts.length) continue;
    var description = match
        .group(2)!
        .replaceFirst(RegExp(r'\s+\d{1,3}\s*[↔⇔–—-]\s*\d{1,3}.*$'), '')
        .replaceFirst(
          RegExp(r'\s+\d{1,3}\s+No function.*$', caseSensitive: false),
          '',
        )
        .trim();
    description = _cleanFunction(description);
    if (description.isEmpty ||
        RegExp(r'^[↔⇔–—-]').hasMatch(description) ||
        RegExp(
          r'^(?:CH|Function|Value)',
          caseSensitive: false,
        ).hasMatch(description)) {
      continue;
    }
    for (var modeIndex = 0; modeIndex < counts.length; modeIndex++) {
      final position = int.tryParse(positions[modeIndex]);
      if (position == null || position < 1 || position > counts[modeIndex]) {
        continue;
      }
      if (parsed[modeIndex].containsKey(position)) continue;
      final definition = _classifyTableChannel(description, position);
      final ranges = _rangesFromLine(
        match.group(2)!,
        definition.name,
        definition.kind,
      );
      parsed[modeIndex][position] = _DetectedChannel(
        name: definition.name,
        kind: definition.kind,
        fineOf: definition.fineOf,
        color: definition.color,
        ranges: ranges,
        confidence: definition.confidence,
      );
    }
  }
}

String _contextDisplayName(String value) {
  final lower = value.toLowerCase();
  if (lower.contains('movement')) return 'Movement';
  if (lower.contains('pixels')) return 'Pixels';
  return 'Single';
}

/// Parses "mode-matrix" tables — the Chauvet DJ house style where several DMX
/// modes are printed as parallel channel-number columns ahead of a shared
/// Function/Value column, e.g. a header row of "3Ch 12Ch 28Ch Function Value
/// Percent/Setting" followed by rows like "– 3 1 Red 1 000 255 0-100%" where
/// a dash means the function does not exist in that mode. Some rows carry
/// two alternative functions for the same channel (e.g. "Program speed" vs
/// "Sound sensitivity", selected by another channel's value); those merge
/// into one channel with a combined name. The table commonly continues onto
/// a following page behind a repeated header row and footer/header
/// furniture, which this parser treats as one continuous section because the
/// repeated header does not match the row grammar and simply falls through.
///
/// This is deliberately a separate path from [_contextualPersonalityTables]:
/// that parser keys mode boundaries off named "Single/Dual Control Mode"
/// section headings and "Name (NCh)" personality groups, neither of which
/// this table has — its header is the numeric "NCh" tokens themselves, with
/// no named personality and no section heading. Reusing that path would mean
/// teaching it to recognize a second, incompatible heading grammar and a
/// second row grammar (single shared description column instead of one
/// description per personality group); a focused parser is clearer than
/// contorting the existing one to serve two different table shapes.
///
/// Same start-end separator class used elsewhere in this file (dash
/// variants, arrows, 'ó', and U+F0F3 — the two glyphs PDF.js's text layer
/// resolves a particular Chauvet symbol-font's separator glyph to,
/// depending on the PDF's embedded font/ToUnicode map; poppler's pdftotext
/// leaves the same glyph unresolved as the raw PUA codepoint, which is why
/// a `pdftotext -layout` dump and the in-app PDF.js pipeline can disagree
/// here for the same PDF) instead of plain whitespace, since that glyph is
/// what actually separates the two value numbers in this table family.
const _rangeSeparatorClass = '[-–—↔⇔ó]';

/// A mode-matrix row's leading per-mode position cell: either a channel
/// number or a dash meaning "this function does not exist in this mode".
/// Shared between [_parseModeMatrixSection]'s row grammar and
/// [_mergeSplitMatrixRows]'s line-rejoining pass so the two agree on what
/// counts as a bare position token.
const _matrixTokenPattern = r'(?:\d{1,3}|[-–—])';

List<_DetectedModeTable> _modeMatrixTables(String text) {
  final headerPattern = RegExp(
    r'^[ \t]*((?:\d{1,3}\s*-?\s*Ch\b[ \t]*){2,})Function\b',
    caseSensitive: false,
    multiLine: true,
  );
  final matches = headerPattern.allMatches(text).toList();
  if (matches.isEmpty) return const [];
  List<int> countsOf(RegExpMatch match) => RegExp(
    r'(\d{1,3})\s*-?\s*Ch\b',
    caseSensitive: false,
  ).allMatches(match.group(1)!).map((m) => int.parse(m.group(1)!)).toList();

  final tables = <_DetectedModeTable>[];
  var index = 0;
  while (index < matches.length) {
    final counts = countsOf(matches[index]);
    if (counts.length < 2) {
      index++;
      continue;
    }
    // A repeated header with the same column sizes (a page-break
    // continuation) extends the current section instead of starting a new
    // table; a header with different column sizes starts a new table.
    var next = index + 1;
    while (next < matches.length &&
        _sameCounts(countsOf(matches[next]), counts)) {
      next++;
    }
    final sectionEnd = next < matches.length
        ? matches[next].start
        : text.length;
    final section = text.substring(matches[index].end, sectionEnd);
    tables.addAll(_parseModeMatrixSection(section, counts));
    index = next;
  }
  return tables;
}

bool _sameCounts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _MatrixRow {
  _MatrixRow({
    required this.tokens,
    required this.description,
    required this.ranges,
    required this.mergeable,
  });
  final List<int?> tokens;
  String description;
  final List<DmxRange> ranges;
  final bool mergeable;
  bool merged = false;
}

/// Rejoins a channel-row whose leading mode-position tokens PDF.js's
/// `positionedText()` split across two physical lines. This happens when a
/// channel's row is tall (it carries several stacked value ranges) and one
/// of its position cells — typically a lone dash meaning "this function
/// does not exist in this mode" — sits at a slightly different vertical
/// center than the rest of that row's cells, so the ±2–5pt y-tolerance
/// grouping puts it in its own row. For example Sentinel_Wash_Q7Z_ILS's
/// channel 14 row prints as a bare "–" line followed by
/// "14 Movement macros   120 ó 135 Movement macro 8" on the next line,
/// instead of one "– 14 Movement macros ..." line.
///
/// Detects a line made up solely of 1..columnCount-1 bare position tokens
/// (dash or number, no other text) and, if the next non-blank/
/// non-furniture line starts with exactly the remaining tokens the row
/// needs, splices the two into one logical line so [_parseModeMatrixSection]'s
/// row grammar sees a normal, complete row. Requires every combined token to
/// be a plausible position in its mode (same check [_parseModeMatrixSection]
/// applies to a whole-line row match) before committing to the splice, so an
/// unrelated short line — a stray page number, for instance — followed by
/// ordinary prose can't get spliced into a bogus row.
List<String> _mergeSplitMatrixRows(List<String> lines, List<int> counts) {
  final columnCount = counts.length;
  final bareTokensLine = RegExp(
    '^(?:$_matrixTokenPattern[ \\t]+)*$_matrixTokenPattern\$',
  );
  final tokenMatcher = RegExp(_matrixTokenPattern);
  final merged = <String>[];
  var index = 0;
  while (index < lines.length) {
    final trimmed = lines[index].trim();
    final leadTokens = trimmed.isEmpty || !bareTokensLine.hasMatch(trimmed)
        ? null
        : tokenMatcher.allMatches(trimmed).toList();
    if (leadTokens != null && leadTokens.length < columnCount) {
      var next = index + 1;
      while (next < lines.length) {
        final nextTrimmed = lines[next].trim();
        if (nextTrimmed.isEmpty ||
            nextTrimmed.startsWith('=== DMXTRACT PAGE') ||
            _looksLikePageFurniture(nextTrimmed)) {
          next++;
          continue;
        }
        break;
      }
      final needed = columnCount - leadTokens.length;
      final prefixPattern = RegExp(
        '^[ \\t]*(?:$_matrixTokenPattern[ \\t]+){${needed - 1}}'
        '$_matrixTokenPattern(?=[ \\t]|\$)',
      );
      final prefixMatch = next < lines.length
          ? prefixPattern.firstMatch(lines[next])
          : null;
      if (prefixMatch != null) {
        final combined = [
          ...leadTokens.map((m) => int.tryParse(m.group(0)!)),
          ...tokenMatcher
              .allMatches(prefixMatch.group(0)!)
              .map((m) => int.tryParse(m.group(0)!)),
        ];
        var plausible = true;
        for (var position = 0; position < combined.length; position++) {
          final value = combined[position];
          if (value != null && (value < 1 || value > counts[position])) {
            plausible = false;
            break;
          }
        }
        if (plausible) {
          merged.add('$trimmed ${lines[next].trimLeft()}');
          index = next + 1;
          continue;
        }
      }
    }
    merged.add(lines[index]);
    index++;
  }
  return merged;
}

List<_DetectedModeTable> _parseModeMatrixSection(
  String section,
  List<int> counts,
) {
  final columnCount = counts.length;
  final rowPattern = RegExp(
    '^[ \\t]*((?:$_matrixTokenPattern[ \\t]+){${columnCount - 1}}'
    '$_matrixTokenPattern)(?:[ \\t]+(.+?))?[ \\t]*\$',
  );
  final tokenMatcher = RegExp(_matrixTokenPattern);
  // The same "start-end" separator class used throughout the file (dash
  // variants, arrows, and 'ó' — the character PDF.js resolves a particular
  // Chauvet PDF font's separator glyph to) rather than plain whitespace,
  // since that glyph — not extra spacing — is what actually sits between
  // the two value numbers in this table family.
  final twoNumberValue = RegExp(
    '^[ \\t]*(\\d{1,3})\\s*$_rangeSeparatorClass\\s*(\\d{1,3})[ \\t]+(.+?)[ \\t]*\$',
  );
  final oneNumberValue = RegExp(r'^[ \t]*(\d{1,3})[ \t]+(.+?)[ \t]*$');
  final columnSplit = RegExp(r'[ \t]{2,}');

  // The header declares exactly how many channels each mode has, so once
  // we've matched a row at the highest declared position of the widest mode
  // and filled its ranges to full 0-255 coverage, the table is provably
  // complete — see the `finalRow` check below, which bounds the section
  // instead of letting it run unbounded to the header search's fallback of
  // "rest of the document" and sweep up trailing prose/footers as ranges.
  final maxCount = counts.reduce((a, b) => a > b ? a : b);
  final maxIndex = counts.indexOf(maxCount);
  _MatrixRow? finalRow;

  final rows = <_MatrixRow>[];
  _MatrixRow? currentRow;
  var pendingRanges = <DmxRange>[];
  String? pendingFunction;
  var expectMergeRange = false;

  final lines = _mergeSplitMatrixRows(
    section.split(RegExp(r'\r\n|\r|\n')),
    counts,
  );
  for (final rawLine in lines) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('=== DMXTRACT PAGE') ||
        _looksLikePageFurniture(trimmed)) {
      continue;
    }

    final rowMatch = rowPattern.firstMatch(rawLine);
    final rowTokens = rowMatch == null
        ? null
        : tokenMatcher
              .allMatches(rowMatch.group(1)!)
              .map((m) => int.tryParse(m.group(0)!))
              .toList();
    // A line of `columnCount` dash/digit tokens is only really a channel
    // row if every non-dash token is a plausible position in its mode — a
    // value line like "001 – 250 Automatic program" tokenizes the same way
    // ([1, null, 250] for a 3Ch/12Ch/28Ch header) whenever the manual's
    // separator glyph happens to be one of the dash variants this class
    // also treats as a row-token placeholder, but 250 exceeds every mode's
    // declared channel count, so it belongs to the value grammar below
    // instead. Rejecting it here — rather than only when assigning parsed
    // positions to modes afterward — matters because accepting it would
    // otherwise consume `pendingRanges`/`pendingFunction` and become
    // `currentRow`, silently swallowing the real row that should have.
    var rowPlausible = rowTokens != null;
    if (rowTokens != null) {
      for (var i = 0; i < columnCount; i++) {
        final value = rowTokens[i];
        if (value != null && (value < 1 || value > counts[i])) {
          rowPlausible = false;
          break;
        }
      }
    }
    if (rowMatch != null && rowTokens != null && rowPlausible) {
      final tokens = rowTokens;
      final restRaw = (rowMatch.group(2) ?? '').trim();
      expectMergeRange = false;
      if (restRaw.isEmpty) {
        // A channel-row with no inline text: its function label lives on a
        // preceding standalone line (the common shape for a channel whose
        // function depends on another channel's value, e.g. "Program speed"
        // printed above a blank row for the channel it belongs to).
        final description = pendingFunction ?? '';
        final ranges = <DmxRange>[...pendingRanges];
        pendingRanges = [];
        pendingFunction = null;
        currentRow = _MatrixRow(
          tokens: tokens,
          description: description,
          ranges: ranges,
          mergeable: true,
        );
      } else {
        // The wide gap pdftotext/positionedText insert between real table
        // columns (>=2 spaces) separates the function name from an inline
        // value range; a plain function name with no digits has no such gap.
        final split = restRaw.split(columnSplit);
        final namePart = _cleanFunction(split.first);
        final inlineRange = split.length > 1
            ? _matrixInlineRange(split.sublist(1).join('   '))
            : null;
        final ranges = <DmxRange>[...pendingRanges, ?inlineRange];
        pendingRanges = [];
        pendingFunction = null;
        currentRow = _MatrixRow(
          tokens: tokens,
          description: namePart,
          ranges: ranges,
          mergeable: false,
        );
      }
      rows.add(currentRow);
      if (finalRow == null &&
          tokens.length > maxIndex &&
          tokens[maxIndex] == maxCount) {
        finalRow = currentRow;
      }
      if (identical(currentRow, finalRow) &&
          _rangesCoverFull(currentRow.ranges)) {
        // This row's own inline range (or the pending ranges gathered
        // ahead of it) already covers 0-255 by itself — e.g. a plain
        // "Full range" channel with no follow-up value lines — so the
        // table is complete right away; see the fuller explanation above
        // `finalRow`'s declaration.
        break;
      }
      continue;
    }

    int? valueStart;
    int? valueEnd;
    String? valueDescription;
    final two = twoNumberValue.firstMatch(rawLine);
    if (two != null) {
      final start = int.tryParse(two.group(1)!);
      final end = int.tryParse(two.group(2)!);
      if (start != null && end != null && start <= end && end <= 255) {
        valueStart = start;
        valueEnd = end;
        valueDescription = two.group(3);
      }
    }
    if (valueStart == null) {
      final one = oneNumberValue.firstMatch(rawLine);
      if (one != null) {
        final start = int.tryParse(one.group(1)!);
        if (start != null && start <= 255) {
          valueStart = start;
          valueEnd = start;
          valueDescription = one.group(2);
        }
      }
    }
    if (valueStart != null) {
      final range = _matrixRange(valueStart, valueEnd!, valueDescription ?? '');
      final target = currentRow;
      if (expectMergeRange && target != null) {
        // The range immediately following a merged alternate-function label
        // belongs to that alternate function, even though the channel's
        // ranges already cover 0-255 from its first function.
        target.ranges.add(range);
        expectMergeRange = false;
      } else if (target != null && !_rangesCoverFull(target.ranges)) {
        // A leading or trailing range line with no row of its own extends
        // whichever channel isn't fully covered yet — the same convention
        // _parseTableSection uses for ranges that precede or follow a row.
        target.ranges.add(range);
      } else {
        pendingRanges.add(range);
        continue;
      }
      if (identical(target, finalRow) && _rangesCoverFull(target.ranges)) {
        // The row we just extended is the last channel of this table's
        // widest mode (see `finalRow` above) and its ranges now cover the
        // full 0-255 span, so the table is provably complete — nothing
        // legitimately printed after this row belongs to it. Stopping here
        // keeps trailing manual content (the next prose section, page
        // footers, an appendix) from being swept in as bogus ranges on
        // whichever channel happened to be open when they were consumed.
        break;
      }
      continue;
    }

    if (_looksLikeMatrixFunctionLabel(trimmed)) {
      final label = _cleanFunction(trimmed);
      if (currentRow != null && currentRow.mergeable) {
        // A second bare label after a blank-inline row is this fixture's way
        // of printing an alternate function for the same DMX channel; fold
        // it into a combined name rather than treating it as a new channel.
        currentRow.description = currentRow.description.isEmpty
            ? label
            : '${currentRow.description} / $label';
        currentRow.merged = true;
        expectMergeRange = true;
      } else {
        pendingFunction ??= label;
      }
    }
  }

  final parsedByMode = List<Map<int, _DetectedChannel>>.generate(
    columnCount,
    (_) => <int, _DetectedChannel>{},
  );
  for (final row in rows) {
    if (row.description.isEmpty) continue;
    final definition = _classifyTableChannel(row.description, 1);
    final name = row.merged ? row.description : definition.name;
    for (var modeIndex = 0; modeIndex < columnCount; modeIndex++) {
      final position = row.tokens[modeIndex];
      if (position == null || position < 1 || position > counts[modeIndex]) {
        continue;
      }
      parsedByMode[modeIndex].putIfAbsent(
        position,
        () => _DetectedChannel(
          name: name,
          kind: definition.kind,
          fineOf: definition.fineOf,
          color: definition.color,
          ranges: List<DmxRange>.of(row.ranges),
          confidence: definition.confidence,
        ),
      );
    }
  }

  return [
    for (var modeIndex = 0; modeIndex < columnCount; modeIndex++)
      _DetectedModeTable(
        code: '${counts[modeIndex]}Ch',
        channelCount: counts[modeIndex],
        parsedCount: parsedByMode[modeIndex].length,
        channels: [
          for (var position = 1; position <= counts[modeIndex]; position++)
            parsedByMode[modeIndex][position] ??
                _DetectedChannel(
                  name: 'Channel $position',
                  kind: 'generic',
                  confidence: .25,
                ),
        ],
      ),
  ];
}

/// Parses an inline "000 ó 255 description" value that follows a function
/// name on the same physical row (used by e.g. "Red 1 ... 000 ó 255 0-100%").
DmxRange? _matrixInlineRange(String value) {
  final match = RegExp(
    '^[ \\t]*(\\d{1,3})\\s*$_rangeSeparatorClass\\s*(\\d{1,3})'
    '(?:[ \\t]+(.+?))?[ \\t]*\$',
  ).firstMatch(value);
  if (match == null) return null;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  if (start == null || end == null || start > end || end > 255) return null;
  return _matrixRange(start, end, match.group(3) ?? '');
}

/// Range name/safety inference shared by [_parseModeMatrixSection]'s two
/// range-building shapes — this inline "name ... 000 sep 255 text" row shape
/// ([_matrixInlineRange]) and the standalone "000 sep 255 text" value-line
/// shape — so a capability doesn't end up unsafe-by-default, or literally
/// named after a bare percentage like "0-100%", just because of which of
/// the two physical line shapes the manual happened to print it as. Channel
/// `kind` (which would let this defer to [_rangesFromLine]'s richer,
/// kind-aware fallback naming) isn't known yet at this point in the
/// matrix parse — classification only runs once a row's full description is
/// assembled — so this sticks to the text-only signals both call sites
/// already had available.
DmxRange _matrixRange(int start, int end, String rawName) {
  final name = _cleanFunction(rawName);
  final lower = name.toLowerCase();
  final isBarePercent = RegExp(
    r'^\d{1,3}(?:\.\d+)?\s*[-–—↔⇔]\s*\d{1,3}(?:\.\d+)?%$',
  ).hasMatch(name);
  return DmxRange(
    start: start,
    end: end,
    name: name.isEmpty || isBarePercent ? 'Full range' : name,
    safety: lower.contains('strobe') && !lower.contains('no function')
        ? 'strobe'
        : 'normal',
    confidence: .9,
  );
}

bool _looksLikeMatrixFunctionLabel(String value) {
  if (value.isEmpty || value.length > 60) return false;
  if (value.startsWith('(')) return false;
  // Real function labels in this table family are plain words ("Program
  // speed", "Motor rotation"); anything with a digit is either a value line
  // we already handled or page furniture (a title/revision/page number).
  if (RegExp(r'\d').hasMatch(value)) return false;
  if (_looksLikePageFurniture(value)) return false;
  if (RegExp(
    r'^(?:function|value|percent|setting|channel)\b',
    caseSensitive: false,
  ).hasMatch(value)) {
    return false;
  }
  return RegExp(r'[A-Za-z]').hasMatch(value);
}

/// Parses manuals that print "N-channel mode" / "N channel mode"
/// headings each followed by a sequential
/// Channel / Function / DMX Value / Functional Description table, a common
/// layout in budget moving-effect-light manuals (as opposed to the coded
/// "<code> Channel Table" layout [_codedChannelTables] handles, where the
/// function name trails the value range instead of leading it). A channel
/// with several value ranges (e.g. a nine-range strobe channel) simply
/// repeats as extra range-only rows under the same channel.
List<_DetectedModeTable> _sequentialModeTables(String text) {
  // A heading normally opens its own line, but a photographed two-column
  // spread OCRs with both columns run onto one physical line, landing a
  // later heading mid-line right after whatever the OCR engine put at the
  // gutter. That is sometimes a literal column-separator glyph ("|" or
  // ";"), but on real sideways-photographed manuals it is just as often
  // nothing more than an ordinary single space — no punctuation survives to
  // anchor on (measured on real photos: the same heading came through as
  // "...infinite rotation 42-channel mode" and "...adjust 58-channel mode",
  // plain space, no glyph). Accepting the heading anywhere it appears, not
  // just at true line start or after a gutter glyph, is what lets every
  // mode in a multi-mode manual get picked up instead of just the one whose
  // heading happened to survive on its own line; the corroboration
  // requirement below (2+ headings or a "DMX Channel Table" section
  // heading) is what keeps this from firing on a stray, unrelated mention
  // of a channel count in ordinary prose.
  final heading = RegExp(
    // The gap between the digit and "channel" is deliberately [ \t], not
    // \s: \s also matches a newline, and this heading isn't anchored to
    // line start (see above), so that would let it bridge two unrelated
    // physical lines — e.g. an "...UNIT 4" table-column label immediately
    // followed by an unrelated "CHANNEL MODE" section heading on the next
    // line reads as "4\n  CHANNEL MODE", a bogus 4-channel mode heading.
    r'(\d{1,3})[ \t]*-?[ \t]*channel\s+mode\b',
    caseSensitive: false,
    multiLine: true,
  );
  final matches = heading.allMatches(text).toList();
  if (matches.isEmpty) return const [];
  final hasChannelTableHeading = RegExp(
    r'\bDMX\s+Channel\s+Table\b',
    caseSensitive: false,
  ).hasMatch(text);
  // A single heading on its own is too easy to hit by accident (stray prose
  // mentioning a channel count); require either a second sequential-mode
  // heading or a "DMX Channel Table" section heading to corroborate that
  // this manual actually uses this table dialect before committing to it.
  if (matches.length < 2 && !hasChannelTableHeading) return const [];

  // A heading repeating on a continuation page (a long table split across
  // pages commonly reprints its heading after the page break) must not
  // start a second, discarded table: every occurrence of a given channel
  // count is parsed into the *same* channel map, keyed by first-seen
  // order, so the rows that follow a repeated heading are kept instead of
  // silently lost.
  final order = <int>[];
  final parsedByCount = <int, Map<int, _DetectedChannel>>{};
  for (var index = 0; index < matches.length; index++) {
    final match = matches[index];
    final channelCount = int.tryParse(match.group(1)!);
    if (channelCount == null || channelCount < 1 || channelCount > 512) {
      continue;
    }
    final end = index + 1 < matches.length
        ? matches[index + 1].start
        : text.length;
    final section = text.substring(match.end, end);
    final parsed = parsedByCount.putIfAbsent(channelCount, () {
      order.add(channelCount);
      return <int, _DetectedChannel>{};
    });
    _parseSequentialModeRows(section, channelCount, parsed);
  }

  final modes = <_DetectedModeTable>[];
  for (final channelCount in order) {
    final parsed = parsedByCount[channelCount]!;
    _fillRepeatedColorSeries(parsed, channelCount);
    modes.add(
      _DetectedModeTable(
        code: '$channelCount-channel mode',
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
      ),
    );
  }
  return modes;
}

void _parseSequentialModeRows(
  String section,
  int channelCount,
  Map<int, _DetectedChannel> parsed,
) {
  // Channel + function + value range on one physical row, e.g.
  // "1 X-axis 0-255 (0-540 degrees)".
  final fullRow = RegExp(
    '^\\s*(\\d{1,3})\\s+(.*?)\\s*(\\d{1,3})\\s*$_rangeSeparatorClass'
    '\\s*(\\d{1,3})(?:\\s+(.*?))?\\s*\$',
  );
  // A follow-up value range for the channel currently being read, printed
  // with no channel number of its own — how a multi-range channel (a
  // strobe's nine speed bands, a rotation channel's four control zones)
  // continues after its first row.
  final continuationRow = RegExp(
    '^\\s*(\\d{1,3})\\s*$_rangeSeparatorClass\\s*(\\d{1,3})'
    '(?:\\s+(.*?))?\\s*\$',
  );
  // Channel + function with no value range on this row — the range(s)
  // follow as continuation rows below.
  final functionOnlyRow = RegExp(r'^\s*(\d{1,3})\s+([A-Za-z].*?)\s*$');
  final ellipsisRow = RegExp(r'^(?:\.{2,}|…+)(?:\s+(?:\.{2,}|…+))*$');

  int? currentChannel;
  for (final rawLine in section.split(RegExp(r'[\r\n]+'))) {
    final normalized = _normalizeTableLine(rawLine);
    if (normalized.isEmpty ||
        normalized.startsWith('=== DMXTRACT PAGE') ||
        _looksLikePageFurniture(normalized) ||
        ellipsisRow.hasMatch(normalized)) {
      // A literal "......"/"……" row stands in for the intermediate channels
      // of a repeated RGBW-per-zone block; skipping it here (rather than
      // trying to parse it) lets _fillRepeatedColorSeries synthesize those
      // channels afterward from the explicit zones printed before and after
      // the ellipsis.
      continue;
    }
    final line = _resolveSequentialLine(normalized, fullRow, continuationRow);

    final full = fullRow.firstMatch(line);
    if (full != null) {
      final position = int.parse(full.group(1)!);
      if (position < 1 || position > channelCount) continue;
      final start = _normalizeDmxValue(int.parse(full.group(3)!));
      final end = _normalizeDmxValue(int.parse(full.group(4)!));
      if (start > end || end > 255) continue;
      final functionText = _cleanFunction(full.group(2)!);
      final description = _cleanFunction(full.group(5) ?? '');
      final classifyText = functionText.isNotEmpty
          ? _prepareSequentialFunctionName(functionText)
          : description;
      final definition = _classifyTableChannel(classifyText, position);
      final range = _rangeFromParts(
        start,
        end,
        description.isNotEmpty ? description : functionText,
        definition.kind,
      );
      parsed[position] = _mergeDetectedChannel(
        parsed[position],
        definition,
        range,
      );
      currentChannel = position;
      continue;
    }

    final continuationMatch = continuationRow.firstMatch(line);
    if (continuationMatch != null && currentChannel != null) {
      final start = _normalizeDmxValue(int.parse(continuationMatch.group(1)!));
      final end = _normalizeDmxValue(int.parse(continuationMatch.group(2)!));
      final existing = parsed[currentChannel];
      if (start <= end && end <= 255 && existing != null) {
        final description = _cleanFunction(continuationMatch.group(3) ?? '');
        parsed[currentChannel] = _mergeDetectedChannel(
          existing,
          existing,
          _rangeFromParts(start, end, description, existing.kind),
        );
      }
      continue;
    }

    final functionOnly = functionOnlyRow.firstMatch(line);
    if (functionOnly != null) {
      final position = int.parse(functionOnly.group(1)!);
      if (position < 1 || position > channelCount) continue;
      final functionText = _cleanFunction(functionOnly.group(2)!);
      if (functionText.isEmpty || _looksLikePageFurniture(functionText)) {
        continue;
      }
      final definition = _classifyTableChannel(
        _prepareSequentialFunctionName(functionText),
        position,
      );
      parsed.putIfAbsent(
        position,
        () => _DetectedChannel(
          name: definition.name,
          kind: definition.kind,
          fineOf: definition.fineOf,
          color: definition.color,
          ranges: <DmxRange>[],
          confidence: definition.confidence,
        ),
      );
      currentChannel = position;
    }
  }
}

/// Rewrites a "Color Dimming"/"Color Dimmer" function name — either
/// fully spelled ("Red Dimming") or an abbreviated per-zone LED code ("R1
/// LED Dimming") — down to just the color token so [_classifyTableChannel]
/// resolves it through one of its per-color branches instead of its
/// generic-dimmer branch, which would otherwise discard which color (and
/// zone) the dimmer controls: that branch's "dimmer/dimming/intensity"
/// check runs before the color-aware checks and matches on the word
/// "Dimming" alone.
const _sequentialLetterColors = <String, String>{
  'r': 'Red',
  'g': 'Green',
  'b': 'Blue',
  'w': 'White',
  'a': 'Amber',
  'uv': 'UV',
};

String _prepareSequentialFunctionName(String value) {
  final colorDimming = RegExp(
    r'^(Red|Green|Blue|White|Amber|UV|Ultraviolet)\s+Dimm(?:ing|er)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (colorDimming != null) return colorDimming.group(1)!;
  // The single-letter shorthand ("R Dimming", "W Dimmer") this manual
  // family's RGBW master-dimming rows actually print; expand it to the
  // full color name so it takes the same color-aware path as the
  // spelled-out form above instead of falling into the generic
  // dimmer/dimming/intensity branch of [_classifyTableChannel], which
  // matches on the word "dimming" alone and drops which color it is.
  final letterDimming = RegExp(
    r'^([RGBWA]|UV)\s+Dimm(?:ing|er)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (letterDimming != null) {
    return _sequentialLetterColors[letterDimming.group(1)!.toLowerCase()]!;
  }
  final zoneDimming = RegExp(
    r'^([RGBW])(\d{1,2})\s+LED\s+Dimm(?:ing|er)$',
    caseSensitive: false,
  ).firstMatch(value);
  if (zoneDimming != null) {
    return '${zoneDimming.group(1)}${zoneDimming.group(2)}';
  }
  // A bare trailing color letter after a "Light strip" prefix ("Light
  // strip R") is this manual family's shorthand for the light strip
  // sub-fixture's color channels. Scoped to this specific prefix (rather
  // than any function name that happens to end in a single letter) so
  // unrelated text isn't misread as a color.
  final lightStripColor = RegExp(
    r'^Light\s*strip\s+([RGBWA])$',
    caseSensitive: false,
  ).firstMatch(value);
  if (lightStripColor != null) {
    return _sequentialLetterColors[lightStripColor.group(1)!.toLowerCase()]!;
  }
  return value;
}

/// Chooses between a row's normalized text and its digit-rejoined variant
/// (see [_rejoinDigitSplitRangeTokens]) for value-range matching.
///
/// The rejoin is a blunt instrument: its digit-run pattern can't tell a
/// genuinely OCR-split byte value ("19 0" -> "190") apart from an unrelated
/// digit at the end of the function-name column bumping into the value
/// column's leading digit ("...Zone 1 0-255..." -> "...Zone 10-255...").
/// So the normalized line is tried first, and only displaced by the
/// rejoined line when the normalized reading isn't trustworthy: no match at
/// all, a numerically invalid range, or (for a full row) no function text —
/// an empty function is the fingerprint of the false rejoin candidate above,
/// since the digit that should have started the value instead got read as
/// the whole "function", leaving the value's own leading digit to open the
/// range early.
String _resolveSequentialLine(
  String normalized,
  RegExp fullRow,
  RegExp continuationRow,
) {
  final rejoined = _rejoinDigitSplitRangeTokens(normalized);
  if (rejoined == normalized) return normalized;
  if (_isConfidentSequentialRowMatch(normalized, fullRow, continuationRow)) {
    return normalized;
  }
  return rejoined;
}

bool _isConfidentSequentialRowMatch(
  String line,
  RegExp fullRow,
  RegExp continuationRow,
) {
  final full = fullRow.firstMatch(line);
  if (full != null) {
    final start = _normalizeDmxValue(int.parse(full.group(3)!));
    final end = _normalizeDmxValue(int.parse(full.group(4)!));
    if (start <= end && end <= 255 && full.group(2)!.trim().isNotEmpty) {
      return true;
    }
  }
  final continuation = continuationRow.firstMatch(line);
  if (continuation != null) {
    final start = _normalizeDmxValue(int.parse(continuation.group(1)!));
    final end = _normalizeDmxValue(int.parse(continuation.group(2)!));
    if (start <= end && end <= 255) return true;
  }
  return false;
}

/// Rejoins a 2-3 digit DMX byte value that OCR split with a stray inner
/// space beside a range separator ("128-19 0", "200-2 50", "2 51-255" all
/// become "128-190", "200-250", "251-255"). Only touches digit runs
/// directly adjacent to a separator character, so ordinary function-name
/// text is never altered by itself — [_resolveSequentialLine] is what
/// keeps it from being applied where it would corrupt a row instead.
String _rejoinDigitSplitRangeTokens(String line) {
  const splitNumber = r'\d(?:\s?\d){0,2}';
  final pattern = RegExp(
    '($splitNumber)\\s*($_rangeSeparatorClass)\\s*($splitNumber)',
  );
  return line.replaceAllMapped(pattern, (match) {
    final start = match.group(1)!.replaceAll(' ', '');
    final end = match.group(3)!.replaceAll(' ', '');
    return '$start${match.group(2)}$end';
  });
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
    '^\\s*(\\d{1,3})\\s+(\\d{1,3})\\s*$_rangeSeparatorClass\\s*(\\d{1,3})\\s+(.+?)\\s*\$',
  );
  final rowWithoutRange = RegExp(r'^\s*(\d{1,3})\s+([A-Za-z].+?)\s*$');
  final continuation = RegExp(
    '^\\s*(\\d{1,3})\\s*$_rangeSeparatorClass\\s*(\\d{1,3})\\s+(.+?)\\s*\$',
  );

  for (final section in sections) {
    int? currentChannel;
    var nextPosition = 1;
    for (final rawLine in section.split(RegExp(r'[\r\n]+'))) {
      final line = _normalizeTableLine(rawLine);
      if (line.isEmpty || line.startsWith('=== DMXTRACT PAGE')) continue;
      if (parsed.containsKey(channelCount) &&
          _isSupplementalTableHeading(line)) {
        // The final coded personality is commonly followed by appendix tables
        // whose first column is a range-row number, not a DMX channel number.
        // Stop the channel grid here so those rows can be interpreted against
        // the named control instead of silently overwriting later channels.
        break;
      }
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
          final currentRanges = parsed[currentChannel]?.ranges ?? const [];
          final startsAnotherFullRow =
              start == 0 &&
              end == 255 &&
              _rangesCoverFull(currentRanges) &&
              nextPosition <= channelCount &&
              !_looksLikePageFurniture(description);
          if (startsAnotherFullRow) {
            // On scanned grid tables the row-number column is often the first
            // thing OCR loses. A second complete 0-255 range cannot belong to
            // a channel whose range is already complete, so preserve its
            // table order and recover it as the next row.
            final definition = _withConfidence(
              _classifyTableChannel(description, nextPosition),
              .7,
            );
            parsed[nextPosition] = _mergeDetectedChannel(
              parsed[nextPosition],
              definition,
              _rangeFromParts(
                start,
                end,
                description,
                definition.kind,
                confidence: .65,
              ),
            );
            currentChannel = nextPosition;
            nextPosition++;
          } else {
            final definition = _classifyTableChannel(
              description,
              currentChannel,
            );
            parsed[currentChannel] = _mergeDetectedChannel(
              parsed[currentChannel],
              definition,
              _rangeFromParts(start, end, description, definition.kind),
            );
          }
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

  _fillRepeatedColorSeries(parsed, channelCount);

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

bool _isSupplementalTableHeading(String line) => RegExp(
  r'^(?:colou?r[ _]+temperature|mode\s+table(?:\s*[i12①②])?|shutter|background\s+colou?r)$',
  caseSensitive: false,
).hasMatch(line);

void _fillRepeatedColorSeries(
  Map<int, _DetectedChannel> parsed,
  int channelCount,
) {
  final groups = <String, List<({int position, int zone, String component})>>{};
  for (final entry in parsed.entries) {
    final part = _repeatedColorPart(entry.value.name);
    if (part == null) continue;
    groups.putIfAbsent(part.group, () => []).add((
      position: entry.key,
      zone: part.zone,
      component: part.component,
    ));
  }

  for (final group in groups.entries) {
    final observations = group.value;
    final zones = observations.map((item) => item.zone).toSet().toList()
      ..sort();
    if (zones.length < 2) continue;

    final componentOffsets = <String, int>{};
    final baseZone = zones.first;
    final baseRows =
        observations.where((item) => item.zone == baseZone).toList()
          ..sort((left, right) => left.position.compareTo(right.position));
    if (baseRows.length < 2) continue;
    final basePosition = baseRows.first.position;
    for (final row in baseRows) {
      componentOffsets[row.component] = row.position - basePosition;
    }

    int? stride;
    for (final component in componentOffsets.keys) {
      final matching =
          observations.where((item) => item.component == component).toList()
            ..sort((left, right) => left.zone.compareTo(right.zone));
      for (var index = 1; index < matching.length; index++) {
        final zoneDelta = matching[index].zone - matching[index - 1].zone;
        final positionDelta =
            matching[index].position - matching[index - 1].position;
        if (zoneDelta <= 0 || positionDelta % zoneDelta != 0) continue;
        final candidate = positionDelta ~/ zoneDelta;
        if (candidate > 0 && candidate >= componentOffsets.length) {
          stride = candidate;
          break;
        }
      }
      if (stride != null) break;
    }
    if (stride == null) continue;

    // Every explicit observation must agree with the inferred template. This
    // prevents unrelated color groups elsewhere in the personality from being
    // joined merely because their human-readable names happen to be similar.
    final consistent = observations.every((item) {
      final offset = componentOffsets[item.component];
      if (offset == null) return false;
      return item.position ==
          basePosition + (item.zone - baseZone) * stride! + offset;
    });
    if (!consistent) continue;

    for (var zone = zones.first; zone <= zones.last; zone++) {
      for (final component in componentOffsets.entries) {
        final position =
            basePosition + (zone - baseZone) * stride + component.value;
        if (position < 1 ||
            position > channelCount ||
            parsed[position] != null) {
          continue;
        }
        final name = _repeatedColorName(group.key, zone, component.key);
        const colorCodes = {
          'red': 'RED',
          'green': 'GREEN',
          'blue': 'BLUE',
          'white': 'WHITE',
          'amber': 'AMBER',
          'uv': 'UV',
        };
        final fine = group.key == 'main-fine';
        final definition = _DetectedChannel(
          name: name,
          kind: 'colorIntensity',
          color: colorCodes[component.key],
          fineOf: fine
              ? 'colorIntensity:${colorCodes[component.key]}:$zone'
              : null,
          confidence: .72,
        );
        parsed[position] = _mergeDetectedChannel(
          null,
          definition,
          _rangeFromParts(
            0,
            255,
            '$name intensity',
            definition.kind,
            confidence: .65,
          ),
        );
      }
    }
  }
}

({String group, int zone, String component})? _repeatedColorPart(String name) {
  final family = RegExp(
    r'^(LED|Auxiliary light)\s+(\d{1,3})\s+(red|green|blue|white|amber|uv)$',
    caseSensitive: false,
  ).firstMatch(name);
  if (family != null) {
    return (
      group: family.group(1)!.toLowerCase(),
      zone: int.parse(family.group(2)!),
      component: family.group(3)!.toLowerCase(),
    );
  }
  final ordinary = RegExp(
    r'^(Red|Green|Blue|White|Amber|UV)\s+(\d{1,3})(\s+fine)?$',
    caseSensitive: false,
  ).firstMatch(name);
  if (ordinary == null) return null;
  return (
    group: ordinary.group(3) == null ? 'main' : 'main-fine',
    zone: int.parse(ordinary.group(2)!),
    component: ordinary.group(1)!.toLowerCase(),
  );
}

String _repeatedColorName(String group, int zone, String component) {
  final color = component == 'uv'
      ? 'UV'
      : '${component[0].toUpperCase()}${component.substring(1)}';
  return switch (group) {
    'led' => 'LED $zone ${component.toLowerCase()}',
    'auxiliary light' => 'Auxiliary light $zone ${component.toLowerCase()}',
    'main-fine' => '$color $zone fine',
    _ => '$color $zone',
  };
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
  final existingRanges = existing?.ranges ?? const <DmxRange>[];
  // manual_extractor.js's extractImage() keeps both of a photo's scored OCR
  // readings rather than discarding one (either can garble the one heading
  // a mode table depends on while the other reads it cleanly), so the same
  // physical row can legitimately appear twice in the text handed to this
  // parser. Skip a range that exactly repeats one already recorded for this
  // channel instead of appending a redundant duplicate — a channel legally
  // repeating the identical (start, end) bounds for two different meanings
  // does not happen in practice.
  final isDuplicate =
      range != null &&
      existingRanges.any((r) => r.start == range.start && r.end == range.end);
  final ranges = <DmxRange>[
    ...existingRanges,
    if (range != null && !isDuplicate) range,
  ];
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
  final numberedModeTable = RegExp(
    r'^[mv]ode[_\s-]*table[_\s-]*[\(]?([12id])[\)]?',
    caseSensitive: false,
  ).firstMatch(cleaned);
  if (numberedModeTable != null) {
    final marker = numberedModeTable.group(1)!.toLowerCase();
    final number = marker == '2' ? '2' : '1';
    cleaned = cleaned.replaceRange(
      0,
      numberedModeTable.end,
      'Mode table $number',
    );
  } else {
    cleaned = cleaned.replaceFirst(
      RegExp(r'^[mv]ode[_\s-]*table\w*', caseSensitive: false),
      'Mode table',
    );
  }
  return cleaned;
}

bool _looksLikePageFurniture(String value) =>
    // The "=== DMXTRACT PAGE N ===" marker itself, in case a two-line
    // title/suffix match bridges a cover page whose product name rendered
    // as an unreadable image, leaving the marker as the only "title" line.
    value.trimLeft().startsWith('=') ||
    RegExp(
      r'^(page|p\.?\s*\d|rev(?:ision)?|user manual|contents?)\b',
      caseSensitive: false,
    ).hasMatch(value) ||
    // A running header/footer ("Rotosphere HP User Manual Rev. 1", or the
    // same text with a page number printed ahead of it on the facing page:
    // "8   Rotosphere HP User Manual Rev. 1") repeats the manual's title —
    // the prefix check above only catches it when that phrase leads the
    // line, so also catch it anywhere for callers (like the mode-matrix
    // parser's value-line grammar) that hand this a description with a
    // leading page number or product name already split off.
    RegExp(r'\buser\s+manual\b', caseSensitive: false).hasMatch(value);

String _relationshipKey(_DetectedChannel channel) {
  if (channel.kind == 'colorIntensity') {
    final zone = RegExp(r'\d+').firstMatch(channel.name)?.group(0) ?? '';
    return 'colorIntensity:${channel.color ?? ''}:$zone';
  }
  if (channel.kind == 'intensity') {
    final zone =
        RegExp(r'\d+(?:\s*[-–—]\s*\d+)?').firstMatch(channel.name)?.group(0) ??
        '';
    if (channel.name.toLowerCase().contains('background')) {
      return 'intensity:background:$zone';
    }
    return zone.isEmpty ? 'intensity:dimmer' : 'intensity:dimmer:$zone';
  }
  if (channel.kind == 'focus') return 'focus';
  if (const {'pan', 'tilt', 'zoom'}.contains(channel.kind)) {
    final zone =
        RegExp(r'\d+(?:\s*[-–—]\s*\d+)?').firstMatch(channel.name)?.group(0) ??
        '';
    return zone.isEmpty ? channel.kind : '${channel.kind}:$zone';
  }
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
  final pattern = RegExp(
    '\\b(\\d{1,3})\\s*$_rangeSeparatorClass\\s*(\\d{1,3})\\b',
  );
  for (final match in pattern.allMatches(value)) {
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    if (start == null || end == null || start > end || end > 255) continue;
    final trailing = value.substring(match.end).trim();
    if (trailing.startsWith('%')) continue;
    var label = trailing
        .replaceFirst(
          RegExp('^\\d{1,3}\\s*$_rangeSeparatorClass\\s*\\d{1,3}%\\s*'),
          '',
        )
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
      .replaceFirst(
        RegExp('^\\d{1,3}\\s*$_rangeSeparatorClass\\s*\\d{1,3}\\s+'),
        '',
      )
      .replaceFirst(RegExp(r'^(?:(?:\d{1,3}|-)\s+){1,6}'), '');
  final lower = withoutModeColumns.toLowerCase().replaceAll('_', ' ');
  String? numberedSuffix(String label) => RegExp(
    '\\b$label\\s+(\\d{1,3}(?:\\s*[-–—]\\s*\\d{1,3})?)',
  ).firstMatch(lower)?.group(1);
  if (RegExp(r'\btilt\s+(?:speed|time)\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Tilt speed', kind: 'speed');
  }
  if (RegExp(r'\btilt\s+macro\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Tilt macro', kind: 'effect');
  }
  if (RegExp(r'(pan.?tilt|x.?y|xy).*(speed|time)').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Pan / tilt speed', kind: 'speed');
  }
  if (RegExp(
    r'(?:fine\s+(?:pan|x.?axis)|(pan|x.?axis)\s*(?:fine|16.?bit|least))',
  ).hasMatch(lower)) {
    final zone = numberedSuffix(r'(?:fine\s+)?pan');
    return _DetectedChannel(
      name: zone == null ? 'Pan fine' : 'Pan $zone fine',
      kind: 'pan',
      fineOf: zone == null ? 'pan' : 'pan:$zone',
    );
  }
  if (RegExp(
    r'(?:fine\s+(?:tilt|y.?axis)|(tilt|y.?axis)\s*(?:fine|16.?bit|least))',
  ).hasMatch(lower)) {
    final zone = numberedSuffix(r'(?:fine\s+)?tilt');
    return _DetectedChannel(
      name: zone == null ? 'Tilt fine' : 'Tilt $zone fine',
      kind: 'tilt',
      fineOf: zone == null ? 'tilt' : 'tilt:$zone',
    );
  }
  if (RegExp(r'\bpan\b|\bx.?axis\b').hasMatch(lower)) {
    final zone = numberedSuffix('pan');
    return _DetectedChannel(
      name: zone == null ? 'Pan' : 'Pan $zone',
      kind: 'pan',
    );
  }
  if (RegExp(r'\btilt\b|\by.?axis\b').hasMatch(lower)) {
    final zone = numberedSuffix('tilt');
    return _DetectedChannel(
      name: zone == null ? 'Tilt' : 'Tilt $zone',
      kind: 'tilt',
    );
  }
  if (RegExp(
    r'(?:\bfine\s+(?:dimmer|dimming|intensity)\b|\b(?:dimmer|dimming|intensity)\b.*\b(?:fine|fine.?tuning)\b|\bbackground\s+colou?r\s+fine\b)',
  ).hasMatch(lower)) {
    final zone = numberedSuffix(r'(?:fine\s+)?(?:dimmer|dimming|intensity)');
    final background = lower.contains('background');
    return _DetectedChannel(
      name: background
          ? 'Background color dimmer fine'
          : zone == null
          ? 'Dimmer fine'
          : 'Dimmer $zone fine',
      kind: 'intensity',
      fineOf: background
          ? 'intensity:background:${zone ?? ''}'
          : zone == null
          ? 'intensity:dimmer'
          : 'intensity:dimmer:$zone',
    );
  }
  if (RegExp(r'\b(dimmer|dimming|intensity)\b').hasMatch(lower)) {
    final zone = numberedSuffix(r'(?:dimmer|dimming|intensity)');
    final background = lower.contains('background');
    final aura = lower.contains('aura');
    return _DetectedChannel(
      name: background
          ? 'Background color dimmer'
          : aura
          ? 'Aura dimmer'
          : zone == null
          ? 'Dimmer'
          : 'Dimmer $zone',
      kind: 'intensity',
    );
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
  if (RegExp(r'(?:\bfine\s+zoom\b|\bzoom\b.*\bfine\b)').hasMatch(lower)) {
    final zone = numberedSuffix(r'(?:fine\s+)?zoom');
    return _DetectedChannel(
      name: zone == null ? 'Zoom fine' : 'Zoom $zone fine',
      kind: 'zoom',
      fineOf: zone == null ? 'zoom' : 'zoom:$zone',
    );
  }
  if (RegExp(r'\bzoom\b').hasMatch(lower)) {
    final zone = RegExp(
      r'\bzoom\s+(\d{1,3}(?:\s*[-–—]\s*\d{1,3})?)',
    ).firstMatch(lower)?.group(1);
    return _DetectedChannel(
      name: zone == null ? 'Zoom' : 'Zoom $zone',
      kind: 'zoom',
    );
  }
  if (RegExp(r'\b(?:ctc|colou?r temperature)\b').hasMatch(lower)) {
    return _DetectedChannel(
      name: lower.contains('aura')
          ? 'Aura color temperature'
          : 'Color temperature',
      kind: 'colorTemperature',
    );
  }
  if (RegExp(r'green\s*/\s*magenta|green.*shift|\btint\b').hasMatch(lower)) {
    return _DetectedChannel(
      name: lower.contains('aura')
          ? 'Aura green / magenta tint'
          : 'Green / magenta tint',
      kind: 'effect',
    );
  }
  if (RegExp(r'\bbeamshaper\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Beamshaper', kind: 'effect');
  }
  if (RegExp(r'\bbackground\s+colou?r\b').hasMatch(lower)) {
    return const _DetectedChannel(name: 'Background color', kind: 'colorWheel');
  }
  if (RegExp(r'fixture\s+control\s*/?\s*settings').hasMatch(lower)) {
    return const _DetectedChannel(
      name: 'Fixture control / settings',
      kind: 'maintenance',
    );
  }
  if (RegExp(r'\bmode\b').hasMatch(lower)) {
    final table = RegExp(r'\bmode\s*table\s*[\(]?([12id])').firstMatch(lower);
    final number = switch (table?.group(1)) {
      '2' => '2',
      // Circled 1 is frequently OCR'd as D in scanned personality tables.
      'd' => '1',
      '1' => '1',
      'i' => '1',
      _ => null,
    };
    return _DetectedChannel(
      name: number == null ? 'Mode' : 'Mode table $number',
      kind: 'mode',
    );
  }
  if (RegExp(
    r'\b(program|auto).*\bspeed\b|\bspeed\b|\bvelocity\b',
  ).hasMatch(lower)) {
    return const _DetectedChannel(name: 'Program speed', kind: 'speed');
  }
  if (RegExp(r'\b(strobe|shutter|flash)\b').hasMatch(lower)) {
    return _DetectedChannel(
      name: lower.contains('shutter')
          ? 'Shutter / strobe'
          : lower.contains('aura')
          ? 'Aura strobe / shutter'
          : 'Light switch / strobe',
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
  final secondaryColor = RegExp(
    r'\b(?:fu\s+guang|supplementary\s+light|auxiliary\s+light)\s+([rgbw])\b',
  ).firstMatch(lower);
  if (secondaryColor != null) {
    const colors = {
      'r': ('Auxiliary red', 'RED'),
      'g': ('Auxiliary green', 'GREEN'),
      'b': ('Auxiliary blue', 'BLUE'),
      'w': ('Auxiliary white', 'WHITE'),
    };
    final color = colors[secondaryColor.group(1)]!;
    return _DetectedChannel(
      name: color.$1,
      kind: 'colorIntensity',
      color: color.$2,
    );
  }
  final ledIntensity = RegExp(r'^led\s*(\d{1,3})$').firstMatch(lower.trim());
  if (ledIntensity != null) {
    return _DetectedChannel(
      name: 'LED ${ledIntensity.group(1)} intensity',
      kind: 'intensity',
    );
  }
  final ledColor = RegExp(
    r'\bled\s*(\d{1,3})\s+(red|green|blue|white|amber|uv|ultraviolet)\b',
  ).firstMatch(lower);
  if (ledColor != null) {
    const colors = {
      'red': 'RED',
      'green': 'GREEN',
      'blue': 'BLUE',
      'white': 'WHITE',
      'amber': 'AMBER',
      'uv': 'UV',
      'ultraviolet': 'UV',
    };
    final component = ledColor.group(2) == 'ultraviolet'
        ? 'uv'
        : ledColor.group(2)!;
    return _DetectedChannel(
      name: 'LED ${ledColor.group(1)} $component',
      kind: 'colorIntensity',
      color: colors[ledColor.group(2)],
    );
  }
  final auxiliaryColor = RegExp(
    r'\bauxiliary\s+light\s+([rgbw])\s*(\d{1,3})\b',
  ).firstMatch(lower);
  if (auxiliaryColor != null) {
    const colors = {
      'r': ('red', 'RED'),
      'g': ('green', 'GREEN'),
      'b': ('blue', 'BLUE'),
      'w': ('white', 'WHITE'),
    };
    final color = colors[auxiliaryColor.group(1)]!;
    return _DetectedChannel(
      name: 'Auxiliary light ${auxiliaryColor.group(2)} ${color.$1}',
      kind: 'colorIntensity',
      color: color.$2,
    );
  }
  final abbreviatedColor = RegExp(
    r'^(?:(fine)\s+)?([rgbw])\s*(\d{1,2})(?:\s+(fine|fine.?tuning|fine.?tuned|trimming))?\b',
  ).firstMatch(lower);
  if (abbreviatedColor != null) {
    const colors = {
      'r': ('Red', 'RED'),
      'g': ('Green', 'GREEN'),
      'b': ('Blue', 'BLUE'),
      'w': ('White', 'WHITE'),
    };
    final color = colors[abbreviatedColor.group(2)]!;
    final zone = abbreviatedColor.group(3)!;
    final fine =
        abbreviatedColor.group(1) != null || abbreviatedColor.group(4) != null;
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
      '\\b(?:(fine)\\s+)?${entry.key}\\s*(\\d{1,2})?(?:\\s+(fine|fine.?tuning))?\\b',
    ).firstMatch(lower);
    if (colorMatch != null) {
      final zone = colorMatch.group(2);
      final fine = colorMatch.group(1) != null || colorMatch.group(3) != null;
      return _DetectedChannel(
        name: zone == null
            ? fine
                  ? lower.contains('aura')
                        ? 'Aura ${entry.value.$1.toLowerCase()} fine'
                        : '${entry.value.$1} fine'
                  : lower.contains('aura')
                  ? 'Aura ${entry.value.$1.toLowerCase()}'
                  : entry.value.$1
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
      .replaceAll(
        RegExp('\\b\\d{1,3}\\s*$_rangeSeparatorClass\\s*\\d{1,3}\\b.*\$'),
        '',
      )
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
