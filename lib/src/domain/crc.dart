import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import '../util/utils.dart';

/// CRC-16/IBM with reversed polynomial 0xA001 (== reversed 0x8005).
///
/// Mirrors `domain/Crc.java`. The output bytes are byte-swapped before
/// being returned (per the Java original), matching the on-wire byte
/// order for STS tokens.
class Crc {
  /// Width of the CRC bit-field on the wire (`16`).
  static const int noOfBits = 16;
  BitString _bits;

  /// Creates a zero-valued 16-bit CRC placeholder, ready to be filled
  /// by [generateCrc] / [generateCrcBytes].
  Crc() : _bits = BitString.fromValue(0, noOfBits);

  /// Wraps an existing 16-bit CRC value.
  ///
  /// Throws [InvalidRangeException] if [bs] is not exactly 16 bits
  /// wide.
  Crc.fromBitString(BitString bs) : _bits = bs {
    if (bs.length != noOfBits) {
      throw const InvalidRangeException('CRC must be 16 bits');
    }
  }

  /// The 16-bit CRC as a [BitString].
  BitString get bitString => _bits;

  /// Compute the CRC of the *value* of `initialBitString` (interpreted
  /// as a 7-byte big-endian payload, as the Java code does via
  /// `Utils.longToBytes`).
  BitString generateCrc(BitString initialBitString) {
    final bytes = Utils.longToBytes7(initialBitString.value);
    final crc = generateCrcBytes(bytes);
    return BitString.fromValue(crc, noOfBits);
  }

  /// CRC-16/IBM (reversed polynomial 0xA001), with the resulting 16-bit
  /// value byte-swapped before return (matches `Crc.generateCRC(byte[])`).
  int generateCrcBytes(List<int> bytes) {
    var crc = 0xFFFF;
    for (var pos = 0; pos < bytes.length; pos++) {
      crc ^= (0xFF & bytes[pos]);
      for (var i = 8; i != 0; i--) {
        if ((crc & 0x0001) != 0) {
          crc >>= 1;
          crc ^= 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    final swapped = ((crc & 0xFF) << 8) | ((crc >> 8) & 0xFF);
    return swapped & 0xFFFF;
  }
}
