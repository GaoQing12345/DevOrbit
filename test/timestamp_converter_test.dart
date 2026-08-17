import 'package:dev_orbit/features/timestamp/timestamp_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auto-detects second and millisecond timestamps', () {
    final seconds = TimestampConverter.parseTimestamp('1710000000');
    final milliseconds = TimestampConverter.parseTimestamp('1710000000000');

    expect(seconds.unit, TimestampUnit.seconds);
    expect(seconds.dateTime.millisecondsSinceEpoch, 1710000000000);
    expect(milliseconds.unit, TimestampUnit.milliseconds);
    expect(milliseconds.dateTime.millisecondsSinceEpoch, 1710000000000);
  });

  test('supports negative timestamps and rejects invalid input', () {
    final conversion = TimestampConverter.parseTimestamp('-1');

    expect(conversion.unit, TimestampUnit.seconds);
    expect(conversion.dateTime.millisecondsSinceEpoch, -1000);
    expect(
      () => TimestampConverter.parseTimestamp('12.4'),
      throwsFormatException,
    );
    expect(
      () => TimestampConverter.parseTimestamp('999999999999999999'),
      throwsFormatException,
    );
  });

  test('parses strict local date-time values with milliseconds', () {
    final parsed = TimestampConverter.parseDateTime('2026-08-17 14:30:45.123');

    expect(parsed.year, 2026);
    expect(parsed.month, 8);
    expect(parsed.day, 17);
    expect(parsed.hour, 14);
    expect(parsed.minute, 30);
    expect(parsed.second, 45);
    expect(parsed.millisecond, 123);
    expect(
      TimestampConverter.formatDateTime(parsed),
      '2026-08-17 14:30:45.123',
    );
  });

  test('normalizes ISO offsets to the system local time zone', () {
    final parsed = TimestampConverter.parseDateTime(
      '2026-08-17T14:30:45.123+08:00',
    );
    final expected = DateTime.utc(
      2026,
      8,
      17,
      14,
      30,
      45,
      123,
    ).subtract(const Duration(hours: 8)).toLocal();

    expect(parsed, expected);
  });

  test('rejects normalized but invalid calendar dates', () {
    expect(
      () => TimestampConverter.parseDateTime('2026-02-30 10:00:00'),
      throwsFormatException,
    );
    expect(
      () => TimestampConverter.parseDateTime('2026-08-17'),
      throwsFormatException,
    );
    expect(
      () => TimestampConverter.parseDateTime('999999-08-17 10:00:00'),
      throwsFormatException,
    );
  });

  test('uses floor semantics for negative second timestamps', () {
    final conversion = TimestampConverter.convertDateTime(
      DateTime.fromMillisecondsSinceEpoch(-1),
    );

    expect(conversion.seconds, -1);
    expect(conversion.milliseconds, -1);
  });
}
