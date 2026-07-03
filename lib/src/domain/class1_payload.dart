import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// Variable-width manufacturer code embedded in Class 1 tokens.
///
/// SubClass 0 (InitiateMeterTestOrDisplay1) uses 8 bits.
/// SubClass 1 (InitiateMeterTestOrDisplay2) uses 16 bits.
class ManufacturerCode {
  /// Packed 8- or 16-bit manufacturer code.
  final BitString bitString;

  /// Wraps a pre-built [bitString] of width 8 or 16.
  ///
  /// Throws [InvalidManufacturerCodeException] for any other width.
  ManufacturerCode(this.bitString) {
    if (bitString.length != 8 && bitString.length != 16) {
      throw const InvalidManufacturerCodeException(
        'ManufacturerCode must be 8 or 16 bits wide',
      );
    }
  }

  /// Builds a [ManufacturerCode] from an integer [value].
  ///
  /// [widthBits] must be `8` or `16`; [value] must fit unsigned in
  /// that many bits. Throws [InvalidManufacturerCodeException]
  /// otherwise.
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

  /// Integer value of the packed manufacturer code.
  int get value => bitString.value;
}

/// Variable-width "control" payload inside Class 1 tokens.
///
/// SubClass 0 = 36 bits; SubClass 1 = 28 bits. We don't decode the
/// inner semantics here — the value is just a vendor-defined APDU.
class Control {
  /// Packed 28- or 36-bit vendor-defined control payload.
  final BitString bitString;

  /// Manufacturer code that scopes how [bitString] is interpreted.
  final ManufacturerCode manufacturerCode;

  /// Wraps a pre-built [bitString] of width 28 or 36 alongside its
  /// owning [manufacturerCode].
  ///
  /// Throws [InvalidControlBitStringException] for any other width.
  Control(this.bitString, this.manufacturerCode) {
    if (bitString.length != 28 && bitString.length != 36) {
      throw const InvalidControlBitStringException(
        'Control must be 28 or 36 bits wide',
      );
    }
  }

  /// Integer value of the packed control payload.
  int get value => bitString.value;
}
