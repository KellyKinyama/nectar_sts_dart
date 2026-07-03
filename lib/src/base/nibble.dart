import '../exceptions/exceptions.dart';
import 'bit_string.dart';

/// A 4-bit field (0..15). Wraps a [BitString] of length 4.
/// Mirrors `domain/base/Nibble.java`.
///
/// Example:
/// ```dart
/// // Extract the low nibble of an 8-bit field.
/// final byte = BitString.fromValue(0xAB, 8);
/// final low  = byte.getNibble(0);
/// low.nibble.value; // 0xB
/// ```
class Nibble {
  /// Bit width of a nibble (`4`).
  static const int noBitsNibble = 4;

  /// Largest value a [Nibble] may hold (`0xF` == `15`).
  static const int maxNibbleValue = 15;

  BitString _bitString;

  /// Creates a zero-valued nibble.
  Nibble() : _bitString = BitString.fromValue(0, noBitsNibble);

  /// Wraps an existing 4-bit [BitString].
  ///
  /// The supplied [bs] must have `value <= 0xF`; otherwise
  /// [InvalidNibbleBitStringException] is thrown.
  Nibble.fromBitString(BitString bs) : _bitString = bs {
    setNibble(bs);
  }

  /// The 4-bit backing [BitString].
  BitString get nibble => _bitString;

  /// Replaces the backing value with [bs].
  ///
  /// [bs] must satisfy `value <= 0xF`. The stored [BitString] is
  /// resized to exactly [noBitsNibble] bits.
  void setNibble(BitString bs) {
    if (bs.value <= maxNibbleValue) {
      _bitString = bs;
      _bitString.length = noBitsNibble;
    } else {
      throw const InvalidNibbleBitStringException('Nibble value exceeds 0xF');
    }
  }

  /// Returns the four bits as `'0'`/`'1'` character codes, LSB-first.
  List<int> getCharArray() => _bitString.getBits();
}
