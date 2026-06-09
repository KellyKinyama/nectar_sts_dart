/// Luhn (mod-10) check-digit generator. Direct port of
/// `generators/utils/LuhnAlgorithm.java`.
class LuhnAlgorithm {
  LuhnAlgorithm._();

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
