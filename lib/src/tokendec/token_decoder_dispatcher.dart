import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/token.dart';
import 'class1_token_decoder.dart';
import 'class2_token_decoder.dart';
import 'transfer_electricity_credit_decoder.dart';

/// Result of a top-level decode operation. Either a fully-rehydrated
/// [Token] on success, or a structured [DecodeFailure] on any error.
///
/// Using a sealed class instead of plain exceptions lets callers
/// pattern-match on the outcome (e.g. log + reject rather than crash).
sealed class DecodeResult {
  const DecodeResult();
}

class DecodeAccepted extends DecodeResult {
  final Token token;
  const DecodeAccepted(this.token);
}

class DecodeFailure extends DecodeResult {
  final StsError error;
  final String reason;
  const DecodeFailure(this.error, this.reason);

  @override
  String toString() => 'DecodeFailure($reason)';
}

/// Top-level dispatcher: takes any 20-digit token string and routes
/// it to the appropriate class decoder based on the transposed 2-bit
/// token class. Returns a [DecodeResult] rather than throwing.
///
/// Currently supports Class 0 (TransferElectricityCredit) and Class 1
/// (InitiateMeterTestOrDisplay 1/2). Class 2 and Class 3 tokens are
/// rejected with `DecodeFailure(NotImplementedException(...))`.
class TokenDecoderDispatcher {
  final DecoderKey decoderKey;
  final EncryptionAlgorithm encryptionAlgorithm;

  TokenDecoderDispatcher(this.decoderKey, this.encryptionAlgorithm);

  DecodeResult decodeDecimal(String requestID, String decimal20) {
    try {
      final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
      final r = TokenTransposition.untransposeFromBinary66(binary66);
      final klass = r.tokenClass.bitString.value;
      switch (klass) {
        case 0:
          final tok = TransferElectricityCreditDecoder(
            decoderKey,
            encryptionAlgorithm,
          ).decodeBinary66(requestID, binary66);
          return DecodeAccepted(tok);
        case 1:
          final tok = Class1TokenDecoder(
            decoderKey,
            encryptionAlgorithm,
          ).decodeBinary66(requestID, binary66);
          return DecodeAccepted(tok);
        case 2:
          final tok = Class2TokenDecoder(
            decoderKey,
            encryptionAlgorithm,
          ).decodeBinary66(requestID, binary66);
          return DecodeAccepted(tok);
        case 3:
          return const DecodeFailure(
            NotImplementedException(
              'Class 3 (reserved) tokens are not implemented',
            ),
            'class 3 reserved',
          );
        default:
          return DecodeFailure(
            TokenError('Unknown token class: $klass'),
            'unknown token class',
          );
      }
    } on StsError catch (e) {
      return DecodeFailure(e, e.message);
    }
  }
}

/// Convenience for `decodeDecimal` that throws instead of returning
/// a failure result. Useful for tests and one-shot scripts.
extension TokenDecoderDispatcherThrowing on TokenDecoderDispatcher {
  Token decodeOrThrow(String requestID, String decimal20) {
    final r = decodeDecimal(requestID, decimal20);
    return switch (r) {
      DecodeAccepted(:final token) => token,
      DecodeFailure(:final error) => throw error,
    };
  }
}
