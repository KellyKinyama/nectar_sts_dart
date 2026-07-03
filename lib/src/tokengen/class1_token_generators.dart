import '../base/bit_string.dart';
import '../domain/crc.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class1_tokens.dart';
import '../token/token.dart';
import 'token_generator.dart';

/// Class 1 generator. The 64-bit data block is laid out as
/// `crc.concat(manufacturerCode, control, subClass)` (LSB-first concat).
///
/// Example (from `test/class1_and_dispatcher_test.dart`):
/// ```dart
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
///
/// // Round-trip through the dispatcher.
/// final result = TokenDecoderDispatcher(
///   decoderKey, StandardTransferAlgorithm(),
/// ).decodeDecimal('req-100', token.tokenNo);
/// final decoded = (result as DecodeAccepted).token
///     as InitiateMeterTestOrDisplay1Token;
/// decoded.manufacturerCode!.value; // 0xA5
/// decoded.control!.value;          // 0x123456789
/// ```
abstract class Class1TokenGenerator<T extends Class1Token>
    extends TokenGenerator<T> {
  /// Forwards [decoderKey] and [encryptionAlgorithm] to [TokenGenerator].
  Class1TokenGenerator(super.decoderKey, super.encryptionAlgorithm);

  /// Assembles the 64-bit data block per STS Class 1 layout, computes
  /// the CRC over the 50-bit protected input and stamps it onto the
  /// token.
  ///
  /// Throws [InvalidTokenException] when a required payload field is
  /// missing.
  @override
  BitString buildDataBlock(T token) {
    if (token.manufacturerCode == null ||
        token.control == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw const InvalidTokenException(
        'Class 1 token is missing required fields before generation',
      );
    }
    final mfg = token.manufacturerCode!.bitString;
    final ctrl = token.control!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final cls = token.tokenClass!.bitString;

    // CRC input: mfg || ctrl || sub || cls
    // Widths sum to 8+36+4+2 = 50 (subClass 0) or 16+28+4+2 = 50 (subClass 1).
    final crcInput = mfg.concat([ctrl, sub, cls]);
    final crc = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crc);

    // 64-bit data block: crc || mfg || ctrl || sub
    return crc.concat([mfg, ctrl, sub]);
  }

  /// Class 1 tokens are NOT encrypted (per IEC 62055-41 §8.4 / the
  /// Java upstream's [Meter.decodeNative] which routes class==1 directly
  /// to the subclass decoder without invoking the EA). The data block
  /// is transposed and emitted in the clear so that meters without
  /// the decoder key can still execute display / self-test commands.
  @override
  T generate(T token) {
    final dataBlock = buildDataBlock(token);
    final transposed = TokenTransposition.transposeToBinary66(
      token.tokenClass!,
      dataBlock,
    );
    token.encryptedTokenBitString = transposed;
    token.decryptedTokenBitString = dataBlock.toPaddedBinary();
    return token;
  }
}

/// Concrete generator for the 8-bit-manufacturer / 36-bit-control
/// InitiateMeterTestOrDisplay1 token.
class InitiateMeterTestOrDisplay1TokenGenerator
    extends Class1TokenGenerator<InitiateMeterTestOrDisplay1Token> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  InitiateMeterTestOrDisplay1TokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);
}

/// Concrete generator for the 16-bit-manufacturer / 28-bit-control
/// InitiateMeterTestOrDisplay2 token.
class InitiateMeterTestOrDisplay2TokenGenerator
    extends Class1TokenGenerator<InitiateMeterTestOrDisplay2Token> {
  /// Binds [decoderKey] and [encryptionAlgorithm].
  InitiateMeterTestOrDisplay2TokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);
}
