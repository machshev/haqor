import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../study_workspace.dart';

/// A day of the week by name: "Day 3", or "Sabbath".
String timelineWeekdayName(int weekday) =>
    weekday == 7 ? 'Sabbath' : 'Day $weekday';

/// Where an entry falls on a timeline's axis, from its first day to its
/// last: a time given by its month alone runs to the month's end, and one
/// given by its year alone to the year's.
({double first, double last}) timelineEntryDays(
  StudyTimeline timeline,
  StudyTimelineEntry entry,
) {
  TimelineTime lastDay(TimelineTime time) {
    if (time.day != null) return time;
    final month = time.month ?? timeline.monthsIn(time.value);
    return TimelineTime(
      time.value,
      month: month,
      day: timeline.daysInMonth(time.value, month),
    );
  }

  final start = entry.start.month == null
      ? TimelineTime(entry.start.value, month: 1, day: 1)
      : TimelineTime(
          entry.start.value,
          month: entry.start.month,
          day: entry.start.day ?? 1,
        );
  return (
    first: timeline.positionOf(start),
    last: timeline.positionOf(lastDay(entry.last)),
  );
}

/// One year of a timeline as a calendar: each month a grid of weeks from
/// the first day to the Sabbath, the Sabbaths coloured, and the high
/// Sabbaths more strongly; events marked on their days and spans across
/// theirs. Tapping a day calls [onTapDay].
class TimelineCalendar extends StatelessWidget {
  const TimelineCalendar({
    super.key,
    required this.timeline,
    required this.entries,
    required this.year,
    this.onTapDay,
    this.selected,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;

  /// The year shown, as written; 0 on one year's calendar.
  final double year;
  final ValueChanged<TimelineTime>? onTapDay;
  final TimelineTime? selected;

  bool _inYear(TimelineTime time) => timeline.isAnnual || time.value == year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Entries dated to the year alone are listed above its months.
    final yearOnly = [
      for (final entry in entries)
        if (!entry.isSpan && entry.start.month == null && _inYear(entry.start))
          entry,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = math.max(1, (constraints.maxWidth / 320).floor());
        final width = math.min(
          (constraints.maxWidth - gap * (columns + 1)) / columns,
          420.0,
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(gap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Legend(scheme: scheme),
              if (yearOnly.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final entry in yearOnly)
                        Chip(
                          avatar: Icon(
                            Icons.radio_button_checked,
                            size: 14,
                            color: scheme.tertiary,
                          ),
                          label: Text(entry.title),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: gap),
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var month = 1; month <= timeline.monthsIn(year); month++)
                    SizedBox(
                      width: width,
                      child: _Month(
                        timeline: timeline,
                        entries: entries,
                        year: year,
                        month: month,
                        inYear: _inYear,
                        onTapDay: onTapDay,
                        selected: selected,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    Widget swatch(Color color, String label, {bool dot = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: dot ? 8 : 14,
          height: dot ? 8 : 14,
          decoration: BoxDecoration(
            color: color,
            shape: dot ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: dot ? null : BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        swatch(scheme.secondaryContainer, 'Sabbath'),
        swatch(scheme.tertiaryContainer, 'High Sabbath'),
        swatch(scheme.tertiary, 'Event', dot: true),
        swatch(scheme.primary, 'Span'),
      ],
    );
  }
}

class _Month extends StatelessWidget {
  const _Month({
    required this.timeline,
    required this.entries,
    required this.year,
    required this.month,
    required this.inYear,
    required this.onTapDay,
    required this.selected,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final double year;
  final int month;
  final bool Function(TimelineTime time) inYear;
  final ValueChanged<TimelineTime>? onTapDay;
  final TimelineTime? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = timeline.daysInMonth(year, month);
    final first = timeline.weekdayOf(TimelineTime(year, month: month, day: 1));
    // Events dated to the month alone are listed under its name.
    final monthOnly = [
      for (final entry in entries)
        if (!entry.isSpan &&
            entry.start.month == month &&
            entry.start.day == null &&
            inYear(entry.start))
          entry,
    ];
    final spans = [
      for (final entry in entries)
        if (entry.isSpan)
          (entry: entry, days: timelineEntryDays(timeline, entry)),
    ];
    final cells = <Widget>[
      for (var i = 1; i < first; i++) const SizedBox.shrink(),
      for (var day = 1; day <= days; day++)
        _day(context, TimelineTime(year, month: month, day: day), spans),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              timeline.monthChoice(year, month),
              key: ValueKey('calendar-month-$month'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            for (final entry in monthOnly)
              Text(
                entry.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.tertiary,
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      color: weekday == 7 ? scheme.secondaryContainer : null,
                      child: Text(
                        weekday == 7 ? 'Sab' : '$weekday',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: weekday == 7 ? FontWeight.bold : null,
                          color: weekday == 7
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            for (var row = 0; row * 7 < cells.length; row++)
              Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: row * 7 + col < cells.length
                          ? cells[row * 7 + col]
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _day(
    BuildContext context,
    TimelineTime day,
    List<({StudyTimelineEntry entry, ({double first, double last}) days})>
    spans,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final position = timeline.positionOf(day);
    final events = [
      for (final entry in entries)
        if (!entry.isSpan &&
            entry.start.month == day.month &&
            entry.start.day == day.day &&
            inYear(entry.start))
          entry,
    ];
    final over = [
      for (final span in spans)
        if (position >= span.days.first - 1e-9 &&
            position <= span.days.last + 1e-9)
          span.entry,
    ];
    final high = timeline.isHighSabbath(day);
    final sabbath = timeline.weekdayOf(day) == 7;
    final isSelected =
        selected != null &&
        selected!.month == day.month &&
        selected!.day == day.day &&
        inYear(selected!);
    final titles = [...events, ...over].map((e) => e.title).toList();
    final cell = InkWell(
      key: ValueKey('calendar-day-${day.month}-${day.day}'),
      onTap: onTapDay == null ? null : () => onTapDay!(day),
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: high
              ? scheme.tertiaryContainer
              : sabbath
              ? scheme.secondaryContainer
              : null,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: scheme.primary, width: 2)
              : null,
        ),
        child: Stack(
          children: [
            Align(
              alignment: const Alignment(0, -0.6),
              child: Text(
                '${day.day}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: sabbath || high ? FontWeight.bold : null,
                  color: high
                      ? scheme.onTertiaryContainer
                      : sabbath
                      ? scheme.onSecondaryContainer
                      : null,
                ),
              ),
            ),
            if (events.isNotEmpty)
              Align(
                alignment: const Alignment(0, 0.55),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final _ in events.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: scheme.tertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            if (over.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 2,
                child: Container(
                  height: 3,
                  color: scheme.primary.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
    return titles.isEmpty
        ? cell
        : Tooltip(message: titles.join('\n'), child: cell);
  }
}
