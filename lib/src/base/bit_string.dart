import '../exceptions/exceptions.dart';
import 'bit.dart';
import 'nibble.dart';

/// A bit field of up to 64 bits.
///
/// Internally a Dart `int` (64-bit on the VM) plus an explicit `length`.
/// Bit positions are indexed **LSB-first**: bit 0 is the least
/// significant bit, bit `length - 1` is the most significant. This
/// matches the original Java `BitString` API.
///
/// Direct port of `domain/base/BitString.java`.
class BitString implements Comparable<BitString> {
  static const int sameCmp = 0;
  static const int lessThanCmp = -1;
  static const int greaterThanCmp = 1;

  static const int maxNoBits = 64;

  int _value = 0;
  int _length = maxNoBits;

  BitString() {
    _length = maxNoBits;
  }

  BitString.fromValue(int value, [int? length])
    : _value = value,
      _length = length ?? maxNoBits;

  BitString.fromBinary(String bits) {
    setValueFromString(bits);
    _length = bits.length;
  }

  int get value => _value;
  set value(int v) => _value = v;

  int get length => _length;
  set length(int n) => _length = n;

  void setValueFromString(String bits) {
    if (bits.isEmpty || bits.length > 64) {
      throw const InvalidBitStringException('Invalid bitstring length');
    }
    for (var i = 0; i < bits.length; i++) {
      final c = bits.codeUnitAt(i);
      if (c != 0x30 && c != 0x31) {
        throw InvalidBitStringException('Invalid bitstring: $bits');
      }
    }
    _value = int.parse(bits, radix: 2);
  }

  @override
  int compareTo(BitString other) {
    if (_length != other._length) {
      throw const IllegalComparisonError(
        'BitString length mismatch in comparison',
      );
    }
    if (_value == other._value) return sameCmp;
    return _value < other._value ? lessThanCmp : greaterThanCmp;
  }

  /// Concatenates `[bitStrings]` onto `this`.
  ///
  /// Java semantics: existing bits stay in the low positions, each
  /// appended bitstring is shifted up by the running total of bits seen
  /// so far. The result is the original bits in the LSBs followed by
  /// the appended bits in increasing significance.
  BitString concat(List<BitString> bitStrings) {
    var result = _value;
    var noOfBits = _length;
    var previousShift = noOfBits;
    for (final bs in bitStrings) {
      noOfBits += bs._length;
    }
    if (noOfBits > maxNoBits) {
      throw const BitConcatOverflowError(
        'BitString concatenation overflows 64 bits',
      );
    }
    for (final cur in bitStrings) {
      result |= (cur._value << previousShift);
      previousShift += cur._length;
    }
    return BitString.fromValue(result, noOfBits);
  }

  /// Replace bits in the range `[startIndex, endIndex]` (both inclusive,
  /// LSB-indexed) with the supplied '0'/'1' character codes. Length of
  /// `replacementBits` must equal `endIndex - startIndex + 1`.
  void setBitsRangeChars(
    int startIndex,
    int endIndex,
    List<int> replacementBits,
  ) {
    if (replacementBits.length != endIndex - startIndex + 1) {
      throw const InvalidRangeException(
        'replacement length does not match range',
      );
    }
    for (var k = 0; startIndex <= endIndex; startIndex++, k++) {
      setBitChar(startIndex, replacementBits[k]);
    }
  }

  /// Extract `[noOfBits]` bits starting at LSB-position `[startIndex]`.
  BitString extractBits(int startIndex, int noOfBits) {
    if (noOfBits <= 0) {
      throw const InvalidRangeException('extract requires at least 1 bit');
    }
    if (startIndex + noOfBits > _length) {
      throw const InvalidRangeException('extract range exceeds bitstring');
    }
    // Java: long allOnes = ~0;
    //       long mask = (allOnes << (64 - noOfBits)) >>> (64 - startIndex - noOfBits);
    //       long extracted = (value & mask) << (length - (startIndex + noOfBits)) >>> (length - noOfBits);
    final allOnes = -1;
    final mask =
        (allOnes << (maxNoBits - noOfBits)).toUnsigned(64) >>>
        (maxNoBits - startIndex - noOfBits);
    final extracted =
        ((_value & mask) << (_length - (startIndex + noOfBits))).toUnsigned(
          64,
        ) >>>
        (_length - noOfBits);
    final out = BitString.fromValue(extracted, noOfBits);
    return out;
  }

  Nibble getNibble(int nibblePosition) {
    const sizeOfNibble = 4;
    final noOfNibbles = _length ~/ sizeOfNibble;
    if (nibblePosition < 0 || nibblePosition >= noOfNibbles) {
      throw const NibbleOutOfRangeException('Nibble position out of range');
    }
    final startNibbleIndex = nibblePosition * 4;
    final extracted = extractBits(startNibbleIndex, sizeOfNibble);
    return Nibble.fromBitString(extracted);
  }

  void setNibble(int nibblePosition, Nibble substitute) {
    const sizeOfNibble = 4;
    final noOfNibbles = _length ~/ sizeOfNibble;
    if (nibblePosition < 0 || nibblePosition >= noOfNibbles) {
      throw const NibbleOutOfRangeException('Nibble position out of range');
    }
    final startIndex = nibblePosition * 4;
    final endIndex = startIndex + 3;
    setBitsRangeChars(startIndex, endIndex, substitute.getCharArray());
  }

  Bit getBit(int position) {
    final mask = (1 << position);
    final bit = (_value & mask) >>> position;
    return Bit(bit == 0 ? 0x30 : 0x31);
  }

  /// Set the bit at `index` using a '0' / '1' character code (0x30/0x31).
  void setBitChar(int index, int charCode) {
    if (charCode == 0x31) {
      setBit(index);
    } else if (charCode == 0x30) {
      clearBit(index);
    }
  }

  void setBit(int position) {
    _value |= (1 << position);
  }

  void clearBit(int position) {
    _value &= ~(1 << position);
  }

  void setBitsRange(int fromIndex, int toIndex) {
    if (toIndex < fromIndex || (fromIndex - toIndex).abs() > maxNoBits) {
      throw const InvalidRangeException('Invalid range for setBitsRange');
    }
    while (fromIndex <= toIndex) {
      setBit(fromIndex);
      fromIndex++;
    }
  }

  void clearBitRange(int fromIndex, int toIndex) {
    if (toIndex < fromIndex || (fromIndex - toIndex).abs() > maxNoBits) {
      throw const InvalidRangeException('Invalid range for clearBitRange');
    }
    while (fromIndex <= toIndex) {
      clearBit(fromIndex);
      fromIndex++;
    }
  }

  static BitString rotate(
    BitString bitString,
    RotateDirection direction,
    int shiftSteps,
  ) {
    final rotated = bitString.clone();
    if (bitString._length == maxNoBits) {
      final bits = direction == RotateDirection.right
          ? _rotateRight64(rotated._value, shiftSteps)
          : _rotateLeft64(rotated._value, shiftSteps);
      return BitString.fromValue(bits, bitString._length);
    }

    if (direction == RotateDirection.right) {
      final extracted = bitString.extractBits(0, shiftSteps);
      final mod = shiftSteps % bitString._length;
      rotated.setBitsRangeChars(
        bitString._length - mod,
        bitString._length - 1,
        extracted.getBits(),
      );
      final translated = bitString.extractBits(mod, bitString._length - mod);
      rotated.setBitsRangeChars(
        0,
        bitString._length - mod - 1,
        translated.getBits(),
      );
    } else {
      final extracted = bitString
          .extractBits(bitString._length - shiftSteps, shiftSteps)
          .flip();
      rotated.setBitsRangeChars(0, shiftSteps - 1, extracted.getBits());
      final translated = bitString.extractBits(
        0,
        bitString._length - shiftSteps,
      );
      rotated.setBitsRangeChars(
        shiftSteps,
        bitString._length - 1,
        translated.getBits(),
      );
    }
    return rotated;
  }

  static int _rotateLeft64(int v, int n) {
    n &= 63;
    if (n == 0) return v;
    final lo = v.toUnsigned(64);
    return ((lo << n) | (lo >>> (64 - n))).toUnsigned(64);
  }

  static int _rotateRight64(int v, int n) {
    n &= 63;
    if (n == 0) return v;
    final lo = v.toUnsigned(64);
    return ((lo >>> n) | (lo << (64 - n))).toUnsigned(64);
  }

  @override
  String toString() => _value.toRadixString(2);

  String toHexString() => _value.toRadixString(16);

  /// Returns the bits as a List of '0' / '1' character codes,
  /// ordered LSB-first (index 0 = bit 0).
  List<int> getBits() {
    final bits = List<int>.filled(_length, 0x30);
    for (var i = 0; i < _length; i++) {
      bits[i] = getBit(i).value;
    }
    return bits;
  }

  /// Reverse the bit order within `[length]`.
  BitString flip() {
    final bits = getBits();
    final flipped = clone();
    for (var fwd = 0, b = _length - 1; b >= 0; b--, fwd++) {
      flipped.setBitChar(b, bits[fwd]);
    }
    return flipped;
  }

  BitString clone() => BitString.fromValue(_value, _length);

  /// MSB-first padded binary string (used by formatters that mirror
  /// `String.format("%Ns", Long.toBinaryString(...))`).
  String toPaddedBinary() {
    // Route via BigInt so values with bit 63 set (which appear as
    // negative signed ints) emit an unsigned binary string instead of
    // a `-`-prefixed one.
    final s = BigInt.from(_value).toUnsigned(64).toRadixString(2);
    if (s.length >= _length) return s.substring(s.length - _length);
    return '${'0' * (_length - s.length)}$s';
  }
}

enum RotateDirection { left, right }
