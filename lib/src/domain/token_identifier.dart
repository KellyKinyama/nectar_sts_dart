import '../base/bit_string.dart';
import '../exceptions/exceptions.dart';
import 'base_date.dart';

/// 24-bit Token Identifier: the number of minutes elapsed between a
/// chosen [BaseDate] and the issue time of the token.
///
/// Mirrors `domain/TokenIdentifier.java` but uses `DateTime` rather
/// than Joda-Time. The "minute-of-day == 1 → add 1 minute" quirk from
/// the Java original is preserved bit-for-bit.
class TokenIdentifier {
  static const int noOfBits = 24;

  BitString _tidBits = BitString.fromValue(0, noOfBits);
  DateTime _timeOfIssue;
  late DateTime _refDateTime;

  TokenIdentifier(BaseDate baseDate, {DateTime? timeOfIssue})
    : _timeOfIssue = timeOfIssue?.toUtc() ?? DateTime.now().toUtc() {
    _refDateTime = baseDate.dateTime;
    _generateTid();
  }

  /// Reconstruct a TID from its 24-bit packed form (decoder side).
  /// The `_timeOfIssue` field is derived from the encoded minutes via
  /// the supplied [baseDate].
  factory TokenIdentifier.fromBitString(
    BitString bs, {
    BaseDate baseDate = BaseDate.date1993,
  }) {
    if (bs.length != noOfBits) {
      throw const InvalidDateTimeBitsException('TID must be 24 bits');
    }
    final minutes = bs.value;
    final issuedAt = baseDate.dateTime.add(Duration(minutes: minutes));
    final tid = TokenIdentifier(baseDate, timeOfIssue: issuedAt);
    return tid;
  }

  BitString get bitString => _tidBits;
  DateTime get timeOfIssue => _timeOfIssue;
  DateTime get refBaseTime => _refDateTime;

  set timeOfIssue(DateTime t) {
    _timeOfIssue = t.toUtc();
    _generateTid();
  }

  void setBaseDate(BaseDate baseDate) {
    _refDateTime = baseDate.dateTime;
    _generateTid();
  }

  void _generateTid() {
    var diff = getDifferenceFromBaseTimeInMinutes();
    if (_timeOfIssue.minute == 1 && _timeOfIssue.hour == 0) {
      diff += 1; // mirrors Java's `getMinuteOfDay() == 1` quirk
    }
    _tidBits = BitString.fromValue(diff, noOfBits);
  }

  int getDifferenceFromBaseTimeInMinutes() {
    final diff = _timeOfIssue.difference(_refDateTime);
    return diff.inMinutes;
  }

  /// Recover the issue time encoded in a 24-bit TID bitstring.
  DateTime getDateTimeOfIssue(BitString tidBits) {
    if (tidBits.length != noOfBits) {
      throw const InvalidDateTimeBitsException('TID must be 24 bits');
    }
    final minutes = tidBits.value.toInt();
    return _refDateTime.add(Duration(minutes: minutes));
  }

  String bitsToString() => _tidBits.toPaddedBinary();

  @override
  String toString() => _tidBits.toString();
}
