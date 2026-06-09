import '../base/bit_string.dart';
import '../keys/decoder_key.dart';

/// Algorithm code in the IEC 62055-41 encryption-algorithm field.
enum EncryptionAlgorithmCode {
  sta('07'),
  dea('09'),
  misty1('11');

  final String name;
  const EncryptionAlgorithmCode(this.name);
}

/// Common contract for EA07 (STA), EA09 (DEA) and EA11 (MISTY1).
abstract class EncryptionAlgorithm {
  final EncryptionAlgorithmCode code;
  const EncryptionAlgorithm(this.code);

  BitString encrypt(DecoderKey decoderKey, BitString dataBlock);
  BitString decrypt(DecoderKey decoderKey, BitString dataBlock);
}
