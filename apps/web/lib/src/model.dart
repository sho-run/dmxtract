import 'dart:convert';

import 'gdtf_attribute_catalog.dart';

class DmxRange {
  DmxRange({
    required this.start,
    required this.end,
    required this.name,
    this.safety = 'normal',
    this.confidence = 1,
  });
  int start;
  int end;
  String name;
  String safety;
  double confidence;
  bool contains(int value) => value >= start && value <= end;
  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'name': name,
    'capability': null,
    'wheelSlot': null,
    'safety': safety,
    'confidence': {
      'score': confidence,
      'reason': confidence < .65 ? 'Manual text was unclear' : '',
    },
    'source': null,
  };
  factory DmxRange.fromJson(Map<String, Object?> json) {
    final confidence = json['confidence'];
    return DmxRange(
      start: json['start'] as int? ?? 0,
      end: json['end'] as int? ?? 255,
      name: json['name'] as String? ?? 'Unknown',
      safety: json['safety'] as String? ?? 'normal',
      confidence: confidence is Map
          ? (confidence['score'] as num? ?? 1).toDouble()
          : 1,
    );
  }
}

/// The channel kinds the canonical fixture schema (schemas/fixture-v1.json,
/// generated from the Rust core's `ChannelKind`) accepts.
const schemaChannelKinds = {
  'intensity',
  'colorIntensity',
  'pan',
  'tilt',
  'shutter',
  'strobe',
  'colorWheel',
  'goboWheel',
  'goboRotation',
  'focus',
  'zoom',
  'prism',
  'frost',
  'speed',
  'effect',
  'maintenance',
  'generic',
};

/// Folds a kind the schema has no variant for onto the nearest one it does.
/// The extractor classifies a show/program/mode-select control as 'mode' and
/// a CTC control as 'colorTemperature'; the Rust core rejects a fixture
/// carrying either as invalid JSON, which used to fail validation and both
/// exports outright (roughly one real manual in seven in the local corpus).
String schemaChannelKind(String kind) => schemaChannelKinds.contains(kind)
    ? kind
    : kind == 'mode'
    ? 'effect'
    : 'generic';

class DmxChannel {
  DmxChannel({
    required this.id,
    required this.name,
    String kind = 'generic',
    this.fineOf,
    this.color,
    this.wheelId,
    this.gdtfAttribute,
    this.gdtfFeature,
    List<DmxRange>? ranges,
    this.confidence = 1,
  }) : kind = schemaChannelKind(kind),
       ranges = ranges ?? [] {
    // `kind` here is still the constructor argument, not the folded field,
    // so the default attribute keeps the finer meaning (Effects1, CTC).
    gdtfAttribute ??= defaultGdtfAttribute(kind, color);
    gdtfFeature ??= defaultGdtfFeature(gdtfAttribute!);
  }
  String id;
  String name;
  String kind;
  String? fineOf;
  String? color;
  String? wheelId;
  String? gdtfAttribute;
  String? gdtfFeature;
  List<DmxRange> ranges;
  double confidence;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'color': color,
    'fineOf': fineOf,
    'wheelId': wheelId,
    'gdtfAttribute': gdtfAttribute,
    'gdtfFeature': gdtfFeature,
    'ranges': ranges.map((item) => item.toJson()).toList(),
    'confidence': {
      'score': confidence,
      'reason': confidence < .65 ? 'Please check this control' : '',
    },
    'source': null,
  };
  factory DmxChannel.fromJson(Map<String, Object?> json) => DmxChannel(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] as String? ?? 'generic',
    fineOf: json['fineOf'] as String?,
    color: json['color'] as String?,
    wheelId: json['wheelId'] as String?,
    gdtfAttribute: json['gdtfAttribute'] as String?,
    gdtfFeature: json['gdtfFeature'] as String?,
    ranges: (json['ranges'] as List? ?? [])
        .map(
          (item) => DmxRange.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList(),
    confidence: ((json['confidence'] as Map?)?['score'] as num? ?? 1)
        .toDouble(),
  );

  /// The non-"normal" (strobe/lamp/reset/maintenance) range covering
  /// [value], if any. Ranges may overlap (see `validate.rs`'s
  /// `range.overlap` warning, which does not reject them), so this always
  /// checks every range rather than only the first one that contains
  /// [value] — the single source of truth for "is this value risky",
  /// shared by the Test screen's unlock-dialog gate and
  /// `DmxtractState.sendValue`'s send-path gate so the two can never
  /// disagree about the same channel/value pair.
  DmxRange? riskyRangeFor(int value) {
    for (final range in ranges) {
      if (range.contains(value) && range.safety != 'normal') return range;
    }
    return null;
  }

  /// True if [value] falls inside any non-"normal" range. See
  /// [riskyRangeFor].
  bool isRisky(int value) => riskyRangeFor(value) != null;
}

class FixtureMode {
  FixtureMode({
    required this.id,
    required this.name,
    required this.channelIds,
    this.breaks = 1,
    this.shortName = '',
  });
  String id;
  String name;
  String shortName;
  int breaks;
  List<String> channelIds;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'shortName': shortName,
    'breaks': breaks,
    'channels': [
      for (var index = 0; index < channelIds.length; index++)
        {
          'channelId': channelIds[index],
          'offset': index % 512 + 1,
          'dmxBreak': index ~/ 512 + 1,
        },
    ],
    'confidence': {'score': 1, 'reason': ''},
  };
  factory FixtureMode.fromJson(Map<String, Object?> json) => FixtureMode(
    id: json['id'] as String,
    name: json['name'] as String,
    shortName: json['shortName'] as String? ?? '',
    breaks: json['breaks'] as int? ?? 1,
    channelIds: (json['channels'] as List)
        .map((item) => (item as Map)['channelId'] as String)
        .toList(),
  );
}

class FixtureProject {
  FixtureProject({
    required this.id,
    required this.manufacturer,
    required this.model,
    required this.channels,
    required this.modes,
    this.sourceName = '',
    this.identityFromManual = false,
    this.identityConfidence = .92,
    this.wheels = const [],
    this.physical = const {},
  });
  String id;
  String manufacturer;
  String model;
  String sourceName;
  bool identityFromManual;

  /// How much evidence backs [manufacturer]/[model]: 1.0 is an
  /// in-document title match on a brand extraction_rules.dart already
  /// trusts; well under .5 means a filename echo or a brand with only
  /// weak catalog evidence. See extraction_rules.dart's identity-pack
  /// scoring — this replaces what used to be a flat, always-.92 constant.
  double identityConfidence;
  List<DmxChannel> channels;
  List<FixtureMode> modes;
  List<Map<String, Object?>> wheels;
  Map<String, Object?> physical;
  int get maxModeChannelCount => modes.isEmpty
      ? 0
      : modes
            .map((mode) => mode.channelIds.length)
            .reduce((a, b) => a > b ? a : b);
  Map<String, Object?> toJson() => {
    'schema': 'https://dmxtract.sho.run/schemas/fixture-v1.json',
    'schemaVersion': 1,
    'id': id,
    'identity': {
      'manufacturer': manufacturer,
      'model': model,
      'shortName': model,
      'categories': <String>[],
      'confidence': {
        'score': identityConfidence,
        'reason': identityConfidence < .5
            ? 'Please check the maker and model we found'
            : '',
      },
    },
    'physical': physical,
    'provenance': {
      'sourceType': 'manual',
      'sourceName': sourceName,
      'identityFromManual': identityFromManual,
      'importedAt': DateTime.now().toUtc().toIso8601String(),
      'notes': ['Extracted locally in the browser'],
    },
    'channels': channels.map((item) => item.toJson()).toList(),
    'modes': modes.map((item) => item.toJson()).toList(),
    'wheels': wheels,
    'matrix': null,
    'geometry': {
      'body': true,
      'yoke': channels.any((item) => item.kind == 'pan'),
      'head': channels.any((item) => item.kind == 'tilt'),
      'beam': true,
      'pixelEmitters': false,
    },
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  factory FixtureProject.fromJson(Map<String, Object?> json) {
    final identity = Map<String, Object?>.from(json['identity'] as Map);
    return FixtureProject(
      id: json['id'] as String,
      manufacturer: identity['manufacturer'] as String,
      model: identity['model'] as String,
      sourceName: (json['provenance'] as Map?)?['sourceName'] as String? ?? '',
      identityFromManual:
          (json['provenance'] as Map?)?['identityFromManual'] as bool? ?? false,
      identityConfidence:
          ((identity['confidence'] as Map?)?['score'] as num? ?? .92)
              .toDouble(),
      channels: (json['channels'] as List)
          .map(
            (item) =>
                DmxChannel.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(),
      modes: (json['modes'] as List)
          .map(
            (item) =>
                FixtureMode.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(),
      wheels: (json['wheels'] as List? ?? [])
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList(),
      physical: Map<String, Object?>.from(json['physical'] as Map? ?? {}),
    );
  }
}

String slug(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
