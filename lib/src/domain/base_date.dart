/// One of the three IEC 62055-41 base dates from which a TID is
/// counted in minutes.
///
/// Mirrors `domain/BaseDate.java` but without Joda-Time.
enum BaseDate {
  date1993('93', 1993),
  date2014('14', 2014),
  date2035('35', 2035);

  final String shortCode;
  final int year;
  const BaseDate(this.shortCode, this.year);

  DateTime get dateTime => DateTime.utc(year, 1, 1);
}
