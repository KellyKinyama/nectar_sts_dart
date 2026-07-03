import 'dart:math';

import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// 4-bit random number embedded in every Class 0 / Class 2 token.
///
/// The random isn't cryptographically meaningful — it just decorrelates
/// otherwise-identical tokens (same amount, same minute) so they CRC
/// and encrypt to different ciphertexts.
class RandomNo {
  /// Width of the random-number bit-field on the wire (`4`).
  static const int noOfBits = 4;

  /// Packed 4-bit random value in `0..15`.
  final BitString bitString;

  /// Wraps a pre-built 4-bit [BitString].
  ///
  /// Throws [InvalidRangeException] if [bitString] is not exactly 4
  /// bits or its value is outside `0..15`.
  RandomNo(this.bitString) {
    if (bitString.length != noOfBits ||
        bitString.value < 0 ||
        bitString.value > 15) {
      throw const InvalidRangeException(
        'RandomNo must be a 4-bit BitString in [0..15]',
      );
    }
  }

  /// Builds a [RandomNo] from an integer in `0..15`.
  factory RandomNo.fromInt(int value) {
    if (value < 0 || value > 15) {
      throw const InvalidRangeException('RandomNo value must be 0..15');
    }
    return RandomNo(BitString.fromValue(value, noOfBits));
  }

  /// Draws a random value in `0..15`.
  ///
  /// Uses [Random.secure] by default; pass [rng] to inject a
  /// deterministic source in tests.
  factory RandomNo.random([Random? rng]) {
    final r = rng ?? Random.secure();
    return RandomNo.fromInt(r.nextInt(16));
  }

  /// Human-readable field name (`"RandomNo"`).
  String get name => 'RandomNo';
}
