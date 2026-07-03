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
///
/// Example:
/// ```dart
/// TokenSubClass.electricityCredit().bitString.value;         // 0
/// TokenSubClass.set1stSectionDecoderKey().bitString.value;   // 0x3
/// TokenSubClass.set4thSectionDecoderKey().bitString.value;   // 0x9
/// ```
class TokenSubClass {
  /// Width of the sub-class bit-field on the wire (`4`).
  static const int noOfBits = 4;

  /// Packed 4-bit sub-class value.
  final BitString bitString;

  /// Human-readable label for this sub-class.
  final String name;

  TokenSubClass._(int value, this.name)
      : assert(value >= 0 && value <= 15),
        bitString = BitString.fromValue(value, noOfBits);

  /// Builds a [TokenSubClass] with an arbitrary [value] in `0..15` and
  /// a caller-supplied [name].
  ///
  /// Throws [InvalidTokenSubclassException] when [value] is outside
  /// `0..15`. Prefer one of the named factory constructors below.
  factory TokenSubClass(int value, String name) {
    if (value < 0 || value > 15) {
      throw InvalidTokenSubclassException(
        'Token sub-class must be 0..15, got $value',
      );
    }
    return TokenSubClass._(value, name);
  }

  // Class 0 sub-classes.

  /// Class 0 sub-class 0 — electricity credit.
  factory TokenSubClass.electricityCredit() =>
      TokenSubClass._(0, 'Electricity');

  /// Class 0 sub-class 1 — water credit.
  factory TokenSubClass.waterCredit() => TokenSubClass._(1, 'Water');

  /// Class 0 sub-class 2 — gas credit.
  factory TokenSubClass.gasCredit() => TokenSubClass._(2, 'Gas');

  /// Class 0 sub-class 3 — time credit.
  factory TokenSubClass.timeCredit() => TokenSubClass._(3, 'Time');

  /// Class 0 sub-class 4 — electricity credit denominated in currency.
  factory TokenSubClass.electricityCurrencyCredit() =>
      TokenSubClass._(4, 'Electricity Currency');

  // Class 1 sub-classes.

  /// Class 1 sub-class 0 — initiate meter test / display, variant 1.
  factory TokenSubClass.initiateMeterTestDisplay1() =>
      TokenSubClass._(0, 'InitiateMeterTestDisplay1');

  /// Class 1 sub-class 1 — initiate meter test / display, variant 2.
  factory TokenSubClass.initiateMeterTestDisplay2() =>
      TokenSubClass._(1, 'InitiateMeterTestDisplay2');

  // Class 2 sub-classes (engineering / management). Numeric values
  // match the upstream Java `tokensubclass.class2.*` constants.

  /// Class 2 sub-class 0x0 — set Maximum Power Limit.
  factory TokenSubClass.setMaximumPowerLimit() =>
      TokenSubClass._(0x0, 'SetMaximumPowerLimit');

  /// Class 2 sub-class 0x1 — clear accumulated credit.
  factory TokenSubClass.clearCredit() => TokenSubClass._(0x1, 'ClearCredit');

  /// Class 2 sub-class 0x2 — set tariff rate.
  factory TokenSubClass.setTariffRate() =>
      TokenSubClass._(0x2, 'SetTariffRate');

  /// Class 2 sub-class 0x3 — install 1st section of new decoder key
  /// (KCT stage 1).
  factory TokenSubClass.set1stSectionDecoderKey() =>
      TokenSubClass._(0x3, 'Set1stSectionDecoderKey');

  /// Class 2 sub-class 0x4 — install 2nd section of new decoder key
  /// (KCT stage 2).
  factory TokenSubClass.set2ndSectionDecoderKey() =>
      TokenSubClass._(0x4, 'Set2ndSectionDecoderKey');

  /// Class 2 sub-class 0x5 — clear tamper condition.
  factory TokenSubClass.clearTamperCondition() =>
      TokenSubClass._(0x5, 'ClearTamperCondition');

  /// Class 2 sub-class 0x6 — set Maximum Phase-Power Unbalance Limit.
  factory TokenSubClass.setMaximumPhasePowerUnbalanceLimit() =>
      TokenSubClass._(0x6, 'SetMaximumPhasePowerUnbalanceLimit');

  /// Class 2 sub-class 0x8 — install 3rd section of new decoder key
  /// (MISTY1 KCT stage 3).
  factory TokenSubClass.set3rdSectionDecoderKey() =>
      TokenSubClass._(0x8, 'Set3rdSectionDecoderKey');

  /// Class 2 sub-class 0x9 — install 4th section of new decoder key
  /// (MISTY1 KCT stage 4).
  factory TokenSubClass.set4thSectionDecoderKey() =>
      TokenSubClass._(0x9, 'Set4thSectionDecoderKey');

  /// Returns the packed value as a binary string.
  @override
  String toString() => bitString.toString();
}
