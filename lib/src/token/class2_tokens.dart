import '../base/bit_string.dart';
import '../domain/class2_payload.dart';
import '../domain/class2_register_payloads.dart';
import '../domain/primitives.dart';
import '../domain/random_no.dart';
import '../domain/token_class.dart';
import '../domain/token_identifier.dart';
import '../domain/token_subclass.dart';
import 'token.dart';

/// Marker base for all Class 2 (management / engineering) tokens.
abstract class Class2Token extends Token {
  /// Base constructor for subclasses.
  Class2Token(super.requestID);
}

/// Common shape of the five Class 2 management tokens that follow the
/// same 64-bit data block layout as Class 0 (only the 16-bit payload
/// register differs):
///
///   bits  0..15   CRC                  (16)
///   bits 16..31   <payload register>   (16)
///   bits 32..55   TokenIdentifier      (24)
///   bits 56..59   RandomNo             ( 4)
///   bits 60..63   TokenSubClass        ( 4)
///
/// Subclasses override [registerBits] / [setRegisterBits] to plug in
/// their payload-specific type.
///
/// Example (SetMaximumPowerLimit issued via [VirtualHsm], round-tripped
/// through the top-level dispatcher — from
/// `test/class2_register_tokens_test.dart`):
/// ```dart
/// final tokenNo = hsm.generateToken('mpl-rt', {
///   VirtualHsmParams.tokenClass:         '2',
///   VirtualHsmParams.tokenSubclass:      '0',
///   VirtualHsmParams.maximumPowerLimit:  4321,
///   // … usual DKGA-02 parameters (kt, sgc, ti, krn, iin, drn, base date)
/// }).tokenNo;
///
/// final result = TokenDecoderDispatcher(decoderKey, StandardTransferAlgorithm())
///     .decodeDecimal('mpl-rt-dec', tokenNo);
/// final t = (result as DecodeAccepted).token as SetMaximumPowerLimitToken;
/// t.maximumPowerLimit!.value; // 4321
/// ```
abstract class Class2RegisterToken extends Class2Token {
  /// TID field, populated after [decode].
  TokenIdentifier? tokenIdentifier;

  /// Random-number field, populated after [decode].
  RandomNo? randomNo;

  /// Base constructor for subclasses.
  Class2RegisterToken(super.requestID);

  /// 16-bit payload register. Subclass-specific (Register / Pad /
  /// Rate / MaximumPowerLimit / MaximumPhasePowerUnbalanceLimit).
  BitString? get registerBits;

  /// Setter counterpart of [registerBits]; subclasses parse [value]
  /// into their concrete payload type.
  set registerBits(BitString? value);

  /// Extracts the 24-bit TID (bits 32..55) as a [TokenIdentifier].
  TokenIdentifier extractTokenIdentifier(BitString decryptedDataBlock) =>
      TokenIdentifier.fromBitString(decryptedDataBlock.extractBits(32, 24));

  /// Extracts the 4-bit random-number field (bits 56..59) as a
  /// [RandomNo].
  RandomNo extractRandomNo(BitString decryptedDataBlock) =>
      RandomNo(decryptedDataBlock.extractBits(56, 4));

  /// Verifies the CRC, extracts the 16-bit payload register plus TID
  /// and RandomNo.
  ///
  /// Throws [CrcError] on CRC mismatch.
  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);
    registerBits = decryptedDataBlock.extractBits(16, 16);
    tokenIdentifier = extractTokenIdentifier(decryptedDataBlock);
    randomNo = extractRandomNo(decryptedDataBlock);
  }
}

// ---------------------------------------------------------------------------
// SetMaximumPowerLimit Token (Class 2 / SubClass 0x0)
// ---------------------------------------------------------------------------

/// Tells the meter to clamp the customer's instantaneous power draw
/// to the carried [maximumPowerLimit] (a 16-bit unsigned value).
class SetMaximumPowerLimitToken extends Class2RegisterToken {
  /// Payload MPL, populated after [decode].
  MaximumPowerLimit? maximumPowerLimit;

  /// Builds an empty SetMaximumPowerLimit token; pre-populates
  /// [tokenClass] and [tokenSubClass].
  SetMaximumPowerLimitToken(super.requestID) {
    tokenClass = TokenClass.engineering('Set Maximum Power Limit');
    tokenSubClass = TokenSubClass.setMaximumPowerLimit();
  }

  /// Type tag `"SetMaximumPowerLimit_20"` used in dispatcher lookups.
  @override
  String get type => 'SetMaximumPowerLimit_20';

  /// Adapts the 16-bit register slot as [MaximumPowerLimit].
  @override
  BitString? get registerBits => maximumPowerLimit?.bitString;

  /// Parses [value] into a [MaximumPowerLimit] (or clears when null).
  @override
  set registerBits(BitString? value) {
    maximumPowerLimit =
        value == null ? null : MaximumPowerLimit.fromBitString(value);
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory SetMaximumPowerLimitToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = SetMaximumPowerLimitToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// ClearCredit Token (Class 2 / SubClass 0x1)
// ---------------------------------------------------------------------------

/// Tells the meter to reset its credit balance. The 16-bit
/// [register] field carries an optional snapshot value the meter
/// writes into the post-clear counter (commonly 0).
class ClearCreditToken extends Class2RegisterToken {
  /// Post-clear register snapshot, populated after [decode].
  Register? register;

  /// Builds an empty ClearCredit token; pre-populates [tokenClass]
  /// and [tokenSubClass].
  ClearCreditToken(super.requestID) {
    tokenClass = TokenClass.engineering('Clear Credit');
    tokenSubClass = TokenSubClass.clearCredit();
  }

  /// Type tag `"ClearCredit_21"` used in dispatcher lookups.
  @override
  String get type => 'ClearCredit_21';

  /// Adapts the 16-bit register slot as [Register].
  @override
  BitString? get registerBits => register?.bitString;

  /// Parses [value] into a [Register] (or clears when null).
  @override
  set registerBits(BitString? value) {
    register = value == null ? null : Register(value);
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory ClearCreditToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = ClearCreditToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// SetTariffRate Token (Class 2 / SubClass 0x2)
// ---------------------------------------------------------------------------

/// Tells the meter to switch to the carried 16-bit tariff [rate].
class SetTariffRateToken extends Class2RegisterToken {
  /// New tariff rate, populated after [decode].
  Rate? rate;

  /// Builds an empty SetTariffRate token; pre-populates [tokenClass]
  /// and [tokenSubClass].
  SetTariffRateToken(super.requestID) {
    tokenClass = TokenClass.engineering('Set Tariff Rate');
    tokenSubClass = TokenSubClass.setTariffRate();
  }

  /// Type tag `"SetTariffRate_22"` used in dispatcher lookups.
  @override
  String get type => 'SetTariffRate_22';

  /// Adapts the 16-bit register slot as [Rate].
  @override
  BitString? get registerBits => rate?.bitString;

  /// Parses [value] into a [Rate] (or clears when null).
  @override
  set registerBits(BitString? value) {
    rate = value == null ? null : Rate(value);
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory SetTariffRateToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = SetTariffRateToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// 1st Section Decoder Key Change Token (Class 2 / SubClass 0x3)
// ---------------------------------------------------------------------------

/// Conveys the high-order 32 bits of a new decoder key together with
/// the new Key Type, the high nibble of the new Key Expiry Number,
/// the new Key Revision Number and the Rollover Key Change flag.
///
/// 64-bit decrypted data block layout (LSB-first):
///
///   bits  0..15   CRC                                 (16)
///   bits 16..47   NewKeyHighOrder (NKHO)              (32)
///   bits 48..49   KeyType                             ( 2)
///   bit   50      _3KCT (reserved, 0 for 64-bit KCT)  ( 1)
///   bit   51      RolloverKeyChange (RO)              ( 1)
///   bits 52..55   KeyRevisionNumber (new KRN)         ( 4)
///   bits 56..59   KeyExpiryNumberHighOrder (KENHO)    ( 4)
///   bits 60..63   TokenSubClass = 0x3                 ( 4)
///
/// Must always be applied as a pair with [Set2ndSectionDecoderKeyToken].
class Set1stSectionDecoderKeyToken extends Class2Token {
  /// High nibble of the new KEN, populated after [decode].
  KeyExpiryNumberHighOrder? keyExpiryNumberHighOrder;

  /// New key revision number, populated after [decode].
  KeyRevisionNumber? keyRevisionNumber;

  /// Rollover-key-change flag, populated after [decode].
  RolloverKeyChange? rolloverKeyChange;

  /// New key type, populated after [decode].
  KeyType? keyType;

  /// High-order 32 bits of the new decoder key, populated after
  /// [decode].
  NewKeyHighOrder? newKeyHighOrder;

  /// Reserved `_3KCT` bit, defaulted to zero and rewritten by [decode].
  Reserved3Kct? reserved3Kct;

  /// Builds an empty 1st-section KCT; pre-populates [tokenClass],
  /// [tokenSubClass] and defaults [reserved3Kct] to zero.
  Set1stSectionDecoderKeyToken(super.requestID) {
    tokenClass = TokenClass.engineering('Set 1st Section Decoder Key');
    tokenSubClass = TokenSubClass.set1stSectionDecoderKey();
    reserved3Kct = Reserved3Kct.zero();
  }

  /// Type tag `"Set1stSectionDecoderKey_23"` used in dispatcher
  /// lookups.
  @override
  String get type => 'Set1stSectionDecoderKey_23';

  /// Verifies the CRC and extracts every 1st-section KCT field.
  ///
  /// Throws [CrcError] on CRC mismatch.
  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);

    newKeyHighOrder = NewKeyHighOrder(decryptedDataBlock.extractBits(16, 32));
    keyType = KeyType(decryptedDataBlock.extractBits(48, 2).value);
    reserved3Kct = Reserved3Kct(decryptedDataBlock.extractBits(50, 1));
    rolloverKeyChange = RolloverKeyChange(
      decryptedDataBlock.extractBits(51, 1),
    );
    keyRevisionNumber = KeyRevisionNumber(
      decryptedDataBlock.extractBits(52, 4).value,
    );
    keyExpiryNumberHighOrder = KeyExpiryNumberHighOrder(
      decryptedDataBlock.extractBits(56, 4),
    );
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory Set1stSectionDecoderKeyToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = Set1stSectionDecoderKeyToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// 2nd Section Decoder Key Change Token (Class 2 / SubClass 0x4)
// ---------------------------------------------------------------------------

/// Conveys the low-order 32 bits of a new decoder key together with
/// the new Tariff Index and the low nibble of the new KEN.
///
/// 64-bit decrypted data block layout (LSB-first):
///
///   bits  0..15   CRC                                 (16)
///   bits 16..47   NewKeyLowOrder (NKLO)               (32)
///   bits 48..55   TariffIndex (8-bit binary form)     ( 8)
///   bits 56..59   KeyExpiryNumberLowOrder (KENLO)     ( 4)
///   bits 60..63   TokenSubClass = 0x4                 ( 4)
class Set2ndSectionDecoderKeyToken extends Class2Token {
  /// Low nibble of the new KEN, populated after [decode].
  KeyExpiryNumberLowOrder? keyExpiryNumberLowOrder;

  /// New tariff index, populated after [decode].
  TariffIndex? tariffIndex;

  /// Low-order 32 bits of the new decoder key, populated after
  /// [decode].
  NewKeyLowOrder? newKeyLowOrder;

  /// Builds an empty 2nd-section KCT; pre-populates [tokenClass] and
  /// [tokenSubClass].
  Set2ndSectionDecoderKeyToken(super.requestID) {
    tokenClass = TokenClass.engineering('Set 2nd Section Decoder Key');
    tokenSubClass = TokenSubClass.set2ndSectionDecoderKey();
  }

  /// Type tag `"Set2ndSectionDecoderKey_24"` used in dispatcher
  /// lookups.
  @override
  String get type => 'Set2ndSectionDecoderKey_24';

  /// Verifies the CRC and extracts every 2nd-section KCT field.
  ///
  /// Throws [CrcError] on CRC mismatch.
  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);

    newKeyLowOrder = NewKeyLowOrder(decryptedDataBlock.extractBits(16, 32));
    final tiBits = decryptedDataBlock.extractBits(48, 8).value;
    tariffIndex = TariffIndex(tiBits.toString().padLeft(2, '0'));
    keyExpiryNumberLowOrder = KeyExpiryNumberLowOrder(
      decryptedDataBlock.extractBits(56, 4),
    );
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory Set2ndSectionDecoderKeyToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = Set2ndSectionDecoderKeyToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// ClearTamperCondition Token (Class 2 / SubClass 0x5)
// ---------------------------------------------------------------------------

/// Tells the meter to clear any latched tamper-detection flags. The
/// 16-bit [pad] field is just nonce padding.
class ClearTamperConditionToken extends Class2RegisterToken {
  /// 16-bit random padding, populated after [decode].
  Pad? pad;

  /// Builds an empty ClearTamperCondition token; pre-populates
  /// [tokenClass] and [tokenSubClass].
  ClearTamperConditionToken(super.requestID) {
    tokenClass = TokenClass.engineering('Clear Tamper Condition');
    tokenSubClass = TokenSubClass.clearTamperCondition();
  }

  /// Type tag `"ClearTamperCondition_25"` used in dispatcher lookups.
  @override
  String get type => 'ClearTamperCondition_25';

  /// Adapts the 16-bit register slot as [Pad].
  @override
  BitString? get registerBits => pad?.bitString;

  /// Parses [value] into a [Pad] (or clears when null).
  @override
  set registerBits(BitString? value) {
    pad = value == null ? null : Pad(value);
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory ClearTamperConditionToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = ClearTamperConditionToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// SetMaximumPhasePowerUnbalanceLimit Token (Class 2 / SubClass 0x6)
// ---------------------------------------------------------------------------

/// Tells the meter to clamp the inter-phase power unbalance to the
/// carried 16-bit [maximumPhasePowerUnbalanceLimit] (commonly a
/// percentage).
class SetMaximumPhasePowerUnbalanceLimitToken extends Class2RegisterToken {
  /// Payload MPPUL, populated after [decode].
  MaximumPhasePowerUnbalanceLimit? maximumPhasePowerUnbalanceLimit;

  /// Builds an empty SetMaximumPhasePowerUnbalanceLimit token;
  /// pre-populates [tokenClass] and [tokenSubClass].
  SetMaximumPhasePowerUnbalanceLimitToken(super.requestID) {
    tokenClass = TokenClass.engineering(
      'Set Maximum Phase Power Unbalance Limit',
    );
    tokenSubClass = TokenSubClass.setMaximumPhasePowerUnbalanceLimit();
  }

  /// Type tag `"SetMaximumPhasePowerUnbalanceLimit_26"` used in
  /// dispatcher lookups.
  @override
  String get type => 'SetMaximumPhasePowerUnbalanceLimit_26';

  /// Adapts the 16-bit register slot as [MaximumPhasePowerUnbalanceLimit].
  @override
  BitString? get registerBits => maximumPhasePowerUnbalanceLimit?.bitString;

  /// Parses [value] into a [MaximumPhasePowerUnbalanceLimit] (or
  /// clears when null).
  @override
  set registerBits(BitString? value) {
    maximumPhasePowerUnbalanceLimit = value == null
        ? null
        : MaximumPhasePowerUnbalanceLimit.fromBitString(value);
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory SetMaximumPhasePowerUnbalanceLimitToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = SetMaximumPhasePowerUnbalanceLimitToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// 3rd Section Decoder Key Change Token (Class 2 / SubClass 0x8)
// ---------------------------------------------------------------------------

/// Conveys bits 32..63 (`NewKeyMiddleOrder2`) of a 128-bit MISTY1
/// decoder key together with the low-order 12 bits of a new Supply
/// Group Code.
///
/// 64-bit decrypted data block layout (LSB-first):
///
///   bits  0..15   CRC                                 (16)
///   bits 16..47   NewKeyMiddleOrder2 (NKMO2)          (32)
///   bits 48..59   SupplyGroupCodeLowOrder (SGCLO)     (12)
///   bits 60..63   TokenSubClass = 0x8                 ( 4)
///
/// Must always be applied as part of a 4-token set together with the
/// 1st, 2nd and 4th Section KCTs (MISTY1 path only).
class Set3rdSectionDecoderKeyToken extends Class2Token {
  /// Low-order 12 bits of the new SGC, populated after [decode].
  SupplyGroupCodeLowOrder? supplyGroupCodeLowOrder;

  /// MISTY1 middle-order-2 32 bits of the new decoder key, populated
  /// after [decode].
  NewKeyMiddleOrder2? newKeyMiddleOrder2;

  /// Builds an empty 3rd-section KCT; pre-populates [tokenClass] and
  /// [tokenSubClass].
  Set3rdSectionDecoderKeyToken(super.requestID) {
    tokenClass = TokenClass.engineering('Set 3rd Section Decoder Key');
    tokenSubClass = TokenSubClass.set3rdSectionDecoderKey();
  }

  /// Type tag `"Set3rdSectionDecoderKey_28"` used in dispatcher
  /// lookups.
  @override
  String get type => 'Set3rdSectionDecoderKey_28';

  /// Verifies the CRC and extracts every 3rd-section KCT field.
  ///
  /// Throws [CrcError] on CRC mismatch.
  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);

    newKeyMiddleOrder2 = NewKeyMiddleOrder2(
      decryptedDataBlock.extractBits(16, 32),
    );
    supplyGroupCodeLowOrder = SupplyGroupCodeLowOrder(
      decryptedDataBlock.extractBits(48, 12),
    );
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory Set3rdSectionDecoderKeyToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = Set3rdSectionDecoderKeyToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

// ---------------------------------------------------------------------------
// 4th Section Decoder Key Change Token (Class 2 / SubClass 0x9)
// ---------------------------------------------------------------------------

/// Conveys bits 64..95 (`NewKeyMiddleOrder1`) of a 128-bit MISTY1
/// decoder key together with the high-order 12 bits of a new Supply
/// Group Code.
///
/// 64-bit decrypted data block layout (LSB-first):
///
///   bits  0..15   CRC                                 (16)
///   bits 16..47   NewKeyMiddleOrder1 (NKMO1)          (32)
///   bits 48..59   SupplyGroupCodeHighOrder (SGCHO)    (12)
///   bits 60..63   TokenSubClass = 0x9                 ( 4)
class Set4thSectionDecoderKeyToken extends Class2Token {
  /// High-order 12 bits of the new SGC, populated after [decode].
  SupplyGroupCodeHighOrder? supplyGroupCodeHighOrder;

  /// MISTY1 middle-order-1 32 bits of the new decoder key, populated
  /// after [decode].
  NewKeyMiddleOrder1? newKeyMiddleOrder1;

  /// Builds an empty 4th-section KCT; pre-populates [tokenClass] and
  /// [tokenSubClass].
  Set4thSectionDecoderKeyToken(super.requestID) {
    tokenClass = TokenClass.engineering('Set 4th Section Decoder Key');
    tokenSubClass = TokenSubClass.set4thSectionDecoderKey();
  }

  /// Type tag `"Set4thSectionDecoderKey_29"` used in dispatcher
  /// lookups.
  @override
  String get type => 'Set4thSectionDecoderKey_29';

  /// Verifies the CRC and extracts every 4th-section KCT field.
  ///
  /// Throws [CrcError] on CRC mismatch.
  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);

    newKeyMiddleOrder1 = NewKeyMiddleOrder1(
      decryptedDataBlock.extractBits(16, 32),
    );
    supplyGroupCodeHighOrder = SupplyGroupCodeHighOrder(
      decryptedDataBlock.extractBits(48, 12),
    );
  }

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory Set4thSectionDecoderKeyToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = Set4thSectionDecoderKeyToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}
