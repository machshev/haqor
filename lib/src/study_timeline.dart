import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'study_workspace.dart' show StudyPassage;

/// How a timeline counts time.
enum TimelineScale {
  /// Calendar years, BC (stored negative) and AD, with no year zero.
  calendar,

  /// Years counted from a start of the study's own, such as a reign.
  years,

  /// Plain numbers in a unit the study names: days, weeks, generations.
  units,

  /// One year's calendar, the same every year, such as the feasts: times
  /// are a month and day, without a year (stored as year 0).
  annual,
}

/// The part of a day an event falls in. A day runs from sunset to sunset
/// (Genesis 1:5, Leviticus 23:32): its night comes first, then its
/// daytime, and its evening, "between the evenings" when the Passover was
/// killed (Exodus 12:6), closes it.
enum TimelineDayPart {
  night('at night', 'Night', 0.25),
  daytime('by day', 'Day', 0.7),
  evening('at evening', 'Evening', 0.94);

  const TimelineDayPart(this.phrase, this.label, this.fraction);

  /// How it reads after a date: "14 Nisan, at evening".
  final String phrase;
  final String label;

  /// Where in its day it stands, from the sunset that begins it.
  final double fraction;
}

/// What a span's length is counted in.
enum TimelineDurationUnit { years, months, days, units }

/// Which years of a year-counting timeline have a second Adar, the month
/// added to keep the lunar year in step with the seasons.
enum TimelineLeapMonths {
  /// None: every year has twelve months.
  none,

  /// The years the timeline lists ([StudyTimeline.leapYears]).
  chosen,

  /// The years the fixed Hebrew 19-year cycle gives: the 3rd, 6th, 8th,
  /// 11th, 14th, 17th and 19th of each cycle, counted in years of the world
  /// (anno mundi). Only calendar years can be placed in it.
  cycle,
}

/// How a timeline names its months; all count from Nisan (Abib), the first.
enum TimelineMonthNaming {
  /// The names used after the exile: Nisan, Iyyar, … Adar
  /// ([hebrewMonthNames]).
  postExile,

  /// The four names given before the exile, Abib, Ziv, Ethanim and Bul
  /// ([preExileMonthNames]); the other months by number.
  preExile,

  /// Every month by number, as Scripture most often gives them.
  numbered,
}

/// The months named before the exile: Abib, the first (Exodus 13:4); Ziv,
/// the second (1 Kings 6:1); Ethanim, the seventh (1 Kings 8:2); and Bul,
/// the eighth (1 Kings 6:38).
const preExileMonthNames = {1: 'Abib', 2: 'Ziv', 7: 'Ethanim', 8: 'Bul'};

/// [n] as an ordinal: 1st, 2nd, 3rd, 4th, … 11th, 12th, 13th, … 21st.
String ordinal(int n) {
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

/// A day of the week as a name in a sentence: "1st day of the week", or
/// "Sabbath" for the 7th.
String timelineWeekdayLabel(int weekday) =>
    weekday == 7 ? 'Sabbath' : '${ordinal(weekday)} day of the week';

/// The months of the Bible's year, from Nisan (Abib), its first month. They
/// are lunar: 30 and 29 days by turns, Nisan's 30, a year of 354 days. In a
/// leap year Adar becomes Adar I, of 30 days, and Adar II follows as a
/// thirteenth month of 29: a year of 384 days.
const hebrewMonthNames = [
  'Nisan',
  'Iyyar',
  'Sivan',
  'Tammuz',
  'Av',
  'Elul',
  'Tishri',
  'Marcheshvan',
  'Kislev',
  'Tevet',
  'Shevat',
  'Adar',
];

/// The most months and days a year-counting time may give, whatever its
/// year: a leap year's thirteen months, and a month's thirty days.
const _mostMonths = 13;
const _mostDays = 30;

/// The days of a twelve-month year before [month] begins: 29 for each month
/// before it, and one more for each of those (Nisan, Sivan, …) of 30. The
/// same holds for every month up to Adar I in a leap year, and Adar II
/// follows Adar I's 30.
int _daysBefore(int month) =>
    (month - 1) * 29 + month ~/ 2 + (month == 13 ? 1 : 0);

/// Whether the Hebrew year [am] (anno mundi) has a second Adar in the fixed
/// 19-year cycle.
bool hebrewCycleLeapYear(int am) => (7 * am + 1) % 19 < 7;

/// A Nisan-to-Adar year counted with a year zero (1 BC is 0) runs into the
/// spring of the next, when its Adars fall, in this year of the world.
const _anno = 3761;

/// A number on a timeline's scale as written: whole numbers without a
/// decimal point, others with at most two places.
String formatTimelineNumber(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

Object _jsonNumber(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? value.round()
    : value;

/// A point on a timeline: a year (or a count of the timeline's unit), with,
/// on a year-counting timeline, the month and day within that year when
/// they are known. Months and days are 1-based.
@immutable
class TimelineTime {
  const TimelineTime(this.value, {this.month, this.day});

  final double value;
  final int? month;
  final int? day;

  /// The finest part given: [TimelineDurationUnit.days],
  /// [TimelineDurationUnit.months] or else [TimelineDurationUnit.years].
  TimelineDurationUnit get precision => day != null
      ? TimelineDurationUnit.days
      : month != null
      ? TimelineDurationUnit.months
      : TimelineDurationUnit.years;

  /// Whether it is well formed in any year; whether its year has the month
  /// and its month the day is for its timeline to say
  /// ([StudyTimeline.fits]).
  bool get isValid =>
      value.isFinite &&
      (month == null ||
          (month! >= 1 &&
              month! <= _mostMonths &&
              value == value.roundToDouble())) &&
      (day == null || (month != null && day! >= 1 && day! <= _mostDays));

  /// Where it falls on a continuous axis, for ordering: the year, then the
  /// month and day as fractions of it, allowing for a thirteenth month. On
  /// a [calendar] axis a BC year moves up one, so 1 BC runs straight on
  /// into AD 1. [StudyTimeline.positionOf] places it more exactly.
  double position({bool calendar = false}) =>
      (calendar && value < 0 ? value + 1 : value) +
      (month == null ? 0 : (month! - 1) / _mostMonths) +
      (day == null ? 0 : (day! - 1) / (_mostMonths * _mostDays));

  @override
  bool operator ==(Object other) =>
      other is TimelineTime &&
      other.value == value &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(value, month, day);

  @override
  String toString() => 'TimelineTime($value, $month, $day)';
}

/// How long a span lasts, as it was entered.
@immutable
class TimelineDuration {
  const TimelineDuration(this.amount, this.unit);

  final double amount;
  final TimelineDurationUnit unit;

  bool get isValid =>
      amount.isFinite &&
      amount >= 0 &&
      (unit == TimelineDurationUnit.units || amount == amount.roundToDouble());

  Map<String, Object?> toJson() => {
    'amount': _jsonNumber(amount),
    'unit': unit.name,
  };

  static TimelineDuration? fromJson(Object? value) {
    if (value is! Map) return null;
    final amount = value['amount'];
    final unit = TimelineDurationUnit.values
        .where((u) => u.name == value['unit'])
        .firstOrNull;
    if (amount is! num || unit == null) return null;
    final duration = TimelineDuration(amount.toDouble(), unit);
    return duration.isValid ? duration : null;
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineDuration && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);
}

/// A custom timeline: an outline container, like a passage summary, whose
/// events and spans are placed on a [scale] of its own, counted in [unit]s
/// unless it counts calendar years. Any other item may sit in it too.
@immutable
class StudyTimeline {
  const StudyTimeline({
    required this.id,
    required this.title,
    this.scale = TimelineScale.units,
    this.unit = 'Year',
    this.leapMonths = TimelineLeapMonths.none,
    this.leapYears = const {},
    this.monthNaming = TimelineMonthNaming.postExile,
    this.nisanWeekday = 1,
    this.weekYear,
    this.showSeasons = false,
    this.categoryColors = const {},
    this.note = '',
    this.parentId,
    this.order = 0,
    this.extra = const {},
  });

  /// Keys this version does not know, kept so that saving does not erase
  /// fields a newer version wrote.
  final Map<String, Object?> extra;

  final String id;
  final String title;
  final TimelineScale scale;

  /// What the scale counts, unless it counts calendar years.
  final String unit;

  /// Which of its years have a second Adar; for [TimelineLeapMonths.chosen],
  /// [leapYears] lists them as written (BC negative).
  final TimelineLeapMonths leapMonths;
  final Set<int> leapYears;

  /// How its months are named.
  final TimelineMonthNaming monthNaming;

  /// The day of the week 1 Nisan falls on, 1 to 6 or 7 for the Sabbath: in
  /// [weekYear], from which the weeks run on through the years; or, without
  /// one (and always on one year's calendar), in every year.
  final int nisanWeekday;
  final double? weekYear;

  /// Whether its views show the seasons of the land and the moon's phases
  /// (see [timelineSeasons]).
  final bool showSeasons;

  /// The colour each category of its entries is shown in, as an index
  /// into the palette of category colours; given one as an entry first
  /// takes it (see [withCategory]).
  final Map<String, int> categoryColors;

  /// The colour [entry] is shown in, as an index into the palette of
  /// category colours; null for one without a category.
  int? colorOf(StudyTimelineEntry entry) =>
      entry.category.isEmpty ? null : categoryColors[entry.category];

  /// This timeline with a colour for [category]: the one it has, or the
  /// first of [palette] colours no other category has yet, else the next
  /// round.
  StudyTimeline withCategory(String category, {int palette = 8}) {
    if (category.isEmpty || categoryColors.containsKey(category)) return this;
    final used = categoryColors.values.toSet();
    final free = [
      for (var i = 0; i < palette; i++)
        if (!used.contains(i)) i,
    ];
    return copyWith(
      categoryColors: {
        ...categoryColors,
        category: free.firstOrNull ?? categoryColors.length % palette,
      },
    );
  }
  final String note;
  final String? parentId;
  final int order;

  bool get isValid => id.isNotEmpty && title.isNotEmpty;
  bool get isCalendar => scale == TimelineScale.calendar;

  bool get isAnnual => scale == TimelineScale.annual;

  /// Whether it counts years, calendar ones or its own.
  bool get countsYears =>
      scale == TimelineScale.calendar || scale == TimelineScale.years;

  /// Whether its times may name a month and day: counting years, or one
  /// year's calendar, where they must name the month.
  bool get hasMonths => countsYears || isAnnual;

  /// The units a span starting at [start] may give its length in: years
  /// where it counts them, then months and days as far as the start names
  /// them; or the timeline's own unit.
  List<TimelineDurationUnit> durationUnitsFor(TimelineTime start) => hasMonths
      ? [
          if (countsYears) TimelineDurationUnit.years,
          if (start.month != null) TimelineDurationUnit.months,
          if (start.day != null) TimelineDurationUnit.days,
        ]
      : const [TimelineDurationUnit.units];

  /// How its leap years are found in fact: none off the year scales, and
  /// the cycle only for calendar years.
  TimelineLeapMonths get _leap => !countsYears
      ? TimelineLeapMonths.none
      : leapMonths == TimelineLeapMonths.cycle && !isCalendar
      ? TimelineLeapMonths.none
      : leapMonths;

  /// Whether the year [value] (as written) has a second Adar. One year's
  /// calendar has it, or not, whatever the setting that turns it on.
  bool isLeapYear(double value) => isAnnual
      ? leapMonths != TimelineLeapMonths.none
      : switch (_leap) {
          TimelineLeapMonths.none => false,
          TimelineLeapMonths.chosen => leapYears.contains(value.round()),
          TimelineLeapMonths.cycle => hebrewCycleLeapYear(
            _astronomical(value) + _anno,
          ),
        };

  int monthsIn(double value) => isLeapYear(value) ? 13 : 12;

  /// The day of the week [time] (with its month and day) falls on: 1 to 6,
  /// or 7 for the Sabbath. Weeks run on unbroken from 1 Nisan of
  /// [weekYear], through years of 354 or 384 days.
  int weekdayOf(TimelineTime time) {
    final month = time.month ?? 1;
    var days = _daysBefore(month) + (time.day ?? 1) - 1;
    final anchor = weekYear;
    if (countsYears && anchor != null) {
      final from = _astronomical(anchor);
      final to = _astronomical(time.value);
      for (var year = math.min(from, to); year < math.max(from, to); year++) {
        final length = daysInYear(_written(year));
        days += from < to ? length : -length;
      }
    }
    return (nisanWeekday - 1 + days) % 7 + 1;
  }

  /// Whether [time] falls on the day [day]: its month and day, and its year
  /// unless this is one year's calendar.
  bool isOnDay(TimelineTime time, TimelineTime day) =>
      time.month == day.month &&
      time.day == day.day &&
      (isAnnual || time.value == day.value);

  /// The high Sabbaths among [entries] that fall on [day].
  List<StudyTimelineEntry> highSabbathsOn(
    Iterable<StudyTimelineEntry> entries,
    TimelineTime day,
  ) => [
    for (final entry in entries)
      if (entry.isHighSabbath && isOnDay(entry.start, day)) entry,
  ];

  /// The year after (or, with [step] -1, before) [value]: by era there is
  /// no year 0.
  double nextYear(double value, {int step = 1}) =>
      _written(_astronomical(value) + step);

  int daysInYear(double value) => isLeapYear(value) ? 384 : 354;

  /// The days in [month] of the year [value]: 30 and 29 by turns from
  /// Nisan; in a leap year Adar I has 30 and Adar II 29.
  int daysInMonth(double value, int month) {
    if (month == 13) return 29;
    if (month == 12 && isLeapYear(value)) return 30;
    return month.isOdd ? 30 : 29;
  }

  /// The month's name in the year [value], as the timeline names them:
  /// "Nisan" (Adar I and Adar II in a leap year), "Abib", or by number,
  /// "3rd month". The months added in a leap year have no name before the
  /// exile, and go by number.
  String monthName(double value, int month) {
    final name = _monthName(value, month);
    return name ?? '${ordinal(month)} month';
  }

  /// The month's name, or null for one known only by its number.
  String? _monthName(double value, int month) => switch (monthNaming) {
    TimelineMonthNaming.numbered => null,
    TimelineMonthNaming.preExile => preExileMonthNames[month],
    TimelineMonthNaming.postExile =>
      month == 13
          ? 'Adar II'
          : month == 12 && isLeapYear(value)
          ? 'Adar I'
          : hebrewMonthNames[month - 1],
  };

  /// A month as offered to choose from: its number with its name, "1 ·
  /// Nisan", or for one known only by number, "3rd month".
  String monthChoice(double value, int month) {
    final name = _monthName(value, month);
    return name == null ? '${ordinal(month)} month' : '$month · $name';
  }

  /// A day of a month as written: "14 Nisan", or for a month known only
  /// by number, "14th of the 3rd month".
  String formatDate(double value, int month, int? day) {
    final name = _monthName(value, month);
    if (day == null) return monthName(value, month);
    return name == null
        ? '${ordinal(day)} of the ${ordinal(month)} month'
        : '$day $name';
  }

  /// Whether [time] can stand on this timeline: its year has its month and
  /// its month its day; on one year's calendar, it names its month.
  bool fits(TimelineTime time) {
    if (!time.isValid) return false;
    final month = time.month;
    if (isAnnual && (month == null || time.value != 0)) return false;
    if (month == null || !hasMonths) return true;
    if (month > monthsIn(time.value)) return false;
    final day = time.day;
    return day == null || day <= daysInMonth(time.value, month);
  }

  /// Where [time] falls on this timeline's continuous axis: its year, and
  /// the days of the year before its month and day as a fraction of it.
  double positionOf(TimelineTime time) {
    final month = time.month;
    if (month == null || !hasMonths) {
      return time.position(calendar: isCalendar);
    }
    final year = TimelineTime(time.value).position(calendar: isCalendar);
    final days = _daysBefore(month) + (time.day ?? 1) - 1;
    return year + days / daysInYear(time.value);
  }

  /// Where [time] ends on the axis: a day where the next begins, as a day
  /// is a stretch of it; a coarser time, or one off the year scales, where
  /// it starts.
  double endOf(TimelineTime time) {
    final start = positionOf(time);
    if (!hasMonths || time.month == null || time.day == null) return start;
    return start + 1 / daysInYear(time.value);
  }

  /// The middle of [time] on the axis: the middle of a day, else where it
  /// starts.
  double centreOf(TimelineTime time) => (positionOf(time) + endOf(time)) / 2;

  /// A year as written turned into one counted with a year zero (1 BC is 0),
  /// so that years can be added across the turn of the era; and back.
  int _astronomical(double value) {
    final year = value.round();
    return isCalendar && year < 0 ? year + 1 : year;
  }

  double _written(int year) =>
      (isCalendar && year <= 0 ? year - 1 : year).toDouble();

  /// The time [duration] after [start], or null when the duration is finer
  /// than the start (months from a year alone), or the start is not a
  /// whole year where it must be or does not fit the timeline. Months are
  /// lunar, a second Adar in each leap year (see [hebrewMonthNames]). A
  /// month or year added to a day its end month lacks ends on that month's
  /// last day; one added to Adar II, in a year without it, in Adar. Days
  /// are counted inclusively, as the seven days of Unleavened Bread run
  /// from the 15th to the 21st: the end is the last of them, so a span of
  /// days lasts at least one. On one year's calendar a span must end within
  /// the year.
  TimelineTime? addDuration(TimelineTime start, TimelineDuration duration) {
    final end = _addDuration(start, duration);
    return isAnnual && end != null && end.value != start.value ? null : end;
  }

  /// The day [n] days after [time] (before it, for [n] negative), or null
  /// when [time] is not a day of this timeline, or, on one year's calendar,
  /// the day falls outside the year.
  TimelineTime? addDays(TimelineTime time, int n) {
    if (!hasMonths || time.day == null || !fits(time)) return null;
    var year = _astronomical(time.value);
    var day = _daysBefore(time.month!) + time.day! - 1 + n;
    while (day < 0) {
      year--;
      day += daysInYear(_written(year));
    }
    while (day >= daysInYear(_written(year))) {
      day -= daysInYear(_written(year));
      year++;
    }
    final value = _written(year);
    if (isAnnual && value != 0) return null;
    var month = 1;
    while (day >= daysInMonth(value, month)) {
      day -= daysInMonth(value, month);
      month++;
    }
    return TimelineTime(value, month: month, day: day + 1);
  }

  /// The days from [from] to [to]: 0 for the same day, negative where [to]
  /// comes first; null unless both are days of this timeline.
  int? daysBetween(TimelineTime from, TimelineTime to) {
    if (!hasMonths || from.day == null || to.day == null) return null;
    if (!fits(from) || !fits(to)) return null;
    var days =
        _daysBefore(to.month!) + to.day! - _daysBefore(from.month!) - from.day!;
    final a = _astronomical(from.value);
    final b = _astronomical(to.value);
    for (var year = math.min(a, b); year < math.max(a, b); year++) {
      final length = daysInYear(_written(year));
      days += a < b ? length : -length;
    }
    return days;
  }

  /// Where [day] falls in the counted span [span] (see
  /// [StudyTimelineEntry.isCounted]): its day, from 1, its week, from 1,
  /// and its day within that week; null outside the span, or where the
  /// span is not counted in days.
  ({int day, int week, int dayOfWeek})? countIn(
    StudyTimelineEntry span,
    TimelineTime day,
  ) {
    if (!span.isCounted) return null;
    final n = daysBetween(span.start, day);
    final length = daysBetween(span.start, span.last);
    if (n == null || length == null || n < 0 || n > length) return null;
    return (day: n + 1, week: n ~/ 7 + 1, dayOfWeek: n % 7 + 1);
  }

  /// Which day of [span] [day] is, 1 for its first; null outside it, or
  /// where either is not dated to the day.
  int? dayIn(StudyTimelineEntry span, TimelineTime day) {
    final n = daysBetween(span.start, day);
    final length = daysBetween(span.start, span.last);
    if (n == null || length == null || n < 0 || n > length) return null;
    return n + 1;
  }

  /// The days a span runs, its first and last among them; null where it
  /// is not dated to the day.
  int? daysIn(StudyTimelineEntry span) {
    final days = daysBetween(span.start, span.last);
    return days == null ? null : days + 1;
  }

  /// Where an entry pinned by [pin] to [anchor] starts (see [TimelinePin]):
  /// counted in days from the anchor's first day, day 1 being that day, or
  /// else in months or years from its start; then moved on, given a
  /// weekday, to the first such day. Null where it cannot be counted.
  TimelineTime? placePin(StudyTimelineEntry anchor, TimelinePin pin) {
    final offset = pin.offset;
    var at = offset.unit == TimelineDurationUnit.days
        ? addDays(anchor.start, offset.amount.round() - 1)
        : addDuration(anchor.start, offset);
    final weekday = pin.weekday;
    if (at == null || weekday == null) return at;
    for (var i = 0; i < 7; i++) {
      if (weekdayOf(at!) == weekday) return at;
      at = addDays(at, 1);
      if (at == null) return null;
    }
    return null;
  }

  /// How an entry pinned to [anchor] starts out: on its first day, or else
  /// at its start; null where nothing can be counted from its start.
  TimelinePin? firstPinTo(StudyTimelineEntry anchor) {
    final units = durationUnitsFor(anchor.start);
    if (units.contains(TimelineDurationUnit.days)) {
      return TimelinePin(
        anchor.id,
        const TimelineDuration(1, TimelineDurationUnit.days),
      );
    }
    return units.isEmpty
        ? null
        : TimelinePin(anchor.id, TimelineDuration(0, units.first));
  }

  /// [entry] moved to start at [start], a span keeping its length: its
  /// end worked out again from its duration, or moved as many days (or, by
  /// years alone, years) as its start. Null where it cannot be moved so.
  StudyTimelineEntry? moveEntry(StudyTimelineEntry entry, TimelineTime start) {
    final end = entry.end;
    if (end == null) return entry.withTime(start: start, end: null);
    final duration = entry.duration;
    if (duration != null) {
      return entry
          .withTime(start: start, end: end, duration: duration)
          .fittedTo(this);
    }
    final days = daysBetween(entry.start, start);
    final TimelineTime? moved;
    if (days != null && end.day != null) {
      moved = addDays(end, days);
    } else if (start.month == null &&
        entry.start.month == null &&
        end.month == null &&
        countsYears) {
      moved = TimelineTime(
        _written(
          _astronomical(end.value) +
              _astronomical(start.value) -
              _astronomical(entry.start.value),
        ),
      );
    } else if (!hasMonths) {
      moved = TimelineTime(end.value + start.value - entry.start.value);
    } else {
      moved = null;
    }
    return moved == null ? null : entry.withTime(start: start, end: moved);
  }

  TimelineTime? _addDuration(TimelineTime start, TimelineDuration duration) {
    if (!duration.isValid || !fits(start)) return null;
    if (!durationUnitsFor(start).contains(duration.unit)) return null;
    final amount = duration.amount;
    if (!hasMonths) return TimelineTime(start.value + amount);
    if (start.value != start.value.roundToDouble()) return null;
    final n = amount.round();
    var year = _astronomical(start.value);
    switch (duration.unit) {
      case TimelineDurationUnit.units:
        return null;
      case TimelineDurationUnit.years:
        return _settle(_written(year + n), start.month, start.day);
      case TimelineDurationUnit.months:
        var month = start.month!;
        var left = n;
        while (left > 0) {
          final rest = monthsIn(_written(year)) - month;
          if (left <= rest) {
            month += left;
            left = 0;
          } else {
            left -= rest + 1;
            year++;
            month = 1;
          }
        }
        return _settle(_written(year), month, start.day);
      case TimelineDurationUnit.days:
        if (n < 1) return null;
        var day = _daysBefore(start.month!) + start.day! - 1 + n - 1;
        while (day >= daysInYear(_written(year))) {
          day -= daysInYear(_written(year));
          year++;
        }
        final value = _written(year);
        var month = 1;
        while (day >= daysInMonth(value, month)) {
          day -= daysInMonth(value, month);
          month++;
        }
        return TimelineTime(value, month: month, day: day + 1);
    }
  }

  /// [time] moved to where it can stand on this timeline: without a year
  /// on one year's calendar, Adar II as Adar in a year without it, and a
  /// day its month lacks as the month's last. Times off the year scales,
  /// and those it cannot place (a year's calendar without a month), are
  /// left as they are.
  TimelineTime settle(TimelineTime time) {
    if (!hasMonths || time.month == null || !time.isValid) return time;
    return _settle(isAnnual ? 0 : time.value, time.month, time.day);
  }

  /// The time [month] and [day] of [value] give, kept within the year's
  /// months and the month's days.
  TimelineTime _settle(double value, int? month, int? day) {
    if (month == null) return TimelineTime(value);
    final kept = math.min(month, monthsIn(value));
    return TimelineTime(
      value,
      month: kept,
      day: day == null ? null : math.min(day, daysInMonth(value, kept)),
    );
  }

  /// The year (or count) alone as written: "1446 BC" or "AD 30" counting
  /// calendar years, else the unit and number, as "Day 3".
  String formatValue(double value) {
    if (isCalendar) {
      final number = formatTimelineNumber(value.abs());
      if (value < 0) return '$number BC';
      if (value > 0) return 'AD $number';
    }
    final signed = formatTimelineNumber(value);
    return unit.isEmpty ? signed : '$unit $signed';
  }

  /// A time as written: "14 Nisan 1446 BC", "Iyyar, Year 4", "Day 3".
  String formatTime(TimelineTime time) {
    final value = formatValue(time.value);
    final month = time.month;
    if (month == null || !hasMonths) return value;
    final date = formatDate(time.value, month, time.day);
    if (isAnnual) return date;
    return isCalendar ? '$date $value' : '$date, $value';
  }

  /// A length as written: "40 years", "1 month", "7 Days".
  String formatDuration(TimelineDuration duration) {
    final amount = formatTimelineNumber(duration.amount);
    final one = duration.amount == 1;
    return switch (duration.unit) {
      TimelineDurationUnit.years => '$amount ${one ? 'year' : 'years'}',
      TimelineDurationUnit.months => '$amount ${one ? 'month' : 'months'}',
      TimelineDurationUnit.days => '$amount ${one ? 'day' : 'days'}',
      TimelineDurationUnit.units =>
        unit.isEmpty
            ? amount
            : one || unit.endsWith('s')
            ? '$amount $unit'
            : '$amount ${unit}s',
    };
  }

  StudyTimeline copyWith({
    String? title,
    TimelineScale? scale,
    String? unit,
    TimelineLeapMonths? leapMonths,
    Set<int>? leapYears,
    TimelineMonthNaming? monthNaming,
    int? nisanWeekday,
    double? Function()? weekYear,
    bool? showSeasons,
    Map<String, int>? categoryColors,
    String? note,
    String? Function()? parentId,
    int? order,
  }) => StudyTimeline(
    extra: extra,
    id: id,
    title: title ?? this.title,
    scale: scale ?? this.scale,
    unit: unit ?? this.unit,
    leapMonths: leapMonths ?? this.leapMonths,
    leapYears: leapYears ?? this.leapYears,
    monthNaming: monthNaming ?? this.monthNaming,
    nisanWeekday: nisanWeekday ?? this.nisanWeekday,
    weekYear: weekYear == null ? this.weekYear : weekYear(),
    showSeasons: showSeasons ?? this.showSeasons,
    categoryColors: categoryColors ?? this.categoryColors,
    note: note ?? this.note,
    parentId: parentId == null ? this.parentId : parentId(),
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'scale': scale.name,
    'unit': unit,
    if (leapMonths != TimelineLeapMonths.none) 'leapMonths': leapMonths.name,
    if (leapYears.isNotEmpty) 'leapYears': leapYears.toList()..sort(),
    if (monthNaming != TimelineMonthNaming.postExile)
      'monthNames': monthNaming.name,
    if (nisanWeekday != 1) 'nisanWeekday': nisanWeekday,
    if (weekYear != null) 'weekYear': _jsonNumber(weekYear!),
    if (showSeasons) 'seasons': true,
    if (categoryColors.isNotEmpty) 'categories': categoryColors,
    if (note.isNotEmpty) 'note': note,
    if (parentId != null) 'parent': parentId,
    'order': order,
  };

  static StudyTimeline? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    if (id is! String || title is! String) return null;
    // The first timelines had only an era flag for calendar years.
    final scale =
        TimelineScale.values
            .where((s) => s.name == value['scale'])
            .firstOrNull ??
        (value['era'] == true ? TimelineScale.calendar : TimelineScale.units);
    final timeline = StudyTimeline(
      extra: timelineExtraKeys(value, const {
        'id',
        'title',
        'scale',
        'era',
        'unit',
        'leapMonths',
        'leapYears',
        'monthNames',
        'nisanWeekday',
        'weekYear',
        'seasons',
        'categories',
        'sabbaths',
        'note',
        'parent',
        'order',
      }),
      id: id,
      title: title,
      scale: scale,
      unit: value['unit'] is String ? value['unit'] as String : 'Year',
      leapMonths:
          TimelineLeapMonths.values
              .where((l) => l.name == value['leapMonths'])
              .firstOrNull ??
          TimelineLeapMonths.none,
      leapYears: {
        if (value['leapYears'] is List)
          ...(value['leapYears'] as List).whereType<int>(),
      },
      monthNaming:
          TimelineMonthNaming.values
              .where((n) => n.name == value['monthNames'])
              .firstOrNull ??
          TimelineMonthNaming.postExile,
      nisanWeekday:
          value['nisanWeekday'] is int &&
              (value['nisanWeekday'] as int) >= 1 &&
              (value['nisanWeekday'] as int) <= 7
          ? value['nisanWeekday'] as int
          : 1,
      weekYear: value['weekYear'] is num
          ? (value['weekYear'] as num).toDouble()
          : null,
      showSeasons: value['seasons'] == true,
      categoryColors: {
        if (value['categories'] case final Map categories)
          for (final MapEntry(:key, :value) in categories.entries)
            if (key is String && value is int && value >= 0) key: value,
      },
      note: value['note'] is String ? value['note'] as String : '',
      parentId: value['parent'] is String ? value['parent'] as String : null,
      order: value['order'] is int ? value['order'] as int : 0,
    );
    return timeline.isValid ? timeline : null;
  }

  /// The high Sabbaths a timeline stored by date alone, before they became
  /// events (see [StudyTimelineEntry.sabbath]); dropped from the timeline
  /// on load, as `sabbaths` is a key it knows.
  static List<TimelineTime> legacySabbaths(Object? value) => [
    if (value is Map && value['sabbaths'] is List)
      for (final day in value['sabbaths'] as List)
        if (day is Map &&
            day['month'] is int &&
            day['day'] is int &&
            (day['year'] == null || day['year'] is num))
          TimelineTime(
            (day['year'] as num?)?.toDouble() ?? 0,
            month: day['month'] as int,
            day: day['day'] as int,
          ),
  ];
}

/// How an entry is pinned to another on its timeline, the [anchorId], so
/// that it moves with it: [offset] from the anchor's start. Days are
/// counted as Scripture counts them, inclusively: day 1 is the anchor's
/// own (first) day, 2 the next, 0 the day before, as Pentecost is the 50th
/// day counting from the wave sheaf (Leviticus 23:15-16). Months and years
/// count on from the start, from 0. Given a [weekday] (1 to 6, or 7 for
/// the Sabbath), it falls on the first such day on or after that day: the
/// morrow after the Sabbath.
@immutable
class TimelinePin {
  const TimelinePin(this.anchorId, this.offset, {this.weekday});

  final String anchorId;
  final TimelineDuration offset;
  final int? weekday;

  bool get isDays => offset.unit == TimelineDurationUnit.days;

  bool get isValid =>
      anchorId.isNotEmpty &&
      offset.amount.isFinite &&
      (offset.unit == TimelineDurationUnit.units ||
          offset.amount == offset.amount.roundToDouble()) &&
      (isDays || offset.amount >= 0) &&
      (weekday == null || (isDays && weekday! >= 1 && weekday! <= 7));

  Map<String, Object?> toJson() => {
    'anchor': anchorId,
    'offset': offset.toJson(),
    if (weekday != null) 'weekday': weekday,
  };

  static TimelinePin? fromJson(Object? value) {
    if (value is! Map) return null;
    final anchor = value['anchor'];
    final offset = value['offset'];
    final weekday = value['weekday'];
    if (anchor is! String || offset is! Map) return null;
    if (weekday != null && weekday is! int) return null;
    final amount = offset['amount'];
    final unit = TimelineDurationUnit.values
        .where((u) => u.name == offset['unit'])
        .firstOrNull;
    if (amount is! num || unit == null) return null;
    final pin = TimelinePin(
      anchor,
      TimelineDuration(amount.toDouble(), unit),
      weekday: weekday as int?,
    );
    return pin.isValid ? pin : null;
  }

  @override
  bool operator ==(Object other) =>
      other is TimelinePin &&
      other.anchorId == anchorId &&
      other.offset == offset &&
      other.weekday == weekday;

  @override
  int get hashCode => Object.hash(anchorId, offset, weekday);
}

/// An event (a point in time) or a span (from [start] to [end]) on a
/// timeline, which it lives directly in, with the verses it is linked to.
/// A span may be given by its [duration], from which its end is worked
/// out on its timeline (see [StudyTimeline.addDuration]). [date] is how the
/// time is written where the scale alone would not say it ("c."). It
/// may be pinned to another entry ([pin]), moving with it.
@immutable
class StudyTimelineEntry {
  const StudyTimelineEntry({
    required this.id,
    required this.title,
    required this.timelineId,
    required this.start,
    this.end,
    this.duration,
    this.date = '',
    this.verses = const [],
    this.note = '',
    this.sabbath = false,
    this.counted = false,
    this.part,
    this.category = '',
    this.dayNotes = const {},
    this.order = 0,
    this.pin,
    this.extra = const {},
  });

  /// Keys this version does not know, kept so that saving does not erase
  /// fields a newer version wrote.
  final Map<String, Object?> extra;

  final String id;
  final String title;
  final String timelineId;
  final TimelineTime start;

  /// Present only for a span.
  final TimelineTime? end;

  /// How long a span lasts, when it was given that way.
  final TimelineDuration? duration;
  final String date;

  /// The verse ranges it is linked to; only their references are used.
  final List<StudyPassage> verses;
  final String note;

  /// Whether this event is a high Sabbath: a feast day kept as a Sabbath,
  /// its day coloured as one in the calendar. Spans are not.
  final bool sabbath;

  /// Whether a span's days and weeks are counted and numbered, as the
  /// fifty days to Pentecost (Leviticus 23:15-16); see [isCounted].
  final bool counted;

  /// The part of its day an event falls in, where it is dated to the day;
  /// null for the whole day.
  final TimelineDayPart? part;

  /// What kind of entry it is, as the study names it ("Pilgrim feast"),
  /// coloured as its timeline colours it (see
  /// [StudyTimeline.categoryColors]); empty for none.
  final String category;

  /// A span's notes for its days, by day from 1 for its first: the
  /// offerings of each day of Tabernacles (Numbers 29:12-38).
  final Map<int, String> dayNotes;

  /// [part] where it means anything: an event dated to the day.
  TimelineDayPart? get dayPart => isSpan || start.day == null ? null : part;
  final int order;

  /// The entry on its timeline it is pinned to: its [start] is then kept
  /// where [StudyTimeline.placePin] puts it, following the anchor as it
  /// moves.
  final TimelinePin? pin;

  bool get isSpan => end != null;
  bool get isHighSabbath => sabbath && !isSpan;
  bool get isCounted => counted && isSpan;
  TimelineTime get last => end ?? start;
  String get key => 'timeline-entry-$id';

  bool get isValid =>
      id.isNotEmpty &&
      title.isNotEmpty &&
      start.isValid &&
      (end == null || (end!.isValid && end!.position() >= start.position())) &&
      (duration == null || (end != null && duration!.isValid)) &&
      (pin == null || (pin!.isValid && pin!.anchorId != id));

  /// Pinned by [pin], or, given none, unpinned; the start is placed by
  /// the workspace (see [StudyTimeline.placePin]).
  StudyTimelineEntry pinnedTo(TimelinePin? pin) => StudyTimelineEntry(
    extra: extra,
    id: id,
    title: title,
    timelineId: timelineId,
    start: start,
    end: end,
    duration: duration,
    date: date,
    verses: verses,
    note: note,
    sabbath: sabbath,
    counted: counted,
    part: part,
    category: category,
    dayNotes: dayNotes,
    order: order,
    pin: pin,
  );

  bool linksVerse(int book, int chapter, int verse) =>
      verses.any((passage) => passage.containsVerse(book, chapter, verse));

  /// Change only the time; retain the outline place and notes.
  StudyTimelineEntry withTime({
    required TimelineTime start,
    required TimelineTime? end,
    TimelineDuration? duration,
  }) => StudyTimelineEntry(
    extra: extra,
    id: id,
    title: title,
    timelineId: timelineId,
    start: start,
    end: end,
    duration: duration,
    date: date,
    verses: verses,
    note: note,
    sabbath: sabbath,
    counted: counted,
    part: part,
    category: category,
    dayNotes: dayNotes,
    order: order,
    pin: pin,
  );

  /// The entry on [timeline], its end worked out again from its duration
  /// (for one given that way); null when the duration no longer fits.
  StudyTimelineEntry? fittedTo(StudyTimeline timeline) {
    final duration = this.duration;
    if (duration == null) return this;
    final end = timeline.addDuration(start, duration);
    if (end == null) return null;
    return end == this.end
        ? this
        : withTime(start: start, end: end, duration: duration);
  }

  StudyTimelineEntry copyWith({
    String? title,
    String? timelineId,
    String? date,
    List<StudyPassage>? verses,
    String? note,
    bool? sabbath,
    bool? counted,
    TimelineDayPart? Function()? part,
    String? category,
    Map<int, String>? dayNotes,
    int? order,
  }) => StudyTimelineEntry(
    extra: extra,
    id: id,
    title: title ?? this.title,
    timelineId: timelineId ?? this.timelineId,
    start: start,
    end: end,
    duration: duration,
    date: date ?? this.date,
    verses: verses ?? this.verses,
    note: note ?? this.note,
    sabbath: sabbath ?? this.sabbath,
    counted: counted ?? this.counted,
    part: part == null ? this.part : part(),
    category: category ?? this.category,
    dayNotes: dayNotes ?? this.dayNotes,
    order: order ?? this.order,
    pin: pin,
  );

  Map<String, Object?> toJson() => {
    ...extra,
    'id': id,
    'title': title,
    'timeline': timelineId,
    'start': _jsonNumber(start.value),
    if (start.month != null) 'startMonth': start.month,
    if (start.day != null) 'startDay': start.day,
    if (end != null) 'end': _jsonNumber(end!.value),
    if (end?.month != null) 'endMonth': end!.month,
    if (end?.day != null) 'endDay': end!.day,
    if (duration != null) 'duration': duration!.toJson(),
    if (date.isNotEmpty) 'date': date,
    if (verses.isNotEmpty)
      'verses': [
        for (final passage in verses)
          {
            'book': passage.bookIndex,
            'chapter': passage.chapter,
            'verse': passage.verse,
            if (passage.wholeChapter) 'wholeChapter': true,
            if (passage.endChapter != null) 'endChapter': passage.endChapter,
            if (passage.endVerse != null) 'endVerse': passage.endVerse,
          },
      ],
    if (note.isNotEmpty) 'note': note,
    if (sabbath) 'sabbath': true,
    if (counted) 'counted': true,
    if (part != null) 'part': part!.name,
    if (category.isNotEmpty) 'category': category,
    if (dayNotes.isNotEmpty)
      'days': {
        for (final day in dayNotes.keys.toList()..sort())
          '$day': dayNotes[day],
      },
    'order': order,
    if (pin != null) 'pin': pin!.toJson(),
  };

  static StudyTimelineEntry? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final timelineId = value['timeline'];
    final start = value['start'];
    final end = value['end'];
    if (id is! String ||
        title is! String ||
        timelineId is! String ||
        start is! num ||
        (end != null && end is! num)) {
      return null;
    }
    // A pin was first kept as a span and an offset into it.
    final pin =
        TimelinePin.fromJson(value['pin']) ??
        TimelinePin.fromJson({
          'anchor': value['span'],
          'offset': value['offset'],
        });
    for (final key in ['startMonth', 'startDay', 'endMonth', 'endDay']) {
      if (value[key] != null && value[key] is! int) return null;
    }
    final entry = StudyTimelineEntry(
      extra: timelineExtraKeys(value, const {
        'id',
        'title',
        'timeline',
        'start',
        'startMonth',
        'startDay',
        'end',
        'endMonth',
        'endDay',
        'duration',
        'date',
        'verses',
        'note',
        'sabbath',
        'counted',
        'part',
        'category',
        'days',
        'order',
        'pin',
        'span',
        'offset',
      }),
      id: id,
      title: title,
      timelineId: timelineId,
      start: TimelineTime(
        start.toDouble(),
        month: value['startMonth'] as int?,
        day: value['startDay'] as int?,
      ),
      end: end == null
          ? null
          : TimelineTime(
              (end as num).toDouble(),
              month: value['endMonth'] as int?,
              day: value['endDay'] as int?,
            ),
      duration: end == null
          ? null
          : TimelineDuration.fromJson(value['duration']),
      date: value['date'] is String ? value['date'] as String : '',
      verses: [
        if (value['verses'] is List)
          for (final raw in value['verses'] as List)
            ?StudyPassage.fromJson(raw),
      ],
      note: value['note'] is String ? value['note'] as String : '',
      sabbath: value['sabbath'] == true,
      counted: value['counted'] == true,
      part: TimelineDayPart.values
          .where((p) => p.name == value['part'])
          .firstOrNull,
      category: value['category'] is String
          ? (value['category'] as String).trim()
          : '',
      dayNotes: {
        if (value['days'] case final Map days)
          for (final MapEntry(:key, :value) in days.entries)
            if (key is String &&
                (int.tryParse(key) ?? 0) >= 1 &&
                value is String &&
                value.trim().isNotEmpty)
              int.parse(key): value.trim(),
      },
      order: value['order'] is int ? value['order'] as int : 0,
      pin: pin,
    );
    return entry.isValid ? entry : null;
  }
}

/// Orders a timeline's entries by when they start, then end.
int compareTimelineEntries(StudyTimelineEntry a, StudyTimelineEntry b) {
  final start = a.start.position().compareTo(b.start.position());
  if (start != 0) return start;
  final last = a.last.position().compareTo(b.last.position());
  if (last != 0) return last;
  // Within a day, night, then day, then evening; the whole day first.
  final part = (a.dayPart?.index ?? -1).compareTo(b.dayPart?.index ?? -1);
  if (part != 0) return part;
  return a.order.compareTo(b.order);
}

/// The entries of [value] whose keys are not among [known].
Map<String, Object?> timelineExtraKeys(Map value, Set<String> known) => {
  for (final entry in value.entries)
    if (entry.key is String && !known.contains(entry.key))
      entry.key as String: entry.value,
};

/// What a season of the land is: rain, or a stage of the farming year.
enum TimelineSeasonKind { rain, harvest }

/// A season of the land of Israel through the year, roughly, as Scripture
/// marks it: [from] a month and day to [to] one (inclusive), or, without
/// [to], to the year's end.
@immutable
class TimelineSeason {
  const TimelineSeason(
    this.name,
    this.kind,
    this.from,
    this.to,
    this.references,
  );

  final String name;
  final TimelineSeasonKind kind;
  final ({int month, int day}) from;
  final ({int month, int day})? to;
  final String references;

  /// Where it runs in the year [value] of [timeline], as axis positions.
  ({double start, double end}) inYear(StudyTimeline timeline, double value) {
    final months = timeline.monthsIn(value);
    final last = to ?? (month: months, day: 30);
    final month = math.min(last.month, months);
    return (
      start: timeline.positionOf(
        TimelineTime(value, month: from.month, day: from.day),
      ),
      end: timeline.endOf(
        TimelineTime(
          value,
          month: month,
          day: math.min(last.day, timeline.daysInMonth(value, month)),
        ),
      ),
    );
  }
}

/// The seasons of the land through the year, roughly: the early and the
/// latter rain, and the farming year from the barley harvest at Passover
/// to the sowing after the early rain.
const timelineSeasons = [
  TimelineSeason(
    'Latter rain',
    TimelineSeasonKind.rain,
    (month: 1, day: 1),
    (month: 1, day: 30),
    'Deuteronomy 11:14; Joel 2:23; Jeremiah 5:24',
  ),
  TimelineSeason(
    'Early rain',
    TimelineSeasonKind.rain,
    (month: 8, day: 1),
    (month: 9, day: 30),
    'Deuteronomy 11:14; Joel 2:23; James 5:7',
  ),
  TimelineSeason(
    'Latter rain',
    TimelineSeasonKind.rain,
    (month: 12, day: 1),
    null,
    'Deuteronomy 11:14; Joel 2:23; Jeremiah 5:24',
  ),
  TimelineSeason(
    'Barley harvest',
    TimelineSeasonKind.harvest,
    (month: 1, day: 15),
    (month: 2, day: 15),
    'Exodus 9:31-32; Ruth 1:22; 2 Samuel 21:9',
  ),
  TimelineSeason(
    'Wheat harvest',
    TimelineSeasonKind.harvest,
    (month: 2, day: 16),
    (month: 3, day: 30),
    'Exodus 34:22; Ruth 2:23; 1 Samuel 12:17',
  ),
  TimelineSeason(
    'Summer fruit',
    TimelineSeasonKind.harvest,
    (month: 4, day: 1),
    (month: 5, day: 30),
    'Amos 8:1-2; Jeremiah 40:10-12; 2 Samuel 16:1',
  ),
  TimelineSeason(
    'Vintage',
    TimelineSeasonKind.harvest,
    (month: 6, day: 1),
    (month: 6, day: 29),
    'Leviticus 26:5; Judges 9:27',
  ),
  TimelineSeason(
    'Ingathering',
    TimelineSeasonKind.harvest,
    (month: 7, day: 1),
    (month: 7, day: 30),
    'Exodus 23:16; Deuteronomy 16:13',
  ),
  TimelineSeason(
    'Ploughing and sowing',
    TimelineSeasonKind.harvest,
    (month: 8, day: 1),
    (month: 10, day: 29),
    'Leviticus 26:5; Proverbs 20:4',
  ),
];

/// The moon on [day] of a month: its start, the new moon, on the 1st, and
/// the full moon on the 15th, when the Passover and Tabernacles begin;
/// null on other days.
String? timelineMoonOn(int day) => switch (day) {
  1 => 'New moon',
  15 => 'Full moon',
  _ => null,
};
