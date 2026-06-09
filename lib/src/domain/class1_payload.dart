import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// Variable-width manufacturer code embedded in Class 1 tokens.
///
/// SubClass 0 (InitiateMeterTestOrDisplay1) uses 8 bits.
/// SubClass 1 (InitiateMeterTestOrDisplay2) uses 16 bits.
class ManufacturerCode {
  final BitString bitString;

  ManufacturerCode(this.bitString) {
    if (bitString.length != 8 && bitString.length != 16) {
      throw const InvalidManufacturerCodeException(
        'ManufacturerCode must be 8 or 16 bits wide',
      );
    }
  }

  factory ManufacturerCode.fromInt(int value, {required int widthBits}) {
    if (widthBits != 8 && widthBits != 16) {
      throw const InvalidManufacturerCodeException(
        'ManufacturerCode width must be 8 or 16',
      );
    }
    if (value < 0 || value >= (1 << widthBits)) {
      throw InvalidManufacturerCodeException(
        'ManufacturerCode $value out of range for $widthBits bits',
      );
    }
    return ManufacturerCode(BitString.fromValue(value, widthBits));
  }

  int get value => bitString.value;
}

/// Variable-width "control" payload inside Class 1 tokens.
///
/// SubClass 0 = 36 bits; SubClass 1 = 28 bits. We don't decode the
/// inner semantics here — the value is just a vendor-defined APDU.
class Control {
  final BitString bitString;
  final ManufacturerCode manufacturerCode;

  Control(this.bitString, this.manufacturerCode) {
    if (bitString.length != 28 && bitString.length != 36) {
      throw const InvalidControlBitStringException(
        'Control must be 28 or 36 bits wide',
      );
    }
  }

  int get value => bitString.value;
}
