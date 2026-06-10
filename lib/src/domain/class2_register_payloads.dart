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

/// 16-bit "credit register" snapshot carried by `ClearCredit_21`.
/// Real meters apply this as: "clear all customer credit and write
/// this register value into the post-clear balance counter".
class Register {
  final BitString bitString;

  Register(this.bitString) {
    if (bitString.length != 16) {
      throw const InvalidRegisterBitStringException(
        'Register must be exactly 16 bits',
      );
    }
  }

  int get value => bitString.value;
  String get name => 'Register';

  @override
  String toString() => '$value';
}

/// 16-bit "pad" payload carried by `ClearTamperCondition_25`. Acts as
/// random padding so two ClearTamperCondition tokens issued in the
/// same minute don't share the same encrypted block.
class Pad {
  final BitString bitString;

  Pad(this.bitString) {
    if (bitString.length != 16) {
      throw const InvalidPadException('Pad must be exactly 16 bits');
    }
  }

  int get value => bitString.value;
  String get name => 'Pad';

  @override
  String toString() => '$value';
}

/// 16-bit tariff-rate value carried by `SetTariffRate_22`. The
/// upstream Java has a `rate` package with a richer `Rate` type; the
/// algorithmic mirror only needs the 16-bit payload.
class Rate {
  final BitString bitString;

  Rate(this.bitString) {
    if (bitString.length != 16) {
      throw const InvalidRateException('Rate must be exactly 16 bits');
    }
  }

  factory Rate.fromValue(int value) {
    if (value < 0 || value > 0xFFFF) {
      throw InvalidRateException(
        'Rate value must fit in 16 bits (0..65535), got $value',
      );
    }
    return Rate(BitString.fromValue(value, 16));
  }

  int get value => bitString.value;
  String get name => 'Rate';

  @override
  String toString() => '$value';
}

/// 16-bit Maximum Power Limit carried by `SetMaximumPowerLimit_20`.
/// Interpreted by the meter as a power cap in watts (or whatever
/// units the utility's metering profile defines — STS Edition 1
/// does not nail this down beyond "16 unsigned bits").
class MaximumPowerLimit {
  final BitString bitString;

  MaximumPowerLimit._(this.bitString);

  factory MaximumPowerLimit(int value) {
    if (value < 0 || value > 0xFFFF) {
      throw InvalidMplException(
        'Maximum Power Limit must fit in 16 bits (0..65535), got $value',
      );
    }
    return MaximumPowerLimit._(BitString.fromValue(value, 16));
  }

  factory MaximumPowerLimit.fromBitString(BitString bs) {
    if (bs.length != 16) {
      throw const InvalidMplException(
        'Maximum Power Limit must be exactly 16 bits',
      );
    }
    return MaximumPowerLimit._(bs);
  }

  int get value => bitString.value;
  String get name => 'Maximum Power Limit';

  @override
  String toString() => '$value';
}

/// 16-bit Maximum Phase Power Unbalance Limit carried by
/// `SetMaximumPhasePowerUnbalanceLimit_26`. Interpreted by the meter
/// as an unbalance threshold (commonly a percentage).
class MaximumPhasePowerUnbalanceLimit {
  final BitString bitString;

  MaximumPhasePowerUnbalanceLimit._(this.bitString);

  factory MaximumPhasePowerUnbalanceLimit(int value) {
    if (value < 0 || value > 0xFFFF) {
      throw InvalidMppulException(
        'Maximum Phase Power Unbalance Limit must fit in 16 bits, got $value',
      );
    }
    return MaximumPhasePowerUnbalanceLimit._(BitString.fromValue(value, 16));
  }

  factory MaximumPhasePowerUnbalanceLimit.fromBitString(BitString bs) {
    if (bs.length != 16) {
      throw const InvalidMppulException(
        'Maximum Phase Power Unbalance Limit must be exactly 16 bits',
      );
    }
    return MaximumPhasePowerUnbalanceLimit._(bs);
  }

  int get value => bitString.value;
  String get name => 'Maximum Phase Power Unbalance Limit';

  @override
  String toString() => '$value';
}
