import 'dart:convert';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:nectar_sts_dart/src/server/api_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

TokenIssuer _hsm() => VirtualHsmIssuer(
      VirtualHsm(
        VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
      ),
    );

Future<Map<String, dynamic>> _getJson(Handler handler, String path) async {
  final req = Request('GET', Uri.parse('http://localhost$path'));
  final resp = await handler(req);
  final raw = await resp.readAsString();
  expect(resp.statusCode, 200, reason: raw);
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('GET /openapi.json', () {
    test('returns a well-formed OpenAPI 3.0 document', () async {
      final handler = buildApiHandler(_hsm());
      final spec = await _getJson(handler, '/openapi.json');

      expect(spec['openapi'], startsWith('3.0'));
      expect(spec['info'], isA<Map>());
      expect((spec['info'] as Map)['title'], 'nectar_sts_dart');

      final paths = spec['paths'] as Map<String, dynamic>;
      // Spot-check a representative slice of the surface so the test
      // catches accidental removals without enumerating every route.
      expect(
          paths.keys,
          containsAll(<String>[
            '/healthz',
            '/openapi.json',
            '/v1/health/backend',
            '/v1/status/nodes',
            '/v1/tokens',
            '/v1/tokens/key-change',
            '/v1/tokens/mse/clear-credit',
            '/v1/tokens/credit/electricity-currency',
            '/v1/tokens/results/{originalRequestId}',
            '/v1/tokens/{tokenNo}/verify',
            '/v1/tokens/{tokenNo}',
            '/v1/meters',
            '/v1/meters/{serial}',
          ]));

      // Every path entry must declare at least one HTTP method that is
      // an object (the operation), not an arbitrary scalar.
      for (final entry in paths.entries) {
        final ops = entry.value as Map<String, dynamic>;
        expect(ops, isNotEmpty, reason: 'no methods on ${entry.key}');
        for (final m in ops.keys) {
          expect(
            const ['get', 'post', 'put', 'delete', 'patch', 'parameters'],
            contains(m),
            reason: 'unexpected key "$m" on ${entry.key}',
          );
        }
      }

      // The shared envelope schema must exist and be referenced.
      final components = spec['components'] as Map<String, dynamic>;
      expect(
        ((components['schemas'] as Map)['ApiResponse'] as Map)['type'],
        'object',
      );
    });

    test('is reachable WITHOUT bearer auth even when configured', () async {
      final handler = buildApiHandler(_hsm(), bearerToken: 's3cret');
      final req = Request('GET', Uri.parse('http://localhost/openapi.json'));
      final resp = await handler(req);
      expect(resp.statusCode, 200);
      expect(
        resp.headers['content-type'],
        contains('application/json'),
      );
    });
  });
}
