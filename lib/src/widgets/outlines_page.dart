import 'package:flutter/material.dart';

import '../bindings/bindings.dart';
import '../outlines.dart';
import '../verse_counts.dart';

/// Opens a passage in the reader: 0-based book index, chapter, verse.
typedef OutlineNavigate = void Function(int bookIndex, int chapter, int verse);

/// [navigate], first closing every route above [context]'s own, and that one
/// too when [closeOwn].
OutlineNavigate? _closing(
  BuildContext context,
  OutlineNavigate? navigate, {
  required bool closeOwn,
}) {
  if (navigate == null) return null;
  return (book, chapter, verse) {
    final own = ModalRoute.of(context);
    final navigator = Navigator.of(context)..popUntil((route) => route == own);
    if (closeOwn) navigator.maybePop();
    navigate(book, chapter, verse);
  };
}

/// Opens [s]'s first verse with [navigate].
void _read(OutlineSectionEntry s, OutlineNavigate? navigate) =>
    navigate?.call(s.book - 1, s.chapter, s.verse);

/// Whether a section runs from a chapter's start to one's end: a psalm, a
/// book of the Psalms.
bool _wholeChapters(OutlineSectionEntry s) =>
    s.verse == 1 && s.lastVerse == verseCount(s.lastBook - 1, s.lastChapter);

/// What the text calls a section, its facts, and its note.
class OutlineSectionDetails extends StatelessWidget {
  const OutlineSectionDetails({
    super.key,
    required this.tree,
    required this.section,
    this.showNote = true,
  });

  final OutlineTree tree;
  final int section;
  final bool showNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final s = tree[section];
    final facts = [
      for (final facet in tree.outline.facets)
        for (final v in s.factsOf(facet.key)) (facet.title, v),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.superscription.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              s.superscription,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        if (facts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final (facet, value) in facts)
                  Tooltip(
                    message: facet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        value,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (showNote && s.note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(s.note, style: muted),
          ),
      ],
    );
  }
}

/// A section as a row: its title and subtitle, its passage, and below them
/// its details. Tapping it opens it in the reader.
class OutlineSectionTile extends StatelessWidget {
  const OutlineSectionTile({
    super.key,
    required this.tree,
    required this.section,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.selected = false,
    this.indent = 0,
  });

  final OutlineTree tree;
  final int section;
  final bool useEnglishBookNames;
  final OutlineNavigate? onNavigateToPassage;
  final bool selected;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = tree[section];
    final passage = outlinePassageLabel(
      s,
      useEnglish: useEnglishBookNames,
      wholeChapters: _wholeChapters(s),
    );
    return ListTile(
      key: ValueKey('outline-section-${tree.outline.key}-$section'),
      selected: selected,
      contentPadding: EdgeInsetsDirectional.only(start: 16 + indent, end: 16),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: s.title),
            if (s.subtitle.isNotEmpty)
              TextSpan(
                text: '  ${s.subtitle}',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (s.title != passage)
            Text(passage, style: theme.textTheme.labelSmall),
          OutlineSectionDetails(tree: tree, section: section),
        ],
      ),
      onTap: onNavigateToPassage == null
          ? null
          : () => _read(s, onNavigateToPassage),
    );
  }
}

/// Haqor's book outlines, to choose one from.
class OutlinesPage extends StatefulWidget {
  const OutlinesPage({
    super.key,
    this.store,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
  });

  /// The outlines, by default the app's.
  final OutlinesStore? store;
  final bool useEnglishBookNames;
  final OutlineNavigate? onNavigateToPassage;

  static Future<void> open(
    BuildContext context, {
    bool useEnglishBookNames = false,
    OutlineNavigate? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OutlinesPage(
        useEnglishBookNames: useEnglishBookNames,
        onNavigateToPassage: onNavigateToPassage,
      ),
    ),
  );

  @override
  State<OutlinesPage> createState() => _OutlinesPageState();
}

class _OutlinesPageState extends State<OutlinesPage> {
  late final OutlinesStore _store = widget.store ?? OutlinesStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trees = _store.trees;
    return Scaffold(
      appBar: AppBar(title: const Text('Book outlines')),
      body: !_store.loaded
          ? const Center(child: CircularProgressIndicator())
          : trees.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This database has no book outlines. Update the app\'s '
                  'data to see them.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final t in trees)
                  ListTile(
                    key: ValueKey('outline-${t.outline.key}'),
                    title: Text(t.outline.title),
                    subtitle: Text(
                      t.outline.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => OutlinePage.open(
                      context,
                      t,
                      useEnglishBookNames: widget.useEnglishBookNames,
                      onNavigateToPassage: widget.onNavigateToPassage,
                      closeCaller: true,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// How [OutlinePage] lists an outline.
enum OutlineView {
  structure('Structure', Icons.account_tree_outlined),
  list('Index', Icons.list);

  const OutlineView(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// One outline: as a tree to fold and unfold, or as an index of its
/// smallest sections filtered by its facets and a search.
class OutlinePage extends StatefulWidget {
  const OutlinePage({
    super.key,
    required this.tree,
    this.initialSection,
    this.initialView = OutlineView.structure,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
  });

  final OutlineTree tree;

  /// The section to show unfolded and marked, if any.
  final int? initialSection;
  final OutlineView initialView;
  final bool useEnglishBookNames;
  final OutlineNavigate? onNavigateToPassage;

  /// Opens [tree] above the route of [context]. A passage closes it, and
  /// every page above it, back to that route, and that route too when
  /// [closeCaller], before opening in the reader.
  static Future<void> open(
    BuildContext context,
    OutlineTree tree, {
    int? section,
    bool useEnglishBookNames = false,
    OutlineNavigate? onNavigateToPassage,
    bool closeCaller = false,
  }) {
    final navigator = Navigator.of(context);
    final caller = ModalRoute.of(context);
    return navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => OutlinePage(
          tree: tree,
          initialSection: section,
          useEnglishBookNames: useEnglishBookNames,
          onNavigateToPassage: onNavigateToPassage == null
              ? null
              : (book, chapter, verse) {
                  navigator.popUntil((route) => route == caller);
                  if (closeCaller) navigator.maybePop();
                  onNavigateToPassage(book, chapter, verse);
                },
        ),
      ),
    );
  }

  @override
  State<OutlinePage> createState() => _OutlinePageState();
}

class _OutlinePageState extends State<OutlinePage> {
  OutlineTree get _tree => widget.tree;

  late OutlineView _view = widget.initialView;

  /// The sections unfolded in the tree.
  late final Set<int> _open = {
    if (widget.initialSection case final s?) ..._tree.pathTo(s),
  };

  final _selectedKey = GlobalKey();

  String _query = '';

  /// The values chosen of each facet, by its key: a leaf passes with any of
  /// a facet's chosen values, and every facet with any chosen.
  final Map<String, Set<String>> _chosen = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _selectedKey.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(context, alignment: 0.3);
        }
      });
    }
  }

  bool _passes(int leaf) {
    final s = _tree[leaf];
    for (final MapEntry(:key, :value) in _chosen.entries) {
      if (value.isNotEmpty && !s.factsOf(key).any(value.contains)) {
        return false;
      }
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      s.title,
      s.subtitle,
      s.superscription,
      s.note,
      outlinePassageLabel(s, useEnglish: widget.useEnglishBookNames),
      for (final f in s.facts) ...f.values,
    ].any((text) => text.toLowerCase().contains(query));
  }

  Widget _tile(int section, {double indent = 0}) => OutlineSectionTile(
    key: section == widget.initialSection ? _selectedKey : null,
    tree: _tree,
    section: section,
    indent: indent,
    selected: section == widget.initialSection,
    useEnglishBookNames: widget.useEnglishBookNames,
    onNavigateToPassage: widget.onNavigateToPassage,
  );

  /// [section] and, unfolded, those inside it, [depth] deep.
  List<Widget> _branch(int section, int depth) {
    final indent = 16.0 * depth;
    // A leaf lines up under its parent's title, past the fold arrow.
    if (_tree.isLeaf(section)) return [_tile(section, indent: indent + 12)];
    final theme = Theme.of(context);
    final s = _tree[section];
    final open = _open.contains(section);
    return [
      ListTile(
        key: ValueKey('outline-group-${_tree.outline.key}-$section'),
        selected: section == widget.initialSection,
        contentPadding: EdgeInsetsDirectional.only(start: 4 + indent, end: 4),
        leading: Icon(open ? Icons.expand_more : Icons.chevron_right),
        minLeadingWidth: 24,
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: s.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: depth == 0 ? theme.colorScheme.primary : null,
                ),
              ),
              if (s.subtitle.isNotEmpty)
                TextSpan(
                  text: '  ${s.subtitle}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        subtitle: open
            ? OutlineSectionDetails(tree: _tree, section: section)
            : null,
        trailing: widget.onNavigateToPassage == null
            ? null
            : IconButton(
                tooltip: 'Read',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => _read(s, widget.onNavigateToPassage),
              ),
        onTap: () =>
            setState(() => open ? _open.remove(section) : _open.add(section)),
      ),
      if (open)
        for (final c in _tree.children(section)) ..._branch(c, depth + 1),
    ];
  }

  Widget _structure(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(_tree.outline.note, style: theme.textTheme.bodySmall),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton(
                onPressed: () => setState(() {
                  if (_open.isEmpty) {
                    _open.addAll([
                      for (var i = 0; i < _tree.outline.sections.length; i++)
                        if (!_tree.isLeaf(i)) i,
                    ]);
                  } else {
                    _open.clear();
                  }
                }),
                child: Text(_open.isEmpty ? 'Unfold all' : 'Fold all'),
              ),
            ),
          ),
          for (final t in _tree.top) ..._branch(t, 0),
        ],
      ),
    );
  }

  Widget _index(BuildContext context) {
    final theme = Theme.of(context);
    final leaves = _tree.leaves.where(_passes).toList();
    final facets = [
      for (final f in _tree.outline.facets)
        if (_tree.valuesOf(f.key).isNotEmpty) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            key: const ValueKey('outline-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search titles and notes',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        for (final f in facets)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Center(
                    child: Text(f.title, style: theme.textTheme.labelMedium),
                  ),
                ),
                for (final (value, count) in _tree.valuesOf(f.key))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilterChip(
                      key: ValueKey('outline-facet-${f.key}-$value'),
                      visualDensity: VisualDensity.compact,
                      label: Text('$value ($count)'),
                      selected: _chosen[f.key]?.contains(value) ?? false,
                      onSelected: (on) => setState(() {
                        final chosen = _chosen[f.key] ??= {};
                        on ? chosen.add(value) : chosen.remove(value);
                      }),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '${leaves.length} of ${_tree.leaves.length}',
            style: theme.textTheme.labelSmall,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: leaves.length,
            itemBuilder: (context, i) => _tile(leaves[i]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_tree.outline.title),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<OutlineView>(
            key: const ValueKey('outline-view'),
            showSelectedIcon: false,
            segments: [
              for (final v in OutlineView.values)
                ButtonSegment(
                  value: v,
                  icon: Icon(v.icon),
                  label: Text(v.label),
                ),
            ],
            selected: {_view},
            onSelectionChanged: (picked) =>
                setState(() => _view = picked.single),
          ),
        ),
      ),
    ),
    body: switch (_view) {
      OutlineView.structure => _structure(context),
      OutlineView.list => _index(context),
    },
  );
}

/// Where chapters [chapter] to [lastChapter] of a book stand in each outline
/// touching them: the sections around them, from the top down, and the
/// smallest sections in them with their titles and facts.
class ChapterOutlinesSheet extends StatefulWidget {
  const ChapterOutlinesSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.lastChapter,
    this.store,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;
  final int lastChapter;

  /// The outlines, by default the app's.
  final OutlinesStore? store;
  final bool useEnglishBookNames;
  final OutlineNavigate? onNavigateToPassage;

  @override
  State<ChapterOutlinesSheet> createState() => _ChapterOutlinesSheetState();
}

class _ChapterOutlinesSheetState extends State<ChapterOutlinesSheet> {
  late final OutlinesStore _store = widget.store ?? OutlinesStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final book = widget.bookIndex + 1;
    final first = widget.chapter;
    final last = widget.lastChapter;
    final trees = _store.touching(book, first, last);
    if (trees.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No book outline covers these chapters.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final navigate = _closing(
      context,
      widget.onNavigateToPassage,
      closeOwn: false,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final t in trees) ...[
          Builder(
            builder: (context) {
              final path = t.pathAround(book, first, last);
              final leaves = t.leavesTouching(book, first, last);
              // The path's last is shown in full below when it is the one
              // leaf.
              final around = [
                for (final i in path)
                  if (!(leaves.length == 1 && leaves.single == i)) i,
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    key: ValueKey('chapter-outline-${t.outline.key}'),
                    title: Text(
                      t.outline.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    subtitle: around.isEmpty
                        ? null
                        : Text(
                            [
                              for (final i in around)
                                t[i].subtitle.isEmpty
                                    ? t[i].title
                                    : '${t[i].title} (${t[i].subtitle})',
                            ].join(' › '),
                          ),
                    trailing: TextButton(
                      onPressed: () => OutlinePage.open(
                        context,
                        t,
                        section: leaves.firstOrNull ?? path.lastOrNull,
                        useEnglishBookNames: widget.useEnglishBookNames,
                        onNavigateToPassage: widget.onNavigateToPassage,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                  for (final i in leaves)
                    OutlineSectionTile(
                      tree: t,
                      section: i,
                      indent: 8,
                      useEnglishBookNames: widget.useEnglishBookNames,
                      onNavigateToPassage: navigate,
                    ),
                  const Divider(height: 1),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
