import 'brand_catalog.dart';
import 'channel_attribute_map.dart';
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
  // A product line or a "Model:" line states the model; a title is checked
  // against the pages after the cover, which OCR may have misread.
  final modelFromManual =
      productLineModelMatch?.group(1)?.trim() ??
      numberedModelMatch?.group(1)?.replaceAll(' ', '') ??
      _corroboratedModel(
        text,
        titleModel ?? _firstNonStopwordTitle(titledModelMatch),
      );
  final fallback = _modelFromFilename(sourceName);
  final model = modelFromManual ?? fallback ?? 'Unknown fixture';
  // A model recovered only from the filename (no in-document title match)
  // is an honest guess, not a read — score it low below and let the
  // help-question logic flag it, rather than presenting it with the same
  // confidence as a title actually read off the manual's cover.
  final modelIsFilenameEcho = modelFromManual == null && fallback != null;
  // Deliberately body-text-only: a filename fallback here (as this used to
  // do via `_manufacturer(sourceName)`) can attribute a brand with zero
  // evidence anywhere in the manual's own text — exactly the defect class
  // this identity pack exists to kill. If the body has no evidence, the
  // fixture stays an honest "Unknown manufacturer".
  final manufacturerMatch = _detectManufacturer(
    flat,
    modelFromManual ?? fallback,
    titleModelHint: modelFromManual,
  );
  final manufacturer = manufacturerMatch?.name ?? 'Unknown manufacturer';
  final manufacturerFromManual = manufacturer;
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
  // A front-panel menu's own mode-select field can be the only place a
  // manual declares its mode set, both in the menu-navigation prose
  // ("the CHANNEL CH: menu variable field can be set to 06, 07, 08, or
  // 12") and in the menu-reference table row ("CHANNEL   CH: 06, 07, 08,
  // 12   DMX Channel Mode") — see Elation SixPar 200. Both print as
  // "CH:" followed by a comma-separated list of channel counts, so that
  // shape alone is corroboration enough without also requiring the word
  // "CHANNEL" nearby: across this project's entire mined manual corpus,
  // "CH:" followed by a number and a comma never appears for any other
  // reason.
  for (final match in RegExp(
    r'CH:\s*((?:\d{1,3}\s*,\s*)+(?:or\s*)?\d{1,3})',
    caseSensitive: false,
  ).allMatches(flat)) {
    for (final numberMatch in RegExp(r'\d{1,3}').allMatches(match.group(1)!)) {
      final value = int.tryParse(numberMatch.group(0)!);
      if (value != null &&
          value > 0 &&
          value <= 512 &&
          !modeCounts.contains(value)) {
        modeCounts.add(value);
      }
    }
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
  final matrixResult = namedModes.isEmpty
      ? _matrixLikeModeTables(text)
      : (modes: const <_DetectedModeTable>[], mayHaveGaps: false);
  final matrixModes = matrixResult.modes;
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
    // Two independent mode groups occasionally declare the same channel
    // count under the same code (e.g. a mode-matrix table family with
    // several cell-size sections, where "RGBWL 80ch" in one section and
    // "RGBWL 16-bit 80ch" in another both size out to 80Ch): `code` alone
    // then isn't unique across `structuredModes`, and reusing it verbatim
    // for both `mode.id` and every channel's id prefix would silently
    // alias the second mode's channels onto the first's ids (any
    // `channels.firstWhere((c) => c.id == id)` lookup - including this
    // file's own `fineOf` resolution in a wider table - would resolve to
    // whichever mode happened to be assembled first). The *id* prefix is
    // disambiguated on a repeat occurrence to keep every id unique; the
    // displayed name/shortName must be disambiguated too (a suffix like
    // " (2)"), or the exported GDTF ends up with two <DMXMode> elements
    // sharing the same Name - these are genuinely distinct modes that
    // merely happen to share a DMX footprint (see export_service.dart's
    // `Name="${mode.name}"` and InitialFunction, which both assume
    // mode.name is unique).
    final modeCodeOccurrences = <String, int>{};
    for (final detectedMode in structuredModes) {
      final occurrence = (modeCodeOccurrences[detectedMode.code] ?? 0) + 1;
      modeCodeOccurrences[detectedMode.code] = occurrence;
      final idPrefix = occurrence > 1
          ? '${slug(detectedMode.code)}-$occurrence'
          : slug(detectedMode.code);
      final displayName = occurrence > 1
          ? '${detectedMode.code} ($occurrence)'
          : detectedMode.code;
      final modeChannelIds = <String>[];
      final coarseIds = <String, String>{};
      for (var index = 0; index < detectedMode.channelCount; index++) {
        final definition = detectedMode.channels[index];
        final supplementalRanges = _supplementalRangesFor(
          definition,
          codedSupplementalRanges,
        );
        final channelId =
            '$idPrefix-${(index + 1).toString().padLeft(3, '0')}-${slug(definition.name)}';
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
            gdtfAttribute: definition.gdtfAttribute,
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
          id: 'mode-$idPrefix',
          name: displayName,
          shortName: displayName,
          channelIds: modeChannelIds,
          breaks: (detectedMode.channelCount / 512).ceil().clamp(1, 64),
        ),
      );
    }
    // A sparse mode-matrix grammar (see `mayHaveGaps` on
    // [_matrixLikeModeTables]) only proves it found *a* table, not that it
    // found the document's *entire* mode set - some manuals in this family
    // print one or more personality groups in a still-unsupported table
    // shape elsewhere in the same document. A generic-channel-count
    // gap-fill pass used to run here to cover that gap, but measured
    // against the eval corpus it was net-negative: it bought +0.003
    // footprint recall while costing footprint precision (-0.012) and
    // introducing both duplicate channel ids within a fixture (its
    // one-shot `-${index+1}` collision suffix stopped being unique from
    // the third gap-fill mode onward) and duplicate DMXMode names in the
    // GDTF export. The gap is left unfilled instead - see `mayHaveGaps`'s
    // own doc comment for the still-unsupported table shapes this leaves
    // out.
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
          gdtfAttribute: definition.gdtfAttribute,
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
  final identityConfidence = _identityConfidence(
    manufacturerMatch: manufacturerMatch,
    modelFromTitle: modelFromManual != null,
    modelIsFilenameEcho: modelIsFilenameEcho,
  );
  final fixture = FixtureProject(
    id: '${slug(manufacturer)}-${slug(model)}',
    manufacturer: manufacturer,
    model: model,
    sourceName: sourceName,
    identityFromManual:
        modelFromManual != null &&
        manufacturerFromManual != 'Unknown manufacturer',
    identityConfidence: identityConfidence,
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
    // A field that isn't literally "Unknown" can still be a low-confidence
    // guess (a brand recovered only from weak catalog evidence, a model
    // that's just the filename echoed back) — surface the same kind of
    // prompt for those instead of presenting them as settled facts.
    if (!manufacturer.startsWith('Unknown') &&
        !model.startsWith('Unknown') &&
        identityConfidence < .5)
      "We're not fully confident about the maker or model we found — please check them.",
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
// ---------------------------------------------------------------------
// Manufacturer identity: evidence-based matching against the generated
// brand catalog (brand_catalog.g.dart, from unified.db), plus a small set
// of brands this extractor already gets right at 94-100% on the GDTF
// benchmark (see scripts/eval/README.md). Those known brands are checked
// FIRST, in their original priority order, so they keep winning exactly
// as before — but through the SAME evidence machinery the catalog scan
// uses, not a bare `.contains`, because a bare substring check is what
// caused the defect this pack exists to fix: a Laserworld manual's own
// legal-imprint line ("CEO: Martin Werner") satisfied `lower.contains
// ('martin')` and hallucinated manufacturer "Martin" with zero actual
// brand evidence anywhere in the document.
//
// The catalog scan (tier 2) only ever runs when tier 1 finds nothing, and
// only ever returns a brand that has at least one qualifying occurrence
// IN THE MANUAL'S OWN BODY TEXT — never from the source filename. A
// filename-based fallback (this file used to also call `_manufacturer` on
// `sourceName` when the body scan came up empty) is exactly how a fixture
// can end up attributed to a brand that appears nowhere in its own
// manual, so that fallback is gone: no body evidence means an honest
// "Unknown manufacturer".

/// A brand match found in the document body, with enough evidence detail
/// for [_identityConfidence] to score it.
class _IdentityMatch {
  const _IdentityMatch({
    required this.name,
    required this.tier,
    required this.occurrences,
    required this.early,
    required this.coOccursWithModel,
    this.selfIdentifies = false,
    this.adjacentToModel = false,
  });
  final String name;

  /// 'known' = one of this extractor's own high-precision brands.
  /// 'catalog' = recovered from the generated brand catalog.
  final String tier;
  final int occurrences;
  final bool early;
  final bool coOccursWithModel;

  /// True when the manual explicitly names its own maker ("thank you for
  /// purchasing this `<brand>` product") rather than the brand word merely
  /// showing up somewhere.
  final bool selfIdentifies;

  /// True when a brand mention sits immediately next to (within a few
  /// words of) the detected model text, as in "The Equinox Fusion 200
  /// Zoom Spot can be operated..." — a much tighter, more reliable signal
  /// than [coOccursWithModel]'s generous 800-character window. That wider
  /// window exists for score tie-breaking, where being wrong occasionally
  /// costs little, but most manuals repeat the model name in a running
  /// header on every page, which puts nearly every word in the document
  /// "near" a model mention by that measure — not reliable enough to ever
  /// let a brand past the minimum-evidence gate on it.
  final bool adjacentToModel;
}

/// Honorific/role-title words that, immediately in front of a brand
/// spelling, mark that occurrence as a person's name rather than the
/// fixture's manufacturer — the "CEO: Martin Werner" class of false
/// positive. Checked as the word (or two-word phrase, for "Managing
/// Director") immediately preceding the match, a trailing colon ignored.
const _personNameContext = <String>{
  'mr',
  'mrs',
  'ms',
  'dr',
  'herr',
  'mme',
  'ceo',
  'cto',
  'coo',
  'president',
  'founder',
  'owner',
  'director',
  'managing director',
  'geschäftsführer',
  'verwaltungsrat',
  // French "Conseil d'administration:" (board of directors) - the ' /
  // ‘ apostrophe in "d'administration" splits into separate word tokens
  // under the plain-letter-sequence regex below, so the word actually
  // seen immediately before the name is "administration", not
  // "d'administration". Real corpus shape: Laserworld_ScanBar10RGb_UM
  // and Laserworld_DS1000RGBShowNet_UM both list "Conseil
  // d'administration: Martin Werner" alongside "CEO:"/"Verwaltungsrat:" -
  // without this entry those two occurrences alone kept "Martin" above
  // the empty-evidence bar.
  'administration',
};

/// Lowercase, whitespace-collapsed, punctuation-insensitive word sequence
/// — used to check whether one string's words are contained in another's
/// (a catalog spelling embedded in a detected model string).
String _normalizeWords(String value) => RegExp(
  r'[A-Za-z0-9]+',
).allMatches(value).map((m) => m.group(0)!.toLowerCase()).join(' ');

/// True when [needleWords] (already space-joined, normalized words) occurs
/// as a contiguous run of *whole* words inside [haystackWords] — unlike a
/// raw string `.contains`, this does not treat "robe" as present inside
/// "probeam" just because the letters line up mid-word.
bool _wordSequenceContains(String haystackWords, String needleWords) {
  if (needleWords.isEmpty) return false;
  final haystack = haystackWords.split(' ');
  final needle = needleWords.split(' ');
  if (needle.length > haystack.length) return false;
  for (var start = 0; start + needle.length <= haystack.length; start++) {
    var matches = true;
    for (var i = 0; i < needle.length; i++) {
      if (haystack[start + i] != needle[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

bool _isPersonNameContext(String flat, int matchStart) {
  final windowStart = (matchStart - 40).clamp(0, flat.length);
  final before = flat.substring(windowStart, matchStart);
  final words = RegExp(
    r'[A-Za-zÀ-ÖØ-öø-ÿ]+',
  ).allMatches(before).map((m) => m.group(0)!.toLowerCase()).toList();
  if (words.isEmpty) return false;
  if (_personNameContext.contains(words.last)) return true;
  if (words.length >= 2 &&
      _personNameContext.contains('${words[words.length - 2]} ${words.last}')) {
    return true;
  }
  return false;
}

/// Word-boundary, case-insensitive match for [spelling] that also
/// tolerates a `©`/`®`/`™` glyph glued directly onto the word with no
/// space (real corpus shapes: "BRITEQ®", "ADJ®", "©Eliminator").
RegExp _brandPattern(String spelling) => RegExp(
  r'(?<![A-Za-z0-9])[©®™]?' +
      RegExp.escape(spelling) +
      r'[©®™]?(?![A-Za-z0-9])',
  caseSensitive: false,
);

/// Every non-person-name-context match offset for any of [spellings] in
/// [flat] - deduplicated by offset, since [spellings] routinely contains
/// several case variants of the same word ("Showtec"/"SHOWTEC") that all
/// match the same real-world mention. Without the dedup, a brand with N
/// case-variant aliases has every real occurrence counted N times, which
/// both inflates its score against single-spelling brands and lets it
/// clear the minimum-evidence gate below on far fewer real mentions than
/// the gate's number implies.
List<int> _brandOccurrences(String flat, Iterable<String> spellings) {
  final offsets = <int>{};
  for (final spelling in spellings) {
    for (final match in _brandPattern(spelling).allMatches(flat)) {
      if (!_isPersonNameContext(flat, match.start)) offsets.add(match.start);
    }
  }
  return offsets.toList()..sort();
}

/// The character offset up to which a match counts as "early" (roughly
/// the manual's first two pages) — page markers survive `flat`'s
/// whitespace-collapsing untouched, so this reads them directly off it.
int _earlyPageEnd(String flat) {
  final markers = RegExp(
    r'=== DMXTRACT PAGE \d+ ===',
  ).allMatches(flat).toList();
  return markers.length >= 3 ? markers[2].start : flat.length;
}

_IdentityMatch? _matchFor(
  String flat,
  String name,
  Iterable<String> spellings,
  int earlyEnd,
  String? modelHint,
) {
  final offsets = _brandOccurrences(flat, spellings);
  if (offsets.isEmpty) return null;
  final early = offsets.any((offset) => offset < earlyEnd);
  var coOccurs = false;
  if (modelHint != null && modelHint.length >= 3) {
    final modelOffsets = <int>[
      for (final match in RegExp(
        RegExp.escape(modelHint),
        caseSensitive: false,
      ).allMatches(flat))
        match.start,
    ];
    coOccurs = offsets.any(
      (offset) => modelOffsets.any((m) => (offset - m).abs() < 800),
    );
  }
  return _IdentityMatch(
    name: name,
    tier: 'known',
    occurrences: offsets.length,
    early: early,
    coOccursWithModel: coOccurs,
  );
}

_IdentityMatch? _detectManufacturer(
  String flat,
  String? modelHint, {
  required String? titleModelHint,
}) {
  final earlyEnd = _earlyPageEnd(flat);
  // Tier 1: known high-precision brands, in their original priority
  // order (Chauvet's DJ/Professional split is decided the same way it
  // always was, once we know "Chauvet" itself has real evidence).
  final betopper = _matchFor(
    flat,
    'Betopper',
    const ['Betopper'],
    earlyEnd,
    modelHint,
  );
  if (betopper != null) return betopper;
  final shehds = _matchFor(
    flat,
    'SHEHDS',
    const ['SHEHDS'],
    earlyEnd,
    modelHint,
  );
  if (shehds != null) return shehds;
  final chauvet = _matchFor(
    flat,
    'Chauvet',
    const ['Chauvet'],
    earlyEnd,
    modelHint,
  );
  if (chauvet != null) {
    final lower = flat.toLowerCase();
    final name =
        lower.contains('chauvet professional') || lower.contains('colorado pxl')
        ? 'Chauvet Professional'
        : 'Chauvet DJ';
    return _IdentityMatch(
      name: name,
      tier: 'known',
      occurrences: chauvet.occurrences,
      early: chauvet.early,
      coOccursWithModel: chauvet.coOccursWithModel,
    );
  }
  final martin = _matchFor(
    flat,
    'Martin',
    const ['Martin'],
    earlyEnd,
    modelHint,
  );
  if (martin != null) return martin;
  final altman = _matchFor(
    flat,
    'Altman',
    const ['Altman'],
    earlyEnd,
    modelHint,
  );
  if (altman != null) return altman;
  // "ADJ" is a 3-character acronym, unlike this tier's other (long,
  // low-collision) brand words - it also reads as the common prose
  // abbreviation "adj." (adjust/adjustment), including the real corpus
  // shape of "Adjust" itself getting OCR/column-split across a line
  // break into a standalone "Adj" token followed by "ust" on the next
  // line (Elation_PlatinumSpot15RPro_UM: "Adj Calibrate Values" /
  // "ust ..."), which otherwise hallucinates manufacturer "ADJ" in a
  // document that never mentions Elation. A single hit is not enough
  // real-world evidence for a token this collision-prone; require at
  // least a second occurrence before trusting it outright.
  final adj = _matchFor(flat, 'ADJ', const ['ADJ'], earlyEnd, modelHint);
  if (adj != null && adj.occurrences >= 2) return adj;

  // Tier 2: recovery layer over the full generated brand catalog. A cheap
  // lowercase `contains` prefilters each entry before the precise
  // word-boundary regex runs, since most of ~1900 entries never appear in
  // any given manual.
  //
  // Ranking is occurrence-count-first: a brand genuinely named throughout
  // the manual (dozens of times) must always beat an incidental word that
  // happens to appear a handful of times, or an ordinary-English-word
  // catalog entry that shows up constantly for unrelated reasons ("head"
  // as in "moving head", counted a few dozen times across a typical
  // manual) — capping occurrence evidence at a small number (as an
  // earlier version of this scan did) let those ties fall to an
  // alphabetical tiebreak, which is how a manual mentioning "Robe" 30+
  // times once lost to "Prg" (an abbreviation for "test program",
  // mentioned 8 times) purely because both got clamped to the same score.
  // Early-page and model-co-occurrence remain small nudges for near-ties,
  // never enough to overturn a real occurrence-count gap.
  final flatLower = flat.toLowerCase();
  // Only an in-document TITLE match guards against self-reference — the
  // filename fallback routinely embeds the manufacturer's own name as a
  // filename-naming convention ("Laserworld_ScanBar10RGb_UM.pdf"), so
  // using it here would wrongly exclude the real brand as if it were
  // just its own product name repeating.
  final normalizedTitleModelHint = titleModelHint == null
      ? null
      : _normalizeWords(titleModelHint);
  _IdentityMatch? best;
  double bestScore = -1;
  for (final entry in brandCatalog) {
    final spellings = entry.spellings.toList();
    final mightMatch = spellings.any(
      (spelling) => flatLower.contains(spelling.toLowerCase()),
    );
    if (!mightMatch) continue;
    final offsets = _brandOccurrences(flat, spellings);
    if (offsets.isEmpty) continue;
    // A catalog word embedded in the fixture's own model name/number
    // ("Fusion" inside model "Fusion 200 Zoom Spot") is that product name
    // repeating, not a separate brand mention. Only treat it as
    // self-reference when the *only* mention found anywhere in the body
    // is the one inside the title/model text — a brand that repeats
    // elsewhere in the body is real, independent evidence and must stay
    // a candidate (real corpus shape: a cover page reading "ROBE Robin
    // Spikie" must not disable "Robe" when the body names it a dozen
    // more times). This also compares whole words, not raw substrings —
    // normalized "probeam" containing the letters of "robe" is not the
    // same *word* as "robe" and must not exclude an unrelated brand.
    if (normalizedTitleModelHint != null &&
        offsets.length <= 1 &&
        spellings.any(
          (spelling) => _wordSequenceContains(
            normalizedTitleModelHint,
            _normalizeWords(spelling),
          ),
        )) {
      continue;
    }
    final early = offsets.any((offset) => offset < earlyEnd);
    var coOccurs = false;
    var adjacentToModel = false;
    if (modelHint != null && modelHint.length >= 3) {
      final modelOffsets = <int>[
        for (final match in RegExp(
          RegExp.escape(modelHint),
          caseSensitive: false,
        ).allMatches(flat))
          match.start,
      ];
      coOccurs = offsets.any(
        (offset) => modelOffsets.any((m) => (offset - m).abs() < 800),
      );
      // Most manuals repeat the model name in a running header on every
      // page, so "within 800 characters of *some* model mention" is true
      // for nearly every word in the document once a manual is a few
      // pages long - not reliable evidence of anything. Real corpus
      // shapes: "MKII" (Stairville_LEDMatrixBlinder5x5MKII_UM) and "Gobo
      // Flower" (Equinox_HelixXPFlower_UM) each repeat as a page header
      // 20-40+ times, which put the ordinary prose words "play" ("...let
      // children play with the packaging...") and "universal" ("a
      // universal DMX controller") within the loose window purely by
      // page-header density, not because either word means anything
      // brand-related. A genuine "<Brand> <Model>" mention - the shape
      // this signal exists to catch (Equinox_Fusion200ZoomSpot_UM: "The
      // Equinox Fusion 200 Zoom Spot can be operated...") - has the brand
      // word directly beside the model text, not merely on the same
      // page.
      adjacentToModel = offsets.any(
        (offset) => modelOffsets.any((m) => (offset - m).abs() <= 20),
      );
    }
    // "Thank you for purchasing this <brand> product" (and near variants)
    // is the strongest, most brand-agnostic signal a manual gives of its
    // own maker — real corpus shape, seen verbatim across Laserworld,
    // Showtec and Briteq manuals in this benchmark. Weighted heavily
    // enough to beat a higher-occurrence but incidental mention (e.g. a
    // parent/holding company named repeatedly in a legal footer).
    final selfIdentifies = spellings.any(
      (spelling) => RegExp(
        r'(?:purchasing|buying) this\s+' +
            RegExp.escape(spelling) +
            r'\b|\bthis\s+' +
            RegExp.escape(spelling) +
            r'\s+product\b',
        caseSensitive: false,
      ).hasMatch(flat),
    );
    // A handful of catalog entries are real, current manufacturers
    // (ETC/Electronic Theatre Controls, WORK/WORK Pro, Highlite's
    // Infinity line) that are *also* common English words/abbreviations
    // far too frequent in ordinary manual prose to trust from raw
    // occurrence count the way the rest of the catalog is - unlike the
    // entries the generator denylists outright (see
    // scripts/update_brand_catalog.py), these are established enough
    // brands that deleting them entirely would make them permanently
    // unattributable even when a manual plainly does self-identify.
    // Require the same explicit self-identification signal used above
    // instead of occurrence count for these specifically.
    if (entry.requiresStrongSignal && !selfIdentifies) continue;
    final score =
        offsets.length +
        (early ? 1 : 0) +
        (coOccurs ? 1 : 0) +
        (selfIdentifies ? 20 : 0);
    if (score > bestScore ||
        (score == bestScore &&
            (best == null || entry.canonical.compareTo(best.name) < 0))) {
      bestScore = score.toDouble();
      best = _IdentityMatch(
        name: entry.canonical,
        tier: 'catalog',
        occurrences: offsets.length,
        early: early,
        coOccursWithModel: coOccurs,
        selfIdentifies: selfIdentifies,
        adjacentToModel: adjacentToModel,
      );
    }
  }
  // Minimum-evidence gate: a catalog scan over ~1800 names always finds
  // *some* match in a long enough document, and plenty of catalog entries
  // are themselves ordinary English words ("Play", "Strong") or product
  // words a MagicQ/GDTF source happens to also list as a "manufacturer"
  // ("Fusion", "Helix" — see the entries this file's generator denylists).
  // Picking whichever such word occurs most often, when the manual simply
  // never names its actual maker anywhere (a real corpus shape: several
  // rebranded/white-label manuals in this benchmark's corpus never
  // mention their own brand at all), produces a confidently WRONG brand
  // instead of an honest "Unknown manufacturer" — worse than not
  // guessing. Require either an explicit self-identification ("thank you
  // for purchasing this <brand> product") or a real, repeated, early
  // presence before ever trusting a tier-2 catalog match.
  //
  // A brand mentioned right next to the fixture's own detected model name
  // ("The Equinox Fusion 200 Zoom Spot can be operated...") is a much
  // stronger signal per mention than an incidental repeat elsewhere in
  // the manual, so it clears the bar at a lower count — but still not on
  // a single mention alone (real corpus shape: Equinox_Fusion200ZoomSpot_
  // UM names "Equinox" exactly twice, both directly beside the model
  // name; that is real, load-bearing evidence a flat >=6 count was
  // throwing away). This deliberately checks the tight [adjacentToModel]
  // signal, not the generous 800-character [coOccursWithModel] used for
  // score nudging above — that wider window is satisfied by an ordinary
  // prose word purely from page-header density (see adjacentToModel's own
  // doc comment) and must never be allowed to override this gate.
  final modelCoOccurrenceRescue =
      best != null && best.adjacentToModel && best.occurrences >= 2;
  if (best != null &&
      !best.selfIdentifies &&
      !modelCoOccurrenceRescue &&
      best.occurrences < 6) {
    return null;
  }
  return best;
}

/// Evidence-based replacement for the old flat 0.92 identity confidence
/// constant. Scores the manufacturer match and the model source
/// separately, then combines them — capping hard for the two known
/// low-trust shapes this pack targets: a model that's just the source
/// filename echoed back, and a manufacturer found only through weak
/// catalog evidence (or not found at all).
double _identityConfidence({
  required _IdentityMatch? manufacturerMatch,
  required bool modelFromTitle,
  required bool modelIsFilenameEcho,
}) {
  double manufacturerConfidence;
  if (manufacturerMatch == null) {
    manufacturerConfidence = .15;
  } else if (manufacturerMatch.tier == 'known') {
    // These brands are independently verified at 94-100% on the GDTF
    // benchmark (scripts/eval) — keep the same high trust they always had.
    manufacturerConfidence = .95;
  } else {
    manufacturerConfidence =
        (.5 +
                .1 * manufacturerMatch.occurrences.clamp(0, 3) +
                (manufacturerMatch.early ? .1 : 0) +
                (manufacturerMatch.coOccursWithModel ? .15 : 0))
            .clamp(0, .85);
  }
  final modelConfidence = modelFromTitle
      ? .9
      : modelIsFilenameEcho
      ? .35
      : .15;
  var overall = (manufacturerConfidence + modelConfidence) / 2;
  if (modelIsFilenameEcho) overall = overall.clamp(0, .45);
  if (manufacturerMatch == null) overall = overall.clamp(0, .35);
  return overall.clamp(.05, .97);
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

/// The model name a manual's title gives, as the pages after the cover
/// spell it. A cover page that is only an image reaches the parser as OCR,
/// which misreads a styled title ("ENCORE LPIeZ IP", "HYDRO SPOT |", "FUZE
/// WASH SOO") or reads the artwork as a word ("AwAs"), while the pages
/// inside usually name the product correctly ("Thank you for purchasing the
/// Encore LP12Z IP").
///
/// Both sides are folded before they are compared: lower-cased, with i, l,
/// | and ! read as 1, o as 0, s as 5, z as 2 and b as 8, and everything but
/// letters and digits dropped. A [pick] that matches a run of whole words
/// after the cover keeps its own spelling when the two differ only in case,
/// spacing and punctuation, and otherwise takes the spelling of the first
/// such run without a | or ! in it ("HYDRO SPOT |" becomes "Hydro Spot 1").
/// A pick found nowhere after the cover gives way to the closest match
/// between a line before the second page and a run of about as many words
/// after the cover: more than 80% alike by edit distance, holding a digit
/// that isn't a unit ("150W", "IP65"), holding no DMX value range, and
/// passing the same title checks as any other model. A name with no number
/// of its own is never taken this way, and can take in a neighbouring one
/// ("IP Pixel Controller 1" from "1. Introduction"). Page markers and photo
/// headers are no words.
String? _corroboratedModel(String text, String? pick) {
  final markers = RegExp(
    r'^=== DMXTRACT PAGE \d+ ===[ \t]*$',
    multiLine: true,
  ).allMatches(text).toList();
  if (pick == null || markers.length < 2) return pick;
  bool isMarker(String line) => line.trimLeft().startsWith('===');
  String fold(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[il|!]'), '1')
      .replaceAll('o', '0')
      .replaceAll('s', '5')
      .replaceAll('z', '2')
      .replaceAll('b', '8')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final words = <String>[];
  final folded = <String>[];
  for (final line in text.substring(markers[1].start).split('\n')) {
    if (isMarker(line)) continue;
    for (final word in line.split(RegExp(r'\s+'))) {
      final key = fold(word);
      if (key.isEmpty) continue;
      words.add(word);
      folded.add(key);
    }
  }
  String trimmed(String value) =>
      value.replaceAll(RegExp(r'^[^A-Za-z0-9]+|[^A-Za-z0-9]+$'), '');
  String letters(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final target = fold(pick);
  var found = false;
  for (var i = 0; i < folded.length && target.isNotEmpty; i++) {
    if (!target.startsWith(folded[i])) continue;
    var joined = '';
    for (var j = i; j < folded.length; j++) {
      joined += folded[j];
      if (!target.startsWith(joined)) break;
      if (joined.length < target.length) continue;
      found = true;
      // A | or ! in the run stood in for a 1, I or l, even at either end,
      // where trimming the spelling would drop it ("HYDRO SPOT |").
      final run = words.sublist(i, j + 1).join(' ');
      final spelled = trimmed(run);
      if (letters(spelled) == letters(pick)) return pick;
      if (!RegExp('[|!]').hasMatch(run)) {
        return _modelFromManualTitle(spelled) ?? pick;
      }
      break;
    }
  }
  if (found) return pick;
  final at = <String, List<int>>{};
  for (var i = 0; i < folded.length; i++) {
    if (folded[i].length >= 2) at.putIfAbsent(folded[i], () => []).add(i);
  }
  // A model number is a digit that isn't a unit ("150W", "IP65") in a name
  // that holds no DMX value range ("000-020 No Function" on a table page).
  final unit = RegExp(
    r'^(?:IP\d{2}|\d+(?:[.,]\d+)?(?:W|V|VAC|Hz|mm|cm|kg|lbs?|°|K|%))$',
    caseSensitive: false,
  );
  bool modelLike(String name) =>
      !RegExp(r'\d{1,3}[ \t]*[-–—~][ \t]*\d{1,3}').hasMatch(name) &&
      name
          .split(RegExp(r'\s+'))
          .any(
            (token) => RegExp(r'\d').hasMatch(token) && !unit.hasMatch(token),
          );
  String? best;
  var bestScore = .8;
  for (final raw in text.substring(0, markers[1].start).split('\n')) {
    if (isMarker(raw)) continue;
    final line = trimmed(raw.trim());
    final tokens = line.split(RegExp(r'\s+'));
    if (letters(line).length < 4 ||
        tokens.length > 6 ||
        _looksLikePageFurniture(line)) {
      continue;
    }
    final wanted = tokens.map(fold).join(' ');
    for (final token in tokens) {
      for (final position in at[fold(token)] ?? const <int>[]) {
        for (var size = tokens.length - 1; size <= tokens.length + 1; size++) {
          for (var from = position - size + 1; from <= position; from++) {
            if (size < 1 || from < 0 || from + size > words.length) continue;
            final score = _similarity(
              wanted,
              folded.sublist(from, from + size).join(' '),
            );
            if (score <= bestScore) continue;
            final model = _modelFromManualTitle(
              trimmed(words.sublist(from, from + size).join(' ')),
            );
            if (model != null && modelLike(model)) {
              bestScore = score;
              best = model;
            }
          }
        }
      }
    }
  }
  return best ?? pick;
}

/// 1 minus the edit distance between [a] and [b] over the longer length.
double _similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    previous = current;
  }
  return 1 - previous[b.length] / (a.length > b.length ? a.length : b.length);
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
    this.gdtfAttribute,
  });

  final String name;
  final String kind;
  final String? fineOf;
  final String? color;
  final List<DmxRange>? ranges;
  final double confidence;

  /// A specific GDTF attribute this channel is confident enough to name
  /// directly, from [gdtfAttributeForChannelName]'s mined name-to-
  /// attribute table — e.g. "Gobo1PosRotate" rather than the coarse
  /// "Gobo1" every generic [kind] `goboWheel` channel otherwise defaults
  /// to (see `defaultGdtfAttribute`). Null means "no opinion, let the
  /// usual kind/color-based default apply."
  final String? gdtfAttribute;
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
      // A row whose only real content is a byte-order/bit-depth marker
      // ("LSB", "16 bit", a bare "Fine") and no attribute word of its own
      // is this fixture's way of printing a fine byte's row without
      // repeating the coarse channel's name (real corpus shape: a coarse
      // "Dimmer (MSB)" row immediately followed by a lone "LSB"-only
      // continuation). Treat it as the fine companion of the immediately
      // preceding coarse channel, the same way [containsFineValue] above
      // already does for a bare 0-65535/32768/65535 value with no text.
      final isBareFineMarker = RegExp(
        r'^(?:lsb|16[ -]?bit|fine)$',
        caseSensitive: false,
      ).hasMatch(description);
      if (isBareFineMarker &&
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
          gdtfAttribute: definition.gdtfAttribute,
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
  // A fine byte shares its coarse channel's GDTF Attribute (that's what
  // makes it a fine byte rather than an independent control) — see
  // model.dart's DmxChannel.fineOf doc.
  gdtfAttribute: coarse.gdtfAttribute,
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
        gdtfAttribute: definition.gdtfAttribute,
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
/// The default `tokenPattern` for [_parseModeMatrixSection]'s row grammar
/// and [_mergeSplitMatrixRows]'s line-rejoining pass, so the two agree on
/// what counts as a bare position token. Robe's house style (see
/// [_robeProtocolModeTables]) passes [_robeMatrixTokenPattern] instead: it
/// prints an absent function as a bare asterisk, never a dash - and
/// Robe's own value-range grammar *does* use a plain dash ("20-24 ..."),
/// so accepting dash as an absent-token there too would misparse an
/// ordinary Robe value line as a channel row.
const _matrixTokenPattern = r'(?:\d{1,3}|[-–—])';

/// Robe's absent-position token - see [_matrixTokenPattern].
const _robeMatrixTokenPattern = r'(?:\d{1,3}|\*)';

/// One mode-matrix header occurrence — from any grammar this file
/// recognizes ([_labeledModeMatrixTables], [_sparseModeMatrixTables],
/// [_robeProtocolModeTables]) — reduced to its byte offsets and the
/// per-column channel counts it declares, so they can all be merged into a
/// single position-ordered pass over the document via [_tablesFromHeaders].
class _MatrixHeaderMatch {
  _MatrixHeaderMatch({
    required this.start,
    required this.end,
    required this.counts,
  });
  final int start;
  final int end;
  // A null entry means this header declares a column's mode but not its
  // total channel count (Robe's "Mode/channel" grammar - see
  // [_robeProtocolModeTables]); [_parseModeMatrixSection] infers it from
  // the highest row position it actually observes in that column instead.
  final List<int?> counts;
}

/// Turns a position-ordered list of mode-matrix header occurrences into the
/// tables they bound: a run of headers declaring the same column counts (a
/// page-break continuation) is one continuous table section, and a header
/// with different counts starts a new one. Shared by every header grammar
/// this file recognizes ([_labeledModeMatrixTables], [_sparseModeMatrixTables]
/// and [_robeProtocolModeTables]'s two) so they only have to produce
/// `_MatrixHeaderMatch`es, not re-implement this grouping.
List<_DetectedModeTable> _tablesFromHeaders(
  String text,
  List<_MatrixHeaderMatch> headers, {
  String tokenPattern = _matrixTokenPattern,
}) {
  headers.sort((a, b) => a.start.compareTo(b.start));
  final tables = <_DetectedModeTable>[];
  var index = 0;
  while (index < headers.length) {
    final counts = headers[index].counts;
    if (counts.length < 2) {
      index++;
      continue;
    }
    var next = index + 1;
    while (next < headers.length && _sameCounts(headers[next].counts, counts)) {
      next++;
    }
    final sectionEnd = next < headers.length
        ? headers[next].start
        : text.length;
    // A run of same-counts headers (page-break continuations of one
    // table) must have every occurrence's own header text excised from
    // the section, not just the first's - otherwise a later repeat's
    // bare-number prefix (e.g. the sparse grammar's "48 64 80 ...
    // Function") still tokenizes as an ordinary row whose leading columns
    // happen to equal each mode's own declared channel count, and
    // clobbers that mode's real last row (see _sparseModeMatrixTables;
    // COLORado Solo Bar 4 reprints its header on every page).
    final buffer = StringBuffer();
    var cursor = headers[index].end;
    for (var k = index + 1; k < next; k++) {
      buffer.write(text.substring(cursor, headers[k].start));
      cursor = headers[k].end;
    }
    buffer.write(text.substring(cursor, sectionEnd));
    tables.addAll(
      _parseModeMatrixSection(
        buffer.toString(),
        counts,
        tokenPattern: tokenPattern,
      ),
    );
    index = next;
  }
  return tables;
}

/// Grammar 1: each column names its own channel count with a "Ch" unit,
/// e.g. "3Ch 12Ch 28Ch Function ..." (Chauvet DJ Rotosphere/Sentinel style).
/// Unbounded column count - real manuals in this family top out at 3, but
/// nothing here assumes that. This is the original, long-established
/// mode-matrix grammar every real corpus fixture using it currently scores
/// perfect footprint recall/precision on, so callers can trust a non-empty
/// result from this one alone not to have missed a sibling table elsewhere
/// in the same document the way the sparser grammars below sometimes do.
List<_DetectedModeTable> _labeledModeMatrixTables(String text) {
  final labeledHeaderPattern = RegExp(
    r'^[ \t]*((?:\d{1,3}\s*-?\s*Ch\b[ \t]*){2,})Function\b',
    caseSensitive: false,
    multiLine: true,
  );
  List<int> labeledCountsOf(RegExpMatch match) => RegExp(
    r'(\d{1,3})\s*-?\s*Ch\b',
    caseSensitive: false,
  ).allMatches(match.group(1)!).map((m) => int.parse(m.group(1)!)).toList();

  final headers = [
    for (final match in labeledHeaderPattern.allMatches(text))
      _MatrixHeaderMatch(
        start: match.start,
        end: match.end,
        counts: labeledCountsOf(match),
      ),
  ];
  if (headers.isEmpty) return const [];
  return _tablesFromHeaders(text, headers);
}

/// Grammar 2: the same table family printed with sparse leading columns but
/// no per-column "Ch" unit - just the bare channel-count numbers themselves
/// immediately before "Function", e.g. Chauvet Pro's COLORado Solo Bar 4
/// "48 64 80 160 115 131 147 259 Function Value Percent/Setting" (one
/// column per DMX personality: RGB 48ch through RGBWL Full 259ch, in header
/// order - the same "declared column order maps to mode order" rule
/// grammar 1 already relies on). A manual using this grammar also prints a
/// "`<count>: <mode name>`" legend line just above the header's *first*
/// occurrence, for a human reader.
///
/// Capped at 8 columns (2..8) and requiring the counts to be pairwise
/// distinct, so an unrelated numbered list that happens to end in the word
/// "Function" elsewhere in a manual can't be mistaken for a table header.
/// That alone isn't enough, though: this bare "several numbers then
/// Function" shape also matches Elation's unrelated "DMX CHANNEL TRAITS"
/// table (e.g. FuzeWashZ350's "15 16 17 19 FUNCTION"), which has no such
/// legend and whose modes are better served by the named/sequential table
/// paths this grammar would otherwise preempt (see the caller ordering in
/// [_matrixLikeModeTables]) - so a result here is only trusted when at
/// least one candidate header is corroborated by that legend line
/// appearing shortly before it; without it, this whole grammar backs off
/// and returns nothing for the document. This is a *document-level* gate,
/// not per-header: page-break repeats of a genuine header (COLORado Solo
/// Bar 4 reprints its header on every page) don't carry the legend
/// themselves, only the section's first occurrence does.
///
/// Even for a genuine match, only *some* of the document's personality
/// groups may print this shape (COLORado Solo Bar 4's smallest, "1 Cell",
/// group instead prints each personality pair as its own
/// differently-shaped small table this file doesn't parse), so unlike
/// grammar 1 a non-empty result here isn't proof the document's full mode
/// set was found - see `mayHaveGaps` on [_matrixLikeModeTables].
List<_DetectedModeTable> _sparseModeMatrixTables(String text) {
  final bareHeaderPattern = RegExp(
    r'^[ \t]*((?:\d{1,3}[ \t]+){1,7}\d{1,3})[ \t]+Function\b',
    caseSensitive: false,
    multiLine: true,
  );
  List<int> bareCountsOf(RegExpMatch match) => RegExp(
    r'\d{1,3}',
  ).allMatches(match.group(1)!).map((m) => int.parse(m.group(0)!)).toList();

  final headers = [
    for (final match in bareHeaderPattern.allMatches(text))
      if (bareCountsOf(match).toSet().length == bareCountsOf(match).length)
        _MatrixHeaderMatch(
          start: match.start,
          end: match.end,
          counts: bareCountsOf(match),
        ),
  ];
  if (headers.isEmpty) return const [];
  final legendPattern = RegExp(r'\d{1,3}\s*:\s*[A-Za-z]');
  final hasCorroboratingLegend = headers.any((header) {
    final windowStart = header.start > 500 ? header.start - 500 : 0;
    return legendPattern.hasMatch(text.substring(windowStart, header.start));
  });
  if (!hasCorroboratingLegend) return const [];
  return _tablesFromHeaders(text, headers);
}

/// Robe's own "DMX protocol" per-mode channel table house style (seen on
/// the Robin Footsie and LEDBeam families) - conceptually the same
/// "several modes as parallel position columns" shape the two grammars
/// above handle, but different enough in its header and absent-function
/// marker to need its own recognizer:
///
///  - a "Mode/Total channels" or "Mode/channel" label line introduces the
///    table (e.g. "Robin Footsie1.../... - DMX protocol" followed by
///    "Mode/Total channels   DMX ...  Function ... Type of ... control");
///  - the column-header row that actually repeats on every page is either
///    "`<mode>/<total>  <mode>/<total>  ...  Value ...  control`" (Footsie:
///    the total channel count for that mode is declared right there, e.g.
///    "1/5   2/28   3/35   Value") or just "`<mode>  <mode>  ...  Value`
///    ...  control" (LEDBeam: only the bare mode index, e.g. "1   2
///    Value" - that mode's total isn't declared anywhere in the source
///    and [_parseModeMatrixSection] infers it from the highest row
///    position it actually observes, via a null `counts` entry);
///  - "this function doesn't exist in this mode" is printed as a bare "*"
///    rather than a dash (see [_robeMatrixTokenPattern]).
///
/// The bare "`<n> <n> ... Value`" shape on its own is indistinguishable from
/// an ordinary row whose function happens to be literally named "Value N"
/// (e.g. Chauvet Pro COLORado Solo Bar's own "3   Value 1" row - see
/// [_sparseModeMatrixTables]), so a header candidate here is only accepted
/// when a "Mode/(Total )channel(s)" label appears shortly before it.
List<_DetectedModeTable> _robeProtocolModeTables(String text) {
  final labelPattern = RegExp(
    r'Mode\s*/\s*(?:Total\s+)?channels?\b',
    caseSensitive: false,
  );
  bool hasNearbyLabel(int start) {
    final windowStart = start > 400 ? start - 400 : 0;
    return labelPattern.hasMatch(text.substring(windowStart, start));
  }

  final totalsHeaderPattern = RegExp(
    r'^[ \t]*((?:\d{1,2}/\d{1,3}[ \t]+){1,7})Value\b',
    multiLine: true,
  );
  final indexHeaderPattern = RegExp(
    r'^[ \t]*((?:\d{1,2}[ \t]+){1,7})Value\b',
    multiLine: true,
  );

  final headers = [
    for (final match in totalsHeaderPattern.allMatches(text))
      if (hasNearbyLabel(match.start))
        _MatrixHeaderMatch(
          start: match.start,
          end: match.end,
          counts: RegExp(r'\d{1,2}/(\d{1,3})')
              .allMatches(match.group(1)!)
              .map((m) => int.parse(m.group(1)!))
              .toList(),
        ),
    for (final match in indexHeaderPattern.allMatches(text))
      if (hasNearbyLabel(match.start))
        _MatrixHeaderMatch(
          start: match.start,
          end: match.end,
          counts: List<int?>.filled(
            RegExp(r'\d{1,2}').allMatches(match.group(1)!).length,
            null,
          ),
        ),
  ];
  if (headers.isEmpty) return const [];
  return _tablesFromHeaders(
    text,
    headers,
    tokenPattern: _robeMatrixTokenPattern,
  );
}

/// ADJ / Eliminator "DMX Traits" house style: one position column per DMX
/// personality under a header row of channel counts ("11-CH MODE 24-CH
/// MODE", "24 Ch 34 Ch 64 Ch VALUES", "31Ch 55Ch 57Ch 60Ch 237Ch VALUES",
/// "30ch 36ch 45ch"), then DMX VALUES and FUNCTION/DESCRIPTION columns. It is
/// the same "several modes as parallel position columns" idea as the
/// grammars above, but none of their row grammar carries over, so it has its
/// own section parser ([_parseModeColumnTraits]):
///
///  - a function a personality lacks is a *blank* cell, not a dash or an
///    asterisk. manual_extractor.js (table_columns.js) reads each number's
///    column off the page geometry and prints "–" for a blank cell, so a
///    text-layer PDF arrives with every row explicit ("11   –   –   000-255
///    Amber All"); without that (a photo, a scan) a row carries anywhere from
///    one number to one per column, and [_assignModeColumns] infers where
///    each lone number sat;
///  - each position cell is merged down its function's whole block and
///    vertically centered, so the numbers land on whichever line sits at
///    the block's middle: part-way down a color list ("4   110 - 126
///    Pink"), alone ("5"), or next to nothing but each other ("4   10");
///  - the function name is a bold row of its own above the value rows
///    ("UV Strobe", then "000 - 007   No strobe"); a one-range function
///    either does the same or names itself at the head of that range's
///    description ("2   7   000 - 255   4-in-1 LED + UV Show Speed , Slow to
///    Fast"), and one merged cell can hold two name rows (Dim Modes, then
///    Dimming Speed, on one channel);
///  - a DMX value can be a single number ("141   0.1 s", "000   No
///    Function"), which only reads unambiguously once rows are explicit;
///  - a "…" row skips repeated pixel blocks ("Red 2".."Lime 2", "…", "Red
///    6"), filled back in by [_expandTraitsRepeats];
///  - a block cut by a page break reprints its name and numbers, marked
///    "(cont'd from prev page)", "(cont.)" or "(continued)" - or not marked
///    at all.
///
/// A smaller personality is not a prefix of a larger one: its functions come
/// in a different order and can include ones no other personality has
/// (Eliminator Furious Five RG's 11-CH column reads 1, 2, 3, 6, 4, 5, 9, 7,
/// 8, 10, 11 down the page, and its channel 3 exists in no other mode), so
/// every mode is assembled from its own column.
///
/// The header repeats at the top of every page the table spans, so each
/// occurrence is read only to the end of its own page, and the prose pages
/// after the table never reach the row parser. A page read twice - a photo's
/// two OCR passes, or an OCR'd page's detailed and broad readings - carries
/// the header twice; only the copy with the most value rows is used.
List<_DetectedModeTable> _modeColumnTraitsTables(String text) {
  // A count's unit, with the letter that tells two personalities of one size
  // apart ("8Ch-A 8Ch-B" on COB Cannon LP200X, "9Ch A 9Ch B" on Par Z300
  // RGBA).
  const unit = r'CH(?:[ \t]*-[ \t]*([A-Z])\b|[ \t]+([A-Z])\b)?';
  const word = r'(?:(?:DMX[ \t]+)?VALUES?|DESCRIPTION|FUNCTIONS?)\b';
  final headerPattern = RegExp(
    '^[ \\t]*((?:\\d{1,3}[ \\t]*-?[ \\t]*$unit(?:[ \\t]+MODE)?\\b[ \\t]*)'
    '{2,16})(?:(?:DMX[ \\t]+)?VALUES?\\b[ \\t]*)?'
    '(?:(?:DESCRIPTION|FUNCTIONS?)\\b[ \\t]*)?\$',
    caseSensitive: false,
    multiLine: true,
  );
  final countPattern = RegExp(
    '(\\d{1,3})[ \\t]*-?[ \\t]*$unit',
    caseSensitive: false,
  );
  // A count printed over its unit a row down ("58" above "Ch-A" on Vizi Pix
  // Z19, "126" above "CH" on Jolt Panel FX2), sometimes with the VALUES label
  // on a row between.
  final stackedPattern = RegExp(
    '^[ \\t]*((?:[1-9]\\d{0,2}[ \\t]+){1,15}[1-9]\\d{0,2})'
    '(?:[ \\t]+$word)*[ \\t]*\\r?\\n'
    '(?:[ \\t]*$word(?:[ \\t]+$word)*[ \\t]*\\r?\\n)?'
    '[ \\t]*((?:$unit[ \\t]*){2,16})\$',
    caseSensitive: false,
    multiLine: true,
  );
  final unitPattern = RegExp(unit, caseSensitive: false);
  String variant(RegExpMatch match, int group) => match.group(group) != null
      ? '-${match.group(group)}'
      : match.group(group + 1) != null
      ? ' ${match.group(group + 1)}'
      : '';
  final pageStarts = [
    for (final marker in RegExp(
      r'^=== DMXTRACT PAGE \d+ ===[ \t]*$',
      multiLine: true,
    ).allMatches(text))
      marker.start,
  ];
  final headers =
      <({int start, int end, List<int> counts, List<String> variants})>[];
  void addHeader(RegExpMatch match, List<int> counts, List<String> variants) {
    final labels = {
      for (var i = 0; i < counts.length; i++) '${counts[i]}${variants[i]}',
    };
    if (counts.length >= 2 &&
        counts.length == variants.length &&
        counts.every((count) => count >= 1 && count <= 512) &&
        labels.length == counts.length) {
      headers.add((
        start: match.start,
        end: match.end,
        counts: counts,
        variants: variants,
      ));
    }
  }

  for (final match in headerPattern.allMatches(text)) {
    final labels = countPattern.allMatches(match.group(1)!).toList();
    addHeader(
      match,
      [for (final label in labels) int.parse(label.group(1)!)],
      [for (final label in labels) variant(label, 2)],
    );
  }
  for (final match in stackedPattern.allMatches(text)) {
    addHeader(
      match,
      [
        for (final count in match.group(1)!.trim().split(RegExp(r'[ \t]+')))
          int.parse(count),
      ],
      [
        for (final label in unitPattern.allMatches(match.group(2)!))
          variant(label, 1),
      ],
    );
  }
  headers.sort((a, b) => a.start.compareTo(b.start));
  // Consecutive headers are one table when they name the same personalities
  // and differ in at most one count - a misprint on one page (Encore LP12Z
  // IP's first traits page reads "16Ch" where the next two read "18Ch").
  // Each column takes the largest count printed.
  bool sameTable(
    ({List<int> counts, List<String> variants}) a,
    ({List<int> counts, List<String> variants}) b,
  ) {
    if (a.counts.length != b.counts.length) return false;
    var differ = 0;
    for (var i = 0; i < a.counts.length; i++) {
      if (a.variants[i] != b.variants[i]) return false;
      if (a.counts[i] != b.counts[i]) differ++;
    }
    return differ <= 1;
  }

  final tables = <_DetectedModeTable>[];
  var index = 0;
  while (index < headers.length) {
    final counts = [...headers[index].counts];
    final variants = headers[index].variants;
    var next = index + 1;
    while (next < headers.length &&
        sameTable(
          (counts: headers[next].counts, variants: headers[next].variants),
          (counts: headers[index].counts, variants: variants),
        )) {
      for (var i = 0; i < counts.length; i++) {
        if (headers[next].counts[i] > counts[i]) {
          counts[i] = headers[next].counts[i];
        }
      }
      next++;
    }
    // One copy of the table per page: the one with the most value rows.
    final byPage = <int, List<String>>{};
    final valueRow = RegExp(r'\b\d{1,3}[ \t]?[-–—][ \t]?\d{1,3}\b');
    int valueRows(List<String> lines) =>
        lines.where((line) => valueRow.hasMatch(line)).length;
    for (var k = index; k < next; k++) {
      final start = headers[k].end;
      final nextHeader = k + 1 < headers.length ? headers[k + 1].start : null;
      final pageBreak = pageStarts
          .where((marker) => marker > start)
          .firstOrNull;
      final end =
          pageBreak != null && (nextHeader == null || pageBreak < nextHeader)
          ? pageBreak
          : nextHeader ?? text.length;
      final lines = text.substring(start, end).split(RegExp(r'\r\n|\r|\n'));
      final page = pageStarts.where((marker) => marker < start).length;
      final kept = byPage[page];
      if (kept == null || valueRows(lines) >= valueRows(kept)) {
        byPage[page] = lines;
      }
    }
    tables.addAll(
      _parseModeColumnTraits(byPage.values.toList(), counts, variants),
    );
    index = next;
  }
  return tables;
}

/// What a [_modeColumnTraitsTables] line says once its position cells are
/// set aside: a value range ("000 - 007   Off", or a single value "141
/// 0.1 s"), a function name or other text, or a "…" row. A single value
/// whose description is a bare number ("173   900", in Hz under a "LED
/// Refresh Rate (Hz)" name row) is flagged, since it reads just like a stray
/// pair of numbers.
typedef _TraitsContent = ({
  (int, int)? range,
  String text,
  bool ellipsis,
  bool bareValue,
});

_TraitsContent _traitsContent(String value) {
  final line = value.trim();
  // "…", "...", or dots in every column with the value range left standing
  // ("..   ...   ...   0-255 ..." on ElectraPix Bar 16).
  if (RegExp(
    '^(?:…|\\.{2,})(?:[\\s,.…]|\\d{1,3}[ \\t]*$_rangeSeparatorClass'
    '[ \\t]*\\d{1,3})*\$',
  ).hasMatch(line)) {
    return (range: null, text: '', ellipsis: true, bareValue: false);
  }
  final range = RegExp(
    '^(\\d{1,3})[ \\t]*$_rangeSeparatorClass[ \\t]*(\\d{1,3})(?!\\d)'
    '(?:[ \\t]+(.*))?\$',
  ).firstMatch(line);
  if (range != null) {
    final start = int.parse(range.group(1)!);
    final end = int.parse(range.group(2)!);
    if (start <= end && end <= 255) {
      return (
        range: (start, end),
        text: (range.group(3) ?? '').trim(),
        ellipsis: false,
        bareValue: false,
      );
    }
  }
  // A single value sits in the VALUES column, a column gap away from what it
  // does ("141   0.1 s"); a name that merely starts with a number is one run
  // of text ("64 Color Macros").
  final single = RegExp(r'^(\d{1,3})[ \t]{2,}(\S.*)$').firstMatch(line);
  if (single != null && int.parse(single.group(1)!) <= 255) {
    final value = int.parse(single.group(1)!);
    final description = single.group(2)!.trim();
    return (
      range: (value, value),
      text: description,
      ellipsis: false,
      bareValue: !RegExp('[A-Za-z]').hasMatch(description),
    );
  }
  // A name or description has words - or is the "100%" that a description
  // wrapped after "0 to" leaves for its last line; whatever else is left
  // over (OCR specks, stray punctuation, a lone page number) is noise.
  return (
    range: null,
    text: RegExp(r'[A-Za-z]|^\d{1,3}[ \t]*%$').hasMatch(line) ? line : '',
    ellipsis: false,
    bareValue: false,
  );
}

/// One physical line of a [_modeColumnTraitsTables] section: its leading
/// run of position-like tokens (a number, or null for a "–" printed in a
/// blank cell) and the text left after each of them, so the line can be read
/// once the section knows how many of those tokens are really cells - the
/// rest ("30   36   45   237   6000" under three columns) begin the value.
class _TraitsLine {
  _TraitsLine({
    required this.cells,
    required this.continued,
    required this.restAfter,
  });
  List<int?> cells;

  /// The line carried a "(cont'd from prev page)" or "(continued)" marker.
  final bool continued;

  /// `restAfter[k]` is the line after its first k tokens; `restAfter[0]` is
  /// the whole line.
  final List<String> restAfter;

  /// Whether [cells] are positions; decided per section in
  /// [_parseModeColumnTraits].
  bool positional = false;
  late _TraitsContent content;

  /// Already folded into a neighbouring range's wrapped description.
  bool consumed = false;
  bool get isBareText =>
      !positional && content.range == null && content.text.isNotEmpty;
}

/// One function's block in a [_modeColumnTraitsTables] section: its name
/// row, the position it holds in each mode column (null for a blank cell),
/// and its value ranges. A block cut by a page break arrives as two of
/// these, joined later by the positions they share.
class _TraitsBlock {
  _TraitsBlock(int columnCount, {this.label, this.continued = false})
    : positions = List<int?>.filled(columnCount, null);
  String? label;
  final bool continued;
  final List<int?> positions;
  final ranges = <({int start, int end, String text})>[];
  bool get hasPositions => positions.any((position) => position != null);
  bool overlaps(int start, int end) =>
      ranges.any((range) => start <= range.end && end >= range.start);
}

final _traitsContinuedCell = RegExp(
  r"\(\s*cont(?:['’`]?d\b|inued\b|\.|\b)(?:[ \t]+from)?"
  r'(?:[ \t]+prev(?:ious)?)?(?:[ \t]+page)?[ \t]*\)?',
  caseSensitive: false,
);

/// The rest of a "(cont'd from prev page)" cell after it wrapped onto the
/// next line(s) of its narrow column: "from prev", "prev page)", "page)".
final _traitsContinuedTail = RegExp(
  r'^(?:from[ \t]+prev(?:ious)?(?:[ \t]+page)?[ \t]*\)?'
  r'|prev(?:ious)?[ \t]+page[ \t]*\)?|page[ \t]*\))(?=[ \t]|$)',
  caseSensitive: false,
);

final _traitsHeaderWords = RegExp(
  r'^(?:channel|mode|(?:dmx[ \t]+)?values?|description|functions?)'
  r'(?:[ \t]+(?:channel|mode|(?:dmx[ \t]+)?values?|description|functions?))*$',
  caseSensitive: false,
);

_TraitsLine? _traitsLine(String raw) {
  var line = raw.trim();
  if (line.isEmpty || line.startsWith('=== DMXTRACT PAGE')) return null;
  var continued = false;
  line = line.replaceFirst(_traitsContinuedTail, '').replaceAllMapped(
    _traitsContinuedCell,
    (_) {
      continued = true;
      return '   ';
    },
  ).trim();
  // Page furniture, the header's own words, a "CONTINUED ON NEXT PAGE"
  // footer, and a note printed across the description column ("NOTE: LED
  // Spot Strobe works only when...") are none of them rows.
  if (line.isEmpty ||
      _looksLikePageFurniture(line) ||
      _traitsHeaderWords.hasMatch(line) ||
      RegExp(
        r'^(?:continued\b|notes?\b|\*)',
        caseSensitive: false,
      ).hasMatch(line)) {
    return null;
  }
  // A position is never zero-padded ("000" is a DMX value), never the start
  // of a range ("110 - 126", "000-255") and never the first word of a name
  // ("64 Color Macros" - a cell is followed by a column gap, another cell or
  // the end of the line). A range's separator sits at most a space from its
  // numbers; a blank cell's "–" sits a column gap away ("20   –   000-255").
  final cell = RegExp(
    r'^(?:([1-9]\d{0,2})|[-–—])(?=[ \t]{2,}|[ \t][\d–—-]|[ \t]*$)',
  );
  final rangeAhead = RegExp('^[ \\t]?$_rangeSeparatorClass[ \\t]?\\d');
  final cells = <int?>[];
  final restAfter = [line];
  while (true) {
    final match = cell.firstMatch(restAfter.last);
    if (match == null) break;
    final after = restAfter.last.substring(match.end);
    if (match.group(1) != null && rangeAhead.hasMatch(after)) break;
    cells.add(match.group(1) == null ? null : int.parse(match.group(1)!));
    restAfter.add(after.trimLeft());
  }
  final whole = _traitsContent(line);
  if (cells.isEmpty &&
      whole.range == null &&
      whole.text.isEmpty &&
      !whole.ellipsis) {
    return null;
  }
  return _TraitsLine(cells: cells, continued: continued, restAfter: restAfter);
}

List<_DetectedModeTable> _parseModeColumnTraits(
  List<List<String>> pages,
  List<int> counts,
  List<String> variants,
) {
  final columnCount = counts.length;
  final pageLines = [
    for (final page in pages) [for (final raw in page) ?_traitsLine(raw)],
  ];
  // Rows made explicit by manual_extractor.js carry one cell per column,
  // blanks printed as "–". Once any has, a line with fewer cells isn't a
  // position row - its leading number is a DMX value ("141   0.1 s") -
  // unless it continues a block across a page break.
  final explicit = pageLines.any(
    (lines) => lines.any(
      (line) => line.cells.length == columnCount && line.cells.contains(null),
    ),
  );
  for (final lines in pageLines) {
    for (final line in lines) {
      if (line.cells.length > columnCount) {
        line.cells = line.cells.sublist(0, columnCount);
      }
      final numbered = line.cells.any((cell) => cell != null);
      line.positional =
          numbered &&
          (line.cells.length == columnCount ||
              line.continued ||
              (!explicit && !line.cells.contains(null)));
      line.content = _traitsContent(
        line.restAfter[line.positional ? line.cells.length : 0],
      );
    }
  }
  final lines = <_TraitsLine>[];
  for (final page in pageLines) {
    // Below a page's last value row sits only its footer - the page number
    // (which reads exactly like a lone position number), a web address, the
    // title lines of a second copy of the page - since a block cut by the
    // page break is reprinted on the next one. The one exception is the
    // second half of a wrapped description whose range is that last row.
    final lastRange = page.lastIndexWhere((line) => line.content.range != null);
    var keep = lastRange + 1;
    if (lastRange >= 0 &&
        page[lastRange].content.text.isEmpty &&
        keep < page.length &&
        page[keep].isBareText) {
      keep++;
    }
    page.removeRange(keep, page.length);
    lines.addAll(page);
  }

  final last = List<int>.filled(columnCount, 0);
  final used = [for (final _ in counts) <int>{}];
  final blocks = <_TraitsBlock>[];
  final gaps = <int>[];
  _TraitsBlock? current;
  // A description line that arrived with its block's position numbers,
  // waiting for the value range it describes.
  ({_TraitsBlock block, String text})? pending;

  // Whether bare text at lines[i], right after a value row that printed no
  // description, is that row's description rather than the next function's
  // name: it is when another text line follows (the next name), or a row
  // that names its own value, or nothing. A name is followed by its values -
  // and a line broken with a hyphen, or followed by one that ends in ",",
  // begins a name ("RGB Background" / "Color Macros ,").
  bool describesAbove(int i) {
    final next = lines.skip(i + 1).where((line) => !line.consumed).firstOrNull;
    if (lines[i].content.text.endsWith('-') ||
        (next != null && next.isBareText && next.content.text.endsWith(','))) {
      return false;
    }
    return next == null ||
        next.content.ellipsis ||
        next.isBareText ||
        (next.positional &&
            next.content.range != null &&
            next.content.text.isNotEmpty);
  }

  // Records a line's cells as [block]'s positions when they fit its
  // still-blank columns: straight across for a row with a cell per column,
  // by [_assignModeColumns] otherwise. A cell past its column's count is a
  // misprint (COB Cannon LP200X prints "166" between its 20Ch column's 15
  // and 17), so that column stays blank on the block and the channel it
  // should have named is left for the Check step to ask about.
  bool place(_TraitsBlock block, _TraitsLine line) {
    final positions = line.cells.length == columnCount
        ? [
            for (var column = 0; column < columnCount; column++)
              (line.cells[column] ?? counts[column] + 1) <= counts[column]
                  ? line.cells[column]
                  : null,
          ]
        : _assignModeColumns(
            [for (final cell in line.cells) ?cell],
            counts,
            last,
            used,
            continued: line.continued || block.continued,
          );
    if (positions == null) return false;
    for (var column = 0; column < columnCount; column++) {
      final held = block.positions[column];
      if (positions[column] != null &&
          held != null &&
          held != positions[column]) {
        return false;
      }
    }
    for (var column = 0; column < columnCount; column++) {
      final position = positions[column];
      if (position == null) continue;
      block.positions[column] = position;
      last[column] = position;
      used[column].add(position);
    }
    return true;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.consumed) continue;
    final open = current;
    // A description too long for its cell wraps onto a second line, and the
    // range, centered on the now taller row, lands between the two halves:
    // "Both LED Spots, Contrasting Single Color Half" / "062 - 088" /
    // "Display". Only inside a block still collecting values - after a
    // finished block the same shape is a name row, a range left blank, and
    // the next name row - unless the second half starts in lower case, the
    // rest of a sentence ("Auto Programs Fade, minimum to maximum" / "000 -
    // 255" / "fade", a one-range function's own row), or the first half
    // breaks off mid-phrase ("Outer Green, 0 to" / "000-255" / "100%"), or
    // repeats the name of the function just before ("Inner Program Macro" /
    // "000-255" / "Speed" after Inner Program Macro itself).
    if (line.isBareText &&
        i + 2 < lines.length &&
        lines[i + 1].content.range != null &&
        lines[i + 1].content.text.isEmpty &&
        lines[i + 2].isBareText &&
        (RegExp(
              r'^\p{Ll}',
              unicode: true,
            ).hasMatch(lines[i + 2].content.text) ||
            RegExp(r'\bto$').hasMatch(line.content.text) ||
            (open != null && open.label == line.content.text) ||
            (open != null &&
                open.ranges.isNotEmpty &&
                !_rangesCoverFull([
                  for (final range in open.ranges)
                    DmxRange(
                      start: range.start,
                      end: range.end,
                      name: range.text,
                    ),
                ])))) {
      final middle = lines[i + 1];
      middle.content = (
        range: middle.content.range,
        text: _joinTraitsWrap(line.content.text, lines[i + 2].content.text),
        ellipsis: false,
        bareValue: false,
      );
      lines[i + 2].consumed = true;
      continue;
    }
    final content = line.content;
    if (content.ellipsis) {
      gaps.add(blocks.length);
      current = null;
      continue;
    }
    if (content.range == null && content.text.isNotEmpty) {
      final lower = RegExp(r'^\p{Ll}', unicode: true).hasMatch(content.text);
      if (!line.positional &&
          open != null &&
          open.label != null &&
          open.ranges.isEmpty &&
          !open.hasPositions) {
        // A function name long enough to wrap onto a second line.
        open.label = _joinTraitsWrap(open.label!, content.text);
        continue;
      }
      if (!line.positional &&
          open != null &&
          open.ranges.isNotEmpty &&
          (lower ||
              (open.hasPositions &&
                  open.ranges.last.text.isEmpty &&
                  describesAbove(i)))) {
        // The rest of the last range's description, wrapped below it ("23 -
        // 99" / "refer to Color Temperature Chart"), or all of it when the
        // value row printed none ("Color Macros" / "... 0-255" / "(See
        // Color Macros)" / "Color Temperature" on COB Cannon LP200X). A
        // description still waiting for its value takes the line instead.
        if (lower && identical(pending?.block, open)) {
          pending = (block: open, text: '${pending!.text} ${content.text}');
          continue;
        }
        final last = open.ranges.removeLast();
        open.ranges.add((
          start: last.start,
          end: last.end,
          text: '${last.text} ${content.text}'.trim(),
        ));
        continue;
      }
      if (line.positional &&
          open != null &&
          open.label != null &&
          !open.hasPositions &&
          place(open, line)) {
        // The block's position numbers, centered on a line of its merged
        // cell that holds text: the rest of its name ("Outer Strobe Dura-" /
        // "tion"), or a line of a description that wraps around the value
        // below it ("White Color Temperature Presets," above "23 - 99").
        final label = open.label!;
        if (open.ranges.isEmpty && (label.endsWith('-') || lower)) {
          open.label = _joinTraitsWrap(label, content.text);
        } else {
          pending = (block: open, text: content.text);
        }
        continue;
      }
      // A "100%" left over from a wrapped description is no name.
      if (!RegExp('[A-Za-z]').hasMatch(content.text)) continue;
      final block = _TraitsBlock(
        columnCount,
        label: content.text,
        continued: line.continued,
      );
      blocks.add(block);
      current = block;
      if (line.positional) place(block, line);
      continue;
    }
    if (content.range == null) {
      if (!line.positional) continue;
      // Position numbers on a line of their own, centered in the block.
      if (open != null &&
          (!open.hasPositions || line.continued) &&
          place(open, line)) {
        continue;
      }
      final block = _TraitsBlock(columnCount);
      blocks.add(block);
      current = block;
      place(block, line);
      continue;
    }
    final (start, end) = content.range!;
    if (content.bareValue &&
        (open == null || open.ranges.any((range) => range.end >= start))) {
      // A bare "value   number" pair only counts while it carries on up the
      // open block's values ("173   900" after "171 - 172"); anywhere else
      // it is a stray ("55   55" after "160   10 s").
      continue;
    }
    final joinsOpen =
        open != null &&
        !open.overlaps(start, end) &&
        (!line.positional || !open.hasPositions || line.continued);
    final block = joinsOpen ? open : _TraitsBlock(columnCount);
    if (!joinsOpen) {
      blocks.add(block);
      current = block;
    }
    if (line.positional) place(block, line);
    final lead = identical(pending?.block, block) ? pending!.text : '';
    pending = null;
    var text = '$lead ${content.text}'.trim();
    final comma = text.endsWith(',') ? text.length - 1 : text.indexOf(' , ');
    if (block.ranges.isEmpty &&
        block.label != null &&
        lead.isEmpty &&
        start == 0 &&
        end == 255 &&
        comma > 0 &&
        RegExp(r'^\p{L}', unicode: true).hasMatch(text)) {
      // ADJ ends a name with " ," and the description follows it. On the
      // one value (0-255) of a block whose name row is above, words up to
      // that comma are the rest of the name ("RGBAL+UV Pro -" / "... 000-255 grams
      // Speed ," / "slow to fast"; "RGB Background" / "... 000-255 Program
      // Fade , least" / "to most"); a description wrapped at a comma starts
      // with its value instead ("2300–9900K Linear," / "0–100%").
      block.label = _joinTraitsWrap(
        block.label!,
        text.substring(0, comma).trim(),
      );
      text = text
          .substring(comma + 1)
          .replaceFirst(RegExp(r'^\s*,?'), '')
          .trim();
    }
    block.ranges.add((start: start, end: end, text: text));
  }
  _expandTraitsRepeats(blocks, gaps, columnCount);
  _mergeTraitsNameRows(blocks);

  final tables = <_DetectedModeTable>[];
  for (var column = 0; column < columnCount; column++) {
    final byPosition = <int, List<_TraitsBlock>>{};
    for (final block in blocks) {
      final position = block.positions[column];
      if (position != null) {
        byPosition.putIfAbsent(position, () => []).add(block);
      }
    }
    final size = counts[column];
    tables.add(
      _DetectedModeTable(
        code: '${size}Ch${variants[column]}',
        channelCount: size,
        parsedCount: byPosition.length,
        channels: [
          for (var position = 1; position <= size; position++)
            byPosition[position] == null
                ? _DetectedChannel(
                    name: 'Channel $position',
                    kind: 'generic',
                    confidence: .25,
                  )
                : _traitsChannel(byPosition[position]!, position),
        ],
      ),
    );
  }
  // A header that most of the widest personality's rows didn't follow -
  // printed on the table's first page only, say - is too little evidence to
  // claim the document from the other grammars.
  final widest = tables.reduce(
    (a, b) => a.channelCount >= b.channelCount ? a : b,
  );
  return widest.parsedCount * 2 < widest.channelCount ? const [] : tables;
}

/// A block's function name - its name row, or for a one-range function the
/// head of that range's description - split around its last number:
/// "Ring Red 60" is template "Ring Red #", index 60. A space before the
/// number doesn't matter: ElectraPix Bar 16 prints its first pixel "Red1"
/// and its last "Red 16".
({String template, int index})? _traitsIndex(_TraitsBlock block) {
  final name =
      block.label ??
      (block.ranges.length == 1
          ? block.ranges.single.text.split(',').first
          : null);
  final match = name == null
      ? null
      : RegExp(r'^(.*?)(\d+)(\D*)$').firstMatch(name.trim());
  if (match == null) return null;
  return (
    template: '${match.group(1)!.trimRight()} #${match.group(3)}',
    index: int.parse(match.group(2)!),
  );
}

/// The two halves of a wrapped name or description, as one: "Dimmer Fine
/// (Inten -" and "sity)" are a word broken by a hyphen.
String _joinTraitsWrap(String first, String second) {
  final hyphen = RegExp(r'[ \t]*-$').firstMatch(first);
  return hyphen != null && RegExp(r'^\p{Ll}', unicode: true).hasMatch(second)
      ? '${first.substring(0, hyphen.start)}$second'
      : '$first $second';
}

String _withTraitsIndex(String value, int from, int to) =>
    value.replaceAll(RegExp('(?<![0-9])$from(?![0-9])'), '$to');

/// Fills in the functions a table skips with a "…" row: repeated pixel
/// blocks it prints only for the first pixels and the last ("Red 1".."Lime
/// 2", "…", "Red 6".."Lime 6"). The run of blocks just above the gap that
/// share one index is the repeating unit, and the block just below names the
/// index the run resumes at. A column is filled only when the unit sits in it
/// as consecutive positions and the block below lands exactly the skipped
/// units further on; otherwise that column is left for the user to check.
void _expandTraitsRepeats(
  List<_TraitsBlock> blocks,
  List<int> gaps,
  int columnCount,
) {
  final added = <_TraitsBlock>[];
  for (final gap in gaps) {
    if (gap == 0 || gap >= blocks.length) continue;
    final above = _traitsIndex(blocks[gap - 1]);
    final below = _traitsIndex(blocks[gap]);
    if (above == null || below == null || below.index <= above.index + 1) {
      continue;
    }
    final unit = <_TraitsBlock>[];
    for (var i = gap - 1; i >= 0; i--) {
      if (_traitsIndex(blocks[i])?.index != above.index) break;
      unit.insert(0, blocks[i]);
    }
    if (_traitsIndex(unit.first)!.template != below.template) continue;
    final skipped = below.index - above.index - 1;
    final columns = <int>[];
    for (var column = 0; column < columnCount; column++) {
      final held = [for (final block in unit) block.positions[column]];
      if (held.contains(null)) continue;
      final first = held.first!;
      final consecutive = [
        for (var k = 0; k < held.length; k++) held[k] == first + k,
      ].every((ok) => ok);
      if (consecutive &&
          blocks[gap].positions[column] ==
              first + (skipped + 1) * unit.length) {
        columns.add(column);
      }
    }
    if (columns.isEmpty) continue;
    for (var step = 1; step <= skipped; step++) {
      final index = above.index + step;
      for (final member in unit) {
        final copy = _TraitsBlock(
          columnCount,
          label: member.label == null
              ? null
              : _withTraitsIndex(member.label!, above.index, index),
        );
        for (final column in columns) {
          copy.positions[column] =
              member.positions[column]! + step * unit.length;
        }
        for (final range in member.ranges) {
          copy.ranges.add((
            start: range.start,
            end: range.end,
            text: _withTraitsIndex(range.text, above.index, index),
          ));
        }
        added.add(copy);
      }
    }
  }
  blocks.addAll(added);
}

/// One merged position cell can hold two function-name rows on the same DMX
/// channel, and the cell's numbers then sit beside only one of them: VIZI
/// FX7's Dim Modes, then Dimming Speed with the numbers; Protégé XL's
/// Special Functions with the numbers, then LED Refresh Rate (Hz). A named
/// block left without a position is folded into the neighbour it carries on
/// from - the block above when its values continue past that block's, else
/// the block below when they stop short of where that block's begin.
void _mergeTraitsNameRows(List<_TraitsBlock> blocks) {
  int lowest(_TraitsBlock block) =>
      block.ranges.map((range) => range.start).reduce((a, b) => a < b ? a : b);
  int highest(_TraitsBlock block) =>
      block.ranges.map((range) => range.end).reduce((a, b) => a > b ? a : b);
  bool anchors(_TraitsBlock block) =>
      block.hasPositions && block.ranges.isNotEmpty;
  var i = 0;
  while (i < blocks.length) {
    final block = blocks[i];
    if (block.hasPositions || block.label == null || block.ranges.isEmpty) {
      i++;
      continue;
    }
    final above = i > 0 ? blocks[i - 1] : null;
    final below = i + 1 < blocks.length ? blocks[i + 1] : null;
    if (above != null && anchors(above) && highest(above) < lowest(block)) {
      above.label = above.label == null
          ? block.label
          : '${above.label} / ${block.label}';
      above.ranges.addAll(block.ranges);
      blocks.removeAt(i);
    } else if (below != null &&
        anchors(below) &&
        highest(block) < lowest(below)) {
      below.label = below.label == null
          ? block.label
          : '${block.label} / ${below.label}';
      below.ranges.insertAll(0, block.ranges);
      blocks.removeAt(i);
    } else {
      i++;
    }
  }
}

/// Places a row's position numbers into mode columns when some of its cells
/// were blank ([_modeColumnTraitsTables]). The numbers keep their left-to-
/// right order, and a column only takes a position inside its mode that it
/// hasn't used yet. The table is printed in the widest mode's order, so that
/// column counts up one block at a time while the narrower ones jump
/// around: a placement that continues a column's own count (its last
/// position + 1) wins, and ties go to the wider columns. A number that
/// resumes a block after a page break ("(cont'd from prev page)") repeats
/// its column's last position instead. Null when nothing fits.
List<int?>? _assignModeColumns(
  List<int> numbers,
  List<int> counts,
  List<int> last,
  List<Set<int>> used, {
  required bool continued,
}) {
  final columnCount = counts.length;
  if (numbers.isEmpty || numbers.length > columnCount) return null;
  List<int?>? best;
  var bestScore = -1;
  var bestWidth = -1;
  final placed = List<int?>.filled(columnCount, null);
  void search(int index, int fromColumn, int score, int width) {
    if (index == numbers.length) {
      if (score > bestScore || (score == bestScore && width > bestWidth)) {
        best = List.of(placed);
        bestScore = score;
        bestWidth = width;
      }
      return;
    }
    final number = numbers[index];
    final lastColumn = columnCount - (numbers.length - index);
    for (var column = fromColumn; column <= lastColumn; column++) {
      if (number < 1 || number > counts[column]) continue;
      if (continued ? number != last[column] : used[column].contains(number)) {
        continue;
      }
      final continuesCount = continued || number == last[column] + 1;
      placed[column] = number;
      search(
        index + 1,
        column + 1,
        score + (continuesCount ? 1 : 0),
        width + counts[column],
      );
      placed[column] = null;
    }
  }

  search(0, 0, 0, 0);
  if (best == null && continued) {
    return _assignModeColumns(numbers, counts, last, used, continued: false);
  }
  return best;
}

/// Builds one mode position's channel from the block(s) holding it: the
/// function name from its name row (or, for a one-range function, from the
/// head of that range's description), and the union of its ranges across a
/// page break.
_DetectedChannel _traitsChannel(List<_TraitsBlock> parts, int position) {
  var label = parts.map((part) => part.label).nonNulls.firstOrNull;
  final kept = <({int start, int end, String text})>[];
  for (final part in parts) {
    for (final range in part.ranges) {
      if (kept.every(
        (other) => range.end < other.start || range.start > other.end,
      )) {
        kept.add(range);
      }
    }
  }
  kept.sort((a, b) => a.start.compareTo(b.start));
  final descriptions = [for (final range in kept) range.text];
  if (label == null && kept.length == 1) {
    // "Master Dimmer , 0 to 100%": the name, then what the range does.
    final text = kept.single.text;
    // ADJ separates the name from what the range does with " , ", and a
    // name can hold a comma of its own ("LED Spot, Outboard Color").
    final spaced = text.indexOf(' , ');
    final comma = spaced >= 0 ? spaced : text.indexOf(',');
    label = comma < 0 ? text : text.substring(0, comma);
    descriptions[0] = comma < 0 ? '' : text.substring(comma + 1);
  }
  final name = _cleanFunction(label ?? '');
  if (name.isEmpty) {
    return _DetectedChannel(
      name: 'Channel $position',
      kind: 'generic',
      ranges: [
        for (var i = 0; i < kept.length; i++)
          _traitsRange(
            kept[i].start,
            kept[i].end,
            descriptions[i],
            strobe: false,
          ),
      ],
      confidence: .5,
    );
  }
  final classified = _classifyTableChannel(name, position);
  // "Red Laser" names an emitter, not a color-mixing component: keep a
  // laser's on/off control out of colorIntensity, so nothing that drives
  // color (a console's color picker, an RGB effect) can switch it on.
  final laser = RegExp(r'\blaser\b', caseSensitive: false).hasMatch(name);
  final kind = laser && classified.kind == 'colorIntensity'
      ? 'generic'
      : classified.kind;
  return _DetectedChannel(
    name: name,
    kind: kind,
    fineOf: classified.fineOf,
    color: kind == 'colorIntensity' ? classified.color : null,
    ranges: [
      for (var i = 0; i < kept.length; i++)
        _traitsRange(
          kept[i].start,
          kept[i].end,
          descriptions[i],
          strobe: kind == 'strobe',
        ),
    ],
    gdtfAttribute: kind == classified.kind ? classified.gdtfAttribute : null,
  );
}

/// [_matrixRange], except that a strobe channel's steady settings ("No
/// strobe", "Off") stay out of the strobe safety class.
DmxRange _traitsRange(
  int start,
  int end,
  String description, {
  required bool strobe,
}) {
  final range = _matrixRange(start, end, description);
  final lower = range.name.toLowerCase();
  final steady = RegExp(
    r'^(?:no\s+(?:strobe|function)|off|open|closed|blackout)\b',
  ).hasMatch(lower);
  range.safety = (strobe || lower.contains('strobe')) && !steady
      ? 'strobe'
      : 'normal';
  return range;
}

/// Runs every "several DMX modes as parallel position columns" table
/// grammar this file recognizes and returns the first one that finds
/// anything - a manual only ever uses one of these families, so there's no
/// need to merge results across them. `mayHaveGaps` tells the caller
/// whether a non-empty result is trustworthy as the *complete* set of
/// modes the document declares (grammar 1, long-established and already
/// scoring perfect footprint recall/precision on every real corpus fixture
/// that uses it) or might only be a subset, leaving some of the document's
/// personality groups printed in a still-unsupported table shape elsewhere
/// (grammar 2, Robe's grammar and ADJ's `<N>-CH MODE` traits grammar, all
/// new). Callers don't currently fill that gap from the generic
/// channel-count scan - a generic gap-fill pass used to live here but
/// measured out net-negative on the eval corpus (see the call sites) - so
/// `mayHaveGaps` for now only documents the caveat for a future,
/// better-corroborated fill.
({List<_DetectedModeTable> modes, bool mayHaveGaps}) _matrixLikeModeTables(
  String text,
) {
  final labeled = _labeledModeMatrixTables(text);
  if (labeled.isNotEmpty) return (modes: labeled, mayHaveGaps: false);
  final sparse = _sparseModeMatrixTables(text);
  if (sparse.isNotEmpty) return (modes: sparse, mayHaveGaps: true);
  final robe = _robeProtocolModeTables(text);
  if (robe.isNotEmpty) return (modes: robe, mayHaveGaps: true);
  final traits = _modeColumnTraitsTables(text);
  if (traits.isNotEmpty) return (modes: traits, mayHaveGaps: true);
  // No mode-matrix grammar found anything at all - `mayHaveGaps` must stay
  // false here (not true), even though this is the "new, less-trusted
  // grammar" branch: a caller only reads `mayHaveGaps` once it already
  // knows `modes` is non-empty (`matrixModes.isNotEmpty`), but a stray
  // read without that guard must not be misled into treating "no matrix
  // table exists in this document at all" as "found an incomplete one".
  return (modes: const [], mayHaveGaps: false);
}

bool _sameCounts(List<int?> a, List<int?> b) {
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
List<String> _mergeSplitMatrixRows(
  List<String> lines,
  List<int?> counts, {
  String tokenPattern = _matrixTokenPattern,
}) {
  final columnCount = counts.length;
  final bareTokensLine = RegExp('^(?:$tokenPattern[ \\t]+)*$tokenPattern\$');
  final tokenMatcher = RegExp(tokenPattern);
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
        '^[ \\t]*(?:$tokenPattern[ \\t]+){${needed - 1}}'
        '$tokenPattern(?=[ \\t]|\$)',
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
          final bound = counts[position];
          if (value != null &&
              (value < 1 || (bound != null && value > bound))) {
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
  List<int?> counts, {
  String tokenPattern = _matrixTokenPattern,
}) {
  final columnCount = counts.length;
  final rowPattern = RegExp(
    '^[ \\t]*((?:$tokenPattern[ \\t]+){${columnCount - 1}}'
    '$tokenPattern)(?:[ \\t]+(.+?))?[ \\t]*\$',
  );
  final tokenMatcher = RegExp(tokenPattern);
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

  // The header usually declares exactly how many channels each mode has,
  // so once we've matched a row at the highest declared position of the
  // widest mode and filled its ranges to full 0-255 coverage, the table is
  // provably complete — see the `finalRow` check below, which bounds the
  // section instead of letting it run unbounded to the header search's
  // fallback of "rest of the document" and sweep up trailing prose/footers
  // as ranges. A header that doesn't declare any column's total (Robe's
  // "Mode/channel" grammar - see [_robeProtocolModeTables]) can't use this
  // optimization; the caller's own section bound (the next header, or the
  // end of the document) is all that limits how much text is consumed.
  final knownCounts = <int>[for (final c in counts) ?c];
  final maxCount = knownCounts.isEmpty
      ? null
      : knownCounts.reduce((a, b) => a > b ? a : b);
  final maxIndex = maxCount == null ? -1 : counts.indexOf(maxCount);
  _MatrixRow? finalRow;

  // Per-column highest position actually observed in a row, used to size a
  // mode whose total channel count the header didn't declare.
  final observedMax = List<int>.filled(columnCount, 0);

  final rows = <_MatrixRow>[];
  _MatrixRow? currentRow;
  var pendingRanges = <DmxRange>[];
  String? pendingFunction;
  var expectMergeRange = false;

  final lines = _mergeSplitMatrixRows(
    section.split(RegExp(r'\r\n|\r|\n')),
    counts,
    tokenPattern: tokenPattern,
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
        final bound = counts[i];
        if (value != null && (value < 1 || (bound != null && value > bound))) {
          rowPlausible = false;
          break;
        }
      }
    }
    if (rowMatch != null && rowTokens != null && rowPlausible) {
      final tokens = rowTokens;
      for (var i = 0; i < columnCount; i++) {
        final value = tokens[i];
        if (value != null && value > observedMax[i]) observedMax[i] = value;
      }
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
          maxCount != null &&
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
      final bound = counts[modeIndex];
      if (position == null ||
          position < 1 ||
          (bound != null && position > bound)) {
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
          // A merged row's displayed name is the combined "A / B" label,
          // not `definition.name` (classified from just the last of the
          // two folded-in descriptions) — the mined attribute for that
          // one description alone isn't a match for the combined thing.
          gdtfAttribute: row.merged ? null : definition.gdtfAttribute,
        ),
      );
    }
  }

  return [
    for (var modeIndex = 0; modeIndex < columnCount; modeIndex++)
      if ((counts[modeIndex] ?? observedMax[modeIndex]) > 0)
        _DetectedModeTable(
          code: '${counts[modeIndex] ?? observedMax[modeIndex]}Ch',
          channelCount: counts[modeIndex] ?? observedMax[modeIndex],
          parsedCount: parsedByMode[modeIndex].length,
          channels: [
            for (
              var position = 1;
              position <= (counts[modeIndex] ?? observedMax[modeIndex]);
              position++
            )
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
          gdtfAttribute: definition.gdtfAttribute,
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
    gdtfAttribute: chosen.gdtfAttribute,
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
    gdtfAttribute: channel.gdtfAttribute,
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
    var match = RegExp(r'^\s*(\d{1,3})\s+(.+?)\s*$').firstMatch(line);
    if (match == null || int.tryParse(match.group(1)!) != expected) {
      // Sparse leading position columns (blank/dash when a row's function
      // doesn't apply to one of the fixture's other, simpler personalities
      // that share this same table) can push the table's real sequential
      // position past first place — real corpus shapes: Chauvet COLORado
      // SOLO Bar 4's 16-cell "XY | Ext. Function" table (one throwaway
      // column: "– 2 Fine dimmer 1 000 255 0-100%") and the same
      // fixture's 259-channel "RGBWL Ext./Full" table, which stacks up to
      // seven personality columns ahead of the real "Ext. Function"
      // number ("– – – – 1 1 1 1 Dimmer 1 ...", "– – – – – – – 2 Fine
      // dimmer 1 ..."). Greedily consume up to seven throwaway
      // digit/dash tokens and capture the number immediately before the
      // description — the one those other tables' single-throwaway shape
      // already relied on — so both widths resolve to the same rightmost
      // number. Only tried once the plain single-leading-number match
      // above fails, so an ordinary "N <description>" table is never
      // affected.
      final secondary = RegExp(
        r'^\s*(?:(?:\d{1,3}|[-–—])\s+){1,7}(\d{1,3})\s+(.+?)\s*$',
      ).firstMatch(line);
      match = secondary != null && int.tryParse(secondary.group(1)!) == expected
          ? secondary
          : null;
    }
    if (match != null) {
      var description = match.group(2)!;
      description = description.replaceAll(RegExp(r'\s+'), ' ').trim();
      final base = _classifyTableChannel(description, expected);
      // Values-column bleed guard: a genuine channel-function row always
      // has some descriptive text (a word), not just digits. A row whose
      // classified name comes out as bare digits means every real column
      // was numeric — a multi-value data table (a Color Macros Chart's
      // "MACRO | DMX VALUE | RED | GREEN | BLUE | ..." rows, say) that
      // happens to start each row with a small sequential number, not an
      // actual per-channel function table. [_classifyTableChannel]'s
      // leading-mode-column stripping mis-anchors on it and leaves one
      // stray value column masquerading as the channel name (real corpus
      // shapes: ADJ_Encore_LP12Z_IP's "18CH" mode reading macro RGB
      // values 80/80/77/83... as channel names, ADJ_Focus_Wash_400's
      // "17Ch" mode reading the macro table's trailing all-zero column as
      // "0" for every channel). Fall back to a neutral "Channel N" name
      // instead of fabricating one from the bled value column, and drop
      // the bogus `kind`/`gdtfAttribute` guess along with it (a bare
      // number never resolves through the mined map either way, so `base`
      // itself is already `kind: 'generic'` here — this just also throws
      // away whatever [_rangesFromLine] parsed the numeric "name" text as
      // a range).
      //
      // Deliberately NOT rejecting the row outright (no entry, `expected`
      // held back): a genuine channel table can have one stray numeric-
      // looking row sitting among otherwise-good rows (the mis-anchor is
      // per-row, not per-table), and dropping the entry shrinks
      // `detected.length` right when [_tableChannels]'s adoption
      // threshold (`tableChannels.length >= 4 && >= half of count`) is
      // deciding whether to use this table at all — confirmed on real
      // data: rejecting outright pushed ADJ_Vizi_Beam_RX2_UM's real, 159-
      // range table below that threshold, discarding it wholesale for
      // the canonical-guess fallback's single default range per channel.
      // Keeping the row (renamed, not removed) preserves both the
      // channel count the threshold sees and the row's own range data,
      // and also keeps `expected` in lock-step with the row numbers the
      // source document actually prints, so a later real "N
      // <description>" row still matches instead of the rest of the
      // table truncating into this one row's rejection.
      final isValuesColumnBleed = RegExp(r'^\d+$').hasMatch(base.name);
      final name = isValuesColumnBleed ? 'Channel $expected' : base.name;
      final ranges = <DmxRange>[
        ...pendingRanges,
        ..._rangesFromLine(description, name, base.kind),
      ]..sort((a, b) => a.start.compareTo(b.start));
      pendingRanges.clear();
      detected.add(
        _DetectedChannel(
          name: name,
          kind: isValuesColumnBleed ? 'generic' : base.kind,
          fineOf: isValuesColumnBleed ? null : base.fineOf,
          color: isValuesColumnBleed ? null : base.color,
          ranges: ranges,
          gdtfAttribute: isValuesColumnBleed ? null : base.gdtfAttribute,
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
  // Coarse/fine byte-order labels ("Pan MSB"/"Tilt LSB", a bare "16 bit"/
  // "16-bit" tag) are a second common notation for a coarse/fine pair,
  // alongside the literal word "fine" every branch below already looks
  // for (real corpus shape: Martin_MAC700Profile_UM prints "Dimmer (MSB)"
  // for the coarse row and "Dimmer, fine (LSB)" for its fine byte).
  // Normalizing MSB away and LSB/16-bit onto the word "fine" here, once,
  // lets every attribute branch's existing fine detection cover this
  // notation too instead of duplicating msb/lsb/16-bit checks in each of
  // them — "Pan MSB" reads exactly like plain "Pan" (msb is the default,
  // most-significant byte), and "Pan LSB"/"Pan 16 Bit" reads exactly
  // like "Pan fine".
  final lower = withoutModeColumns
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\bmsb\b'), '')
      .replaceAll(RegExp(r'\b(?:lsb|16[ -]?bit)\b'), 'fine');
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
  final name = cleaned.isEmpty
      ? 'Channel $channel'
      : cleaned.substring(0, cleaned.length.clamp(0, 48));
  // Last resort, tried only once every hand-written branch above has
  // already failed to match: look the (cleaned) description up against
  // the majority name-to-GDTF-attribute table mined from unified.db
  // (scripts/update_channel_attribute_map.py). It only turns some of
  // what used to fall all the way through to a bare "generic"/NoFeature
  // channel into a specific attribute ("Gobo1PosRotate", "HSB_Hue", a
  // zoned "Color4") the hand-written branches never modeled at all.
  //
  // Deliberately attribute-only: `kind` stays 'generic' and `fineOf` is
  // never set here, even though [kindForGdtfAttribute] could answer both.
  // `kind` isn't just cosmetic — callers key row-acceptance bookkeeping
  // off it (`_parseNamedModeRows`'s `mostRecentCoarse`, this file's
  // `_relationshipKey`/`coarseIds` matrix merge), so changing it can flip
  // which manual row a later position accepts, not just how this one
  // channel is labeled (confirmed regression: AmericanDJ_Ultra_Hex_Bar_12
  // channel 10 moved from the correct "White" row to a DMX-value chart's
  // "Program 10" row once `kind` started following the mined attribute).
  // And a mined `fineOf` would need to name the coarse channel's
  // [_relationshipKey], not a bare kind string — `coarseIds` is keyed by
  // the former (a compound key for every kind [_relationshipKey] knows
  // specially, e.g. "intensity:dimmer" or "pan:2") and stays keyed
  // 'generic' for every other kind, so a bare-kind `fineOf` either can
  // never match its real coarse channel (silently dropped) or, for any
  // mined attribute [kindForGdtfAttribute] doesn't specialize, matches
  // 'generic' and adopts the first unrelated generic channel in the mode
  // as its coarse. A fine byte's Attribute still comes through unchanged
  // — it's carried on `gdtfAttribute`, which fine-channel construction
  // (`_fineChannelFor`) already copies from its coarse channel.
  final mined = gdtfAttributeForChannelName(name);
  if (mined != null) {
    return _DetectedChannel(name: name, kind: 'generic', gdtfAttribute: mined);
  }
  return _DetectedChannel(name: name, kind: 'generic');
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
