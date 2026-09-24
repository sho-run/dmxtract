part 'gdtf_attribute_catalog.g.dart';

class GdtfAttributeDefinition {
  const GdtfAttributeDefinition({
    required this.name,
    required this.pretty,
    required this.feature,
  });

  final String name;
  final String pretty;
  final String feature;

  String get beginnerLabel => _friendlyLabels[name] ?? _readable(name);
  String get displayLabel => '$beginnerLabel — $name';
  String get searchText =>
      '$beginnerLabel $name $pretty $feature'.toLowerCase();
  String get concreteName => name.replaceAll('(n)', '1').replaceAll('(m)', '1');
}

const _friendlyLabels = <String, String>{
  'Dimmer': 'Brightness / dimmer',
  'Pan': 'Pan movement',
  'Tilt': 'Tilt movement',
  'PanRotate': 'Continuous pan',
  'TiltRotate': 'Continuous tilt',
  'Gobo(n)': 'Gobo wheel',
  'Gobo(n)Pos': 'Gobo position',
  'Gobo(n)PosRotate': 'Gobo rotation',
  'Color(n)': 'Color wheel',
  'ColorAdd_R': 'Red intensity',
  'ColorAdd_G': 'Green intensity',
  'ColorAdd_B': 'Blue intensity',
  'ColorAdd_W': 'White intensity',
  'ColorAdd_WW': 'Warm white intensity',
  'ColorAdd_CW': 'Cool white intensity',
  'ColorAdd_RY': 'Amber intensity',
  'ColorAdd_GY': 'Lime intensity',
  'ColorAdd_UV': 'UV intensity',
  'Shutter(n)': 'Shutter',
  'Shutter(n)Strobe': 'Strobe',
  'StrobeRate': 'Strobe speed',
  'Iris': 'Iris',
  'Frost(n)': 'Frost',
  'Prism(n)': 'Prism',
  'Zoom': 'Zoom',
  'Focus(n)': 'Focus',
  'Effects(n)': 'Effect',
  'Effects(n)Rate': 'Effect speed',
  'FixtureGlobalReset': 'Fixture reset',
  'LampControl': 'Lamp control',
  'Fan(n)': 'Fan',
  'Fog(n)': 'Fog output',
  'Haze(n)': 'Haze output',
  'NoFeature': 'No function / reserved',
};

String _readable(String value) => value
    .replaceAll('(n)', '')
    .replaceAll('(m)', '')
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'(?<=[a-z0-9])(?=[A-Z])'), (_) => ' ');

GdtfAttributeDefinition? gdtfDefinitionFor(String? attribute) {
  if (attribute == null || attribute.isEmpty) return null;
  for (final definition in gdtfAttributeCatalog) {
    final escaped = RegExp.escape(
      definition.name,
    ).replaceAll(r'\(n\)', r'\d+').replaceAll(r'\(m\)', r'\d+');
    final pattern = '^$escaped\$';
    if (RegExp(pattern).hasMatch(attribute)) return definition;
  }
  return null;
}

String defaultGdtfAttribute(String kind, String? color) => switch (kind) {
  'intensity' => 'Dimmer',
  'pan' => 'Pan',
  'tilt' => 'Tilt',
  'colorIntensity' => switch (color?.toUpperCase()) {
    'RED' => 'ColorAdd_R',
    'GREEN' => 'ColorAdd_G',
    'BLUE' => 'ColorAdd_B',
    'WHITE' => 'ColorAdd_W',
    'AMBER' => 'ColorAdd_RY',
    'UV' => 'ColorAdd_UV',
    'CYAN' => 'ColorAdd_C',
    'MAGENTA' => 'ColorAdd_M',
    'YELLOW' => 'ColorAdd_Y',
    'LIME' => 'ColorAdd_GY',
    _ => 'ColorAdd_W',
  },
  'colorWheel' => 'Color1',
  'goboWheel' => 'Gobo1',
  'goboRotation' => 'Gobo1PosRotate',
  'shutter' || 'strobe' => 'Shutter1Strobe',
  'focus' => 'Focus1',
  'zoom' => 'Zoom',
  'prism' => 'Prism1',
  'frost' => 'Frost1',
  'speed' => 'GlobalMSpeed',
  'effect' || 'mode' => 'Effects1',
  'colorTemperature' => 'CTC',
  'maintenance' => 'Function',
  _ => 'NoFeature',
};

String defaultGdtfFeature(String attribute) =>
    gdtfDefinitionFor(attribute)?.feature ?? 'Control.Control';

String kindForGdtfAttribute(String attribute) {
  final definition = gdtfDefinitionFor(attribute);
  final template = definition?.name ?? attribute;
  final feature = definition?.feature ?? 'Control.Control';
  if (template == 'Dimmer') return 'intensity';
  if (template == 'Pan') return 'pan';
  if (template == 'Tilt') return 'tilt';
  if (template.startsWith('ColorAdd_') || template.startsWith('ColorSub_')) {
    return 'colorIntensity';
  }
  if (template.startsWith('Color(n)')) return 'colorWheel';
  if (template.startsWith('Gobo(n)Pos')) return 'goboRotation';
  if (template.startsWith('Gobo(n)')) return 'goboWheel';
  if (template.startsWith('Shutter') || template.startsWith('Strobe')) {
    return 'strobe';
  }
  if (template.startsWith('Focus')) return 'focus';
  if (template.startsWith('Zoom')) return 'zoom';
  if (template.startsWith('Prism')) return 'prism';
  if (template.startsWith('Frost')) return 'frost';
  if (template.contains('Reset') || template == 'LampControl') {
    return 'maintenance';
  }
  if (template.contains('Rate') || template.contains('Speed')) return 'speed';
  if (feature == 'Beam.Beam' || template.startsWith('Effects')) return 'effect';
  return 'generic';
}
