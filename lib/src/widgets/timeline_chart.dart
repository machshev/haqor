import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// The stretch of a timeline's axis its entries cover (as positions, see
/// [StudyTimeline.positionOf]), with a margin either side; a single point
/// gets one unit either side.
({double start, double end}) timelineExtent(
  StudyTimeline timeline,
  List<StudyTimelineEntry> entries,
) {
  if (entries.isEmpty) return (start: 0, end: 1);
  final start = entries
      .map((e) => timeline.positionOf(e.start))
      .reduce(math.min);
  final end = entries.map((e) => timeline.positionOf(e.last)).reduce(math.max);
  if (end - start < 1e-9) return (start: start - 1, end: end + 1);
  final margin = (end - start) * 0.04;
  return (start: start - margin, end: end + margin);
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
/// the first lane free [gap] before it. [x] places a time; [width] is the
/// least room an entry's mark and label take from its start.
List<TimelineSlot> packTimelineLanes(
  List<StudyTimelineEntry> entries, {
  required double Function(TimelineTime time) x,
  required double Function(StudyTimelineEntry entry) width,
  double gap = 8,
}) {
  final laneEnds = <double>[];
  final slots = <TimelineSlot>[];
  for (final entry in List.of(entries)..sort(compareTimelineEntries)) {
    final left = x(entry.start);
    final right = math.max(x(entry.last), left + width(entry));
    var lane = laneEnds.indexWhere((end) => end + gap <= left);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(right);
    } else {
      laneEnds[lane] = right;
    }
    slots.add((entry: entry, lane: lane, left: left, right: right));
  }
  return slots;
}

/// A marked time on an axis: where it falls, and how it reads.
typedef TimelineTick = ({double position, String label});

/// Round times between the axis positions [start] and [end] of [timeline]
/// to mark on an axis [pixels] wide, about [spacing] pixels apart: steps of
/// 1, 2 or 5 times a power of ten (whole years, where it counts years, and
/// no year zero counting by era), or, zoomed in within a year, its months.
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
  // Months are marked only where at least two fit in a year.
  if (timeline.countsYears && rough <= 0.5) {
    final step = [1, 2, 3, 6].firstWhere((m) => m / 12 >= rough);
    return [
      for (var year = start.floor(); year <= end.ceil(); year++)
        for (var month = 1; month <= 12; month += step)
          if (TimelineTime(written(year.toDouble()), month: month)
              case final time
              when timeline.positionOf(time) >= start &&
                  timeline.positionOf(time) <= end)
            (
              position: timeline.positionOf(time),
              label: month == 1
                  ? timeline.formatTime(time)
                  : hebrewMonthNames[month - 1],
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
          label: timeline.formatValue(value),
        ),
  ];
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

/// How an entry's time reads: its date as written, or else its time on the
/// timeline's scale, a span's from start to end.
String timelineEntryTime(StudyTimeline timeline, StudyTimelineEntry entry) {
  final duration = entry.duration;
  final time = entry.isSpan
      ? '${timeline.formatTime(entry.start)} – '
            '${timeline.formatTime(entry.end!)}'
            '${duration == null ? '' : ' (${timeline.formatDuration(duration)})'}'
      : timeline.formatTime(entry.start);
  return entry.date.isEmpty ? time : '${entry.date} $time';
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
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final double pixelsPerUnit;
  final ValueChanged<StudyTimelineEntry>? onTapEntry;
  final String? selectedId;

  static const padding = 24.0;
  static const laneHeight = 30.0;
  static const axisHeight = 36.0;
  static const _dot = 10.0;

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
    double x(TimelineTime time) => px(timeline.positionOf(time));
    final slots = packTimelineLanes(
      entries,
      x: x,
      width: (e) =>
          (e.isSpan ? 6 : _dot + 4) + _textWidth(e.title, labelStyle) + 4,
    );
    final lanes = slots.isEmpty
        ? 1
        : slots.map((s) => s.lane).reduce(math.max) + 1;
    // Room too for the labels running past the last time.
    final width = slots.fold(
      widthFor(timeline, entries, pixelsPerUnit),
      (width, slot) => math.max(width, slot.right + padding / 2),
    );
    final height = lanes * laneHeight + axisHeight;
    final axisY = lanes * laneHeight + 4;
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
                guides: [
                  for (final slot in slots)
                    if (!slot.entry.isSpan)
                      (
                        x: slot.left + _dot / 2,
                        top: slot.lane * laneHeight + 15,
                      ),
                ],
                color: theme.colorScheme.outline,
                labelStyle: labelStyle?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final slot in slots)
            Positioned(
              left: slot.left,
              top: slot.lane * laneHeight + 4,
              width: slot.right - slot.left,
              height: laneHeight - 8,
              child: _EntryMark(
                entry: slot.entry,
                barWidth: math.max(4, x(slot.entry.last) - x(slot.entry.start)),
                selected: slot.entry.id == selectedId,
                tooltip: timelineEntryTime(timeline, slot.entry),
                onTap: onTapEntry == null
                    ? null
                    : () => onTapEntry!(slot.entry),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryMark extends StatelessWidget {
  const _EntryMark({
    required this.entry,
    required this.barWidth,
    required this.selected,
    required this.tooltip,
    this.onTap,
  });

  final StudyTimelineEntry entry;
  final double barWidth;
  final bool selected;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: selected ? FontWeight.bold : null,
    );
    final label = Text(
      entry.title,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
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
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.primary.withValues(alpha: 0.5),
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: label,
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: TimelineChart._dot,
                    height: TimelineChart._dot,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.tertiary,
                      border: selected
                          ? Border.all(color: scheme.onSurface, width: 2)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(child: label),
                ],
              ),
      ),
    );
  }
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
    required this.color,
    required this.labelStyle,
  });

  final StudyTimeline timeline;
  final double start, end, axisY, width;
  final double Function(double) x;
  final List<({double x, double top})> guides;
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
      canvas.drawLine(Offset(tx, axisY), Offset(tx, axisY + 5), line);
      final painter = TextPainter(
        text: TextSpan(text: tick.label, style: labelStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (tx - painter.width / 2).clamp(0.0, width - painter.width);
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
      old.guides.length != guides.length;
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
              double x(TimelineTime time) =>
                  4 + (timeline.positionOf(time) - extent.start) * scale;
              final slots = packTimelineLanes(
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
                        x: x,
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
    required this.x,
    required this.span,
    required this.event,
    required this.axis,
  });

  final List<TimelineSlot> slots;
  final double Function(TimelineTime) x;
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
            math.max(slot.left + 3, x(slot.entry.last)),
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

/// The full view of a timeline: drawn to scale, zoomable and scrollable,
/// with its entries listed beneath. An entry opens its details, from which
/// its linked verses open in the reader through [onOpenPassage].
class TimelinePage extends StatefulWidget {
  const TimelinePage({
    super.key,
    required this.timeline,
    required this.entries,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.initialSelectedId,
  });

  final StudyTimeline timeline;
  final List<StudyTimelineEntry> entries;
  final bool useEnglishBookNames;
  final ValueChanged<StudyPassage> onOpenPassage;

  /// The entry to show picked out when the page opens.
  final String? initialSelectedId;

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
  /// Null until fitted to the screen's width on the first layout.
  double? _pixelsPerUnit;
  late String? _selectedId = widget.initialSelectedId;
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  /// The scale fitting every time into [width], leaving room after the last
  /// for a label of its own (up to a third of the width).
  double _fit(double width) {
    final extent = timelineExtent(widget.timeline, widget.entries);
    final label = math.min(width / 3, 140.0);
    return math.max(
      1e-6,
      (width - TimelineChart.padding * 2 - label) / (extent.end - extent.start),
    );
  }

  void _zoom(double factor, double viewport) {
    final current = _pixelsPerUnit ?? _fit(viewport);
    // Keep the time at the middle of the view where it is.
    final middle =
        (_horizontal.hasClients ? _horizontal.offset : 0) + viewport / 2;
    final time = (middle - TimelineChart.padding) / current;
    final next = (current * factor).clamp(_fit(viewport) / 4, 1e6);
    setState(() => _pixelsPerUnit = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients) return;
      final offset = time * next + TimelineChart.padding - viewport / 2;
      _horizontal.jumpTo(
        offset.clamp(0.0, _horizontal.position.maxScrollExtent),
      );
    });
  }

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: widget.useEnglishBookNames)} '
      '${passage.reference}';

  Future<void> _show(StudyTimelineEntry entry) async {
    setState(() => _selectedId = entry.id);
    final passage = await showModalBottomSheet<StudyPassage>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  timelineEntryTime(widget.timeline, entry),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
              ],
            ),
          ),
        );
      },
    );
    if (passage == null || !mounted) return;
    Navigator.pop(context);
    widget.onOpenPassage(passage);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = List.of(widget.entries)..sort(compareTimelineEntries);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final ppu = _pixelsPerUnit ?? _fit(viewport);
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.timeline.title),
            actions: [
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.zoom_out),
                onPressed: entries.isEmpty
                    ? null
                    : () => _zoom(1 / 1.5, viewport),
              ),
              IconButton(
                tooltip: 'Fit to width',
                icon: const Icon(Icons.fit_screen_outlined),
                onPressed: entries.isEmpty
                    ? null
                    : () => setState(() => _pixelsPerUnit = null),
              ),
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.zoom_in),
                onPressed: entries.isEmpty ? null : () => _zoom(1.5, viewport),
              ),
            ],
          ),
          body: entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Add events and spans to this timeline from its menu '
                      'in the outline, or from a verse in the reader.',
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
                      child: Scrollbar(
                        controller: _horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontal,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(top: 12),
                          child: SingleChildScrollView(
                            child: TimelineChart(
                              timeline: widget.timeline,
                              entries: entries,
                              pixelsPerUnit: ppu,
                              selectedId: _selectedId,
                              onTapEntry: _show,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        children: [
                          if (widget.timeline.note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: MarkdownNote(widget.timeline.note),
                            ),
                          for (final entry in entries)
                            ListTile(
                              key: ValueKey('timeline-row-${entry.id}'),
                              selected: entry.id == _selectedId,
                              leading: Icon(
                                entry.isSpan
                                    ? Icons.linear_scale
                                    : Icons.radio_button_checked,
                                color: entry.isSpan
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.tertiary,
                              ),
                              title: Text(entry.title),
                              subtitle: Text(
                                [
                                  timelineEntryTime(widget.timeline, entry),
                                  ...entry.verses.map(_reference),
                                ].join(' · '),
                              ),
                              onTap: () => _show(entry),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
