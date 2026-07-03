/// Single-bit '0' or '1' character holder. Mirrors `base/Bit.java`.
///
/// A [Bit] stores its state as an ASCII character code — either `0x30`
/// (`'0'`) or `0x31` (`'1'`) — so it can be dropped straight into the
/// `List<int>` bit buffers used by [BitString] without conversion.
///
/// Typical usage:
///
/// ```dart
/// final b = Bit.fromChar('1');
/// print(b.intValue); // 1
/// print(b);          // '1'
/// ```
class Bit {
  int _val;

  /// Creates a [Bit] from an ASCII character code.
  ///
  /// [char] must be `0x30` (`'0'`) or `0x31` (`'1'`); any other value
  /// throws [ArgumentError].
  Bit(int char) : _val = _validate(char);

  /// Creates a [Bit] from a single-character string.
  ///
  /// The first character of [s] must be `'0'` or `'1'`.
  Bit.fromChar(String s) : _val = _validate(s.codeUnitAt(0));

  /// The character code (`0x30` for '0', `0x31` for '1').
  int get value => _val;

  /// 0 or 1 as a plain integer.
  int get intValue => _val == 0x31 ? 1 : 0;

  /// Replaces the stored bit.
  ///
  /// [char] must be `0x30` (`'0'`) or `0x31` (`'1'`); other values
  /// throw [ArgumentError].
  set value(int char) => _val = _validate(char);

  static int _validate(int char) {
    if (char != 0x30 && char != 0x31) {
      throw ArgumentError('Bit must be 0 or 1, got code $char');
    }
    return char;
  }

  /// Returns `'0'` or `'1'` — the single character this [Bit] represents.
  @override
  String toString() => String.fromCharCode(_val);
}
