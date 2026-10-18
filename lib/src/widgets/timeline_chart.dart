import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';
import 'timeline_calendar.dart';
import 'timeline_wheel.dart';

/// The stretch of a timeline's axis drawn (as positions, see
/// [StudyTimeline.positionOf]): its entries' (see [timelineFocus]), but
/// one year's calendar its whole year.
({double start, double end}) timelineExtent(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
) {
  // One year's calendar shows its whole year.
  if (entries.isEmpty || timeline.isAnnual) return (start: 0, end: 1);
  return timelineFocus(timeline, entries);
}

/// The stretch of a timeline's axis its entries cover, with a margin either
/// side; a single point gets one unit either side, or on one year's
/// calendar half a month, and that calendar's stretch keeps within its year.
({double start, double end}) timelineFocus(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
) {
  if (entries.isEmpty) return (start: 0, end: 1);
  final reaches = [for (final e in entries) timelineEntryReach(timeline, e)];
  final start = reaches.map((r) => r.start).reduce(math.min);
  final end = reaches.map((r) => r.end).reduce(math.max);
  final margin = end - start < 1e-9
      ? (timeline.isAnnual ? 1 / 24 : 1.0)
      : (end - start) * 0.04;
  if (!timeline.isAnnual) return (start: start - margin, end: end + margin);
  return (
    start: math.max(0.0, start - margin),
    end: math.min(1.0, end + margin),
  );
}

/// The stretch of a timeline's axis [entry] covers, as positions: a span's
/// from its start to the end of its last day (see [StudyTimeline.endOf]),
/// and an event's the point in the middle of its day, or in the part of
/// it it falls in (see [TimelineDayPart]).
({double start, double end}) timelineEntryReach(
  StudyTimeline timeline,
  StudyTimelineEntry entry,
) {
  if (!entry.isSpan) {
    final part = entry.dayPart;
    final from = timeline.positionOf(entry.start);
    final at = part == null
        ? timeline.centreOf(entry.start)
        : from + part.fraction * (timeline.endOf(entry.start) - from);
    return (start: at, end: at);
  }
  return (
    start: timeline.positionOf(entry.start),
    end: timeline.endOf(entry.last),
  );
}

/// An entry's place on a drawn timeline: its lane (row) and the horizontal
/// stretch it takes, its bar or dot together with its label.
typedef TimelineSlot = ({
  StudyTimelineEntry entry,
  int lane,
  double left,
  double right,
});

/// Packs [entries] into as few lanes as fit, in time order, each entry in
/// the first lane free [gap] before it. [x] places an axis position, and
/// an entry's slot runs from where its reach starts (see
/// [timelineEntryReach]): a span's start, an event's middle. [width] is
/// the least room an entry's mark and label take from there. An entry
/// pinned to another (see [TimelinePin]) takes a lane below its anchor's,
/// so that the events of a feast hang beneath it, its shabbatons among
/// them; an anchor is placed before what is pinned to it from its start.
/// Shabbatons pinned to nothing above them, stars without labels, all
/// share the first lane. Spans of one category that never overlap, as the
/// three pilgrimages, share a lane of their own, which nothing else takes.
List<TimelineSlot> packTimelineLanes(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries, {
  required double Function(double position) x,
  required double Function(StudyTimelineEntry entry) width,
  double gap = 8,
}) {
  final sorted = List.of(entries)..sort(compareTimelineEntries);
  final byId = {for (final e in sorted) e.id: e};
  double from(StudyTimelineEntry e) => timelineEntryReach(timeline, e).start;
  // The anchor an entry hangs beneath: one placed before it, starting no
  // later than it.
  StudyTimelineEntry? anchorOf(StudyTimelineEntry e) =>
      switch (byId[e.pin?.anchorId]) {
        final anchor? when from(anchor) <= from(e) + 1e-9 => anchor,
        _ => null,
      };
  final ordered = <StudyTimelineEntry>[];
  final seen = Set<StudyTimelineEntry>.identity();
  void visit(StudyTimelineEntry e) {
    if (!seen.add(e)) return;
    if (anchorOf(e) case final anchor?) visit(anchor);
    ordered.add(e);
  }

  sorted.forEach(visit);
  final sabbaths = sorted.any((e) => e.isHighSabbath && anchorOf(e) == null);
  final laneEnds = <double>[if (sabbaths) double.infinity];
  ({double left, double right}) extent(StudyTimelineEntry e) {
    final reach = timelineEntryReach(timeline, e);
    final left = x(reach.start);
    return (left: left, right: math.max(x(reach.end), left + width(e)));
  }

  // A row for each category of two or more spans, none overlapping.
  final byCategory = <String, List<StudyTimelineEntry>>{};
  for (final e in ordered) {
    if (e.isSpan && e.category.isNotEmpty) {
      (byCategory[e.category] ??= []).add(e);
    }
  }
  final rows = <String, int>{};
  for (final MapEntry(key: category, value: spans) in byCategory.entries) {
    if (spans.length < 2) continue;
    final at = spans.map(extent).toList()
      ..sort((a, b) => a.left.compareTo(b.left));
    var apart = true;
    for (var i = 1; i < at.length && apart; i++) {
      apart = at[i - 1].right + gap <= at[i].left;
    }
    if (!apart) continue;
    rows[category] = laneEnds.length;
    // Kept for them: never free to anything else.
    laneEnds.add(double.infinity);
  }
  final slots = <TimelineSlot>[];
  final laneOf = <String, int>{};
  for (final entry in ordered) {
    final (:left, :right) = extent(entry);
    if (entry.isSpan) {
      if (rows[entry.category] case final row?) {
        laneOf[entry.id] = row;
        slots.add((entry: entry, lane: row, left: left, right: right));
        continue;
      }
    }
    final anchor = laneOf[anchorOf(entry)?.id];
    if (entry.isHighSabbath && anchor == null) {
      slots.add((entry: entry, lane: 0, left: left, right: right));
      laneOf[entry.id] = 0;
      continue;
    }
    var lane = laneEnds.indexWhere(
      (end) => end + gap <= left,
      anchor == null ? 0 : anchor + 1,
    );
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(right);
    } else {
      laneEnds[lane] = right;
    }
    laneOf[entry.id] = lane;
    slots.add((entry: entry, lane: lane, left: left, right: right));
  }
  return slots;
}

/// A marked time on an axis: where it falls, how it reads, and where the
/// label stands: under the mark, or for a day in the gap after it, as a
/// day is the stretch between two marks. One without a label is a minor
/// mark, a boundary between days.
typedef TimelineTick = ({double position, double labelAt, String label});

/// Round times between the axis positions [start] and [end] of [timeline]
/// to mark on an axis [pixels] wide, about [spacing] pixels apart: steps of
/// 1, 2 or 5 times a power of ten (whole years, where it counts years, and
/// no year zero counting by era), or, zoomed in within a year, its months,
/// and further in its days.
List<TimelineTick> timelineTicks(
  StudyTimeline timeline,
  double start,
  double end,
  double pixels, {
  double spacing = 96,
}) {
  if (end <= start || pixels <= 0) return const [];
  final rough = (end - start) * spacing / pixels;
  final calendar = timeline.isCalendar;
  // An axis position as written: a BC year sits one below its position.
  double written(double position) =>
      calendar && position <= 0 ? position - 1 : position;
  // Zoomed in to within ten days a label, each day's start is marked, as
  // a day is a stretch of the axis, and its label stands in the gap: the
  // first of a month by its name, and the others by number, every day or
  // every 5th or 10th (5, 10, 15...), leaving off any too near the next
  // month's first.
  if (timeline.hasMonths && rough <= 10 / 354) {
    final step = [1, 5, 10].firstWhere((d) => d / 354 >= rough);
    return [
      for (final year
          in timeline.isAnnual
              ? const [0]
              : [for (var y = start.floor(); y <= end.ceil(); y++) y])
        for (
          var month = 1;
          month <= timeline.monthsIn(written(year.toDouble()));
          month++
        )
          for (
            var day = 1;
            day <= timeline.daysInMonth(written(year.toDouble()), month);
            day++
          )
            if (TimelineTime(written(year.toDouble()), month: month, day: day)
                case final time
                when timeline.endOf(time) > start &&
                    timeline.positionOf(time) < end)
              (
                position: timeline.positionOf(time),
                labelAt: timeline.centreOf(time),
                label: day == 1
                    ? month == 1
                          ? timeline.formatTime(time)
                          : '1 ${timeline.monthName(time.value, month)}'
                    : day % step == 0 &&
                          day + step / 2 <=
                              timeline.daysInMonth(time.value, month)
                    ? '$day'
                    : '',
              ),
    ];
  }
  // Months are marked only where at least two fit in a year; one year's
  // calendar has only its months to mark.
  if (timeline.isAnnual || (timeline.countsYears && rough <= 0.5)) {
    final step = [
      1,
      2,
      3,
      6,
    ].firstWhere((m) => m / 12 >= rough, orElse: () => 6);
    return [
      for (final year
          in timeline.isAnnual
              ? const [0]
              : [for (var y = start.floor(); y <= end.ceil(); y++) y])
        for (
          var month = 1;
          month <= timeline.monthsIn(written(year.toDouble()));
          month += step
        )
          if (TimelineTime(written(year.toDouble()), month: month)
              case final time
              when timeline.positionOf(time) >= start &&
                  timeline.positionOf(time) <= end)
            (
              position: timeline.positionOf(time),
              labelAt: timeline.positionOf(time),
              label: month == 1
                  ? timeline.formatTime(time)
                  : timeline.monthName(time.value, month),
            ),
    ];
  }
  final power = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  var step = [1, 2, 5, 10]
      .map((m) => m * power)
      .firstWhere((s) => s >= rough, orElse: () => 10 * power);
  if (timeline.countsYears) step = math.max(1, step.roundToDouble());
  final last = written(end);
  return [
    for (
      var value = (written(start) / step).ceil() * step;
      value <= last + step * 1e-9;
      value += step
    )
      if (!calendar || value != 0)
        (
          position: timeline.positionOf(TimelineTime(value)),
          labelAt: timeline.positionOf(TimelineTime(value)),
          label: timeline.formatValue(value),
        ),
  ];
}

/// The years, as written, whose stretch of the axis meets that from
/// [start] to [end]: the one year of one year's calendar.
List<double> timelineYearsBetween(
  StudyTimeline timeline,
  double start,
  double end,
) {
  if (timeline.isAnnual) return const [0];
  double written(int position) =>
      timeline.isCalendar && position <= 0 ? position - 1.0 : position * 1.0;
  return [
    for (var y = start.floor(); y <= end.ceil(); y++)
      if (timeline.fits(TimelineTime(written(y), month: 1, day: 1))) written(y),
  ];
}

/// The seasons of the land (see [timelineSeasons]) in the years between
/// the axis positions [start] and [end], each with where it runs; none off
/// the year scales, or over more than [most] years.
List<({TimelineSeason season, double start, double end})> timelineSeasonsIn(
  StudyTimeline timeline,
  double start,
  double end, {
  int most = 60,
}) {
  if (!timeline.hasMonths || end <= start) return const [];
  final years = timelineYearsBetween(timeline, start, end);
  if (years.length > most) return const [];
  return [
    for (final year in years)
      for (final season in timelineSeasons)
        if (season.inYear(timeline, year) case final at
            when at.end > start && at.start < end)
          (season: season, start: at.start, end: at.end),
  ];
}

/// The new and full moons (see [timelineMoonOn]) between the axis
/// positions [start] and [end]: where each day's middle falls, and whether
/// the moon is full; none where there would be more than [most].
List<({double at, bool full})> timelineMoons(
  StudyTimeline timeline,
  double start,
  double end, {
  int most = 2000,
}) {
  if (!timeline.hasMonths || end <= start) return const [];
  final moons = <({double at, bool full})>[];
  for (final year in timelineYearsBetween(timeline, start, end)) {
    for (var month = 1; month <= timeline.monthsIn(year); month++) {
      for (final day in const [1, 15]) {
        final at = timeline.centreOf(
          TimelineTime(year, month: month, day: day),
        );
        if (at < start || at > end) continue;
        if (moons.length >= most) return const [];
        moons.add((at: at, full: day == 15));
      }
    }
  }
  return moons;
}

/// The night halves, from sunset, of the days between the axis positions
/// [start] and [end] of [timeline] (see [TimelineDayPart]); none off the
/// year scales, or where there would be more than [most].
List<({double from, double to})> timelineNights(
  StudyTimeline timeline,
  double start,
  double end, {
  int most = 4000,
}) {
  if (!timeline.hasMonths || end <= start) return const [];
  final years = timelineYearsBetween(timeline, start, end);
  final nights = <({double from, double to})>[];
  for (final year in years) {
    final first = TimelineTime(year, month: 1, day: 1);
    if (!timeline.fits(first)) continue;
    final base = timeline.positionOf(first);
    final length = timeline.daysInYear(year);
    for (var day = 0; day < length; day++) {
      final from = base + day / length;
      if (from + 1 / length < start || from > end) continue;
      if (nights.length >= most) return const [];
      nights.add((from: from, to: from + 0.5 / length));
    }
  }
  return nights;
}

/// A label's width in [style].
double _textWidth(String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}

/// An entry's icon: a span's line, an event's dot, or a high Sabbath's star.
IconData timelineEntryIcon(StudyTimelineEntry entry) => entry.isSpan
    ? Icons.linear_scale
    : entry.isHighSabbath
    ? Icons.star
    : Icons.radio_button_checked;

/// What an entry is called: "Span", "Event" or "Shabbaton".
String timelineEntryKind(StudyTimelineEntry entry) => entry.isSpan
    ? 'Span'
    : entry.isHighSabbath
    ? 'Shabbaton'
    : 'Event';

/// How an entry's time reads: its date as written, or else its time on the
/// timeline's scale, a span's from start to end.
String timelineEntryTime(StudyTimeline timeline, StudyTimelineEntry entry) {
  final duration = entry.duration;
  final time = entry.isSpan
      ? '${timeline.formatTime(entry.start)} – '
            '${timeline.formatTime(entry.end!)}'
            '${duration == null ? '' : ' (${timeline.formatDuration(duration)})'}'
      : timeline.formatTime(entry.start);
  final part = entry.dayPart;
  final when = part == null ? time : '$time, ${part.phrase}';
  return entry.date.isEmpty ? when : '${entry.date} $when';
}

/// A timeline drawn to scale: spans as bars and events as dots, packed into
/// lanes above an axis marked in the timeline's unit.
class TimelineChart extends StatelessWidget {
  const TimelineChart({
    super.key,
    required this.timeline,
    required this.entries,
    required this.pixelsPerUnit,
    this.onTapEntry,
    this.selectedId,
    this.seasons = false,
    this.faded = const {},
    this.groups = const {},
    this.onToggleGroup,
    this.onTapCluster,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final double pixelsPerUnit;

  /// The spans with entries grouped under them (those pinned to them), by
  /// id: how many, and whether they are shown. Each such span's bar has a
  /// button after its title to show or hide them, by [onToggleGroup].
  final Map<String, ({int count, bool open})> groups;
  final ValueChanged<StudyTimelineEntry>? onToggleGroup;

  /// Opens a run of events drawn as one mark, more than [mostStacked]
  /// stacked so close together; given them in time order.
  final ValueChanged<List<StudyTimelineEntry>>? onTapCluster;

  /// Whether to show the seasons of the land above the entries, and the
  /// new and full moons on the axis, zoomed in to them.
  final bool seasons;

  /// The entries drawn faded: those of the timelines it is built on.
  final Set<String> faded;
  final ValueChanged<StudyTimelineEntry>? onTapEntry;
  final String? selectedId;

  static const padding = 24.0;
  static const laneHeight = 30.0;
  static const axisHeight = 36.0;
  static const seasonHeight = 16.0;
  static const _dot = 10.0;

  /// How far an event's mark reaches back from its centre: half a dot,
  /// or of a high Sabbath's star.
  static double _inset(StudyTimelineEntry entry) => entry.isSpan
      ? 0
      : entry.isHighSabbath
      ? (_dot + 2) / 2
      : _dot / 2;

  static double widthFor(
    StudyTimeline timeline,
    List<StudyTimelineEntry> entries,
    double pixelsPerUnit,
  ) {
    final extent = timelineExtent(timeline, entries);
    return (extent.end - extent.start) * pixelsPerUnit + padding * 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall;
    final extent = timelineExtent(timeline, entries);
    double px(double position) =>
        padding + (position - extent.start) * pixelsPerUnit;
    // A shabbaton dated to its day is drawn as that day, behind the rest.
    final shabbatons = [
      for (final e in entries)
        if (_isDayBlock(e)) e,
    ];
    final clusters = _clusters(px);
    final clustered = {
      for (final events in clusters.values)
        for (final e in events) e.id,
    };
    // Packed by their marks alone, to keep to as few lanes as may be; each
    // label then takes what room its lane leaves it.
    final slots = packTimelineLanes(
      timeline,
      [
        for (final e in entries)
          if (!clustered.contains(e.id) && !_isDayBlock(e)) e,
        for (final MapEntry(:key, :value) in clusters.entries)
          _clusterEntry(key, value),
      ],
      x: px,
      width: (e) => e.isHighSabbath
          ? _dot + 2
          : e.isSpan
          ? 4
          : _dot,
      gap: _gap,
    );
    final labels = _labelsFor(slots, labelStyle);
    final lanes = slots.isEmpty
        ? 1
        : slots.map((s) => s.lane).reduce(math.max) + 1;
    // Room too for the labels running past the last time.
    final width = slots.fold(
      widthFor(timeline, entries, pixelsPerUnit),
      (width, slot) => math.max(
        width,
        slot.left + labels[slot.entry.id]!.width + padding / 2,
      ),
    );
    final bands = seasons
        ? timelineSeasonsIn(timeline, extent.start, extent.end)
        : const <({TimelineSeason season, double start, double end})>[];
    // The seasons take a row each for rain and harvest above the lanes.
    final top = bands.isEmpty ? 0.0 : seasonHeight * 2 + 6;
    final height = top + lanes * laneHeight + axisHeight;
    final axisY = top + lanes * laneHeight + 4;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AxisPainter(
                timeline: timeline,
                start: extent.start,
                end: extent.end,
                x: px,
                axisY: axisY,
                width: width,
                // Days run from sunset: their nights shaded, zoomed in to them.
                nights: timeline.hasMonths && pixelsPerUnit / 384 >= 10
                    ? [
                        for (final n in timelineNights(
                          timeline,
                          extent.start,
                          extent.end,
                        ))
                          (from: px(n.from), to: px(n.to)),
                      ]
                    : const [],
                moons: seasons && pixelsPerUnit / 384 >= 6
                    ? [
                        for (final m in timelineMoons(
                          timeline,
                          extent.start,
                          extent.end,
                        ))
                          (x: px(m.at), full: m.full),
                      ]
                    : const [],
                guides: [
                  for (final slot in slots)
                    if (!slot.entry.isSpan)
                      (x: slot.left, top: top + slot.lane * laneHeight + 15),
                ],
                color: theme.colorScheme.outline,
                labelStyle: labelStyle?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          // Each shabbaton its whole day, sundown to sundown, top to axis.
          for (final day in shabbatons)
            if ((
                  from: px(timeline.positionOf(day.start)),
                  to: px(timeline.endOf(day.start)),
                )
                case final at)
              Positioned(
                left: at.from,
                width: math.max(2, at.to - at.from),
                top: 0,
                height: axisY,
                child: _ShabbatonBlock(
                  entry: day,
                  color: switch (timeline.colorOf(day)) {
                    final index? => timelineCategoryColor(
                      index,
                      theme.brightness,
                    ),
                    null => null,
                  },
                  selected: day.id == selectedId,
                  faded: faded.contains(day.id),
                  tooltip: '${day.title} · ${timelineEntryTime(timeline, day)}',
                  onTap: onTapEntry == null ? null : () => onTapEntry!(day),
                ),
              ),
          for (final band in bands)
            Positioned(
              left: px(band.start),
              width: math.max(1, px(band.end) - px(band.start)),
              top:
                  2 +
                  (band.season.kind == TimelineSeasonKind.rain
                      ? 0
                      : seasonHeight + 2),
              height: seasonHeight,
              child: _SeasonBand(season: band.season),
            ),
          for (final slot in slots)
            if (labels[slot.entry.id]! case final label)
              Positioned(
                // An event's mark is centred on its time.
                left: slot.left - _inset(slot.entry),
                top: top + slot.lane * laneHeight + 4,
                width: label.width + _inset(slot.entry),
                height: laneHeight - 8,
                child: Opacity(
                  opacity: faded.contains(slot.entry.id) ? 0.45 : 1,
                  child: _EntryMark(
                    entry: slot.entry,
                    barWidth: math.max(
                      4,
                      px(timelineEntryReach(timeline, slot.entry).end) -
                          slot.left,
                    ),
                    color: switch (timeline.colorOf(slot.entry)) {
                      final index? => timelineCategoryColor(
                        index,
                        theme.brightness,
                      ),
                      null => null,
                    },
                    countedDays: timeline.daysIn(slot.entry) ?? 0,
                    titleWidth: label.title,
                    showTitle: label.title > 0,
                    selected:
                        slot.entry.id == selectedId ||
                        (clusters[slot.entry.id]?.any(
                              (e) => e.id == selectedId,
                            ) ??
                            false),
                    stacked: clusters[slot.entry.id]?.length ?? 0,
                    tooltip: switch (clusters[slot.entry.id]) {
                      // The events it stands for, as many as are short.
                      final events? => [
                        for (final e in events.take(8)) e.title,
                        if (events.length > 8) '… ${events.length - 8} more',
                      ].join('\n'),
                      // Its title too where the label doesn't show it whole.
                      null when slot.entry.isHighSabbath || !label.whole =>
                        '${slot.entry.title} · ${timelineEntryTime(timeline, slot.entry)}',
                      null => timelineEntryTime(timeline, slot.entry),
                    },
                    onTap: switch (clusters[slot.entry.id]) {
                      final events? when onTapCluster != null =>
                        () => onTapCluster!(events),
                      null when onTapEntry != null => () => onTapEntry!(
                        slot.entry,
                      ),
                      _ => null,
                    },
                    group: switch (groups[slot.entry.id]) {
                      final group? when label.group => _GroupToggle(
                        key: ValueKey('timeline-group-${slot.entry.id}'),
                        count: group.count,
                        open: group.open,
                        dense: true,
                        onPressed: onToggleGroup == null
                            ? null
                            : () => onToggleGroup!(slot.entry),
                      ),
                      _ => null,
                    },
                  ),
                ),
              ),
        ],
      ),
    );
  }

  /// The least gap between two marks in a lane.
  static const _gap = 8.0;

  /// The most events stacked one above another at a time before they are
  /// drawn as one mark, with their number.
  static const mostStacked = 5;

  /// The events (not spans or high Sabbaths) whose dots fall so close
  /// together, placed by [px], that more than [mostStacked] would stack,
  /// each such run by the id of its mark (see [_clusterEntry]): from each
  /// event, those starting within a dot and a gap of it.
  /// Whether [entry] is a shabbaton dated to its day, drawn as the whole
  /// of that day rather than as a mark in a lane.
  bool _isDayBlock(StudyTimelineEntry entry) =>
      entry.isHighSabbath && timeline.hasMonths && entry.start.day != null;

  Map<String, List<StudyTimelineEntry>> _clusters(
    double Function(double position) px,
  ) {
    final points = [
      for (final e in entries)
        if (!e.isSpan && !e.isHighSabbath)
          (entry: e, x: px(timelineEntryReach(timeline, e).start)),
    ]..sort((a, b) => a.x.compareTo(b.x));
    final clusters = <String, List<StudyTimelineEntry>>{};
    var i = 0;
    while (i < points.length) {
      var j = i;
      while (j < points.length && points[j].x - points[i].x < _dot + _gap) {
        j++;
      }
      if (j - i > mostStacked) {
        final run = [for (final p in points.sublist(i, j)) p.entry]
          ..sort(compareTimelineEntries);
        clusters['cluster-${run.first.id}'] = run;
        i = j;
      } else {
        i++;
      }
    }
    return clusters;
  }

  /// The mark standing for the run of [events] clustered as [id]: at the
  /// first's time, called by their kind and number, "Births ×11", where they
  /// share a category, else "7 events".
  StudyTimelineEntry _clusterEntry(String id, List<StudyTimelineEntry> events) {
    final first = events.first;
    final categories = {for (final e in events) e.category};
    final category = categories.length == 1 ? categories.single : '';
    return StudyTimelineEntry(
      id: id,
      title: category.isEmpty
          ? '${events.length} events'
          : '$category ×${events.length}',
      timelineId: timeline.id,
      start: first.start,
      part: first.part,
      category: category,
    );
  }

  /// The narrowest a title is cut to before it is left out altogether.
  static const _leastTitle = 28.0;

  /// How each slot's label fits the room its lane leaves it, up to the
  /// next mark in the lane, by entry id: the [width] its mark and label
  /// take from its time, the [title]'s width shown (0 where left out),
  /// whether it is [whole], and whether a span's button for the entries
  /// grouped under it shows. Zoomed out, labels are cut short or left
  /// out; zoomed in, they show whole.
  Map<String, ({double width, double title, bool whole, bool group})>
  _labelsFor(List<TimelineSlot> slots, TextStyle? style) {
    final next = <String, double>{};
    final byLane = <int, List<TimelineSlot>>{};
    for (final slot in slots) {
      (byLane[slot.lane] ??= []).add(slot);
    }
    for (final lane in byLane.values) {
      lane.sort((a, b) => a.left.compareTo(b.left));
      for (var i = 0; i + 1 < lane.length; i++) {
        final after = lane[i + 1];
        next[lane[i].entry.id] = after.left - _inset(after.entry) - _gap;
      }
    }
    return {
      for (final slot in slots)
        slot.entry.id: () {
          final entry = slot.entry;
          final mark = slot.right - slot.left;
          if (entry.isHighSabbath) {
            return (width: mark, title: 0.0, whole: false, group: false);
          }
          final room = (next[entry.id] ?? double.infinity) - slot.left;
          final lead = entry.isSpan ? 6.0 : _dot + 4;
          final title = _textWidth(entry.title, style);
          final button = groups.containsKey(entry.id)
              ? _GroupToggle.width
              : 0.0;
          final full = lead + title + 4 + button;
          if (room >= full) {
            return (
              width: math.max(mark, full),
              title: title,
              whole: true,
              group: true,
            );
          }
          final cut = room - lead - 4 - button;
          if (cut >= _leastTitle) {
            return (
              width: math.max(mark, room),
              title: cut,
              whole: false,
              group: true,
            );
          }
          // A span's button alone, where there is room for it.
          final group = button > 0 && room >= lead + button;
          return (
            width: group ? math.max(mark, room) : mark,
            title: 0.0,
            whole: false,
            group: group,
          );
        }(),
    };
  }
}

/// A season of the land as a band across its stretch of the year, named
/// where it fits, its verses in its tooltip.
class _SeasonBand extends StatelessWidget {
  const _SeasonBand({required this.season});

  final TimelineSeason season;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = timelineSeasonColor(season.kind, theme.brightness);
    return Tooltip(
      message: '${season.name} · ${season.references}',
      child: Container(
        key: ValueKey('timeline-season-${season.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(3),
          border: Border(left: BorderSide(color: color, width: 2)),
        ),
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          season.name,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// A shabbaton as its whole day, from the sundown that begins it to the
/// next, shaded the height of the chart behind its entries, as the
/// calendar shades it; named at its top where it is wide enough.
class _ShabbatonBlock extends StatelessWidget {
  const _ShabbatonBlock({
    required this.entry,
    required this.selected,
    required this.faded,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  final StudyTimelineEntry entry;

  /// Its category's colour, else the theme's shabbaton shade.
  final Color? color;
  final bool selected, faded;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fill = color == null
        ? scheme.tertiaryContainer.withValues(alpha: faded ? 0.3 : 0.6)
        : color!.withValues(alpha: faded ? 0.1 : 0.22);
    final ink = color == null ? scheme.onTertiaryContainer : scheme.onSurface;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey('timeline-mark-${entry.id}'),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) => DecoratedBox(
            decoration: BoxDecoration(
              color: fill,
              border: Border.symmetric(
                vertical: BorderSide(
                  color: selected
                      ? scheme.onSurface
                      : (color ?? scheme.tertiary).withValues(
                          alpha: faded ? 0.25 : 0.6,
                        ),
                  width: selected ? 2 : 1,
                ),
              ),
            ),
            child: constraints.maxWidth < 56
                ? const SizedBox.expand()
                : Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(3, 2, 3, 0),
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          fontWeight: selected ? FontWeight.bold : null,
                          color: ink.withValues(alpha: faded ? 0.6 : 1),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _EntryMark extends StatelessWidget {
  const _EntryMark({
    required this.entry,
    required this.barWidth,
    this.countedDays = 0,
    this.titleWidth = 0,
    this.showTitle = true,
    this.stacked = 0,
    this.color,
    required this.selected,
    required this.tooltip,
    this.onTap,
    this.group,
  });

  final StudyTimelineEntry entry;
  final double barWidth;

  /// Whether its title shows beside it, cut short where its label has too
  /// little room; left out, it is in [tooltip].
  final bool showTitle;

  /// For a mark standing for several events stacked too close together
  /// (see [TimelineChart.mostStacked]), how many; 0 for one entry.
  final int stacked;

  /// For a span with entries grouped under it, the button after its title
  /// that shows or hides them.
  final Widget? group;

  /// For a span dated to the day, its days, to mark them across its bar,
  /// and its weeks where it is counted (see [StudyTimelineEntry.isCounted]),
  /// with its notes for its days (see [StudyTimelineEntry.dayNotes]), clear
  /// of its title, which is [titleWidth] wide.
  final int countedDays;
  final double titleWidth;

  /// Its category's colour (see [timelineEntryColor]); null for the usual.
  final Color? color;
  final bool selected;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = color ?? scheme.primary;
    final dot = color ?? scheme.tertiary;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: selected ? FontWeight.bold : null,
    );
    final label = Text(
      entry.title,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey('timeline-mark-${entry.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: entry.isSpan
            ? Stack(
                clipBehavior: Clip.none,
                alignment: AlignmentDirectional.centerStart,
                children: [
                  Container(
                    width: barWidth,
                    decoration: BoxDecoration(
                      color:
                          color?.withValues(alpha: 0.22) ??
                          scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected ? bar : bar.withValues(alpha: 0.5),
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  if ((entry.isCounted || entry.dayNotes.isNotEmpty) &&
                      countedDays > 0)
                    SizedBox(
                      width: barWidth,
                      height: double.infinity,
                      child: CustomPaint(
                        painter: _DaysPainter(
                          days: countedDays,
                          counted: entry.isCounted,
                          notes: entry.dayNotes,
                          skip: titleWidth + 12,
                          color: bar,
                          labelStyle: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showTitle) Flexible(child: label),
                        if (showTitle && group != null)
                          const SizedBox(width: 4),
                        ?group,
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.isHighSabbath)
                    Icon(
                      Icons.star,
                      size: TimelineChart._dot + 2,
                      color: selected ? scheme.onSurface : dot,
                    )
                  else
                    Container(
                      width: TimelineChart._dot,
                      height: TimelineChart._dot,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dot,
                        border: selected
                            ? Border.all(color: scheme.onSurface, width: 2)
                            : null,
                        // Several events as one, a halo round its dot.
                        boxShadow: stacked > 0
                            ? [
                                BoxShadow(
                                  color: dot.withValues(alpha: 0.35),
                                  spreadRadius: 3,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  // A high Sabbath's title is in its tooltip alone.
                  if (!entry.isHighSabbath && showTitle) ...[
                    const SizedBox(width: 4),
                    Flexible(child: label),
                  ],
                ],
              ),
      ),
    );
  }
}

/// The button that shows or hides the [count] entries grouped under a span
/// (see [TimelinePage.collapseGroups]): a chevron and their number, [dense]
/// to fit after the title on its bar.
class _GroupToggle extends StatelessWidget {
  const _GroupToggle({
    super.key,
    required this.count,
    required this.open,
    this.dense = false,
    this.onPressed,
  });

  /// The room it takes on a bar, with the gap before it.
  static const width = 44.0;

  final int count;
  final bool open;
  final bool dense;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final events = '$count ${count == 1 ? 'entry' : 'entries'}';
    return Tooltip(
      message: open ? 'Hide $events' : 'Show $events',
      child: Material(
        color: open ? scheme.secondaryContainer : scheme.surfaceContainerHigh,
        shape: StadiumBorder(
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 4 : 8,
              vertical: dense ? 0 : 4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: dense ? 14 : 18,
                ),
                Text(
                  '$count',
                  style: (dense
                      ? theme.textTheme.labelSmall
                      : theme.textTheme.labelMedium),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The days of a span across its bar: a faint mark between each two where
/// there is room, and for a counted span a stronger one between its weeks;
/// then its notes for its days, where each day has room for one, or else
/// a counted span's week numbers, each clear of the title, [skip] pixels
/// wide.
class _DaysPainter extends CustomPainter {
  _DaysPainter({
    required this.days,
    required this.counted,
    required this.notes,
    required this.skip,
    required this.color,
    required this.labelStyle,
  });

  final int days;
  final bool counted;
  final Map<int, String> notes;
  final double skip;
  final Color color;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final day = size.width / days;
    final faint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final strong = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1.5;
    for (var n = 1; n < days; n++) {
      final week = counted && n % 7 == 0;
      if (!week && day < 4) continue;
      final x = n * day;
      canvas.drawLine(
        Offset(x, week ? 2 : size.height * 0.6),
        Offset(x, size.height - 2),
        week ? strong : faint,
      );
    }
    if (notes.isNotEmpty && day >= 28) {
      for (var d = 1; d <= days; d++) {
        final note = notes[d];
        final left = (d - 1) * day;
        if (note == null || left < skip) continue;
        final painter = TextPainter(
          text: TextSpan(text: note, style: labelStyle),
          maxLines: 1,
          ellipsis: '…',
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: day - 4);
        painter.paint(
          canvas,
          Offset(
            left + (day - painter.width) / 2,
            (size.height - painter.height) / 2,
          ),
        );
      }
      return;
    }
    if (!counted) return;
    final weeks = (days + 6) ~/ 7;
    for (var w = 1; w <= weeks; w++) {
      final left = (w - 1) * 7 * day;
      final width = math.min(7, days - (w - 1) * 7) * day;
      if (left < skip) continue;
      final text = width >= 56 ? 'Week $w' : '$w';
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width + 4 > width) continue;
      painter.paint(
        canvas,
        Offset(
          left + (width - painter.width) / 2,
          (size.height - painter.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_DaysPainter old) =>
      old.days != days ||
      old.counted != counted ||
      old.notes != notes ||
      old.skip != skip ||
      old.color != color ||
      old.labelStyle != labelStyle;
}

class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.timeline,
    required this.start,
    required this.end,
    required this.x,
    required this.axisY,
    required this.width,
    required this.guides,
    this.nights = const [],
    this.moons = const [],
    required this.color,
    required this.labelStyle,
  });

  final StudyTimeline timeline;
  final double start, end, axisY, width;
  final double Function(double) x;
  final List<({double x, double top})> guides;

  /// The nights to shade, in pixels across.
  final List<({double from, double to})> nights;

  /// The new and full moons to mark above the axis, in pixels across.
  final List<({double x, bool full})> moons;
  final Color color;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    final guide = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final night = Paint()..color = color.withValues(alpha: 0.08);
    for (final n in nights) {
      canvas.drawRect(Rect.fromLTRB(n.from, 0, n.to, axisY), night);
    }
    final moonLine = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final moonFill = Paint()..color = color;
    for (final m in moons) {
      final centre = Offset(m.x, axisY - 6);
      canvas.drawCircle(centre, 3.5, m.full ? moonFill : moonLine);
    }
    for (final g in guides) {
      canvas.drawLine(Offset(g.x, g.top), Offset(g.x, axisY), guide);
    }
    canvas.drawLine(
      Offset(TimelineChart.padding / 2, axisY),
      Offset(width - TimelineChart.padding / 2, axisY),
      line,
    );
    var lastRight = double.negativeInfinity;
    for (final tick in timelineTicks(
      timeline,
      start,
      end,
      width - TimelineChart.padding * 2,
    )) {
      final tx = x(tick.position);
      canvas.drawLine(
        Offset(tx, axisY),
        Offset(tx, axisY + (tick.label.isEmpty ? 3 : 5)),
        line,
      );
      if (tick.label.isEmpty) continue;
      final lx = x(tick.labelAt);
      final painter = TextPainter(
        text: TextSpan(text: tick.label, style: labelStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (lx - painter.width / 2).clamp(0.0, width - painter.width);
      if (left < lastRight + 6) continue;
      painter.paint(canvas, Offset(left, axisY + 8));
      lastRight = left + painter.width;
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.timeline != timeline ||
      old.start != start ||
      old.end != end ||
      old.axisY != axisY ||
      old.width != width ||
      old.color != color ||
      old.guides.length != guides.length ||
      old.nights.length != nights.length ||
      old.moons.length != moons.length;
}

/// A timeline fitted to the width it is given, small and without labels but
/// for its first and last times: an outline row's glimpse of its shape.
class TimelineStrip extends StatelessWidget {
  const TimelineStrip({
    super.key,
    required this.timeline,
    required this.entries,
    this.onTap,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final VoidCallback? onTap;

  static const _lane = 8.0;
  static const _maxLanes = 5;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final extent = timelineExtent(timeline, entries);
    final first = entries
        .map((e) => e.start)
        .reduce(
          (a, b) => timeline.positionOf(a) <= timeline.positionOf(b) ? a : b,
        );
    final last = entries
        .map((e) => e.last)
        .reduce(
          (a, b) => timeline.positionOf(a) >= timeline.positionOf(b) ? a : b,
        );
    return Semantics(
      button: onTap != null,
      label: 'Open timeline',
      child: InkWell(
        key: ValueKey('timeline-strip-${timeline.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final scale = (width - 8) / (extent.end - extent.start);
              double x(double position) =>
                  4 + (position - extent.start) * scale;
              final slots = packTimelineLanes(
                timeline,
                entries,
                x: x,
                width: (e) => e.isSpan ? 3 : 6,
                gap: 2,
              );
              final lanes = math.min(
                _maxLanes,
                slots.map((s) => s.lane).reduce(math.max) + 1,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: lanes * _lane + 3,
                    child: CustomPaint(
                      painter: _StripPainter(
                        slots: [
                          for (final s in slots)
                            if (s.lane < _maxLanes) s,
                        ],
                        end: (e) => x(timelineEntryReach(timeline, e).end),
                        span: theme.colorScheme.primary,
                        event: theme.colorScheme.tertiary,
                        axis: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        timeline.formatTime(first),
                        style: theme.textTheme.labelSmall,
                      ),
                      const Spacer(),
                      if (last != first)
                        Text(
                          timeline.formatTime(last),
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.slots,
    required this.end,
    required this.span,
    required this.event,
    required this.axis,
  });

  final List<TimelineSlot> slots;

  /// Where an entry's mark ends.
  final double Function(StudyTimelineEntry) end;
  final Color span, event, axis;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()..color = axis,
    );
    for (final slot in slots) {
      final y = slot.lane * TimelineStrip._lane + 4;
      if (slot.entry.isSpan) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            slot.left,
            y - 2,
            math.max(slot.left + 3, end(slot.entry)),
            y + 2,
            const Radius.circular(2),
          ),
          Paint()..color = span.withValues(alpha: 0.7),
        );
      } else {
        canvas.drawCircle(Offset(slot.left, y), 3, Paint()..color = event);
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.slots.length != slots.length ||
      old.span != span ||
      old.event != event ||
      !Iterable.generate(slots.length).every(
        (i) =>
            old.slots[i].left == slots[i].left &&
            old.slots[i].lane == slots[i].lane &&
            old.slots[i].entry == slots[i].entry,
      );
}

/// A timeline and its entries as they stand.
typedef TimelineContents = ({
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
});

/// A link as an entry's sheet shows it (see [TimelineLink]): where it
/// leads, by the entry's title and its timeline's, and whether it was made
/// from that end ([back]).
typedef TimelineLinkView = ({
  TimelineLink link,
  String title,
  String timelineTitle,
  bool back,
});

/// What an entry's details sheet was closed to do.
enum _EntryChoice { edit, remove, duplicate, addPinned }

/// What a day's sheet in the calendar was closed to do, besides editing
/// one of its entries.
enum _DayChoice { add, addSabbath }

/// Where a pinned entry falls from its anchor: "Day 3 of Unleavened Bread",
/// "Day 50 counting from the wave sheaf", "2 days before Passover", "the
/// 1st day of the week from Day 2 of Unleavened Bread", "3 months after
/// the reign starts"; null for one not pinned, or whose anchor is not
/// among [entries].
String? timelinePinLabel(
  StudyTimeline timeline,
  StudyTimelineEntry entry,
  List<StudyTimelineEntry> entries,
) {
  final pin = entry.pin;
  if (pin == null) return null;
  final anchor = entries.where((e) => e.id == pin.anchorId).firstOrNull;
  if (anchor == null) return null;
  final amount = pin.offset.amount;
  if (!pin.isDays) {
    final unit = pin.offset.unit == TimelineDurationUnit.units
        ? timeline.unit
        : pin.offset.unit.name;
    return amount == 0
        ? 'At the start of ${anchor.title}'
        : '${formatTimelineNumber(amount)} $unit after ${anchor.title} '
              'starts';
  }
  final day = amount.round();
  final count = day >= 1
      ? anchor.isSpan
            ? 'Day $day of ${anchor.title}'
            : day == 1
            ? 'The day of ${anchor.title}'
            : 'Day $day counting from ${anchor.title}'
      : '${1 - day} day${day == 0 ? '' : 's'} before ${anchor.title}';
  final weekday = pin.weekday;
  return weekday == null
      ? count
      : 'The first ${timelineWeekdayLabel(weekday)} from '
            '${count[0].toLowerCase()}${count.substring(1)}';
}

/// The full view of a timeline: drawn to scale, zoomable and scrollable,
/// with its entries listed beneath. An entry opens its details, from which
/// its linked verses open in the reader through [onOpenPassage]. A timeline
/// with months may be shown instead as a calendar of one year at a time
/// (see [TimelineCalendar]). Given the callbacks, the timeline and its
/// entries are edited here too.
class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.timeline,
    required this.entries,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.initialSelectedId,
    this.initialCalendar = false,
    this.showInitialSelected = false,
    this.reload,
    this.onEditTimeline,
    this.onUpdateTimeline,
    this.onAddEntry,
    this.onEditEntry,
    this.onRemoveEntry,
    this.onDuplicateEntry,
    this.entryDetails,
    this.linksOf,
    this.onOpenLink,
    this.baseTitles = const {},
    this.collapseGroups = false,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final bool useEnglishBookNames;
  final ValueChanged<StudyPassage> onOpenPassage;

  /// The entry to show picked out when the page opens.
  final String? initialSelectedId;

  /// Whether to open on the calendar, where the timeline has months.
  final bool initialCalendar;

  /// Whether to open [initialSelectedId]'s details when the page opens.
  final bool showInitialSelected;

  /// Reads the timeline again after an edit; null when it is gone, which
  /// closes the page.
  final TimelineContents? Function()? reload;

  /// Edit the timeline in its editor, or save a change made here (its
  /// weekdays); add an event or (`span` true) a span to it, starting [at] a
  /// day where one is chosen, or a high Sabbath ([sabbath] true) on one,
  /// or an event pinned to the entry [anchor]; edit, remove or duplicate
  /// an entry, a copy to set beside it another reading of its time. The
  /// page reads the timeline again after each. Without them the page only
  /// shows the timeline.
  final Future<void> Function()? onEditTimeline;
  final Future<void> Function(StudyTimeline timeline)? onUpdateTimeline;
  final Future<void> Function(
    bool span,
    TimelineTime? at, {
    bool sabbath,
    StudyTimelineEntry? anchor,
  })?
  onAddEntry;
  final Future<void> Function(StudyTimelineEntry entry)? onEditEntry;
  final Future<void> Function(StudyTimelineEntry entry)? onRemoveEntry;
  final Future<void> Function(StudyTimelineEntry entry)? onDuplicateEntry;

  /// The links an entry has to entries on other timelines (or its own), and
  /// they to it, shown in its details; and how one opens, its timeline
  /// opened on its entry.
  final List<TimelineLinkView> Function(StudyTimelineEntry entry)? linksOf;
  final ValueChanged<TimelineLink>? onOpenLink;

  /// The titles of the timelines it is built on, by id: their entries are
  /// among [entries], shown faded beneath its own and not edited here.
  final Map<String, String> baseTitles;

  /// Whether the entries pinned to a span start collapsed beneath it in the
  /// chart and the list, shown when it is opened; each group can be opened
  /// or closed either way.
  final bool collapseGroups;

  /// More about an entry, shown in its details beneath its verses.
  final Widget Function(BuildContext sheetContext, StudyTimelineEntry entry)?
  entryDetails;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  /// Null until fitted to the entries on the first layout.
  double? _pixelsPerUnit;

  /// Whether a touch drag across the chart picks a stretch to zoom into,
  /// rather than scrolling; a mouse drag always does.
  bool _selecting = false;

  /// The stretch being dragged across the chart, in its pixels.
  ({double from, double to})? _drag;
  late String? _selectedId = widget.initialSelectedId;
  late StudyTimeline _timeline = widget.timeline;
  late List<StudyTimelineEntry> _entries = widget.entries;
  late bool _calendar = widget.initialCalendar && widget.timeline.hasMonths;

  /// Whether the year is shown as a wheel (see [TimelineWheel]), rather
  /// than the timeline or the calendar.
  bool _wheel = false;

  bool get _chart => !_calendar && !_wheel;

  /// The entries of the timelines it is built on, drawn faded.
  Set<String> get _faded => {
    for (final e in _entries)
      if (e.timelineId != _timeline.id) e.id,
  };

  /// The categories whose entries are hidden from every view.
  final _hidden = <String>{};

  /// Whether the groups of entries pinned to spans start collapsed, and
  /// the spans whose groups are turned the other way.
  late bool _collapsed = widget.collapseGroups;
  final _toggled = <String>{};

  bool _isOpen(String spanId) => _collapsed == _toggled.contains(spanId);

  void _toggleGroup(StudyTimelineEntry span) => setState(() {
    if (!_toggled.remove(span.id)) _toggled.add(span.id);
  });

  /// Opens or closes every group.
  void _setAllGroups({required bool open}) => setState(() {
    _collapsed = !open;
    _toggled.clear();
  });

  /// The span [entry] is grouped under: the one it is pinned to, among
  /// [byId], unless its category is hidden.
  StudyTimelineEntry? _groupOf(
    StudyTimelineEntry entry,
    Map<String, StudyTimelineEntry> byId,
  ) {
    final anchor = byId[entry.pin?.anchorId];
    return anchor != null &&
            anchor.isSpan &&
            anchor.id != entry.id &&
            !_hidden.contains(anchor.category)
        ? anchor
        : null;
  }

  /// [entries] (those of categories shown) as the chart and list show
  /// them: each beneath the span it is grouped under, at [depth] from the
  /// top, left out where a group over it is collapsed; and the entries
  /// grouped under each span, by its id.
  ({
    List<({StudyTimelineEntry entry, int depth})> rows,
    Map<String, int> groupSizes,
  })
  _grouped(List<StudyTimelineEntry> entries) {
    final byId = {for (final e in entries) e.id: e};
    final children = <String, List<StudyTimelineEntry>>{};
    final top = <StudyTimelineEntry>[];
    // Groups pinned round in a ring are left at the top.
    bool inRing(StudyTimelineEntry entry) {
      final seen = {entry.id};
      for (var g = _groupOf(entry, byId); g != null; g = _groupOf(g, byId)) {
        if (!seen.add(g.id)) return g.id == entry.id;
      }
      return false;
    }

    for (final entry in entries) {
      final group = _groupOf(entry, byId);
      if (group == null || inRing(entry)) {
        top.add(entry);
      } else {
        (children[group.id] ??= []).add(entry);
      }
    }
    final rows = <({StudyTimelineEntry entry, int depth})>[];
    final seen = <String>{};
    void add(StudyTimelineEntry entry, int depth) {
      if (!seen.add(entry.id)) return;
      rows.add((entry: entry, depth: depth));
      if (!_isOpen(entry.id)) return;
      for (final child in children[entry.id] ?? const <StudyTimelineEntry>[]) {
        add(child, depth + 1);
      }
    }

    for (final entry in top) {
      add(entry, 0);
    }
    return (
      rows: rows,
      groupSizes: {
        for (final MapEntry(:key, :value) in children.entries)
          key: value.length,
      },
    );
  }

  /// What a row of the list ends with: for a span with entries grouped
  /// under it, [grouped] of them, its button to open or close them; and,
  /// where it can be edited here, its button to edit it. Null for neither.
  Widget? _rowActions(StudyTimelineEntry entry, int? grouped) {
    final edit = entry.timelineId == _timeline.id ? widget.onEditEntry : null;
    final actions = [
      if (grouped != null)
        _GroupToggle(
          key: ValueKey('timeline-group-row-${entry.id}'),
          count: grouped,
          open: _isOpen(entry.id),
          onPressed: () => _toggleGroup(entry),
        ),
      if (edit != null)
        IconButton(
          tooltip: entry.isSpan ? 'Edit span' : 'Edit event',
          icon: const Icon(Icons.edit_note),
          onPressed: () => _edit(() => edit(entry)),
        ),
    ];
    return switch (actions) {
      [] => null,
      [final only] => only,
      _ => Row(mainAxisSize: MainAxisSize.min, children: actions),
    };
  }

  /// Opens the groups over [entry], so that it shows.
  void _reveal(StudyTimelineEntry entry) {
    final byId = {for (final e in _entries) e.id: e};
    var group = _groupOf(entry, byId);
    final seen = <String>{};
    while (group != null && seen.add(group.id)) {
      if (!_isOpen(group.id)) {
        if (!_toggled.remove(group.id)) _toggled.add(group.id);
      }
      group = _groupOf(group, byId);
    }
  }

  /// Shows the timeline drawn to scale, fitted again to its entries; the
  /// calendar ([calendar] true); or the year's wheel ([wheel] true).
  void _showView({bool calendar = false, bool wheel = false}) => setState(() {
    _calendar = calendar;
    _wheel = wheel;
    _pixelsPerUnit = null;
  });
  late double _year = _firstYear();
  TimelineTime? _selectedDay;
  final _horizontal = ScrollController();

  /// The year the calendar opens on: the one its weeks are counted from,
  /// else the first entry's; none on one year's calendar.
  double _firstYear() {
    final timeline = widget.timeline;
    if (timeline.isAnnual) return 0;
    final entries = List.of(widget.entries)..sort(compareTimelineEntries);
    final year =
        timeline.weekYear ?? entries.firstOrNull?.start.value.roundToDouble();
    return year ?? (timeline.isCalendar ? -1 : 1);
  }

  @override
  void initState() {
    super.initState();
    final id = widget.initialSelectedId;
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry != null) _reveal(entry);
    if (!widget.showInitialSelected || entry == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _show(entry);
    });
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  /// Runs an edit, then shows the timeline as it now stands, or closes the
  /// page when the timeline is gone.
  Future<void> _edit(Future<void> Function() edit) async {
    await edit();
    final reload = widget.reload;
    if (!mounted || reload == null) return;
    final contents = reload();
    if (contents == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _timeline = contents.timeline;
      _entries = contents.entries;
      if (!_entries.any((e) => e.id == _selectedId)) _selectedId = null;
    });
  }

  /// The scale fitting the stretch [window] into [width], leaving room
  /// after it, where [label] is set, for a label of its own (up to a third
  /// of the width).
  double _scaleFor(
    ({double start, double end}) window,
    double width, {
    bool label = true,
  }) {
    final room = label ? math.min(width / 3, 140.0) : 0.0;
    return math.max(
      1e-6,
      (width - TimelineChart.padding * 2 - room) / (window.end - window.start),
    );
  }

  /// The least scale zoomed out to: a quarter of the whole drawn timeline's
  /// fitted into [width].
  double _minScale(double width) =>
      _scaleFor(timelineExtent(_timeline, _entries), width) / 4;

  /// Zooms to the scale fitting [window] into [viewport], scrolled to it.
  void _fitTo(
    ({double start, double end}) window,
    double viewport, {
    bool label = true,
  }) {
    final next = _scaleFor(
      window,
      viewport,
      label: label,
    ).clamp(_minScale(viewport), 1e6);
    final extent = timelineExtent(_timeline, _entries);
    setState(() => _pixelsPerUnit = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients) return;
      final offset = (window.start - extent.start) * next;
      _horizontal.jumpTo(
        offset.clamp(0.0, _horizontal.position.maxScrollExtent),
      );
    });
  }

  /// Zooms to fit the timeline's entries into [viewport], not the whole of
  /// one year's calendar.
  void _fitEntries(double viewport) =>
      _fitTo(timelineFocus(_timeline, _entries), viewport);

  void _zoom(double factor, double viewport) {
    final current =
        _pixelsPerUnit ??
        _scaleFor(timelineFocus(_timeline, _entries), viewport);
    // Keep the time at the middle of the view where it is.
    final middle =
        (_horizontal.hasClients ? _horizontal.offset : 0) + viewport / 2;
    final time = (middle - TimelineChart.padding) / current;
    final next = (current * factor).clamp(_minScale(viewport), 1e6);
    setState(() => _pixelsPerUnit = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients) return;
      final offset = time * next + TimelineChart.padding - viewport / 2;
      _horizontal.jumpTo(
        offset.clamp(0.0, _horizontal.position.maxScrollExtent),
      );
    });
  }

  /// Zooms into the stretch dragged across the chart drawn at [ppu], as
  /// long as it is wider than a few pixels.
  void _zoomToDrag(double ppu, double viewport) {
    final drag = _drag;
    setState(() {
      _drag = null;
      _selecting = false;
    });
    if (drag == null || (drag.to - drag.from).abs() < 8) return;
    final extent = timelineExtent(_timeline, _entries);
    double at(double x) => extent.start + (x - TimelineChart.padding) / ppu;
    final from = at(math.min(drag.from, drag.to));
    final to = at(math.max(drag.from, drag.to));
    _fitTo((start: from, end: to), viewport, label: false);
  }

  /// [body] beneath a key to the categories of the timeline's entries,
  /// where they have any: each in its colour, shown or hidden by a tap, its
  /// colour changed from its palette button.
  Widget _withCategories(ThemeData theme, Widget body) {
    final categories = {
      for (final e in _entries)
        if (e.category.isNotEmpty) e.category,
    }.toList()..sort();
    if (categories.isEmpty) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final category in categories)
                InputChip(
                  key: ValueKey('timeline-category-$category'),
                  label: Text(category),
                  selected: !_hidden.contains(category),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(
                    backgroundColor:
                        switch (_timeline.categoryColors[category]) {
                          final index? => timelineCategoryColor(
                            index,
                            theme.brightness,
                          ),
                          null => theme.colorScheme.outline,
                        },
                  ),
                  tooltip: _hidden.contains(category)
                      ? 'Show $category'
                      : 'Hide $category',
                  onSelected: (shown) => setState(() {
                    if (shown) {
                      _hidden.remove(category);
                    } else {
                      _hidden.add(category);
                    }
                  }),
                  deleteIcon: const Icon(Icons.palette_outlined, size: 18),
                  deleteButtonTooltipMessage: 'Colour $category',
                  onDeleted: () => _recolor(category),
                ),
            ],
          ),
        ),
        Expanded(child: body),
      ],
    );
  }

  /// Picks a colour for [category] from the palette, kept with the
  /// timeline where it can be saved.
  Future<void> _recolor(String category) async {
    final current = _timeline.categoryColors[category];
    final brightness = Theme.of(context).brightness;
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Colour for $category'),
        contentPadding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (i, (name, _, _)) in timelineCategoryPalette.indexed)
                Tooltip(
                  message: name,
                  child: InkWell(
                    key: ValueKey('timeline-color-$i'),
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(dialogContext, i),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: timelineCategoryColor(i, brightness),
                      child: i == current
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    if (picked == null || picked == current || !mounted) return;
    final changed = _timeline.copyWith(
      categoryColors: {..._timeline.categoryColors, category: picked},
    );
    setState(() => _timeline = changed);
    final update = widget.onUpdateTimeline;
    if (update != null) await _edit(() => update(changed));
  }

  /// The controls over the chart: zoom out, fit to the entries, pick a
  /// stretch to zoom into by dragging, and zoom in.
  Widget _zoomBar(double viewport) {
    Widget button(
      String tooltip,
      IconData icon,
      VoidCallback onPressed, {
      bool? selected,
    }) => IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      isSelected: selected,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('Zoom out', Icons.zoom_out, () => _zoom(1 / 1.5, viewport)),
          button(
            'Fit to entries',
            Icons.fit_screen_outlined,
            () => _fitEntries(viewport),
          ),
          button(
            'Drag across the timeline to zoom in',
            Icons.highlight_alt,
            () => setState(() => _selecting = !_selecting),
            selected: _selecting,
          ),
          button('Zoom in', Icons.zoom_in, () => _zoom(1.5, viewport)),
        ],
      ),
    );
  }

  /// Shows or hides the seasons of the land, kept with the timeline where
  /// it can be saved.
  void _toggleSeasons() {
    final changed = _timeline.copyWith(showSeasons: !_timeline.showSeasons);
    setState(() => _timeline = changed);
    final update = widget.onUpdateTimeline;
    if (update != null) _edit(() => update(changed));
  }

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: widget.useEnglishBookNames)} '
      '${passage.reference}';

  /// Where [day] falls in each counted span over it: "Day 23 of the
  /// count: week 4, day 2". [except] leaves out a span's own.
  List<String> _counts(TimelineTime day, {String? except}) => [
    for (final span in _entries)
      if (span.id != except)
        if (_timeline.countIn(span, day) case final c?)
          'Day ${c.day} of ${span.title}: week ${c.week}, day ${c.dayOfWeek}',
  ];

  /// The notes the spans over [day] have for it: "Tabernacles, day 3: 11
  /// bulls". [except] leaves out a span's own.
  List<String> _notesOn(TimelineTime day, {String? except}) => [
    for (final span in _entries)
      if (span.id != except && span.dayNotes.isNotEmpty)
        if (_timeline.dayIn(span, day) case final n?)
          if (span.dayNotes[n] case final note?) '${span.title}, day $n: $note',
  ];

  /// A span's notes for its days, each with its date; where they begin
  /// with numbers, each with a bar to its number, so that a count rising
  /// or falling day by day shows.
  Widget _dayNotes(ThemeData theme, StudyTimelineEntry span) {
    final days = _timeline.daysIn(span) ?? 0;
    final number = RegExp(r'^\s*(\d+(?:\.\d+)?)');
    final numbers = {
      for (final MapEntry(:key, :value) in span.dayNotes.entries)
        if (number.firstMatch(value) case final match?)
          key: double.parse(match.group(1)!),
    };
    final most = numbers.values.fold(0.0, math.max);
    final color = timelineEntryColor(
      _timeline,
      span,
      theme.brightness,
      theme.colorScheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Day by day', style: theme.textTheme.labelLarge),
          for (var d = 1; d <= days; d++)
            if (span.dayNotes[d] case final note?)
              Padding(
                key: ValueKey('timeline-day-note-$d'),
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 116,
                      child: Text(
                        [
                          'Day $d',
                          if (_timeline.addDays(span.start, d - 1)
                              case final date?)
                            _timeline.formatTime(date),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(note, style: theme.textTheme.bodyMedium),
                          if (numbers[d] case final n? when most > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: n / most,
                                child: Container(
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// A counted span's length in days and in weeks: "50 days: 7 weeks and
  /// 1 day"; null for one not counted.
  String? _countedLength(StudyTimelineEntry span) {
    final days = span.isCounted ? _timeline.daysIn(span) : null;
    if (days == null) return null;
    final weeks = days ~/ 7;
    final rest = days % 7;
    final parts = [
      if (weeks > 0) '$weeks week${weeks == 1 ? '' : 's'}',
      if (rest > 0) '$rest day${rest == 1 ? '' : 's'}',
    ];
    return 'Counted, $days day${days == 1 ? '' : 's'}: ${parts.join(' and ')}';
  }

  Future<void> _show(StudyTimelineEntry entry) async {
    setState(() {
      _selectedId = entry.id;
      _reveal(entry);
    });
    // One of a timeline it is built on is changed there, not here.
    final own = entry.timelineId == _timeline.id;
    final edit = own ? widget.onEditEntry : null;
    final remove = own ? widget.onRemoveEntry : null;
    final add = widget.onAddEntry;
    final duplicate = own ? widget.onDuplicateEntry : null;
    final links = widget.linksOf?.call(entry) ?? const [];
    final open = widget.onOpenLink;
    final pin = timelinePinLabel(_timeline, entry, _entries);
    final pinned = [
      for (final e in List.of(_entries)..sort(compareTimelineEntries))
        if (e.pin?.anchorId == entry.id) e,
    ];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: theme.textTheme.titleLarge),
                if (!own)
                  Text(
                    'From ${widget.baseTitles[entry.timelineId] ?? 'the timeline it is built on'}',
                    key: const ValueKey('timeline-entry-from-base'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  [timelineEntryTime(_timeline, entry), ?pin].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final line in [
                  ?_countedLength(entry),
                  if (entry.start.day != null) ...[
                    ..._counts(entry.start, except: entry.id),
                    ..._notesOn(entry.start, except: entry.id),
                  ],
                ])
                  Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  MarkdownNote(entry.note),
                ],
                if (entry.verses.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final passage in entry.verses)
                        ActionChip(
                          avatar: const Icon(Icons.menu_book_outlined),
                          label: Text(_reference(passage)),
                          onPressed: () => Navigator.pop(sheetContext, passage),
                        ),
                    ],
                  ),
                ],
                if (entry.dayNotes.isNotEmpty) _dayNotes(theme, entry),
                if (links.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Linked', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final view in links)
                        ActionChip(
                          key: ValueKey(
                            'timeline-link-${view.link.timelineId}-'
                            '${view.link.entryId}',
                          ),
                          avatar: Icon(
                            view.back ? Icons.call_received : Icons.link,
                          ),
                          label: Text('${view.title} · ${view.timelineTitle}'),
                          tooltip: view.back
                              ? 'Links here from ${view.timelineTitle}'
                              : null,
                          onPressed: open == null
                              ? null
                              : () => Navigator.pop(sheetContext, view.link),
                        ),
                    ],
                  ),
                ],
                if (widget.entryDetails case final details?)
                  details(sheetContext, entry),
                // The entries pinned to it, each opening its own details.
                if (pinned.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final e in pinned)
                    ListTile(
                      key: ValueKey('timeline-pinned-${e.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(timelineEntryIcon(e)),
                      title: Text(e.title),
                      subtitle: Text(
                        timelinePinLabel(_timeline, e, _entries) ?? '',
                      ),
                      onTap: () => Navigator.pop(sheetContext, e),
                    ),
                ],
                if (edit != null ||
                    remove != null ||
                    add != null ||
                    duplicate != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    children: [
                      if (edit != null)
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pop(sheetContext, _EntryChoice.edit),
                          icon: const Icon(Icons.edit_note),
                          label: Text(
                            entry.isSpan ? 'Edit span' : 'Edit event',
                          ),
                        ),
                      if (remove != null)
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pop(sheetContext, _EntryChoice.remove),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove'),
                        ),
                      if (duplicate != null)
                        TextButton.icon(
                          key: const ValueKey('timeline-duplicate'),
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            _EntryChoice.duplicate,
                          ),
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Duplicate'),
                        ),
                      if (add != null)
                        TextButton.icon(
                          key: const ValueKey('timeline-add-pinned'),
                          onPressed: () => Navigator.pop(
                            sheetContext,
                            _EntryChoice.addPinned,
                          ),
                          icon: const Icon(Icons.push_pin_outlined),
                          label: Text(
                            entry.isSpan
                                ? 'Add event in this span'
                                : 'Add event counted from this',
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case StudyPassage passage:
        Navigator.pop(context);
        widget.onOpenPassage(passage);
      case _EntryChoice.edit:
        await _edit(() => edit!(entry));
      case _EntryChoice.remove:
        await _edit(() => remove!(entry));
      case _EntryChoice.duplicate:
        await _edit(() => duplicate!(entry));
      case _EntryChoice.addPinned:
        await _edit(() => add!(false, null, anchor: entry));
      case StudyTimelineEntry pinned:
        await _show(pinned);
      case TimelineLink link:
        open?.call(link);
    }
  }

  /// The width the chart was last laid out in, to zoom within.
  double _viewport = 0;

  /// A run of events drawn as one mark (see [TimelineChart.onTapCluster]):
  /// each listed, opening its details, and a way to zoom in until they
  /// stand apart.
  Future<void> _showCluster(List<StudyTimelineEntry> events) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${events.length} events',
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  [
                    timelineEntryTime(_timeline, events.first),
                    if (events.last.start != events.first.start)
                      timelineEntryTime(_timeline, events.last),
                  ].join(' – '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('timeline-cluster-zoom'),
                  onPressed: () => Navigator.pop(sheetContext, true),
                  icon: const Icon(Icons.zoom_in),
                  label: const Text('Zoom in to these'),
                ),
                for (final e in events)
                  ListTile(
                    key: ValueKey('timeline-cluster-row-${e.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      timelineEntryIcon(e),
                      color: timelineEntryColor(
                        _timeline,
                        e,
                        theme.brightness,
                        theme.colorScheme.tertiary,
                      ),
                    ),
                    title: Text(e.title),
                    subtitle: Text(timelineEntryTime(_timeline, e)),
                    onTap: () => Navigator.pop(sheetContext, e),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case StudyTimelineEntry entry:
        await _show(entry);
      case true:
        // Wide enough that a dot and a gap between each two fit.
        final reaches = [
          for (final e in events) timelineEntryReach(_timeline, e).start,
        ];
        final from = reaches.reduce(math.min);
        final to = reaches.reduce(math.max);
        final margin = math.max(
          (to - from) / 2,
          _timeline.hasMonths ? 15 / 354 : 0.5,
        );
        _fitTo((start: from - margin, end: to + margin), _viewport);
    }
  }

  /// A day of the calendar: its entries (among them any high Sabbath), and,
  /// given the callbacks, ways to keep it as a high Sabbath, an event of its
  /// own with a title and notes, or to add another event on it.
  Future<void> _showDay(TimelineTime day) async {
    setState(() => _selectedDay = day);
    final timeline = _timeline;
    final position = timeline.positionOf(day);
    final entries = [
      for (final entry in List.of(_entries)..sort(compareTimelineEntries))
        if (timelineEntryDays(timeline, entry) case final days
            when position >= days.first - 1e-9 && position <= days.last + 1e-9)
          entry,
    ];
    final add = widget.onAddEntry;
    final high = timeline.highSabbathsOn(entries, day).isNotEmpty;
    final weekday = timeline.weekdayOf(day);
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeline.formatTime(day),
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  high
                      ? 'Shabbaton · ${timelineWeekdayName(weekday)}'
                      : timelineWeekdayName(weekday),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                for (final line in [..._counts(day), ..._notesOn(day)])
                  Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                const SizedBox(height: 8),
                for (final entry in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(timelineEntryIcon(entry)),
                    title: Text(entry.title),
                    subtitle: Text(
                      [
                        timelineEntryTime(timeline, entry),
                        if (entry.note.isNotEmpty)
                          markdownPlainText(entry.note),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(sheetContext, entry),
                  ),
                if (add != null && !high)
                  TextButton.icon(
                    key: const ValueKey('calendar-high-sabbath'),
                    onPressed: () =>
                        Navigator.pop(sheetContext, _DayChoice.addSabbath),
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Keep as a shabbaton'),
                  ),
                if (add != null)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(sheetContext, _DayChoice.add),
                    icon: const Icon(Icons.add),
                    label: const Text('Add event on this day'),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (choice) {
      case StudyTimelineEntry entry:
        if (widget.onEditEntry case final edit?) {
          await _edit(() => edit(entry));
        } else {
          await _show(entry);
        }
      case _DayChoice.add:
        await _edit(() => add!(false, day));
      case _DayChoice.addSabbath:
        await _edit(() => add!(false, day, sabbath: true));
    }
  }

  /// The bar above the calendar: the year shown, and which day of the week
  /// 1 Nisan falls on that year.
  Widget _calendarBar(ThemeData theme) {
    final timeline = _timeline;
    final update = widget.onUpdateTimeline;
    final nisan1 = TimelineTime(_year, month: 1, day: 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          if (timeline.countsYears)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Previous year',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                    () => _year = timeline.nextYear(_year, step: -1),
                  ),
                ),
                Text(
                  timeline.formatValue(_year),
                  key: const ValueKey('calendar-year'),
                  style: theme.textTheme.titleMedium,
                ),
                IconButton(
                  tooltip: 'Next year',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      setState(() => _year = timeline.nextYear(_year)),
                ),
              ],
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${timeline.formatDate(_year, 1, 1)} falls on',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                key: ValueKey('calendar-nisan-weekday-$_year'),
                value: timeline.weekdayOf(nisan1),
                items: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    DropdownMenuItem(
                      value: weekday,
                      child: Text(timelineWeekdayName(weekday)),
                    ),
                ],
                onChanged: update == null
                    ? null
                    : (weekday) {
                        if (weekday == null) return;
                        // Counting years, the weeks run on from this year.
                        _edit(
                          () => update(
                            timeline.copyWith(
                              nisanWeekday: weekday,
                              weekYear: () =>
                                  timeline.countsYears ? _year : null,
                            ),
                          ),
                        );
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Those of a category hidden are left out of every view.
    final entries = [
      for (final e in _entries)
        if (!_hidden.contains(e.category)) e,
    ]..sort(compareTimelineEntries);
    // The chart and list leave out those under a collapsed span.
    final grouped = _grouped(entries);
    final shown = [for (final row in grouped.rows) row.entry];
    final groups = grouped.groupSizes;
    final add = widget.onAddEntry;
    final editTimeline = widget.onEditTimeline;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = _viewport = constraints.maxWidth;
        final focus = timelineFocus(_timeline, entries);
        final ppu = _pixelsPerUnit ?? _scaleFor(focus, viewport);
        // Fitted first to the entries, scrolled to them on one year's
        // calendar, which is drawn whole.
        if (_pixelsPerUnit == null && _chart && entries.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pixelsPerUnit == null) _fitEntries(viewport);
          });
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _timeline.year == null
                  ? _timeline.title
                  : '${_timeline.title} · ${formatEraYear(_timeline.year!)}',
            ),
            actions: [
              if (_timeline.hasMonths)
                IconButton(
                  tooltip: _timeline.showSeasons
                      ? 'Hide seasons'
                      : 'Show seasons',
                  isSelected: _timeline.showSeasons,
                  icon: const Icon(Icons.eco_outlined),
                  selectedIcon: const Icon(Icons.eco),
                  onPressed: _toggleSeasons,
                ),
              if (_timeline.hasMonths) ...[
                if (!_chart)
                  IconButton(
                    tooltip: 'Show timeline',
                    icon: const Icon(Icons.timeline),
                    onPressed: _showView,
                  ),
                if (!_calendar)
                  IconButton(
                    tooltip: 'Show calendar',
                    icon: const Icon(Icons.calendar_month_outlined),
                    onPressed: () => _showView(calendar: true),
                  ),
                if (!_wheel)
                  IconButton(
                    tooltip: 'Show year wheel',
                    icon: const Icon(Icons.donut_large),
                    onPressed: () => _showView(wheel: true),
                  ),
              ],
              if (_chart && groups.isNotEmpty)
                if (groups.keys.any((id) => !_isOpen(id)))
                  IconButton(
                    key: const ValueKey('timeline-expand-all'),
                    tooltip: 'Expand all spans',
                    icon: const Icon(Icons.unfold_more),
                    onPressed: () => _setAllGroups(open: true),
                  )
                else
                  IconButton(
                    key: const ValueKey('timeline-collapse-all'),
                    tooltip: 'Collapse all spans',
                    icon: const Icon(Icons.unfold_less),
                    onPressed: () => _setAllGroups(open: false),
                  ),
              if (add != null)
                PopupMenuButton<bool>(
                  tooltip: 'Add to timeline',
                  icon: const Icon(Icons.add),
                  onSelected: (span) => _edit(() => add(span, null)),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: false,
                      child: ListTile(
                        leading: Icon(Icons.radio_button_checked),
                        title: Text('Add event'),
                      ),
                    ),
                    PopupMenuItem(
                      value: true,
                      child: ListTile(
                        leading: Icon(Icons.linear_scale),
                        title: Text('Add span'),
                      ),
                    ),
                  ],
                ),
              if (editTimeline != null)
                IconButton(
                  tooltip: 'Edit timeline',
                  icon: const Icon(Icons.edit_note),
                  onPressed: () => _edit(editTimeline),
                ),
            ],
          ),
          body: _withCategories(
            theme,
            _wheel && _timeline.hasMonths
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _calendarBar(theme),
                      Expanded(
                        child: TimelineWheel(
                          timeline: _timeline,
                          entries: entries,
                          year: _year,
                          selectedId: _selectedId,
                          faded: _faded,
                          onTapEntry: _show,
                        ),
                      ),
                    ],
                  )
                : _calendar && _timeline.hasMonths
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _calendarBar(theme),
                      Expanded(
                        child: TimelineCalendar(
                          timeline: _timeline,
                          entries: entries,
                          year: _year,
                          selected: _selectedDay,
                          faded: _faded,
                          onTapDay: _showDay,
                        ),
                      ),
                    ],
                  )
                : entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        add == null
                            ? 'Add events and spans to this timeline from its '
                                  'menu in the outline, or from a verse in the '
                                  'reader.'
                            : 'Add events and spans with the + above, or from a '
                                  'verse in the reader.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: constraints.maxHeight * 0.55,
                        ),
                        child: Stack(
                          children: [
                            Scrollbar(
                              controller: _horizontal,
                              child: SingleChildScrollView(
                                controller: _horizontal,
                                scrollDirection: Axis.horizontal,
                                // Picking a stretch, a touch drag is the pick's.
                                physics: _selecting
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                // Room above for the controls over the chart.
                                padding: const EdgeInsets.only(top: 48),
                                child: SingleChildScrollView(
                                  child: GestureDetector(
                                    key: const ValueKey('timeline-drag-zoom'),
                                    // A mouse drag doesn't scroll, so always picks.
                                    supportedDevices: _selecting
                                        ? null
                                        : const {PointerDeviceKind.mouse},
                                    dragStartBehavior: DragStartBehavior.down,
                                    onHorizontalDragStart: (d) => setState(
                                      () => _drag = (
                                        from: d.localPosition.dx,
                                        to: d.localPosition.dx,
                                      ),
                                    ),
                                    onHorizontalDragUpdate: (d) => setState(
                                      () => _drag = (
                                        from: _drag?.from ?? d.localPosition.dx,
                                        to: d.localPosition.dx,
                                      ),
                                    ),
                                    onHorizontalDragEnd: (_) =>
                                        _zoomToDrag(ppu, viewport),
                                    onHorizontalDragCancel: () =>
                                        setState(() => _drag = null),
                                    child: Stack(
                                      children: [
                                        TimelineChart(
                                          timeline: _timeline,
                                          entries: shown,
                                          pixelsPerUnit: ppu,
                                          seasons: _timeline.showSeasons,
                                          faded: _faded,
                                          selectedId: _selectedId,
                                          onTapEntry: _show,
                                          groups: {
                                            for (final MapEntry(:key, :value)
                                                in groups.entries)
                                              key: (
                                                count: value,
                                                open: _isOpen(key),
                                              ),
                                          },
                                          onToggleGroup: _toggleGroup,
                                          onTapCluster: _showCluster,
                                        ),
                                        if (_drag case final drag?)
                                          Positioned(
                                            left: math.min(drag.from, drag.to),
                                            width: (drag.to - drag.from).abs(),
                                            top: 0,
                                            bottom: 0,
                                            child: IgnorePointer(
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: theme
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.12),
                                                  border: Border.symmetric(
                                                    vertical: BorderSide(
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 8,
                              child: _zoomBar(viewport),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          children: [
                            if (_timeline.note.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: MarkdownNote(_timeline.note),
                              ),
                            for (final (:entry, :depth) in grouped.rows)
                              ListTile(
                                key: ValueKey('timeline-row-${entry.id}'),
                                selected: entry.id == _selectedId,
                                // Those grouped under a span set in beneath it.
                                contentPadding: EdgeInsetsDirectional.only(
                                  start: 16.0 + 24 * math.min(depth, 4),
                                  end: 16,
                                ),
                                leading: Icon(
                                  timelineEntryIcon(entry),
                                  color: timelineEntryColor(
                                    _timeline,
                                    entry,
                                    theme.brightness,
                                    entry.isSpan
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.tertiary,
                                  ),
                                ),
                                title: Text(entry.title),
                                subtitle: Text(
                                  [
                                    timelineEntryTime(_timeline, entry),
                                    ?timelinePinLabel(
                                      _timeline,
                                      entry,
                                      _entries,
                                    ),
                                    ...entry.verses.map(_reference),
                                    if (widget.baseTitles[entry.timelineId]
                                        case final base?)
                                      'from $base',
                                  ].join(' · '),
                                ),
                                onTap: () => _show(entry),
                                trailing: _rowActions(entry, groups[entry.id]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
