import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../study_workspace.dart';
import 'timeline_calendar.dart';
import 'timeline_chart.dart';

/// Where an entry stands on the year's wheel (see [TimelineWheel]): the
/// stretch of the year it covers, [from] and [to] as fractions of the year
/// from 1 Nisan, clockwise from the top; and where its mark stands, as a
/// fraction of the wheel's radius ([radius]: an event's dot, a span's arc).
typedef TimelineWheelMark = ({
  StudyTimelineEntry entry,
  double from,
  double to,
  double radius,
});

/// An entry's name placed on the wheel: its box, [rect], and the point by
/// it, [at], that a line runs to from its mark.
typedef TimelineWheelLabel = ({StudyTimelineEntry entry, Rect rect, Offset at});

/// How close round the wheel events stand to have their dots stacked
/// inward rather than drawn over one another, how far inward each, and how
/// many deep at most; and how far apart spans must stand to share a ring
/// of arcs.
const _stackGap = 0.012;
const _stackStep = 0.05;
const _stackDepth = 3;
const _spanGap = 0.008;

/// The wheel's rings, as fractions of its radius: the months outermost,
/// then the seasons, then the events' dots, stacked inward where they
/// stand close, then the spans' arcs; the names of both stand in the room
/// within the seasons, clear of them.
const _monthsOuter = 0.99;
const _monthsInner = 0.88;
const _rainRadius = 0.845;
const _harvestRadius = 0.80;
const _eventRadius = 0.75;
const _spanBelowEvents = 0.065;
const _spanStep = 0.045;
const _spanInner = 0.3;
const _labelReach = 0.775;

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
/// Events standing close have their dots stacked inward, and spans are
/// packed into as few rings of arcs as fit, within the dots.
List<TimelineWheelMark> timelineWheelMarks(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
  double year,
) {
  final stretch = timelineYearStretch(timeline, year);
  final length = stretch.end - stretch.start;
  double fraction(double position) =>
      ((position - stretch.start) / length).clamp(0.0, 1.0);
  final events = <TimelineWheelMark>[];
  final spans = <(StudyTimelineEntry, double, double, int)>[];
  final spanEnds = <double>[];
  var lastEvent = double.negativeInfinity;
  var stack = 0;
  var deepest = 0;
  for (final entry in List.of(entries)..sort(compareTimelineEntries)) {
    if (entry.start.month == null) continue;
    final reach = timelineEntryReach(timeline, entry);
    if (reach.end < stretch.start || reach.start >= stretch.end) continue;
    final from = fraction(reach.start);
    final to = fraction(reach.end);
    if (!entry.isSpan) {
      stack = from - lastEvent < _stackGap
          ? math.min(stack + 1, _stackDepth)
          : 0;
      lastEvent = from;
      deepest = math.max(deepest, stack);
      events.add((
        entry: entry,
        from: from,
        to: from,
        radius: _eventRadius - stack * _stackStep,
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
    spans.add((entry, from, math.max(to, from + 0.002), lane));
  }
  // The spans' rings start within the deepest stack of dots.
  final spanOuter = _eventRadius - deepest * _stackStep - _spanBelowEvents;
  return [
    ...events,
    for (final (entry, from, to, lane) in spans)
      (
        entry: entry,
        from: from,
        to: to,
        radius: math.max(_spanInner, spanOuter - lane * _spanStep),
      ),
  ]..sort((a, b) => compareTimelineEntries(a.entry, b.entry));
}

/// The point at [fraction] of the year round a wheel centred on [centre],
/// [radius] out: clockwise from the top, where 1 Nisan stands.
Offset timelineWheelPoint(Offset centre, double radius, double fraction) {
  final angle = -math.pi / 2 + 2 * math.pi * fraction;
  return centre + Offset(math.cos(angle), math.sin(angle)) * radius;
}

/// One year of a timeline as a wheel, its months round the rim from Nisan
/// at the top, the Sabbaths ticked inside them, and, as the timeline
/// shows them, the seasons of the land; its events as dots and its spans
/// as arcs, each named within where there is room, a line out to its
/// mark. The cycle of the feasts shows whole: the spring feasts facing the
/// autumn ones across it. Tapping an entry, or its name, calls
/// [onTapEntry].
class TimelineWheel extends StatelessWidget {
  const TimelineWheel({
    super.key,
    required this.timeline,
    required this.entries,
    required this.year,
    this.selectedId,
    this.onTapEntry,
    this.faded = const {},
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;

  /// The year shown, as written; 0 on one year's calendar.
  final double year;
  final String? selectedId;
  final ValueChanged<StudyTimelineEntry>? onTapEntry;

  /// The entries drawn faded: those of the timelines it is built on.
  final Set<String> faded;

  /// The entry at [point] on a wheel of [size], if any: one of [labels],
  /// an event's dot, or a span's arc.
  static StudyTimelineEntry? entryAt(
    List<TimelineWheelMark> marks,
    Size size,
    Offset point, {
    List<TimelineWheelLabel> labels = const [],
  }) {
    for (final label in labels) {
      if (label.rect.inflate(2).contains(point)) return label.entry;
    }
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
        final layout = TimelineWheelLayout(
          timeline: timeline,
          year: year,
          marks: marks,
          size: size,
          selectedId: selectedId,
          faded: faded,
          theme: theme,
        );
        return Center(
          child: GestureDetector(
            key: const ValueKey('timeline-wheel'),
            onTapUp: (details) {
              final point = details.localPosition;
              final entry = entryAt(marks, size, point, labels: layout.labels);
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
            child: CustomPaint(size: size, painter: _WheelPainter(layout)),
          ),
        );
      },
    );
  }
}

/// A wheel laid out at its size: its entries' colours, and their names
/// placed where they fit.
class TimelineWheelLayout {
  TimelineWheelLayout({
    required this.timeline,
    required this.year,
    required this.marks,
    required this.size,
    required this.selectedId,
    required this.faded,
    required this.theme,
  }) {
    _place();
  }

  final StudyTimeline timeline;
  final double year;
  final List<TimelineWheelMark> marks;
  final Size size;
  final String? selectedId;
  final Set<String> faded;
  final ThemeData theme;

  ColorScheme get scheme => theme.colorScheme;
  Offset get centre => size.center(Offset.zero);
  double get r => size.shortestSide / 2;

  /// The year, or the calendar's title, in the middle.
  late final TextPainter title = TextPainter(
    text: TextSpan(
      text: timeline.isAnnual ? timeline.title : timeline.formatValue(year),
      style: theme.textTheme.titleSmall,
    ),
    maxLines: 1,
    ellipsis: '…',
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(0, r * 0.5));

  Rect get titleRect =>
      Rect.fromCenter(center: centre, width: title.width, height: title.height);

  /// The names placed, with how each is drawn.
  final labels = <TimelineWheelLabel>[];
  final painters = <TextPainter>[];

  Color colorOf(StudyTimelineEntry entry) => timelineEntryColor(
    timeline,
    entry,
    theme.brightness,
    entry.isSpan ? scheme.primary : scheme.tertiary,
  ).withValues(alpha: faded.contains(entry.id) ? 0.45 : 1);

  /// The point of [mark] a line runs from to its name: an event's dot, a
  /// span's start.
  Offset markPoint(TimelineWheelMark mark) =>
      timelineWheelPoint(centre, mark.radius * r, mark.from);

  /// Places each entry's name in the room within the seasons, clear of
  /// the dots and arcs, of the names placed before it and of the title,
  /// as near its mark as it may stand without its line crossing them: the
  /// one chosen first, then the rest by rank (see below). A name stands to
  /// the side of its point away from its mark. One with no room is left
  /// out; its mark may still be tapped.
  void _place() {
    if (size.isEmpty) return;
    final reach = _labelReach * r;
    final blocked = <Rect>[if (title.width > 0) titleRect.inflate(4)];
    for (final mark in marks) {
      if (!mark.entry.isSpan) {
        blocked.add(Rect.fromCircle(center: markPoint(mark), radius: 9));
        continue;
      }
      final radius = mark.radius * r;
      final sweep = mark.to - mark.from;
      final steps = math.max(1, (2 * math.pi * radius * sweep / 4).ceil());
      for (var i = 0; i <= steps; i++) {
        blocked.add(
          Rect.fromCircle(
            center: timelineWheelPoint(
              centre,
              radius,
              mark.from + sweep * i / steps,
            ),
            radius: 6,
          ),
        );
      }
    }
    final names = <Rect>[];
    final lines = <(Offset, Offset)>[];
    bool inside(Rect rect) => [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ].every((p) => (p - centre).distance <= reach);
    // The spans first, then the events, the high Sabbaths among them last,
    // each in the order of the year.
    int rank(TimelineWheelMark m) => m.entry.id == selectedId
        ? 0
        : m.entry.isSpan
        ? 1
        : m.entry.isHighSabbath
        ? 3
        : 2;
    final order = [
      for (var i = 0; i <= 3; i++) ...marks.where((m) => rank(m) == i),
    ];
    final small = theme.textTheme.labelSmall;
    final probe = TextPainter(
      text: TextSpan(text: 'M', style: small),
      textDirection: TextDirection.ltr,
    )..layout();
    // The points a name may stand by, on a grid over the room.
    final grid = probe.height * 0.6;
    final points = <Offset>[
      for (var y = -reach; y <= reach; y += grid)
        for (var x = -reach; x <= reach; x += grid)
          if (x * x + y * y <= reach * reach) centre + Offset(x, y),
    ];
    for (final mark in order) {
      final selected = mark.entry.id == selectedId;
      final painter = TextPainter(
        text: TextSpan(
          text: mark.entry.shortLabel,
          style: small?.copyWith(
            color: mark.entry.isSpan ? colorOf(mark.entry) : null,
            fontWeight: selected ? FontWeight.bold : null,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: math.max(0, reach * 0.8));
      final w = painter.width + 4;
      final h = painter.height;
      final from = markPoint(mark);
      final candidates = [for (final at in points) (at, (at - from).distance)]
        ..sort((a, b) => a.$2.compareTo(b.$2));
      Rect? best;
      Offset? bestAt;
      var bestScore = double.infinity;
      for (final (at, distance) in candidates) {
        if (distance >= bestScore) break;
        final rect = Rect.fromLTWH(
          from.dx <= at.dx ? at.dx : at.dx - w,
          at.dy - h / 2,
          w,
          h,
        );
        if (!inside(rect) ||
            names.any(rect.overlaps) ||
            blocked.any(rect.overlaps)) {
          continue;
        }
        // A line crossing a name, or another line, costs as much as a
        // longer one.
        var score = distance;
        for (final name in names) {
          if (_crosses(from, at, name)) score += 3 * h;
        }
        for (final (a, b) in lines) {
          if (_crosses(a, b, rect)) score += 3 * h;
          if (_meet(a, b, from, at)) score += h;
        }
        if (score < bestScore) {
          best = rect;
          bestAt = at;
          bestScore = score;
        }
      }
      if (best == null || bestAt == null) continue;
      names.add(best.inflate(1));
      lines.add((from, bestAt));
      labels.add((entry: mark.entry, rect: best, at: bestAt));
      painters.add(painter);
    }
  }
}

/// Whether the line from [a] to [b] passes through [rect].
bool _crosses(Offset a, Offset b, Rect rect) {
  var t0 = 0.0;
  var t1 = 1.0;
  final d = b - a;
  for (final (p, q) in [
    (-d.dx, a.dx - rect.left),
    (d.dx, rect.right - a.dx),
    (-d.dy, a.dy - rect.top),
    (d.dy, rect.bottom - a.dy),
  ]) {
    if (p == 0) {
      if (q < 0) return false;
      continue;
    }
    final t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      t0 = math.max(t0, t);
    } else {
      if (t < t0) return false;
      t1 = math.min(t1, t);
    }
  }
  return t0 < t1;
}

/// Whether the lines from [a] to [b] and from [c] to [d] cross.
bool _meet(Offset a, Offset b, Offset c, Offset d) {
  double side(Offset p, Offset q, Offset s) =>
      (q.dx - p.dx) * (s.dy - p.dy) - (q.dy - p.dy) * (s.dx - p.dx);
  return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0;
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.layout);

  final TimelineWheelLayout layout;

  StudyTimeline get timeline => layout.timeline;
  double get year => layout.year;
  ThemeData get theme => layout.theme;
  ColorScheme get scheme => layout.scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final centre = layout.centre;
    final r = layout.r;
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
      final mid = r * (_monthsInner + _monthsOuter) / 2;
      _alongRim(
        canvas,
        timeline.monthName(year, month),
        centre,
        mid,
        (from + to) / 2,
        small?.copyWith(fontWeight: FontWeight.w600),
        maxWidth: 2 * math.pi * mid * (to - from) * 0.92,
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
    // A line from each mark to its name, beneath them all.
    final marksById = {for (final m in layout.marks) m.entry.id: m};
    for (final label in layout.labels) {
      final mark = marksById[label.entry.id]!;
      canvas.drawLine(
        layout.markPoint(mark),
        label.at,
        Paint()
          ..color =
              (mark.entry.isSpan ? layout.colorOf(mark.entry) : scheme.outline)
                  .withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    // The spans as arcs.
    for (final mark in layout.marks.where((m) => m.entry.isSpan)) {
      final selected = mark.entry.id == layout.selectedId;
      final color = layout.colorOf(mark.entry);
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: r * mark.radius),
        angle(mark.from),
        angle(mark.to) - angle(mark.from),
        false,
        Paint()
          ..color = color.withValues(alpha: color.a * (selected ? 1 : 0.6))
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = selected ? 9 : 7,
      );
    }
    // The events as dots.
    for (final mark in layout.marks.where((m) => !m.entry.isSpan)) {
      final selected = mark.entry.id == layout.selectedId;
      final color = layout.colorOf(mark.entry);
      final dot = layout.markPoint(mark);
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
    }
    // The names, each on a ground of its own where a line passes beneath.
    final ground = Paint()..color = scheme.surface.withValues(alpha: 0.85);
    for (final (i, label) in layout.labels.indexed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(label.rect, const Radius.circular(3)),
        ground,
      );
      final after = label.at.dx <= label.rect.left + 0.5;
      layout.painters[i].paint(
        canvas,
        label.rect.topLeft + Offset(after ? 4 : 0, 0),
      );
    }
    // The year in the middle.
    layout.title.paint(canvas, layout.titleRect.topLeft);
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

  /// [text] centred on the point [radius] out at [fraction], cut to
  /// [maxWidth], written along the rim: upright on the wheel's top half,
  /// and turned to read upright on its bottom half too.
  void _alongRim(
    Canvas canvas,
    String text,
    Offset centre,
    double radius,
    double fraction,
    TextStyle? style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: math.max(0, maxWidth));
    final angle = -math.pi / 2 + 2 * math.pi * fraction;
    final bottom = math.sin(angle) > 0;
    canvas
      ..save()
      ..translate(
        centre.dx + math.cos(angle) * radius,
        centre.dy + math.sin(angle) * radius,
      )
      ..rotate(bottom ? angle - math.pi / 2 : angle + math.pi / 2);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.layout.timeline != timeline ||
      old.layout.year != year ||
      old.layout.marks != layout.marks ||
      old.layout.size != layout.size ||
      old.layout.selectedId != layout.selectedId ||
      old.layout.faded != layout.faded ||
      old.layout.theme != theme;
}
