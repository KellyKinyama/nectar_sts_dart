import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class0_tokens.dart';
import '../token/token.dart';

/// Decoder for Class 0 / SubClass 4 "Electricity Currency" credit
/// tokens. Identical decrypt path to
/// [TransferElectricityCreditDecoder]; only the rehydrated token
/// type differs.
class ElectricityCurrencyCreditDecoder {
  final DecoderKey decoderKey;
  final EncryptionAlgorithm encryptionAlgorithm;

  ElectricityCurrencyCreditDecoder(this.decoderKey, this.encryptionAlgorithm);

  ElectricityCurrencyCreditToken decodeDecimal(
    String requestID,
    String decimal20,
  ) {
    final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
    return decodeBinary66(requestID, binary66);
  }

  ElectricityCurrencyCreditToken decodeBinary66(
    String requestID,
    String binary66,
  ) {
    final r = TokenTransposition.untransposeFromBinary66(binary66);
    if (r.tokenClass.bitString.value != 0) {
      throw const TokenError(
        'Token class is not 0 — not an electricity-currency credit token',
      );
    }
    final decrypted = encryptionAlgorithm.decrypt(decoderKey, r.encrypted64);
    final decrypted64 = BitString.fromValue(decrypted.value, 64);
    final encrypted64 = BitString.fromValue(r.encrypted64.value, 64);
    return ElectricityCurrencyCreditToken.decoded(
      requestID,
      decrypted64,
      encrypted64,
    );
  }
}
