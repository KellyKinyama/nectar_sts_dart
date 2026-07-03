/// Luhn (mod-10) check-digit generator. Direct port of
/// `generators/utils/LuhnAlgorithm.java`.
class LuhnAlgorithm {
  LuhnAlgorithm._();

  /// Returns the Luhn (mod-10) check digit for [value].
  ///
  /// The returned digit is in `0..9` and, when appended to the
  /// right-hand end of [value], produces a number whose Luhn sum is
  /// `0 mod 10`. Used across STS PAN, IIN and decoder-serial fields to
  /// derive the trailing check digit.
  static int generateCheckDigit(int value) {
    var sum = 0;
    const modulus = 10;
    var alternate = true;
    while (value > 0) {
      var digit = value % modulus;
      value ~/= modulus;
      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit = (digit % modulus) + 1;
        }
      }
      sum += digit;
      alternate = !alternate;
    }
    final upper = ((sum / modulus).ceil()) * modulus;
    return upper - sum;
  }
}
