enum TimestampUnit { seconds, milliseconds }

class TimestampConversion {
  const TimestampConversion({
    required this.input,
    required this.unit,
    required this.dateTime,
  });

  final int input;
  final TimestampUnit unit;
  final DateTime dateTime;
}

class DateTimeTimestampConversion {
  const DateTimeTimestampConversion({
    required this.dateTime,
    required this.seconds,
    required this.milliseconds,
  });

  final DateTime dateTime;
  final int seconds;
  final int milliseconds;
}

class TimestampConverter {
  const TimestampConverter._();

  static const _millisecondThreshold = 100000000000;
  static const _maximumMilliseconds = 8640000000000000;
  static final _dateTimePattern = RegExp(
    r'^(\d{4,6})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?(Z|[+-]\d{2}:?\d{2})?$',
  );

  static TimestampConversion parseTimestamp(String input) {
    final normalized = input.trim();
    final value = int.tryParse(normalized);
    if (normalized.isEmpty || value == null) {
      throw const FormatException('请输入有效的整数时间戳');
    }

    final unit =
        value >= _millisecondThreshold || value <= -_millisecondThreshold
        ? TimestampUnit.milliseconds
        : TimestampUnit.seconds;
    final milliseconds = unit == TimestampUnit.seconds ? value * 1000 : value;
    if (milliseconds < -_maximumMilliseconds ||
        milliseconds > _maximumMilliseconds) {
      throw const FormatException('时间戳超出支持范围');
    }

    try {
      return TimestampConversion(
        input: value,
        unit: unit,
        dateTime: DateTime.fromMillisecondsSinceEpoch(milliseconds),
      );
    } on ArgumentError {
      throw const FormatException('时间戳超出支持范围');
    }
  }

  static DateTime parseDateTime(String input) {
    final normalized = input.trim();
    final match = _dateTimePattern.firstMatch(normalized);
    if (match == null) {
      throw const FormatException('请输入 yyyy-MM-dd HH:mm:ss 格式的时间');
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    final fraction = match.group(7) ?? '';
    final millisecond = fraction.isEmpty
        ? 0
        : int.parse(fraction.padRight(3, '0'));
    _validateComponents(
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      millisecond: millisecond,
    );

    final zone = match.group(8);
    if (zone == null) {
      try {
        return DateTime(year, month, day, hour, minute, second, millisecond);
      } on ArgumentError {
        throw const FormatException('日期时间超出支持范围');
      }
    }

    var offset = Duration.zero;
    if (zone != 'Z') {
      final digits = zone.substring(1).replaceAll(':', '');
      final offsetHours = int.parse(digits.substring(0, 2));
      final offsetMinutes = int.parse(digits.substring(2, 4));
      if (offsetHours > 23 || offsetMinutes > 59) {
        throw const FormatException('时区偏移无效');
      }
      offset = Duration(hours: offsetHours, minutes: offsetMinutes);
      if (zone.startsWith('-')) offset = -offset;
    }

    try {
      final utc = DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
      ).subtract(offset);
      return utc.toLocal();
    } on ArgumentError {
      throw const FormatException('日期时间超出支持范围');
    }
  }

  static DateTimeTimestampConversion convertDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final milliseconds = local.millisecondsSinceEpoch;
    final seconds = milliseconds >= 0
        ? milliseconds ~/ 1000
        : -((-milliseconds + 999) ~/ 1000);
    return DateTimeTimestampConversion(
      dateTime: local,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  static String formatDateTime(DateTime value) {
    final local = value.toLocal();
    final year = local.year >= 0
        ? local.year.toString().padLeft(4, '0')
        : '-${(-local.year).toString().padLeft(4, '0')}';
    return '$year-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}.'
        '${local.millisecond.toString().padLeft(3, '0')}';
  }

  static String unitLabel(TimestampUnit unit) {
    return unit == TimestampUnit.seconds ? '秒' : '毫秒';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static void _validateComponents({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int second,
    required int millisecond,
  }) {
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw const FormatException('日期时间无效');
    }
    late final DateTime checked;
    try {
      checked = DateTime.utc(
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
      );
    } on ArgumentError {
      throw const FormatException('日期时间超出支持范围');
    }
    if (checked.year != year ||
        checked.month != month ||
        checked.day != day ||
        checked.hour != hour ||
        checked.minute != minute ||
        checked.second != second ||
        checked.millisecond != millisecond) {
      throw const FormatException('日期时间无效');
    }
  }
}
