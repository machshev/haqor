import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bindings/bindings.dart';
import '../syntax_tree.dart';
import 'verse_text_cache.dart';

/// Show one Old Testament verse's syntax (MACULA Hebrew's tree): its clauses
/// and phrases, each labelled with its role, as an outline or a drawn tree.
///
/// [book] is 1-based. [initialView] is the view it opens in; a change of view
/// is reported to [onViewChanged] so the next verse opens the same way.
/// Tapping a word reports it to [onWordTap] with its position in the verse.
Future<void> showSyntaxSheet(
  BuildContext context, {
  required int book,
  required int chapter,
  required int verse,
  required String title,
  required SyntaxView initialView,
  String fontFamily = 'Cardo',
  ValueChanged<SyntaxView>? onViewChanged,
  void Function(String word, int position, String gloss)? onWordTap,
  void Function(GetSyntaxTrees)? sendRequest,
  void Function(GetVerseTexts)? sendVerseTextsRequest,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    maxWidth: 1100,
  ),
  builder: (_) => SyntaxPanel(
    book: book,
    chapter: chapter,
    verse: verse,
    title: title,
    initialView: initialView,
    fontFamily: fontFamily,
    onViewChanged: onViewChanged,
    onWordTap: onWordTap,
    sendRequest: sendRequest,
    sendVerseTextsRequest: sendVerseTextsRequest,
  ),
);

/// The body of [showSyntaxSheet].
class SyntaxPanel extends StatefulWidget {
  const SyntaxPanel({
    super.key,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.title,
    required this.initialView,
    this.fontFamily = 'Cardo',
    this.onViewChanged,
    this.onWordTap,
    this.sendRequest,
    this.sendVerseTextsRequest,
  });

  final int book;
  final int chapter;
  final int verse;
  final String title;
  final SyntaxView initialView;
  final String fontFamily;
  final ValueChanged<SyntaxView>? onViewChanged;
  final void Function(String word, int position, String gloss)? onWordTap;

  /// Test seams: how requests reach Rust, which a widget test cannot load.
  final void Function(GetSyntaxTrees)? sendRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  @override
  State<SyntaxPanel> createState() => _SyntaxPanelState();
}

/// The words of the verse by position, with their glosses.
typedef _Words = ({List<String> hebrew, List<String> glosses});

class _SyntaxPanelState extends State<SyntaxPanel> {
  /// Request ids are handed out app-wide: the reply stream is a broadcast.
  static int _nextRequestId = 1 << 20;
  late final int _requestId = _nextRequestId++;
  StreamSubscription<RustSignalPack<SyntaxTrees>>? _sub;

  late final VerseTextCache _texts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  late final ValueListenable<VerseTextData?> _text = _texts.textFor(
    book: widget.book,
    chapter: widget.chapter,
    verse: widget.verse,
    englishOnly: true,
  );

  late SyntaxView _view = widget.initialView;
  bool _loaded = false;
  SyntaxTreeNode? _tree;

  @override
  void initState() {
    super.initState();
    _sub = SyntaxTrees.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId || !mounted) return;
      setState(() {
        _loaded = true;
        _tree = reply.verses
            .where((v) => v.verse == widget.verse)
            .map(SyntaxTreeNode.fromEntry)
            .firstOrNull;
      });
    });
    final request = GetSyntaxTrees(
      requestId: _requestId,
      book: widget.book,
      chapter: widget.chapter,
      firstVerse: widget.verse,
      lastVerse: widget.verse,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _texts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Syntax', style: theme.textTheme.titleMedium),
                    Text(
                      widget.title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<SyntaxView>(
                key: const ValueKey('syntax-view'),
                showSelectedIcon: false,
                segments: [
                  for (final view in SyntaxView.values)
                    ButtonSegment(value: view, label: Text(view.label)),
                ],
                selected: {_view},
                onSelectionChanged: (s) {
                  setState(() => _view = s.single);
                  widget.onViewChanged?.call(_view);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _Legend(brightness: theme.brightness),
        ),
        const Divider(height: 1),
        Flexible(
          child: ValueListenableBuilder<VerseTextData?>(
            valueListenable: _text,
            builder: (context, text, _) {
              final tree = _tree;
              if (!_loaded || text == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (tree == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('No syntax tree for this verse.')),
                );
              }
              final words = (
                hebrew: text.sourceWords,
                glosses: text.glossWords,
              );
              return _view == SyntaxView.outline
                  ? _Outline(
                      tree: tree,
                      words: words,
                      fontFamily: widget.fontFamily,
                      onWordTap: widget.onWordTap,
                    )
                  : _TreeDiagram(
                      tree: tree,
                      words: words,
                      fontFamily: widget.fontFamily,
                      onWordTap: widget.onWordTap,
                    );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Syntax trees from MACULA Hebrew (Clear Bible, CC BY 4.0).',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// What a leaf shows: the part of the word it stands for, or the word.
({String hebrew, String gloss}) _leafText(SyntaxTreeNode leaf, _Words words) {
  if (leaf.isPart) return (hebrew: leaf.partText, gloss: leaf.partGloss);
  final p = leaf.position;
  return (
    hebrew: p < words.hebrew.length ? words.hebrew[p] : '',
    gloss: p < words.glosses.length ? words.glosses[p] : '',
  );
}

/// Report a tap on the word at [position]: the whole word, even from a leaf
/// that is only part of it, since the word is what its details describe.
void _tapWord(
  void Function(String word, int position, String gloss) onWordTap,
  int position,
  _Words words,
) {
  if (position >= words.hebrew.length) return;
  onWordTap(
    words.hebrew[position],
    position,
    position < words.glosses.length ? words.glosses[position] : '',
  );
}

/// The roles' colours, as a key.
class _Legend extends StatelessWidget {
  const _Legend({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final role in syntaxColourRoles)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 3,
                color: syntaxRoleColor(role, brightness),
              ),
              const SizedBox(width: 4),
              Text(syntaxRoleName(role), style: style),
            ],
          ),
      ],
    );
  }
}

/// A word (or part of one) with its gloss beneath, tappable.
class _WordChip extends StatelessWidget {
  const _WordChip({
    required this.leaf,
    required this.words,
    required this.fontFamily,
    this.onWordTap,
  });

  final SyntaxTreeNode leaf;
  final _Words words;
  final String fontFamily;
  final void Function(String word, int position, String gloss)? onWordTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _leafText(leaf, words);
    final role = leaf.role;
    return InkWell(
      key: ValueKey('syntax-word-${leaf.position}-${leaf.partText}'),
      borderRadius: BorderRadius.circular(6),
      onTap: onWordTap == null
          ? null
          : () => _tapWord(onWordTap!, leaf.position, words),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text.hebrew,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: fontFamily,
                fontFamilyFallback: const ['Noto Serif Hebrew'],
                fontSize: 22,
                height: 1.4,
                decoration: role.isEmpty ? null : TextDecoration.underline,
                decorationColor: role.isEmpty
                    ? null
                    : syntaxRoleColor(role, theme.brightness),
                decorationThickness: 2.5,
              ),
            ),
            if (text.gloss.isNotEmpty)
              Text(text.gloss, style: theme.textTheme.labelSmall),
            if (role.isNotEmpty)
              Text(
                syntaxRoleName(role),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: syntaxRoleColor(role, theme.brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The tree as nested blocks: each clause or phrase a labelled block, its
/// constituents inside it, and a run of words as a right-to-left line.
class _Outline extends StatelessWidget {
  const _Outline({
    required this.tree,
    required this.words,
    required this.fontFamily,
    this.onWordTap,
  });

  final SyntaxTreeNode tree;
  final _Words words;
  final String fontFamily;
  final void Function(String word, int position, String gloss)? onWordTap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('syntax-outline'),
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
    child: _block(context, tree),
  );

  Widget _block(BuildContext context, SyntaxTreeNode node) {
    if (node.isLeaf) {
      return _WordChip(
        leaf: node,
        words: words,
        fontFamily: fontFamily,
        onWordTap: onWordTap,
      );
    }
    final theme = Theme.of(context);
    final accent = node.role.isEmpty
        ? theme.colorScheme.outlineVariant
        : syntaxRoleColor(node.role, theme.brightness);
    final label = [
      if (node.role.isNotEmpty) syntaxRoleName(node.role),
      if (node.kind.isNotEmpty) syntaxKindName(node.kind),
    ].join(' · ');
    // Runs of words sit on one right-to-left line; groups stack beneath.
    final rows = <Widget>[];
    var run = <SyntaxTreeNode>[];
    void flush() {
      if (run.isEmpty) return;
      rows.add(
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Wrap(
            textDirection: TextDirection.rtl,
            children: [
              for (final leaf in run)
                _WordChip(
                  leaf: leaf,
                  words: words,
                  fontFamily: fontFamily,
                  onWordTap: onWordTap,
                ),
            ],
          ),
        ),
      );
      run = [];
    }

    for (final child in node.children) {
      if (child.isLeaf) {
        run.add(child);
      } else if (_plainPhrase(child)) {
        // A phrase with no role of its own reads as its words.
        run.addAll(child.leaves);
      } else {
        flush();
        rows.add(_block(context, child));
      }
    }
    flush();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 4, 4),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: node.role.isEmpty
                    ? theme.colorScheme.onSurfaceVariant
                    : accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ...rows,
        ],
      ),
    );
  }
}

/// Whether [node] is a phrase the outline shows as its words alone: no role
/// of its own, not a clause, and nothing inside it that has either.
bool _plainPhrase(SyntaxTreeNode node) =>
    !node.isLeaf &&
    node.role.isEmpty &&
    node.kind != 'cl' &&
    node.children.every((c) => c.isLeaf || _plainPhrase(c));

/// One node of the drawn tree, placed.
class _Placed {
  _Placed(this.node, this.center, this.top, this.size);

  final SyntaxTreeNode node;
  final double center;
  final double top;
  final Size size;
  final List<_Placed> children = [];
}

/// The tree drawn top-down, its first constituents on the right as Hebrew
/// reads, inside a pan-and-zoom viewer.
class _TreeDiagram extends StatelessWidget {
  const _TreeDiagram({
    required this.tree,
    required this.words,
    required this.fontFamily,
    this.onWordTap,
  });

  final SyntaxTreeNode tree;
  final _Words words;
  final String fontFamily;
  final void Function(String word, int position, String gloss)? onWordTap;

  static const _levelHeight = 64.0;
  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelMedium!;
    final hebrewStyle = TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: 22,
    );
    final glossStyle = theme.textTheme.labelSmall!;

    Size measure(String text, TextStyle style, {TextDirection? direction}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction ?? TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      return painter.size;
    }

    Size boxOf(SyntaxTreeNode node) {
      if (node.isLeaf) {
        final text = _leafText(node, words);
        final hebrew = measure(
          text.hebrew,
          hebrewStyle,
          direction: TextDirection.rtl,
        );
        final gloss = measure(text.gloss, glossStyle);
        return Size(
          math.max(hebrew.width, gloss.width) + 12,
          hebrew.height + gloss.height + 12,
        );
      }
      final label = measure(node.label, labelStyle);
      return Size(label.width + 16, label.height + 8);
    }

    // Lay out right to left: each subtree takes the width of its children
    // or its own box, whichever is wider, and its box centres over them.
    var maxBottom = 0.0;
    _Placed place(SyntaxTreeNode node, double right, int depth) {
      final box = boxOf(node);
      final top = depth * _levelHeight;
      maxBottom = math.max(maxBottom, top + box.height);
      if (node.children.isEmpty) {
        return _Placed(node, right - box.width / 2, top, box);
      }
      var cursor = right;
      final placed = <_Placed>[];
      for (final child in node.children) {
        final p = place(child, cursor, depth + 1);
        placed.add(p);
        cursor = _leftEdge(p) - _gap;
      }
      final childrenWidth = right - (cursor + _gap);
      var center = (placed.first.center + placed.last.center) / 2;
      if (box.width > childrenWidth) center = right - box.width / 2;
      return _Placed(node, center, top, box)..children.addAll(placed);
    }

    final root = place(tree, 0, 0);
    final left = _leftEdge(root);
    final width = -left + 24;
    final height = maxBottom + 24;
    final nodes = <_Placed>[];
    void collect(_Placed p) {
      nodes.add(p);
      p.children.forEach(collect);
    }

    collect(root);
    final dx = -left + 12;
    const dy = 12.0;
    final lineColor = theme.colorScheme.outline;

    // Open on the start of the verse, its right-hand side, scaled down to
    // fit the width where that leaves the text readable.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / width).clamp(0.6, 1.0);
        final shift = math.min(0.0, constraints.maxWidth - width * scale);
        return InteractiveViewer(
          key: const ValueKey('syntax-tree'),
          transformationController: TransformationController(
            Matrix4.identity()
              ..translateByDouble(shift, 0, 0, 1)
              ..scaleByDouble(scale, scale, 1, 1),
          ),
          constrained: false,
          minScale: 0.3,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(200),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EdgePainter(root, dx, dy, lineColor),
                  ),
                ),
                for (final p in nodes)
                  Positioned(
                    left: p.center - p.size.width / 2 + dx,
                    top: p.top + dy,
                    width: p.size.width,
                    height: p.size.height,
                    child: p.node.isLeaf
                        ? _treeLeaf(context, p.node, hebrewStyle, glossStyle)
                        : _treeLabel(context, p.node, labelStyle),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static double _leftEdge(_Placed p) {
    var left = p.center - p.size.width / 2;
    for (final c in p.children) {
      left = math.min(left, _leftEdge(c));
    }
    return left;
  }

  Widget _treeLabel(
    BuildContext context,
    SyntaxTreeNode node,
    TextStyle style,
  ) {
    final theme = Theme.of(context);
    final accent = node.role.isEmpty
        ? theme.colorScheme.outlineVariant
        : syntaxRoleColor(node.role, theme.brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border.all(color: accent, width: node.role.isEmpty ? 1 : 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          node.label,
          style: style.copyWith(
            color: node.role.isEmpty ? null : accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _treeLeaf(
    BuildContext context,
    SyntaxTreeNode node,
    TextStyle hebrewStyle,
    TextStyle glossStyle,
  ) {
    final theme = Theme.of(context);
    final text = _leafText(node, words);
    return GestureDetector(
      onTap: onWordTap == null
          ? null
          : () => _tapWord(onWordTap!, node.position, words),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text.hebrew,
            textDirection: TextDirection.rtl,
            style: hebrewStyle.copyWith(
              decoration: node.role.isEmpty ? null : TextDecoration.underline,
              decorationColor: node.role.isEmpty
                  ? null
                  : syntaxRoleColor(node.role, theme.brightness),
              decorationThickness: 2.5,
            ),
          ),
          Text(text.gloss, style: glossStyle),
        ],
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.root, this.dx, this.dy, this.color);

  final _Placed root;
  final double dx;
  final double dy;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    void draw(_Placed p) {
      final from = Offset(p.center + dx, p.top + p.size.height + dy);
      for (final c in p.children) {
        canvas.drawLine(from, Offset(c.center + dx, c.top + dy), paint);
        draw(c);
      }
    }

    draw(root);
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.root != root || old.color != color;
}
