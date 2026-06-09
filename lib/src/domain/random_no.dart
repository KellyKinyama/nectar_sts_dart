import 'dart:math';

import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// 4-bit random number embedded in every Class 0 / Class 2 token.
///
/// The random isn't cryptographically meaningful — it just decorrelates
/// otherwise-identical tokens (same amount, same minute) so they CRC
/// and encrypt to different ciphertexts.
class RandomNo {
  static const int noOfBits = 4;
  final BitString bitString;

  RandomNo(this.bitString) {
    if (bitString.length != noOfBits ||
        bitString.value < 0 ||
        bitString.value > 15) {
      throw const InvalidRangeException(
        'RandomNo must be a 4-bit BitString in [0..15]',
      );
    }
  }

  factory RandomNo.fromInt(int value) {
    if (value < 0 || value > 15) {
      throw const InvalidRangeException('RandomNo value must be 0..15');
    }
    return RandomNo(BitString.fromValue(value, noOfBits));
  }

  factory RandomNo.random([Random? rng]) {
    final r = rng ?? Random.secure();
    return RandomNo.fromInt(r.nextInt(16));
  }

  String get name => 'RandomNo';
}
