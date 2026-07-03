import '../base/bit_string.dart';
import '../keys/decoder_key.dart';

/// Algorithm code in the IEC 62055-41 encryption-algorithm field.
enum EncryptionAlgorithmCode {
  sta('07'),
  dea('09'),
  misty1('11');

  /// Two-digit STS code as it appears in key-parameter fields
  /// (`'07'`, `'09'`, `'11'`).
  final String name;

  /// Named constant constructor for the fixed EA-code set.
  const EncryptionAlgorithmCode(this.name);
}

/// Common contract for EA07 (STA), EA09 (DEA) and EA11 (MISTY1).
abstract class EncryptionAlgorithm {
  /// The algorithm identifier for this implementation.
  final EncryptionAlgorithmCode code;

  /// Base constructor for subclasses; binds the algorithm identifier.
  const EncryptionAlgorithm(this.code);

  /// Encrypts a fixed-width [dataBlock] with [decoderKey].
  ///
  /// The expected [dataBlock] width and [decoderKey] size depend on
  /// the concrete algorithm (64-bit block for STA/DEA, 64-bit block
  /// with a 128-bit key for MISTY1).
  BitString encrypt(DecoderKey decoderKey, BitString dataBlock);

  /// Decrypts a fixed-width [dataBlock] with [decoderKey].
  ///
  /// The inverse of [encrypt]; block/key widths are the same.
  BitString decrypt(DecoderKey decoderKey, BitString dataBlock);
}
