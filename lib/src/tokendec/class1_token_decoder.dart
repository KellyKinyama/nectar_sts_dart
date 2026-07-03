import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class1_tokens.dart';
import '../token/token.dart';

/// Decoder for Class 1 tokens (InitiateMeterTestOrDisplay 1 & 2).
///
/// Per IEC 62055-41 §8.4 (and the Java upstream's [Meter.decodeNative]),
/// Class 1 tokens are transmitted in the clear — the 66-bit transposed
/// payload IS the data block. We therefore skip the EA decrypt step
/// and dispatch directly on the embedded sub-class bits (60..63) to
/// choose between the 8/36-bit and 16/28-bit layouts.
///
/// The [DecoderKey] / [EncryptionAlgorithm] parameters are accepted
/// for API symmetry with the Class 0/2 decoders but are unused.
///
/// Example:
/// ```dart
/// // key + algorithm are ignored for Class 1; pass any values.
/// final decoder = Class1TokenDecoder(decoderKey, StandardTransferAlgorithm());
/// final t = decoder.decodeDecimal('req-100', tokenNo20);
/// if (t is InitiateMeterTestOrDisplay1Token) {
///   t.manufacturerCode!.value; // 8-bit mfg code
///   t.control!.value;          // 36-bit control payload
/// }
/// ```
class Class1TokenDecoder {
  /// Accepted for API symmetry with Class 0/2 decoders; unused for
  /// Class 1 (payload is transmitted in the clear).
  final DecoderKey decoderKey;

  /// Accepted for API symmetry; unused for Class 1.
  final EncryptionAlgorithm encryptionAlgorithm;

  /// Binds [decoderKey] and [encryptionAlgorithm]; neither is used
  /// during decode.
  Class1TokenDecoder(this.decoderKey, this.encryptionAlgorithm);

  /// Decode a Class 1 token from its 20-digit displayable form.
  Class1Token decodeDecimal(String requestID, String decimal20) {
    final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
    return decodeBinary66(requestID, binary66);
  }

  /// Decode a Class 1 token from the raw 66-bit binary string.
  ///
  /// Throws [TokenError] when the token class is not 1 or the
  /// sub-class nibble is unknown.
  Class1Token decodeBinary66(String requestID, String binary66) {
    final r = TokenTransposition.untransposeFromBinary66(binary66);
    if (r.tokenClass.bitString.value != 1) {
      throw const TokenError('Token class is not 1 — not a Class 1 token');
    }
    final dataBlock = BitString.fromValue(r.encrypted64.value, 64);

    final subClassValue = dataBlock.extractBits(60, 4).value;
    switch (subClassValue) {
      case 0:
        return InitiateMeterTestOrDisplay1Token.decoded(
          requestID,
          dataBlock,
          dataBlock,
        );
      case 1:
        return InitiateMeterTestOrDisplay2Token.decoded(
          requestID,
          dataBlock,
          dataBlock,
        );
      default:
        throw TokenError('Unknown Class 1 sub-class: $subClassValue');
    }
  }
}
