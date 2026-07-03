import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class0_tokens.dart';
import '../token/token.dart';

/// Decoder for Class 0 / SubClass 1 "Transfer Water Credit" tokens.
/// Identical decrypt path to [TransferElectricityCreditDecoder];
/// only the rehydrated token type differs.
class TransferWaterCreditDecoder {
  /// Decoder key used to decrypt the 64-bit block.
  final DecoderKey decoderKey;

  /// Encryption algorithm used for the decrypt phase.
  final EncryptionAlgorithm encryptionAlgorithm;

  /// Binds [decoderKey] and [encryptionAlgorithm].
  TransferWaterCreditDecoder(this.decoderKey, this.encryptionAlgorithm);

  /// Decode a water-credit token from its 20-digit displayable form.
  TransferWaterCreditToken decodeDecimal(String requestID, String decimal20) {
    final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
    return decodeBinary66(requestID, binary66);
  }

  /// Decode a water-credit token from the raw 66-bit binary string.
  ///
  /// Throws [TokenError] when the token class is not 0.
  TransferWaterCreditToken decodeBinary66(String requestID, String binary66) {
    final r = TokenTransposition.untransposeFromBinary66(binary66);
    if (r.tokenClass.bitString.value != 0) {
      throw const TokenError(
        'Token class is not 0 — not a water credit transfer token',
      );
    }
    final decrypted = encryptionAlgorithm.decrypt(decoderKey, r.encrypted64);
    final decrypted64 = BitString.fromValue(decrypted.value, 64);
    final encrypted64 = BitString.fromValue(r.encrypted64.value, 64);
    return TransferWaterCreditToken.decoded(
      requestID,
      decrypted64,
      encrypted64,
    );
  }
}
