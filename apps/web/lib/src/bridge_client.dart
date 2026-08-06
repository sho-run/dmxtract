import 'dart:convert';
import 'package:http/http.dart' as http;

class ArtNetNode {
  const ArtNetNode({
    required this.host,
    required this.name,
    required this.shortName,
    required this.portCount,
  });
  final String host;
  final String name;
  final String shortName;
  final int portCount;

  factory ArtNetNode.fromJson(Map<String, Object?> json) => ArtNetNode(
    host: json['host'] as String,
    name: json['name'] as String? ?? 'Art-Net node',
    shortName: json['shortName'] as String? ?? '',
    portCount: json['portCount'] as int? ?? 0,
  );
}

enum PairApprovalStatus { pending, approved, denied, expired }

class BridgeClient {
  BridgeClient({this.baseUrl = 'http://127.0.0.1:46321', http.Client? client})
    : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;
  String get controlsUrl => '$baseUrl/';
  String? token;
  String? leaseId;

  Future<bool> isAvailable({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/v1/health'))
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<ArtNetNode>> discoverArtNet() async {
    final response = await _client
        .get(Uri.parse('$baseUrl/v1/discovery/artnet'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode >= 400) return const [];
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    return (decoded['nodes'] as List? ?? const [])
        .map(
          (item) => ArtNetNode.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList();
  }

  Future<String> requestPair(String origin) async {
    final response = await _post('/v1/pair/request', {
      'origin': origin,
    }, authorize: false);
    return response['requestId'] as String;
  }

  Future<void> confirmPair(String requestId, String code) async {
    final response = await _post('/v1/pair/confirm', {
      'requestId': requestId,
      'code': code,
    }, authorize: false);
    token = response['token'] as String;
  }

  Future<PairApprovalStatus> checkPairApproval(String requestId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/v1/pair/$requestId/status'),
    );
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    if (response.statusCode >= 400) {
      throw Exception(decoded['error'] ?? 'Bridge approval failed');
    }
    switch (decoded['status']) {
      case 'approved':
        token = decoded['token'] as String;
        return PairApprovalStatus.approved;
      case 'denied':
        return PairApprovalStatus.denied;
      case 'expired':
        // api.rs `pair_status` returns this exactly once (200, not an
        // error) then removes the pairing record, so the *next* poll would
        // otherwise 400 with a less specific "no longer available" — map
        // it explicitly rather than letting it fall into `pending`.
        return PairApprovalStatus.expired;
      default:
        return PairApprovalStatus.pending;
    }
  }

  Future<String> begin(String origin, Map<String, Object?> output) async {
    final response = await _post('/v1/test/begin', {
      'origin': origin,
      'output': output,
    });
    leaseId = response['leaseId'] as String;
    return response['output'] as String;
  }

  Future<void> setChannel(
    int channel,
    int value, {
    int universe = 1,
    bool risky = false,
  }) async {
    if (leaseId == null) return;
    await _post('/v1/test/$leaseId/channels', {
      'universe': universe,
      'channels': [
        {'channel': channel, 'value': value},
      ],
      'risky': risky,
    });
  }

  Future<void> heartbeat() async {
    if (leaseId != null) await _post('/v1/test/$leaseId/heartbeat', {});
  }

  Future<void> unlock() async {
    if (leaseId != null) await _post('/v1/test/$leaseId/unlock', {});
  }

  Future<void> blackout() async {
    if (leaseId != null) await _post('/v1/test/$leaseId/blackout', {});
  }

  Future<void> end() async {
    if (leaseId != null) await _post('/v1/test/$leaseId/end', {});
    leaseId = null;
  }

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    bool authorize = true,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'content-type': 'application/json',
        if (authorize && token != null) 'authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    if (response.statusCode == 401) {
      // The bridge's idle watchdog can self-exit (`std::process::exit(0)`
      // in api.rs) between requests, which destroys every in-memory
      // session — including the 12-hour token this client is holding. That
      // token is now permanently dead until the user re-pairs; clear it so
      // callers fall back to the pairing flow instead of retrying the same
      // 401 forever.
      token = null;
      leaseId = null;
    }
    if (response.statusCode >= 400) {
      throw Exception(decoded['error'] ?? 'Bridge request failed');
    }
    return decoded;
  }
}
