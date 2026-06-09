import 'dart:typed_data';

import '../base/bit_string.dart' as bs;
import '../base/bit_string.dart' show RotateDirection;

/// Abstract base for vending / decoder keys.
///
/// Mirrors `domain/keys/Key.java`. Bit numbering for `getKeyBit` /
/// `setKeyBit` / `rotate` follows the Java original:
///
/// - `pos / 8` selects the byte (byte 0 first, then byte 1, etc.).
/// - Within the selected byte, `pos % 8 == 0` is the **LSB** and
///   `pos % 8 == 7` is the MSB.
///
/// So for an 8-byte buffer, bit 0 is the LSB of byte 0 and bit 63 is
/// the MSB of byte 7. This is the same LSB-first-within-byte
/// convention that `BitString` uses, just spread across multiple bytes
/// in storage order.
abstract class Key {
  Uint8List _keyData;

  Key([List<int>? keyData]) : _keyData = Uint8List.fromList(keyData ?? []);

  Uint8List get keyData => _keyData;
  set keyData(List<int> bytes) => _keyData = Uint8List.fromList(bytes);

  String get name;
  String bitsToString();
  bs.BitString get bitString;

  /// Bitwise NOT of the first 8 bytes of the input. The Java original
  /// only iterates `b < 8` regardless of `ec.length`; we mirror that.
  Uint8List complement(List<int> ec) {
    final out = Uint8List(ec.length);
    for (var b = 0; b < 8; b++) {
      out[b] = (~ec[b]) & 0xFF;
    }
    return out;
  }

  /// Rotate-right by 12 bits over the 64-bit complemented key — the
  /// fixed pre-processing step used by EA07's `processDecoderKey`.
  Uint8List rotateComplemented(List<int> complemented) {
    final lenBits = complemented.length * 8;
    return rotate(complemented, lenBits, 12, RotateDirection.right);
  }

  Uint8List rotateRight(List<int> input, int steps) {
    return rotate(input, input.length * 8, steps, RotateDirection.right);
  }

  Uint8List rotateLeft(List<int> input, int steps) {
    return rotate(input, input.length * 8, steps, RotateDirection.left);
  }

  /// Bit-level rotation over the byte array, treating it as one big
  /// MSB-first bit string of length `len`.
  Uint8List rotate(
    List<int> input,
    int len,
    int steps,
    RotateDirection direction,
  ) {
    final numOfBytes = ((len - 1) ~/ 8) + 1;
    final out = Uint8List(numOfBytes);
    for (var i = 0; i < len; i++) {
      final newPos = (i + steps) % len;
      if (direction == RotateDirection.right) {
        final v = getKeyBit(input, newPos);
        setKeyBit(out, i, v);
      } else {
        final v = getKeyBit(input, i);
        setKeyBit(out, newPos, v);
      }
    }
    return out;
  }

  /// MSB-first bit getter: `pos == 0` → bit 7 of `data[0]`.
  int getKeyBit(List<int> data, int pos) {
    final posByte = pos ~/ 8;
    final posBit = 7 - (pos % 8);
    final valByte = data[posByte];
    return (valByte >> (8 - (posBit + 1))) & 0x0001;
  }

  /// MSB-first bit setter.
  void setKeyBit(List<int> data, int pos, int val) {
    final posByte = pos ~/ 8;
    final posBit = 7 - (pos % 8);
    final oldByte = data[posByte];
    // Mirror the Java mask: `(0xFF7F >> posBit) & oldByte` clears the bit
    // at the target position, then OR in the new value.
    final cleared = ((0xFF7F >> posBit) & oldByte) & 0x00FF;
    data[posByte] = (((val & 1) << (8 - (posBit + 1))) | cleared) & 0xFF;
  }
}
