import '../base/bit_string.dart';
import '../encryption/encryption_algorithm.dart';
import '../keys/decoder_key.dart';
import '../token/token.dart';

/// Common skeleton of every token-generator. The only shared piece of
/// behaviour is the 66-bit transposition (which is identical for every
/// class) and EA07 encryption (which any class may delegate to).
abstract class TokenGenerator<T extends Token> {
  final DecoderKey decoderKey;
  final EncryptionAlgorithm encryptionAlgorithm;

  TokenGenerator(this.decoderKey, this.encryptionAlgorithm);

  /// Build the 64-bit decrypted data block for the token. Class
  /// implementations override this to encode their specific payload.
  BitString buildDataBlock(T token);

  /// Generate / populate the token in place. Returns the same token
  /// instance with `encryptedTokenBitString` (66-char binary) and the
  /// CRC field filled in.
  T generate(T token) {
    final dataBlock = buildDataBlock(token);
    final encrypted = encryptionAlgorithm.encrypt(decoderKey, dataBlock);
    final transposed = TokenTransposition.transposeToBinary66(
      token.tokenClass!,
      encrypted,
    );
    token.encryptedTokenBitString = transposed;
    token.decryptedTokenBitString = dataBlock.toPaddedBinary();
    return token;
  }
}
