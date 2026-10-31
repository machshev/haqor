import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../event_sequence.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// The width and height of an event's card in the graph, and the room
/// between cards across and down.
const _cardWidth = 172.0;
const _cardHeight = 64.0;
const _gapAcross = 20.0;
const _gapDown = 44.0;

/// Laid left to right, the room between ranks across, and between the cards
/// of a rank down.
const _gapRank = 56.0;
const _gapStack = 16.0;

/// Where the choice of drawing left to right is kept.
const eventSequenceHorizontalKey = 'event_sequence_horizontal';

/// A sequence of the Bible's events drawn as what is known to come before
/// what: each event below those it follows, joined by the orderings that
/// no longer route implies. Picking an event shows which events are known
/// to come before it and after it, which are of unknown order to it, and
/// what each ordering rests on; an event with a sequence of its own opens
/// it.
class EventSequencePage extends StatefulWidget {
  const EventSequencePage({
    super.key,
    required this.sequence,
    required this.sequences,
    required this.events,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.focusEventId,
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

  static Future<void> open(
    BuildContext context, {
    required EventSequenceEntry sequence,
    required BibleSequences sequences,
    required Map<int, BibleEventEntry> events,
    required bool useEnglishBookNames,
    required ValueChanged<StudyPassage> onOpenPassage,
    int? focusEventId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventSequencePage(
        sequence: sequence,
        sequences: sequences,
        events: events,
        useEnglishBookNames: useEnglishBookNames,
        onOpenPassage: onOpenPassage,
        focusEventId: focusEventId,
      ),
    ),
  );

  @override
  State<EventSequencePage> createState() => _EventSequencePageState();
}

class _EventSequencePageState extends State<EventSequencePage> {
  late final SequenceGraph _graph = SequenceGraph(widget.sequence);
  final _transform = TransformationController();
  int? _selected;

  /// Whether the view has been placed on its first layout.
  bool _placed = false;

  @override
  void initState() {
    super.initState();
    _loadOrientation();
    final focus = widget.focusEventId;
    if (focus == null) return;
    final path = widget.sequences.pathTo(focus);
    final at = path.indexWhere((s) => s.key == widget.sequence.key);
    if (at < 0) return;
    if (at == path.length - 1) {
      _selected = focus;
    } else {
      // The event of this sequence that opens the next on the way.
      _selected = path[at + 1].expands;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openInside(path[at + 1], focus: focus);
      });
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Whether the graph runs left to right, each event right of those it
  /// follows, rather than top to bottom. Kept for the next sequence opened,
  /// and between runs.
  static bool _lastHorizontal = false;
  bool _horizontal = _lastHorizontal;

  /// The view's size when it was last laid out, to place the graph in after
  /// it is turned.
  Size _viewport = Size.zero;

  Future<void> _loadOrientation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final horizontal = prefs.getBool(eventSequenceHorizontalKey);
      if (horizontal == null || horizontal == _horizontal || !mounted) return;
      _setOrientation(horizontal, save: false);
    } catch (_) {
      // Without stored preferences, the default stands.
    }
  }

  void _setOrientation(bool horizontal, {bool save = true}) {
    _lastHorizontal = horizontal;
    setState(() => _horizontal = horizontal);
    final at = _selected ?? _graph.rows.firstOrNull?.first;
    if (at != null && _viewport != Size.zero) _centreOn(at, _viewport);
    if (save) {
      SharedPreferences.getInstance()
          .then((p) => p.setBool(eventSequenceHorizontalKey, horizontal))
          .catchError((_) => false);
    }
  }

  Offset _cardAt(int event) {
    final rank = _graph.row[event]!.toDouble();
    final across = _graph.column[event]!;
    return _horizontal
        ? Offset(
            _gapRank / 2 + rank * (_cardWidth + _gapRank),
            _gapStack + across * (_cardHeight + _gapStack),
          )
        : Offset(
            _gapAcross + across * (_cardWidth + _gapAcross),
            _gapDown / 2 + rank * (_cardHeight + _gapDown),
          );
  }

  Size get _canvas => _horizontal
      ? Size(
          _graph.rows.length * (_cardWidth + _gapRank),
          _graph.width * (_cardHeight + _gapStack) + _gapStack,
        )
      : Size(
          _graph.width * (_cardWidth + _gapAcross) + _gapAcross,
          _graph.rows.length * (_cardHeight + _gapDown),
        );

  /// Shows [event]'s card in the middle of the view across the graph's
  /// flow, and a little after where it starts along it.
  void _centreOn(int event, Size viewport) {
    final card = _cardAt(event);
    final scale = _transform.value.getMaxScaleOnAxis();
    final (x, y) = _horizontal
        ? (
            math.min(0.0, viewport.width / 4 - card.dx * scale),
            viewport.height / 2 - (card.dy + _cardHeight / 2) * scale,
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
      );

  /// The sequence's note: what it orders, and how.
  void _showNote() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.sequence.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            MarkdownNote(widget.sequence.note),
          ],
        ),
      ),
    ),
  );

  void _openPassage(StudyPassage passage) {
    Navigator.pop(context);
    widget.onOpenPassage(passage);
  }

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: widget.useEnglishBookNames)} '
      '${passage.reference}';

  String _title(int event) => widget.events[event]?.title ?? 'Event $event';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sequence.title),
            Text(
              '${_graph.events.length} events in order',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('sequence-orientation'),
            tooltip: _horizontal ? 'Draw top to bottom' : 'Draw left to right',
            icon: Icon(_horizontal ? Icons.swap_vert : Icons.swap_horiz),
            onPressed: () => _setOrientation(!_horizontal),
          ),
          if (widget.sequence.note.isNotEmpty)
            IconButton(
              key: const ValueKey('sequence-about'),
              tooltip: 'About this order',
              icon: const Icon(Icons.info_outline),
              onPressed: _showNote,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                if (!_placed) {
                  _placed = true;
                  final first = _selected ?? _graph.rows.firstOrNull?.first;
                  if (first != null) _centreOn(first, constraints.biggest);
                }
                return InteractiveViewer(
                  key: const ValueKey('sequence-graph'),
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.25,
                  maxScale: 2,
                  boundaryMargin: EdgeInsets.all(constraints.maxWidth / 2),
                  child: _graphView(theme),
                );
              },
            ),
          ),
          _panel(theme),
        ],
      ),
    );
  }

  Widget _graphView(ThemeData theme) {
    final selected = _selected;
    final before = selected == null ? const <int>{} : _graph.before(selected);
    final after = selected == null ? const <int>{} : _graph.after(selected);
    final scheme = theme.colorScheme;
    return SizedBox.fromSize(
      size: _canvas,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgePainter(
                edges: [
                  for (final (u, v) in _graph.drawnEdges)
                    (
                      from:
                          _cardAt(u) +
                          (_horizontal
                              ? const Offset(_cardWidth, _cardHeight / 2)
                              : const Offset(_cardWidth / 2, _cardHeight)),
                      to:
                          _cardAt(v) +
                          (_horizontal
                              ? const Offset(0, _cardHeight / 2)
                              : const Offset(_cardWidth / 2, 0)),
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
          for (final event in _graph.events)
            Positioned(
              left: _cardAt(event).dx,
              top: _cardAt(event).dy,
              width: _cardWidth,
              height: _cardHeight,
              child: _card(
                theme,
                event,
                relation: selected == null
                    ? null
                    : event == selected
                    ? _Relation.selected
                    : before.contains(event)
                    ? _Relation.before
                    : after.contains(event)
                    ? _Relation.after
                    : _Relation.unknown,
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme, int event, {_Relation? relation}) {
    final scheme = theme.colorScheme;
    final entry = widget.events[event];
    final inner = widget.sequences.expanding[event];
    final first = entry?.passages.firstOrNull;
    final (background, foreground) = switch (relation) {
      _Relation.selected => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      _Relation.before => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _Relation.after => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _ => (scheme.surfaceContainerHigh, scheme.onSurface),
    };
    final passages = entry?.passages.length ?? 0;
    return Opacity(
      opacity: relation == _Relation.unknown ? 0.45 : 1,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      if (first != null)
                        Text(
                          [
                            _reference(_passage(first)),
                            if (passages > 1) '+${passages - 1}',
                          ].join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: 0.75),
                          ),
                        ),
                    ],
                  ),
                ),
                if (inner != null)
                  Icon(
                    Icons.account_tree_outlined,
                    size: 18,
                    color: foreground,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Beneath the graph: the sequence's note, or the picked event's verses,
  /// what it is known to follow and precede and on what basis.
  Widget _panel(ThemeData theme) {
    final selected = _selected;
    final scheme = theme.colorScheme;
    final children = <Widget>[];
    if (selected == null) {
      children.add(
        Text(
          'Each event is drawn below those it is known to follow. '
          'Tap one to see what is known to come before and after it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      final entry = widget.events[selected];
      final inner = widget.sequences.expanding[selected];
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
              onTap: () => setState(() => _selected = event),
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
      final follows = _graph.directlyBefore(selected);
      final precedes = _graph.directlyAfter(selected);
      children.addAll([
        Row(
          children: [
            Expanded(
              child: Text(_title(selected), style: theme.textTheme.titleMedium),
            ),
            IconButton(
              tooltip: 'Close',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            legend(
              scheme.tertiaryContainer,
              'Before: ${_graph.before(selected).length}',
            ),
            legend(
              scheme.secondaryContainer,
              'After: ${_graph.after(selected).length}',
            ),
            legend(
              scheme.surfaceContainerHigh,
              'Order unknown: ${_graph.unorderedWith(selected)}',
            ),
          ],
        ),
        if (inner != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('sequence-open-inner'),
            onPressed: () => _openInside(inner),
            icon: const Icon(Icons.account_tree_outlined),
            label: Text('Open ${inner.title}: ${inner.events.length} events'),
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
      ]);
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
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
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

/// How an event stands to the one picked out.
enum _Relation { selected, before, after, unknown }

/// The orderings, each a curve down from the bottom of one card to the top
/// of the next with a head where it arrives; those leading to or from the
/// picked event lit.
class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.edges,
    required this.color,
    required this.litColor,
    required this.horizontal,
  });

  final List<({Offset from, Offset to, bool lit})> edges;
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
        final run = horizontal ? to.dx - from.dx : to.dy - from.dy;
        final bend = math.min(horizontal ? _gapRank : _gapDown, run / 2);
        final c1 = from + along * bend;
        final c2 = to - along * bend;
        final end = to - along * 5;
        canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy),
          paint,
        );
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
