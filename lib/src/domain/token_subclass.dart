import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// 4-bit token sub-class, occupying the top 4 bits of the 64-bit
/// decrypted token data block. Sub-class semantics depend on the
/// owning class:
///
/// Class 0 (Credit Transfer):
///   0  Electricity
///   1  Water
///   2  Gas
///   3  Time
///   4  Electricity (currency-denominated)
class TokenSubClass {
  static const int noOfBits = 4;
  final BitString bitString;
  final String name;

  TokenSubClass._(int value, this.name)
    : assert(value >= 0 && value <= 15),
      bitString = BitString.fromValue(value, noOfBits);

  factory TokenSubClass(int value, String name) {
    if (value < 0 || value > 15) {
      throw InvalidTokenSubclassException(
        'Token sub-class must be 0..15, got $value',
      );
    }
    return TokenSubClass._(value, name);
  }

  // Class 0 sub-classes.
  factory TokenSubClass.electricityCredit() =>
      TokenSubClass._(0, 'Electricity');
  factory TokenSubClass.waterCredit() => TokenSubClass._(1, 'Water');
  factory TokenSubClass.gasCredit() => TokenSubClass._(2, 'Gas');
  factory TokenSubClass.timeCredit() => TokenSubClass._(3, 'Time');
  factory TokenSubClass.electricityCurrencyCredit() =>
      TokenSubClass._(4, 'Electricity Currency');

  // Class 1 sub-classes.
  factory TokenSubClass.initiateMeterTestDisplay1() =>
      TokenSubClass._(0, 'InitiateMeterTestDisplay1');
  factory TokenSubClass.initiateMeterTestDisplay2() =>
      TokenSubClass._(1, 'InitiateMeterTestDisplay2');

  @override
  String toString() => bitString.toString();
}
