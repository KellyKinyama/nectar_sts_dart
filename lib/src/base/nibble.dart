import '../exceptions/exceptions.dart';
import 'bit_string.dart';

/// A 4-bit field (0..15). Wraps a [BitString] of length 4.
/// Mirrors `domain/base/Nibble.java`.
class Nibble {
  static const int noBitsNibble = 4;
  static const int maxNibbleValue = 15;

  BitString _bitString;

  Nibble() : _bitString = BitString.fromValue(0, noBitsNibble);

  Nibble.fromBitString(BitString bs) : _bitString = bs {
    setNibble(bs);
  }

  BitString get nibble => _bitString;

  void setNibble(BitString bs) {
    if (bs.value <= maxNibbleValue) {
      _bitString = bs;
      _bitString.length = noBitsNibble;
    } else {
      throw const InvalidNibbleBitStringException('Nibble value exceeds 0xF');
    }
  }

  List<int> getCharArray() => _bitString.getBits();
}
