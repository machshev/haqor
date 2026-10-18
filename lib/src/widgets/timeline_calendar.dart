import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../study_workspace.dart';
import 'timeline_chart.dart';

/// The colours a timeline's categories may take (see
/// [StudyTimeline.categoryColors]), by name, each for light and for dark.
const timelineCategoryPalette = [
  ('Blue', Color(0xFF1E6FC2), Color(0xFF64B5F6)),
  ('Green', Color(0xFF2E7D32), Color(0xFF81C784)),
  ('Red', Color(0xFFC62828), Color(0xFFE57373)),
  ('Purple', Color(0xFF7B1FA2), Color(0xFFBA68C8)),
  ('Orange', Color(0xFFD86A00), Color(0xFFFFB74D)),
  ('Teal', Color(0xFF00796B), Color(0xFF4DB6AC)),
  ('Brown', Color(0xFF6D4C41), Color(0xFFBCAAA4)),
  ('Pink', Color(0xFFC2185B), Color(0xFFF06292)),
];

/// The colour of the category [index] (see [timelineCategoryPalette]).
Color timelineCategoryColor(int index, Brightness brightness) {
  final (_, light, dark) =
      timelineCategoryPalette[index % timelineCategoryPalette.length];
  return brightness == Brightness.dark ? dark : light;
}

/// The colour [entry] is shown in on [timeline]: its category's, else
/// [fallback].
Color timelineEntryColor(
  StudyTimeline timeline,
  StudyTimelineEntry entry,
  Brightness brightness,
  Color fallback,
) {
  final index = timeline.colorOf(entry);
  return index == null ? fallback : timelineCategoryColor(index, brightness);
}

/// The colour a season of the land is shown in: blue for rain, gold for
/// the farming year.
Color timelineSeasonColor(TimelineSeasonKind kind, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (kind) {
    TimelineSeasonKind.rain =>
      dark ? const Color(0xFF5B9BD5) : const Color(0xFF3A78B5),
    TimelineSeasonKind.harvest =>
      dark ? const Color(0xFFD9A93F) : const Color(0xFFB07D12),
  };
}

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
    this.faded = const {},
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;

  /// The year shown, as written; 0 on one year's calendar.
  final double year;
  final ValueChanged<TimelineTime>? onTapDay;
  final TimelineTime? selected;

  /// The entries drawn faded: those of the timelines it is built on.
  final Set<String> faded;

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
              _Legend(scheme: scheme, counted: entries.any((e) => e.isCounted)),
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
                        faded: faded,
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
  const _Legend({required this.scheme, this.counted = false});

  final ColorScheme scheme;

  /// Whether a count runs in the year, its days numbered.
  final bool counted;

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
        swatch(scheme.tertiaryContainer, 'Shabbaton (a ceasing)'),
        swatch(scheme.tertiary, 'Event', dot: true),
        swatch(scheme.primary, 'Span'),
        if (counted)
          Text(
            '7  Day of a count',
            style: style?.copyWith(color: scheme.primary),
          ),
        Text('Days run from sunset to sunset.', style: style),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle_outlined,
              size: 8,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text('New moon', style: style),
            const SizedBox(width: 8),
            Icon(Icons.circle, size: 8, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('Full moon', style: style),
          ],
        ),
      ],
    );
  }
}

/// A span's bar across its days in one week of the calendar, columns
/// [from] to [to], rounded where it [starts] and [ends], and named; and
/// beneath it the events pinned to it, by column, each a dot in its colour
/// with its title. Tapping one taps its day.
class _SpanLane extends StatelessWidget {
  const _SpanLane({
    super.key,
    required this.timeline,
    required this.span,
    required this.from,
    required this.to,
    required this.starts,
    required this.ends,
    required this.pinned,
    required this.dayAt,
    required this.onTapDay,
  });

  final StudyTimeline timeline;
  final StudyTimelineEntry span;
  final int from, to;
  final bool starts, ends;
  final Map<int, List<StudyTimelineEntry>> pinned;
  final TimelineTime? Function(int col) dayAt;
  final ValueChanged<TimelineTime>? onTapDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = timelineEntryColor(
      timeline,
      span,
      theme.brightness,
      scheme.primary,
    );
    final small = theme.textTheme.labelSmall?.copyWith(fontSize: 9);
    const radius = Radius.circular(4);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / 7;
        return SizedBox(
          height: pinned.isEmpty ? 17 : 33,
          child: Stack(
            children: [
              Positioned(
                left: from * width + 1,
                width: (to - from + 1) * width - 2,
                top: 2,
                height: 14,
                child: Tooltip(
                  message:
                      '${span.title} · ${timelineEntryTime(timeline, span)}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: AlignmentDirectional.centerStart,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.22),
                      border: Border.all(color: color.withValues(alpha: 0.7)),
                      borderRadius: BorderRadius.horizontal(
                        left: starts ? radius : Radius.zero,
                        right: ends ? radius : Radius.zero,
                      ),
                    ),
                    child: Text(
                      span.shortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small?.copyWith(color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
              for (final MapEntry(key: col, value: events) in pinned.entries)
                Positioned(
                  left: col * width,
                  width: width,
                  top: 18,
                  height: 14,
                  child: Tooltip(
                    message: [
                      for (final e in events)
                        '${e.title} · ${timelinePinLabel(timeline, e, [span, e]) ?? timelineEntryTime(timeline, e)}',
                    ].join('\n'),
                    child: InkWell(
                      key: ValueKey(
                        'calendar-pinned-${span.id}-${events.first.id}',
                      ),
                      onTap: onTapDay == null || dayAt(col) == null
                          ? null
                          : () => onTapDay!(dayAt(col)!),
                      child: Row(
                        children: [
                          const SizedBox(width: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: timelineEntryColor(
                                timeline,
                                events.first,
                                theme.brightness,
                                scheme.tertiary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              events.map((e) => e.title).join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: small,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
    required this.faded,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final double year;
  final int month;
  final bool Function(TimelineTime time) inYear;
  final ValueChanged<TimelineTime>? onTapDay;
  final TimelineTime? selected;

  /// The entries drawn faded: those of the timelines it is built on.
  final Set<String> faded;

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
            if (timeline.showSeasons) _seasons(context),
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
            for (var row = 0; row * 7 < cells.length; row++) ...[
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
              ..._spanLanes(context, row, first, days, spans),
            ],
          ],
        ),
      ),
    );
  }

  /// Beneath the week [row] of the month, which begins on the weekday
  /// [first] and has [days] days, a bar for each span over its days, named,
  /// and beneath the bar the events pinned to the span (see [TimelinePin])
  /// on their days: the days of a feast with what falls on them.
  List<Widget> _spanLanes(
    BuildContext context,
    int row,
    int first,
    int days,
    List<({StudyTimelineEntry entry, ({double first, double last}) days})>
    spans,
  ) {
    TimelineTime? dayAt(int col) {
      final day = row * 7 + col - (first - 1) + 1;
      return day >= 1 && day <= days
          ? TimelineTime(year, month: month, day: day)
          : null;
    }

    bool covers(({double first, double last}) span, TimelineTime day) {
      final at = timeline.positionOf(day);
      return at >= span.first - 1e-9 && at <= span.last + 1e-9;
    }

    // Whether the span stops before the day [step] days on from [day].
    bool beyond(
      ({double first, double last}) span,
      TimelineTime day,
      int step,
    ) {
      final next = timeline.addDays(day, step);
      return next == null || !covers(span, next);
    }

    final lanes = <Widget>[];
    for (final span in List.of(
      spans,
    )..sort((a, b) => compareTimelineEntries(a.entry, b.entry))) {
      final cols = [
        for (var col = 0; col < 7; col++)
          if (dayAt(col) case final day? when covers(span.days, day)) col,
      ];
      if (cols.isEmpty) continue;
      final firstDay = dayAt(cols.first)!;
      final lastDay = dayAt(cols.last)!;
      // Its events on these days, gathered by day.
      final pinned = <int, List<StudyTimelineEntry>>{};
      for (final entry in entries) {
        if (entry.isSpan ||
            entry.pin?.anchorId != span.entry.id ||
            !inYear(entry.start) ||
            entry.start.month != month) {
          continue;
        }
        for (final col in cols) {
          if (dayAt(col)!.day == entry.start.day) {
            (pinned[col] ??= []).add(entry);
          }
        }
      }
      lanes.add(
        Opacity(
          opacity: faded.contains(span.entry.id) ? 0.45 : 1,
          child: _SpanLane(
            key: ValueKey('calendar-span-${span.entry.id}-$month-$row'),
            timeline: timeline,
            span: span.entry,
            from: cols.first,
            to: cols.last,
            starts: beyond(span.days, firstDay, -1),
            ends: beyond(span.days, lastDay, 1),
            pinned: pinned,
            dayAt: dayAt,
            onTapDay: onTapDay,
          ),
        ),
      );
    }
    return lanes;
  }

  /// The seasons of the land in this month, each named in its colour, its
  /// verses in its tooltip.
  Widget _seasons(BuildContext context) {
    final theme = Theme.of(context);
    final from = timeline.positionOf(TimelineTime(year, month: month, day: 1));
    final to = timeline.endOf(
      TimelineTime(year, month: month, day: timeline.daysInMonth(year, month)),
    );
    final seasons = <TimelineSeason>[];
    for (final season in timelineSeasons) {
      final at = season.inYear(timeline, year);
      if (at.start < to &&
          at.end > from &&
          !seasons.any((s) => s.name == season.name)) {
        seasons.add(season);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 8,
        children: [
          for (final season in seasons)
            Tooltip(
              message: '${season.name} · ${season.references}',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    season.kind == TimelineSeasonKind.rain
                        ? Icons.water_drop_outlined
                        : Icons.grass,
                    size: 12,
                    color: timelineSeasonColor(season.kind, theme.brightness),
                  ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      season.name,
                      key: ValueKey('calendar-season-$month-${season.name}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: timelineSeasonColor(
                          season.kind,
                          theme.brightness,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
    // A shabbaton shows in its day's colour, not as a dot, and an event
    // pinned to a span over its day beneath that span's bar.
    final dots = [
      for (final entry in events)
        if (!entry.isHighSabbath &&
            !over.any((span) => span.id == entry.pin?.anchorId))
          entry,
    ];
    final high = events.any((entry) => entry.isHighSabbath);
    // Its number in a count running over it.
    final count = [
      for (final span in over) ?timeline.countIn(span, day),
    ].firstOrNull;
    final sabbath = timeline.weekdayOf(day) == 7;
    final isSelected =
        selected != null &&
        selected!.month == day.month &&
        selected!.day == day.day &&
        inYear(selected!);
    final moon = timelineMoonOn(day.day!);
    final titles = [
      ?moon,
      for (final e in events)
        e.dayPart == null ? e.title : '${e.title}, ${e.dayPart!.phrase}',
      // A span by name, with its note for the day.
      for (final span in over)
        switch (span.dayNotes[timeline.dayIn(span, day)]) {
          final note? => '${span.title}: $note',
          null => span.title,
        },
    ];
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
            if (moon != null)
              Positioned(
                top: 3,
                right: 3,
                child: Icon(
                  moon == 'Full moon' ? Icons.circle : Icons.circle_outlined,
                  key: ValueKey('calendar-moon-${day.month}-${day.day}'),
                  size: 7,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            if (count != null)
              Positioned(
                top: 1,
                left: 3,
                child: Text(
                  '${count.day}',
                  key: ValueKey('calendar-count-${day.month}-${day.day}'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: scheme.primary,
                    fontWeight: count.dayOfWeek == 1 ? FontWeight.bold : null,
                  ),
                ),
              ),
            if (dots.isNotEmpty)
              Align(
                alignment: const Alignment(0, 0.55),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final dot in dots.take(3))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color:
                              timelineEntryColor(
                                timeline,
                                dot,
                                theme.brightness,
                                scheme.tertiary,
                              ).withValues(
                                alpha: faded.contains(dot.id) ? 0.45 : 1,
                              ),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
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
