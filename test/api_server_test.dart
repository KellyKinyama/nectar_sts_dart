import 'dart:convert';
import 'dart:io';

import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:nectar_sts_dart/src/server/api_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

TokenIssuer _hsm() => VirtualHsmIssuer(
  VirtualHsm(
    VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
  ),
);

class _UnhealthyIssuer implements TokenIssuer {
  @override
  String get name => 'UnhealthyIssuer';

  @override
  Future<Map<String, Object?>> checkBackend() async => {
    'ok': false,
    'backend': name,
    'error': 'boom: connection refused',
  };

  @override
  Future<List<Map<String, Object?>>> getNodeStatus() async =>
      throw StateError('node-status: backend offline');

  @override
  Future<Token> generateToken(String requestId, Map<String, dynamic> params) =>
      throw UnimplementedError();

  @override
  Future<Token> decodeToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) => throw UnimplementedError();

  @override
  Future<List<Map<String, Object?>>> issueKeyChangeTokens(
    String requestId,
    Map<String, dynamic> params,
  ) => throw UnimplementedError();

  @override
  Future<List<Map<String, Object?>>> issueMseToken(
    String requestId,
    int subclass,
    double transferAmount,
    Map<String, dynamic> params,
  ) => throw UnimplementedError();

  @override
  Future<Map<String, Object?>> issueMeterTestToken(
    String requestId,
    int subclass,
    int control,
    int manufacturerCode,
  ) => throw UnimplementedError();

  @override
  Future<List<Map<String, Object?>>> issueCurrencyCreditToken(
    String requestId,
    int subclass,
    Map<String, dynamic> params,
  ) => throw UnimplementedError();

  @override
  Future<List<Map<String, Object?>>> fetchTokenResult(
    String requestId,
    String originalRequestId,
  ) => throw UnimplementedError();

  @override
  Future<Map<String, Object?>> verifyToken(
    String requestId,
    String tokenNo,
    Map<String, dynamic> params,
  ) => throw UnimplementedError();
}

Map<String, dynamic> _baseParams() => {
  'decoder_key_generation_algorithm': '02',
  'encryption_algorithm': 'sta',
  'key_type': 2,
  'supply_group_code': '123456',
  'tariff_index': '07',
  'key_revision_no': 1,
  'issuer_identification_no': '600727',
  'decoder_reference_number': '12345678901',
  'class': '0',
  'subclass': '0',
  'amount': 25.5,
  'token_id': '2024-06-01T12:00:00Z',
  'random_no': 7,
  'base_date': '1993',
};

Future<Map<String, dynamic>> _post(
  Handler handler,
  String path,
  Map<String, dynamic> body, {
  Map<String, String> headers = const {},
}) async {
  final req = Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: {'content-type': 'application/json', ...headers},
    body: jsonEncode(body),
  );
  final resp = await handler(req);
  final raw = await resp.readAsString();
  return {
    'status': resp.statusCode,
    'body': raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>,
  };
}

Future<Map<String, dynamic>> _get(Handler handler, String path) async {
  final req = Request('GET', Uri.parse('http://localhost$path'));
  final resp = await handler(req);
  final raw = await resp.readAsString();
  return {
    'status': resp.statusCode,
    'body': jsonDecode(raw) as Map<String, dynamic>,
  };
}

void main() {
  group('HTTP API (electricity-only MVP)', () {
    test('GET /healthz returns 200 ok', () async {
      final handler = buildApiHandler(_hsm());
      final r = await _get(handler, '/healthz');
      expect(r['status'], 200);
      expect((r['body'] as Map)['status'], 'ok');
    });

    test('GET /v1/health/backend returns 200 with VirtualHsmIssuer', () async {
      final handler = buildApiHandler(_hsm());
      final r = await _get(handler, '/v1/health/backend');
      expect(r['status'], 200);
      final body = r['body'] as Map<String, dynamic>;
      expect(body['ok'], isTrue);
      expect(body['backend'], isNotEmpty);
    });

    test(
      'GET /v1/health/backend returns 503 when issuer is unhealthy',
      () async {
        final handler = buildApiHandler(_UnhealthyIssuer());
        final r = await _get(handler, '/v1/health/backend');
        expect(r['status'], 503);
        final body = r['body'] as Map<String, dynamic>;
        expect(body['ok'], isFalse);
        expect(body['error'], contains('boom'));
      },
    );

    test(
      'GET /v1/status/nodes returns 200 with synthetic VirtualHsm entry',
      () async {
        final handler = buildApiHandler(_hsm());
        final r = await _get(handler, '/v1/status/nodes');
        expect(r['status'], 200);
        final body = r['body'] as Map<String, dynamic>;
        final nodes = body['nodes'] as List;
        expect(nodes, hasLength(1));
        final n0 = nodes.first as Map<String, dynamic>;
        expect((n0['info'] as Map)['backend'], isNotEmpty);
        expect(n0['alerts'], isEmpty);
      },
    );

    test(
      'GET /v1/status/nodes returns 503 when issuer.getNodeStatus throws',
      () async {
        final handler = buildApiHandler(_UnhealthyIssuer());
        final r = await _get(handler, '/v1/status/nodes');
        expect(r['status'], 503);
        final body = r['body'] as Map<String, dynamic>;
        expect(body['nodes'], isEmpty);
        expect(body['error'], contains('backend offline'));
      },
    );

    test(
      'POST /v1/tokens/key-change -> 501 NotImplemented for VirtualHsm',
      () async {
        final handler = buildApiHandler(_hsm());
        final r = await _post(handler, '/v1/tokens/key-change', {
          ..._baseParams(),
          'new_supply_group_code': '234567',
          'new_key_revision_number': 2,
          'new_tariff_index': '07',
        });
        expect(r['status'], 501);
        final body = r['body'] as Map<String, dynamic>;
        expect(
          (body['status'] as Map)['message'],
          contains('Key Change Token'),
        );
      },
    );

    test(
      'POST /v1/tokens/mse/* -> 501 NotImplemented for VirtualHsm',
      () async {
        final handler = buildApiHandler(_hsm());
        for (final path in const [
          '/v1/tokens/mse/clear-credit',
          '/v1/tokens/mse/clear-tamper',
        ]) {
          final r = await _post(handler, path, _baseParams());
          expect(r['status'], 501, reason: '$path expected 501');
          expect(
            ((r['body'] as Map)['status'] as Map)['message'],
            contains('MSE token'),
          );
        }
      },
    );

    test(
      'POST /v1/tokens/mse/set-max-power -> 400 when maximum_power_limit missing',
      () async {
        final handler = buildApiHandler(_hsm());
        final r = await _post(
          handler,
          '/v1/tokens/mse/set-max-power',
          _baseParams(),
        );
        expect(r['status'], 400);
        expect(
          ((r['body'] as Map)['status'] as Map)['message'],
          contains('maximum_power_limit'),
        );
      },
    );

    test(
      'POST /v1/tokens/mse/set-flag -> 400 when flag_type/flag_value missing',
      () async {
        final handler = buildApiHandler(_hsm());
        final r = await _post(
          handler,
          '/v1/tokens/mse/set-flag',
          _baseParams(),
        );
        expect(r['status'], 400);
        expect(
          ((r['body'] as Map)['status'] as Map)['message'],
          anyOf(contains('flag_type'), contains('flag_value')),
        );
      },
    );

    test(
      'POST /v1/tokens/meter-test -> 501 NotImplemented for VirtualHsm',
      () async {
        final handler = buildApiHandler(_hsm());
        final r = await _post(handler, '/v1/tokens/meter-test', {
          'subclass': 1,
          'control': 3,
          'manufacturer_code': 7,
        });
        expect(r['status'], 501);
        expect(
          ((r['body'] as Map)['status'] as Map)['message'],
          contains('NMSE meter-test'),
        );
      },
    );

    test('POST /v1/tokens/meter-test -> 400 when control missing', () async {
      final handler = buildApiHandler(_hsm());
      final r = await _post(handler, '/v1/tokens/meter-test', {
        'subclass': 1,
        'manufacturer_code': 7,
      });
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'],
        contains('control'),
      );
    });

    test(
      'POST /v1/tokens/credit/*-currency -> 501 NotImplemented for VirtualHsm',
      () async {
        final handler = buildApiHandler(_hsm());
        for (final path in const [
          '/v1/tokens/credit/electricity-currency',
          '/v1/tokens/credit/water-currency',
          '/v1/tokens/credit/gas-currency',
          '/v1/tokens/credit/time-currency',
        ]) {
          final r = await _post(handler, path, {
            ..._baseParams(),
            'amount': 50.0,
          });
          expect(r['status'], 501, reason: '$path expected 501');
          expect(
            ((r['body'] as Map)['status'] as Map)['message'],
            contains('currency-credit'),
          );
        }
      },
    );

    test(
      'GET /v1/tokens/results/<id> -> 501 NotImplemented for VirtualHsm',
      () async {
        final handler = buildApiHandler(_hsm());
        final r = await _get(handler, '/v1/tokens/results/req-original-123');
        expect(r['status'], 501);
        expect(
          ((r['body'] as Map)['status'] as Map)['message'],
          contains('token-result replay'),
        );
      },
    );

    test(
      'POST /v1/tokens/<tokenNo>/verify -> Valid round-trip for VirtualHsm',
      () async {
        final handler = buildApiHandler(_hsm());
        final params = _baseParams();

        final gen = await _post(handler, '/v1/tokens', params);
        expect(gen['status'], 200, reason: 'generate failed: ${gen['body']}');
        final tokenNo =
            (((gen['body'] as Map)['data'] as Map)['token'] as List).first
                as Map;
        final tn = tokenNo['token_no'] as String;

        final r = await _post(handler, '/v1/tokens/$tn/verify', params);
        expect(r['status'], 200, reason: 'verify failed: ${r['body']}');
        final data = (r['body'] as Map)['data'] as Map;
        expect(data['tokenNo'], tn);
        expect(data['validationResult'], 'Valid');
        expect(data['isValid'], true);
        final tok = data['token'] as Map;
        expect(tok['tokenNo'], tn);
        expect(tok['subclass'], 0);
        expect(tok['description'], 'Electricity_00');
        expect(tok['scaledAmount'], isNotEmpty);
      },
    );

    test(
      'POST /v1/tokens/<tokenNo>/verify -> Invalid (CRC) for tampered token',
      () async {
        final handler = buildApiHandler(_hsm());
        final params = _baseParams();

        final gen = await _post(handler, '/v1/tokens', params);
        expect(gen['status'], 200);
        final tn =
            ((((gen['body'] as Map)['data'] as Map)['token'] as List).first
                    as Map)['token_no']
                as String;
        // Twiddle a single digit so the CRC fails.
        final tampered = tn.substring(0, 19) + (tn[19] == '0' ? '1' : '0');

        final r = await _post(handler, '/v1/tokens/$tampered/verify', params);
        expect(r['status'], 200, reason: 'verify failed: ${r['body']}');
        final data = (r['body'] as Map)['data'] as Map;
        expect(data['tokenNo'], tampered);
        expect(data['isValid'], false);
        expect(data['validationResult'], isA<String>());
        expect(data['validationResult'], isNot('Valid'));
        expect(data['reason'], isA<String>());
        expect(data.containsKey('token'), isFalse);
      },
    );

    test('POST /v1/tokens -> POST /v1/tokens/{tokenNo} round-trips', () async {
      final handler = buildApiHandler(_hsm());
      final params = _baseParams();

      final gen = await _post(handler, '/v1/tokens', params);
      expect(gen['status'], 200, reason: 'generate failed: ${gen['body']}');
      final genData = (gen['body'] as Map)['data'] as Map;
      final tokenList = genData['token'] as List;
      final tokenNo = (tokenList.first as Map)['token_no'] as String;
      expect(tokenNo, hasLength(20));

      final dec = await _post(handler, '/v1/tokens/$tokenNo', params);
      expect(dec['status'], 200, reason: 'decode failed: ${dec['body']}');
      final decData = (dec['body'] as Map)['data'] as Map;
      final details = decData['token_details'] as Map;
      expect(details['amount'], closeTo(25.5, 1e-9));
      expect(details['random_no'], 7);
      expect(details['type'], 'Electricity_00');
    });

    test('POST /v1/tokens with bad JSON -> 400', () async {
      final handler = buildApiHandler(_hsm());
      final req = Request(
        'POST',
        Uri.parse('http://localhost/v1/tokens'),
        headers: {'content-type': 'application/json'},
        body: '{not json',
      );
      final resp = await handler(req);
      expect(resp.statusCode, 400);
    });

    test('out-of-scope class (gas) -> 501 NotImplemented', () async {
      final handler = buildApiHandler(_hsm());
      final params = _baseParams()
        ..['subclass'] = '2'
        ..['amount'] = 10.0;
      final r = await _post(handler, '/v1/tokens', params);
      expect(r['status'], 501);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('not ported'),
      );
    });

    test('bearer-token auth rejects requests without the header', () async {
      final handler = buildApiHandler(_hsm(), bearerToken: 's3cret');
      final r = await _post(handler, '/v1/tokens', _baseParams());
      expect(r['status'], 401);
    });

    test('bearer-token auth accepts the right token', () async {
      final handler = buildApiHandler(_hsm(), bearerToken: 's3cret');
      final r = await _post(
        handler,
        '/v1/tokens',
        _baseParams(),
        headers: {'authorization': 'Bearer s3cret'},
      );
      expect(r['status'], 200);
    });

    test('bearer-token auth still allows /healthz', () async {
      final handler = buildApiHandler(_hsm(), bearerToken: 's3cret');
      final r = await _get(handler, '/healthz');
      expect(r['status'], 200);
    });
  });

  group('vending log + tightening', () {
    test('every successful generate appends one record to the log', () async {
      final log = VendingLog();
      final handler = buildApiHandler(_hsm(), log: log);

      final r = await _post(handler, '/v1/tokens', _baseParams());
      expect(r['status'], 200);
      expect(log.length, 1);
      final rec = log.issues.single;
      expect(rec.tokenNo, hasLength(20));
      expect(rec.iin, '600727');
      expect(rec.amountKwh, closeTo(25.5, 1e-9));
      expect(rec.tidMinutes, isNotNull);
    });

    test(
      'same meter + same token_id is rejected with 409 TID collision',
      () async {
        final log = VendingLog();
        final handler = buildApiHandler(_hsm(), log: log);
        final params = _baseParams();

        final first = await _post(handler, '/v1/tokens', params);
        expect(first['status'], 200);

        final second = await _post(handler, '/v1/tokens', params);
        expect(second['status'], 409);
        final msg = ((second['body'] as Map)['status'] as Map)['message'];
        expect(msg.toString(), contains('TID collision'));
        // Log should still contain only the first record.
        expect(log.length, 1);
      },
    );

    test('different meter (same TID) does NOT collide', () async {
      final log = VendingLog();
      final handler = buildApiHandler(_hsm(), log: log);
      final p1 = _baseParams();
      final p2 = _baseParams()..['decoder_reference_number'] = '99999999999';

      expect((await _post(handler, '/v1/tokens', p1))['status'], 200);
      expect((await _post(handler, '/v1/tokens', p2))['status'], 200);
      expect(log.length, 2);
    });

    test('GET /v1/tokens lists every issue, filterable by ?iain', () async {
      final log = VendingLog();
      final handler = buildApiHandler(_hsm(), log: log);
      final p1 = _baseParams();
      final p2 = _baseParams()
        ..['decoder_reference_number'] = '99999999999'
        ..['token_id'] = '2024-06-01T13:00:00Z';
      await _post(handler, '/v1/tokens', p1);
      await _post(handler, '/v1/tokens', p2);

      final all = await _get(handler, '/v1/tokens');
      expect(all['status'], 200);
      expect(((all['body'] as Map)['data'] as Map)['count'], 2);

      final filtered = await _get(handler, '/v1/tokens?iain=12345678901');
      expect(((filtered['body'] as Map)['data'] as Map)['count'], 1);
    });

    test('GET /v1/tokens/{tokenNo} looks up an issued token', () async {
      final log = VendingLog();
      final handler = buildApiHandler(_hsm(), log: log);
      final gen = await _post(handler, '/v1/tokens', _baseParams());
      final tokenNo =
          (((gen['body'] as Map)['data'] as Map)['token'] as List)
                  .first['token_no']
              as String;

      final hit = await _get(handler, '/v1/tokens/$tokenNo');
      expect(hit['status'], 200);
      final rec = ((hit['body'] as Map)['data'] as Map)['issued_token'] as Map;
      expect(rec['token_no'], tokenNo);

      final miss = await _get(handler, '/v1/tokens/12345678901234567890');
      expect(miss['status'], 404);
    });

    test('GET /v1/tokens returns 503 when no log is configured', () async {
      final handler = buildApiHandler(_hsm()); // log: null
      final r = await _get(handler, '/v1/tokens');
      expect(r['status'], 503);
    });

    test('vending_key in request body is rejected as 400', () async {
      final handler = buildApiHandler(_hsm());
      final params = _baseParams()..['vending_key'] = '0011223344556677';
      final r = await _post(handler, '/v1/tokens', params);
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('vending_key'),
      );
    });

    test('amount <= 0 is rejected as 400', () async {
      final handler = buildApiHandler(_hsm());
      final zero = _baseParams()..['amount'] = 0;
      final neg = _baseParams()..['amount'] = -5;
      expect((await _post(handler, '/v1/tokens', zero))['status'], 400);
      expect((await _post(handler, '/v1/tokens', neg))['status'], 400);
    });

    test('log persists across a fresh load (simulated restart)', () async {
      final dir = await Directory.systemTemp.createTemp('vlog');
      try {
        final path = '${dir.path}\\v.json';
        final log1 = VendingLog(filePath: path);
        final h1 = buildApiHandler(_hsm(), log: log1);
        await _post(h1, '/v1/tokens', _baseParams());
        expect(log1.length, 1);
        expect(File(path).existsSync(), isTrue);

        // Simulate a server restart by re-loading from disk.
        final log2 = VendingLog.loadOrCreate(path);
        expect(log2.length, 1);
        expect(log2.issues.single.tokenNo, equals(log1.issues.single.tokenNo));

        // The replay protection now spans restarts.
        final h2 = buildApiHandler(_hsm(), log: log2);
        final replay = await _post(h2, '/v1/tokens', _baseParams());
        expect(replay['status'], 409);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('meter registry', () {
    Map<String, dynamic> _registerBody() => {
      'serial': 'METER-001',
      'subscriber_label': 'Acme Bakery',
      'encryption_algorithm': 'sta',
      'identity': {
        'issuer_identification_no': '600727',
        'decoder_reference_number': '12345678901',
        'key_type': 2,
        'supply_group_code': '123456',
        'tariff_index': '07',
        'key_revision_no': 1,
        'decoder_key_generation_algorithm': '02',
      },
    };

    test('POST /v1/meters registers and GET /v1/meters lists it', () async {
      final reg = MeterRegistry();
      final handler = buildApiHandler(_hsm(), registry: reg);

      final create = await _post(handler, '/v1/meters', _registerBody());
      expect(create['status'], 201, reason: '${create['body']}');
      expect(reg.length, 1);

      final list = await _get(handler, '/v1/meters');
      expect(list['status'], 200);
      expect(((list['body'] as Map)['data'] as Map)['count'], 1);

      final one = await _get(handler, '/v1/meters/METER-001');
      expect(one['status'], 200);
      final meter = ((one['body'] as Map)['data'] as Map)['meter'] as Map;
      expect(meter['serial'], 'METER-001');
      expect(meter['subscriber_label'], 'Acme Bakery');
    });

    test('duplicate serial -> 409', () async {
      final handler = buildApiHandler(_hsm(), registry: MeterRegistry());
      expect(
        (await _post(handler, '/v1/meters', _registerBody()))['status'],
        201,
      );
      expect(
        (await _post(handler, '/v1/meters', _registerBody()))['status'],
        409,
      );
    });

    test('DELETE /v1/meters/{serial} removes the entry', () async {
      final reg = MeterRegistry();
      final handler = buildApiHandler(_hsm(), registry: reg);
      await _post(handler, '/v1/meters', _registerBody());
      expect(reg.length, 1);

      final req = Request(
        'DELETE',
        Uri.parse('http://localhost/v1/meters/METER-001'),
      );
      final resp = await handler(req);
      expect(resp.statusCode, 200);
      expect(reg.length, 0);

      final miss = await _get(handler, '/v1/meters/METER-001');
      expect(miss['status'], 404);
    });

    test(
      'POST /v1/tokens with meter_serial vends using registered identity',
      () async {
        final reg = MeterRegistry();
        final log = VendingLog();
        final handler = buildApiHandler(_hsm(), registry: reg, log: log);
        await _post(handler, '/v1/meters', _registerBody());

        final body = {
          'meter_serial': 'METER-001',
          'class': '0',
          'subclass': '0',
          'amount': 10.0,
          'token_id': '2024-07-01T09:00:00Z',
          'random_no': 3,
          'base_date': '1993',
        };
        final r = await _post(handler, '/v1/tokens', body);
        expect(r['status'], 200, reason: '${r['body']}');
        final data = (r['body'] as Map)['data'] as Map;
        expect(data['meter_serial'], 'METER-001');
        final tokenNo = (data['token'] as List).first['token_no'] as String;
        expect(tokenNo, hasLength(20));

        // Audit row links back to the serial.
        expect(log.issues.single.meterSerial, 'METER-001');
        expect(log.issues.single.iain, '12345678901');
      },
    );

    test('meter_serial + inline identity field -> 400', () async {
      final reg = MeterRegistry();
      final handler = buildApiHandler(_hsm(), registry: reg);
      await _post(handler, '/v1/meters', _registerBody());

      final body = {
        'meter_serial': 'METER-001',
        'decoder_reference_number': '99999999999', // conflict
        'class': '0',
        'subclass': '0',
        'amount': 5.0,
        'token_id': '2024-07-01T10:00:00Z',
      };
      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('cannot be combined'),
      );
    });

    test('unknown meter_serial -> 404', () async {
      final handler = buildApiHandler(_hsm(), registry: MeterRegistry());
      final r = await _post(handler, '/v1/tokens', {
        'meter_serial': 'NOPE',
        'class': '0',
        'subclass': '0',
        'amount': 5.0,
        'token_id': '2024-07-01T10:00:00Z',
      });
      expect(r['status'], 404);
    });

    test('meter_serial with no registry configured -> 400', () async {
      final handler = buildApiHandler(_hsm()); // no registry
      final r = await _post(handler, '/v1/tokens', {
        'meter_serial': 'METER-001',
        'class': '0',
        'subclass': '0',
        'amount': 5.0,
      });
      expect(r['status'], 400);
    });

    test('registry endpoints return 503 when registry is disabled', () async {
      final handler = buildApiHandler(_hsm()); // no registry
      final list = await _get(handler, '/v1/meters');
      expect(list['status'], 503);
      final create = await _post(handler, '/v1/meters', _registerBody());
      expect(create['status'], 503);
    });

    test('registry persists across a fresh load (simulated restart)', () async {
      final dir = await Directory.systemTemp.createTemp('mreg');
      try {
        final path = '${dir.path}\\m.json';
        final reg1 = MeterRegistry(filePath: path);
        final h1 = buildApiHandler(_hsm(), registry: reg1);
        await _post(h1, '/v1/meters', _registerBody());
        expect(File(path).existsSync(), isTrue);

        final reg2 = MeterRegistry.loadOrCreate(path);
        expect(reg2.length, 1);
        expect(reg2.find('METER-001'), isNotNull);

        // The vending shortcut still works against the reloaded registry.
        final h2 = buildApiHandler(_hsm(), registry: reg2);
        final r = await _post(h2, '/v1/tokens', {
          'meter_serial': 'METER-001',
          'class': '0',
          'subclass': '0',
          'amount': 7.5,
          'token_id': '2024-07-02T11:00:00Z',
          'base_date': '1993',
        });
        expect(r['status'], 200);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('tariff / pricing', () {
    TariffBook _book() => TariffBook(
      byTariffIndex: {
        '07': const Tariff(currency: 'KES', pricePerKwh: 24.0),
        '01': const Tariff(currency: 'IDR', pricePerKwh: 1444, adminFee: 2500),
      },
    );

    test(
      'amount_money is converted to kWh and reported in pricing block',
      () async {
        final log = VendingLog();
        final handler = buildApiHandler(_hsm(), log: log, tariffs: _book());
        final body = _baseParams()
          ..remove('amount')
          ..['amount_money'] = 240.0; // KES at 24/kWh → 10 kWh

        final r = await _post(handler, '/v1/tokens', body);
        expect(r['status'], 200, reason: '${r['body']}');
        final data = (r['body'] as Map)['data'] as Map;
        final pricing = data['pricing'] as Map;
        expect(pricing['currency'], 'KES');
        expect(pricing['kwh'], closeTo(10.0, 1e-9));
        expect(pricing['amount_money'], closeTo(240.0, 1e-9));
        expect(pricing['total_money'], closeTo(240.0, 1e-9));

        // Persisted record carries currency + cash total.
        expect(log.issues.single.currency, 'KES');
        expect(log.issues.single.amountMoney, closeTo(240.0, 1e-9));
        expect(log.issues.single.amountKwh, closeTo(10.0, 1e-9));
      },
    );

    test(
      'plain amount request with a tariff surfaces money in response',
      () async {
        final handler = buildApiHandler(_hsm(), tariffs: _book());
        final r = await _post(handler, '/v1/tokens', _baseParams());
        expect(r['status'], 200);
        final pricing = ((r['body'] as Map)['data'] as Map)['pricing'] as Map;
        expect(pricing['currency'], 'KES');
        expect(pricing['kwh'], closeTo(25.5, 1e-9));
        expect(pricing['amount_money'], closeTo(25.5 * 24.0, 1e-9));
      },
    );

    test('per-index tariff with admin fee is respected', () async {
      final handler = buildApiHandler(_hsm(), tariffs: _book());
      final body = _baseParams()
        ..['tariff_index'] = '01'
        ..remove('amount')
        ..['amount_money'] = 20000.0; // IDR

      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 200, reason: '${r['body']}');
      final pricing = ((r['body'] as Map)['data'] as Map)['pricing'] as Map;
      expect(pricing['currency'], 'IDR');
      expect(pricing['admin_fee'], 2500);
      expect(pricing['kwh'], closeTo((20000 - 2500) / 1444, 1e-9));
      expect(pricing['total_money'], closeTo(20000.0, 1e-9));
    });

    test('both amount and amount_money -> 400', () async {
      final handler = buildApiHandler(_hsm(), tariffs: _book());
      final body = _baseParams()..['amount_money'] = 100.0;
      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('not both'),
      );
    });

    test('amount_money without a server-side tariff -> 400', () async {
      final handler = buildApiHandler(_hsm()); // no tariffs
      final body = _baseParams()
        ..remove('amount')
        ..['amount_money'] = 100.0;
      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('requires a configured tariff'),
      );
    });

    test('currency mismatch between request and tariff -> 400', () async {
      final handler = buildApiHandler(_hsm(), tariffs: _book());
      final body = _baseParams()
        ..remove('amount')
        ..['amount_money'] = 100.0
        ..['currency'] = 'USD';
      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('currency mismatch'),
      );
    });

    test('amount_money that only covers the admin fee -> 400', () async {
      final handler = buildApiHandler(_hsm(), tariffs: _book());
      final body = _baseParams()
        ..['tariff_index'] = '01'
        ..remove('amount')
        ..['amount_money'] = 2500.0; // exactly the IDR admin fee
      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('no kWh purchased'),
      );
    });
  });

  group('caller-supplied request id', () {
    test('X-Request-Id header is echoed back in envelope', () async {
      final handler = buildApiHandler(_hsm());
      final r = await _post(
        handler,
        '/v1/tokens',
        _baseParams(),
        headers: {'X-Request-Id': 'caller-abc-123'},
      );
      expect(r['status'], 200, reason: '${r['body']}');
      expect((r['body'] as Map)['request_id'], 'caller-abc-123');
    });

    test('body.request_id is honored when no header is set', () async {
      final handler = buildApiHandler(_hsm());
      final body = _baseParams()..['request_id'] = 'caller-body-xyz';
      final r = await _post(handler, '/v1/tokens', body);
      expect(r['status'], 200, reason: '${r['body']}');
      expect((r['body'] as Map)['request_id'], 'caller-body-xyz');
    });

    test('header takes precedence over body.request_id', () async {
      final handler = buildApiHandler(_hsm());
      final body = _baseParams()..['request_id'] = 'body-loses';
      final r = await _post(
        handler,
        '/v1/tokens',
        body,
        headers: {'X-Request-Id': 'header-wins'},
      );
      expect(r['status'], 200, reason: '${r['body']}');
      expect((r['body'] as Map)['request_id'], 'header-wins');
    });

    test('invalid X-Request-Id (illegal char) -> 400', () async {
      final handler = buildApiHandler(_hsm());
      final r = await _post(
        handler,
        '/v1/tokens',
        _baseParams(),
        headers: {'X-Request-Id': 'has spaces'},
      );
      expect(r['status'], 400);
      expect(
        ((r['body'] as Map)['status'] as Map)['message'].toString(),
        contains('X-Request-Id'),
      );
    });

    test('omitted request id -> server-generated value is returned', () async {
      final handler = buildApiHandler(_hsm());
      final r = await _post(handler, '/v1/tokens', _baseParams());
      expect(r['status'], 200);
      final id = (r['body'] as Map)['request_id'] as String;
      expect(id, startsWith('req-'));
      expect(id.length, greaterThan(4));
    });
  });
}
