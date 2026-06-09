/// Single-bit '0' or '1' character holder. Mirrors `base/Bit.java`.
class Bit {
  int _val;

  Bit(int char) : _val = _validate(char);

  Bit.fromChar(String s) : _val = _validate(s.codeUnitAt(0));

  /// The character code (`0x30` for '0', `0x31` for '1').
  int get value => _val;

  /// 0 or 1 as a plain integer.
  int get intValue => _val == 0x31 ? 1 : 0;

  set value(int char) => _val = _validate(char);

  static int _validate(int char) {
    if (char != 0x30 && char != 0x31) {
      throw ArgumentError('Bit must be 0 or 1, got code $char');
    }
    return char;
  }

  @override
  String toString() => String.fromCharCode(_val);
}
