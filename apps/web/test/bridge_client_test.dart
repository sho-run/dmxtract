import 'package:dmxtract_web/src/bridge_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('visible approval stores the origin-bound bridge token', () async {
    final client = BridgeClient(
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          'http://127.0.0.1:46321/v1/pair/request-id/status',
        );
        return http.Response(
          '{"status":"approved","token":"origin-bound-token"}',
          200,
        );
      }),
    );

    final status = await client.checkPairApproval('request-id');

    expect(status, PairApprovalStatus.approved);
    expect(client.token, 'origin-bound-token');
  });

  test('denied visible approval does not create a bridge token', () async {
    final client = BridgeClient(
      client: MockClient(
        (_) async => http.Response('{"status":"denied"}', 200),
      ),
    );

    final status = await client.checkPairApproval('request-id');

    expect(status, PairApprovalStatus.denied);
    expect(client.token, isNull);
  });
}
