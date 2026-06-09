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
class Amount {
  static const int noOfBits = 16;
  static const int unitsPurchasedMin = 0;
  static const int unitsPurchasedMax = 18201624;

  final double unitsPurchased;
  late final BitString bitString;

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

  String get name => 'Amount';
}
