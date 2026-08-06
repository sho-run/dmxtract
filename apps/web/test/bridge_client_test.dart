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

  test('an expired pairing request maps to PairApprovalStatus.expired', () async {
    // api.rs `pair_status` returns this as a 200, not an error, exactly
    // once before pruning the pairing record.
    final client = BridgeClient(
      client: MockClient(
        (_) async => http.Response(
          '{"status":"expired","message":"That pairing request expired. Ask again."}',
          200,
        ),
      ),
    );

    final status = await client.checkPairApproval('request-id');

    expect(status, PairApprovalStatus.expired);
  });

  test('a 401 clears a dead session token instead of leaving it live', () async {
    final client = BridgeClient(
      client: MockClient(
        (_) async => http.Response(
          '{"error":"This token belongs to a different site or has expired."}',
          401,
        ),
      ),
    )..token = 'stale-token';

    await expectLater(
      client.begin('https://example.test', {}),
      throwsException,
    );

    expect(
      client.token,
      isNull,
      reason:
          'a bridge that self-exited its idle watchdog (api.rs '
          'start_idle_watchdog) invalidates every in-memory session; the '
          'client must not keep retrying the same dead token',
    );
  });
}
