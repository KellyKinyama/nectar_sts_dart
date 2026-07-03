/// One of the three IEC 62055-41 base dates from which a TID is
/// counted in minutes.
///
/// Mirrors `domain/BaseDate.java` but without Joda-Time.
///
/// Example:
/// ```dart
/// BaseDate.date1993.shortCode;      // '93'
/// BaseDate.date1993.year;           // 1993
/// BaseDate.date1993.dateTime;       // 1993-01-01 00:00:00.000Z
/// ```
enum BaseDate {
  date1993('93', 1993),
  date2014('14', 2014),
  date2035('35', 2035);

  /// Two-digit STS short code (e.g. `'93'`, `'14'`, `'35'`) used inside
  /// key-parameter fields.
  final String shortCode;

  /// Calendar year of `1 January 00:00 UTC` for this base date.
  final int year;

  /// Named constant constructor for the fixed STS base-date set.
  const BaseDate(this.shortCode, this.year);

  /// The base date itself as a UTC [DateTime] (`year-01-01 00:00Z`).
  ///
  /// Used as the anchor from which a [TokenIdentifier]'s
  /// minutes-since-base counter is measured.
  DateTime get dateTime => DateTime.utc(year, 1, 1);
}
