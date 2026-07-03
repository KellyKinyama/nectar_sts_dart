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
  /// Width of the TID bit-field on the wire (`24`).
  static const int noOfBits = 24;

  BitString _tidBits = BitString.fromValue(0, noOfBits);
  DateTime _timeOfIssue;
  late DateTime _refDateTime;

  /// Builds a TID for the current instant (or [timeOfIssue] if
  /// supplied), anchored to [baseDate].
  ///
  /// The [timeOfIssue] is normalised to UTC. The 24-bit TID is
  /// computed as `timeOfIssue - baseDate` in whole minutes (with the
  /// STS `+1` quirk for `00:01` UTC).
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

  /// The 24-bit TID as a [BitString].
  BitString get bitString => _tidBits;

  /// UTC issue time this TID was generated from.
  DateTime get timeOfIssue => _timeOfIssue;

  /// UTC [BaseDate] anchor this TID is measured from.
  DateTime get refBaseTime => _refDateTime;

  /// Updates the issue time and re-derives the packed TID bits.
  ///
  /// [t] is normalised to UTC before storage.
  set timeOfIssue(DateTime t) {
    _timeOfIssue = t.toUtc();
    _generateTid();
  }

  /// Switches the anchor to a different [baseDate] and re-derives the
  /// packed TID bits (issue time is unchanged).
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

  /// Returns `timeOfIssue - refBaseTime` in whole minutes.
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

  /// Returns the TID as a zero-padded 24-bit binary string.
  String bitsToString() => _tidBits.toPaddedBinary();

  /// Returns the TID as an unpadded base-2 string (for logging).
  @override
  String toString() => _tidBits.toString();
}
