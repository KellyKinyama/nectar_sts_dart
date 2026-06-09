import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';

/// 2-bit token class, prepended to the encrypted 64-bit block during
/// transposition. IEC 62055-41 defines four classes:
///   - 0  Credit transfer (electricity/water/gas/...)
///   - 1  Initiate meter test / display
///   - 2  Engineering / set-parameter
///   - 3  Reserved
class TokenClass {
  static const int noOfBits = 2;
  final BitString bitString;
  final String name;

  TokenClass._(int value, this.name)
    : assert(value >= 0 && value <= 3),
      bitString = BitString.fromValue(value, noOfBits);

  factory TokenClass(int value, String name) {
    if (value < 0 || value > 3) {
      throw InvalidTokenClassException('Token class must be 0..3, got $value');
    }
    return TokenClass._(value, name);
  }

  /// Class 0 — credit transfer (the common "top-up" tokens).
  factory TokenClass.electricityCreditTransfer() =>
      TokenClass._(0, 'Electricity Credit Transfer');
  factory TokenClass.waterCreditTransfer() =>
      TokenClass._(0, 'Water Credit Transfer');
  factory TokenClass.gasCreditTransfer() =>
      TokenClass._(0, 'Gas Credit Transfer');
  factory TokenClass.currencyCreditTransfer() =>
      TokenClass._(0, 'Currency Credit Transfer');

  /// Class 1 — initiate meter test or display.
  factory TokenClass.initiateMeterTestDisplay() =>
      TokenClass._(1, 'Initiate Meter Test/Display');

  /// Class 2 — engineering / set-parameter tokens.
  factory TokenClass.engineering(String name) => TokenClass._(2, name);

  @override
  String toString() => bitString.toString();
}
