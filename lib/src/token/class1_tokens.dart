import '../base/bit_string.dart';
import '../domain/class1_payload.dart';
import '../domain/token_class.dart';
import '../domain/token_subclass.dart';
import 'token.dart';

/// Common shape of every Class 1 token. The 64-bit data block carries:
///
///   bits  0..15   CRC                   (16)
///   bits 16..M    ManufacturerCode      (8 for subClass 0, 16 for 1)
///   bits M..59    Control               (36 for subClass 0, 28 for 1)
///   bits 60..63   TokenSubClass         (4)
///
/// where `M` is 24 (subClass 0) or 32 (subClass 1).
abstract class Class1Token extends Token {
  ManufacturerCode? manufacturerCode;
  Control? control;

  Class1Token(super.requestID);
}

/// Class 1 / SubClass 0 — InitiateMeterTestOrDisplay1
/// (8-bit ManufacturerCode, 36-bit Control).
class InitiateMeterTestOrDisplay1Token extends Class1Token {
  static const int manufacturerCodeWidth = 8;
  static const int controlWidth = 36;

  InitiateMeterTestOrDisplay1Token(super.requestID) {
    tokenClass = TokenClass.initiateMeterTestDisplay();
    tokenSubClass = TokenSubClass.initiateMeterTestDisplay1();
  }

  @override
  String get type => 'InitiateMeterTestOrDisplay1_10';

  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);
    manufacturerCode = ManufacturerCode(
      decryptedDataBlock.extractBits(16, manufacturerCodeWidth),
    );
    control = Control(
      decryptedDataBlock.extractBits(24, controlWidth),
      manufacturerCode!,
    );
  }

  factory InitiateMeterTestOrDisplay1Token.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = InitiateMeterTestOrDisplay1Token(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}

/// Class 1 / SubClass 1 — InitiateMeterTestOrDisplay2
/// (16-bit ManufacturerCode, 28-bit Control).
class InitiateMeterTestOrDisplay2Token extends Class1Token {
  static const int manufacturerCodeWidth = 16;
  static const int controlWidth = 28;

  InitiateMeterTestOrDisplay2Token(super.requestID) {
    tokenClass = TokenClass.initiateMeterTestDisplay();
    tokenSubClass = TokenSubClass.initiateMeterTestDisplay2();
  }

  @override
  String get type => 'InitiateMeterTestOrDisplay2_11';

  @override
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock) {
    decryptedTokenBitString = decryptedDataBlock.toPaddedBinary();
    checkCrc(decryptedDataBlock, tokenClass!);
    crc = extractCrc(decryptedDataBlock);
    manufacturerCode = ManufacturerCode(
      decryptedDataBlock.extractBits(16, manufacturerCodeWidth),
    );
    control = Control(
      decryptedDataBlock.extractBits(32, controlWidth),
      manufacturerCode!,
    );
  }

  factory InitiateMeterTestOrDisplay2Token.decoded(
    String requestID,
    BitString decryptedDataBlock,
    BitString encryptedDataBlock,
  ) {
    final t = InitiateMeterTestOrDisplay2Token(requestID);
    t.decode(decryptedDataBlock, encryptedDataBlock);
    return t;
  }
}
