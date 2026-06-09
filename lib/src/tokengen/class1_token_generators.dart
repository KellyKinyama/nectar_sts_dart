import '../base/bit_string.dart';
import '../domain/crc.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class1_tokens.dart';
import 'token_generator.dart';

/// Class 1 generator. The 64-bit data block is laid out as
/// `crc.concat(manufacturerCode, control, subClass)` (LSB-first concat).
abstract class Class1TokenGenerator<T extends Class1Token>
    extends TokenGenerator<T> {
  Class1TokenGenerator(super.decoderKey, super.encryptionAlgorithm);

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
}

class InitiateMeterTestOrDisplay1TokenGenerator
    extends Class1TokenGenerator<InitiateMeterTestOrDisplay1Token> {
  InitiateMeterTestOrDisplay1TokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);
}

class InitiateMeterTestOrDisplay2TokenGenerator
    extends Class1TokenGenerator<InitiateMeterTestOrDisplay2Token> {
  InitiateMeterTestOrDisplay2TokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);
}
