/// Virtual STS meter — the customer-side counterpart to [VirtualHsm].
///
/// A real prepaid electricity meter is personalized at the factory
/// with a decoder key (derived from the utility's vending key via
/// DKGA-02 / DKGA-04). When a customer punches in a 20-digit token,
/// the meter:
///   1. transposes + decrypts the 64-bit data block,
///   2. verifies the CRC,
///   3. checks the Token Identifier (TID) against its
///      already-applied list to reject replays,
///   4. credits the purchased amount to its internal kWh balance,
///   5. stores the new state in non-volatile memory.
///
/// This class is a software simulator of that pipeline. State is
/// persisted as a single JSON file so a meter survives across
/// process restarts and can be inspected with any text editor.
///
/// Out of scope (matches the rest of this MVP): water, gas, Class 1
/// meter-test/display tokens (acknowledged but not "applied"), and
/// Class 2 management tokens (rejected).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../nectar_sts_dart.dart';

/// Outcome of [VirtualMeter.applyToken].
sealed class ApplyResult {
  const ApplyResult();
}

/// A Class 0/0 credit token was accepted and the balance was updated.
class ApplyAccepted extends ApplyResult {
  final double amountKwh;
  final double newBalanceKwh;
  final int tidMinutes;
  final DateTime issuedAt;
  const ApplyAccepted({
    required this.amountKwh,
    required this.newBalanceKwh,
    required this.tidMinutes,
    required this.issuedAt,
  });
}

/// The token's TID matches one already in the applied-tokens log.
/// Balance is unchanged. Real meters track a TID window; this sim
/// stores the full set for simplicity.
class ApplyReplay extends ApplyResult {
  final int tidMinutes;
  const ApplyReplay(this.tidMinutes);
}

/// The token decoded cleanly but is not a credit-bearing class
/// (e.g. Class 1 meter-test). Logged but the balance is unchanged.
class ApplyNonCredit extends ApplyResult {
  final String tokenType;
  const ApplyNonCredit(this.tokenType);
}

/// Decode failed — bad CRC, wrong key, non-numeric token, etc.
class ApplyRejected extends ApplyResult {
  final String reason;
  const ApplyRejected(this.reason);
}

/// Persisted record of one successfully-applied credit token.
class AppliedTokenRecord {
  final String tokenNo;
  final double amountKwh;
  final int tidMinutes;
  final DateTime issuedAt;
  final DateTime appliedAt;

  const AppliedTokenRecord({
    required this.tokenNo,
    required this.amountKwh,
    required this.tidMinutes,
    required this.issuedAt,
    required this.appliedAt,
  });

  Map<String, dynamic> toJson() => {
    'token_no': tokenNo,
    'amount_kwh': amountKwh,
    'tid_minutes': tidMinutes,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'applied_at': appliedAt.toUtc().toIso8601String(),
  };

  factory AppliedTokenRecord.fromJson(Map<String, dynamic> j) =>
      AppliedTokenRecord(
        tokenNo: j['token_no'] as String,
        amountKwh: (j['amount_kwh'] as num).toDouble(),
        tidMinutes: (j['tid_minutes'] as num).toInt(),
        issuedAt: DateTime.parse(j['issued_at'] as String),
        appliedAt: DateTime.parse(j['applied_at'] as String),
      );
}

/// Personalization data stored on the meter for human inspection /
/// re-derivation. Not strictly needed at runtime — the decoder key
/// is the only field touched on every token apply — but persisted
/// so the JSON file is self-documenting and a stolen meter sim can
/// be paired back to its vending key.
class MeterIdentity {
  final String issuerIdentificationNumber;
  final String individualAccountIdentificationNumber;
  final int keyType;
  final String supplyGroupCode;
  final String tariffIndex;
  final int keyRevisionNumber;
  final String decoderKeyGenerationAlgorithm; // '02' or '04'
  final String? baseDate; // only meaningful for DKGA-04

  const MeterIdentity({
    required this.issuerIdentificationNumber,
    required this.individualAccountIdentificationNumber,
    required this.keyType,
    required this.supplyGroupCode,
    required this.tariffIndex,
    required this.keyRevisionNumber,
    this.decoderKeyGenerationAlgorithm = '02',
    this.baseDate,
  });

  Map<String, dynamic> toJson() => {
    'issuer_identification_no': issuerIdentificationNumber,
    'decoder_reference_number': individualAccountIdentificationNumber,
    'key_type': keyType,
    'supply_group_code': supplyGroupCode,
    'tariff_index': tariffIndex,
    'key_revision_no': keyRevisionNumber,
    'decoder_key_generation_algorithm': decoderKeyGenerationAlgorithm,
    if (baseDate != null) 'base_date': baseDate,
  };

  factory MeterIdentity.fromJson(Map<String, dynamic> j) => MeterIdentity(
    issuerIdentificationNumber: j['issuer_identification_no'] as String,
    individualAccountIdentificationNumber:
        j['decoder_reference_number'] as String,
    keyType: (j['key_type'] as num).toInt(),
    supplyGroupCode: j['supply_group_code'] as String,
    tariffIndex: j['tariff_index'] as String,
    keyRevisionNumber: (j['key_revision_no'] as num).toInt(),
    decoderKeyGenerationAlgorithm:
        (j['decoder_key_generation_algorithm'] as String?) ?? '02',
    baseDate: j['base_date'] as String?,
  );
}

class VirtualMeter {
  final MeterIdentity identity;
  final Uint8List decoderKeyBytes;
  final String encryptionAlgorithmName; // 'sta' | 'dea'
  double balanceKwh;
  final List<AppliedTokenRecord> appliedTokens;
  final DateTime createdAt;

  /// Filesystem path the meter was loaded from (or will be saved
  /// to). `null` for in-memory-only meters used in unit tests.
  String? filePath;

  VirtualMeter({
    required this.identity,
    required this.decoderKeyBytes,
    this.encryptionAlgorithmName = 'sta',
    this.balanceKwh = 0.0,
    List<AppliedTokenRecord>? appliedTokens,
    DateTime? createdAt,
    this.filePath,
  }) : appliedTokens = appliedTokens ?? <AppliedTokenRecord>[],
       createdAt = createdAt ?? DateTime.now().toUtc();

  /// Factory: personalize a fresh meter from a vending key + identity.
  /// Mirrors what a utility's factory provisioning step would do.
  factory VirtualMeter.setup({
    required MeterIdentity identity,
    required Uint8List vendingKeyBytes,
    String encryptionAlgorithm = 'sta',
    double initialBalanceKwh = 0.0,
    String? filePath,
  }) {
    final hsm = VirtualHsm(VendingCommonDesKey(vendingKeyBytes));
    final DecoderKey decoderKey;
    switch (identity.decoderKeyGenerationAlgorithm) {
      case '02':
        decoderKey = hsm.deriveDecoderKeyDkga02(
          issuerIdentificationNumber: IssuerIdentificationNumber(
            identity.issuerIdentificationNumber,
          ),
          individualAccountIdentificationNumber:
              IndividualAccountIdentificationNumber(
                identity.individualAccountIdentificationNumber,
              ),
          keyType: KeyType(identity.keyType),
          supplyGroupCode: SupplyGroupCode(identity.supplyGroupCode),
          tariffIndex: TariffIndex(identity.tariffIndex),
          keyRevisionNumber: KeyRevisionNumber(identity.keyRevisionNumber),
        );
      case '04':
        if (identity.baseDate == null) {
          throw const InvalidBaseDateException(
            'DKGA-04 setup requires a base_date in the identity',
          );
        }
        decoderKey = hsm.deriveDecoderKeyDkga04(
          baseDate: _parseBaseDate(identity.baseDate!),
          tariffIndex: TariffIndex(identity.tariffIndex),
          supplyGroupCode: SupplyGroupCode(identity.supplyGroupCode),
          keyType: KeyType(identity.keyType),
          keyRevisionNumber: KeyRevisionNumber(identity.keyRevisionNumber),
          encryptionAlgorithm: _eaFromName(encryptionAlgorithm),
          meterPan: MeterPrimaryAccountNumber(
            issuerIdentificationNumber: IssuerIdentificationNumber(
              identity.issuerIdentificationNumber,
            ),
            individualAccountIdentificationNumber:
                IndividualAccountIdentificationNumber(
                  identity.individualAccountIdentificationNumber,
                ),
          ),
        );
      default:
        throw InvalidDecoderKeyGenerationAlgorithm(
          'VirtualMeter.setup: unsupported DKGA '
          '"${identity.decoderKeyGenerationAlgorithm}" '
          '(only "02" and "04" are ported)',
        );
    }
    return VirtualMeter(
      identity: identity,
      decoderKeyBytes: Uint8List.fromList(decoderKey.keyData),
      encryptionAlgorithmName: encryptionAlgorithm,
      balanceKwh: initialBalanceKwh,
      filePath: filePath,
    );
  }

  /// Apply a 20-digit token. Updates [balanceKwh] + [appliedTokens]
  /// on accept. Does NOT auto-persist — call [save] afterwards if a
  /// filesystem-backed meter.
  ApplyResult applyToken(String tokenNo) {
    final dispatcher = TokenDecoderDispatcher(
      DecoderKey(decoderKeyBytes),
      _eaFromName(encryptionAlgorithmName),
    );
    final requestId = 'meter-${DateTime.now().microsecondsSinceEpoch}';
    final result = dispatcher.decodeDecimal(requestId, tokenNo);
    if (result is DecodeFailure) {
      return ApplyRejected('${result.error.runtimeType}: ${result.reason}');
    }
    final token = (result as DecodeAccepted).token;

    if (token is! TransferElectricityCreditToken) {
      return ApplyNonCredit(token.type);
    }

    final tid = token.tokenIdentifier!.bitString.value;
    final alreadyApplied = appliedTokens.any((r) => r.tidMinutes == tid);
    if (alreadyApplied) return ApplyReplay(tid);

    final amount = token.amountPurchased!.unitsPurchased;
    balanceKwh += amount;
    final record = AppliedTokenRecord(
      tokenNo: tokenNo,
      amountKwh: amount,
      tidMinutes: tid,
      issuedAt: token.tokenIdentifier!.timeOfIssue,
      appliedAt: DateTime.now().toUtc(),
    );
    appliedTokens.add(record);
    return ApplyAccepted(
      amountKwh: amount,
      newBalanceKwh: balanceKwh,
      tidMinutes: tid,
      issuedAt: record.issuedAt,
    );
  }

  // ---- persistence ---------------------------------------------

  Map<String, dynamic> toJson() => {
    'schema': 'nectar_sts_dart.virtual_meter/v1',
    'created_at': createdAt.toIso8601String(),
    'identity': identity.toJson(),
    'decoder_key_hex': _bytesToHex(decoderKeyBytes),
    'encryption_algorithm': encryptionAlgorithmName,
    'balance_kwh': balanceKwh,
    'applied_tokens': appliedTokens.map((r) => r.toJson()).toList(),
  };

  factory VirtualMeter.fromJson(Map<String, dynamic> j, {String? filePath}) {
    final schema = j['schema'];
    if (schema != null && schema != 'nectar_sts_dart.virtual_meter/v1') {
      throw FormatException('Unsupported meter schema: $schema');
    }
    return VirtualMeter(
      identity: MeterIdentity.fromJson(j['identity'] as Map<String, dynamic>),
      decoderKeyBytes: parseHexKey(j['decoder_key_hex'] as String),
      encryptionAlgorithmName: (j['encryption_algorithm'] as String?) ?? 'sta',
      balanceKwh: (j['balance_kwh'] as num).toDouble(),
      appliedTokens: ((j['applied_tokens'] as List?) ?? const [])
          .map((e) => AppliedTokenRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: j['created_at'] is String
          ? DateTime.parse(j['created_at'] as String)
          : null,
      filePath: filePath,
    );
  }

  /// Read a meter from a JSON file. Throws [FileSystemException] if
  /// the file doesn't exist.
  static VirtualMeter load(String filePath) {
    final raw = File(filePath).readAsStringSync();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return VirtualMeter.fromJson(j, filePath: filePath);
  }

  /// Write the meter to [filePath] (or `this.filePath`) using a
  /// pretty-printed two-space indent.
  void save([String? target]) {
    final path = target ?? filePath;
    if (path == null) {
      throw StateError(
        'VirtualMeter.save called with no path and no filePath set',
      );
    }
    const enc = JsonEncoder.withIndent('  ');
    File(path).writeAsStringSync('${enc.convert(toJson())}\n');
    filePath = path;
  }
}

EncryptionAlgorithm _eaFromName(String name) {
  switch (name.toLowerCase()) {
    case 'sta':
      return StandardTransferAlgorithm();
    case 'dea':
      return DataEncryptionAlgorithm();
    default:
      throw InvalidTokenException('Unknown encryption_algorithm: $name');
  }
}

BaseDate _parseBaseDate(String raw) {
  switch (raw.trim()) {
    case '1993':
    case '93':
      return BaseDate.date1993;
    case '2014':
    case '14':
      return BaseDate.date2014;
    case '2035':
    case '35':
      return BaseDate.date2035;
    default:
      throw InvalidBaseDateException('Unknown base_date: $raw');
  }
}

String _bytesToHex(Uint8List bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
