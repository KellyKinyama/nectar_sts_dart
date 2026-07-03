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

/// A Class 0 credit token (electricity, water, or gas) was accepted
/// and the matching balance was updated. [commodity] is one of
/// `'electricity'`, `'water'`, `'gas'`; [amountKwh] / [newBalanceKwh]
/// are unit-agnostic numeric amounts (kWh for electricity, m³ for
/// water/gas) named for backwards compatibility.
class ApplyAccepted extends ApplyResult {
  /// Amount credited (numeric — kWh / m³ depending on commodity).
  final double amountKwh;

  /// Balance for [commodity] after the credit was applied.
  final double newBalanceKwh;

  /// TID (minutes-since-base-date) of the accepted token.
  final int tidMinutes;

  /// Wall-clock time the token was issued by the vending back-office.
  final DateTime issuedAt;

  /// `'electricity'`, `'water'`, or `'gas'`.
  final String commodity;

  /// Builds a successful credit-token result.
  const ApplyAccepted({
    required this.amountKwh,
    required this.newBalanceKwh,
    required this.tidMinutes,
    required this.issuedAt,
    this.commodity = 'electricity',
  });
}

/// The token's TID matches one already in the applied-tokens log.
/// Balance is unchanged. Real meters track a TID window; this sim
/// stores the full set for simplicity.
class ApplyReplay extends ApplyResult {
  /// TID of the already-seen token.
  final int tidMinutes;

  /// Builds a replay-detection result for the given [tidMinutes].
  const ApplyReplay(this.tidMinutes);
}

/// The token decoded cleanly but is not a credit-bearing class
/// (e.g. Class 1 meter-test). Logged but the balance is unchanged.
class ApplyNonCredit extends ApplyResult {
  /// Type tag of the accepted-but-not-credit-bearing token.
  final String tokenType;

  /// Builds a non-credit acknowledgement for [tokenType].
  const ApplyNonCredit(this.tokenType);
}

/// Decode failed — bad CRC, wrong key, non-numeric token, etc.
class ApplyRejected extends ApplyResult {
  /// Human-readable rejection reason (safe for logs).
  final String reason;

  /// Builds a rejection result carrying [reason].
  const ApplyRejected(this.reason);
}

/// A 1st Section Decoder Key Change Token was accepted and stashed,
/// waiting for the matching 2nd section before rotation happens.
class ApplyKeyChange1stStaged extends ApplyResult {
  /// High nibble of the incoming new KEN.
  final int keyExpiryNumberHighOrder;

  /// Incoming new KRN.
  final int newKeyRevisionNumber;

  /// Incoming new key type.
  final int newKeyType;

  /// Rollover flag from the 1st-section token.
  final bool rolloverKeyChange;

  /// Builds a 1st-section staged result.
  const ApplyKeyChange1stStaged({
    required this.keyExpiryNumberHighOrder,
    required this.newKeyRevisionNumber,
    required this.newKeyType,
    required this.rolloverKeyChange,
  });
}

/// A 2nd Section Decoder Key Change Token was accepted and stashed,
/// waiting for the matching 1st section before rotation happens.
class ApplyKeyChange2ndStaged extends ApplyResult {
  /// Low nibble of the incoming new KEN.
  final int keyExpiryNumberLowOrder;

  /// Incoming new tariff index.
  final String newTariffIndex;

  /// Builds a 2nd-section staged result.
  const ApplyKeyChange2ndStaged({
    required this.keyExpiryNumberLowOrder,
    required this.newTariffIndex,
  });
}

/// A 3rd Section Decoder Key Change Token (MISTY1) was accepted and
/// stashed. Rotation waits for all four sections to arrive.
class ApplyKeyChange3rdStaged extends ApplyResult {
  /// Low 12 bits of the incoming SGC.
  final int supplyGroupCodeLowOrder;

  /// Builds a 3rd-section staged result.
  const ApplyKeyChange3rdStaged({required this.supplyGroupCodeLowOrder});
}

/// A 4th Section Decoder Key Change Token (MISTY1) was accepted and
/// stashed. Rotation waits for all four sections to arrive.
class ApplyKeyChange4thStaged extends ApplyResult {
  /// High 12 bits of the incoming SGC.
  final int supplyGroupCodeHighOrder;

  /// Builds a 4th-section staged result.
  const ApplyKeyChange4thStaged({required this.supplyGroupCodeHighOrder});
}

/// Both halves of a decoder-key change have arrived; the meter
/// rotated to the new key. Subsequent tokens are decoded under it.
class ApplyKeyRotated extends ApplyResult {
  /// Newly-active KRN.
  final int newKeyRevisionNumber;

  /// Newly-active key type.
  final int newKeyType;

  /// Full 8-bit newly-active KEN (KENHO<<4 | KENLO).
  final int keyExpiryNumber;

  /// Newly-active tariff index.
  final String newTariffIndex;

  /// Rollover flag from the 1st-section token.
  final bool rolloverKeyChange;

  /// New 6-digit Supply Group Code after a MISTY1 4-section rotation
  /// (assembled from SGCHO|SGCLO). `null` for STA 2-section rotations,
  /// which don't change the SGC.
  final String? newSupplyGroupCode;

  /// Builds a completed-rotation result.
  const ApplyKeyRotated({
    required this.newKeyRevisionNumber,
    required this.newKeyType,
    required this.keyExpiryNumber,
    required this.newTariffIndex,
    required this.rolloverKeyChange,
    this.newSupplyGroupCode,
  });
}

/// A Class 2 KCT token decoded successfully but cannot be applied in
/// the meter's current state (e.g. a 2nd section arrived without a
/// matching 1st section already staged, or vice-versa).
class ApplyKeyChangeRejected extends ApplyResult {
  /// Human-readable rejection reason.
  final String reason;

  /// Builds a KCT-rejection result.
  const ApplyKeyChangeRejected(this.reason);
}

/// A management token (Class 2 register-payload subclass) was
/// already-seen by TID. Meter state is unchanged.
class ApplyManagementReplay extends ApplyResult {
  /// Type tag of the already-seen management token.
  final String tokenType;

  /// TID of the already-seen token.
  final int tidMinutes;

  /// Builds a management-replay result.
  const ApplyManagementReplay({
    required this.tokenType,
    required this.tidMinutes,
  });
}

/// `SetMaximumPowerLimit_20` was accepted and the meter's MPL was
/// updated.
class ApplyMaximumPowerLimitSet extends ApplyResult {
  /// Newly-active MPL value (16-bit unsigned).
  final int maximumPowerLimit;

  /// TID of the applied token.
  final int tidMinutes;

  /// Builds a MPL-updated result.
  const ApplyMaximumPowerLimitSet({
    required this.maximumPowerLimit,
    required this.tidMinutes,
  });
}

/// `ClearCredit_21` was accepted; balance was reset to 0.
class ApplyCreditCleared extends ApplyResult {
  /// Balance the meter held immediately before the reset.
  final double previousBalanceKwh;

  /// Value from the token's 16-bit register field (commonly 0).
  final int register;

  /// TID of the applied token.
  final int tidMinutes;

  /// Builds a credit-cleared result.
  const ApplyCreditCleared({
    required this.previousBalanceKwh,
    required this.register,
    required this.tidMinutes,
  });
}

/// `SetTariffRate_22` was accepted and the active tariff rate was
/// updated.
class ApplyTariffRateSet extends ApplyResult {
  /// Newly-active tariff rate (16-bit unsigned).
  final int tariffRate;

  /// TID of the applied token.
  final int tidMinutes;

  /// Builds a tariff-rate-updated result.
  const ApplyTariffRateSet({
    required this.tariffRate,
    required this.tidMinutes,
  });
}

/// `ClearTamperCondition_25` was accepted; any latched tamper flags
/// have been cleared.
class ApplyTamperConditionCleared extends ApplyResult {
  /// TID of the applied token.
  final int tidMinutes;

  /// Builds a tamper-cleared result.
  const ApplyTamperConditionCleared({required this.tidMinutes});
}

/// `SetMaximumPhasePowerUnbalanceLimit_26` was accepted and the
/// meter's MPPUL setting was updated.
class ApplyMaximumPhasePowerUnbalanceLimitSet extends ApplyResult {
  /// Newly-active MPPUL value (16-bit unsigned).
  final int maximumPhasePowerUnbalanceLimit;

  /// TID of the applied token.
  final int tidMinutes;

  /// Builds a MPPUL-updated result.
  const ApplyMaximumPhasePowerUnbalanceLimitSet({
    required this.maximumPhasePowerUnbalanceLimit,
    required this.tidMinutes,
  });
}

/// Persisted record of one successfully-applied credit token.
class AppliedTokenRecord {
  /// 20-digit token string as displayed to the customer.
  final String tokenNo;

  /// Credit amount from the token (kWh / m³).
  final double amountKwh;

  /// TID (minutes-since-base-date) for replay protection.
  final int tidMinutes;

  /// Wall-clock time the token was issued by the back-office.
  final DateTime issuedAt;

  /// Wall-clock time this record was written to meter state.
  final DateTime appliedAt;

  /// `'electricity'`, `'water'`, or `'gas'`.
  final String commodity;

  /// Builds an accepted-token audit record.
  const AppliedTokenRecord({
    required this.tokenNo,
    required this.amountKwh,
    required this.tidMinutes,
    required this.issuedAt,
    required this.appliedAt,
    this.commodity = 'electricity',
  });

  /// Serialises this record to a JSON-friendly map. Elides
  /// `commodity` when it's the default `'electricity'`.
  Map<String, dynamic> toJson() => {
        'token_no': tokenNo,
        'amount_kwh': amountKwh,
        'tid_minutes': tidMinutes,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        'applied_at': appliedAt.toUtc().toIso8601String(),
        if (commodity != 'electricity') 'commodity': commodity,
      };

  /// Rebuilds an [AppliedTokenRecord] from a JSON map produced by
  /// [toJson].
  factory AppliedTokenRecord.fromJson(Map<String, dynamic> j) =>
      AppliedTokenRecord(
        tokenNo: j['token_no'] as String,
        amountKwh: (j['amount_kwh'] as num).toDouble(),
        tidMinutes: (j['tid_minutes'] as num).toInt(),
        issuedAt: DateTime.parse(j['issued_at'] as String),
        appliedAt: DateTime.parse(j['applied_at'] as String),
        commodity: (j['commodity'] as String?) ?? 'electricity',
      );
}

/// Persisted record of one successfully-applied Class 2 register
/// management token. Used for TID-based replay protection.
class AppliedManagementTokenRecord {
  /// 20-digit token string as displayed to the operator.
  final String tokenNo;

  /// Type tag (e.g. `'SetMaximumPowerLimit_20'`).
  final String tokenType;

  /// TID for replay protection.
  final int tidMinutes;

  /// 16-bit payload register value from the token.
  final int registerValue;

  /// Wall-clock time the token was issued by the back-office.
  final DateTime issuedAt;

  /// Wall-clock time this record was written to meter state.
  final DateTime appliedAt;

  /// Builds a management-token audit record.
  const AppliedManagementTokenRecord({
    required this.tokenNo,
    required this.tokenType,
    required this.tidMinutes,
    required this.registerValue,
    required this.issuedAt,
    required this.appliedAt,
  });

  /// Serialises this record to a JSON-friendly map.
  Map<String, dynamic> toJson() => {
        'token_no': tokenNo,
        'token_type': tokenType,
        'tid_minutes': tidMinutes,
        'register_value': registerValue,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        'applied_at': appliedAt.toUtc().toIso8601String(),
      };

  /// Rebuilds an [AppliedManagementTokenRecord] from a JSON map
  /// produced by [toJson].
  factory AppliedManagementTokenRecord.fromJson(Map<String, dynamic> j) =>
      AppliedManagementTokenRecord(
        tokenNo: j['token_no'] as String,
        tokenType: j['token_type'] as String,
        tidMinutes: (j['tid_minutes'] as num).toInt(),
        registerValue: (j['register_value'] as num).toInt(),
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
  /// 6-digit Issuer Identification Number.
  final String issuerIdentificationNumber;

  /// 11-digit Individual Account Identification Number / Decoder
  /// Reference Number.
  final String individualAccountIdentificationNumber;

  /// Numeric key-type code.
  final int keyType;

  /// 6-digit Supply Group Code.
  final String supplyGroupCode;

  /// 2-digit tariff index string.
  final String tariffIndex;

  /// Integer key revision number.
  final int keyRevisionNumber;

  /// `'02'` (DKGA-02) or `'04'` (DKGA-04). Defaults to `'02'`.
  final String decoderKeyGenerationAlgorithm; // '02' or '04'

  /// Base-date string; only meaningful for DKGA-04.
  final String? baseDate; // only meaningful for DKGA-04

  /// Builds a personalization descriptor.
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

  /// Serialises this identity to a JSON-friendly map. Uses the same
  /// key names as the vending-service param map.
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

  /// Rebuilds a [MeterIdentity] from a JSON map produced by [toJson].
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
  /// Personalization descriptor (IIN / IAIN / SGC / TI / KRN / DKGA).
  MeterIdentity identity;

  /// Currently-active decoder key (raw bytes).
  Uint8List decoderKeyBytes;

  /// Currently-active encryption algorithm name (`'sta'`, `'dea'`, or
  /// `'misty1'`).
  final String encryptionAlgorithmName; // 'sta' | 'dea' | 'misty1'

  /// Current electricity credit balance in kWh.
  double balanceKwh;

  /// Current water-credit balance in the meter's water units
  /// (typically m³). Incremented by accepted
  /// [TransferWaterCreditToken]s. Persisted alongside [balanceKwh].
  double balanceWater;

  /// Current gas-credit balance in the meter's gas units (typically
  /// m³). Incremented by accepted [TransferGasCreditToken]s.
  double balanceGas;

  /// Audit log of accepted credit tokens (for replay protection and
  /// operator inspection).
  final List<AppliedTokenRecord> appliedTokens;

  /// Audit log of accepted Class 2 register-payload management
  /// tokens.
  final List<AppliedManagementTokenRecord> appliedManagementTokens;

  /// UTC wall-clock time this meter's JSON state was created.
  final DateTime createdAt;

  /// Filesystem path the meter was loaded from (or will be saved
  /// to). `null` for in-memory-only meters used in unit tests.
  String? filePath;

  /// Current 8-bit Key Expiry Number, if a KCT pair has ever
  /// rotated this meter. `null` on a freshly-personalized meter.
  int? keyExpiryNumber;

  /// Last-set Maximum Power Limit, in the meter's MPL units (16-bit
  /// unsigned). `null` if `SetMaximumPowerLimit` has never been
  /// applied to this meter.
  int? maximumPowerLimit;

  /// Last-set Maximum Phase Power Unbalance Limit (16-bit unsigned).
  int? maximumPhasePowerUnbalanceLimit;

  /// Last-set Tariff Rate (16-bit unsigned).
  int? tariffRate;

  /// When the last `ClearTamperCondition_25` token was applied, if
  /// any. Used to detect whether the meter is currently in a clean
  /// tamper-state-machine state.
  DateTime? tamperConditionClearedAt;

  /// When the last `ClearCredit_21` token was applied, if any.
  DateTime? creditClearedAt;

  // ---- Staged Class 2 Decoder Key Change Token halves --------
  // A real STS meter buffers exactly one in-flight 1st + one
  // in-flight 2nd section. The pair is applied (rotation) the
  // moment both have arrived. Anything else is rejected.
  //
  // For MISTY1, two additional staging slots hold the 3rd and 4th
  // sections (NKMO2+SGCLO and NKMO1+SGCHO); rotation happens only
  // when all four sections have arrived.
  PendingKctSection? _pending1st;
  PendingKctSection? _pending2nd;
  PendingKctSection? _pending3rd;
  PendingKctSection? _pending4th;

  /// Currently-staged 1st-section KCT (if any).
  PendingKctSection? get pending1stSection => _pending1st;

  /// Currently-staged 2nd-section KCT (if any).
  PendingKctSection? get pending2ndSection => _pending2nd;

  /// Currently-staged 3rd-section KCT (MISTY1 rotation, if any).
  PendingKctSection? get pending3rdSection => _pending3rd;

  /// Currently-staged 4th-section KCT (MISTY1 rotation, if any).
  PendingKctSection? get pending4thSection => _pending4th;

  /// Sim-only: a real meter latches a tamper flag in NVRAM when its
  /// case-open or magnetic-tamper sensors trip. The flag is cleared
  /// only by a successful `ClearTamperCondition_25` token. Use
  /// [tripTamper] in tests/demos to simulate the sensor firing.
  bool tamperLatched;

  /// Builds a meter directly from raw state. Prefer
  /// [VirtualMeter.setup] for personalising a fresh meter from a
  /// vending key.
  VirtualMeter({
    required this.identity,
    required this.decoderKeyBytes,
    this.encryptionAlgorithmName = 'sta',
    this.balanceKwh = 0.0,
    this.balanceWater = 0.0,
    this.balanceGas = 0.0,
    List<AppliedTokenRecord>? appliedTokens,
    List<AppliedManagementTokenRecord>? appliedManagementTokens,
    DateTime? createdAt,
    this.filePath,
    this.keyExpiryNumber,
    this.maximumPowerLimit,
    this.maximumPhasePowerUnbalanceLimit,
    this.tariffRate,
    this.tamperConditionClearedAt,
    this.creditClearedAt,
    this.tamperLatched = false,
    PendingKctSection? pending1stSection,
    PendingKctSection? pending2ndSection,
    PendingKctSection? pending3rdSection,
    PendingKctSection? pending4thSection,
  })  : appliedTokens = appliedTokens ?? <AppliedTokenRecord>[],
        appliedManagementTokens =
            appliedManagementTokens ?? <AppliedManagementTokenRecord>[],
        createdAt = createdAt ?? DateTime.now().toUtc(),
        _pending1st = pending1stSection,
        _pending2nd = pending2ndSection,
        _pending3rd = pending3rdSection,
        _pending4th = pending4thSection;

  /// Sim-only: simulate the meter's tamper sensors firing. Sets the
  /// `tamperLatched` flag, which is cleared only by a successful
  /// `ClearTamperCondition_25` token.
  void tripTamper() {
    tamperLatched = true;
  }

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

    if (token is Set1stSectionDecoderKeyToken) {
      return _stage1stSection(token);
    }
    if (token is Set2ndSectionDecoderKeyToken) {
      return _stage2ndSection(token);
    }
    if (token is Set3rdSectionDecoderKeyToken) {
      return _stage3rdSection(token);
    }
    if (token is Set4thSectionDecoderKeyToken) {
      return _stage4thSection(token);
    }
    if (token is SetMaximumPowerLimitToken) {
      return _applyMaximumPowerLimit(tokenNo, token);
    }
    if (token is ClearCreditToken) {
      return _applyClearCredit(tokenNo, token);
    }
    if (token is SetTariffRateToken) {
      return _applySetTariffRate(tokenNo, token);
    }
    if (token is ClearTamperConditionToken) {
      return _applyClearTamperCondition(tokenNo, token);
    }
    if (token is SetMaximumPhasePowerUnbalanceLimitToken) {
      return _applyMaximumPhasePowerUnbalanceLimit(tokenNo, token);
    }

    if (token is TransferElectricityCreditToken) {
      return _applyTransferCredit(tokenNo, token, 'electricity');
    }
    if (token is TransferWaterCreditToken) {
      return _applyTransferCredit(tokenNo, token, 'water');
    }
    if (token is TransferGasCreditToken) {
      return _applyTransferCredit(tokenNo, token, 'gas');
    }

    return ApplyNonCredit(token.type);
  }

  ApplyResult _applyTransferCredit(
    String tokenNo,
    Token token,
    String commodity,
  ) {
    final double amount;
    final TokenIdentifier tid_;
    if (token is TransferElectricityCreditToken) {
      amount = token.amountPurchased!.unitsPurchased;
      tid_ = token.tokenIdentifier!;
    } else if (token is TransferWaterCreditToken) {
      amount = token.amountPurchased!.unitsPurchased;
      tid_ = token.tokenIdentifier!;
    } else if (token is TransferGasCreditToken) {
      amount = token.amountPurchased!.unitsPurchased;
      tid_ = token.tokenIdentifier!;
    } else {
      return ApplyNonCredit(token.type);
    }

    final tid = tid_.bitString.value;
    final alreadyApplied = appliedTokens.any(
      (r) => r.tidMinutes == tid && r.commodity == commodity,
    );
    if (alreadyApplied) return ApplyReplay(tid);

    final double newBalance;
    switch (commodity) {
      case 'water':
        balanceWater += amount;
        newBalance = balanceWater;
      case 'gas':
        balanceGas += amount;
        newBalance = balanceGas;
      default:
        balanceKwh += amount;
        newBalance = balanceKwh;
    }

    final record = AppliedTokenRecord(
      tokenNo: tokenNo,
      amountKwh: amount,
      tidMinutes: tid,
      issuedAt: tid_.timeOfIssue,
      appliedAt: DateTime.now().toUtc(),
      commodity: commodity,
    );
    appliedTokens.add(record);
    return ApplyAccepted(
      amountKwh: amount,
      newBalanceKwh: newBalance,
      tidMinutes: tid,
      issuedAt: record.issuedAt,
      commodity: commodity,
    );
  }

  // ---- Class 2 KCT staging ------------------------------------

  ApplyResult _stage1stSection(Set1stSectionDecoderKeyToken t) {
    final staged = PendingKctSection.first(
      newKeyHighOrderBits: t.newKeyHighOrder!.bitString.toPaddedBinary(),
      keyExpiryNumberHighOrder: t.keyExpiryNumberHighOrder!.value,
      newKeyRevisionNumber: t.keyRevisionNumber!.value,
      newKeyType: t.keyType!.value,
      rolloverKeyChange: t.rolloverKeyChange!.isRollover,
      stagedAt: DateTime.now().toUtc(),
    );
    _pending1st = staged;
    final maybeRotate = _maybeRotate();
    if (maybeRotate != null) return maybeRotate;
    return ApplyKeyChange1stStaged(
      keyExpiryNumberHighOrder: staged.keyExpiryNumberHighOrder!,
      newKeyRevisionNumber: staged.newKeyRevisionNumber!,
      newKeyType: staged.newKeyType!,
      rolloverKeyChange: staged.rolloverKeyChange!,
    );
  }

  ApplyResult _stage2ndSection(Set2ndSectionDecoderKeyToken t) {
    final staged = PendingKctSection.second(
      newKeyLowOrderBits: t.newKeyLowOrder!.bitString.toPaddedBinary(),
      keyExpiryNumberLowOrder: t.keyExpiryNumberLowOrder!.value,
      newTariffIndex: t.tariffIndex!.value,
      stagedAt: DateTime.now().toUtc(),
    );
    _pending2nd = staged;
    final maybeRotate = _maybeRotate();
    if (maybeRotate != null) return maybeRotate;
    return ApplyKeyChange2ndStaged(
      keyExpiryNumberLowOrder: staged.keyExpiryNumberLowOrder!,
      newTariffIndex: staged.newTariffIndex!,
    );
  }

  ApplyResult _stage3rdSection(Set3rdSectionDecoderKeyToken t) {
    final staged = PendingKctSection.third(
      newKeyMiddleOrder2Bits: t.newKeyMiddleOrder2!.bitString.toPaddedBinary(),
      supplyGroupCodeLowOrder: t.supplyGroupCodeLowOrder!.bitString.value,
      stagedAt: DateTime.now().toUtc(),
    );
    _pending3rd = staged;
    final maybeRotate = _maybeRotate();
    if (maybeRotate != null) return maybeRotate;
    return ApplyKeyChange3rdStaged(
      supplyGroupCodeLowOrder: staged.supplyGroupCodeLowOrder!,
    );
  }

  ApplyResult _stage4thSection(Set4thSectionDecoderKeyToken t) {
    final staged = PendingKctSection.fourth(
      newKeyMiddleOrder1Bits: t.newKeyMiddleOrder1!.bitString.toPaddedBinary(),
      supplyGroupCodeHighOrder: t.supplyGroupCodeHighOrder!.bitString.value,
      stagedAt: DateTime.now().toUtc(),
    );
    _pending4th = staged;
    final maybeRotate = _maybeRotate();
    if (maybeRotate != null) return maybeRotate;
    return ApplyKeyChange4thStaged(
      supplyGroupCodeHighOrder: staged.supplyGroupCodeHighOrder!,
    );
  }

  /// Returns an [ApplyKeyRotated] iff every section needed for the
  /// active EA's rotation has been staged. STA/DEA need 1st+2nd;
  /// MISTY1 needs 1st+2nd+3rd+4th. Otherwise returns null and the
  /// caller emits the per-section staged result.
  ApplyResult? _maybeRotate() {
    final isMisty1 = encryptionAlgorithmName.toLowerCase() == 'misty1';
    if (isMisty1) {
      if (_pending1st == null ||
          _pending2nd == null ||
          _pending3rd == null ||
          _pending4th == null) {
        return null;
      }
      return _rotateMisty1();
    }
    if (_pending1st == null || _pending2nd == null) return null;
    return _tryRotate();
  }

  ApplyResult _rotateMisty1() {
    final p1 = _pending1st!;
    final p2 = _pending2nd!;
    final p3 = _pending3rd!;
    final p4 = _pending4th!;
    final newKey = combineMisty1DecoderKey(
      NewKeyHighOrder(BitString.fromBinary(p1.newKeyHighOrderBits!)),
      NewKeyMiddleOrder2(BitString.fromBinary(p3.newKeyMiddleOrder2Bits!)),
      NewKeyMiddleOrder1(BitString.fromBinary(p4.newKeyMiddleOrder1Bits!)),
      NewKeyLowOrder(BitString.fromBinary(p2.newKeyLowOrderBits!)),
    );
    final newKen =
        (p1.keyExpiryNumberHighOrder! << 4) | p2.keyExpiryNumberLowOrder!;
    final newSgc24 =
        (p4.supplyGroupCodeHighOrder! << 12) | p3.supplyGroupCodeLowOrder!;
    final newSgcStr = newSgc24.toString().padLeft(6, '0');

    decoderKeyBytes = Uint8List.fromList(newKey.keyData);
    keyExpiryNumber = newKen;
    identity = MeterIdentity(
      issuerIdentificationNumber: identity.issuerIdentificationNumber,
      individualAccountIdentificationNumber:
          identity.individualAccountIdentificationNumber,
      keyType: p1.newKeyType!,
      supplyGroupCode: newSgcStr,
      tariffIndex: p2.newTariffIndex!,
      keyRevisionNumber: p1.newKeyRevisionNumber!,
      decoderKeyGenerationAlgorithm: identity.decoderKeyGenerationAlgorithm,
      baseDate: identity.baseDate,
    );
    _pending1st = null;
    _pending2nd = null;
    _pending3rd = null;
    _pending4th = null;
    return ApplyKeyRotated(
      newKeyRevisionNumber: p1.newKeyRevisionNumber!,
      newKeyType: p1.newKeyType!,
      keyExpiryNumber: newKen,
      newTariffIndex: p2.newTariffIndex!,
      rolloverKeyChange: p1.rolloverKeyChange!,
      newSupplyGroupCode: newSgcStr,
    );
  }

  ApplyResult _tryRotate() {
    final p1 = _pending1st!;
    final p2 = _pending2nd!;
    final newKey = combineStaDecoderKey(
      NewKeyHighOrder(BitString.fromBinary(p1.newKeyHighOrderBits!)),
      NewKeyLowOrder(BitString.fromBinary(p2.newKeyLowOrderBits!)),
    );
    final newKen =
        (p1.keyExpiryNumberHighOrder! << 4) | p2.keyExpiryNumberLowOrder!;

    decoderKeyBytes = Uint8List.fromList(newKey.keyData);
    keyExpiryNumber = newKen;
    identity = MeterIdentity(
      issuerIdentificationNumber: identity.issuerIdentificationNumber,
      individualAccountIdentificationNumber:
          identity.individualAccountIdentificationNumber,
      keyType: p1.newKeyType!,
      supplyGroupCode: identity.supplyGroupCode,
      tariffIndex: p2.newTariffIndex!,
      keyRevisionNumber: p1.newKeyRevisionNumber!,
      decoderKeyGenerationAlgorithm: identity.decoderKeyGenerationAlgorithm,
      baseDate: identity.baseDate,
    );
    _pending1st = null;
    _pending2nd = null;
    return ApplyKeyRotated(
      newKeyRevisionNumber: p1.newKeyRevisionNumber!,
      newKeyType: p1.newKeyType!,
      keyExpiryNumber: newKen,
      newTariffIndex: p2.newTariffIndex!,
      rolloverKeyChange: p1.rolloverKeyChange!,
    );
  }

  // ---- Class 2 register-payload management tokens ------------

  ApplyResult _applyMaximumPowerLimit(
    String tokenNo,
    SetMaximumPowerLimitToken t,
  ) {
    final tid = t.tokenIdentifier!.bitString.value;
    final replay = _findManagementReplay(tid, t.type);
    if (replay != null) return replay;
    final value = t.maximumPowerLimit!.value;
    maximumPowerLimit = value;
    _recordManagementApply(tokenNo, t, tid, value);
    return ApplyMaximumPowerLimitSet(maximumPowerLimit: value, tidMinutes: tid);
  }

  ApplyResult _applyClearCredit(String tokenNo, ClearCreditToken t) {
    final tid = t.tokenIdentifier!.bitString.value;
    final replay = _findManagementReplay(tid, t.type);
    if (replay != null) return replay;
    final reg = t.register!.value;
    final previous = balanceKwh;
    balanceKwh = 0.0;
    creditClearedAt = DateTime.now().toUtc();
    _recordManagementApply(tokenNo, t, tid, reg);
    return ApplyCreditCleared(
      previousBalanceKwh: previous,
      register: reg,
      tidMinutes: tid,
    );
  }

  ApplyResult _applySetTariffRate(String tokenNo, SetTariffRateToken t) {
    final tid = t.tokenIdentifier!.bitString.value;
    final replay = _findManagementReplay(tid, t.type);
    if (replay != null) return replay;
    final value = t.rate!.value;
    tariffRate = value;
    _recordManagementApply(tokenNo, t, tid, value);
    return ApplyTariffRateSet(tariffRate: value, tidMinutes: tid);
  }

  ApplyResult _applyClearTamperCondition(
    String tokenNo,
    ClearTamperConditionToken t,
  ) {
    final tid = t.tokenIdentifier!.bitString.value;
    final replay = _findManagementReplay(tid, t.type);
    if (replay != null) return replay;
    tamperLatched = false;
    tamperConditionClearedAt = DateTime.now().toUtc();
    _recordManagementApply(tokenNo, t, tid, t.pad!.value);
    return ApplyTamperConditionCleared(tidMinutes: tid);
  }

  ApplyResult _applyMaximumPhasePowerUnbalanceLimit(
    String tokenNo,
    SetMaximumPhasePowerUnbalanceLimitToken t,
  ) {
    final tid = t.tokenIdentifier!.bitString.value;
    final replay = _findManagementReplay(tid, t.type);
    if (replay != null) return replay;
    final value = t.maximumPhasePowerUnbalanceLimit!.value;
    maximumPhasePowerUnbalanceLimit = value;
    _recordManagementApply(tokenNo, t, tid, value);
    return ApplyMaximumPhasePowerUnbalanceLimitSet(
      maximumPhasePowerUnbalanceLimit: value,
      tidMinutes: tid,
    );
  }

  ApplyManagementReplay? _findManagementReplay(int tid, String tokenType) {
    final hit = appliedManagementTokens.any(
      (r) => r.tidMinutes == tid && r.tokenType == tokenType,
    );
    return hit
        ? ApplyManagementReplay(tokenType: tokenType, tidMinutes: tid)
        : null;
  }

  void _recordManagementApply(
    String tokenNo,
    Class2RegisterToken token,
    int tid,
    int registerValue,
  ) {
    appliedManagementTokens.add(
      AppliedManagementTokenRecord(
        tokenNo: tokenNo,
        tokenType: token.type,
        tidMinutes: tid,
        registerValue: registerValue,
        issuedAt: token.tokenIdentifier!.timeOfIssue,
        appliedAt: DateTime.now().toUtc(),
      ),
    );
  }

  // ---- persistence ---------------------------------------------

  /// Serialises this meter to a JSON-friendly map (schema
  /// `nectar_sts_dart.virtual_meter/v4`).
  Map<String, dynamic> toJson() => {
        'schema': 'nectar_sts_dart.virtual_meter/v4',
        'created_at': createdAt.toIso8601String(),
        'identity': identity.toJson(),
        'decoder_key_hex': _bytesToHex(decoderKeyBytes),
        'encryption_algorithm': encryptionAlgorithmName,
        'balance_kwh': balanceKwh,
        if (balanceWater != 0.0) 'balance_water': balanceWater,
        if (balanceGas != 0.0) 'balance_gas': balanceGas,
        if (keyExpiryNumber != null) 'key_expiry_number': keyExpiryNumber,
        if (maximumPowerLimit != null) 'maximum_power_limit': maximumPowerLimit,
        if (maximumPhasePowerUnbalanceLimit != null)
          'maximum_phase_power_unbalance_limit':
              maximumPhasePowerUnbalanceLimit,
        if (tariffRate != null) 'tariff_rate': tariffRate,
        if (tamperConditionClearedAt != null)
          'tamper_condition_cleared_at':
              tamperConditionClearedAt!.toUtc().toIso8601String(),
        if (creditClearedAt != null)
          'credit_cleared_at': creditClearedAt!.toUtc().toIso8601String(),
        if (tamperLatched) 'tamper_latched': true,
        if (_pending1st != null) 'pending_1st_section': _pending1st!.toJson(),
        if (_pending2nd != null) 'pending_2nd_section': _pending2nd!.toJson(),
        if (_pending3rd != null) 'pending_3rd_section': _pending3rd!.toJson(),
        if (_pending4th != null) 'pending_4th_section': _pending4th!.toJson(),
        'applied_tokens': appliedTokens.map((r) => r.toJson()).toList(),
        'applied_management_tokens':
            appliedManagementTokens.map((r) => r.toJson()).toList(),
      };

  /// Rebuilds a [VirtualMeter] from a JSON map produced by
  /// [toJson]. Accepts v1–v4 schemas.
  ///
  /// Throws [FormatException] on an unrecognised schema string.
  factory VirtualMeter.fromJson(Map<String, dynamic> j, {String? filePath}) {
    final schema = j['schema'];
    if (schema != null &&
        schema != 'nectar_sts_dart.virtual_meter/v1' &&
        schema != 'nectar_sts_dart.virtual_meter/v2' &&
        schema != 'nectar_sts_dart.virtual_meter/v3' &&
        schema != 'nectar_sts_dart.virtual_meter/v4') {
      throw FormatException('Unsupported meter schema: $schema');
    }
    return VirtualMeter(
      identity: MeterIdentity.fromJson(j['identity'] as Map<String, dynamic>),
      decoderKeyBytes: parseHexKey(j['decoder_key_hex'] as String),
      encryptionAlgorithmName: (j['encryption_algorithm'] as String?) ?? 'sta',
      balanceKwh: (j['balance_kwh'] as num).toDouble(),
      balanceWater: (j['balance_water'] as num?)?.toDouble() ?? 0.0,
      balanceGas: (j['balance_gas'] as num?)?.toDouble() ?? 0.0,
      appliedTokens: ((j['applied_tokens'] as List?) ?? const [])
          .map((e) => AppliedTokenRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      appliedManagementTokens:
          ((j['applied_management_tokens'] as List?) ?? const [])
              .map(
                (e) => AppliedManagementTokenRecord.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList(),
      createdAt: j['created_at'] is String
          ? DateTime.parse(j['created_at'] as String)
          : null,
      filePath: filePath,
      keyExpiryNumber: j['key_expiry_number'] is num
          ? (j['key_expiry_number'] as num).toInt()
          : null,
      maximumPowerLimit: j['maximum_power_limit'] is num
          ? (j['maximum_power_limit'] as num).toInt()
          : null,
      maximumPhasePowerUnbalanceLimit:
          j['maximum_phase_power_unbalance_limit'] is num
              ? (j['maximum_phase_power_unbalance_limit'] as num).toInt()
              : null,
      tariffRate:
          j['tariff_rate'] is num ? (j['tariff_rate'] as num).toInt() : null,
      tamperConditionClearedAt: j['tamper_condition_cleared_at'] is String
          ? DateTime.parse(j['tamper_condition_cleared_at'] as String)
          : null,
      creditClearedAt: j['credit_cleared_at'] is String
          ? DateTime.parse(j['credit_cleared_at'] as String)
          : null,
      tamperLatched: j['tamper_latched'] == true,
      pending1stSection: j['pending_1st_section'] is Map<String, dynamic>
          ? PendingKctSection.fromJson(
              j['pending_1st_section'] as Map<String, dynamic>,
            )
          : null,
      pending2ndSection: j['pending_2nd_section'] is Map<String, dynamic>
          ? PendingKctSection.fromJson(
              j['pending_2nd_section'] as Map<String, dynamic>,
            )
          : null,
      pending3rdSection: j['pending_3rd_section'] is Map<String, dynamic>
          ? PendingKctSection.fromJson(
              j['pending_3rd_section'] as Map<String, dynamic>,
            )
          : null,
      pending4thSection: j['pending_4th_section'] is Map<String, dynamic>
          ? PendingKctSection.fromJson(
              j['pending_4th_section'] as Map<String, dynamic>,
            )
          : null,
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
    case 'misty1':
      return Misty1EncryptionAlgorithm();
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

/// Persisted staging slot for one half of a pending Decoder Key
/// Change Token pair. The meter holds at most one of each (1st /
/// 2nd) — a fresh same-section token simply overwrites the slot,
/// matching real meter behavior for KCT retries.
class PendingKctSection {
  // ---- 1st section fields ----
  /// 1st section: MSB-first 32-bit binary string of NKHO.
  final String? newKeyHighOrderBits; // 32-bit binary string (MSB-first)
  /// 1st section: high nibble of the new KEN (0..15).
  final int? keyExpiryNumberHighOrder; // 0..15
  /// 1st section: new KRN (1..9).
  final int? newKeyRevisionNumber; // 1..9
  /// 1st section: new key type (0..3).
  final int? newKeyType; // 0..3
  /// 1st section: rollover flag.
  final bool? rolloverKeyChange;

  // ---- 2nd section fields ----
  /// 2nd section: MSB-first 32-bit binary string of NKLO.
  final String? newKeyLowOrderBits; // 32-bit binary string (MSB-first)
  /// 2nd section: low nibble of the new KEN (0..15).
  final int? keyExpiryNumberLowOrder; // 0..15
  /// 2nd section: new tariff-index string.
  final String? newTariffIndex; // 2-digit decimal string

  // ---- 3rd section fields (MISTY1) ----
  /// 3rd section: MSB-first 32-bit binary string of NKMO2.
  final String? newKeyMiddleOrder2Bits; // 32-bit binary string (MSB-first)
  /// 3rd section: low 12 bits of the new SGC.
  final int? supplyGroupCodeLowOrder; // 0..0xFFF (12-bit value)

  // ---- 4th section fields (MISTY1) ----
  /// 4th section: MSB-first 32-bit binary string of NKMO1.
  final String? newKeyMiddleOrder1Bits; // 32-bit binary string (MSB-first)
  /// 4th section: high 12 bits of the new SGC.
  final int? supplyGroupCodeHighOrder; // 0..0xFFF (12-bit value)

  /// Wall-clock time the section was staged.
  final DateTime stagedAt;

  const PendingKctSection._({
    this.newKeyHighOrderBits,
    this.keyExpiryNumberHighOrder,
    this.newKeyRevisionNumber,
    this.newKeyType,
    this.rolloverKeyChange,
    this.newKeyLowOrderBits,
    this.keyExpiryNumberLowOrder,
    this.newTariffIndex,
    this.newKeyMiddleOrder2Bits,
    this.supplyGroupCodeLowOrder,
    this.newKeyMiddleOrder1Bits,
    this.supplyGroupCodeHighOrder,
    required this.stagedAt,
  });

  /// Builds a staged 1st-section slot.
  factory PendingKctSection.first({
    required String newKeyHighOrderBits,
    required int keyExpiryNumberHighOrder,
    required int newKeyRevisionNumber,
    required int newKeyType,
    required bool rolloverKeyChange,
    required DateTime stagedAt,
  }) =>
      PendingKctSection._(
        newKeyHighOrderBits: newKeyHighOrderBits,
        keyExpiryNumberHighOrder: keyExpiryNumberHighOrder,
        newKeyRevisionNumber: newKeyRevisionNumber,
        newKeyType: newKeyType,
        rolloverKeyChange: rolloverKeyChange,
        stagedAt: stagedAt,
      );

  /// Builds a staged 2nd-section slot.
  factory PendingKctSection.second({
    required String newKeyLowOrderBits,
    required int keyExpiryNumberLowOrder,
    required String newTariffIndex,
    required DateTime stagedAt,
  }) =>
      PendingKctSection._(
        newKeyLowOrderBits: newKeyLowOrderBits,
        keyExpiryNumberLowOrder: keyExpiryNumberLowOrder,
        newTariffIndex: newTariffIndex,
        stagedAt: stagedAt,
      );

  /// Builds a staged 3rd-section slot (MISTY1 rotation).
  factory PendingKctSection.third({
    required String newKeyMiddleOrder2Bits,
    required int supplyGroupCodeLowOrder,
    required DateTime stagedAt,
  }) =>
      PendingKctSection._(
        newKeyMiddleOrder2Bits: newKeyMiddleOrder2Bits,
        supplyGroupCodeLowOrder: supplyGroupCodeLowOrder,
        stagedAt: stagedAt,
      );

  /// Builds a staged 4th-section slot (MISTY1 rotation).
  factory PendingKctSection.fourth({
    required String newKeyMiddleOrder1Bits,
    required int supplyGroupCodeHighOrder,
    required DateTime stagedAt,
  }) =>
      PendingKctSection._(
        newKeyMiddleOrder1Bits: newKeyMiddleOrder1Bits,
        supplyGroupCodeHighOrder: supplyGroupCodeHighOrder,
        stagedAt: stagedAt,
      );

  /// Serialises this staged section to a JSON-friendly map. Only
  /// the fields populated for the section (1st/2nd/3rd/4th) are
  /// emitted.
  Map<String, dynamic> toJson() => {
        if (newKeyHighOrderBits != null)
          'new_key_high_order_bits': newKeyHighOrderBits,
        if (keyExpiryNumberHighOrder != null)
          'key_expiry_number_high_order': keyExpiryNumberHighOrder,
        if (newKeyRevisionNumber != null)
          'new_key_revision_number': newKeyRevisionNumber,
        if (newKeyType != null) 'new_key_type': newKeyType,
        if (rolloverKeyChange != null)
          'roll_over_key_change': rolloverKeyChange,
        if (newKeyLowOrderBits != null)
          'new_key_low_order_bits': newKeyLowOrderBits,
        if (keyExpiryNumberLowOrder != null)
          'key_expiry_number_low_order': keyExpiryNumberLowOrder,
        if (newTariffIndex != null) 'new_tariff_index': newTariffIndex,
        if (newKeyMiddleOrder2Bits != null)
          'new_key_middle_order_2_bits': newKeyMiddleOrder2Bits,
        if (supplyGroupCodeLowOrder != null)
          'supply_group_code_low_order': supplyGroupCodeLowOrder,
        if (newKeyMiddleOrder1Bits != null)
          'new_key_middle_order_1_bits': newKeyMiddleOrder1Bits,
        if (supplyGroupCodeHighOrder != null)
          'supply_group_code_high_order': supplyGroupCodeHighOrder,
        'staged_at': stagedAt.toUtc().toIso8601String(),
      };

  /// Rebuilds a [PendingKctSection] from a JSON map produced by
  /// [toJson].
  /// Rebuilds a [PendingKctSection] from a JSON map produced by
  /// [toJson].
  factory PendingKctSection.fromJson(Map<String, dynamic> j) =>
      PendingKctSection._(
        newKeyHighOrderBits: j['new_key_high_order_bits'] as String?,
        keyExpiryNumberHighOrder: j['key_expiry_number_high_order'] is num
            ? (j['key_expiry_number_high_order'] as num).toInt()
            : null,
        newKeyRevisionNumber: j['new_key_revision_number'] is num
            ? (j['new_key_revision_number'] as num).toInt()
            : null,
        newKeyType: j['new_key_type'] is num
            ? (j['new_key_type'] as num).toInt()
            : null,
        rolloverKeyChange: j['roll_over_key_change'] as bool?,
        newKeyLowOrderBits: j['new_key_low_order_bits'] as String?,
        keyExpiryNumberLowOrder: j['key_expiry_number_low_order'] is num
            ? (j['key_expiry_number_low_order'] as num).toInt()
            : null,
        newTariffIndex: j['new_tariff_index'] as String?,
        newKeyMiddleOrder2Bits: j['new_key_middle_order_2_bits'] as String?,
        supplyGroupCodeLowOrder: j['supply_group_code_low_order'] is num
            ? (j['supply_group_code_low_order'] as num).toInt()
            : null,
        newKeyMiddleOrder1Bits: j['new_key_middle_order_1_bits'] as String?,
        supplyGroupCodeHighOrder: j['supply_group_code_high_order'] is num
            ? (j['supply_group_code_high_order'] as num).toInt()
            : null,
        stagedAt: DateTime.parse(j['staged_at'] as String),
      );
}
