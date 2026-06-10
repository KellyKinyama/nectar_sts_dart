/// MySQL-backed replacement for [VendingLog].
///
/// Same conceptual surface — append on success, query for TID
/// collisions, look up by token number — but persisted into the
/// `tokens` table the Laravel `sts-vending` dashboard reads from.
///
/// Schema bridge:
///   - `tokens.amount_kwh`, `currency`, `issued_at`, `token_class`,
///     `token_sub_class`, `token_kind`, `payload` are first-class
///     columns the dashboard renders.
///   - `tid_minutes`, `random_no`, `identity_fingerprint`,
///     `request_id`, raw identity fields are NOT in the Laravel
///     schema. We stash them inside the `engine_response` JSON
///     column and query them via
///     `JSON_EXTRACT(engine_response, '\$.tid_minutes')` etc.
///
/// The Laravel migration declares `tokens.meter_id` and
/// `tokens.vending_key_id` as NOT NULL foreign keys — so [append]
/// REQUIRES that the meter exists in the registry and has been
/// linked to a vending key by the Laravel admin. If either lookup
/// fails [append] throws [DbVendingLogPersistenceException]; the
/// API server is expected to surface that as `409` / `412` to the
/// caller.
library;

import 'db_queries.dart';
import 'vending_log.dart' show IssuedTokenRecord, VendingLogStore;

class DbVendingLogPersistenceException implements Exception {
  final String message;
  DbVendingLogPersistenceException(this.message);
  @override
  String toString() => 'DbVendingLogPersistenceException: $message';
}

class DbVendingLog implements VendingLogStore {
  int _count = 0;

  /// Cached row-count, refreshed by [refreshCount] or after every
  /// successful [append].
  int get length => _count;

  Future<void> refreshCount() async {
    _count = await DbQueries.tokenCount();
  }

  /// Persist a freshly-issued token. Throws
  /// [DbVendingLogPersistenceException] if the meter row is
  /// missing or the meter has no `vending_key_id`.
  @override
  Future<void> record(IssuedTokenRecord r) async {
    final meter = await DbQueries.findMeterByIinIain(iin: r.iin, iain: r.iain);
    if (meter == null) {
      throw DbVendingLogPersistenceException(
        'No meter row for IIN=${r.iin} IAIN=${r.iain}. Register the '
        'meter via POST /v1/meters (or in the Laravel dashboard) '
        'before issuing tokens against it.',
      );
    }
    if (meter.vendingKeyId == null) {
      throw DbVendingLogPersistenceException(
        'Meter ${meter.decoderSerialNumber ?? '#${meter.id}'} has no '
        'vending_key_id. Link the meter to a vending key in the '
        'Laravel dashboard before issuing tokens.',
      );
    }
    await DbQueries.insertIssuedToken(
      requestId: r.requestId,
      tokenNo: r.tokenNo,
      meterId: meter.id,
      vendingKeyId: meter.vendingKeyId,
      tokenClass: r.tokenClass,
      tokenSubClass: r.tokenSubclass,
      tokenKind: _tokenKindFor(r),
      amountKwh: r.amountKwh,
      currency: r.currency,
      issuedAt: r.issuedAt,
      tidMinutes: r.tidMinutes,
      randomNo: r.randomNo,
      identityFingerprint: r.identityFingerprint,
      payload: _payloadJson(r),
      engineResponse: _engineResponseJson(r),
      status: 'issued',
    );
    _count++;
  }

  /// True when this exact `(identity, tid_minutes)` pair has
  /// already been minted — vending would produce a replay token.
  @override
  Future<bool> tidExists({
    required String identityFingerprint,
    required int? tidMinutes,
  }) async {
    if (tidMinutes == null) return false;
    final parts = identityFingerprint.split('|');
    if (parts.length < 2) return false;
    final meter = await DbQueries.findMeterByIinIain(
      iin: parts[0],
      iain: parts[1],
    );
    if (meter == null) return false;
    return DbQueries.hasTidCollision(meterId: meter.id, tidMinutes: tidMinutes);
  }

  /// Returns the colliding record (used to build rich error
  /// messages on TID-collision rejection).
  @override
  Future<IssuedTokenRecord?> findCollision({
    required String identityFingerprint,
    required int tidMinutes,
  }) async {
    final parts = identityFingerprint.split('|');
    if (parts.length < 2) return null;
    final meter = await DbQueries.findMeterByIinIain(
      iin: parts[0],
      iain: parts[1],
    );
    if (meter == null) return null;
    final rows = await DbQueries.findTokensByMeter(
      iin: parts[0],
      iain: parts[1],
      limit: 200,
    );
    for (final row in rows) {
      final eng = row.engineResponse;
      if (eng != null && (eng['tid_minutes'] as num?)?.toInt() == tidMinutes) {
        return _toRecord(row);
      }
    }
    return null;
  }

  /// Lookup by 20-digit token number.
  @override
  Future<IssuedTokenRecord?> lookupToken(String tokenNo) async {
    final row = await DbQueries.findTokenByNo(tokenNo);
    return row == null ? null : _toRecord(row);
  }

  /// All tokens belonging to a meter (filter by `iin` and/or
  /// `iain`). Most-recent first.
  @override
  Future<List<IssuedTokenRecord>> forMeter({
    String? iin,
    String? iain,
    int limit = 500,
  }) async {
    final rows = await DbQueries.findTokensByMeter(
      iin: iin,
      iain: iain,
      limit: limit,
    );
    return rows.map(_toRecord).toList();
  }

  @override
  Future<int> total() async {
    await refreshCount();
    return _count;
  }

  // ---- mapping --------------------------------------------------

  static String _tokenKindFor(IssuedTokenRecord r) {
    switch (r.tokenClass) {
      case 0:
        return 'credit';
      case 1:
        return 'management';
      case 2:
        return 'test';
      case 3:
        return 'reserved';
      default:
        return 'unknown';
    }
  }

  /// What the dashboard renders as the "request payload" column.
  static Map<String, dynamic> _payloadJson(IssuedTokenRecord r) => {
    'iin': r.iin,
    'iain': r.iain,
    'key_type': r.keyType,
    'supply_group_code': r.supplyGroupCode,
    'tariff_index': r.tariffIndex,
    'key_revision_no': r.keyRevisionNumber,
    'decoder_key_generation_algorithm': r.decoderKeyGenerationAlgorithm,
    'token_class': r.tokenClass,
    'token_subclass': r.tokenSubclass,
    if (r.amountKwh != null) 'amount_kwh': r.amountKwh,
    if (r.amountMoney != null) 'amount_money': r.amountMoney,
    if (r.currency != null) 'currency': r.currency,
    if (r.meterSerial != null) 'meter_serial': r.meterSerial,
  };

  static Map<String, dynamic> _engineResponseJson(IssuedTokenRecord r) => {
    'request_id': r.requestId,
    'identity_fingerprint': r.identityFingerprint,
    if (r.tidMinutes != null) 'tid_minutes': r.tidMinutes,
    if (r.randomNo != null) 'random_no': r.randomNo,
    if (r.meterSerial != null) 'meter_serial': r.meterSerial,
    'iin': r.iin,
    'iain': r.iain,
    'key_type': r.keyType,
    'supply_group_code': r.supplyGroupCode,
    'tariff_index': r.tariffIndex,
    'key_revision_number': r.keyRevisionNumber,
    'decoder_key_generation_algorithm': r.decoderKeyGenerationAlgorithm,
    'token_subclass': r.tokenSubclass,
  };

  static IssuedTokenRecord _toRecord(IssuedTokenRow row) {
    final eng = row.engineResponse ?? const <String, dynamic>{};
    // The Dart writer wraps the caller-supplied engine payload
    // inside an enrichment envelope:
    //   { tid_minutes, random_no, identity_fingerprint,
    //     raw: { iin, iain, key_type, ... meter_serial } }
    // So when we read back, the identity fields live under `raw`
    // while the audit triple stays at the top.
    final raw = (eng['raw'] is Map<String, dynamic>)
        ? eng['raw'] as Map<String, dynamic>
        : eng;
    int? asInt(Object? v) => v == null ? null : (v as num).toInt();
    return IssuedTokenRecord(
      requestId: (raw['request_id'] as String?) ?? row.requestId,
      tokenNo: row.tokenNo,
      issuedAt: row.issuedAt,
      iin: (raw['iin'] as String?) ?? '',
      iain: (raw['iain'] as String?) ?? '',
      keyType: asInt(raw['key_type']) ?? 2,
      supplyGroupCode: (raw['supply_group_code'] as String?) ?? '',
      tariffIndex: (raw['tariff_index'] as String?) ?? '01',
      keyRevisionNumber: asInt(raw['key_revision_number']) ?? 1,
      decoderKeyGenerationAlgorithm:
          (raw['decoder_key_generation_algorithm'] as String?) ?? '02',
      tokenClass: row.tokenClass,
      tokenSubclass: asInt(raw['token_subclass']) ?? row.tokenSubClass ?? 0,
      amountKwh: row.amountKwh,
      tidMinutes: asInt(eng['tid_minutes']) ?? asInt(raw['tid_minutes']),
      randomNo: asInt(eng['random_no']) ?? asInt(raw['random_no']),
      amountMoney: (raw['amount_money'] as num?)?.toDouble(),
      currency: (raw['currency'] as String?) ?? row.currency,
      meterSerial: raw['meter_serial'] as String?,
    );
  }
}
