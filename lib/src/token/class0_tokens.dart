import '../base/bit_string.dart';
import '../domain/amount.dart';
import '../domain/random_no.dart';
import '../domain/token_class.dart';
import '../domain/token_identifier.dart';
import '../domain/token_subclass.dart';
import 'token.dart';

/// Common shape of every Class 0 token (credit-transfer family).
///
/// Decrypted 64-bit data block layout:
///
///   bits  0..15   CRC                  (16)
///   bits 16..31   Amount               (16)
///   bits 32..55   TokenIdentifier      (24)
///   bits 56..59   RandomNo             ( 4)
///   bits 60..63   TokenSubClass        ( 4)
abstract class Class0Token extends Token {
  /// Amount purchased, populated after [decode].
  Amount? amountPurchased;

  /// TID (issue-time) field, populated after [decode].
  TokenIdentifier? tokenIdentifier;

  /// Random-number field, populated after [decode].
  RandomNo? randomNo;

  /// Base constructor for subclasses.
  Class0Token(super.requestID);

  /// Extracts the 16-bit amount field (bits 16..31) as an [Amount].
  Amount extractAmount(BitString decryptedDataBlock) =>
      Amount.fromBitString(decryptedDataBlock.extractBits(16, 16));

  /// Extracts the 24-bit TID (bits 32..55) as a [TokenIdentifier].
  TokenIdentifier extractTokenIdentifier(BitString decryptedDataBlock) =>
      TokenIdentifier.fromBitString(decryptedDataBlock.extractBits(32, 24));

  /// Extracts the 4-bit random-number field (bits 56..59) as a
  /// [RandomNo].
  RandomNo extractRandomNo(BitString decryptedDataBlock) =>
      RandomNo(decryptedDataBlock.extractBits(56, 4));

  /// Verifies the CRC, extracts and stores every Class 0 field.
  ///
  /// Throws [CrcError] on CRC mismatch.
  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);
    amountPurchased = extractAmount(decryptedDataBlock);
    tokenIdentifier = extractTokenIdentifier(decryptedDataBlock);
    randomNo = extractRandomNo(decryptedDataBlock);
  }
}

/// Concrete: the most common token — Class 0 / SubClass 0,
/// "Transfer Electricity Credit" (kWh top-up).
class TransferElectricityCreditToken extends Class0Token {
  /// Builds an empty electricity-credit token; pre-populates
  /// [tokenClass] and [tokenSubClass].
  TransferElectricityCreditToken(super.requestID) {
    tokenClass = TokenClass.electricityCreditTransfer();
    tokenSubClass = TokenSubClass.electricityCredit();
  }

  /// Type tag `"Electricity_00"` used in dispatcher lookups.
  @override
  String get type => 'Electricity_00';

  /// Decoder-side factory: rebuild a fully-populated token from
  /// the decrypted + encrypted blocks coming out of the meter pipeline.
  factory TransferElectricityCreditToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = TransferElectricityCreditToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    t.encryptedTokenBitString = null; // not the 66-bit form, only the 64
    return t;
  }
}

/// Concrete: Class 0 / SubClass 4, "Electricity Currency" credit
/// (currency-denominated electricity top-up). Same 64-bit data block
/// layout as [TransferElectricityCreditToken]; the [TokenSubClass]
/// nibble carries `4` instead of `0` so a meter can distinguish the
/// two when the API contract calls for a currency-credit reply.
class ElectricityCurrencyCreditToken extends Class0Token {
  /// Builds an empty electricity-currency-credit token; pre-populates
  /// [tokenClass] and [tokenSubClass].
  ElectricityCurrencyCreditToken(super.requestID) {
    tokenClass = TokenClass.electricityCreditTransfer();
    tokenSubClass = TokenSubClass.electricityCurrencyCredit();
  }

  /// Type tag `"ElectricityCurrency_04"` used in dispatcher lookups.
  @override
  String get type => 'ElectricityCurrency_04';

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory ElectricityCurrencyCreditToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = ElectricityCurrencyCreditToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    t.encryptedTokenBitString = null;
    return t;
  }
}

/// Concrete: Class 0 / SubClass 1, "Transfer Water Credit" (water
/// top-up). Identical 64-bit data block layout to
/// [TransferElectricityCreditToken]; the [TokenSubClass] nibble is 1.
class TransferWaterCreditToken extends Class0Token {
  /// Builds an empty water-credit token; pre-populates [tokenClass]
  /// and [tokenSubClass].
  TransferWaterCreditToken(super.requestID) {
    tokenClass = TokenClass.waterCreditTransfer();
    tokenSubClass = TokenSubClass.waterCredit();
  }

  /// Type tag `"Water_01"` used in dispatcher lookups.
  @override
  String get type => 'Water_01';

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory TransferWaterCreditToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = TransferWaterCreditToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    t.encryptedTokenBitString = null;
    return t;
  }
}

/// Concrete: Class 0 / SubClass 2, "Transfer Gas Credit" (gas
/// top-up). Identical 64-bit data block layout to
/// [TransferElectricityCreditToken]; the [TokenSubClass] nibble is 2.
class TransferGasCreditToken extends Class0Token {
  /// Builds an empty gas-credit token; pre-populates [tokenClass] and
  /// [tokenSubClass].
  TransferGasCreditToken(super.requestID) {
    tokenClass = TokenClass.gasCreditTransfer();
    tokenSubClass = TokenSubClass.gasCredit();
  }

  /// Type tag `"Gas_02"` used in dispatcher lookups.
  @override
  String get type => 'Gas_02';

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
  factory TransferGasCreditToken.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = TransferGasCreditToken(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    t.encryptedTokenBitString = null;
    return t;
  }
}
