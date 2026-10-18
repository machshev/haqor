import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../study_workspace.dart';
import 'timeline_calendar.dart';
import 'timeline_chart.dart';

/// Where an entry stands on the year's wheel (see [TimelineWheel]): the
/// stretch of the year it covers, [from] and [to] as fractions of the year
/// from 1 Nisan, clockwise from the top; and, as fractions of the wheel's
/// radius, where its mark stands ([radius]: an event's dot, a span's arc)
/// and where an event's label does ([labelRadius]).
typedef TimelineWheelMark = ({
  StudyTimelineEntry entry,
  double from,
  double to,
  double radius,
  double labelRadius,
});

/// How far round the wheel events must stand apart to share a ring of
/// labels, and spans to share a ring of arcs.
const _eventGap = 0.03;
const _spanGap = 0.008;

/// The wheel's rings, as fractions of its radius: the months outermost,
/// then the seasons, then the events' dots, their labels in up to three
/// rings within, and the spans' arcs within those.
const _monthsOuter = 0.99;
const _monthsInner = 0.88;
const _rainRadius = 0.845;
const _harvestRadius = 0.80;
const _eventRadius = 0.745;
const _labelRadii = [0.69, 0.62, 0.55];
const _spanOuter = 0.47;
const _spanStep = 0.06;
const _spanInner = 0.2;

/// The stretch of the axis the year [year] of [timeline] covers.
({double start, double end}) timelineYearStretch(
  StudyTimeline timeline,
  double year,
) {
  final months = timeline.monthsIn(year);
  return (
    start: timeline.positionOf(TimelineTime(year, month: 1, day: 1)),
    end: timeline.endOf(
      TimelineTime(
        year,
        month: months,
        day: timeline.daysInMonth(year, months),
      ),
    ),
  );
}

/// Where [entries] stand on the wheel of the year [year] of [timeline]:
/// those dated within it to the month at least, a span cut to the year.
/// Events are staggered across the rings of labels where they stand close,
/// and spans packed into as few rings of arcs as fit.
List<TimelineWheelMark> timelineWheelMarks(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
  double year,
) {
  final stretch = timelineYearStretch(timeline, year);
  final length = stretch.end - stretch.start;
  double fraction(double position) =>
      ((position - stretch.start) / length).clamp(0.0, 1.0);
  final marks = <TimelineWheelMark>[];
  final labelEnds = List.filled(_labelRadii.length, double.negativeInfinity);
  final spanEnds = <double>[];
  for (final entry in List.of(entries)..sort(compareTimelineEntries)) {
    if (entry.start.month == null) continue;
    final reach = timelineEntryReach(timeline, entry);
    if (reach.end < stretch.start || reach.start >= stretch.end) continue;
    final from = fraction(reach.start);
    final to = fraction(reach.end);
    if (!entry.isSpan) {
      var ring = labelEnds.indexWhere((end) => end + _eventGap <= from);
      if (ring < 0) {
        // Every ring is crowded here: the one free longest ago.
        ring = labelEnds.indexOf(labelEnds.reduce(math.min));
      }
      labelEnds[ring] = from;
      marks.add((
        entry: entry,
        from: from,
        to: from,
        radius: _eventRadius,
        labelRadius: _labelRadii[ring],
      ));
      continue;
    }
    var lane = spanEnds.indexWhere((end) => end + _spanGap <= from);
    if (lane < 0) {
      lane = spanEnds.length;
      spanEnds.add(to);
    } else {
      spanEnds[lane] = to;
    }
    final radius = math.max(_spanInner, _spanOuter - lane * _spanStep);
    marks.add((
      entry: entry,
      from: from,
      to: math.max(to, from + 0.002),
      radius: radius,
      labelRadius: radius,
    ));
  }
  return marks;
}

/// The point at [fraction] of the year round a wheel centred on [centre],
/// [radius] out: clockwise from the top, where 1 Nisan stands.
Offset timelineWheelPoint(Offset centre, double radius, double fraction) {
  final angle = -math.pi / 2 + 2 * math.pi * fraction;
  return centre + Offset(math.cos(angle), math.sin(angle)) * radius;
}

/// One year of a timeline as a wheel, its months round the rim from Nisan
/// at the top, the Sabbaths ticked inside them, and, as the timeline
/// shows them, the seasons of the land; its events as dots, named within,
/// and its spans as arcs. The cycle of the feasts shows whole: the spring
/// feasts facing the autumn ones across it. Tapping an entry calls
/// [onTapEntry].
class TimelineWheel extends StatelessWidget {
  const TimelineWheel({
    super.key,
    required this.timeline,
    required this.entries,
    required this.year,
    this.selectedId,
    this.onTapEntry,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;

  /// The year shown, as written; 0 on one year's calendar.
  final double year;
  final String? selectedId;
  final ValueChanged<StudyTimelineEntry>? onTapEntry;

  /// The entry at [point] on a wheel of [size], if any: an event's dot, or
  /// a span's arc.
  static StudyTimelineEntry? entryAt(
    List<TimelineWheelMark> marks,
    Size size,
    Offset point,
  ) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final offset = point - centre;
    final distance = offset.distance;
    final fraction =
        ((math.atan2(offset.dy, offset.dx) + math.pi / 2) / (2 * math.pi)) %
        1.0;
    TimelineWheelMark? best;
    var bestDistance = double.infinity;
    for (final mark in marks) {
      if (!mark.entry.isSpan) {
        final at = timelineWheelPoint(centre, mark.radius * radius, mark.from);
        final d = (at - point).distance;
        if (d < 14 && d < bestDistance) {
          best = mark;
          bestDistance = d;
        }
      } else if ((distance - mark.radius * radius).abs() < 8 &&
          fraction >= mark.from - 0.003 &&
          fraction <= mark.to + 0.003) {
        final d = (distance - mark.radius * radius).abs();
        if (d < bestDistance) {
          best = mark;
          bestDistance = d;
        }
      }
    }
    return best?.entry;
  }

  /// The season of the land at [point] on a wheel of [size] showing the
  /// year [year] of [timeline], if it shows them and one is there.
  static TimelineSeason? seasonAt(
    StudyTimeline timeline,
    double year,
    Size size,
    Offset point,
  ) {
    if (!timeline.showSeasons) return null;
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final offset = point - centre;
    final stretch = timelineYearStretch(timeline, year);
    final fraction =
        ((math.atan2(offset.dy, offset.dx) + math.pi / 2) / (2 * math.pi)) %
        1.0;
    final position = stretch.start + fraction * (stretch.end - stretch.start);
    for (final season in timelineSeasons) {
      final ring = season.kind == TimelineSeasonKind.rain
          ? _rainRadius
          : _harvestRadius;
      final at = season.inYear(timeline, year);
      if ((offset.distance - ring * radius).abs() <= 8 &&
          position >= at.start &&
          position <= at.end) {
        return season;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final marks = timelineWheelMarks(timeline, entries, year);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
          0.0,
          math.min(constraints.maxWidth, constraints.maxHeight) - 16,
        );
        final size = Size.square(side);
        return Center(
          child: GestureDetector(
            key: const ValueKey('timeline-wheel'),
            onTapUp: (details) {
              final point = details.localPosition;
              final entry = entryAt(marks, size, point);
              if (entry != null) {
                onTapEntry?.call(entry);
                return;
              }
              // A season tapped says what it is, and where it is written.
              final season = seasonAt(timeline, year, size, point);
              if (season == null) return;
              ScaffoldMessenger.maybeOf(context)
                ?..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text('${season.name} · ${season.references}'),
                  ),
                );
            },
            child: CustomPaint(
              size: size,
              painter: _WheelPainter(
                timeline: timeline,
                year: year,
                marks: marks,
                selectedId: selectedId,
                theme: theme,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.timeline,
    required this.year,
    required this.marks,
    required this.selectedId,
    required this.theme,
  });

  final StudyTimeline timeline;
  final double year;
  final List<TimelineWheelMark> marks;
  final String? selectedId;
  final ThemeData theme;

  ColorScheme get scheme => theme.colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centre = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final stretch = timelineYearStretch(timeline, year);
    final length = stretch.end - stretch.start;
    double fraction(double position) => (position - stretch.start) / length;
    double angle(double fraction) => -math.pi / 2 + 2 * math.pi * fraction;
    final small = theme.textTheme.labelSmall;

    // The months round the rim, named along it.
    final months = timeline.monthsIn(year);
    for (var month = 1; month <= months; month++) {
      final from = fraction(
        timeline.positionOf(TimelineTime(year, month: month, day: 1)),
      );
      final to = fraction(
        timeline.endOf(
          TimelineTime(
            year,
            month: month,
            day: timeline.daysInMonth(year, month),
          ),
        ),
      );
      _band(
        canvas,
        centre,
        r * _monthsInner,
        r * _monthsOuter,
        angle(from),
        angle(to) - angle(from),
        Paint()
          ..color = month.isOdd
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHigh,
      );
      _text(
        canvas,
        timeline.monthName(year, month),
        timelineWheelPoint(
          centre,
          r * (_monthsInner + _monthsOuter) / 2,
          (from + to) / 2,
        ),
        small?.copyWith(fontWeight: FontWeight.w600),
        maxWidth: 2 * math.pi * r * 0.9 * (to - from),
      );
    }
    // The Sabbaths, ticked just inside the months.
    final sabbath = Paint()
      ..color = scheme.secondary
      ..strokeWidth = 1.5;
    final days = timeline.daysInYear(year);
    for (var day = 0; day < days; day++) {
      final time = timeline.addDays(TimelineTime(year, month: 1, day: 1), day);
      if (time == null || timeline.weekdayOf(time) != 7) continue;
      final at = fraction(timeline.centreOf(time));
      canvas.drawLine(
        timelineWheelPoint(centre, r * (_monthsInner - 0.005), at),
        timelineWheelPoint(centre, r * (_monthsInner - 0.03), at),
        sabbath,
      );
    }
    // The seasons of the land, rain outside the farming year.
    // Each apart from the next, and shaded by turns.
    if (timeline.showSeasons) {
      for (final (i, season) in timelineSeasons.indexed) {
        final at = season.inYear(timeline, year);
        final radius = season.kind == TimelineSeasonKind.rain
            ? _rainRadius
            : _harvestRadius;
        final color = timelineSeasonColor(season.kind, theme.brightness);
        final from = angle(fraction(at.start)) + 0.012;
        final to = angle(fraction(at.end)) - 0.012;
        if (to <= from) continue;
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: r * radius),
          from,
          to - from,
          false,
          Paint()
            ..color = color.withValues(alpha: i.isEven ? 0.75 : 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.025,
        );
      }
    }
    // The spans as arcs, named at their start.
    for (final mark in marks.where((m) => m.entry.isSpan)) {
      final selected = mark.entry.id == selectedId;
      final color = timelineEntryColor(
        timeline,
        mark.entry,
        theme.brightness,
        scheme.primary,
      );
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r * mark.radius),
        angle(mark.from),
        angle(mark.to) - angle(mark.from),
        false,
        Paint()
          ..color = color.withValues(alpha: selected ? 1 : 0.6)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = selected ? 9 : 7,
      );
      _label(
        canvas,
        mark.entry.title,
        centre,
        r * (mark.radius - 0.035),
        mark.from,
        small?.copyWith(
          color: color,
          fontWeight: selected ? FontWeight.bold : null,
        ),
      );
    }
    // The events as dots, named within, a line out to each label.
    final leader = Paint()
      ..color = scheme.outline.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (final mark in marks.where((m) => !m.entry.isSpan)) {
      final selected = mark.entry.id == selectedId;
      final color = timelineEntryColor(
        timeline,
        mark.entry,
        theme.brightness,
        scheme.tertiary,
      );
      final dot = timelineWheelPoint(centre, r * mark.radius, mark.from);
      final label = timelineWheelPoint(centre, r * mark.labelRadius, mark.from);
      canvas.drawLine(dot, label, leader);
      if (mark.entry.isHighSabbath) {
        canvas.drawCircle(dot, 6, Paint()..color = scheme.tertiaryContainer);
        canvas.drawCircle(
          dot,
          6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      } else {
        canvas.drawCircle(dot, 5, Paint()..color = color);
      }
      if (selected) {
        canvas.drawCircle(
          dot,
          8,
          Paint()
            ..color = scheme.onSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
      _label(
        canvas,
        mark.entry.title,
        centre,
        r * mark.labelRadius,
        mark.from,
        small?.copyWith(fontWeight: selected ? FontWeight.bold : null),
      );
    }
    // The year in the middle.
    _text(
      canvas,
      timeline.isAnnual ? timeline.title : timeline.formatValue(year),
      centre,
      theme.textTheme.titleSmall,
      maxWidth: r * _spanInner * 2,
    );
  }

  /// A ring's stretch from [from] round [sweep], between radii [inner] and
  /// [outer].
  void _band(
    Canvas canvas,
    Offset centre,
    double inner,
    double outer,
    double from,
    double sweep,
    Paint paint,
  ) {
    final path = Path()
      ..arcTo(Rect.fromCircle(center: centre, radius: outer), from, sweep, true)
      ..arcTo(
        Rect.fromCircle(center: centre, radius: inner),
        from + sweep,
        -sweep,
        false,
      )
      ..close();
    canvas.drawPath(path, paint);
  }

  /// [text] centred on [at], cut to [maxWidth].
  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle? style, {
    double maxWidth = double.infinity,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, maxWidth));
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  /// [text] beside the point [radius] out at [fraction], running inward:
  /// ending at it on the wheel's right half, starting from it on its left.
  void _label(
    Canvas canvas,
    String text,
    Offset centre,
    double radius,
    double fraction,
    TextStyle? style,
  ) {
    final at = timelineWheelPoint(centre, radius, fraction);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(40, radius * 0.9));
    final right = at.dx >= centre.dx;
    painter.paint(
      canvas,
      Offset(
        right ? at.dx - painter.width - 4 : at.dx + 4,
        at.dy - painter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.timeline != timeline ||
      old.year != year ||
      old.marks != marks ||
      old.selectedId != selectedId ||
      old.theme != theme;
}
