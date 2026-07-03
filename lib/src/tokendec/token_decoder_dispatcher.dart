import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class0_tokens.dart';
import '../token/token.dart';
import 'class1_token_decoder.dart';
import 'class2_token_decoder.dart';

/// Result of a top-level decode operation. Either a fully-rehydrated
/// [Token] on success, or a structured [DecodeFailure] on any error.
///
/// Using a sealed class instead of plain exceptions lets callers
/// pattern-match on the outcome (e.g. log + reject rather than crash).
sealed class DecodeResult {
  const DecodeResult();
}

/// Success arm of a [DecodeResult].
class DecodeAccepted extends DecodeResult {
  /// The fully-rehydrated token returned to the caller.
  final Token token;

  /// Wraps a successfully decoded [token].
  const DecodeAccepted(this.token);
}

/// Failure arm of a [DecodeResult].
class DecodeFailure extends DecodeResult {
  /// The structured [StsError] that terminated the decode.
  final StsError error;

  /// Short human-readable reason (safe for logs / HTTP body).
  final String reason;

  /// Wraps a decode failure with its [error] and [reason].
  const DecodeFailure(this.error, this.reason);

  /// Returns `"DecodeFailure(<reason>)"`.
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
  /// Decoder key used for every class that requires decryption.
  final DecoderKey decoderKey;

  /// Encryption algorithm used for the decrypt phase (STA / MISTY1 /
  /// ...).
  final EncryptionAlgorithm encryptionAlgorithm;

  /// Binds [decoderKey] and [encryptionAlgorithm].
  TokenDecoderDispatcher(this.decoderKey, this.encryptionAlgorithm);

  /// Untranspose [decimal20], route on the token-class bits and
  /// return either [DecodeAccepted] with the rehydrated token or
  /// [DecodeFailure] with a structured error.
  DecodeResult decodeDecimal(String requestID, String decimal20) {
    try {
      final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
      final r = TokenTransposition.untransposeFromBinary66(binary66);
      final klass = r.tokenClass.bitString.value;
      switch (klass) {
        case 0:
          // Class 0 holds two ported subclasses today (0 = kWh
          // electricity credit, 4 = currency-denominated electricity
          // credit). The subclass nibble lives at bits 60..63 of the
          // decrypted data block, so we decrypt once here and route
          // to the right concrete token type without paying for a
          // second decrypt in a child decoder.
          final decrypted = encryptionAlgorithm.decrypt(
            decoderKey,
            r.encrypted64,
          );
          final decrypted64 = BitString.fromValue(decrypted.value, 64);
          final encrypted64 = BitString.fromValue(r.encrypted64.value, 64);
          final sub = decrypted64.extractBits(60, 4).value;
          switch (sub) {
            case 0:
              return DecodeAccepted(
                TransferElectricityCreditToken.decoded(
                  requestID,
                  decrypted64,
                  encrypted64,
                ),
              );
            case 1:
              return DecodeAccepted(
                TransferWaterCreditToken.decoded(
                  requestID,
                  decrypted64,
                  encrypted64,
                ),
              );
            case 2:
              return DecodeAccepted(
                TransferGasCreditToken.decoded(
                  requestID,
                  decrypted64,
                  encrypted64,
                ),
              );
            case 4:
              return DecodeAccepted(
                ElectricityCurrencyCreditToken.decoded(
                  requestID,
                  decrypted64,
                  encrypted64,
                ),
              );
            default:
              return DecodeFailure(
                TokenError('Unsupported Class 0 subclass: $sub'),
                'unsupported class 0 subclass',
              );
          }
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
  /// Like [TokenDecoderDispatcher.decodeDecimal] but re-throws the
  /// [StsError] embedded in [DecodeFailure] instead of returning it.
  Token decodeOrThrow(String requestID, String decimal20) {
    final r = decodeDecimal(requestID, decimal20);
    return switch (r) {
      DecodeAccepted(:final token) => token,
      DecodeFailure(:final error) => throw error,
    };
  }
}
