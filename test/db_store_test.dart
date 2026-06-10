/// End-to-end integration tests for the MySQL-backed stores.
///
/// These run only when the dart server is configured against a real
/// MySQL instance (env var `STS_DB_HOST` is set). When the env var
/// is missing the entire group is skipped — `dart test` stays
/// green on machines without WAMP / the Laravel dashboard.
///
/// Local setup (Windows + WAMP + the `sts-vending` Laravel app):
///
///   $env:STS_DB_HOST     = '127.0.0.1'
///   $env:STS_DB_DATABASE = 'sts_vending'
///   $env:STS_DB_USERNAME = 'root'
///   $env:STS_DB_PASSWORD = ''
///   dart test test/db_store_test.dart
///
/// The tests own one throwaway `supply_groups` row (`code=987654`)
/// and one matching `vending_keys` row. Both are inserted in
/// `setUpAll` and deleted in `tearDownAll` (cascade also deletes
/// any leftover meters + tokens), so the Laravel admin data
/// (the seeded `123456` supply group, etc.) is never touched.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:eloquent/eloquent.dart';
import 'package:nectar_sts_dart/nectar_sts_dart.dart';
import 'package:nectar_sts_dart/src/server/api_server.dart';
import 'package:nectar_sts_dart/src/server/database.dart';
import 'package:nectar_sts_dart/src/server/db_meter_registry.dart';
import 'package:nectar_sts_dart/src/server/db_queries.dart';
import 'package:nectar_sts_dart/src/server/db_vending_log.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _testSgc = '987654';
const _testIin = '600727';
const _testIain = '12345678901';
const _testSerial = 'DBTST01'; // <= 8 chars, fits meters.decoder_serial_number
const _testSerial2 = 'DBTST02';

String _now() => DateTime.now()
    .toUtc()
    .toIso8601String()
    .split('.')
    .first
    .replaceFirst('T', ' ');

Future<int> _seedSupplyGroup(Connection db) async {
  final id = await db.table('supply_groups').insertGetId({
    'code': _testSgc,
    'name': 'DB Integration Test Supply Group',
    'utility': 'TEST-UTIL',
    'region': 'TEST-REGION',
    'is_active': 1,
    'created_at': _now(),
    'updated_at': _now(),
  });
  return id is int ? id : (id as num).toInt();
}

Future<int> _seedVendingKey(Connection db, int sgId) async {
  final id = await db.table('vending_keys').insertGetId({
    'name': 'DB Integration Test VUDK',
    'supply_group_id': sgId,
    'key_type': 2,
    'tariff_index': '07',
    'key_revision_number': 1,
    'key_expiry_number': 255,
    'algorithm': 'DKGA02',
    'encryption_algorithm': 'EA07',
    'base_date': 1993,
    // The Dart server never reads vudk_blob — but the column is
    // NOT NULL. 8 zero bytes is a valid filler for DKGA02.
    'vudk_blob': Uint8List.fromList(List<int>.filled(8, 0)),
    'is_active': 1,
    'created_at': _now(),
    'updated_at': _now(),
  });
  return id is int ? id : (id as num).toInt();
}

/// Cascade order: tokens → meters → vending_keys → supply_groups.
/// We rely on the Laravel FK `onDelete('cascade')`s, but we also
/// scrub by IIN/IAIN as a safety net in case rows leaked from a
/// previously-aborted run.
Future<void> _cleanup(Connection db) async {
  // Delete any test meters left behind (cascades to tokens).
  await db
      .table('meters')
      .where('iin', '=', _testIin)
      .where('iain', '=', _testIain)
      .delete();
  // Then drop the supply_group; this cascades to any vending_keys
  // we created against it.
  await db.table('supply_groups').where('code', '=', _testSgc).delete();
}

/// Link `meters.vending_key_id` after registration — mirrors what
/// the Laravel admin does in the dashboard UI before the Dart
/// server is allowed to vend tokens against this meter.
Future<void> _linkVendingKey(
  Connection db, {
  required String serial,
  required int vendingKeyId,
}) async {
  await db.table('meters').where('decoder_serial_number', '=', serial).update({
    'vending_key_id': vendingKeyId,
    'updated_at': _now(),
  });
}

VirtualHsm _hsm() => VirtualHsm(
  VendingCommonDesKey([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]),
);

RegisteredMeter _testMeter({
  String serial = _testSerial,
  String iain = _testIain,
}) => RegisteredMeter(
  serial: serial,
  identity: MeterIdentity(
    issuerIdentificationNumber: _testIin,
    individualAccountIdentificationNumber: iain,
    keyType: 2,
    supplyGroupCode: _testSgc,
    tariffIndex: '07',
    keyRevisionNumber: 1,
  ),
  subscriberLabel: 'DB Integration Test',
  registeredAt: DateTime.now().toUtc(),
);

Future<Map<String, dynamic>> _post(
  Handler handler,
  String path,
  Map<String, dynamic> body,
) async {
  final req = Request(
    'POST',
    Uri.parse('http://localhost$path'),
    headers: {'content-type': 'application/json'},
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
    'body': raw.isEmpty ? null : jsonDecode(raw) as Map<String, dynamic>,
  };
}

void main() {
  final dbConfigured = Database.isConfigured;
  final skipReason = dbConfigured
      ? null
      : 'STS_DB_HOST is not set — skipping DB-backed integration tests. '
            'See test/db_store_test.dart for the env vars to set.';

  group('DB-backed stores (MySQL `sts_vending`)', () {
    late Connection db;
    late int sgId;
    late int vkId;

    setUpAll(() async {
      db = await Database.connection();
      // Defensive scrub in case a previous run left residue.
      await _cleanup(db);
      sgId = await _seedSupplyGroup(db);
      vkId = await _seedVendingKey(db, sgId);
    });

    tearDownAll(() async {
      try {
        await _cleanup(db);
      } finally {
        await Database.close();
      }
    });

    // ---- DbMeterRegistry ----------------------------------------

    test('DbMeterRegistry add + lookup + list + delete round-trip', () async {
      final reg = DbMeterRegistry();
      await reg.refreshCount();
      final before = reg.length;

      await reg.add(_testMeter());

      final hit = await reg.lookup(_testSerial);
      expect(hit, isNotNull);
      expect(hit!.serial, _testSerial);
      expect(hit.identity.issuerIdentificationNumber, _testIin);
      expect(hit.identity.individualAccountIdentificationNumber, _testIain);
      expect(hit.identity.supplyGroupCode, _testSgc);

      final all = await reg.list();
      expect(
        all.where((m) => m.serial == _testSerial).length,
        1,
        reason: 'Registered meter should appear in list()',
      );

      expect(await reg.total(), greaterThan(before));

      final deleted = await reg.delete(_testSerial);
      expect(deleted, isTrue);
      expect(await reg.lookup(_testSerial), isNull);
    });

    test('add throws DuplicateMeterSerialException on serial clash', () async {
      final reg = DbMeterRegistry();
      await reg.add(_testMeter());
      try {
        expect(
          () async => reg.add(_testMeter()),
          throwsA(isA<DuplicateMeterSerialException>()),
        );
      } finally {
        await reg.delete(_testSerial);
      }
    });

    test('add throws MissingForeignRowException for an unknown SGC', () async {
      final reg = DbMeterRegistry();
      final bogus = RegisteredMeter(
        serial: 'DBTST09',
        identity: const MeterIdentity(
          issuerIdentificationNumber: _testIin,
          individualAccountIdentificationNumber: _testIain,
          keyType: 2,
          supplyGroupCode: '000001', // not seeded
          tariffIndex: '07',
          keyRevisionNumber: 1,
        ),
        registeredAt: DateTime.now().toUtc(),
      );
      expect(
        () async => reg.add(bogus),
        throwsA(isA<MissingForeignRowException>()),
      );
    });

    // ---- DbVendingLog -------------------------------------------

    test('record without a vending_key_id link throws '
        'DbVendingLogPersistenceException', () async {
      final reg = DbMeterRegistry();
      final log = DbVendingLog();
      await reg.add(_testMeter());
      try {
        final record = IssuedTokenRecord(
          requestId: 'req-test-unlinked',
          tokenNo: '12345678901234567890',
          issuedAt: DateTime.now().toUtc(),
          iin: _testIin,
          iain: _testIain,
          keyType: 2,
          supplyGroupCode: _testSgc,
          tariffIndex: '07',
          keyRevisionNumber: 1,
          decoderKeyGenerationAlgorithm: '02',
          tokenClass: 0,
          tokenSubclass: 0,
          amountKwh: 5.0,
          tidMinutes: 1000,
          randomNo: 1,
        );
        expect(
          () async => log.record(record),
          throwsA(isA<DbVendingLogPersistenceException>()),
        );
      } finally {
        await reg.delete(_testSerial);
      }
    });

    test(
      'record + lookupToken + forMeter round-trip with linked vending key',
      () async {
        final reg = DbMeterRegistry();
        final log = DbVendingLog();
        await reg.add(_testMeter());
        await _linkVendingKey(db, serial: _testSerial, vendingKeyId: vkId);

        try {
          final issuedAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
          final record = IssuedTokenRecord(
            requestId: 'req-test-roundtrip',
            tokenNo: '11111111112222222222',
            issuedAt: issuedAt,
            iin: _testIin,
            iain: _testIain,
            keyType: 2,
            supplyGroupCode: _testSgc,
            tariffIndex: '07',
            keyRevisionNumber: 1,
            decoderKeyGenerationAlgorithm: '02',
            tokenClass: 0,
            tokenSubclass: 0,
            amountKwh: 12.5,
            tidMinutes: 1234567,
            randomNo: 9,
            meterSerial: _testSerial,
          );

          await log.record(record);

          final hit = await log.lookupToken('11111111112222222222');
          expect(hit, isNotNull);
          expect(hit!.tokenNo, '11111111112222222222');
          expect(hit.amountKwh, closeTo(12.5, 1e-9));
          expect(hit.tidMinutes, 1234567);
          expect(hit.randomNo, 9);
          expect(hit.meterSerial, _testSerial);
          expect(hit.iin, _testIin);
          expect(hit.iain, _testIain);

          final byMeter = await log.forMeter(iin: _testIin, iain: _testIain);
          expect(
            byMeter.where((r) => r.tokenNo == '11111111112222222222').length,
            1,
          );
        } finally {
          await reg.delete(_testSerial);
        }
      },
    );

    test(
      'tidExists + findCollision detect a same-meter same-TID replay',
      () async {
        final reg = DbMeterRegistry();
        final log = DbVendingLog();
        await reg.add(_testMeter());
        await _linkVendingKey(db, serial: _testSerial, vendingKeyId: vkId);

        try {
          const fp = '$_testIin|$_testIain|2|$_testSgc|07|1|02';
          const tid = 2345678;

          // Pre-state: no collision.
          expect(
            await log.tidExists(identityFingerprint: fp, tidMinutes: tid),
            isFalse,
          );

          await log.record(
            IssuedTokenRecord(
              requestId: 'req-test-collision-1',
              tokenNo: '33333333334444444444',
              issuedAt: DateTime.now().toUtc(),
              iin: _testIin,
              iain: _testIain,
              keyType: 2,
              supplyGroupCode: _testSgc,
              tariffIndex: '07',
              keyRevisionNumber: 1,
              decoderKeyGenerationAlgorithm: '02',
              tokenClass: 0,
              tokenSubclass: 0,
              amountKwh: 7.0,
              tidMinutes: tid,
              randomNo: 2,
              meterSerial: _testSerial,
            ),
          );

          expect(
            await log.tidExists(identityFingerprint: fp, tidMinutes: tid),
            isTrue,
          );

          final prior = await log.findCollision(
            identityFingerprint: fp,
            tidMinutes: tid,
          );
          expect(prior, isNotNull);
          expect(prior!.tokenNo, '33333333334444444444');
          expect(prior.requestId, 'req-test-collision-1');
        } finally {
          await reg.delete(_testSerial);
        }
      },
    );

    // ---- End-to-end through buildApiHandler ---------------------

    test('HTTP: POST /v1/meters then POST /v1/tokens end-to-end via '
        'buildApiHandler', () async {
      final reg = DbMeterRegistry();
      final log = DbVendingLog();
      final handler = buildApiHandler(_hsm(), registry: reg, log: log);

      // 1. Register the meter through the HTTP surface.
      final create = await _post(handler, '/v1/meters', {
        'serial': _testSerial,
        'subscriber_label': 'DB Integration Test',
        'encryption_algorithm': 'sta',
        'identity': {
          'issuer_identification_no': _testIin,
          'decoder_reference_number': _testIain,
          'key_type': 2,
          'supply_group_code': _testSgc,
          'tariff_index': '07',
          'key_revision_no': 1,
          'decoder_key_generation_algorithm': '02',
        },
      });
      expect(
        create['status'],
        201,
        reason: 'register failed: ${create['body']}',
      );

      // 2. Simulate the Laravel admin linking a vending key.
      await _linkVendingKey(db, serial: _testSerial, vendingKeyId: vkId);

      try {
        // 3. Mint a token by serial (shortcut path).
        final gen = await _post(handler, '/v1/tokens', {
          'meter_serial': _testSerial,
          'class': '0',
          'subclass': '0',
          'amount': 15.0,
          'token_id': '2024-08-01T08:30:00Z',
          'random_no': 4,
        });
        expect(gen['status'], 200, reason: 'generate failed: ${gen['body']}');
        final genData = (gen['body'] as Map)['data'] as Map;
        final tokenNo =
            ((genData['token'] as List).first as Map)['token_no'] as String;
        expect(tokenNo, hasLength(20));
        expect(genData['meter_serial'], _testSerial);

        // 4. Look up via the audit endpoint.
        final hit = await _get(handler, '/v1/tokens/$tokenNo');
        expect(hit['status'], 200);
        final issued =
            ((hit['body'] as Map)['data'] as Map)['issued_token'] as Map;
        expect(issued['token_no'], tokenNo);
        expect(issued['iin'], _testIin);
        expect(issued['iain'], _testIain);
        expect(issued['amount_kwh'], closeTo(15.0, 1e-9));
        expect(issued['meter_serial'], _testSerial);

        // 5. Re-issuing the same (meter, token_id) collides.
        final replay = await _post(handler, '/v1/tokens', {
          'meter_serial': _testSerial,
          'class': '0',
          'subclass': '0',
          'amount': 15.0,
          'token_id': '2024-08-01T08:30:00Z',
        });
        expect(replay['status'], 409);
        expect(
          ((replay['body'] as Map)['status'] as Map)['message'].toString(),
          contains('TID collision'),
        );
      } finally {
        // Best-effort cleanup. _cleanup() in tearDownAll also
        // sweeps by IIN/IAIN, but doing it here keeps individual
        // failures from polluting later tests in the same run.
        await db
            .table('meters')
            .where('decoder_serial_number', '=', _testSerial)
            .delete();
      }
    });

    test('HTTP: POST /v1/meters with an unknown SGC -> 412', () async {
      final reg = DbMeterRegistry();
      final handler = buildApiHandler(_hsm(), registry: reg);

      final create = await _post(handler, '/v1/meters', {
        'serial': _testSerial2,
        'identity': {
          'issuer_identification_no': _testIin,
          'decoder_reference_number': _testIain,
          'key_type': 2,
          'supply_group_code': '000001',
          'tariff_index': '07',
          'key_revision_no': 1,
          'decoder_key_generation_algorithm': '02',
        },
      });
      expect(create['status'], 412, reason: '${create['body']}');
      final msg = ((create['body'] as Map)['status'] as Map)['message']
          .toString();
      expect(msg, contains('supply_groups'));
    });

    // ---- Sanity: shared connection lifecycle --------------------

    test('Database.connection() reuses the same pooled Connection', () async {
      final a = await Database.connection();
      final b = await Database.connection();
      expect(identical(a, b), isTrue);
    });
  }, skip: skipReason);

  if (!dbConfigured) {
    // Surface a single passing test so `dart test test/db_store_test.dart`
    // doesn't report "no tests ran" on machines without a DB.
    test('DB integration suite skipped (STS_DB_HOST not set)', () {
      stderr.writeln(
        '[db_store_test] STS_DB_HOST not set — DB integration suite '
        'skipped. See the file header for setup instructions.',
      );
    });
  }
}
