import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// Miscellaneous helpers ported from `generators/utils/Utils.java`.
class Utils {
  Utils._();

  /// Encode a kWh / kVA / litres / m³ amount into the 16-bit
  /// 2-bit-exponent + 14-bit-mantissa form required for the
  /// Units-Purchased field. Mirrors `Utils.convertToBitString(double)`.
  ///
  /// The Java original deliberately uses double arithmetic and
  /// `Math.ceil` to match the rounding model from IEC 62055-41 v2.0 p.41
  /// "Maximum error due to rounding".
  static BitString convertToBitString(double unitsPurchased) {
    var mantissa = unitsPurchased;
    var exponent = 0;
    for (exponent = 0; exponent <= 3; exponent++) {
      if (mantissa < _pow2_14) break;
      mantissa -= _pow2_14;
      mantissa /= 10;
    }
    final v = (exponent << 14) + mantissa.ceil();
    return BitString.fromValue(v);
  }

  /// Decode a 16-bit amount field back to a double, in the same units
  /// the encoder expected. Mirrors `Utils.convertToDouble`.
  static double convertToDouble(BitString amount) {
    const noOfBits = 16;
    if (amount.length != noOfBits) {
      throw const InvalidUnitsPurchasedBitsException(
        'Amount bitstring must be 16 bits',
      );
    }
    final raw = amount.value;
    final mantissa = raw & 0x3FFF;
    final exponent = raw >>> 14;
    if (exponent > 3) {
      throw RangeError('exponent value too large');
    }
    var units = mantissa * _pow10[exponent];
    for (var i = 1; i <= exponent; i++) {
      units += _pow2_14 * _pow10[i - 1];
    }
    return units / 10.0;
  }

  /// Convert a long to 7 big-endian bytes (Java
  /// `Utils.longToBytes` is intentionally 7 bytes wide, not 8).
  /// Used as the CRC input width.
  static List<int> longToBytes7(int v) {
    final out = List<int>.filled(7, 0);
    for (var i = 6; i >= 0; i--) {
      out[i] = v & 0xFF;
      v >>= 8;
    }
    return out;
  }

  /// Convert an 8-byte big-endian array to a long. Mirrors
  /// `Utils.bytesToLong`.
  static int bytesToLong(List<int> b) {
    var result = 0;
    for (var i = 0; i < 8; i++) {
      result <<= 8;
      result |= (b[i] & 0xFF);
    }
    return result;
  }

  /// Decimal digit count of a non-negative long.
  static int getNoOfDigits(int v) {
    var n = 0;
    while (v > 0) {
      v ~/= 10;
      n++;
    }
    return n;
  }

  /// Concatenate two byte arrays.
  static List<int> combine(List<int> a, List<int> b) => [...a, ...b];

  static const double _pow2_14 = 16384.0; // 2^14
  static const List<double> _pow10 = [1.0, 10.0, 100.0, 1000.0];
}
