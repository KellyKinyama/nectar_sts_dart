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
  Amount? amountPurchased;
  TokenIdentifier? tokenIdentifier;
  RandomNo? randomNo;

  Class0Token(super.requestID);

  Amount extractAmount(BitString decryptedDataBlock) =>
      Amount.fromBitString(decryptedDataBlock.extractBits(16, 16));

  TokenIdentifier extractTokenIdentifier(BitString decryptedDataBlock) =>
      TokenIdentifier.fromBitString(decryptedDataBlock.extractBits(32, 24));

  RandomNo extractRandomNo(BitString decryptedDataBlock) =>
      RandomNo(decryptedDataBlock.extractBits(56, 4));

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
  TransferElectricityCreditToken(super.requestID) {
    tokenClass = TokenClass.electricityCreditTransfer();
    tokenSubClass = TokenSubClass.electricityCredit();
  }

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
  ElectricityCurrencyCreditToken(super.requestID) {
    tokenClass = TokenClass.electricityCreditTransfer();
    tokenSubClass = TokenSubClass.electricityCurrencyCredit();
  }

  @override
  String get type => 'ElectricityCurrency_04';

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
