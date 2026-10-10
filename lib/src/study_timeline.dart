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
/// same holds for every month up to Adar I in a leap year.
int _daysBefore(int month) => (month - 1) * 29 + month ~/ 2;

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

  int daysInYear(double value) => isLeapYear(value) ? 384 : 354;

  /// The days in [month] of the year [value]: 30 and 29 by turns from
  /// Nisan; in a leap year Adar I has 30 and Adar II 29.
  int daysInMonth(double value, int month) {
    if (month == 13) return 29;
    if (month == 12 && isLeapYear(value)) return 30;
    return month.isOdd ? 30 : 29;
  }

  /// The month's name in the year [value]: Adar I and Adar II in a leap
  /// year.
  String monthName(double value, int month) {
    if (month == 13) return 'Adar II';
    if (month == 12 && isLeapYear(value)) return 'Adar I';
    return hebrewMonthNames[month - 1];
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
  /// last day; one added to Adar II, in a year without it, in Adar. On one
  /// year's calendar a span must end within the year.
  TimelineTime? addDuration(TimelineTime start, TimelineDuration duration) {
    final end = _addDuration(start, duration);
    return isAnnual && end != null && end.value != start.value ? null : end;
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
        var day = _daysBefore(start.month!) + start.day! - 1 + n;
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
    final name = monthName(time.value, month);
    final date = time.day == null ? name : '${time.day} $name';
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
      note: value['note'] is String ? value['note'] as String : '',
      parentId: value['parent'] is String ? value['parent'] as String : null,
      order: value['order'] is int ? value['order'] as int : 0,
    );
    return timeline.isValid ? timeline : null;
  }
}

/// An event (a point in time) or a span (from [start] to [end]) on a
/// timeline, which it lives directly in, with the verses it is linked to.
/// A span may be given by its [duration], from which its end is worked
/// out on its timeline (see [StudyTimeline.addDuration]). [date] is how the
/// time is written where the scale alone would not say it ("c.").
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
    this.order = 0,
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
  final int order;

  bool get isSpan => end != null;
  TimelineTime get last => end ?? start;
  String get key => 'timeline-entry-$id';

  bool get isValid =>
      id.isNotEmpty &&
      title.isNotEmpty &&
      start.isValid &&
      (end == null || (end!.isValid && end!.position() >= start.position())) &&
      (duration == null || (end != null && duration!.isValid));

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
    order: order,
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
    order: order ?? this.order,
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
    'order': order,
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
        'order',
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
      order: value['order'] is int ? value['order'] as int : 0,
    );
    return entry.isValid ? entry : null;
  }
}

/// Orders a timeline's entries by when they start, then end.
int compareTimelineEntries(StudyTimelineEntry a, StudyTimelineEntry b) {
  final start = a.start.position().compareTo(b.start.position());
  if (start != 0) return start;
  final last = a.last.position().compareTo(b.last.position());
  return last != 0 ? last : a.order.compareTo(b.order);
}

/// The entries of [value] whose keys are not among [known].
Map<String, Object?> timelineExtraKeys(Map value, Set<String> known) => {
  for (final entry in value.entries)
    if (entry.key is String && !known.contains(entry.key))
      entry.key as String: entry.value,
};
