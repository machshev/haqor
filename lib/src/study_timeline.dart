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
}

/// What a span's length is counted in.
enum TimelineDurationUnit { years, months, days, units }

/// The months of the Bible's year, from Nisan (Abib), its first month. They
/// are lunar: 30 and 29 days by turns, Nisan's 30, a year of 354 days. The
/// month added in some years (a second Adar) is not counted.
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

/// The days in a lunar [month] (1-based, from Nisan).
int lunarMonthDays(int month) => month.isOdd ? 30 : 29;

const _lunarYearDays = 354;

/// The days of the lunar year before [month] begins: 29 for each month
/// before it, and one more for each of those (Nisan, Sivan, …) of 30.
int _daysBefore(int month) => (month - 1) * 29 + month ~/ 2;

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

  bool get isValid =>
      value.isFinite &&
      (month == null ||
          (month! >= 1 && month! <= 12 && value == value.roundToDouble())) &&
      (day == null ||
          (month != null && day! >= 1 && day! <= lunarMonthDays(month!)));

  /// Where it falls on a continuous axis, for ordering and drawing: the
  /// year, then the month and day as fractions of it. On a [calendar] axis
  /// a BC year moves up one, so 1 BC runs straight on into AD 1.
  double position({bool calendar = false}) =>
      (calendar && value < 0 ? value + 1 : value) +
      (month == null ? 0 : (month! - 1) / 12) +
      (day == null ? 0 : (day! - 1) / _lunarYearDays);

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
  final String note;
  final String? parentId;
  final int order;

  bool get isValid => id.isNotEmpty && title.isNotEmpty;
  bool get isCalendar => scale == TimelineScale.calendar;

  /// Whether it counts years, whose times may name a month and day.
  bool get countsYears => scale != TimelineScale.units;

  /// The units a span starting at [start] may give its length in: years,
  /// then months and days as far as the start names them; or the
  /// timeline's own unit.
  List<TimelineDurationUnit> durationUnitsFor(TimelineTime start) => countsYears
      ? [
          TimelineDurationUnit.years,
          if (start.month != null) TimelineDurationUnit.months,
          if (start.day != null) TimelineDurationUnit.days,
        ]
      : const [TimelineDurationUnit.units];

  /// Where [time] falls on this timeline's continuous axis.
  double positionOf(TimelineTime time) => time.position(calendar: isCalendar);

  /// A year as written turned into one counted with a year zero (1 BC is 0),
  /// so that years can be added across the turn of the era; and back.
  int _astronomical(double value) {
    final year = value.round();
    return isCalendar && year < 0 ? year + 1 : year;
  }

  double _written(int year) =>
      (isCalendar && year <= 0 ? year - 1 : year).toDouble();

  /// The time [duration] after [start], or null when the duration is finer
  /// than the start (months from a year alone) or the start is not a whole
  /// year where it must be. Months are lunar (see [hebrewMonthNames]); a
  /// month added to a 30th ends on a 29-day month's last day.
  TimelineTime? addDuration(TimelineTime start, TimelineDuration duration) {
    if (!duration.isValid || !start.isValid) return null;
    if (!durationUnitsFor(start).contains(duration.unit)) return null;
    final amount = duration.amount;
    if (!countsYears) return TimelineTime(start.value + amount);
    if (start.value != start.value.roundToDouble()) return null;
    final n = amount.round();
    final year = _astronomical(start.value);
    switch (duration.unit) {
      case TimelineDurationUnit.units:
        return null;
      case TimelineDurationUnit.years:
        final end = TimelineTime(
          _written(year + n),
          month: start.month,
          day: start.day,
        );
        return _clampDay(end);
      case TimelineDurationUnit.months:
        final total = year * 12 + (start.month! - 1) + n;
        final endYear = (total / 12).floor();
        return _clampDay(
          TimelineTime(
            _written(endYear),
            month: total - endYear * 12 + 1,
            day: start.day,
          ),
        );
      case TimelineDurationUnit.days:
        final ordinal =
            year * _lunarYearDays +
            _daysBefore(start.month!) +
            (start.day! - 1) +
            n;
        final endYear = (ordinal / _lunarYearDays).floor();
        final inYear = ordinal - endYear * _lunarYearDays;
        var month = 12;
        while (_daysBefore(month) > inYear) {
          month--;
        }
        return TimelineTime(
          _written(endYear),
          month: month,
          day: inYear - _daysBefore(month) + 1,
        );
    }
  }

  TimelineTime _clampDay(TimelineTime time) {
    final day = time.day;
    if (day == null) return time;
    final most = lunarMonthDays(time.month!);
    return day <= most
        ? time
        : TimelineTime(time.value, month: time.month, day: most);
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
    if (month == null || !countsYears) return value;
    final name = hebrewMonthNames[month - 1];
    final date = time.day == null ? name : '${time.day} $name';
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
    String? note,
    String? Function()? parentId,
    int? order,
  }) => StudyTimeline(
    extra: extra,
    id: id,
    title: title ?? this.title,
    scale: scale ?? this.scale,
    unit: unit ?? this.unit,
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
        'note',
        'parent',
        'order',
      }),
      id: id,
      title: title,
      scale: scale,
      unit: value['unit'] is String ? value['unit'] as String : 'Year',
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
