import '../base/bit_string.dart';
import '../domain/class2_payload.dart';
import '../domain/class2_register_payloads.dart';
import '../domain/crc.dart';
import '../domain/primitives.dart';
import '../domain/random_no.dart';
import '../domain/token_identifier.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class2_tokens.dart';
import 'token_generator.dart';

/// Marker base for all Class 2 token generators.
abstract class Class2TokenGenerator<T extends Class2Token>
    extends TokenGenerator<T> {
  /// Forwards [decoderKey] and [encryptionAlgorithm] to [TokenGenerator].
  Class2TokenGenerator(super.decoderKey, super.encryptionAlgorithm);
}

/// Shared generator for the five Class 2 management tokens that
/// follow the same 64-bit data block layout as Class 0 (only the
/// 16-bit payload register differs).
///
/// 64-bit data block: `crc || register(16) || tid(24) || rnd(4) || sub(4)`
/// CRC input (50 bits): `register || tid || rnd || sub || class`.
///
/// Example (SetMaximumPowerLimit, from
/// `test/class2_register_tokens_test.dart`):
/// ```dart
/// final token = SetMaximumPowerLimitTokenGenerator(
///   decoderKey, StandardTransferAlgorithm(),
/// ).buildToken(
///   'mpl-rt',
///   randomNo:          RandomNo.fromInt(7),
///   tokenIdentifier:   TokenIdentifier(BaseDate.date1993),
///   maximumPowerLimit: MaximumPowerLimit(4321),
/// );
///
/// SetMaximumPowerLimitTokenGenerator(
///   decoderKey, StandardTransferAlgorithm(),
/// ).generate(token);
/// token.tokenNo; // 20-digit displayable form
/// ```
abstract class Class2RegisterTokenGenerator<T extends Class2RegisterToken>
    extends Class2TokenGenerator<T> {
  /// Forwards [decoderKey] and [encryptionAlgorithm].
  Class2RegisterTokenGenerator(super.decoderKey, super.encryptionAlgorithm);

  /// Assembles the 64-bit data block per the Class 2 register layout
  /// and stamps the CRC.
  ///
  /// Throws [InvalidTokenException] when a required payload field is
  /// missing.
  @override
  BitString buildDataBlock(T token) {
    if (token.registerBits == null ||
        token.tokenIdentifier == null ||
        token.randomNo == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw InvalidTokenException(
        '${token.runtimeType} is missing required fields before generation',
      );
    }
    final reg = token.registerBits!;
    final tid = token.tokenIdentifier!.bitString;
    final rnd = token.randomNo!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final cls = token.tokenClass!.bitString;

    final crcInput = reg.concat([tid, rnd, sub, cls]);
    final crc = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crc);

    return crc.concat([reg, tid, rnd, sub]);
  }
}

/// Generator for the SetMaximumPowerLimit engineering token.
class SetMaximumPowerLimitTokenGenerator
    extends Class2RegisterTokenGenerator<SetMaximumPowerLimitToken> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  SetMaximumPowerLimitTokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);

  /// Convenience: build a fully-populated
  /// [SetMaximumPowerLimitToken]; still needs [generate] to encrypt.
  SetMaximumPowerLimitToken buildToken(
    String requestID, {
    required RandomNo randomNo,
    required TokenIdentifier tokenIdentifier,
    required MaximumPowerLimit maximumPowerLimit,
  }) =>
      SetMaximumPowerLimitToken(requestID)
        ..randomNo = randomNo
        ..tokenIdentifier = tokenIdentifier
        ..maximumPowerLimit = maximumPowerLimit;
}

/// Generator for the ClearCredit engineering token.
class ClearCreditTokenGenerator
    extends Class2RegisterTokenGenerator<ClearCreditToken> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  ClearCreditTokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);

  /// Convenience: build a fully-populated [ClearCreditToken]; still
  /// needs [generate] to encrypt.
  ClearCreditToken buildToken(
    String requestID, {
    required RandomNo randomNo,
    required TokenIdentifier tokenIdentifier,
    required Register register,
  }) =>
      ClearCreditToken(requestID)
        ..randomNo = randomNo
        ..tokenIdentifier = tokenIdentifier
        ..register = register;
}

/// Generator for the SetTariffRate engineering token.
class SetTariffRateTokenGenerator
    extends Class2RegisterTokenGenerator<SetTariffRateToken> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  SetTariffRateTokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);

  /// Convenience: build a fully-populated [SetTariffRateToken]; still
  /// needs [generate] to encrypt.
  SetTariffRateToken buildToken(
    String requestID, {
    required RandomNo randomNo,
    required TokenIdentifier tokenIdentifier,
    required Rate rate,
  }) =>
      SetTariffRateToken(requestID)
        ..randomNo = randomNo
        ..tokenIdentifier = tokenIdentifier
        ..rate = rate;
}

/// Generator for the ClearTamperCondition engineering token.
class ClearTamperConditionTokenGenerator
    extends Class2RegisterTokenGenerator<ClearTamperConditionToken> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  ClearTamperConditionTokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);

  /// Convenience: build a fully-populated
  /// [ClearTamperConditionToken]; still needs [generate] to encrypt.
  ClearTamperConditionToken buildToken(
    String requestID, {
    required RandomNo randomNo,
    required TokenIdentifier tokenIdentifier,
    required Pad pad,
  }) =>
      ClearTamperConditionToken(requestID)
        ..randomNo = randomNo
        ..tokenIdentifier = tokenIdentifier
        ..pad = pad;
}

/// Generator for the SetMaximumPhasePowerUnbalanceLimit engineering
/// token.
class SetMaximumPhasePowerUnbalanceLimitTokenGenerator
    extends Class2RegisterTokenGenerator<
        SetMaximumPhasePowerUnbalanceLimitToken> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  SetMaximumPhasePowerUnbalanceLimitTokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);

  /// Convenience: build a fully-populated
  /// [SetMaximumPhasePowerUnbalanceLimitToken]; still needs
  /// [generate] to encrypt.
  SetMaximumPhasePowerUnbalanceLimitToken buildToken(
    String requestID, {
    required RandomNo randomNo,
    required TokenIdentifier tokenIdentifier,
    required MaximumPhasePowerUnbalanceLimit maximumPhasePowerUnbalanceLimit,
  }) =>
      SetMaximumPhasePowerUnbalanceLimitToken(requestID)
        ..randomNo = randomNo
        ..tokenIdentifier = tokenIdentifier
        ..maximumPhasePowerUnbalanceLimit = maximumPhasePowerUnbalanceLimit;
}

// ---------------------------------------------------------------------------
// 1st Section Decoder Key Change Token Generator
// ---------------------------------------------------------------------------

/// Encrypts the high-order half of a new decoder key under the
/// *current* decoder key. The matching low half ships in
/// [Set2ndSectionDecoderKeyTokenGenerator]; both must be applied to
/// the meter as a pair before the rotation takes effect.
class Set1stSectionDecoderKeyTokenGenerator
    extends Class2TokenGenerator<Set1stSectionDecoderKeyToken> {
  /// High nibble of the new KEN.
  final KeyExpiryNumberHighOrder keyExpiryNumberHighOrder;

  /// New KRN attached to the rotated key.
  final KeyRevisionNumber keyRevisionNumber;

  /// Rollover-key-change flag.
  final RolloverKeyChange rolloverKeyChange;

  /// New key type (DEA / MISTY1 / ...).
  final KeyType keyType;

  /// The new decoder key being rotated in; only its high half rides
  /// in this token.
  final DecoderKey newDecoderKey;

  /// Builds a 1st-section-KCT generator wired for STA (EA07) or
  /// MISTY1 (EA11); any other algorithm raises
  /// [NotImplementedException].
  Set1stSectionDecoderKeyTokenGenerator({
    required DecoderKey decoderKey,
    required EncryptionAlgorithm encryptionAlgorithm,
    required this.keyExpiryNumberHighOrder,
    required this.keyRevisionNumber,
    required this.rolloverKeyChange,
    required this.keyType,
    required this.newDecoderKey,
  }) : super(decoderKey, encryptionAlgorithm) {
    if (encryptionAlgorithm.code != EncryptionAlgorithmCode.sta &&
        encryptionAlgorithm.code != EncryptionAlgorithmCode.misty1) {
      throw NotImplementedException(
        'Set1stSectionDecoderKeyTokenGenerator currently supports STA '
        '(EA07) and MISTY1 (EA11) only; got ${encryptionAlgorithm.code.name}',
      );
    }
  }

  /// Build a fully-populated [Set1stSectionDecoderKeyToken]. Mirrors
  /// the Java constructor that auto-splits the new decoder key.
  Set1stSectionDecoderKeyToken buildToken(String requestID) {
    final NewKeyHighOrder nkho;
    if (encryptionAlgorithm.code == EncryptionAlgorithmCode.sta) {
      nkho = splitStaDecoderKey(newDecoderKey).high;
    } else {
      nkho = splitMisty1DecoderKey(newDecoderKey).high;
    }
    final token = Set1stSectionDecoderKeyToken(requestID)
      ..keyExpiryNumberHighOrder = keyExpiryNumberHighOrder
      ..keyRevisionNumber = keyRevisionNumber
      ..rolloverKeyChange = rolloverKeyChange
      ..keyType = keyType
      ..newKeyHighOrder = nkho
      ..reserved3Kct = Reserved3Kct.zero();
    return token;
  }

  /// One-shot helper: build the token then call [generate].
  Set1stSectionDecoderKeyToken generateNew(String requestID) {
    return generate(buildToken(requestID));
  }

  @override
  BitString buildDataBlock(Set1stSectionDecoderKeyToken token) {
    if (token.keyExpiryNumberHighOrder == null ||
        token.keyRevisionNumber == null ||
        token.rolloverKeyChange == null ||
        token.keyType == null ||
        token.newKeyHighOrder == null ||
        token.reserved3Kct == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw const InvalidTokenException(
        'Set1stSectionDecoderKeyToken is missing required fields before '
        'generation',
      );
    }
    final cls = token.tokenClass!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final kenho = token.keyExpiryNumberHighOrder!.bitString;
    final krn = BitString.fromValue(token.keyRevisionNumber!.value, 4);
    final ro = token.rolloverKeyChange!.bitString;
    final res = token.reserved3Kct!.bitString;
    final kt = BitString.fromValue(token.keyType!.value, 2);
    final nkho = token.newKeyHighOrder!.bitString;

    // CRC input: nkho || kt || res || ro || krn || kenho || sub || class
    //          = 32 + 2 + 1 + 1 + 4 + 4 + 4 + 2 = 50 bits.
    final crcInput = nkho.concat([kt, res, ro, krn, kenho, sub, cls]);
    final crcBits = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crcBits);

    // 64-bit data block: crc || nkho || kt || res || ro || krn || kenho || sub
    //                  = 16 + 32 + 2 + 1 + 1 + 4 + 4 + 4 = 64 bits.
    return crcBits.concat([nkho, kt, res, ro, krn, kenho, sub]);
  }
}

// ---------------------------------------------------------------------------
// 2nd Section Decoder Key Change Token Generator
// ---------------------------------------------------------------------------

/// Encrypts the low-order half of a new decoder key under the current
/// decoder key. Paired with [Set1stSectionDecoderKeyTokenGenerator].
class Set2ndSectionDecoderKeyTokenGenerator
    extends Class2TokenGenerator<Set2ndSectionDecoderKeyToken> {
  /// Low nibble of the new KEN.
  final KeyExpiryNumberLowOrder keyExpiryNumberLowOrder;

  /// New tariff-index attached to the rotated key.
  final TariffIndex tariffIndex;

  /// The new decoder key being rotated in; only its low half rides in
  /// this token.
  final DecoderKey newDecoderKey;

  /// Builds a 2nd-section-KCT generator wired for STA (EA07) or
  /// MISTY1 (EA11); any other algorithm raises
  /// [NotImplementedException].
  Set2ndSectionDecoderKeyTokenGenerator({
    required DecoderKey decoderKey,
    required EncryptionAlgorithm encryptionAlgorithm,
    required this.keyExpiryNumberLowOrder,
    required this.tariffIndex,
    required this.newDecoderKey,
  }) : super(decoderKey, encryptionAlgorithm) {
    if (encryptionAlgorithm.code != EncryptionAlgorithmCode.sta &&
        encryptionAlgorithm.code != EncryptionAlgorithmCode.misty1) {
      throw NotImplementedException(
        'Set2ndSectionDecoderKeyTokenGenerator currently supports STA '
        '(EA07) and MISTY1 (EA11) only; got ${encryptionAlgorithm.code.name}',
      );
    }
  }

  /// Build a fully-populated [Set2ndSectionDecoderKeyToken]. Auto-splits
  /// the new decoder key and picks the low half.
  Set2ndSectionDecoderKeyToken buildToken(String requestID) {
    final NewKeyLowOrder nklo;
    if (encryptionAlgorithm.code == EncryptionAlgorithmCode.sta) {
      nklo = splitStaDecoderKey(newDecoderKey).low;
    } else {
      nklo = splitMisty1DecoderKey(newDecoderKey).low;
    }
    return Set2ndSectionDecoderKeyToken(requestID)
      ..keyExpiryNumberLowOrder = keyExpiryNumberLowOrder
      ..tariffIndex = tariffIndex
      ..newKeyLowOrder = nklo;
  }

  /// One-shot helper: build the token then call [generate].
  Set2ndSectionDecoderKeyToken generateNew(String requestID) {
    return generate(buildToken(requestID));
  }

  @override
  BitString buildDataBlock(Set2ndSectionDecoderKeyToken token) {
    if (token.keyExpiryNumberLowOrder == null ||
        token.tariffIndex == null ||
        token.newKeyLowOrder == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw const InvalidTokenException(
        'Set2ndSectionDecoderKeyToken is missing required fields before '
        'generation',
      );
    }
    final cls = token.tokenClass!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final kenlo = token.keyExpiryNumberLowOrder!.bitString;
    final ti = BitString.fromValue(int.parse(token.tariffIndex!.value), 8);
    final nklo = token.newKeyLowOrder!.bitString;

    // CRC input: nklo || ti || kenlo || sub || class
    //          = 32 + 8 + 4 + 4 + 2 = 50 bits.
    final crcInput = nklo.concat([ti, kenlo, sub, cls]);
    final crcBits = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crcBits);

    // 64-bit data block: crc || nklo || ti || kenlo || sub
    //                  = 16 + 32 + 8 + 4 + 4 = 64 bits.
    return crcBits.concat([nklo, ti, kenlo, sub]);
  }
}

// ---------------------------------------------------------------------------
// 3rd Section Decoder Key Change Token Generator
// ---------------------------------------------------------------------------

/// Encrypts `NewKeyMiddleOrder2` (bits 32..63 of the 128-bit MISTY1
/// key) together with the low-order 12 bits of a new Supply Group
/// Code. MISTY1 path only — Java throws `NotSupportedException` for
/// STA.
class Set3rdSectionDecoderKeyTokenGenerator
    extends Class2TokenGenerator<Set3rdSectionDecoderKeyToken> {
  /// New supply-group-code being rotated in; only its low 12 bits
  /// ride in this token.
  final SupplyGroupCode supplyGroupCode;

  /// The new 128-bit MISTY1 decoder key being rotated in; only its
  /// middle-order-2 32 bits ride in this token.
  final DecoderKey newDecoderKey;

  /// Builds a 3rd-section-KCT generator; requires MISTY1 (EA11).
  Set3rdSectionDecoderKeyTokenGenerator({
    required DecoderKey decoderKey,
    required EncryptionAlgorithm encryptionAlgorithm,
    required this.supplyGroupCode,
    required this.newDecoderKey,
  }) : super(decoderKey, encryptionAlgorithm) {
    if (encryptionAlgorithm.code != EncryptionAlgorithmCode.misty1) {
      throw NotImplementedException(
        'Set3rdSection KCT requires MISTY1 (EA11); '
        'got ${encryptionAlgorithm.code.name}',
      );
    }
  }

  /// Build a fully-populated [Set3rdSectionDecoderKeyToken]. Auto-splits
  /// the new decoder key and picks the middle-order-2 32 bits.
  Set3rdSectionDecoderKeyToken buildToken(String requestID) {
    final split = splitMisty1DecoderKey(newDecoderKey);
    return Set3rdSectionDecoderKeyToken(requestID)
      ..supplyGroupCodeLowOrder = SupplyGroupCodeLowOrder.fromSupplyGroupCode(
        supplyGroupCode,
      )
      ..newKeyMiddleOrder2 = split.middle2;
  }

  /// One-shot helper: build the token then call [generate].
  Set3rdSectionDecoderKeyToken generateNew(String requestID) {
    return generate(buildToken(requestID));
  }

  @override
  BitString buildDataBlock(Set3rdSectionDecoderKeyToken token) {
    if (token.supplyGroupCodeLowOrder == null ||
        token.newKeyMiddleOrder2 == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw const InvalidTokenException(
        'Set3rdSectionDecoderKeyToken is missing required fields before '
        'generation',
      );
    }
    final cls = token.tokenClass!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final sgclo = token.supplyGroupCodeLowOrder!.bitString;
    final nkmo2 = token.newKeyMiddleOrder2!.bitString;

    // CRC input: nkmo2 || sgclo || sub || class
    //          = 32 + 12 + 4 + 2 = 50 bits.
    final crcInput = nkmo2.concat([sgclo, sub, cls]);
    final crcBits = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crcBits);

    // 64-bit data block: crc || nkmo2 || sgclo || sub
    //                  = 16 + 32 + 12 + 4 = 64 bits.
    return crcBits.concat([nkmo2, sgclo, sub]);
  }
}

// ---------------------------------------------------------------------------
// 4th Section Decoder Key Change Token Generator
// ---------------------------------------------------------------------------

/// Encrypts `NewKeyMiddleOrder1` (bits 64..95 of the 128-bit MISTY1
/// key) together with the high-order 12 bits of a new Supply Group
/// Code. MISTY1 path only.
class Set4thSectionDecoderKeyTokenGenerator
    extends Class2TokenGenerator<Set4thSectionDecoderKeyToken> {
  /// New supply-group-code being rotated in; only its high 12 bits
  /// ride in this token.
  final SupplyGroupCode supplyGroupCode;

  /// The new 128-bit MISTY1 decoder key being rotated in; only its
  /// middle-order-1 32 bits ride in this token.
  final DecoderKey newDecoderKey;

  /// Builds a 4th-section-KCT generator; requires MISTY1 (EA11).
  Set4thSectionDecoderKeyTokenGenerator({
    required DecoderKey decoderKey,
    required EncryptionAlgorithm encryptionAlgorithm,
    required this.supplyGroupCode,
    required this.newDecoderKey,
  }) : super(decoderKey, encryptionAlgorithm) {
    if (encryptionAlgorithm.code != EncryptionAlgorithmCode.misty1) {
      throw NotImplementedException(
        'Set4thSection KCT requires MISTY1 (EA11); '
        'got ${encryptionAlgorithm.code.name}',
      );
    }
  }

  /// Build a fully-populated [Set4thSectionDecoderKeyToken]. Auto-splits
  /// the new decoder key and picks the middle-order-1 32 bits.
  Set4thSectionDecoderKeyToken buildToken(String requestID) {
    final split = splitMisty1DecoderKey(newDecoderKey);
    return Set4thSectionDecoderKeyToken(requestID)
      ..supplyGroupCodeHighOrder = SupplyGroupCodeHighOrder.fromSupplyGroupCode(
        supplyGroupCode,
      )
      ..newKeyMiddleOrder1 = split.middle1;
  }

  /// One-shot helper: build the token then call [generate].
  Set4thSectionDecoderKeyToken generateNew(String requestID) {
    return generate(buildToken(requestID));
  }

  @override
  BitString buildDataBlock(Set4thSectionDecoderKeyToken token) {
    if (token.supplyGroupCodeHighOrder == null ||
        token.newKeyMiddleOrder1 == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw const InvalidTokenException(
        'Set4thSectionDecoderKeyToken is missing required fields before '
        'generation',
      );
    }
    final cls = token.tokenClass!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final sgcho = token.supplyGroupCodeHighOrder!.bitString;
    final nkmo1 = token.newKeyMiddleOrder1!.bitString;

    // CRC input: nkmo1 || sgcho || sub || class
    //          = 32 + 12 + 4 + 2 = 50 bits.
    final crcInput = nkmo1.concat([sgcho, sub, cls]);
    final crcBits = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crcBits);

    // 64-bit data block: crc || nkmo1 || sgcho || sub
    //                  = 16 + 32 + 12 + 4 = 64 bits.
    return crcBits.concat([nkmo1, sgcho, sub]);
  }
}
