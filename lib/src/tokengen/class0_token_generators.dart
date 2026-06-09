import '../base/bit_string.dart';
import '../domain/crc.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class0_tokens.dart';
import '../token/token.dart';
import 'token_generator.dart';

/// Class 0 generator. Builds the 64-bit decrypted data block as
/// `crc.concat(amount, tid, rnd, subClass)` (LSB-first concat order)
/// after computing the CRC over `amount || tid || rnd || subClass || class`.
abstract class Class0TokenGenerator<T extends Class0Token>
    extends TokenGenerator<T> {
  Class0TokenGenerator(super.decoderKey, super.encryptionAlgorithm);

  @override
  BitString buildDataBlock(T token) {
    if (token.amountPurchased == null ||
        token.tokenIdentifier == null ||
        token.randomNo == null ||
        token.tokenClass == null ||
        token.tokenSubClass == null) {
      throw const InvalidTokenException(
        'Class 0 token is missing required fields before generation',
      );
    }
    final amount = token.amountPurchased!.bitString;
    final tid = token.tokenIdentifier!.bitString;
    final rnd = token.randomNo!.bitString;
    final sub = token.tokenSubClass!.bitString;
    final cls = token.tokenClass!.bitString;

    // CRC over 16+24+4+4+2 = 50 bits.
    final crcInput = amount.concat([tid, rnd, sub, cls]);
    final crc = Crc().generateCrc(crcInput);
    token.crc = Crc.fromBitString(crc);

    // 64-bit data block: crc || amount || tid || rnd || sub
    // = 16 + 16 + 24 + 4 + 4 = 64 bits.
    return crc.concat([amount, tid, rnd, sub]);
  }
}

/// Concrete Class 0 / SubClass 0 generator (kWh top-up).
class TransferElectricityCreditTokenGenerator
    extends Class0TokenGenerator<TransferElectricityCreditToken> {
  TransferElectricityCreditTokenGenerator(
    DecoderKey decoderKey,
    EncryptionAlgorithm encryptionAlgorithm,
  ) : super(decoderKey, encryptionAlgorithm);
}
