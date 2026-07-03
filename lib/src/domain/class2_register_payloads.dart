/// 16-bit register-payload primitives shared by the five
/// Class 2 management tokens that follow the
/// `crc(16) | register(16) | tid(24) | rnd(4) | sub(4)` layout:
///
///   - `Register`                       (ClearCredit_21)
///   - `Pad`                            (ClearTamperCondition_25)
///   - `Rate`                           (SetTariffRate_22)
///   - `MaximumPowerLimit`              (SetMaximumPowerLimit_20)
///   - `MaximumPhasePowerUnbalanceLimit`(SetMaximumPhasePowerUnbalanceLimit_26)
///
/// Each wraps a 16-bit `BitString`. The numeric variants
/// (`MaximumPowerLimit`, `MaximumPhasePowerUnbalanceLimit`) accept a
/// `long` and build the 16-bit form; the BitString variants accept the
/// payload bits directly (mirroring the Java upstream constructors).
library;

import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import '../util/utils.dart';

/// 16-bit "credit register" snapshot carried by `ClearCredit_21`.
/// Real meters apply this as: "clear all customer credit and write
/// this register value into the post-clear balance counter".
class Register {
  /// Packed 16-bit credit-register value.
  final BitString bitString;

  /// Wraps a pre-built 16-bit [bitString]; throws
  /// [InvalidRegisterBitStringException] for any other width.
  Register(this.bitString) {
    if (bitString.length != 16) {
      throw const InvalidRegisterBitStringException(
        'Register must be exactly 16 bits',
      );
    }
  }

  /// Integer register value in `0..65535`.
  int get value => bitString.value;

  /// Human-readable field name.
  String get name => 'Register';

  /// Returns [value] as a decimal string.
  @override
  String toString() => '$value';
}

/// 16-bit "pad" payload carried by `ClearTamperCondition_25`. Acts as
/// random padding so two ClearTamperCondition tokens issued in the
/// same minute don't share the same encrypted block.
class Pad {
  /// Packed 16-bit random padding value.
  final BitString bitString;

  /// Wraps a pre-built 16-bit [bitString]; throws
  /// [InvalidPadException] for any other width.
  Pad(this.bitString) {
    if (bitString.length != 16) {
      throw const InvalidPadException('Pad must be exactly 16 bits');
    }
  }

  /// Integer pad value in `0..65535`.
  int get value => bitString.value;

  /// Human-readable field name.
  String get name => 'Pad';

  /// Returns [value] as a decimal string.
  @override
  String toString() => '$value';
}

/// 16-bit tariff-rate value carried by `SetTariffRate_22`. The
/// upstream Java has a `rate` package with a richer `Rate` type; the
/// algorithmic mirror only needs the 16-bit payload.
class Rate {
  /// Packed 16-bit tariff-rate value.
  final BitString bitString;

  /// Wraps a pre-built 16-bit [bitString]; throws
  /// [InvalidRateException] for any other width.
  Rate(this.bitString) {
    if (bitString.length != 16) {
      throw const InvalidRateException('Rate must be exactly 16 bits');
    }
  }

  /// Builds a [Rate] from an integer [value] in `0..65535`.
  ///
  /// Throws [InvalidRateException] outside that range.
  factory Rate.fromValue(int value) {
    if (value < 0 || value > 0xFFFF) {
      throw InvalidRateException(
        'Rate value must fit in 16 bits (0..65535), got $value',
      );
    }
    return Rate(BitString.fromValue(value, 16));
  }

  /// Integer rate value in `0..65535`.
  int get value => bitString.value;

  /// Human-readable field name.
  String get name => 'Rate';

  /// Returns [value] as a decimal string.
  @override
  String toString() => '$value';
}

/// 16-bit Maximum Power Limit carried by `SetMaximumPowerLimit_20`.
/// Interpreted by the meter as a power cap in watts (or whatever
/// units the utility's metering profile defines — STS Edition 1
/// does not nail this down beyond "16 unsigned bits").
class MaximumPowerLimit {
  /// Inclusive upper bound matching STS-spec Amount range (the same
  /// 2-bit exponent + 14-bit mantissa packing applies).
  static const int maxValue = 18201624;

  /// Packed 16-bit MPL value.
  final BitString bitString;

  MaximumPowerLimit._(this.bitString);

  /// Builds an [MaximumPowerLimit] from an integer [value] in
  /// `0..maxValue`.
  ///
  /// The integer is packed into the 16-bit exponent-and-mantissa form
  /// via [Utils.convertToBitString]. Throws [InvalidMplException]
  /// outside range.
  factory MaximumPowerLimit(int value) {
    if (value < 0 || value > maxValue) {
      throw InvalidMplException(
        'Maximum Power Limit must be in 0..$maxValue, got $value',
      );
    }
    final bs = Utils.convertToBitString(value.toDouble());
    bs.length = 16;
    return MaximumPowerLimit._(bs);
  }

  /// Wraps a pre-built 16-bit [bs]; throws [InvalidMplException] for
  /// any other width.
  factory MaximumPowerLimit.fromBitString(BitString bs) {
    if (bs.length != 16) {
      throw const InvalidMplException(
        'Maximum Power Limit must be exactly 16 bits',
      );
    }
    return MaximumPowerLimit._(bs);
  }

  /// Raw integer form of the packed MPL bits.
  int get value => bitString.value;

  /// Human-readable field name.
  String get name => 'Maximum Power Limit';

  /// Returns [value] as a decimal string.
  @override
  String toString() => '$value';
}

/// 16-bit Maximum Phase Power Unbalance Limit carried by
/// `SetMaximumPhasePowerUnbalanceLimit_26`. Interpreted by the meter
/// as an unbalance threshold (commonly a percentage).
class MaximumPhasePowerUnbalanceLimit {
  /// Inclusive upper bound matching STS-spec Amount range.
  static const int maxValue = 18201624;

  /// Packed 16-bit MPPUL value.
  final BitString bitString;

  MaximumPhasePowerUnbalanceLimit._(this.bitString);

  /// Builds an [MaximumPhasePowerUnbalanceLimit] from an integer
  /// [value] in `0..maxValue`.
  ///
  /// The integer is packed into the 16-bit exponent-and-mantissa form
  /// via [Utils.convertToBitString]. Throws [InvalidMppulException]
  /// outside range.
  factory MaximumPhasePowerUnbalanceLimit(int value) {
    if (value < 0 || value > maxValue) {
      throw InvalidMppulException(
        'Maximum Phase Power Unbalance Limit must be in 0..$maxValue, got $value',
      );
    }
    final bs = Utils.convertToBitString(value.toDouble());
    bs.length = 16;
    return MaximumPhasePowerUnbalanceLimit._(bs);
  }

  /// Wraps a pre-built 16-bit [bs]; throws [InvalidMppulException] for
  /// any other width.
  factory MaximumPhasePowerUnbalanceLimit.fromBitString(BitString bs) {
    if (bs.length != 16) {
      throw const InvalidMppulException(
        'Maximum Phase Power Unbalance Limit must be exactly 16 bits',
      );
    }
    return MaximumPhasePowerUnbalanceLimit._(bs);
  }

  /// Raw integer form of the packed MPPUL bits.
  int get value => bitString.value;

  /// Human-readable field name.
  String get name => 'Maximum Phase Power Unbalance Limit';

  /// Returns [value] as a decimal string.
  @override
  String toString() => '$value';
}
