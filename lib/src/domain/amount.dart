import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import '../util/utils.dart';

/// 16-bit electricity / water / gas amount field.
///
/// Storage convention (matches IEC 62055-41 + Nectar):
///   - `unitsPurchased`  : the human-readable value (e.g. `5.5` kWh).
///   - `bitString`       : the 16-bit packed form = 2-bit exponent (top)
///                          + 14-bit mantissa (low). Always encodes
///                          `unitsPurchased * 10` (tenths of a unit).
///
/// Range is 0 .. 18 201 624 units, per the STS specification.
///
/// Example:
/// ```dart
/// final a = Amount(25.5);   // 25.5 kWh
/// a.bitString.length;       // 16
///
/// // Round-trip via the wire encoding.
/// final back = Amount.fromBitString(a.bitString);
/// back.unitsPurchased;      // 25.5
/// ```
class Amount {
  /// Width of the packed amount bit-field on the wire (`16`).
  static const int noOfBits = 16;

  /// Minimum accepted units-purchased value (inclusive).
  static const int unitsPurchasedMin = 0;

  /// Maximum accepted units-purchased value (inclusive), per
  /// IEC 62055-41.
  static const int unitsPurchasedMax = 18201624;

  /// The human-readable units value (e.g. `5.5` kWh).
  final double unitsPurchased;

  /// The 16-bit packed encoding of [unitsPurchased] (exponent +
  /// mantissa).
  late final BitString bitString;

  /// Builds an [Amount] from a human-readable [unitsPurchased] value.
  ///
  /// Encoding is `unitsPurchased * 10` (tenths of a unit) via
  /// [Utils.convertToBitString]. Values below 1 round up to at least
  /// 1 tenth so a tiny top-up still encodes non-zero. Throws
  /// [InvalidUnitsPurchasedException] when outside
  /// `[unitsPurchasedMin, unitsPurchasedMax]`.
  Amount(this.unitsPurchased) {
    if (unitsPurchased < unitsPurchasedMin ||
        unitsPurchased > unitsPurchasedMax) {
      throw InvalidUnitsPurchasedException(
        'Invalid number of units purchased: $unitsPurchased',
      );
    }
    // Encode "tenths of a unit". For values <1, Java uses Math.ceil to
    // round up so a 0.05 kWh top-up still encodes as 1 tenth.
    final tenths = unitsPurchased < 1
        ? (unitsPurchased * 10).ceil().toDouble()
        : (unitsPurchased * 10).truncateToDouble();
    final bs = Utils.convertToBitString(tenths);
    bs.length = noOfBits;
    bitString = bs;
  }

  /// Reverse construct from a 16-bit `BitString` (decoder side).
  Amount.fromBitString(BitString bs)
      : assert(bs.length == noOfBits),
        unitsPurchased = Utils.convertToDouble(bs),
        bitString = bs;

  /// Human-readable field name (`"Amount"`).
  String get name => 'Amount';
}
