part 'brand_catalog.g.dart';

/// One fixture manufacturer known from the unified ground-truth database
/// (unified.db, merged from several fixture-library sources on GDTF's
/// model), with alternate spellings collapsed into
/// [aliases] so matching code only has to iterate the merged list once.
class BrandCatalogEntry {
  const BrandCatalogEntry({
    required this.canonical,
    required this.aliases,
    this.requiresStrongSignal = false,
  });

  /// The spelling to report as the fixture's manufacturer.
  final String canonical;

  /// Other case/spacing variants of the same name seen in the source
  /// database (e.g. "LaserWorld" as an alias of canonical "Laserworld").
  final List<String> aliases;

  /// True for a small set of entries that are real, established
  /// manufacturers but whose name also reads as an ordinary English word
  /// or abbreviation ("ETC", "WORK", "Infinity") — too common in
  /// unrelated manual prose to trust from occurrence count the way the
  /// rest of the catalog is. The matcher requires an explicit
  /// self-identification match for these instead of counting words.
  final bool requiresStrongSignal;

  /// All spellings ([canonical] plus every alias) worth scanning a
  /// document for.
  Iterable<String> get spellings => [canonical, ...aliases];
}
