/// Static query builder facade over the shared MySQL pool.
///
/// All DB access in the DB-backed meter registry / vending log goes
/// through this file. Style + structure mirrors
/// `C:\www\dart\dart-ari\lib\ari\api\db_queries.dart`:
///   * `static Future<...>` methods, no instances.
///   * `final db = await getDbConnection();`
///   * `db.table('...').where(...).get() / .insert(...) / .update(...)`
///   * `await Database.release(db);` in `finally`.
///
/// **Schema.** Targets the same `sts_vending` MySQL schema the Laravel
/// dashboard owns (see `C:\www\web\laravel\sts-vending\database\migrations`).
/// Relevant tables:
///   - `supply_groups (id, code, name, ...)`
///   - `vending_keys  (id, name, supply_group_id, key_type, tariff_index,
///                     key_revision_number, key_expiry_number, algorithm,
///                     encryption_algorithm, base_date, vudk_blob, ...)`
///     NOTE: `vudk_blob` is encrypted at rest with Laravel's APP_KEY —
///     the Dart server never reads it. The server uses its own
///     `VENDING_KEY_HEX` env var for token generation; this table is
///     consulted only for the non-secret metadata (algorithm, EA,
///     KT, TI, KRN, KEN, BD, SGC).
///   - `meters (id, pan, iin, iain, decoder_serial_number,
///              supply_group_id, vending_key_id, tariff_id, customer_id, ...)`
///   - `tokens (id, request_id, token_no, meter_id, vending_key_id,
///              token_class, token_sub_class, token_kind, amount_kwh,
///              currency, issued_at, payload, engine_response,
///              status, failure_reason, ...)`
///
/// **What the Dart server stores in `tokens.engine_response`.** The
/// JSON includes the per-token audit fields the Laravel schema does
/// not have dedicated columns for:
///   { "tid_minutes": int|null,
///     "random_no":   int|null,
///     "identity_fingerprint": "<iin>|<iain>|<kt>|<sgc>|<ti>|<krn>|<dkga>",
///     "raw": { ...full engine response... } }
/// `hasTidCollision` and `findIssuedByMeter` use MySQL JSON_EXTRACT
/// to query those fields.
library;

import 'dart:convert';

import 'package:eloquent/eloquent.dart';

import 'database.dart';

/// MySQL TINYINT(1) columns come back as either `bool` (mysql_dart,
/// when the column metadata flags BOOLEAN) or `num` (older drivers
/// / non-BOOLEAN tinyints). Normalise so call sites don't have to
/// guard each cast.
bool _asBool(Object? v) {
  if (v == null) return false;
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/// MySQL DECIMAL columns come back as `String` from mysql_dart's
/// binary protocol. Normalise to `double?`.
double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Returned by [DbQueries.findMeterByPan] / [findMeterBySerial]. Carries
/// the joined identity the server needs to derive a decoder key.
class MeterRow {
  final int id;
  final String pan;
  final String iin;
  final String iain;
  final String? decoderSerialNumber;
  final int supplyGroupId;
  final String supplyGroupCode;
  final int? vendingKeyId;
  final int? keyType;
  final String? tariffIndex;
  final int? keyRevisionNumber;
  final int? keyExpiryNumber;
  final String? algorithm; // 'DKGA02' / 'DKGA04'
  final String? encryptionAlgorithm; // 'EA07' / 'EA11'
  final int? baseDate;
  final String? location;
  final bool isActive;

  const MeterRow({
    required this.id,
    required this.pan,
    required this.iin,
    required this.iain,
    required this.supplyGroupId,
    required this.supplyGroupCode,
    required this.isActive,
    this.decoderSerialNumber,
    this.vendingKeyId,
    this.keyType,
    this.tariffIndex,
    this.keyRevisionNumber,
    this.keyExpiryNumber,
    this.algorithm,
    this.encryptionAlgorithm,
    this.baseDate,
    this.location,
  });

  factory MeterRow.fromRow(Map<String, dynamic> r) => MeterRow(
        id: (r['id'] as num).toInt(),
        pan: r['pan'] as String,
        iin: r['iin'] as String,
        iain: r['iain'] as String,
        decoderSerialNumber: r['decoder_serial_number'] as String?,
        supplyGroupId: (r['supply_group_id'] as num).toInt(),
        supplyGroupCode: r['sg_code'] as String,
        vendingKeyId: (r['vending_key_id'] as num?)?.toInt(),
        keyType: (r['vk_key_type'] as num?)?.toInt(),
        tariffIndex: r['vk_tariff_index'] as String?,
        keyRevisionNumber: (r['vk_key_revision_number'] as num?)?.toInt(),
        keyExpiryNumber: (r['vk_key_expiry_number'] as num?)?.toInt(),
        algorithm: r['vk_algorithm'] as String?,
        encryptionAlgorithm: r['vk_encryption_algorithm'] as String?,
        baseDate: (r['vk_base_date'] as num?)?.toInt(),
        location: r['location'] as String?,
        isActive: _asBool(r['is_active']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'pan': pan,
        'iin': iin,
        'iain': iain,
        'decoder_serial_number': decoderSerialNumber,
        'supply_group_id': supplyGroupId,
        'supply_group_code': supplyGroupCode,
        'vending_key_id': vendingKeyId,
        'key_type': keyType,
        'tariff_index': tariffIndex,
        'key_revision_number': keyRevisionNumber,
        'key_expiry_number': keyExpiryNumber,
        'algorithm': algorithm,
        'encryption_algorithm': encryptionAlgorithm,
        'base_date': baseDate,
        'location': location,
        'is_active': isActive,
      };
}

/// Returned by the vending-log queries. Subset of the `tokens` row
/// the Dart server cares about.
class IssuedTokenRow {
  final int id;
  final String requestId;
  final String tokenNo;
  final int meterId;
  final String meterPan;
  final int? vendingKeyId;
  final int tokenClass;
  final int? tokenSubClass;
  final String tokenKind;
  final double? amountKwh;
  final String? currency;
  final DateTime issuedAt;
  final Map<String, dynamic>? engineResponse;
  final String status;

  const IssuedTokenRow({
    required this.id,
    required this.requestId,
    required this.tokenNo,
    required this.meterId,
    required this.meterPan,
    required this.tokenClass,
    required this.tokenKind,
    required this.issuedAt,
    required this.status,
    this.vendingKeyId,
    this.tokenSubClass,
    this.amountKwh,
    this.currency,
    this.engineResponse,
  });

  factory IssuedTokenRow.fromRow(Map<String, dynamic> r) {
    Map<String, dynamic>? engine;
    final rawEngine = r['engine_response'];
    if (rawEngine is String && rawEngine.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEngine);
        if (decoded is Map<String, dynamic>) {
          engine = decoded;
        } else if (decoded is String) {
          // mysql_dart may return the JSON column double-encoded
          // after CAST(... AS CHAR). Peel one layer if so.
          final inner = jsonDecode(decoded);
          if (inner is Map<String, dynamic>) engine = inner;
        }
      } catch (_) {
        engine = null;
      }
    } else if (rawEngine is Map<String, dynamic>) {
      engine = rawEngine;
    }
    return IssuedTokenRow(
      id: (r['id'] as num).toInt(),
      requestId: r['request_id'] as String,
      tokenNo: r['token_no'] as String,
      meterId: (r['meter_id'] as num).toInt(),
      meterPan: (r['meter_pan'] as String?) ?? '',
      vendingKeyId: (r['vending_key_id'] as num?)?.toInt(),
      tokenClass: (r['token_class'] as num).toInt(),
      tokenSubClass: (r['token_sub_class'] as num?)?.toInt(),
      tokenKind: r['token_kind'] as String,
      amountKwh: _asDouble(r['amount_kwh']),
      currency: r['currency'] as String?,
      issuedAt: _parseDate(r['issued_at']),
      engineResponse: engine,
      status: (r['status'] as String?) ?? 'issued',
    );
  }

  static DateTime _parseDate(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v.replaceFirst(' ', 'T'));
    return DateTime.now().toUtc();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'request_id': requestId,
        'token_no': tokenNo,
        'meter_id': meterId,
        'meter_pan': meterPan,
        'vending_key_id': vendingKeyId,
        'token_class': tokenClass,
        'token_sub_class': tokenSubClass,
        'token_kind': tokenKind,
        'amount_kwh': amountKwh,
        if (currency != null) 'currency': currency,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        'status': status,
        if (engineResponse != null) 'engine_response': engineResponse,
      };
}

/// Raised when the Laravel dashboard hasn't pre-provisioned the
/// supporting row a Dart-side register call needs.
class MissingForeignRowException implements Exception {
  final String table;
  final String key;
  final String value;
  const MissingForeignRowException(this.table, this.key, this.value);
  @override
  String toString() =>
      'MissingForeignRowException: no $table row where $key=$value '
      '(create it in the Laravel dashboard first)';
}

/// `yyyy-MM-dd HH:mm:ss` UTC. MySQL DATETIME-compatible.
String _mysqlNow() => DateTime.now()
    .toUtc()
    .toIso8601String()
    .split('.')
    .first
    .replaceFirst('T', ' ');

class DbQueries {
  /// Backwards-compatible accessor. Returns the process-wide pooled
  /// connection. Do NOT call `disconnect()` on the result.
  static Future<Connection> getDbConnection() => Database.connection();

  // ---- supply groups -------------------------------------------

  /// Find a supply-group `id` by its 6-digit SGC. Returns `null` when
  /// the row does not exist.
  static Future<int?> findSupplyGroupIdByCode(String code) async {
    final db = await getDbConnection();
    try {
      final row =
          await db.table('supply_groups').where('code', '=', code).first();
      if (row == null) return null;
      return (row['id'] as num).toInt();
    } finally {
      await Database.release(db);
    }
  }

  // ---- meters --------------------------------------------------

  /// All registered meters, joined with the SGC + vending-key
  /// metadata the Dart token server needs.
  static Future<List<MeterRow>> listMeters({int limit = 500}) async {
    final db = await getDbConnection();
    try {
      final rows = await _selectMeters(db).limit(limit).get();
      return rows.cast<Map<String, dynamic>>().map(MeterRow.fromRow).toList();
    } finally {
      await Database.release(db);
    }
  }

  static Future<MeterRow?> findMeterById(int id) async {
    final db = await getDbConnection();
    try {
      final row = await _selectMeters(db).where('meters.id', '=', id).first();
      if (row == null) return null;
      return MeterRow.fromRow(Map<String, dynamic>.from(row));
    } finally {
      await Database.release(db);
    }
  }

  static Future<MeterRow?> findMeterByPan(String pan) async {
    final db = await getDbConnection();
    try {
      final row = await _selectMeters(db).where('meters.pan', '=', pan).first();
      if (row == null) return null;
      return MeterRow.fromRow(Map<String, dynamic>.from(row));
    } finally {
      await Database.release(db);
    }
  }

  static Future<MeterRow?> findMeterBySerial(String decoderSerial) async {
    final db = await getDbConnection();
    try {
      final row = await _selectMeters(
        db,
      ).where('meters.decoder_serial_number', '=', decoderSerial).first();
      if (row == null) return null;
      return MeterRow.fromRow(Map<String, dynamic>.from(row));
    } finally {
      await Database.release(db);
    }
  }

  /// Find the meter that shares the IIN+IAIN tuple. Used by the
  /// vending-log lookup endpoints.
  static Future<MeterRow?> findMeterByIinIain({
    required String iin,
    required String iain,
  }) async {
    final db = await getDbConnection();
    try {
      final row = await _selectMeters(
        db,
      ).where('meters.iin', '=', iin).where('meters.iain', '=', iain).first();
      if (row == null) return null;
      return MeterRow.fromRow(Map<String, dynamic>.from(row));
    } finally {
      await Database.release(db);
    }
  }

  /// Insert a meter row. The Dart side does NOT manage `vending_keys`
  /// or `supply_groups` rows — those are admin-owned in Laravel.
  /// [supplyGroupCode] must already exist; [vendingKeyId] is optional
  /// (the server may run with its own env-var key without a row).
  static Future<int> registerMeter({
    required String pan,
    required String iin,
    required String iain,
    required String supplyGroupCode,
    int? vendingKeyId,
    String? decoderSerialNumber,
    String? manufacturerCode,
    String? location,
    bool isActive = true,
  }) async {
    final sgId = await findSupplyGroupIdByCode(supplyGroupCode);
    if (sgId == null) {
      throw MissingForeignRowException(
        'supply_groups',
        'code',
        supplyGroupCode,
      );
    }

    final db = await getDbConnection();
    try {
      final now = _mysqlNow();
      final id = await db.table('meters').insertGetId({
        'pan': pan,
        'iin': iin,
        'iain': iain,
        'decoder_serial_number': decoderSerialNumber,
        'manufacturer_code': manufacturerCode,
        'supply_group_id': sgId,
        'vending_key_id': vendingKeyId,
        'location': location,
        'balance_kwh': 0,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
        'updated_at': now,
      });
      return id is int ? id : (id as num).toInt();
    } finally {
      await Database.release(db);
    }
  }

  static Future<bool> removeMeterBySerial(String decoderSerial) async {
    final db = await getDbConnection();
    try {
      final n = await db
          .table('meters')
          .where('decoder_serial_number', '=', decoderSerial)
          .delete();
      return n > 0;
    } finally {
      await Database.release(db);
    }
  }

  static Future<int> meterCount() async {
    final db = await getDbConnection();
    try {
      return await db.table('meters').count();
    } finally {
      await Database.release(db);
    }
  }

  // ---- tokens (vending log) ------------------------------------

  /// Insert an issued-token row. Returns the new `tokens.id`.
  ///
  /// [engineResponse] gets stored verbatim in the JSON `engine_response`
  /// column, EXCEPT we hoist `tid_minutes`, `random_no` and
  /// `identity_fingerprint` to the top level of the stored JSON so the
  /// collision query can use `JSON_EXTRACT` cheaply.
  static Future<int> insertIssuedToken({
    required String requestId,
    required String tokenNo,
    required int meterId,
    int? vendingKeyId,
    required int tokenClass,
    int? tokenSubClass,
    required String tokenKind,
    double? amountKwh,
    String? currency,
    DateTime? issuedAt,
    int? tidMinutes,
    int? randomNo,
    required String identityFingerprint,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> engineResponse,
    String status = 'issued',
    String? failureReason,
  }) async {
    final db = await getDbConnection();
    try {
      final now = _mysqlNow();
      final issued = (issuedAt ?? DateTime.now().toUtc())
          .toIso8601String()
          .split('.')
          .first
          .replaceFirst('T', ' ');
      final enrichedEngine = <String, dynamic>{
        'tid_minutes': tidMinutes,
        'random_no': randomNo,
        'identity_fingerprint': identityFingerprint,
        'raw': engineResponse,
      };
      final id = await db.table('tokens').insertGetId({
        'request_id': requestId,
        'token_no': tokenNo,
        'meter_id': meterId,
        'vending_key_id': vendingKeyId,
        'token_class': tokenClass,
        'token_sub_class': tokenSubClass,
        'token_kind': tokenKind,
        'amount_kwh': amountKwh,
        'currency': currency,
        'issued_at': issued,
        'payload': jsonEncode(payload),
        'engine_response': jsonEncode(enrichedEngine),
        'status': status,
        'failure_reason': failureReason,
        'created_at': now,
        'updated_at': now,
      });
      return id is int ? id : (id as num).toInt();
    } finally {
      await Database.release(db);
    }
  }

  /// `true` if the meter has already been issued a token with the
  /// same `tid_minutes` value (re-issuing it would produce a token
  /// the physical meter silently rejects as a replay).
  ///
  /// Implemented as `JSON_EXTRACT(engine_response, '$.tid_minutes')`
  /// because the Laravel schema doesn't have a dedicated column.
  static Future<bool> hasTidCollision({
    required int meterId,
    required int tidMinutes,
  }) async {
    final db = await getDbConnection();
    try {
      final n = await db
          .table('tokens')
          .where('meter_id', '=', meterId)
          .whereRaw("JSON_EXTRACT(engine_response, '\$.tid_minutes') = ?", [
        tidMinutes,
      ]).count();
      return n > 0;
    } finally {
      await Database.release(db);
    }
  }

  static Future<IssuedTokenRow?> findTokenByNo(String tokenNo) async {
    final db = await getDbConnection();
    try {
      final row = await _selectTokens(
        db,
      ).where('tokens.token_no', '=', tokenNo).first();
      if (row == null) return null;
      return IssuedTokenRow.fromRow(Map<String, dynamic>.from(row));
    } finally {
      await Database.release(db);
    }
  }

  static Future<List<IssuedTokenRow>> findTokensByMeter({
    String? iin,
    String? iain,
    int limit = 500,
  }) async {
    final db = await getDbConnection();
    try {
      var q = _selectTokens(db);
      if (iin != null) q = q.where('meters.iin', '=', iin);
      if (iain != null) q = q.where('meters.iain', '=', iain);
      final rows =
          await q.orderBy('tokens.issued_at', 'desc').limit(limit).get();
      return rows
          .cast<Map<String, dynamic>>()
          .map(IssuedTokenRow.fromRow)
          .toList();
    } finally {
      await Database.release(db);
    }
  }

  static Future<int> tokenCount() async {
    final db = await getDbConnection();
    try {
      return await db.table('tokens').count();
    } finally {
      await Database.release(db);
    }
  }

  // ---- shared join builders ------------------------------------

  /// `meters` + `supply_groups` + (optional) `vending_keys`. All
  /// public meter queries share the same projection so [MeterRow.fromRow]
  /// can be a single mapper.
  static QueryBuilder _selectMeters(Connection db) => db
          .table('meters')
          .join('supply_groups', 'supply_groups.id', '=',
              'meters.supply_group_id')
          .leftJoin(
              'vending_keys', 'vending_keys.id', '=', 'meters.vending_key_id')
          .select([
        'meters.id',
        'meters.pan',
        'meters.iin',
        'meters.iain',
        'meters.decoder_serial_number',
        'meters.supply_group_id',
        'meters.vending_key_id',
        'meters.location',
        'meters.is_active',
        'supply_groups.code as sg_code',
        'vending_keys.key_type as vk_key_type',
        'vending_keys.tariff_index as vk_tariff_index',
        'vending_keys.key_revision_number as vk_key_revision_number',
        'vending_keys.key_expiry_number as vk_key_expiry_number',
        'vending_keys.algorithm as vk_algorithm',
        'vending_keys.encryption_algorithm as vk_encryption_algorithm',
        'vending_keys.base_date as vk_base_date',
      ]);

  static QueryBuilder _selectTokens(Connection db) => db
          .table('tokens')
          .leftJoin('meters', 'meters.id', '=', 'tokens.meter_id')
          .select([
        'tokens.id',
        'tokens.request_id',
        'tokens.token_no',
        'tokens.meter_id',
        'tokens.vending_key_id',
        'tokens.token_class',
        'tokens.token_sub_class',
        'tokens.token_kind',
        'tokens.amount_kwh',
        'tokens.currency',
        'tokens.issued_at',
        // mysql_dart's binary protocol can't decode JSON (column
        // type 245) — cast to CHAR so it comes back as a string we
        // can json-decode ourselves.
        QueryExpression(
          'CAST(tokens.engine_response AS CHAR) as engine_response',
        ),
        'tokens.status',
        'meters.pan as meter_pan',
      ]);
}
