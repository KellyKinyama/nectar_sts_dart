import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class1_tokens.dart';
import '../token/token.dart';

/// Decoder for Class 1 tokens (InitiateMeterTestOrDisplay 1 & 2).
///
/// Dispatches on the embedded sub-class bits (60..63 of the decrypted
/// data block) to choose between the 8/36-bit and 16/28-bit layouts.
class Class1TokenDecoder {
  final DecoderKey decoderKey;
  final EncryptionAlgorithm encryptionAlgorithm;

  Class1TokenDecoder(this.decoderKey, this.encryptionAlgorithm);

  Class1Token decodeDecimal(String requestID, String decimal20) {
    final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
    return decodeBinary66(requestID, binary66);
  }

  Class1Token decodeBinary66(String requestID, String binary66) {
    final r = TokenTransposition.untransposeFromBinary66(binary66);
    if (r.tokenClass.bitString.value != 1) {
      throw const TokenError('Token class is not 1 — not a Class 1 token');
    }
    final decrypted = encryptionAlgorithm.decrypt(decoderKey, r.encrypted64);
    final decrypted64 = BitString.fromValue(decrypted.value, 64);
    final encrypted64 = BitString.fromValue(r.encrypted64.value, 64);

    final subClassValue = decrypted64.extractBits(60, 4).value;
    switch (subClassValue) {
      case 0:
        return InitiateMeterTestOrDisplay1Token.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 1:
        return InitiateMeterTestOrDisplay2Token.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      default:
        throw TokenError('Unknown Class 1 sub-class: $subClassValue');
    }
  }
}
