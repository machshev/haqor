import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../study_workspace.dart';
import 'timeline_calendar.dart';
import 'timeline_chart.dart';

/// A time span divided into equal segments using the wheel's event layout.
class TimelineWheelCycle {
  const TimelineWheelCycle({
    required this.start,
    required this.length,
    required this.title,
    required this.segments,
    this.dayCount = 0,
    this.description,
  });
  final double start;
  final double length;
  final String title;
  final String? description;
  final List<String> segments;

  /// Days divided into evening and morning, including the symbolic days
  /// of the 7,000-year creation week.
  /// These are schematic halves, not calculated sunrise/sunset times.
  final int dayCount;

  List<({String label, double from, double to})> get dayParts => [
    for (var day = 0; day < dayCount; day++) ...[
      (label: 'Evening', from: day / dayCount, to: (day + 0.5) / dayCount),
      (
        label: 'Morning',
        from: (day + 0.5) / dayCount,
        to: (day + 1) / dayCount,
      ),
    ],
  ];
}

/// The wheel implied by a saved timeline's time span. Years retain the
/// calendar wheel, with its actual month lengths and leap months.
TimelineWheelCycle? timelineCycleOf(StudyTimeline timeline) {
  final extent = timeline.extent;
  if (extent == null || extent == TimelineExtent.year) return null;
  final labels = switch (extent) {
    TimelineExtent.day => [for (var h = 0; h < 24; h++) '$h'],
    TimelineExtent.week => [
      for (var d = 1; d <= 7; d++) d == 7 ? 'Day 7 · Sabbath' : 'Day $d',
    ],
    TimelineExtent.month => [
      for (var d = 1; d <= timeline.monthDays; d++) '$d',
    ],
    TimelineExtent.hayovel => [for (var y = 1; y <= 50; y++) '$y'],
    TimelineExtent.creationWeek => const [
      'Day 1 · Light',
      'Day 2 · Firmament',
      'Day 3 · Land and plants',
      'Day 4 · Lights',
      'Day 5 · Fish and birds',
      'Day 6 · Animals and man',
      'Day 7 · Rest',
    ],
    TimelineExtent.year => <String>[],
  };
  return TimelineWheelCycle(
    start: extent.start,
    length: timeline.extentLength!,
    title: extent == TimelineExtent.hayovel
        ? 'HaYovel'
        : extent == TimelineExtent.creationWeek
        ? '7,000 years'
        : extent.label,
    segments: labels,
    description: extent == TimelineExtent.creationWeek
        ? 'Creation week · 7,000 years · Evening → Morning within each 1,000-year day'
        : null,
    dayCount: extent == TimelineExtent.day
        ? 1
        : extent == TimelineExtent.week || extent == TimelineExtent.creationWeek
        ? 7
        : 0,
  );
}

/// A dated section's whole chronology, divided into at most about twelve
/// readable year intervals. A point occupies its year so the last event
/// never falls exactly on the excluded end of the wheel.
TimelineWheelCycle timelineChronologyCycle(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
) {
  final reaches = [
    for (final entry in entries)
      (
        start: timelineEntryReach(timeline, entry).start,
        end: entry.isSpan
            ? timelineEntryReach(timeline, entry).end
            : timeline.positionOf(entry.start).floorToDouble() + 1,
      ),
  ];
  final first = reaches.isEmpty
      ? 0.0
      : reaches.map((r) => r.start).reduce(math.min);
  final last = reaches.isEmpty
      ? 1.0
      : reaches.map((r) => r.end).reduce(math.max);
  final target = math.max(1.0, (last - first) / 10);
  final power = math.pow(10, (math.log(target) / math.ln10).floor()).toDouble();
  final step = [
    1,
    2,
    5,
    10,
  ].map((n) => n * power).firstWhere((n) => n >= target);
  final start = (first / step).floor() * step;
  final count = math.max(1, ((last - start) / step).ceil());
  String label(double position) => timeline.formatValue(
    timeline.isCalendar && position <= 0 ? position - 1 : position,
  );
  return TimelineWheelCycle(
    start: start,
    length: count * step,
    title: '${formatTimelineNumber(count * step)} years',
    description:
        '${label(start)} – ${label(start + count * step)} · '
        '${formatTimelineNumber(step)} years per segment',
    segments: [for (var i = 0; i < count; i++) label(start + i * step)],
  );
}

/// Where an entry stands on the year's wheel (see [TimelineWheel]): the
/// stretch of the year it covers, [from] and [to] as fractions of the year
/// from 1 Nisan, clockwise from the top; where its mark stands, as a
/// fraction of the wheel's radius ([radius]: an event's dot, a span's arc);
/// and the high Sabbaths of an event's day drawn with it ([sabbaths]), its
/// dot then a star.
typedef TimelineWheelMark = ({
  StudyTimelineEntry entry,
  double from,
  double to,
  double radius,
  List<StudyTimelineEntry> sabbaths,
});

/// Whether [mark] is drawn as a high Sabbath's star: one itself, or an
/// event on one.
bool timelineWheelStar(TimelineWheelMark mark) =>
    mark.entry.isHighSabbath || mark.sabbaths.isNotEmpty;

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
/// A high Sabbath on the day of the event it belongs to is drawn with it, that
/// event's dot a star. Events standing close have their dots stacked
/// inward, and spans are packed into as few rings of arcs as fit, within
/// the dots.
List<TimelineWheelMark> timelineWheelMarks(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
  double year, {
  TimelineWheelCycle? cycle,
}) {
  final stretch = cycle == null
      ? timelineYearStretch(timeline, year)
      : (start: cycle.start, end: cycle.start + cycle.length);
  final length = stretch.end - stretch.start;
  double fraction(double position) =>
      ((position - stretch.start) / length).clamp(0.0, 1.0);
  final sorted = List.of(entries)..sort(compareTimelineEntries);
  // Each high Sabbath on the day of another event, by that event.
  final sabbathsOf = <String, List<StudyTimelineEntry>>{};
  final joined = <String>{};
  for (final sabbath in sorted.where((e) => e.isHighSabbath)) {
    if (sabbath.start.day == null) continue;
    // The event it is pinned to, or else one of its category, on its day;
    // not one only falling on it, as the ʿomer may.
    final onDay = sorted.where(
      (e) =>
          !e.isSpan &&
          !e.isHighSabbath &&
          timeline.isOnDay(e.start, sabbath.start),
    );
    final event =
        onDay.where((e) => e.id == sabbath.pin?.anchorId).firstOrNull ??
        onDay
            .where(
              (e) =>
                  sabbath.category.isNotEmpty && e.category == sabbath.category,
            )
            .firstOrNull;
    if (event == null) continue;
    (sabbathsOf[event.id] ??= []).add(sabbath);
    joined.add(sabbath.id);
  }
  final events = <TimelineWheelMark>[];
  final spans = <(StudyTimelineEntry, double, double, int)>[];
  final spanEnds = <double>[];
  var lastEvent = double.negativeInfinity;
  var stack = 0;
  var deepest = 0;
  for (final entry in sorted) {
    if ((cycle == null && entry.start.month == null) ||
        joined.contains(entry.id)) {
      continue;
    }
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
        sabbaths: sabbathsOf[entry.id] ?? const [],
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
  // Fit every lane in the annulus instead of piling overflow onto its
  // innermost ring. Sparse wheels retain their usual spacing.
  final spanStep = spanEnds.length < 2
      ? _spanStep
      : math.min(_spanStep, (spanOuter - _spanInner) / (spanEnds.length - 1));
  return [
    ...events,
    for (final (entry, from, to, lane) in spans)
      (
        entry: entry,
        from: from,
        to: to,
        radius: spanOuter - lane * spanStep,
        sabbaths: const <StudyTimelineEntry>[],
      ),
  ]..sort((a, b) => compareTimelineEntries(a.entry, b.entry));
}

/// The point at [fraction] of the year round a wheel centred on [centre],
/// [radius] out: clockwise from the top, where 1 Nisan stands, unless the
/// wheel is turned [turn] of the way round.
Offset timelineWheelPoint(
  Offset centre,
  double radius,
  double fraction, {
  double turn = 0,
}) {
  final angle = -math.pi / 2 + 2 * math.pi * (fraction + turn);
  return centre + Offset(math.cos(angle), math.sin(angle)) * radius;
}

/// One year of a timeline as a wheel, its months round the rim from Nisan
/// at the top, the Sabbaths ticked inside them, and, as the timeline
/// shows them, the seasons of the land; its events as dots, a high
/// Sabbath's as a star, and its spans as arcs, each named within where
/// there is room, a line out to its mark. The cycle of the feasts shows
/// whole: the spring feasts facing the autumn ones across it. Tapping an
/// entry, or its name, calls [onTapEntry]; an event drawn with a high
/// Sabbath of its day, [onTapDay] with that day, as there is one.
///
/// Dragged, the wheel turns about its centre; pinched, scrolled, or by its
/// buttons, it zooms, its names placed afresh in the room it then has, and
/// dragged with two fingers it moves.
class TimelineWheel extends StatefulWidget {
  const TimelineWheel({
    super.key,
    required this.timeline,
    required this.entries,
    required this.year,
    this.cycle,
    this.selectedId,
    this.onTapEntry,
    this.onTapDay,
    this.faded = const {},
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;

  /// The year shown, as written; 0 on one year's calendar.
  final double year;
  final TimelineWheelCycle? cycle;
  final String? selectedId;
  final ValueChanged<StudyTimelineEntry>? onTapEntry;
  final ValueChanged<TimelineTime>? onTapDay;

  /// The entries drawn faded: those of the timelines it is built on.
  final Set<String> faded;

  /// The mark at [point] on a wheel of [size] turned [turn] of the way
  /// round, if any: one named by one of [labels], an event's dot, or a
  /// span's arc.
  static TimelineWheelMark? markAt(
    List<TimelineWheelMark> marks,
    Size size,
    Offset point, {
    List<TimelineWheelLabel> labels = const [],
    double turn = 0,
  }) {
    for (final label in labels) {
      if (label.rect.inflate(2).contains(point)) {
        return marks.firstWhere((m) => m.entry.id == label.entry.id);
      }
    }
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final offset = point - centre;
    final distance = offset.distance;
    final fraction =
        ((math.atan2(offset.dy, offset.dx) + math.pi / 2) / (2 * math.pi) -
            turn) %
        1.0;
    TimelineWheelMark? best;
    var bestDistance = double.infinity;
    for (final mark in marks) {
      if (!mark.entry.isSpan) {
        final at = timelineWheelPoint(
          centre,
          mark.radius * radius,
          mark.from,
          turn: turn,
        );
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
    return best;
  }

  /// The season of the land at [point] on a wheel of [size] turned [turn]
  /// of the way round, showing the year [year] of [timeline], if it shows
  /// them and one is there.
  static TimelineSeason? seasonAt(
    StudyTimeline timeline,
    double year,
    Size size,
    Offset point, {
    double turn = 0,
  }) {
    if (!timeline.showSeasons) return null;
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final offset = point - centre;
    final stretch = timelineYearStretch(timeline, year);
    final fraction =
        ((math.atan2(offset.dy, offset.dx) + math.pi / 2) / (2 * math.pi) -
            turn) %
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
  State<TimelineWheel> createState() => _TimelineWheelState();
}

class _TimelineWheelState extends State<TimelineWheel> {
  static const _maxZoom = 6.0;

  /// How far round the wheel is turned, as a fraction of a turn clockwise.
  double _turn = 0;

  /// How far zoomed in, and where the zoomed wheel's top left stands in
  /// view.
  double _zoom = 1;
  Offset _pan = Offset.zero;

  /// The side of the view, as last laid out.
  double _side = 0;

  /// Where a drag last stood, and a pinch's scale and twist.
  Offset _lastFocal = Offset.zero;
  double _lastScale = 1;
  double _lastRotation = 0;

  bool get _moved => _turn != 0 || _zoom != 1;

  /// [pan] held so the wheel covers the view.
  Offset _clamp(Offset pan) {
    final over = _side * (_zoom - 1);
    return Offset(pan.dx.clamp(-over, 0.0), pan.dy.clamp(-over, 0.0));
  }

  /// Zooms by [factor], [focal] in view staying put.
  void _zoomAt(Offset focal, double factor) {
    final zoom = (_zoom * factor).clamp(1.0, _maxZoom);
    final by = zoom / _zoom;
    _zoom = zoom;
    _pan = _clamp(focal - (focal - _pan) * by);
  }

  void _zoomBy(double factor) =>
      setState(() => _zoomAt(Offset(_side / 2, _side / 2), factor));

  void _reset() => setState(() {
    _turn = 0;
    _zoom = 1;
    _pan = Offset.zero;
  });

  /// Where the last pointer came down: a drag turns the wheel from there,
  /// not from where it was first seen to be a drag.
  Offset _down = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocal = details.pointerCount < 2 ? _down : details.localFocalPoint;
    _lastScale = 1;
    _lastRotation = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final focal = details.localFocalPoint;
    setState(() {
      if (details.pointerCount < 2) {
        // One finger, or the mouse, turns the wheel about its centre.
        final centre = _pan + Offset(_side, _side) * _zoom / 2;
        final from = _lastFocal - centre;
        final to = focal - centre;
        if (from.distance > 4 && to.distance > 4) {
          var delta = to.direction - from.direction;
          if (delta > math.pi) delta -= 2 * math.pi;
          if (delta < -math.pi) delta += 2 * math.pi;
          _turn = (_turn + delta / (2 * math.pi)) % 1.0;
        }
      } else {
        // Two zoom it, move it, and twisted, turn it.
        _zoomAt(_lastFocal, details.scale / _lastScale);
        _pan = _clamp(_pan + focal - _lastFocal);
        _turn =
            (_turn + (details.rotation - _lastRotation) / (2 * math.pi)) % 1.0;
        _lastScale = details.scale;
        _lastRotation = details.rotation;
      }
      _lastFocal = focal;
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      setState(
        () => _zoomAt(
          scroll.localPosition,
          math.exp(-scroll.scrollDelta.dy / 300),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.timeline;
    final year = widget.year;
    final theme = Theme.of(context);
    final marks = timelineWheelMarks(
      timeline,
      widget.entries,
      year,
      cycle: widget.cycle,
    );
    // A key to the stars, whose names are mostly left off.
    final key = marks.any(timelineWheelStar)
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              key: const ValueKey('timeline-wheel-key'),
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: const Size.square(16),
                  painter: _KeyStar(theme.colorScheme),
                ),
                const SizedBox(width: 4),
                Text(
                  'Shabbaton (a ceasing)',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          )
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(
          0.0,
          math.min(
                constraints.maxWidth,
                constraints.maxHeight - (key == null ? 0 : 28),
              ) -
              16,
        );
        _side = side;
        _pan = _clamp(_pan);
        final size = Size.square(side * _zoom);
        final layout = TimelineWheelLayout(
          timeline: timeline,
          year: year,
          cycle: widget.cycle,
          marks: marks,
          size: size,
          selectedId: widget.selectedId,
          faded: widget.faded,
          theme: theme,
          turn: _turn,
          visible: _zoom == 1 ? null : (-_pan & Size.square(side)),
        );
        // The zoom, on a ground of its own over the wheel zoomed beneath.
        final zoom = Material(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.zoom_in),
                onPressed: _zoom < _maxZoom ? () => _zoomBy(1.5) : null,
              ),
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.zoom_out),
                onPressed: _zoom > 1 ? () => _zoomBy(1 / 1.5) : null,
              ),
              IconButton(
                tooltip: 'Reset wheel',
                icon: const Icon(Icons.restart_alt),
                onPressed: _moved ? _reset : null,
              ),
            ],
          ),
        );
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Listener(
                    onPointerSignal: _onPointerSignal,
                    onPointerDown: (event) => _down = event.localPosition,
                    child: GestureDetector(
                      key: const ValueKey('timeline-wheel'),
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onTapUp: (details) {
                        final point = details.localPosition - _pan;
                        final mark = TimelineWheel.markAt(
                          marks,
                          size,
                          point,
                          labels: layout.labels,
                          turn: _turn,
                        );
                        if (mark != null) {
                          final day = widget.onTapDay;
                          if (mark.sabbaths.isNotEmpty && day != null) {
                            day(mark.entry.start);
                          } else {
                            widget.onTapEntry?.call(mark.entry);
                          }
                          return;
                        }
                        // A season tapped says what it is, and where it is written.
                        if (widget.cycle != null) return;
                        final season = TimelineWheel.seasonAt(
                          timeline,
                          year,
                          size,
                          point,
                          turn: _turn,
                        );
                        if (season == null) return;
                        ScaffoldMessenger.maybeOf(context)
                          ?..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                '${season.name} · ${season.references}',
                              ),
                            ),
                          );
                      },
                      child: ClipRect(
                        child: SizedBox.square(
                          dimension: side,
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            minWidth: 0,
                            minHeight: 0,
                            maxWidth: double.infinity,
                            maxHeight: double.infinity,
                            child: Transform.translate(
                              offset: _pan,
                              child: CustomPaint(
                                size: size,
                                painter: _WheelPainter(layout),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(right: 0, bottom: 0, child: zoom),
                ],
              ),
              ?key,
            ],
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
    this.cycle,
    required this.marks,
    required this.size,
    required this.selectedId,
    required this.faded,
    required this.theme,
    this.turn = 0,
    this.visible,
  }) {
    _place();
  }

  final StudyTimeline timeline;
  final double year;
  final TimelineWheelCycle? cycle;
  final List<TimelineWheelMark> marks;
  final Size size;
  final String? selectedId;
  final Set<String> faded;
  final ThemeData theme;

  /// How far round the wheel is turned, as a fraction of a turn clockwise.
  final double turn;

  /// The part of the wheel in view, when zoomed in: only marks in it are
  /// named, and only within it; all of it when null.
  final Rect? visible;

  ColorScheme get scheme => theme.colorScheme;
  Offset get centre => size.center(Offset.zero);
  double get r => size.shortestSide / 2;

  /// Leave visible space between dense rings, including the selected arc.
  late final double spanStrokeLimit = () {
    final radii =
        marks.where((m) => m.entry.isSpan).map((m) => m.radius).toSet().toList()
          ..sort();
    var gap = double.infinity;
    for (var i = 1; i < radii.length; i++) {
      gap = math.min(gap, radii[i] - radii[i - 1]);
    }
    return gap * r * 0.75;
  }();

  double spanStrokeWidth(TimelineWheelMark mark) =>
      math.min(mark.entry.id == selectedId ? 9.0 : 7.0, spanStrokeLimit);

  /// The year, or the calendar's title, in the middle.
  late final TextPainter title = TextPainter(
    text: TextSpan(
      text:
          cycle?.title ??
          (timeline.isAnnual ? timeline.title : timeline.formatValue(year)),
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

  /// The point [radius] out at [fraction] of the year, as the wheel is
  /// turned.
  Offset point(double radius, double fraction) =>
      timelineWheelPoint(centre, radius, fraction, turn: turn);

  /// The point of [mark] a line runs from to its name: an event's dot, a
  /// span's start, or, zoomed in, the first of it in view.
  Offset markPoint(TimelineWheelMark mark) =>
      _from[mark.entry.id] ?? point(mark.radius * r, mark.from);

  final _from = <String, Offset>{};

  /// Whether [mark] is chosen: its entry, or a high Sabbath drawn with it.
  bool isSelected(TimelineWheelMark mark) =>
      selectedId != null &&
      (mark.entry.id == selectedId ||
          mark.sabbaths.any((e) => e.id == selectedId));

  /// Places each entry's name in the room within the seasons, clear of
  /// the dots and arcs, of the names placed before it and of the title,
  /// as near its mark as it may stand without its line crossing them: the
  /// one chosen first, then the rest by rank (see below). A name stands to
  /// the side of its point away from its mark. One with no room is left
  /// out; its mark may still be tapped.
  void _place() {
    if (size.isEmpty) return;
    final reach = _labelReach * r;
    final view = visible ?? Offset.zero & size;
    final blocked = <Rect>[if (title.width > 0) titleRect.inflate(4)];
    // The marks in view, which alone are named.
    final shown = <TimelineWheelMark>{};
    for (final mark in marks) {
      if (!mark.entry.isSpan) {
        final at = markPoint(mark);
        blocked.add(Rect.fromCircle(center: at, radius: 9));
        if (view.contains(at)) shown.add(mark);
        continue;
      }
      final radius = mark.radius * r;
      final sweep = mark.to - mark.from;
      final steps = math.max(1, (2 * math.pi * radius * sweep / 4).ceil());
      for (var i = 0; i <= steps; i++) {
        final at = point(radius, mark.from + sweep * i / steps);
        blocked.add(Rect.fromCircle(center: at, radius: 6));
        if (!shown.contains(mark) && view.contains(at)) {
          shown.add(mark);
          if (i > 0) _from[mark.entry.id] = at;
        }
      }
    }
    final names = <Rect>[];
    final lines = <(Offset, Offset)>[];
    bool inside(Rect rect) => [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ].every((p) => (p - centre).distance <= reach && view.contains(p));
    // A high Sabbath called as others are ("Shabbaton", "Miqra qodesh")
    // goes unnamed unless chosen: its star, and the key, say what it is.
    final called = <String, int>{};
    for (final mark in marks) {
      for (final e in [
        mark.entry,
        ...mark.sabbaths,
      ].where((e) => e.isHighSabbath)) {
        called.update(e.shortLabel, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    bool unnamed(TimelineWheelMark m) =>
        m.entry.isHighSabbath && called[m.entry.shortLabel]! > 1;
    // The spans first, then the events, the high Sabbaths among them last,
    // each in the order of the year.
    int rank(TimelineWheelMark m) => isSelected(m)
        ? 0
        : unnamed(m)
        ? -1
        : m.entry.isSpan
        ? 1
        : m.entry.isHighSabbath
        ? 3
        : 2;
    final order = [
      for (var i = 0; i <= 3; i++)
        ...marks.where((m) => rank(m) == i && shown.contains(m)),
    ];
    final small = theme.textTheme.labelSmall;
    final probe = TextPainter(
      text: TextSpan(text: 'M', style: small),
      textDirection: TextDirection.ltr,
    )..layout();
    // The points a name may stand by, on a grid over the room in view.
    final grid = probe.height * 0.6;
    final points = <Offset>[
      for (var y = -reach; y <= reach; y += grid)
        if (view.top <= centre.dy + y && centre.dy + y <= view.bottom)
          for (var x = -reach; x <= reach; x += grid)
            if (x * x + y * y <= reach * reach &&
                view.left <= centre.dx + x &&
                centre.dx + x <= view.right)
              centre + Offset(x, y),
    ];
    for (final mark in order) {
      final selected = isSelected(mark);
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
    double angle(double fraction) =>
        -math.pi / 2 + 2 * math.pi * (fraction + layout.turn);
    final small = theme.textTheme.labelSmall;

    // The months round the rim, named along it.
    final cycle = layout.cycle;
    final months = cycle?.segments.length ?? timeline.monthsIn(year);
    for (var month = 1; month <= months; month++) {
      final from = cycle != null
          ? (month - 1) / months
          : fraction(
              timeline.positionOf(TimelineTime(year, month: month, day: 1)),
            );
      final to = cycle != null
          ? month / months
          : fraction(
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
        cycle?.segments[month - 1] ?? timeline.monthName(year, month),
        centre,
        mid,
        (from + to) / 2 + layout.turn,
        small?.copyWith(fontWeight: FontWeight.w600),
        maxWidth: 2 * math.pi * mid * (to - from) * 0.92,
      );
    }
    // Evening first, then morning, inside each literal day's rim.
    for (final part
        in cycle?.dayParts ?? <({String label, double from, double to})>[]) {
      final evening = part.label == 'Evening';
      _band(
        canvas,
        centre,
        r * 0.79,
        r * 0.875,
        angle(part.from),
        angle(part.to) - angle(part.from),
        Paint()
          ..color = evening
              ? scheme.secondaryContainer
              : scheme.tertiaryContainer,
      );
      final mid = r * 0.8325;
      _alongRim(
        canvas,
        part.label,
        centre,
        mid,
        (part.from + part.to) / 2 + layout.turn,
        small?.copyWith(
          color: evening
              ? scheme.onSecondaryContainer
              : scheme.onTertiaryContainer,
        ),
        maxWidth: 2 * math.pi * mid * (part.to - part.from) * 0.92,
      );
    }
    // The Sabbaths, ticked just inside the months.
    final sabbath = Paint()
      ..color = scheme.secondary
      ..strokeWidth = 1.5;
    final days = cycle == null ? timeline.daysInYear(year) : 0;
    for (var day = 0; day < days; day++) {
      final time = timeline.addDays(TimelineTime(year, month: 1, day: 1), day);
      if (time == null || timeline.weekdayOf(time) != 7) continue;
      final at = fraction(timeline.centreOf(time));
      canvas.drawLine(
        layout.point(r * (_monthsInner - 0.005), at),
        layout.point(r * (_monthsInner - 0.03), at),
        sabbath,
      );
    }
    // The seasons of the land, rain outside the farming year.
    // Each apart from the next, and shaded by turns.
    if (cycle == null && timeline.showSeasons) {
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
          ..strokeWidth = layout.spanStrokeWidth(mark),
      );
    }
    // The events as dots, a high Sabbath's, or an event's on one, a star.
    for (final mark in layout.marks.where((m) => !m.entry.isSpan)) {
      final selected = layout.isSelected(mark);
      final color = layout.colorOf(mark.entry);
      final dot = layout.point(r * mark.radius, mark.from);
      if (timelineWheelStar(mark)) {
        final star = _star(dot, 8);
        canvas
          ..drawPath(star, Paint()..color = scheme.tertiaryContainer)
          ..drawPath(
            star,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = 1.5,
          );
      } else {
        canvas.drawCircle(dot, 5, Paint()..color = color);
      }
      if (selected) {
        canvas.drawCircle(
          dot,
          timelineWheelStar(mark) ? 10 : 8,
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

  /// A five-pointed star centred on [centre], its points [radius] out.
  static Path _star(Offset centre, double radius) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final p =
          centre +
          Offset(math.cos(a), math.sin(a)) *
              (i.isEven ? radius : radius * 0.45);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
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
      old.layout.cycle != layout.cycle ||
      old.layout.marks != layout.marks ||
      old.layout.size != layout.size ||
      old.layout.selectedId != layout.selectedId ||
      old.layout.faded != layout.faded ||
      old.layout.theme != theme ||
      old.layout.turn != layout.turn ||
      old.layout.visible != layout.visible;
}

/// A high Sabbath's star, as the wheel draws it, for its key.
class _KeyStar extends CustomPainter {
  _KeyStar(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final star = _WheelPainter._star(
      size.center(Offset.zero),
      size.shortestSide / 2 - 1,
    );
    canvas
      ..drawPath(star, Paint()..color = scheme.tertiaryContainer)
      ..drawPath(
        star,
        Paint()
          ..color = scheme.tertiary
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.5,
      );
  }

  @override
  bool shouldRepaint(_KeyStar old) => old.scheme != scheme;
}
