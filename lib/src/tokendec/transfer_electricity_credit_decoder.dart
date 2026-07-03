import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class0_tokens.dart';
import '../token/token.dart';

/// Decoder for Class 0 / SubClass 0 "Transfer Electricity Credit"
/// tokens. Accepts either a 20-digit decimal token string or the
/// already-decoded 66-bit binary string, untransposes, decrypts and
/// rebuilds the [TransferElectricityCreditToken].
///
/// Example (from `test/token_round_trip_test.dart`):
/// ```dart
/// final decoded = TransferElectricityCreditDecoder(
///   decoderKey,
///   StandardTransferAlgorithm(),
/// ).decodeDecimal('req-001-back', token.tokenNo);
///
/// decoded.amountPurchased!.unitsPurchased; // 5.5
/// decoded.tokenClass!.bitString.value;     // 0
/// ```
class TransferElectricityCreditDecoder {
  /// Decoder key used to decrypt the 64-bit block.
  final DecoderKey decoderKey;

  /// Encryption algorithm used for the decrypt phase.
  final EncryptionAlgorithm encryptionAlgorithm;

  /// Binds [decoderKey] and [encryptionAlgorithm].
  TransferElectricityCreditDecoder(this.decoderKey, this.encryptionAlgorithm);

  /// Decode a token from its 20-digit displayable form.
  TransferElectricityCreditToken decodeDecimal(
    String requestID,
    String decimal20,
  ) {
    final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
    return decodeBinary66(requestID, binary66);
  }

  /// Decode a token from the raw 66-bit binary string.
  TransferElectricityCreditToken decodeBinary66(
    String requestID,
    String binary66,
  ) {
    final r = TokenTransposition.untransposeFromBinary66(binary66);
    if (r.tokenClass.bitString.value != 0) {
      throw const TokenError(
        'Token class is not 0 — not an electricity credit transfer token',
      );
    }
    final decrypted = encryptionAlgorithm.decrypt(decoderKey, r.encrypted64);
    // Force length to 64 so extractBits below behaves.
    final decrypted64 = BitString.fromValue(decrypted.value, 64);
    final encrypted64 = BitString.fromValue(r.encrypted64.value, 64);
    return TransferElectricityCreditToken.decoded(
      requestID,
      decrypted64,
      encrypted64,
    );
  }
}
