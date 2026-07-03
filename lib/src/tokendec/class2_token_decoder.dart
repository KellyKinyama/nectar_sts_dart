import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../exceptions/exceptions.dart';
import '../keys/decoder_key.dart';
import '../token/class2_tokens.dart';
import '../token/token.dart';

/// Decoder for Class 2 (management / engineering) tokens.
///
/// Dispatches on the 4-bit token sub-class (bits 60..63 of the
/// decrypted block). Currently supports the 64-bit decoder-key
/// transfer pair (1st + 2nd sections); 3rd / 4th section (for the
/// 128-bit MISTY1 path) are rejected with [NotImplementedException].
class Class2TokenDecoder {
  /// Current decoder key used to decrypt the 64-bit block.
  final DecoderKey decoderKey;

  /// Encryption algorithm used for the decrypt phase (STA / MISTY1 /
  /// ...).
  final EncryptionAlgorithm encryptionAlgorithm;

  /// Binds [decoderKey] and [encryptionAlgorithm].
  Class2TokenDecoder(this.decoderKey, this.encryptionAlgorithm);

  /// Decode a Class 2 token from its 20-digit displayable form.
  Class2Token decodeDecimal(String requestID, String decimal20) {
    final binary66 = TokenTransposition.tokenNoToBinary66(decimal20);
    return decodeBinary66(requestID, binary66);
  }

  /// Decode a Class 2 token from the raw 66-bit binary string.
  ///
  /// Throws [TokenError] when the token class is not 2, and
  /// [NotImplementedException] for unsupported sub-classes.
  Class2Token decodeBinary66(String requestID, String binary66) {
    final r = TokenTransposition.untransposeFromBinary66(binary66);
    if (r.tokenClass.bitString.value != 2) {
      throw const TokenError('Token class is not 2 — not a Class 2 token');
    }
    final decrypted = encryptionAlgorithm.decrypt(decoderKey, r.encrypted64);
    final decrypted64 = BitString.fromValue(decrypted.value, 64);
    final encrypted64 = BitString.fromValue(r.encrypted64.value, 64);

    final subClassValue = decrypted64.extractBits(60, 4).value;
    switch (subClassValue) {
      case 0x0:
        return SetMaximumPowerLimitToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 0x1:
        return ClearCreditToken.decoded(requestID, decrypted64, encrypted64);
      case 0x2:
        return SetTariffRateToken.decoded(requestID, decrypted64, encrypted64);
      case 0x3:
        return Set1stSectionDecoderKeyToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 0x4:
        return Set2ndSectionDecoderKeyToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 0x5:
        return ClearTamperConditionToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 0x6:
        return SetMaximumPhasePowerUnbalanceLimitToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 0x7:
        throw NotImplementedException(
          'Class 2 SubClass 0x7 (SetWaterMeterFactor) is not ported — '
          'water meters are out of scope',
        );
      case 0x8:
        return Set3rdSectionDecoderKeyToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      case 0x9:
        return Set4thSectionDecoderKeyToken.decoded(
          requestID,
          decrypted64,
          encrypted64,
        );
      default:
        throw NotImplementedException(
          'Class 2 SubClass 0x${subClassValue.toRadixString(16)} is not '
          'defined in STS Edition 1',
        );
    }
  }
}
