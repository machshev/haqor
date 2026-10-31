import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../event_sequence.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';
import 'place_map.dart' show Basemap;
import 'sequence_map_page.dart';
import 'sequence_style.dart';
import 'timeline_calendar.dart' show timelineCategoryColor;

/// The width of an event's card in the graph, the most it is tall (its
/// height otherwise fitted to its title), and the room between cards across
/// and, where an arrow joins them, down.
const _cardWidth = 172.0;
const _cardHeight = 64.0;
const _gapAcross = 20.0;
const _gapDown = 28.0;

/// Laid left to right, the room between ranks across where an arrow joins
/// them, and between the cards of a rank down.
const _gapRank = 36.0;
const _gapStack = 12.0;

/// The room between ranks joined only one to one, each card straight after
/// the one it follows: stacked, with no arrow between.
const _gapStacked = 4.0;

/// The room an unfolded group's title takes before its first row, top to
/// bottom; left to right, the room each depth of titles takes above the
/// cards, and the room before a group's first rank.
const _groupHeader = 30.0;
const _groupHeaderAcross = 26.0;
const _groupPad = 12.0;

/// How far each depth of unfolded group is drawn in from the one around it.
const _groupInset = 6.0;

/// The room a feast's mark takes before the row of its event.
const _milestoneSpace = 30.0;

/// The room the lanes' names take above them, top to bottom.
const _laneHeader = 26.0;

/// Where the choices of drawing left to right, in region lanes, and as an
/// outline are kept.
const eventSequenceHorizontalKey = 'event_sequence_horizontal';
const eventSequenceLanesKey = 'event_sequence_lanes';
const eventSequenceOutlineKey = 'event_sequence_outline';

/// A sequence of the Bible's events drawn as what is known to come before
/// what: each event below those it follows, joined by the orderings that
/// no longer route implies. Picking an event shows which events are known
/// to come before it and after it, which are of unknown order to it, and
/// what each ordering rests on; an event with a sequence of its own opens
/// it.
///
/// A sequence with groupings (Robertson's parts, John's feasts) is drawn
/// folded into its groups, each unfolded on its own; its events are marked
/// by their kinds and Gospels, its feasts drawn across it, and its events
/// can be filtered by kind or person, laid in lanes by region, read as an
/// outline, and shown on the map.
class EventSequencePage extends StatefulWidget {
  const EventSequencePage({
    super.key,
    required this.sequence,
    required this.sequences,
    required this.events,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.focusEventId,
    this.basemap,
  });

  final EventSequenceEntry sequence;
  final BibleSequences sequences;

  /// Every event, by id.
  final Map<int, BibleEventEntry> events;
  final bool useEnglishBookNames;

  /// Opens a passage, this page closed first.
  final ValueChanged<StudyPassage> onOpenPassage;

  /// The event to open on: one of its own picked out, or, inside a
  /// sequence one of its events opens, that event picked out and the
  /// sequence opened on it.
  final int? focusEventId;

  /// The basemap its maps draw; the bundled one when null. A test passes
  /// its own.
  final Basemap? basemap;

  static Future<void> open(
    BuildContext context, {
    required EventSequenceEntry sequence,
    required BibleSequences sequences,
    required Map<int, BibleEventEntry> events,
    required bool useEnglishBookNames,
    required ValueChanged<StudyPassage> onOpenPassage,
    int? focusEventId,
    Basemap? basemap,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventSequencePage(
        sequence: sequence,
        sequences: sequences,
        events: events,
        useEnglishBookNames: useEnglishBookNames,
        onOpenPassage: onOpenPassage,
        focusEventId: focusEventId,
        basemap: basemap,
      ),
    ),
  );

  @override
  State<EventSequencePage> createState() => _EventSequencePageState();
}

/// An unfolded group's box: where it lies along the flow and across it.
typedef _Box = ({
  int group,
  int depth,
  double alongStart,
  double alongEnd,
  double acrossStart,
  double acrossEnd,
});

/// "1 event", "3 events".
String _events(int n) => n == 1 ? '1 event' : '$n events';

class _EventSequencePageState extends State<EventSequencePage> {
  /// Every event, none folded: what is known before and after each.
  late final SequenceGraph _full = SequenceGraph(widget.sequence);
  late final List<GroupingTree> _trees = [
    for (final g in widget.sequence.groupings) GroupingTree(g),
  ];
  late final Map<int, SequenceEventDetailsEntry> _details = {
    for (final d in widget.sequence.details) d.event: d,
  };
  late final Map<int, SequenceMilestoneEntry> _milestones = {
    for (final m in widget.sequence.milestones) m.event: m,
  };

  /// Each event's place in the order drawn, none folded.
  late final Map<int, int> _order = {
    for (final (i, e) in _full.drawnOrder.indexed) e: i,
  };

  late SequenceGraph _graph;
  final _transform = TransformationController();

  /// The node picked out: an event, or a folded group (see [groupNode]).
  int? _selected;

  /// The grouping drawn, by index, or null for none.
  int? _grouping;

  /// The groups unfolded.
  final _expanded = <int>{};

  /// The kinds of event lit, by family, and the person whose events are
  /// lit; with neither, every event.
  final _families = <SequenceFamily>{};
  int? _person;
  String? _track;
  late final List<String> _tracks = {
    for (final d in widget.sequence.details) ...d.tracks,
  }.toList();

  /// Whether the view has been placed on its first layout.
  bool _placed = false;

  /// The styles cards' titles are measured in, and the heights measured,
  /// by node; until the theme is known, every card at its tallest.
  TextStyle? _titleStyle;
  TextStyle? _footStyle;
  TextScaler _textScaler = TextScaler.noScaling;
  final _fitted = <int, double>{};

  /// The grouping last chosen for each sequence, by key: its key, or empty
  /// for none.
  static final _lastGrouping = <String, String>{};

  @override
  void initState() {
    super.initState();
    final last = _lastGrouping[widget.sequence.key];
    _grouping = last == null
        ? (_trees.isEmpty ? null : 0)
        : switch (_trees.indexWhere((t) => t.grouping.key == last)) {
            -1 => null,
            final i => i,
          };
    _loadPreferences();
    final focus = widget.focusEventId;
    int? select;
    if (focus != null) {
      final path = widget.sequences.pathTo(focus);
      final at = path.indexWhere((s) => s.key == widget.sequence.key);
      if (at == path.length - 1) {
        select = focus;
      } else if (at >= 0) {
        // The event of this sequence that opens the next on the way.
        select = path[at + 1].expands;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openInside(path[at + 1], focus: focus);
        });
      }
    }
    if (select != null) _unfoldTo(select);
    _rebuild();
    _selected = select;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final text = Theme.of(context).textTheme;
    final title = text.bodySmall?.copyWith(height: 1.2);
    final foot = text.labelSmall;
    final scaler = MediaQuery.textScalerOf(context);
    if (title == _titleStyle && foot == _footStyle && scaler == _textScaler) {
      return;
    }
    _titleStyle = title;
    _footStyle = foot;
    _textScaler = scaler;
    _fitted.clear();
    _measure();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// How tall [node]'s card need be: its title's lines (two at most), its
  /// marks beneath, and for a folded group the button unfolding it.
  double _fittedHeight(int node) {
    final title = _titleStyle;
    if (title == null) return _cardHeight;
    return _fitted[node] ??= () {
      final group = nodeGroup(node);
      final String text;
      final double width;
      if (group != null) {
        text = _tree?[group].title ?? '';
        width = _cardWidth - 10 - 40;
      } else {
        text = _title(node);
        final striped = kindsOf(_details[node]).isNotEmpty;
        width = _cardWidth - (striped ? 4 + 7 : 10) - 6;
      }
      final lines = TextPainter(
        text: TextSpan(
          text: text,
          style: title.copyWith(
            fontWeight: group == null ? FontWeight.w600 : FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: _textScaler,
        maxLines: 2,
      )..layout(maxWidth: width);
      final foot = TextPainter(
        text: TextSpan(text: 'Mt', style: _footStyle),
        textDirection: TextDirection.ltr,
        textScaler: _textScaler,
      )..layout();
      final height = 5 + lines.height + 2 + math.max(14.0, foot.height) + 5;
      lines.dispose();
      foot.dispose();
      return math.min(
        _cardHeight,
        math.max(group == null ? 0.0 : 50.0, height.ceilToDouble()),
      );
    }();
  }

  GroupingTree? get _tree => _grouping == null ? null : _trees[_grouping!];

  /// Whether the graph runs left to right, each event right of those it
  /// follows, rather than top to bottom; whether its events lie in lanes
  /// by region; and whether it is read as an outline instead. Kept for the
  /// next sequence opened, and between runs.
  static bool _lastHorizontal = false;
  static bool _lastLanes = false;
  static bool _lastOutline = false;
  bool _horizontal = _lastHorizontal;
  bool _lanes = _lastLanes;
  bool _outline = _lastOutline;

  /// Whether any of its events has a region, to lay in lanes.
  late final bool _hasRegions = _details.values.any((d) => d.region.isNotEmpty);

  /// The view's size when it was last laid out, to place the graph in after
  /// it is turned.
  Size _viewport = Size.zero;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final horizontal = prefs.getBool(eventSequenceHorizontalKey);
      final lanes = prefs.getBool(eventSequenceLanesKey);
      final outline = prefs.getBool(eventSequenceOutlineKey);
      if (lanes != null && lanes != _lanes) _setLanes(lanes, save: false);
      if (outline != null && outline != _outline) {
        _setOutline(outline, save: false);
      }
      if (horizontal != null && horizontal != _horizontal) {
        _setOrientation(horizontal, save: false);
      }
    } catch (_) {
      // Without stored preferences, the defaults stand.
    }
  }

  void _save(String key, bool value) => SharedPreferences.getInstance()
      .then((p) => p.setBool(key, value))
      .catchError((_) => false);

  void _setOrientation(bool horizontal, {bool save = true}) {
    _lastHorizontal = horizontal;
    setState(() {
      _horizontal = horizontal;
      _measure();
    });
    _centreOnSelected();
    if (save) _save(eventSequenceHorizontalKey, horizontal);
  }

  void _setLanes(bool lanes, {bool save = true}) {
    _lastLanes = lanes;
    setState(() {
      _lanes = lanes;
      _rebuild();
    });
    _centreOnSelected();
    if (save) _save(eventSequenceLanesKey, lanes);
  }

  void _setOutline(bool outline, {bool save = true}) {
    _lastOutline = outline;
    setState(() => _outline = outline);
    if (!outline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centreOnSelected();
      });
    }
    if (save) _save(eventSequenceOutlineKey, outline);
  }

  void _setGrouping(int? grouping) {
    _lastGrouping[widget.sequence.key] = grouping == null
        ? ''
        : _trees[grouping].grouping.key;
    final selected = _selected;
    final event = selected == null
        ? null
        : nodeGroup(selected) == null
        ? selected
        : null;
    setState(() {
      _grouping = grouping;
      _expanded.clear();
      if (event != null) _unfoldTo(event);
      _rebuild();
      _selected = event;
    });
    _centreOnSelected();
  }

  /// Unfolds the groups holding [event], so that it is drawn.
  void _unfoldTo(int event) {
    final tree = _tree;
    final leaf = tree?.leafOf[event];
    if (tree == null || leaf == null) return;
    _expanded.addAll(tree.pathTo(leaf));
  }

  /// The graph drawn again for the grouping, the groups unfolded and the
  /// lanes; the node picked out kept, or the group it is folded in.
  void _rebuild() {
    _graph = SequenceGraph(
      widget.sequence,
      grouping: _tree,
      expanded: _expanded,
      laneOf: _lanes && _hasRegions ? _laneOf : null,
    );
    final selected = _selected;
    if (selected != null && !_graph.events.contains(selected)) {
      _selected = switch (nodeGroup(selected)) {
        null => _graph.nodeOf[selected],
        final g => _graph.nodeOf[_tree?.eventsOf(g).firstOrNull],
      };
    }
    _measure();
  }

  /// The lane of [node]: its region's, or for a folded group the region
  /// most of its events are in.
  int? _laneOf(int node) {
    final g = nodeGroup(node);
    if (g == null) return regionLane(_details[node]?.region ?? '');
    final count = <int, int>{};
    for (final e in _tree!.eventsOf(g)) {
      final lane = regionLane(_details[e]?.region ?? '');
      if (lane != null) count[lane] = (count[lane] ?? 0) + 1;
    }
    if (count.isEmpty) return null;
    return count.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  void _toggle(int group) {
    setState(() {
      if (!_expanded.remove(group)) _expanded.add(group);
      _rebuild();
      if (_expanded.contains(group)) {
        // Its first event or group picked out, where the eye goes next.
        _selected = null;
      } else {
        _selected = groupNode(group);
      }
    });
    if (!_outline) {
      final first = _expanded.contains(group)
          ? _graph.events.firstWhere(
              (n) => _graph.groupRows[group]?.$1 == _graph.row[n],
              orElse: () => groupNode(group),
            )
          : groupNode(group);
      if (_graph.events.contains(first)) _centreOn(first, _viewport);
    }
  }

  void _foldAll(bool unfold) {
    setState(() {
      _expanded.clear();
      if (unfold) {
        _expanded.addAll(
          List.generate(_tree?.grouping.groups.length ?? 0, (i) => i),
        );
      }
      _rebuild();
    });
    _centreOnSelected();
  }

  /// Picks out [event], unfolding the groups it is in.
  void _reveal(int event) {
    setState(() {
      _unfoldTo(event);
      _rebuild();
      _selected = event;
    });
    if (!_outline) _centreOn(event, _viewport);
  }

  // The graph's geometry, measured by [_measure] for the graph drawn.

  /// Where each row starts along the flow, and where the last ends.
  var _rowAt = <double>[];
  var _alongEnd = 0.0;

  /// How far each row reaches along the flow; left to right, how tall
  /// every card is.
  var _rowAlong = <double>[];
  var _cardAcross = _cardHeight;

  /// The edges not drawn, their cards stacked one after the other.
  var _stacked = <(int, int)>{};

  /// Where an edge passing more than one row would run behind the cards
  /// between its ends, the column (in slots, as [SequenceGraph.column]) it
  /// runs down instead, in the room beside them.
  var _detours = <(int, int), double>{};

  /// Where the first slot starts across the flow, and where the canvas
  /// ends.
  var _acrossStart = 0.0;
  var _acrossEnd = 0.0;
  var _boxes = <_Box>[];

  /// The feasts drawn, by the row of their event.
  var _milestoneRows = <int, SequenceMilestoneEntry>{};

  double get _slot =>
      _horizontal ? _cardAcross + _gapStack : _cardWidth + _gapAcross;

  /// The size of [node]'s card: as tall as the tallest of its row, or left
  /// to right as the tallest of all.
  Size _cardSize(int node) => Size(
    _cardWidth,
    _horizontal ? _cardAcross : _rowAlong[_graph.row[node]!],
  );

  void _measure() {
    final graph = _graph;
    final tree = _tree;
    final starts = <int, List<int>>{};
    final ends = <int, List<int>>{};
    var deepest = 0;
    for (final MapEntry(key: group, value: (first, last))
        in graph.groupRows.entries) {
      if (!_expanded.contains(group)) continue;
      (starts[first] ??= []).add(group);
      (ends[last] ??= []).add(group);
      deepest = math.max(deepest, tree!.depth(group) + 1);
    }
    _milestoneRows = {
      for (final m in widget.sequence.milestones) ?graph.row[m.event]: m,
    };
    final headerAlong = _horizontal ? _groupPad : _groupHeader;
    final laned = graph.lanes.isNotEmpty;

    // Each card fitted to its title: top to bottom, a row as tall as its
    // tallest; left to right, every card as tall as the tallest.
    final fitted = [
      for (final r in graph.rows) r.map(_fittedHeight).fold(0.0, math.max),
    ];
    _cardAcross = fitted.fold(0.0, math.max);
    if (_cardAcross == 0) _cardAcross = _cardHeight;
    _rowAlong = _horizontal
        ? List.filled(graph.rows.length, _cardWidth)
        : fitted;

    // Where the edges from one row to the next all join one to one, each
    // card straight after the one it follows and nothing between, the cards
    // are stacked without an arrow; an arrow is kept where a card leads to
    // or follows more than one. Longer edges pass beside the stack, and
    // where a group ends and the next begins, the boxes are stacked too.
    bool stackable((int, int) edge) {
      final (u, v) = edge;
      return graph.oneToOne.contains(edge) &&
          (graph.column[u]! - graph.column[v]!).abs() < 1e-6;
    }

    final between = <int, List<(int, int)>>{};
    for (final edge in graph.drawnEdges) {
      final (u, v) = edge;
      if (graph.row[v] == graph.row[u]! + 1) {
        (between[graph.row[u]!] ??= []).add(edge);
      }
    }
    // An edge passing rows whose cards lie in its way is taken beside
    // them, in the room between slots nearest its ends; and kept room at
    // each end, to turn there.
    final detours = <(int, int), double>{};
    final turning = <int>{};
    final half = (_horizontal ? _cardAcross : _cardWidth) / (2 * _slot);
    for (final edge in graph.drawnEdges) {
      final (u, v) = edge;
      final (top, bottom) = (graph.row[u]!, graph.row[v]!);
      if (bottom - top < 2) continue;
      final (from, to) = (graph.column[u]!, graph.column[v]!);
      final passed = [for (var r = top + 1; r < bottom; r++) ...graph.rows[r]];
      bool inWay(double at, int node) =>
          (at - graph.column[node]!).abs() < half + 0.02;
      final blocked = [
        for (var r = top + 1; r < bottom; r++)
          for (final o in graph.rows[r])
            if (inWay(from + (to - from) * (r - top) / (bottom - top), o)) o,
      ];
      if (blocked.isEmpty) continue;
      final ways = [
        for (final o in passed) ...[
          graph.column[o]! - 0.5,
          graph.column[o]! + 0.5,
        ],
      ].where((at) => !passed.any((o) => inWay(at, o)));
      if (ways.isEmpty) continue;
      detours[edge] = ways.reduce(
        (a, b) =>
            (a - from).abs() + (a - to).abs() <=
                (b - from).abs() + (b - to).abs()
            ? a
            : b,
      );
      turning
        ..add(top)
        ..add(bottom - 1);
    }
    _detours = detours;

    final stacked = <(int, int)>{};
    final tight = <int>{};
    for (final MapEntry(key: r, value: edges) in between.entries) {
      if (_milestoneRows.containsKey(r + 1) ||
          turning.contains(r) ||
          !edges.every(stackable)) {
        continue;
      }
      tight.add(r);
      stacked.addAll(edges);
    }
    _stacked = stacked;

    final gap = _horizontal ? _gapRank : _gapDown;
    var at = (laned && !_horizontal ? _laneHeader : 0.0) + gap / 2;
    final rowAt = <double>[];
    for (var r = 0; r < graph.rows.length; r++) {
      at += _groupPad * (ends[r - 1]?.length ?? 0);
      at += headerAlong * (starts[r]?.length ?? 0);
      if (_milestoneRows.containsKey(r)) at += _milestoneSpace;
      rowAt.add(at);
      at +=
          _rowAlong[r] +
          (tight.contains(r) || r == graph.rows.length - 1 ? _gapStacked : gap);
    }
    if (graph.rows.isNotEmpty) at += gap / 2 - _gapStacked;
    at += _groupPad * (ends[graph.rows.length - 1]?.length ?? 0);
    _rowAt = rowAt;
    _alongEnd = at;
    _acrossStart = _horizontal
        ? deepest * _groupHeaderAcross + _gapStack
        : _gapAcross + deepest * _groupInset;
    // Top to bottom, unfolded groups at least three cards wide, so that
    // their titles can be read; the cards in the middle.
    final natural = graph.width * _slot;
    final least = !_horizontal && deepest > 0 ? 3 * _slot : 0.0;
    final spare = math.max(0.0, least - natural);
    _acrossStart += spare / 2;
    _acrossEnd = _acrossStart + natural + spare / 2 + deepest * _groupInset;

    final boxes = <_Box>[];
    for (final MapEntry(key: group, value: (first, last))
        in graph.groupRows.entries) {
      if (!_expanded.contains(group)) continue;
      final depth = tree!.depth(group);
      final outerFirst = starts[first]!
          .where((g) => tree.depth(g) >= depth)
          .length;
      final outerLast = ends[last]!.where((g) => tree.depth(g) >= depth).length;
      boxes.add((
        group: group,
        depth: depth,
        alongStart:
            rowAt[first] -
            (_milestoneRows.containsKey(first) ? _milestoneSpace : 0) -
            headerAlong * outerFirst,
        alongEnd: rowAt[last] + _rowAlong[last] + _groupPad * outerLast - 4,
        acrossStart: _horizontal
            ? depth * _groupHeaderAcross
            : depth * _groupInset + 4,
        acrossEnd: _acrossEnd - depth * _groupInset - 4,
      ));
    }
    // The outer first, so that the inner lie over them.
    boxes.sort((a, b) => a.depth.compareTo(b.depth));
    _boxes = boxes;
  }

  Offset _cardAt(int node) {
    final along = _rowAt[_graph.row[node]!];
    final across = _acrossStart + _graph.column[node]! * _slot;
    return _horizontal ? Offset(along, across) : Offset(across, along);
  }

  Size get _canvas =>
      _horizontal ? Size(_alongEnd, _acrossEnd) : Size(_acrossEnd, _alongEnd);

  void _centreOnSelected() {
    if (_viewport == Size.zero || _outline) return;
    final at = _selected ?? _graph.rows.firstOrNull?.firstOrNull;
    if (at != null) _centreOn(at, _viewport);
  }

  /// Shows [node]'s card in the middle of the view across the graph's
  /// flow, and a little after where it starts along it.
  void _centreOn(int node, Size viewport) {
    if (viewport == Size.zero || !_graph.row.containsKey(node)) return;
    final card = _cardAt(node);
    final scale = _transform.value.getMaxScaleOnAxis();
    final (x, y) = _horizontal
        ? (
            math.min(0.0, viewport.width / 4 - card.dx * scale),
            viewport.height / 2 - (card.dy + _cardAcross / 2) * scale,
          )
        : (
            viewport.width / 2 - (card.dx + _cardWidth / 2) * scale,
            math.min(0.0, viewport.height / 3 - card.dy * scale),
          );
    _transform.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _openInside(EventSequenceEntry inner, {int? focus}) =>
      EventSequencePage.open(
        context,
        sequence: inner,
        sequences: widget.sequences,
        events: widget.events,
        useEnglishBookNames: widget.useEnglishBookNames,
        onOpenPassage: (passage) {
          Navigator.pop(context);
          widget.onOpenPassage(passage);
        },
        focusEventId: focus,
        basemap: widget.basemap,
      );

  /// The sequence's note, and its grouping's: what it orders, and how.
  void _showNote() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      final tree = _tree;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.sequence.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              MarkdownNote(widget.sequence.note),
              if (tree != null && tree.grouping.note.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(tree.grouping.title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                MarkdownNote(tree.grouping.note),
              ],
            ],
          ),
        ),
      );
    },
  );

  void _openPassage(StudyPassage passage) {
    Navigator.pop(context);
    widget.onOpenPassage(passage);
  }

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: widget.useEnglishBookNames)} '
      '${passage.reference}';

  String _title(int node) => switch (nodeGroup(node)) {
    final g? => _tree?[g].title ?? 'Group ${g + 1}',
    null => widget.events[node]?.title ?? 'Event $node',
  };

  /// [events] in the order they are drawn, none folded.
  List<int> _ordered(Iterable<int> events) =>
      [...events]..sort((a, b) => (_order[a] ?? 0).compareTo(_order[b] ?? 0));

  bool get _filtering =>
      _families.isNotEmpty || _person != null || _track != null;

  /// Whether [event] is of a kind lit and has the person lit.
  bool _lit(int event) {
    if (_track != null &&
        !(_details[event]?.tracks.contains(_track) ?? false)) {
      return false;
    }
    if (_families.isNotEmpty &&
        !kindsOf(_details[event]).any((k) => _families.contains(k.family))) {
      return false;
    }
    final person = _person;
    if (person != null &&
        !(widget.events[event]?.people.any((p) => p.id == person) ?? false)) {
      return false;
    }
    return true;
  }

  /// The moʿadim's entry for a feast, and its colour there.
  (StudyTimelineEntry?, Color) _feast(String key, ThemeData theme) {
    final moadim = standardTimelineById('moadim');
    final entry = moadim?.entries.where((e) => e.id == key).firstOrNull;
    final index = entry == null ? null : moadim!.template.colorOf(entry);
    return (
      entry,
      index == null
          ? SequenceFamily.feasts.ink(theme.colorScheme)
          : timelineCategoryColor(index, theme.brightness),
    );
  }

  StudyPassage _milestonePassage(SequenceMilestoneEntry m) =>
      StudyPassage(bookIndex: m.book - 1, chapter: m.chapter, verse: m.verse);

  /// A feast an event falls at: what the moʿadim say of it, its verse, and
  /// its event.
  void _showMilestone(SequenceMilestoneEntry m) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) {
      final theme = Theme.of(sheet);
      final (entry, color) = _feast(m.feast, theme);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.celebration_outlined, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(m.label, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              if (entry != null) ...[
                const SizedBox(height: 4),
                Text(entry.title, style: theme.textTheme.titleSmall),
              ],
              if (entry?.note case final note? when note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(note, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined),
                    label: Text(_reference(_milestonePassage(m))),
                    onPressed: () {
                      Navigator.pop(sheet);
                      _openPassage(_milestonePassage(m));
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.adjust),
                    label: Text(_title(m.event)),
                    onPressed: () {
                      Navigator.pop(sheet);
                      if (_outline) {
                        setState(() {
                          _unfoldTo(m.event);
                          _rebuild();
                          _selected = m.event;
                        });
                      } else {
                        _reveal(m.event);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  /// The map of [events], titled [title].
  void _openMap(String title, List<int> events) => SequenceMapPage.open(
    context,
    title: title,
    tracks: {for (final e in events) e: _details[e]?.tracks ?? const []},
    initialTrack: _track,
    passages: {
      for (final e in events) e: widget.events[e]?.passages ?? const [],
    },
    basemap: widget.basemap,
    stops: [
      for (final e in _ordered(events))
        (
          event: e,
          title: _title(e),
          places: _details[e]?.places ?? const <SequencePlaceEntry>[],
        ),
    ],
    knownBefore: (a, b) => _full.after(a).contains(b),
    onOpenEvent: _outline
        ? (e) => setState(() {
            _unfoldTo(e);
            _rebuild();
            _selected = e;
          })
        : _reveal,
  );

  /// The people taking part in its events, the most often first.
  late final List<(NameSummaryEntry, int)> _people = () {
    final count = <int, int>{};
    final who = <int, NameSummaryEntry>{};
    for (final e in widget.sequence.events) {
      for (final p in widget.events[e]?.people ?? const <NameSummaryEntry>[]) {
        count[p.id] = (count[p.id] ?? 0) + 1;
        who[p.id] = p;
      }
    }
    final list = [for (final id in count.keys) (who[id]!, count[id]!)]
      ..sort((a, b) {
        final c = b.$2.compareTo(a.$2);
        return c != 0 ? c : a.$1.name.compareTo(b.$1.name);
      });
    return list;
  }();

  void _pickPerson() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheet).height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'Light the events of',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (final (person, count) in _people)
              ListTile(
                key: ValueKey('sequence-person-${person.id}'),
                title: Text(person.name),
                subtitle: person.description.isEmpty
                    ? null
                    : Text(person.description, maxLines: 1),
                trailing: Text('$count'),
                selected: person.id == _person,
                onTap: () {
                  Navigator.pop(sheet);
                  setState(() => _person = person.id);
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bar = _filterBar(theme);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sequence.title),
            Text(
              '${_full.events.length} events in order',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (_details.values.any((d) => d.places.isNotEmpty))
            IconButton(
              key: const ValueKey('sequence-map'),
              tooltip: 'Every event on the map',
              icon: const Icon(Icons.map_outlined),
              onPressed: () =>
                  _openMap(widget.sequence.title, widget.sequence.events),
            ),
          if (_tree case final tree?)
            IconButton(
              key: const ValueKey('sequence-fold-toggle'),
              tooltip: _expanded.isEmpty
                  ? 'Unfold every group'
                  : 'Fold every group',
              icon: Icon(
                _expanded.isEmpty ? Icons.unfold_more : Icons.unfold_less,
              ),
              onPressed: tree.grouping.groups.isEmpty
                  ? null
                  : () => _foldAll(_expanded.isEmpty),
            ),
          IconButton(
            key: const ValueKey('sequence-outline'),
            tooltip: _outline ? 'Draw as a graph' : 'Read as an outline',
            icon: Icon(_outline ? Icons.account_tree_outlined : Icons.list),
            onPressed: () => _setOutline(!_outline),
          ),
          if (!_outline)
            IconButton(
              key: const ValueKey('sequence-orientation'),
              tooltip: _horizontal
                  ? 'Draw top to bottom'
                  : 'Draw left to right',
              icon: Icon(_horizontal ? Icons.swap_vert : Icons.swap_horiz),
              onPressed: () => _setOrientation(!_horizontal),
            ),
          PopupMenuButton<String>(
            key: const ValueKey('sequence-menu'),
            onSelected: (choice) => switch (choice) {
              'lanes' => _setLanes(!_lanes),
              'map' => _openMap(widget.sequence.title, widget.sequence.events),
              'about' => _showNote(),
              _ => null,
            },
            itemBuilder: (context) => [
              if (_hasRegions && !_outline)
                CheckedPopupMenuItem(
                  key: const ValueKey('sequence-lanes'),
                  value: 'lanes',
                  checked: _lanes,
                  child: const Text('Lanes by region'),
                ),
              if (_details.values.any((d) => d.places.isNotEmpty))
                const PopupMenuItem(
                  key: ValueKey('sequence-map-all'),
                  value: 'map',
                  child: Text('Every event on the map'),
                ),
              if (widget.sequence.note.isNotEmpty)
                const PopupMenuItem(
                  key: ValueKey('sequence-about'),
                  value: 'about',
                  child: Text('About this order'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          ?bar,
          Expanded(child: _outline ? _outlineView(theme) : _graphPane()),
          _panel(theme),
        ],
      ),
    );
  }

  /// The chips choosing the grouping, and lighting kinds and a person; none
  /// for a sequence with none of them.
  Widget? _filterBar(ThemeData theme) {
    final families = <SequenceFamily>{
      for (final d in _details.values)
        for (final k in kindsOf(d)) k.family,
    };
    if (_trees.isEmpty &&
        families.isEmpty &&
        _people.isEmpty &&
        _tracks.isEmpty) {
      return null;
    }
    final person = _person;
    final personName = person == null
        ? null
        : _people.where((p) => p.$1.id == person).firstOrNull?.$1.name;
    // Compact, the kinds shown by their icons alone (named in their
    // tooltips), and wrapped onto as many lines as they need, so that every
    // chip can be reached without scrolling and few lines are taken.
    const density = VisualDensity.compact;
    const tap = MaterialTapTargetSize.shrinkWrap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          key: const ValueKey('sequence-filters'),
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (_trees.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<int>(
                  key: const ValueKey('sequence-grouping'),
                  tooltip: 'Group by',
                  initialValue: _grouping ?? -1,
                  onSelected: (i) => _setGrouping(i < 0 ? null : i),
                  itemBuilder: (context) => [
                    for (final (i, t) in _trees.indexed)
                      PopupMenuItem(
                        key: ValueKey('sequence-grouping-${t.grouping.key}'),
                        value: i,
                        child: Text(t.grouping.title),
                      ),
                    const PopupMenuItem(
                      key: ValueKey('sequence-grouping-none'),
                      value: -1,
                      child: Text('No groups'),
                    ),
                  ],
                  child: Chip(
                    visualDensity: density,
                    materialTapTargetSize: tap,
                    avatar: const Icon(Icons.segment, size: 18),
                    label: Text(_tree?.grouping.title ?? 'No groups'),
                    deleteIcon: const Icon(Icons.arrow_drop_down),
                    onDeleted: null,
                  ),
                ),
              ),
            for (final track in _tracks)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: FilterChip(
                  key: ValueKey('sequence-track-$track'),
                  avatar: const Icon(Icons.route, size: 18),
                  label: Text(track),
                  tooltip:
                      'Highlight $track’s journey; keep synchronisation links',
                  selected: _track == track,
                  visualDensity: density,
                  materialTapTargetSize: tap,
                  onSelected: (on) =>
                      setState(() => _track = on ? track : null),
                ),
              ),
            if (_people.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: personName == null
                    ? ActionChip(
                        key: const ValueKey('sequence-person'),
                        visualDensity: density,
                        materialTapTargetSize: tap,
                        avatar: const Icon(Icons.person_search_outlined),
                        label: const Text('Person'),
                        onPressed: _pickPerson,
                      )
                    : InputChip(
                        key: const ValueKey('sequence-person'),
                        visualDensity: density,
                        materialTapTargetSize: tap,
                        avatar: const Icon(Icons.person_outline),
                        label: Text(personName),
                        selected: true,
                        showCheckmark: false,
                        onPressed: _pickPerson,
                        onDeleted: () => setState(() => _person = null),
                      ),
              ),
            for (final family in SequenceFamily.values)
              if (families.contains(family))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilterChip(
                    key: ValueKey('sequence-kind-${family.name}'),
                    tooltip: family.label,
                    visualDensity: density,
                    materialTapTargetSize: tap,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    labelPadding: EdgeInsets.zero,
                    label: Icon(
                      family.icon,
                      size: 18,
                      color: family.ink(theme.colorScheme),
                    ),
                    selected: _families.contains(family),
                    showCheckmark: false,
                    onSelected: (on) => setState(() {
                      if (on) {
                        _families.add(family);
                      } else {
                        _families.remove(family);
                      }
                    }),
                  ),
                ),
            if (_filtering)
              ActionChip(
                key: const ValueKey('sequence-clear-filters'),
                tooltip: 'Clear the filters',
                visualDensity: density,
                materialTapTargetSize: tap,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                labelPadding: EdgeInsets.zero,
                label: const Icon(Icons.filter_alt_off_outlined, size: 18),
                onPressed: () => setState(() {
                  _families.clear();
                  _person = null;
                  _track = null;
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _graphPane() => LayoutBuilder(
    builder: (context, constraints) {
      _viewport = constraints.biggest;
      if (!_placed) {
        _placed = true;
        final first = _selected ?? _graph.rows.firstOrNull?.firstOrNull;
        if (first != null) _centreOn(first, constraints.biggest);
      }
      return InteractiveViewer(
        key: const ValueKey('sequence-graph'),
        transformationController: _transform,
        constrained: false,
        minScale: 0.2,
        maxScale: 2,
        boundaryMargin: EdgeInsets.all(constraints.maxWidth / 2),
        child: _graphView(Theme.of(context)),
      );
    },
  );

  Widget _graphView(ThemeData theme) {
    final selected = _selected;
    final before = selected == null ? const <int>{} : _graph.before(selected);
    final after = selected == null ? const <int>{} : _graph.after(selected);
    final scheme = theme.colorScheme;
    final canvas = _canvas;
    return SizedBox.fromSize(
      size: canvas,
      child: Stack(
        children: [
          if (_graph.lanes.isNotEmpty) ..._laneStripes(theme, canvas),
          for (final box in _boxes) _groupBox(theme, box),
          for (final MapEntry(key: row, value: m) in _milestoneRows.entries)
            _milestoneMark(theme, row, m, canvas),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _EdgePainter(
                  edges: [
                    for (final (u, v) in _graph.drawnEdges)
                      if (!_stacked.contains((u, v)))
                        (
                          from:
                              _cardAt(u) +
                              (_horizontal
                                  ? Offset(_cardWidth, _cardAcross / 2)
                                  : Offset(
                                      _cardWidth / 2,
                                      _cardSize(u).height,
                                    )),
                          to:
                              _cardAt(v) +
                              (_horizontal
                                  ? Offset(0, _cardAcross / 2)
                                  : const Offset(_cardWidth / 2, 0)),
                          via: switch (_detours[(u, v)]) {
                            null => null,
                            final column => (
                              across:
                                  _acrossStart +
                                  column * _slot +
                                  (_horizontal ? _cardAcross : _cardWidth) / 2,
                              start: _rowAt[_graph.row[u]! + 1],
                              end:
                                  _rowAt[_graph.row[v]! - 1] +
                                  _rowAlong[_graph.row[v]! - 1],
                            ),
                          },
                          lit:
                              selected != null &&
                              (({u, v}.every(
                                    (e) => e == selected || before.contains(e),
                                  )) ||
                                  ({u, v}.every(
                                    (e) => e == selected || after.contains(e),
                                  ))),
                        ),
                  ],
                  color: scheme.outlineVariant,
                  litColor: scheme.primary,
                  horizontal: _horizontal,
                ),
              ),
            ),
          ),
          for (final box in _boxes) _groupTitle(theme, box),
          for (final node in _graph.events)
            Positioned(
              left: _cardAt(node).dx,
              top: _cardAt(node).dy,
              width: _cardWidth,
              height: _cardSize(node).height,
              child: _card(
                theme,
                node,
                relation: selected == null
                    ? null
                    : node == selected
                    ? _Relation.selected
                    : before.contains(node)
                    ? _Relation.before
                    : after.contains(node)
                    ? _Relation.after
                    : _Relation.unknown,
              ),
            ),
        ],
      ),
    );
  }

  /// Each region's lane, shaded every other one, its name at its head.
  List<Widget> _laneStripes(ThemeData theme, Size canvas) {
    final scheme = theme.colorScheme;
    return [
      for (final (i, lane) in _graph.lanes.indexed) ...[
        Positioned(
          left: _horizontal
              ? 0
              : _acrossStart + lane.start * _slot - _gapAcross / 2,
          top: _horizontal
              ? _acrossStart + lane.start * _slot - _gapStack / 2
              : 0,
          width: _horizontal ? canvas.width : lane.width * _slot,
          height: _horizontal ? lane.width * _slot : canvas.height,
          child: ColoredBox(
            color: i.isEven
                ? scheme.onSurface.withValues(alpha: 0.035)
                : Colors.transparent,
          ),
        ),
        Positioned(
          left: _horizontal
              ? 4
              : _acrossStart + lane.start * _slot - _gapAcross / 2,
          top: _horizontal
              ? _acrossStart + lane.start * _slot - _gapStack / 2
              : 4,
          width: _horizontal ? _gapRank * 3 : lane.width * _slot,
          child: Text(
            sequenceRegions.values.elementAtOrNull(lane.lane) ?? 'Unplaced',
            key: ValueKey('sequence-lane-${lane.lane}'),
            textAlign: _horizontal ? TextAlign.start : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ];
  }

  Rect _boxRect(_Box box) => _horizontal
      ? Rect.fromLTRB(
          box.alongStart,
          box.acrossStart,
          box.alongEnd,
          box.acrossEnd,
        )
      : Rect.fromLTRB(
          box.acrossStart,
          box.alongStart,
          box.acrossEnd,
          box.alongEnd,
        );

  /// An unfolded group's box.
  Widget _groupBox(ThemeData theme, _Box box) {
    final scheme = theme.colorScheme;
    return Positioned.fromRect(
      rect: _boxRect(box),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.035 + 0.02 * box.depth),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }

  /// An unfolded group's title at the head of its box, with the button
  /// folding it: drawn over the edges passing it, on its box's ground.
  Widget _groupTitle(ThemeData theme, _Box box) {
    final scheme = theme.colorScheme;
    final group = _tree![box.group];
    final rect = _boxRect(box);
    final header = _horizontal ? _groupHeaderAcross : _groupHeader;
    var ground = scheme.surface;
    for (var d = 0; d <= box.depth; d++) {
      ground = Color.alphaBlend(
        scheme.primary.withValues(alpha: 0.035 + 0.02 * d),
        ground,
      );
    }
    return Positioned(
      left: rect.left + 4,
      top: rect.top + 1,
      width: math.max(0, rect.width - 8),
      height: header - 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: header - 2,
                child: IconButton(
                  key: ValueKey('sequence-fold-${box.group}'),
                  tooltip: 'Fold ${group.title}',
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  onPressed: () => _toggle(box.group),
                  icon: const Icon(Icons.unfold_less),
                ),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: group.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (group.note.isNotEmpty)
                          TextSpan(
                            text: '  ${group.note}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A feast's mark across the graph, before the row of its event.
  Widget _milestoneMark(
    ThemeData theme,
    int row,
    SequenceMilestoneEntry m,
    Size canvas,
  ) {
    final (_, color) = _feast(m.feast, theme);
    final at = _rowAt[row] - _milestoneSpace + 4;
    final label = Material(
      color: Color.alphaBlend(
        color.withValues(alpha: 0.18),
        theme.colorScheme.surface,
      ),
      shape: StadiumBorder(side: BorderSide(color: color)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => _showMilestone(m),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration_outlined, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                _horizontal
                    ? m.label
                    : '${m.label} · ${_reference(_milestonePassage(m))}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
    final line = DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.6)),
    );
    if (_horizontal) {
      return Positioned(
        key: ValueKey('sequence-milestone-${m.event}'),
        left: at,
        top: 0,
        width: _milestoneSpace - 8,
        height: canvas.height,
        child: Stack(
          children: [
            Positioned(
              left: (_milestoneSpace - 8) / 2 - 1,
              top: 0,
              bottom: 0,
              width: 2,
              child: line,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Center(child: RotatedBox(quarterTurns: 3, child: label)),
            ),
          ],
        ),
      );
    }
    return Positioned(
      key: ValueKey('sequence-milestone-${m.event}'),
      left: 0,
      top: at,
      width: canvas.width,
      height: _milestoneSpace - 8,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: (_milestoneSpace - 8) / 2 - 1,
            height: 2,
            child: line,
          ),
          Positioned(
            left: _acrossStart,
            top: 0,
            bottom: 0,
            child: Center(child: label),
          ),
        ],
      ),
    );
  }

  (Color, Color) _relationColours(
    ColorScheme scheme,
    _Relation? relation,
  ) => switch (relation) {
    _Relation.selected => (scheme.primaryContainer, scheme.onPrimaryContainer),
    _Relation.before => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    _Relation.after => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    _ => (scheme.surfaceContainerHigh, scheme.onSurface),
  };

  Widget _card(ThemeData theme, int node, {_Relation? relation}) {
    if (nodeGroup(node) case final g?) {
      return _groupCard(theme, g, relation: relation);
    }
    final event = node;
    final scheme = theme.colorScheme;
    final entry = widget.events[event];
    final inner = widget.sequences.expanding[event];
    final kinds = kindsOf(_details[event]);
    final chief = kinds.firstOrNull?.family;
    var (background, foreground) = _relationColours(scheme, relation);
    if (relation == null && chief != null) background = chief.tint(scheme);
    final dim =
        (relation == _Relation.unknown ? 0.45 : 1.0) *
        (_filtering && !_lit(event) ? 0.3 : 1.0);
    return Opacity(
      opacity: dim,
      child: Material(
        key: ValueKey('sequence-event-$event'),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: relation == _Relation.selected
              ? BorderSide(color: scheme.primary, width: 2)
              : inner != null
              ? BorderSide(color: scheme.outline)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              setState(() => _selected = _selected == event ? null : event),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (chief != null) Container(width: 4, color: chief.ink(scheme)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(chief == null ? 10 : 7, 5, 6, 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _title(event),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      Row(
                        children: [
                          for (final k in kinds.take(3))
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Tooltip(
                                message: k.label,
                                child: Icon(
                                  k.icon,
                                  size: 13,
                                  color: relation == null
                                      ? k.family.ink(scheme)
                                      : foreground,
                                ),
                              ),
                            ),
                          if (kinds.isEmpty)
                            if (entry?.passages.firstOrNull case final first?)
                              Flexible(
                                child: Text(
                                  _reference(_passage(first)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: foreground.withValues(alpha: 0.75),
                                  ),
                                ),
                              ),
                          const Spacer(),
                          if (inner != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Icon(
                                Icons.account_tree_outlined,
                                size: 14,
                                color: foreground,
                              ),
                            ),
                          SequenceSourceMarks(event: entry, color: foreground),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A folded group's card, drawn as a stack: its title, how many events
  /// it holds (and how many are lit), its feasts, and the button unfolding
  /// it.
  Widget _groupCard(ThemeData theme, int group, {_Relation? relation}) {
    final scheme = theme.colorScheme;
    final tree = _tree!;
    final members = tree.eventsOf(group);
    final lit = _filtering ? members.where(_lit).length : members.length;
    final feasts = [for (final e in members) ?_milestones[e]];
    var (background, foreground) = _relationColours(scheme, relation);
    if (relation == null) background = scheme.surfaceContainerHighest;
    final dim =
        (relation == _Relation.unknown ? 0.45 : 1.0) *
        (_filtering && lit == 0 ? 0.3 : 1.0);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: relation == _Relation.selected ? scheme.primary : scheme.outline,
        width: relation == _Relation.selected ? 2 : 1,
      ),
    );
    return Opacity(
      opacity: dim,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The cards beneath, a little behind.
          for (final offset in const [6.0, 3.0])
            Positioned(
              left: offset,
              top: offset,
              right: -offset,
              bottom: -offset,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Material(
              key: ValueKey('sequence-group-$group'),
              color: background,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  final node = groupNode(group);
                  setState(() => _selected = _selected == node ? null : node);
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 0, 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              tree[group].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    _filtering
                                        ? '$lit of ${_events(members.length)}'
                                        : _events(members.length),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: foreground.withValues(alpha: 0.8),
                                    ),
                                  ),
                                ),
                                for (final m in feasts)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Tooltip(
                                      message: m.label,
                                      child: Icon(
                                        Icons.celebration_outlined,
                                        size: 13,
                                        color: _feast(m.feast, theme).$2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: ValueKey('sequence-unfold-$group'),
                        tooltip: 'Unfold',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        color: foreground,
                        onPressed: () => _toggle(group),
                        icon: const Icon(Icons.unfold_more),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The sequence as a list: its groups as headings that fold, its events
  /// in order beneath them, and its feasts as rules between.
  Widget _outlineView(ThemeData theme) {
    final tree = _tree;
    final items = <Widget>[];
    void events(List<int> list, int depth) {
      for (final e in _ordered(list)) {
        if (_milestones[e] case final m?) {
          items.add(_outlineMilestone(theme, m, depth));
        }
        items.add(_outlineEvent(theme, e, depth));
      }
    }

    void group(int g, int depth) {
      items.add(_outlineGroup(theme, g, depth));
      if (!_expanded.contains(g)) return;
      final children = tree!.children(g);
      if (children.isEmpty) {
        events(tree[g].events, depth + 1);
      } else {
        for (final c in children) {
          group(c, depth + 1);
        }
      }
    }

    if (tree == null) {
      events(widget.sequence.events, 0);
    } else {
      for (final g in tree.top) {
        group(g, 0);
      }
    }
    return ListView(
      key: const ValueKey('sequence-outline-list'),
      children: items,
    );
  }

  Widget _outlineGroup(ThemeData theme, int g, int depth) {
    final tree = _tree!;
    final group = tree[g];
    final members = tree.eventsOf(g);
    final lit = _filtering ? members.where(_lit).length : members.length;
    final open = _expanded.contains(g);
    return Opacity(
      opacity: _filtering && lit == 0 ? 0.4 : 1,
      child: ListTile(
        key: ValueKey('sequence-outline-group-$g'),
        contentPadding: EdgeInsetsDirectional.only(
          start: 8 + 16.0 * depth,
          end: 8,
        ),
        selected: _selected == groupNode(g),
        leading: Icon(open ? Icons.expand_more : Icons.chevron_right),
        title: Text(
          group.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          [
            if (group.note.isNotEmpty) group.note,
            _filtering
                ? '$lit of ${_events(members.length)}'
                : _events(members.length),
          ].join(' · '),
        ),
        onTap: () => _toggle(g),
        onLongPress: () => setState(() => _selected = groupNode(g)),
      ),
    );
  }

  Widget _outlineMilestone(
    ThemeData theme,
    SequenceMilestoneEntry m,
    int depth,
  ) {
    final (_, color) = _feast(m.feast, theme);
    return InkWell(
      key: ValueKey('sequence-outline-milestone-${m.event}'),
      onTap: () => _showMilestone(m),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16.0 + 16 * depth, 6, 16, 6),
        child: Row(
          children: [
            Icon(Icons.celebration_outlined, size: 16, color: color),
            const SizedBox(width: 8),
            Text(
              '${m.label} · ${_reference(_milestonePassage(m))}',
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: color.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _outlineEvent(ThemeData theme, int e, int depth) {
    final scheme = theme.colorScheme;
    final entry = widget.events[e];
    final kinds = kindsOf(_details[e]);
    final chief = kinds.firstOrNull;
    final region = sequenceRegions[_details[e]?.region ?? ''];
    final first = entry?.passages.firstOrNull;
    return Opacity(
      opacity: _filtering && !_lit(e) ? 0.35 : 1,
      child: ListTile(
        key: ValueKey('sequence-outline-event-$e'),
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(
          start: 8 + 16.0 * depth,
          end: 12,
        ),
        selected: _selected == e,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor:
              chief?.family.tint(scheme) ?? scheme.surfaceContainer,
          child: Icon(
            chief?.icon ?? Icons.circle_outlined,
            size: 16,
            color: chief?.family.ink(scheme) ?? scheme.onSurfaceVariant,
          ),
        ),
        title: Text(_title(e)),
        subtitle: Text(
          [
            ...?_details[e]?.tracks,
            ?region,
            if (first != null) _reference(_passage(first)),
          ].join(' · '),
        ),
        trailing: SequenceSourceMarks(event: entry, color: scheme.onSurface),
        onTap: () => setState(() => _selected = _selected == e ? null : e),
      ),
    );
  }

  /// Beneath the graph: what to do, or the picked event's verses, what it
  /// is known to follow and precede and on what basis, or the picked
  /// group's events.
  Widget _panel(ThemeData theme) {
    final selected = _selected;
    final scheme = theme.colorScheme;
    final children = <Widget>[];
    if (selected == null) {
      children.add(
        Text(
          _tree != null
              ? 'Unfold a group to see its events; tap one to see what is '
                    'known to come before and after it.'
              : 'Tap an event to see what is known to come before and after it.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    } else if (nodeGroup(selected) case final g?) {
      children.addAll(_groupPanel(theme, g));
    } else {
      children.addAll(_eventPanel(theme, selected));
    }
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.4,
          ),
          child: SingleChildScrollView(
            key: const ValueKey('sequence-panel'),
            padding: selected == null
                ? const EdgeInsets.fromLTRB(16, 6, 8, 6)
                : const EdgeInsets.fromLTRB(16, 8, 8, 12),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(ThemeData theme, String title) => Row(
    children: [
      Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
      IconButton(
        tooltip: 'Close',
        visualDensity: VisualDensity.compact,
        onPressed: () => setState(() => _selected = null),
        icon: const Icon(Icons.close),
      ),
    ],
  );

  /// How many of [events] are of each family, the most first.
  Widget _familyCounts(ThemeData theme, List<int> events) {
    final count = <SequenceFamily, int>{};
    for (final e in events) {
      for (final f in {for (final k in kindsOf(_details[e])) k.family}) {
        count[f] = (count[f] ?? 0) + 1;
      }
    }
    final list = count.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final MapEntry(key: f, value: n) in list)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(f.icon, size: 16, color: f.ink(theme.colorScheme)),
              const SizedBox(width: 3),
              Text('${f.label} $n', style: theme.textTheme.labelMedium),
            ],
          ),
      ],
    );
  }

  List<Widget> _groupPanel(ThemeData theme, int g) {
    final tree = _tree!;
    final group = tree[g];
    final members = _ordered(tree.eventsOf(g));
    final placed = members.where(
      (e) => _details[e]?.places.isNotEmpty ?? false,
    );
    final scheme = theme.colorScheme;
    return [
      _heading(theme, group.title),
      if (group.note.isNotEmpty)
        Text(
          group.note,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      const SizedBox(height: 6),
      _familyCounts(theme, members),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton.tonalIcon(
            key: const ValueKey('sequence-panel-unfold'),
            onPressed: () => _toggle(g),
            icon: Icon(
              _expanded.contains(g) ? Icons.unfold_less : Icons.unfold_more,
            ),
            label: Text(
              _expanded.contains(g)
                  ? 'Fold'
                  : 'Unfold: ${_events(members.length)}',
            ),
          ),
          if (placed.isNotEmpty)
            OutlinedButton.icon(
              key: const ValueKey('sequence-panel-map'),
              onPressed: () => _openMap(group.title, members),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Map'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      for (final e in members)
        InkWell(
          key: ValueKey('sequence-member-$e'),
          onTap: () => _outline
              ? setState(() {
                  _unfoldTo(e);
                  _rebuild();
                  _selected = e;
                })
              : _reveal(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  kindsOf(_details[e]).firstOrNull?.icon ?? Icons.circle,
                  size: 14,
                  color:
                      kindsOf(_details[e]).firstOrNull?.family.ink(scheme) ??
                      scheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _title(e),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> _eventPanel(ThemeData theme, int selected) {
    final scheme = theme.colorScheme;
    final entry = widget.events[selected];
    final inner = widget.sequences.expanding[selected];
    final details = _details[selected];
    final kinds = kindsOf(details);
    final milestone = _milestones[selected];
    Widget legend(Color color, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.labelMedium),
      ],
    );
    Widget related(String heading, List<(int, List<String>)> list) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(heading, style: theme.textTheme.labelLarge),
        for (final (event, bases) in list)
          InkWell(
            key: ValueKey('sequence-related-$event'),
            onTap: () => _outline
                ? setState(() {
                    _unfoldTo(event);
                    _rebuild();
                    _selected = event;
                  })
                : _reveal(event),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _title(event),
                      style: TextStyle(color: scheme.primary),
                    ),
                    TextSpan(
                      text: ' — ${bases.join('; ')}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
      ],
    );
    final follows = _full.directlyBefore(selected);
    final precedes = _full.directlyAfter(selected);
    final region = sequenceRegions[details?.region ?? ''];
    final places = details?.places ?? const <SequencePlaceEntry>[];
    final people = [
      for (final p in entry?.people ?? const <NameSummaryEntry>[])
        if (p.kind == 'person') p,
    ];
    return [
      _heading(theme, _title(selected)),
      if (kinds.isNotEmpty || region != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Wrap(
            spacing: 10,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final k in kinds)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(k.icon, size: 16, color: k.family.ink(scheme)),
                    const SizedBox(width: 3),
                    Text(k.label, style: theme.textTheme.labelMedium),
                  ],
                ),
              if (region != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_outlined, size: 16, color: scheme.outline),
                    const SizedBox(width: 3),
                    Text(
                      [region, ...places.map((p) => p.label)].join(' · '),
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              SequenceSourceMarks(event: entry, color: scheme.onSurface),
            ],
          ),
        ),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          legend(
            scheme.tertiaryContainer,
            'Before: ${_full.before(selected).length}',
          ),
          legend(
            scheme.secondaryContainer,
            'After: ${_full.after(selected).length}',
          ),
          legend(
            scheme.surfaceContainerHigh,
            'Order unknown: ${_full.unorderedWith(selected)}',
          ),
        ],
      ),
      if (inner != null || milestone != null || places.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (inner != null)
              FilledButton.tonalIcon(
                key: const ValueKey('sequence-open-inner'),
                onPressed: () => _openInside(inner),
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(
                  'Open ${inner.title}: ${inner.events.length} events',
                ),
              ),
            if (milestone != null)
              OutlinedButton.icon(
                key: const ValueKey('sequence-panel-feast'),
                onPressed: () => _showMilestone(milestone),
                icon: Icon(
                  Icons.celebration_outlined,
                  color: _feast(milestone.feast, theme).$2,
                ),
                label: Text(milestone.label),
              ),
            if (places.isNotEmpty)
              OutlinedButton.icon(
                key: const ValueKey('sequence-panel-map'),
                // With the events either side of it, whence and whither.
                onPressed: () => _openMap('Around ${_title(selected)}', [
                  for (final (e, _) in follows) e,
                  selected,
                  for (final (e, _) in precedes) e,
                ]),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Map'),
              ),
          ],
        ),
      ],
      if (entry != null && entry.note.isNotEmpty) ...[
        const SizedBox(height: 8),
        MarkdownNote(entry.note),
      ],
      if (entry != null && entry.passages.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in entry.passages)
              ActionChip(
                avatar: const Icon(Icons.menu_book_outlined),
                label: Text(_reference(_passage(p))),
                onPressed: () => _openPassage(_passage(p)),
              ),
          ],
        ),
      ],
      if (people.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final p in people)
              ActionChip(
                key: ValueKey('sequence-panel-person-${p.id}'),
                avatar: const Icon(Icons.person_outline),
                label: Text(p.name),
                tooltip: 'Light the events of ${p.name}',
                onPressed: () => setState(() => _person = p.id),
              ),
          ],
        ),
      ],
      if (follows.isNotEmpty) related('Comes after', follows),
      if (precedes.isNotEmpty) related('Comes before', precedes),
      if (follows.isEmpty && precedes.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Nothing orders it among the others.',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }
}

/// A passage of an event, as the reader opens it.
StudyPassage _passage(ThematicTarget p) => StudyPassage(
  bookIndex: p.book - 1,
  chapter: p.chapter,
  verse: p.verse,
  endChapter: p.lastChapter == p.chapter ? null : p.lastChapter,
  endVerse: p.lastChapter == p.chapter && p.lastVerse == p.verse
      ? null
      : p.lastVerse,
);

/// How a node stands to the one picked out.
enum _Relation { selected, before, after, unknown }

/// The orderings, each a curve down from the bottom of one card to the top
/// of the next with a head where it arrives; those leading to or from the
/// picked node lit.
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.edges,
    required this.color,
    required this.litColor,
    required this.horizontal,
  });

  /// Each edge from the foot of one card to the head of the next; one
  /// taken beside the cards between runs [via] a line along the flow, from
  /// where it enters their rows to where it leaves them.
  final List<
    ({
      Offset from,
      Offset to,
      ({double across, double start, double end})? via,
      bool lit,
    })
  >
  edges;
  final Color color, litColor;

  /// Whether the edges run left to right, leaving a card's right side for
  /// the next's left, rather than top to bottom.
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    // The unlit first, so that the lit lie over them.
    for (final lit in [false, true]) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lit ? 2 : 1.2
        ..color = lit ? litColor : color;
      final head = Paint()..color = lit ? litColor : color;
      for (final edge in edges) {
        if (edge.lit != lit) continue;
        final (from, to) = (edge.from, edge.to);
        // Along the flow, and across it.
        final along = horizontal ? const Offset(1, 0) : const Offset(0, 1);
        final side = Offset(along.dy, along.dx);
        final end = to - along * 5;
        // A curve leaving along the flow and arriving along it.
        void curve(Path path, Offset a, Offset b) {
          final run = horizontal ? b.dx - a.dx : b.dy - a.dy;
          final bend = math.min(horizontal ? _gapRank : _gapDown, run / 2);
          final c1 = a + along * bend;
          final c2 = b - along * bend;
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
        }

        final path = Path()..moveTo(from.dx, from.dy);
        if (edge.via case final via?) {
          Offset point(double at) =>
              horizontal ? Offset(at, via.across) : Offset(via.across, at);
          final (enter, leave) = (point(via.start), point(via.end));
          curve(path, from, enter);
          path.lineTo(leave.dx, leave.dy);
          curve(path, leave, end);
        } else {
          curve(path, from, end);
        }
        canvas.drawPath(path, paint);
        final back = to - along * 6;
        final left = back - side * 4;
        final right = back + side * 4;
        canvas.drawPath(
          Path()
            ..moveTo(to.dx, to.dy)
            ..lineTo(left.dx, left.dy)
            ..lineTo(right.dx, right.dy)
            ..close(),
          head,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.edges != edges ||
      old.color != color ||
      old.litColor != litColor ||
      old.horizontal != horizontal;
}
