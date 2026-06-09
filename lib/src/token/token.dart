import '../base/bit_string.dart';
import '../domain/crc.dart';
import '../domain/token_class.dart';
import '../domain/token_subclass.dart';
import '../exceptions/exceptions.dart';

/// Abstract base of every STS token.
///
/// Direct port of `domain/token/Token.java`. The token is conceptually
/// a 66-bit value:
///
///   - the top 2 bits are the [TokenClass]
///   - the lower 64 bits are the EA07-encrypted data block (with bits
///     27/28 of that block already replaced by the class bits via
///     [transposeToBinary66] — see below)
///
/// On the wire / on paper the token is displayed as 20 decimal digits
/// (BigInteger of the 66-bit value, zero-padded to 20).
///
/// The 64-bit decrypted data block layout (LSB-first, matching the
/// Java code's `crc.concat(amount, tid, random, subClass)` order) is:
///
///   bits  0..15   CRC-16/IBM             (16)
///   bits 16..31   Amount                 (16)
///   bits 32..55   TokenIdentifier (TID)  (24)
///   bits 56..59   RandomNo               (4)
///   bits 60..63   TokenSubClass          (4)
abstract class Token {
  String requestID;
  String? encryptedTokenBitString; // 66 chars of '0'/'1', MSB-first
  String? decryptedTokenBitString; // 64 chars of '0'/'1', MSB-first
  Crc? crc;
  TokenClass? tokenClass;
  TokenSubClass? tokenSubClass;

  Token(this.requestID);

  /// e.g. "Electricity_00".
  String get type;

  /// Re-hydrate this token from the decrypted + encrypted blocks
  /// already extracted by the decoder.
  void decode(BitString decryptedDataBlock, BitString encryptedDataBlock);

  /// 20-digit displayable form, e.g. "12345678901234567890".
  /// Built from the 66-bit binary string by BigInteger -> decimal,
  /// zero-padded to 20. Mirrors Java's regex grouping which is a no-op
  /// (`$1$2$3$4$5` reassembles without separators).
  String get tokenNo {
    if (encryptedTokenBitString == null) {
      throw const InvalidTokenException(
        'Token has not been generated yet (encryptedTokenBitString is null)',
      );
    }
    final n = BigInt.parse(encryptedTokenBitString!, radix: 2);
    return n.toString().padLeft(20, '0');
  }

  /// Verify the CRC field inside the decrypted block. Throws [CrcError]
  /// if it doesn't match the computed CRC over
  /// `amount || tid || rnd || subclass || class`.
  bool checkCrc(BitString decryptedDataBlock, TokenClass tokenClass) {
    final computed = calculateCrc(decryptedDataBlock, tokenClass);
    final extracted = decryptedDataBlock.extractBits(0, 16);
    if (computed.compareTo(extracted) != BitString.sameCmp) {
      throw const CrcError('CRC mismatch on token decode');
    }
    return true;
  }

  /// CRC over the 48-bit APDU-without-CRC concatenated with the
  /// 2-bit token class.
  BitString calculateCrc(BitString decryptedDataBlock, TokenClass tokenClass) {
    final apdu = decryptedDataBlock.extractBits(16, 48);
    final combined = apdu.concat([tokenClass.bitString]);
    return Crc().generateCrc(combined);
  }

  Crc extractCrc(BitString dataBlock) =>
      Crc.fromBitString(dataBlock.extractBits(0, 16));

  @override
  String toString() =>
      'RequestID: $requestID, Token: '
      '${encryptedTokenBitString == null ? '<not generated>' : tokenNo}';
}

/// Helpers for the 66-bit token transposition that gets prepended /
/// inserted around the encrypted 64-bit block.
class TokenTransposition {
  TokenTransposition._();

  /// Generator side: take the encrypted 64-bit block, swap bits 27 and
  /// 28 with the 2 class bits, then prepend the *displaced* bits to
  /// produce a 66-char binary string (MSB-first).
  static String transposeToBinary66(
    TokenClass tokenClass,
    BitString encrypted64,
  ) {
    if (encrypted64.length != 64) {
      throw const InvalidBitStringException(
        'transposeToBinary66 requires a 64-bit encrypted block',
      );
    }
    final out = encrypted64.clone();
    final b27 = out.getBit(27).intValue;
    final b28 = out.getBit(28).intValue;
    out.setBitChar(27, tokenClass.bitString.getBit(0).value);
    out.setBitChar(28, tokenClass.bitString.getBit(1).value);
    final low64Bin = out.toPaddedBinary();
    return '$b28$b27$low64Bin';
  }

  /// Decoder side: take the 66-char binary string, recover the token
  /// class bits and the original encrypted 64-bit block.
  static ({TokenClass tokenClass, BitString encrypted64})
  untransposeFromBinary66(String binary66) {
    if (binary66.length != 66 || !RegExp(r'^[01]{66}$').hasMatch(binary66)) {
      throw const InvalidBitStringException(
        'untransposeFromBinary66 requires a 66-char binary string',
      );
    }
    final b28 = binary66[0];
    final b27 = binary66[1];
    // low64Bin is MSB-first: index 0 = bit 63, index 63 = bit 0.
    final low64Bin = binary66.substring(2);

    // Class bits are at bit positions 27 (low) and 28 (high) of the
    // encrypted block. In an MSB-first string, bit N is at index 63-N.
    final classLowChar = low64Bin[63 - 27];
    final classHighChar = low64Bin[63 - 28];
    final klass =
        ((classHighChar == '1' ? 1 : 0) << 1) | (classLowChar == '1' ? 1 : 0);

    // Restore the original encrypted bits by string-splicing — avoids
    // any 64-bit-int round-trip that would clobber the MSB on VMs
    // where int is 64-bit *signed*.
    final chars = low64Bin.split('');
    chars[63 - 27] = b27;
    chars[63 - 28] = b28;
    final restored = chars.join();
    // BigInt -> .toSigned(64).toInt() preserves the bit pattern even
    // when bit 63 is set; int.parse(radix:2) and BigInt.toInt() both
    // reject / clamp those values on Dart VM.
    final low64 = BigInt.parse(restored, radix: 2).toSigned(64).toInt();
    final bs = BitString.fromValue(low64, 64);

    return (tokenClass: TokenClass(klass, 'recovered'), encrypted64: bs);
  }

  /// Decode a 20-digit decimal token string into the 66-char binary
  /// string. Inverts [Token.tokenNo].
  static String tokenNoToBinary66(String decimal20) {
    final cleaned = decimal20.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9]{1,20}$').hasMatch(cleaned)) {
      throw const InvalidTokenException(
        'Token number must be 1..20 decimal digits',
      );
    }
    final n = BigInt.parse(cleaned);
    return n.toRadixString(2).padLeft(66, '0');
  }
}
