part 'channel_attribute_map.g.dart';

final _letterDigitBoundary = RegExp(r'(?<=[a-z])(?=[0-9])|(?<=[0-9])(?=[a-z])');
final _nonAlnum = RegExp(r'[^a-z0-9]+');

/// Normalizes a raw channel description into the same lookup key
/// [channelAttributeMap]'s generator (scripts/update_channel_attribute_map.py)
/// derives from unified.db's `pretty` column: casefold, split a letter
/// directly against an adjacent digit, collapse everything else to single
/// spaces, then strip one trailing standalone digit token (a wheel/zone
/// index) and, after that, one trailing "f"/"fine" token. Returns the key
/// plus the zone digit that was stripped, if any — every generated entry
/// templates its attribute's first digit run onto a `{n}` placeholder
/// (see the generator's `templatize`), and [gdtfAttributeForChannelName]
/// substitutes this zone digit back in, defaulting to "1" when the
/// description had none of its own.
({String key, String? zone}) _channelAttributeKey(String description) {
  final lowered = description.toLowerCase().replaceAllMapped(
    _letterDigitBoundary,
    (_) => ' ',
  );
  final normalized = lowered.replaceAll(_nonAlnum, ' ').trim();
  if (normalized.isEmpty) return (key: '', zone: null);
  var tokens = normalized.split(RegExp(r'\s+'));
  String? zone;
  if (RegExp(r'^\d+$').hasMatch(tokens.last)) {
    zone = tokens.last;
    tokens = tokens.sublist(0, tokens.length - 1);
  }
  if (tokens.isNotEmpty && (tokens.last == 'f' || tokens.last == 'fine')) {
    tokens = tokens.sublist(0, tokens.length - 1);
  }
  return (key: tokens.join(' '), zone: zone);
}

/// Looks up a raw channel description (e.g. "Gobo 1", "Red Fine", "Pan/
/// Tilt Speed") against the generated majority name-to-GDTF-attribute
/// table mined from unified.db, returning a concrete attribute like
/// "Gobo1" — or null when the description isn't a high-confidence match
/// for anything in that table (most likely because one of this file's
/// own [_classifyTableChannel] branches already has a more specific,
/// hand-written rule for it and never falls through to this lookup at
/// all; see that function's use of this map as its last-resort step,
/// tried only once every specific branch has already failed to match).
String? gdtfAttributeForChannelName(String description) {
  final lookup = _channelAttributeKey(description);
  if (lookup.key.isEmpty) return null;
  final template = channelAttributeMap[lookup.key];
  if (template == null) return null;
  if (!template.contains('{n}')) return template;
  // The zone comes straight off the printed description ("Auto program
  // 04" -> "04"), but a GDTF attribute index is a plain integer with no
  // leading zeros ("Effects4", never "Effects04") — round-trip it
  // through int so a zero-padded source digit doesn't leak into the
  // exported attribute name.
  final zone = lookup.zone == null ? null : int.tryParse(lookup.zone!);
  return template.replaceAll('{n}', (zone ?? 1).toString());
}
