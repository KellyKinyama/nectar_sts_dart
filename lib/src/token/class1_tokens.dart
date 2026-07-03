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
///
/// Example (from `test/class1_and_dispatcher_test.dart`):
/// ```dart
/// // SubClass 0: 8-bit mfg code, 36-bit control.
/// final token = InitiateMeterTestOrDisplay1Token('req-100')
///   ..manufacturerCode = ManufacturerCode.fromInt(0xA5, widthBits: 8)
///   ..control          = Control(
///     BitString.fromValue(0x123456789, 36),
///     ManufacturerCode.fromInt(0xA5, widthBits: 8),
///   );
///
/// InitiateMeterTestOrDisplay1TokenGenerator(
///   decoderKey, StandardTransferAlgorithm(),
/// ).generate(token);
/// // Class 1 tokens are transmitted in the clear (no EA encrypt).
/// ```
abstract class Class1Token extends Token {
  /// Manufacturer code populated after [decode] (8 or 16 bits).
  ManufacturerCode? manufacturerCode;

  /// Vendor-defined control payload populated after [decode].
  Control? control;

  /// Base constructor for subclasses.
  Class1Token(super.requestID);
}

/// Class 1 / SubClass 0 — InitiateMeterTestOrDisplay1
/// (8-bit ManufacturerCode, 36-bit Control).
class InitiateMeterTestOrDisplay1Token extends Class1Token {
  /// Width of the ManufacturerCode field for this sub-class (`8`).
  static const int manufacturerCodeWidth = 8;

  /// Width of the Control field for this sub-class (`36`).
  static const int controlWidth = 36;

  /// Builds an empty InitiateMeterTestOrDisplay1 token; pre-populates
  /// [tokenClass] and [tokenSubClass].
  InitiateMeterTestOrDisplay1Token(super.requestID) {
    tokenClass = TokenClass.initiateMeterTestDisplay();
    tokenSubClass = TokenSubClass.initiateMeterTestDisplay1();
  }

  /// Type tag `"InitiateMeterTestOrDisplay1_10"` used in dispatcher
  /// lookups.
  @override
  String get type => 'InitiateMeterTestOrDisplay1_10';

  /// Verifies the CRC and extracts the 8-bit manufacturer code +
  /// 36-bit control fields.
  ///
  /// Throws [CrcError] on CRC mismatch.
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

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
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
  /// Width of the ManufacturerCode field for this sub-class (`16`).
  static const int manufacturerCodeWidth = 16;

  /// Width of the Control field for this sub-class (`28`).
  static const int controlWidth = 28;

  /// Builds an empty InitiateMeterTestOrDisplay2 token; pre-populates
  /// [tokenClass] and [tokenSubClass].
  InitiateMeterTestOrDisplay2Token(super.requestID) {
    tokenClass = TokenClass.initiateMeterTestDisplay();
    tokenSubClass = TokenSubClass.initiateMeterTestDisplay2();
  }

  /// Type tag `"InitiateMeterTestOrDisplay2_11"` used in dispatcher
  /// lookups.
  @override
  String get type => 'InitiateMeterTestOrDisplay2_11';

  /// Verifies the CRC and extracts the 16-bit manufacturer code +
  /// 28-bit control fields.
  ///
  /// Throws [CrcError] on CRC mismatch.
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

  /// Decoder-side factory: rebuild a fully-populated token from the
  /// decrypted + encrypted blocks coming out of the meter pipeline.
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
