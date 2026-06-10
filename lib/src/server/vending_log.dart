/// JSON-backed audit log of every token the server has minted.
///
/// Each successful `POST /v1/tokens` appends one [IssuedTokenRecord]
/// to the log and (if a file path is configured) flushes it to disk
/// before responding. The log is also used for fail-fast TID
/// collision detection: re-issuing a token with the same meter
/// identity AND the same Token Identifier (24-bit minute count)
/// would produce a token that the physical meter will silently
/// reject as a replay — so we reject it at vending time instead.
///
/// **What is NOT persisted**:
///   - The vending key.
///   - Derived decoder keys.
///   - The raw 64-bit encrypted block.
///
/// Only the issued 20-digit token number, the meter identity used
/// to derive its decoder key, and the decoded plaintext fields
/// (amount, TID, random_no) are stored. That's the bare minimum
/// needed to:
///   1. Prove what was sold (regulatory audit).
///   2. Detect TID collisions before issuing.
///   3. Help a field engineer diagnose "the meter rejected token X"
///      by looking up X and seeing the identity + TID it was minted
///      against.
library;

import 'dart:convert';
import 'dart:io';

/// A single audit-log row.
class IssuedTokenRecord {
  final String requestId;
  final String tokenNo;
  final DateTime issuedAt;
  final String iin;
  final String iain;
  final int keyType;
  final String supplyGroupCode;
  final String tariffIndex;
  final int keyRevisionNumber;
  final String decoderKeyGenerationAlgorithm;
  final int tokenClass;
  final int tokenSubclass;
  final double? amountKwh; // null for non-credit tokens
  final int? tidMinutes; // null for tokens with no TID (class 1)
  final int? randomNo;

  /// Registry serial the vending request used, if any. `null` when
  /// the request supplied the identity inline rather than via
  /// `meter_serial`.
  final String? meterSerial;

  const IssuedTokenRecord({
    required this.requestId,
    required this.tokenNo,
    required this.issuedAt,
    required this.iin,
    required this.iain,
    required this.keyType,
    required this.supplyGroupCode,
    required this.tariffIndex,
    required this.keyRevisionNumber,
    required this.decoderKeyGenerationAlgorithm,
    required this.tokenClass,
    required this.tokenSubclass,
    this.amountKwh,
    this.tidMinutes,
    this.randomNo,
    this.meterSerial,
  });

  /// Cheap meter-identity key used for collision lookups. Same
  /// shape `VirtualHsm` uses to derive the decoder key, so two
  /// records with the same fingerprint share a decoder key on the
  /// physical meter.
  String get identityFingerprint =>
      '$iin|$iain|$keyType|$supplyGroupCode|$tariffIndex|'
      '$keyRevisionNumber|$decoderKeyGenerationAlgorithm';

  Map<String, dynamic> toJson() => {
    'request_id': requestId,
    'token_no': tokenNo,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'iin': iin,
    'iain': iain,
    'key_type': keyType,
    'supply_group_code': supplyGroupCode,
    'tariff_index': tariffIndex,
    'key_revision_no': keyRevisionNumber,
    'decoder_key_generation_algorithm': decoderKeyGenerationAlgorithm,
    'token_class': tokenClass,
    'token_subclass': tokenSubclass,
    if (amountKwh != null) 'amount_kwh': amountKwh,
    if (tidMinutes != null) 'tid_minutes': tidMinutes,
    if (randomNo != null) 'random_no': randomNo,
    if (meterSerial != null) 'meter_serial': meterSerial,
  };

  factory IssuedTokenRecord.fromJson(Map<String, dynamic> j) =>
      IssuedTokenRecord(
        requestId: j['request_id'] as String,
        tokenNo: j['token_no'] as String,
        issuedAt: DateTime.parse(j['issued_at'] as String),
        iin: j['iin'] as String,
        iain: j['iain'] as String,
        keyType: (j['key_type'] as num).toInt(),
        supplyGroupCode: j['supply_group_code'] as String,
        tariffIndex: j['tariff_index'] as String,
        keyRevisionNumber: (j['key_revision_no'] as num).toInt(),
        decoderKeyGenerationAlgorithm:
            j['decoder_key_generation_algorithm'] as String,
        tokenClass: (j['token_class'] as num).toInt(),
        tokenSubclass: (j['token_subclass'] as num).toInt(),
        amountKwh: (j['amount_kwh'] as num?)?.toDouble(),
        tidMinutes: (j['tid_minutes'] as num?)?.toInt(),
        randomNo: (j['random_no'] as num?)?.toInt(),
        meterSerial: j['meter_serial'] as String?,
      );
}

/// Async-only surface that the REST layer consumes. Both the
/// JSON-file [VendingLog] and the MySQL-backed `DbVendingLog`
/// implement this so handlers don't have to know which is wired up.
///
/// Method names are intentionally distinct from the sync API on
/// [VendingLog] so the in-memory class can keep both.
abstract interface class VendingLogStore {
  /// Persist [r]. May throw if the backing store rejects the row
  /// (e.g. the DB store requires a registered meter).
  Future<void> record(IssuedTokenRecord r);

  /// `true` when `(identityFingerprint, tidMinutes)` has already
  /// been issued — vending would produce a replay token.
  Future<bool> tidExists({
    required String identityFingerprint,
    required int? tidMinutes,
  });

  /// Returns the colliding record, for richer error messages.
  Future<IssuedTokenRecord?> findCollision({
    required String identityFingerprint,
    required int tidMinutes,
  });

  /// Lookup by 20-digit token number.
  Future<IssuedTokenRecord?> lookupToken(String tokenNo);

  /// All tokens for a meter (filter by `iin` and/or `iain`).
  Future<List<IssuedTokenRecord>> forMeter({String? iin, String? iain});

  /// Row count without materialising the full list.
  Future<int> total();
}

class VendingLog implements VendingLogStore {
  final List<IssuedTokenRecord> _issues;
  final DateTime createdAt;

  /// Filesystem path the log persists to. `null` for an in-memory
  /// log (handy for tests).
  String? filePath;

  VendingLog({
    List<IssuedTokenRecord>? issues,
    DateTime? createdAt,
    this.filePath,
  }) : _issues = issues ?? <IssuedTokenRecord>[],
       createdAt = createdAt ?? DateTime.now().toUtc();

  List<IssuedTokenRecord> get issues => List.unmodifiable(_issues);
  int get length => _issues.length;

  /// Append [record] and (if [filePath] is set) flush to disk.
  void append(IssuedTokenRecord record) {
    _issues.add(record);
    if (filePath != null) save();
  }

  /// `true` if the log already contains a record for the same
  /// `(identityFingerprint, tidMinutes)` pair. `tidMinutes == null`
  /// (e.g. Class 1 tokens) never collides.
  bool hasTidCollision({
    required String identityFingerprint,
    required int? tidMinutes,
  }) {
    if (tidMinutes == null) return false;
    for (final r in _issues) {
      if (r.tidMinutes == tidMinutes &&
          r.identityFingerprint == identityFingerprint) {
        return true;
      }
    }
    return false;
  }

  IssuedTokenRecord? findByTokenNo(String tokenNo) {
    for (final r in _issues) {
      if (r.tokenNo == tokenNo) return r;
    }
    return null;
  }

  Iterable<IssuedTokenRecord> findByMeter({String? iin, String? iain}) =>
      _issues.where(
        (r) =>
            (iin == null || r.iin == iin) && (iain == null || r.iain == iain),
      );

  // ---- VendingLogStore (async) --------------------------------

  @override
  Future<void> record(IssuedTokenRecord r) async => append(r);

  @override
  Future<bool> tidExists({
    required String identityFingerprint,
    required int? tidMinutes,
  }) async => hasTidCollision(
    identityFingerprint: identityFingerprint,
    tidMinutes: tidMinutes,
  );

  @override
  Future<IssuedTokenRecord?> findCollision({
    required String identityFingerprint,
    required int tidMinutes,
  }) async {
    for (final r in _issues) {
      if (r.tidMinutes == tidMinutes &&
          r.identityFingerprint == identityFingerprint) {
        return r;
      }
    }
    return null;
  }

  @override
  Future<IssuedTokenRecord?> lookupToken(String tokenNo) async =>
      findByTokenNo(tokenNo);

  @override
  Future<List<IssuedTokenRecord>> forMeter({String? iin, String? iain}) async =>
      findByMeter(iin: iin, iain: iain).toList();

  @override
  Future<int> total() async => length;

  // ---- persistence --------------------------------------------

  Map<String, dynamic> toJson() => {
    'schema': 'nectar_sts_dart.vending_log/v1',
    'created_at': createdAt.toIso8601String(),
    'issues': _issues.map((r) => r.toJson()).toList(),
  };

  factory VendingLog.fromJson(Map<String, dynamic> j, {String? filePath}) {
    final schema = j['schema'];
    if (schema != null && schema != 'nectar_sts_dart.vending_log/v1') {
      throw FormatException('Unsupported vending-log schema: $schema');
    }
    return VendingLog(
      issues: ((j['issues'] as List?) ?? const [])
          .map((e) => IssuedTokenRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: j['created_at'] is String
          ? DateTime.parse(j['created_at'] as String)
          : null,
      filePath: filePath,
    );
  }

  /// Read a log file. If the file does not exist, returns a fresh
  /// log bound to [filePath] (so the first `append` writes it).
  static VendingLog loadOrCreate(String filePath) {
    final f = File(filePath);
    if (!f.existsSync()) {
      return VendingLog(filePath: filePath);
    }
    final raw = f.readAsStringSync();
    if (raw.trim().isEmpty) {
      return VendingLog(filePath: filePath);
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return VendingLog.fromJson(j, filePath: filePath);
  }

  void save([String? target]) {
    final path = target ?? filePath;
    if (path == null) {
      throw StateError('VendingLog.save: no path and no filePath set');
    }
    const enc = JsonEncoder.withIndent('  ');
    File(path).writeAsStringSync('${enc.convert(toJson())}\n');
    filePath = path;
  }
}
