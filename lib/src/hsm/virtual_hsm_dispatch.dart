/// Flat-`Map<String, dynamic>` token generate/decode API for
/// [VirtualHsm], directly mirroring NectarAPI's `tokens-service`
/// `TokenGeneratorManager` / `TokenDecoderManager` / `Generator`
/// param contract.
///
/// The original Java service is driven by JSON request bodies that
/// arrive at `POST /v1/tokens` as `Map<String, Object>`. This layer
/// lets Dart callers use the exact same key names, so a request that
/// works against the upstream Spring Boot service works here unchanged
/// (modulo features that aren't ported — see below).
///
/// Supported via this layer:
///   - DKGA-02, DKGA-04
///   - EA07 (STA), EA09 (DEA, used internally by DKGA-02), EA11 (MISTY1)
///   - Class 0 / SubClass 0 — `TransferElectricityCreditToken`
///   - Class 1 / SubClass 0 + 1 — `InitiateMeterTestOrDisplay1/2Token`
///   - Class 2 / SubClass 0 — `SetMaximumPowerLimitToken`
///   - Class 2 / SubClass 1 — `ClearCreditToken`
///   - Class 2 / SubClass 2 — `SetTariffRateToken`
///   - Class 2 / SubClass 3 + 4 — `Set1stSection` / `Set2ndSectionDecoderKeyToken`
///     (64-bit STA decoder-key rotation pair)
///   - Class 2 / SubClass 5 — `ClearTamperConditionToken`
///   - Class 2 / SubClass 6 — `SetMaximumPhasePowerUnbalanceLimitToken`
///   - Class 2 / SubClass 8 + 9 — `Set3rdSection` / `Set4thSectionDecoderKeyToken`
///     (128-bit MISTY1 decoder-key rotation, completes the 4-section set)
///
/// Rejected with [NotImplementedException]:
///   - DKGA-01, DKGA-03 (not ported)
///   - Class 0 SubClass 1 (water), Class 0 SubClass 2 (gas) (not ported)
///   - Class 2 / SubClass 7 (`SetWaterMeterFactor`) — water out of scope
///   - `type: "prism-thrift"` — use [PrismHsm] instead.
library;

import 'dart:math';
import 'dart:typed_data';

import '../base/bit_string.dart';
import '../domain/amount.dart';
import '../domain/base_date.dart';
import '../domain/class1_payload.dart';
import '../domain/class2_payload.dart';
import '../domain/class2_register_payloads.dart';
import '../domain/primitives.dart';
import '../domain/random_no.dart';
import '../domain/token_identifier.dart';
import '../encryption/data_encryption_algorithm.dart';
import '../encryption/encryption_algorithm.dart';
import '../encryption/misty1_algorithm.dart';
import '../encryption/standard_transfer_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../keys/vending_key.dart';
import '../token/class0_tokens.dart';
import '../token/class1_tokens.dart';
import '../token/class2_tokens.dart';
import '../token/token.dart';
import '../tokendec/token_decoder_dispatcher.dart';
import '../tokengen/class0_token_generators.dart';
import '../tokengen/class1_token_generators.dart';
import '../tokengen/class2_token_generators.dart';
import 'hsm.dart';

/// String constants for the param-map keys consumed by
/// [VirtualHsmDispatch.generateToken] / [VirtualHsmDispatch.decodeToken].
/// Names match the Java `tokens-service` exactly.
class VirtualHsmParams {
  VirtualHsmParams._();

  // dispatch
  static const tokenClass = 'class';
  static const tokenSubclass = 'subclass';
  static const type = 'type';

  // decoder key derivation
  static const decoderKeyGenerationAlgorithm =
      'decoder_key_generation_algorithm';
  static const encryptionAlgorithm = 'encryption_algorithm';
  static const keyType = 'key_type';
  static const supplyGroupCode = 'supply_group_code';
  static const tariffIndex = 'tariff_index';
  static const keyRevisionNo = 'key_revision_no';
  static const issuerIdentificationNo = 'issuer_identification_no';
  static const decoderReferenceNumber = 'decoder_reference_number';
  static const baseDate = 'base_date';
  static const vendingKey = 'vending_key';

  // payload
  static const amount = 'amount';
  static const tokenId = 'token_id';
  static const randomNo = 'random_no';
  static const manufacturerCode = 'manufacturer_code';
  static const control = 'control';

  // Class 2 key-change tokens (params match the upstream Java
  // `Set*SectionDecoderKeyToken.getParams()` keys exactly).
  static const newDecoderKey = 'new_decoder_key';
  static const newSupplyGroupCode = 'new_supply_group_code';
  static const keyExpiryNumberHighOrder = 'key_expiry_number_high_order';
  static const keyExpiryNumberLowOrder = 'key_expiry_number_low_order';
  static const newKeyRevisionNumber = 'new_key_revision_number';
  static const newKeyType = 'new_key_type';
  static const newTariffIndex = 'new_tariff_index';
  static const rollOverKeyChange = 'roll_over_key_change';

  // Class 2 register-payload management tokens.
  static const maximumPowerLimit = 'maximum_power_limit';
  static const register = 'register';
  static const tariffRate = 'tariff_rate';
  static const pad = 'pad';
  static const maximumPhasePowerUnbalanceLimit =
      'maximum_phase_power_unbalance_limit';
}

/// Adds the params-driven `generateToken` / `decodeToken` entry points
/// on top of the typed key-derivation API on [VirtualHsm].
extension VirtualHsmDispatch on VirtualHsm {
  /// Issue a token from a flat param map. See [VirtualHsmParams] for
  /// key names. Returns the fully-generated [Token] (with
  /// `tokenNo` already populated).
  Token generateToken(String requestID, Map<String, dynamic> params) {
    _rejectPrism(params);

    final decoderKey = deriveDecoderKeyFromParams(params);
    final ea = _encryptionAlgorithm(params);
    final klass = _required(params, VirtualHsmParams.tokenClass).toString();
    final sub = _required(params, VirtualHsmParams.tokenSubclass).toString();
    final dispatch = '$klass,$sub';

    switch (dispatch) {
      case '0,0':
        return _generateElectricityCredit(requestID, params, decoderKey, ea);
      case '0,4':
        return _generateElectricityCurrencyCredit(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '1,0':
        return _generateClass1Display1(requestID, params, decoderKey, ea);
      case '1,1':
        return _generateClass1Display2(requestID, params, decoderKey, ea);
      case '0,1':
      case '0,2':
        throw NotImplementedException(
          'Class 0 SubClass $sub (water / gas) tokens are not ported',
        );
      case '2,0':
        return _generateClass2SetMaximumPowerLimit(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '2,1':
        return _generateClass2ClearCredit(requestID, params, decoderKey, ea);
      case '2,2':
        return _generateClass2SetTariffRate(requestID, params, decoderKey, ea);
      case '2,3':
        return _generateClass2KeyChange1stSection(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '2,4':
        return _generateClass2KeyChange2ndSection(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '2,5':
        return _generateClass2ClearTamperCondition(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '2,6':
        return _generateClass2SetMaximumPhasePowerUnbalanceLimit(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '2,7':
        throw NotImplementedException(
          'Class 2 SubClass 7 (SetWaterMeterFactor) is not ported — '
          'water meters are out of scope',
        );
      case '2,8':
        return _generateClass2KeyChange3rdSection(
          requestID,
          params,
          decoderKey,
          ea,
        );
      case '2,9':
        return _generateClass2KeyChange4thSection(
          requestID,
          params,
          decoderKey,
          ea,
        );
      default:
        throw InvalidTokenException('Unknown class/subclass: $klass/$sub');
    }
  }

  /// Decode a previously-issued 20-digit token. Re-derives the same
  /// decoder key from [params] (same keys you would have used to
  /// generate it) and dispatches by transposed token class.
  Token decodeToken(
    String requestID,
    String tokenNo,
    Map<String, dynamic> params,
  ) {
    _rejectPrism(params);
    final decoderKey = deriveDecoderKeyFromParams(params);
    final ea = _encryptionAlgorithm(params);
    return TokenDecoderDispatcher(
      decoderKey,
      ea,
    ).decodeOrThrow(requestID, tokenNo);
  }

  // ---- internals -------------------------------------------------

  void _rejectPrism(Map<String, dynamic> params) {
    final t = params[VirtualHsmParams.type];
    if (t is String && t.trim().toLowerCase() == 'prism-thrift') {
      throw const NotImplementedException(
        'type="prism-thrift" cannot be served by VirtualHsm; use '
        'PrismHsm (currently stubbed) for hardware-HSM token vending',
      );
    }
  }

  /// Derive the decoder key referenced by [params] using this HSM's
  /// vending master key. Reads `decoder_key_generation_algorithm`
  /// plus the per-DKGA parameter set (IIN, IAIN/DRN, SGC, KRN, TI,
  /// KT, and for DKGA-04 also EA + base date). Exposed for callers
  /// that need to pre-compute a target key for embedding in another
  /// token — notably the KCT bundle issuer, which derives the *new*
  /// decoder key from a (new_sgc, new_krn, new_ti, new_kt) override.
  DecoderKey deriveDecoderKeyFromParams(Map<String, dynamic> params) {
    final dkga = _required(
      params,
      VirtualHsmParams.decoderKeyGenerationAlgorithm,
    ).toString();
    switch (dkga) {
      case '02':
        return deriveDecoderKeyDkga02(
          issuerIdentificationNumber: IssuerIdentificationNumber(
            _required(
              params,
              VirtualHsmParams.issuerIdentificationNo,
            ).toString(),
          ),
          individualAccountIdentificationNumber:
              IndividualAccountIdentificationNumber(
                _required(
                  params,
                  VirtualHsmParams.decoderReferenceNumber,
                ).toString(),
              ),
          keyType: KeyType(_intParam(params, VirtualHsmParams.keyType)),
          supplyGroupCode: SupplyGroupCode(
            _required(params, VirtualHsmParams.supplyGroupCode).toString(),
          ),
          tariffIndex: TariffIndex(
            _required(params, VirtualHsmParams.tariffIndex).toString(),
          ),
          keyRevisionNumber: KeyRevisionNumber(
            _intParam(params, VirtualHsmParams.keyRevisionNo),
          ),
        );
      case '04':
        final iin = IssuerIdentificationNumber(
          _required(params, VirtualHsmParams.issuerIdentificationNo).toString(),
        );
        final iain = IndividualAccountIdentificationNumber(
          _required(params, VirtualHsmParams.decoderReferenceNumber).toString(),
        );
        return deriveDecoderKeyDkga04(
          baseDate: _baseDate(params),
          tariffIndex: TariffIndex(
            _required(params, VirtualHsmParams.tariffIndex).toString(),
          ),
          supplyGroupCode: SupplyGroupCode(
            _required(params, VirtualHsmParams.supplyGroupCode).toString(),
          ),
          keyType: KeyType(_intParam(params, VirtualHsmParams.keyType)),
          keyRevisionNumber: KeyRevisionNumber(
            _intParam(params, VirtualHsmParams.keyRevisionNo),
          ),
          encryptionAlgorithm: _encryptionAlgorithm(params),
          meterPan: MeterPrimaryAccountNumber(
            issuerIdentificationNumber: iin,
            individualAccountIdentificationNumber: iain,
          ),
        );
      case '01':
      case '03':
        throw NotImplementedException(
          'DKGA-$dkga is not ported (only DKGA-02 and DKGA-04 are '
          'available in this port)',
        );
      default:
        throw InvalidDecoderKeyGenerationAlgorithm(
          'Unknown decoder_key_generation_algorithm: $dkga',
        );
    }
  }

  EncryptionAlgorithm _encryptionAlgorithm(Map<String, dynamic> params) {
    final ea = (params[VirtualHsmParams.encryptionAlgorithm] ?? 'sta')
        .toString()
        .toLowerCase();
    switch (ea) {
      case 'sta':
        return StandardTransferAlgorithm();
      case 'dea':
        return DataEncryptionAlgorithm();
      case 'misty1':
        return Misty1EncryptionAlgorithm();
      default:
        throw InvalidTokenException('Unknown encryption_algorithm: $ea');
    }
  }

  // ---- token builders -------------------------------------------

  TransferElectricityCreditToken _generateElectricityCredit(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final token = TransferElectricityCreditToken(requestID)
      ..amountPurchased = Amount(_doubleParam(params, VirtualHsmParams.amount))
      ..tokenIdentifier = TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      )
      ..randomNo = _randomFromParams(params);
    TransferElectricityCreditTokenGenerator(decoderKey, ea).generate(token);
    return token;
  }

  ElectricityCurrencyCreditToken _generateElectricityCurrencyCredit(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final token = ElectricityCurrencyCreditToken(requestID)
      ..amountPurchased = Amount(_doubleParam(params, VirtualHsmParams.amount))
      ..tokenIdentifier = TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      )
      ..randomNo = _randomFromParams(params);
    ElectricityCurrencyCreditTokenGenerator(decoderKey, ea).generate(token);
    return token;
  }

  InitiateMeterTestOrDisplay1Token _generateClass1Display1(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final mfg = ManufacturerCode.fromInt(
      _intParam(params, VirtualHsmParams.manufacturerCode),
      widthBits: 8,
    );
    final token = InitiateMeterTestOrDisplay1Token(requestID)
      ..manufacturerCode = mfg
      ..control = Control(
        BitString.fromValue(_intParam(params, VirtualHsmParams.control), 36),
        mfg,
      );
    InitiateMeterTestOrDisplay1TokenGenerator(decoderKey, ea).generate(token);
    return token;
  }

  InitiateMeterTestOrDisplay2Token _generateClass1Display2(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final mfg = ManufacturerCode.fromInt(
      _intParam(params, VirtualHsmParams.manufacturerCode),
      widthBits: 16,
    );
    final token = InitiateMeterTestOrDisplay2Token(requestID)
      ..manufacturerCode = mfg
      ..control = Control(
        BitString.fromValue(_intParam(params, VirtualHsmParams.control), 28),
        mfg,
      );
    InitiateMeterTestOrDisplay2TokenGenerator(decoderKey, ea).generate(token);
    return token;
  }

  Set1stSectionDecoderKeyToken _generateClass2KeyChange1stSection(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final newKey = DecoderKey(
      parseHexKey(_required(params, VirtualHsmParams.newDecoderKey).toString()),
    );
    return Set1stSectionDecoderKeyTokenGenerator(
      decoderKey: decoderKey,
      encryptionAlgorithm: ea,
      keyExpiryNumberHighOrder: KeyExpiryNumberHighOrder(
        BitString.fromValue(
          _intParam(params, VirtualHsmParams.keyExpiryNumberHighOrder),
          4,
        ),
      ),
      keyRevisionNumber: KeyRevisionNumber(
        _intParam(params, VirtualHsmParams.newKeyRevisionNumber),
      ),
      rolloverKeyChange: RolloverKeyChange.fromBool(
        _intParam(params, VirtualHsmParams.rollOverKeyChange) != 0,
      ),
      keyType: KeyType(_intParam(params, VirtualHsmParams.newKeyType)),
      newDecoderKey: newKey,
    ).generateNew(requestID);
  }

  Set2ndSectionDecoderKeyToken _generateClass2KeyChange2ndSection(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final newKey = DecoderKey(
      parseHexKey(_required(params, VirtualHsmParams.newDecoderKey).toString()),
    );
    return Set2ndSectionDecoderKeyTokenGenerator(
      decoderKey: decoderKey,
      encryptionAlgorithm: ea,
      keyExpiryNumberLowOrder: KeyExpiryNumberLowOrder(
        BitString.fromValue(
          _intParam(params, VirtualHsmParams.keyExpiryNumberLowOrder),
          4,
        ),
      ),
      tariffIndex: TariffIndex(
        _required(params, VirtualHsmParams.newTariffIndex).toString(),
      ),
      newDecoderKey: newKey,
    ).generateNew(requestID);
  }

  Set3rdSectionDecoderKeyToken _generateClass2KeyChange3rdSection(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final newKey = DecoderKey(
      parseHexKey(_required(params, VirtualHsmParams.newDecoderKey).toString()),
    );
    return Set3rdSectionDecoderKeyTokenGenerator(
      decoderKey: decoderKey,
      encryptionAlgorithm: ea,
      supplyGroupCode: SupplyGroupCode(
        _required(params, VirtualHsmParams.newSupplyGroupCode).toString(),
      ),
      newDecoderKey: newKey,
    ).generateNew(requestID);
  }

  Set4thSectionDecoderKeyToken _generateClass2KeyChange4thSection(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final newKey = DecoderKey(
      parseHexKey(_required(params, VirtualHsmParams.newDecoderKey).toString()),
    );
    return Set4thSectionDecoderKeyTokenGenerator(
      decoderKey: decoderKey,
      encryptionAlgorithm: ea,
      supplyGroupCode: SupplyGroupCode(
        _required(params, VirtualHsmParams.newSupplyGroupCode).toString(),
      ),
      newDecoderKey: newKey,
    ).generateNew(requestID);
  }

  // ---- Class 2 register-payload management tokens ---------------

  SetMaximumPowerLimitToken _generateClass2SetMaximumPowerLimit(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final gen = SetMaximumPowerLimitTokenGenerator(decoderKey, ea);
    final token = gen.buildToken(
      requestID,
      randomNo: _randomFromParams(params),
      tokenIdentifier: TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      ),
      maximumPowerLimit: MaximumPowerLimit(
        _intParam(params, VirtualHsmParams.maximumPowerLimit),
      ),
    );
    return gen.generate(token);
  }

  ClearCreditToken _generateClass2ClearCredit(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final gen = ClearCreditTokenGenerator(decoderKey, ea);
    final registerValue = params[VirtualHsmParams.register];
    final regBits = registerValue == null
        ? BitString.fromValue(0, 16)
        : BitString.fromValue(
            registerValue is int
                ? registerValue
                : int.parse(registerValue.toString()),
            16,
          );
    final token = gen.buildToken(
      requestID,
      randomNo: _randomFromParams(params),
      tokenIdentifier: TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      ),
      register: Register(regBits),
    );
    return gen.generate(token);
  }

  SetTariffRateToken _generateClass2SetTariffRate(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final gen = SetTariffRateTokenGenerator(decoderKey, ea);
    final token = gen.buildToken(
      requestID,
      randomNo: _randomFromParams(params),
      tokenIdentifier: TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      ),
      rate: Rate.fromValue(_intParam(params, VirtualHsmParams.tariffRate)),
    );
    return gen.generate(token);
  }

  ClearTamperConditionToken _generateClass2ClearTamperCondition(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final gen = ClearTamperConditionTokenGenerator(decoderKey, ea);
    final padValue = params[VirtualHsmParams.pad];
    final padBits = padValue == null
        ? BitString.fromValue(0, 16)
        : BitString.fromValue(
            padValue is int ? padValue : int.parse(padValue.toString()),
            16,
          );
    final token = gen.buildToken(
      requestID,
      randomNo: _randomFromParams(params),
      tokenIdentifier: TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      ),
      pad: Pad(padBits),
    );
    return gen.generate(token);
  }

  SetMaximumPhasePowerUnbalanceLimitToken
  _generateClass2SetMaximumPhasePowerUnbalanceLimit(
    String requestID,
    Map<String, dynamic> params,
    DecoderKey decoderKey,
    EncryptionAlgorithm ea,
  ) {
    final gen = SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
      decoderKey,
      ea,
    );
    final token = gen.buildToken(
      requestID,
      randomNo: _randomFromParams(params),
      tokenIdentifier: TokenIdentifier(
        _baseDate(params),
        timeOfIssue: _dateTimeParam(params, VirtualHsmParams.tokenId),
      ),
      maximumPhasePowerUnbalanceLimit: MaximumPhasePowerUnbalanceLimit(
        _intParam(params, VirtualHsmParams.maximumPhasePowerUnbalanceLimit),
      ),
    );
    return gen.generate(token);
  }
}

// =================================================================
// Param helpers (top-level — extensions can't have private members
// accessible to other extensions on the same class, and these are
// reusable per-call).
// =================================================================

Object _required(Map<String, dynamic> params, String key) {
  final v = params[key];
  if (v == null) {
    throw InvalidTokenException('Missing required param: $key');
  }
  return v;
}

int _intParam(Map<String, dynamic> params, String key) {
  final v = _required(params, key);
  if (v is int) return v;
  if (v is String) return int.parse(v);
  if (v is num) return v.toInt();
  throw InvalidTokenException(
    'Param $key must be an int, got ${v.runtimeType}',
  );
}

double _doubleParam(Map<String, dynamic> params, String key) {
  final v = _required(params, key);
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.parse(v);
  throw InvalidTokenException(
    'Param $key must be a number, got ${v.runtimeType}',
  );
}

DateTime _dateTimeParam(Map<String, dynamic> params, String key) {
  final v = _required(params, key);
  if (v is DateTime) return v.toUtc();
  if (v is String) return DateTime.parse(v).toUtc();
  throw InvalidTokenException(
    'Param $key must be a DateTime or ISO-8601 string, got ${v.runtimeType}',
  );
}

BaseDate _baseDate(Map<String, dynamic> params) {
  final raw = (params[VirtualHsmParams.baseDate] ?? '1993').toString();
  switch (raw) {
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

RandomNo _randomFromParams(Map<String, dynamic> params) {
  final v = params[VirtualHsmParams.randomNo];
  if (v == null) return RandomNo.random(Random.secure());
  if (v is int) return RandomNo.fromInt(v);
  if (v is String) return RandomNo.fromInt(int.parse(v));
  throw InvalidTokenException('Param random_no must be an int / string');
}

/// Parse a hex string into bytes. Accepts upper- or lower-case, with
/// or without leading `0x`. Exposed for callers who want to pre-build
/// a [VendingKey] from a `vending_key` param value.
Uint8List parseHexKey(String hex) {
  var s = hex.trim();
  if (s.startsWith('0x') || s.startsWith('0X')) s = s.substring(2);
  if (s.length.isOdd) {
    throw InvalidTokenException('Hex key must have an even number of digits');
  }
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Inverse of [parseHexKey]: lower-case hex, no separator, no prefix.
String hexEncodeKey(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write((b & 0xFF).toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}
