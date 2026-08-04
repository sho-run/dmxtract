import 'dart:convert';

import 'package:http/http.dart' as http;

import 'model.dart';

class GdtfProfileMatch {
  const GdtfProfileMatch({
    required this.id,
    required this.manufacturer,
    required this.fixture,
    required this.revision,
    required this.source,
    required this.score,
    required this.url,
    this.rating,
    this.version = '',
    this.modeFootprints = const [],
  });

  final String id;
  final String manufacturer;
  final String fixture;
  final String revision;
  final String source;
  final double score;
  final String url;
  final double? rating;
  final String version;
  final List<int> modeFootprints;

  factory GdtfProfileMatch.fromJson(Map<String, Object?> json) =>
      GdtfProfileMatch(
        id: json['id'] as String? ?? '',
        manufacturer: json['manufacturer'] as String? ?? '',
        fixture: json['fixture'] as String? ?? '',
        revision: json['revision'] as String? ?? '',
        source: json['source'] as String? ?? 'community',
        score: (json['score'] as num? ?? 0).toDouble().clamp(0, 1),
        url: json['url'] as String? ?? 'https://gdtf-share.com/',
        rating: (json['rating'] as num?)?.toDouble(),
        version: json['version'] as String? ?? '',
        modeFootprints: (json['modeFootprints'] as List? ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value > 0 && value <= 65535)
            .toList(growable: false),
      );
}

class GdtfLookupResult {
  const GdtfLookupResult({required this.enabled, this.matches = const []});
  final bool enabled;
  final List<GdtfProfileMatch> matches;
}

class GdtfLookupClient {
  GdtfLookupClient({http.Client? client, Uri? endpoint})
    : _client = client ?? http.Client(),
      _endpoint = endpoint ?? Uri.base.resolve('/api/fixture-matches');

  final http.Client _client;
  final Uri _endpoint;

  Future<GdtfLookupResult> search(FixtureProject fixture) async {
    if (!fixture.identityFromManual ||
        _unknown(fixture.manufacturer) ||
        _unknown(fixture.model)) {
      return const GdtfLookupResult(enabled: false);
    }
    try {
      final response = await _client
          .post(
            _endpoint,
            headers: const {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'manufacturer': fixture.manufacturer,
              'model': fixture.model,
              'modeFootprints': fixture.modes
                  .map((mode) => mode.channelIds.length)
                  .where((count) => count > 0)
                  .toSet()
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200 ||
          !response.headers['content-type'].toString().contains(
            'application/json',
          )) {
        return const GdtfLookupResult(enabled: false);
      }
      final body = jsonDecode(response.body) as Map<String, Object?>;
      return GdtfLookupResult(
        enabled: body['enabled'] == true,
        matches: (body['matches'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  GdtfProfileMatch.fromJson(Map<String, Object?>.from(item)),
            )
            .where(
              (match) =>
                  match.manufacturer.isNotEmpty &&
                  match.fixture.isNotEmpty &&
                  match.score >= .72,
            )
            .take(3)
            .toList(growable: false),
      );
    } catch (_) {
      return const GdtfLookupResult(enabled: false);
    }
  }

  bool _unknown(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty || normalized.startsWith('unknown');
  }
}
