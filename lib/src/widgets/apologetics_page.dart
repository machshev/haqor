import 'package:flutter/material.dart';

import '../apologetics.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'chapter_span.dart';

/// Opens a passage in the reader: 0-based book index, chapter, verse.
typedef NavigateToPassage =
    void Function(int bookIndex, int chapter, int verse);

/// A passage by name: "Luke 23:42–43", "Isaiah 52:13–53:12".
String apologeticPassageLabel(PassageSpan s, {required bool useEnglish}) {
  final start =
      '${bookDisplayName(s.book - 1, useEnglish: useEnglish)} '
      '${s.chapter}:${s.verse}';
  if (s.lastChapter == s.chapter && s.lastVerse == s.verse) return start;
  if (s.lastChapter == s.chapter) return '$start–${s.lastVerse}';
  return '$start–${s.lastChapter}:${s.lastVerse}';
}

/// [navigate], first closing every route above [context]'s own, and that one
/// too when [closeOwn].
NavigateToPassage? _closing(
  BuildContext context,
  NavigateToPassage? navigate, {
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

/// A small label for what an entry is.
class ApologeticKindBadge extends StatelessWidget {
  const ApologeticKindBadge({super.key, required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (kind) {
      'evidence' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'doctrine' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        apologeticKindLabel(kind),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground),
      ),
    );
  }
}

/// Everything in an entry: its summary for a conversation, the passages it
/// marks, its argument step by step with the passages that show each step,
/// the objections and their answers, and the entries related to it.
class ApologeticCard extends StatelessWidget {
  const ApologeticCard({
    super.key,
    required this.entry,
    this.subjectTitle,
    this.store,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.onOpenEntry,
    this.onOpenTopic,
  });

  final ApologeticEntry entry;
  final String? subjectTitle;

  /// Lists a topic's entries, by key; without it the topics are not shown.
  final ValueChanged<String>? onOpenTopic;

  /// Where related entries are found, by default the app's.
  final ApologeticsStore? store;
  final bool useEnglishBookNames;
  final NavigateToPassage? onNavigateToPassage;

  /// Opens a related entry, by key.
  final ValueChanged<String>? onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final e = entry;
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
    Widget passages(List<PassageSpan> spans) => spans.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in spans)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      apologeticPassageLabel(
                        p,
                        useEnglish: useEnglishBookNames,
                      ),
                    ),
                    onPressed: onNavigateToPassage == null
                        ? null
                        : () => onNavigateToPassage!(
                            p.book - 1,
                            p.chapter,
                            p.verse,
                          ),
                  ),
              ],
            ),
          );
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              ApologeticKindBadge(kind: e.kind),
              if (subjectTitle != null) ...[
                const SizedBox(width: 8),
                Flexible(child: Text(subjectTitle!, style: muted)),
              ],
            ],
          ),
          if (e.topics.isNotEmpty && onOpenTopic != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final key in e.topics)
                    ActionChip(
                      key: ValueKey('apologetic-topic-$key'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      avatar: const Icon(Icons.sell_outlined, size: 16),
                      label: Text(
                        (store ?? ApologeticsStore.instance)
                                .topic(key)
                                ?.title ??
                            key,
                      ),
                      onPressed: () => onOpenTopic!(key),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(e.summary, style: theme.textTheme.bodyLarge),
          passages(e.passages),
          if (e.points.isNotEmpty)
            section('The argument', [
              for (final (i, p) in e.points.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text('${i + 1}.', style: muted),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.claim),
                            passages(p.passages),
                            for (final s in p.sources)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  [
                                    [
                                      s.author,
                                      s.title,
                                    ].where((t) => t.isNotEmpty).join(', '),
                                    if (s.loc.isNotEmpty) s.loc,
                                  ].join(' '),
                                  style: muted,
                                ),
                              ),
                            for (final s in p.sources)
                              if (s.quote.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '“${s.quote}”',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          if (e.objections.isNotEmpty)
            section('Objections', [
              for (final o in e.objections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.objection,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(o.answer),
                      passages(o.passages),
                    ],
                  ),
                ),
            ]),
          if (e.related.isNotEmpty && onOpenEntry != null)
            section('Related', [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final key in e.related)
                    ActionChip(
                      key: ValueKey('apologetic-related-$key'),
                      avatar: const Icon(Icons.arrow_forward, size: 16),
                      label: Text(
                        (store ?? ApologeticsStore.instance)
                                .byKey(key)
                                ?.title ??
                            key,
                      ),
                      onPressed: () => onOpenEntry!(key),
                    ),
                ],
              ),
            ]),
        ],
      ),
    );
  }
}

/// Opens [entry] on a page of its own above [context], its related entries
/// each opening another above it. A passage closes them all, and the route
/// of [context] too when [closeOwn], before opening in the reader.
Future<void> openApologetic(
  BuildContext context,
  ApologeticEntry entry, {
  ApologeticsStore? store,
  bool useEnglishBookNames = false,
  NavigateToPassage? onNavigateToPassage,
  ValueChanged<String>? onOpenTopic,
  bool closeOwn = false,
}) {
  final s = store ?? ApologeticsStore.instance;
  final navigate = _closing(context, onNavigateToPassage, closeOwn: closeOwn);
  late Future<void> Function(ApologeticEntry) push;
  push = (ApologeticEntry e) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(apologeticKindLabel(e.kind))),
        body: ListView(
          key: ValueKey('apologetic-page-${e.key}'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            ApologeticCard(
              entry: e,
              store: s,
              subjectTitle: s.subject(e.subject)?.title,
              useEnglishBookNames: useEnglishBookNames,
              onNavigateToPassage: navigate,
              onOpenTopic: onOpenTopic,
              onOpenEntry: (key) {
                final related = s.byKey(key);
                if (related != null) push(related);
              },
            ),
          ],
        ),
      ),
    ),
  );
  return push(entry);
}

/// Opens the entries a verse marks: one straight to its page, several as a
/// list to choose from.
Future<void> openApologeticsAt(
  BuildContext context,
  List<ApologeticEntry> entries, {
  bool useEnglishBookNames = false,
  NavigateToPassage? onNavigateToPassage,
}) async {
  if (entries.isEmpty) return;
  if (entries.length == 1) {
    return openApologetic(
      context,
      entries.single,
      useEnglishBookNames: useEnglishBookNames,
      onNavigateToPassage: onNavigateToPassage,
    );
  }
  final chosen = await showModalBottomSheet<ApologeticEntry>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final e in entries)
            ListTile(
              title: Text(e.title),
              trailing: ApologeticKindBadge(kind: e.kind),
              onTap: () => Navigator.of(sheet).pop(e),
            ),
        ],
      ),
    ),
  );
  if (chosen != null && context.mounted) {
    await openApologetic(
      context,
      chosen,
      useEnglishBookNames: useEnglishBookNames,
      onNavigateToPassage: onNavigateToPassage,
    );
  }
}

/// How the apologetics page indexes its entries.
enum ApologeticsIndex {
  /// By subject, each entry once.
  subjects,

  /// By topic, cutting across subjects: an entry may show under several.
  topics,

  /// By whom a conversation is with: common ground, then where they differ.
  audiences,
}

/// Every entry of Haqor's apologetics, for a quick answer in a conversation:
/// indexed by subject, by topic or by whom the conversation is with, searched
/// by words or a passage, and narrowed to one subject, topic or audience and
/// a kind. An entry shows beside the list on a wide screen and on its own
/// page on a narrow one; a passage opens in the reader, closing the page.
class ApologeticsPage extends StatefulWidget {
  const ApologeticsPage({
    super.key,
    this.store,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
  });

  /// The entries, by default the app's.
  final ApologeticsStore? store;
  final bool useEnglishBookNames;
  final NavigateToPassage? onNavigateToPassage;

  static Future<void> open(
    BuildContext context, {
    bool useEnglishBookNames = false,
    NavigateToPassage? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ApologeticsPage(
        useEnglishBookNames: useEnglishBookNames,
        onNavigateToPassage: onNavigateToPassage,
      ),
    ),
  );

  @override
  State<ApologeticsPage> createState() => _ApologeticsPageState();
}

class _ApologeticsPageState extends State<ApologeticsPage> {
  late final ApologeticsStore _store =
      widget.store ?? ApologeticsStore.instance;

  String _query = '';

  ApologeticsIndex _index = ApologeticsIndex.subjects;

  /// The subject shown, or null for all.
  String? _subject;

  /// The topic shown, or null for all.
  String? _topic;

  /// Whom the conversation is with, or null to choose.
  String? _audience;

  /// The kind shown, or null for all.
  String? _kind;

  String? _selectedKey;

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

  /// Whether [e] passes the search and the kind; the index's own choice is
  /// applied as the list is grouped.
  bool _matches(ApologeticEntry e) {
    if (_kind != null && e.kind != _kind) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    String label(PassageSpan p) =>
        apologeticPassageLabel(p, useEnglish: widget.useEnglishBookNames);
    return [
      e.title,
      e.summary,
      for (final p in e.points) ...[p.claim, ...p.passages.map(label)],
      for (final o in e.objections) ...[o.objection, o.answer],
      ...e.passages.map(label),
    ].any((text) => text.toLowerCase().contains(query));
  }

  NavigateToPassage? get _navigate =>
      _closing(context, widget.onNavigateToPassage, closeOwn: true);

  Widget _card(ApologeticEntry e) => ApologeticCard(
    key: ValueKey('apologetic-${e.key}'),
    entry: e,
    store: _store,
    subjectTitle: _store.subject(e.subject)?.title,
    useEnglishBookNames: widget.useEnglishBookNames,
    onNavigateToPassage: _navigate,
    onOpenEntry: (key) => setState(() => _selectedKey = key),
    onOpenTopic: _showTopic,
  );

  /// Lists [key]'s entries, closing any entry page above this one.
  void _showTopic(String key) {
    final own = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == own);
    setState(() {
      _index = ApologeticsIndex.topics;
      _topic = key;
    });
  }

  void _openOwnPage(ApologeticEntry e) => openApologetic(
    context,
    e,
    store: _store,
    useEnglishBookNames: widget.useEnglishBookNames,
    onNavigateToPassage: widget.onNavigateToPassage,
    onOpenTopic: _showTopic,
    closeOwn: true,
  );

  @override
  Widget build(BuildContext context) {
    final all = _store.entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Apologetics')),
      body: !_store.loaded
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This database has no apologetics. Update the app\'s data '
                  'to see them.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                final groups = _groups(all.where(_matches).toList());
                final count = {
                  for (final g in groups)
                    for (final e in g.entries) e.key,
                }.length;
                final list = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _controls(context, count),
                    const Divider(height: 1),
                    Expanded(child: _list(context, groups, wide: wide)),
                  ],
                );
                if (!wide) return list;
                final selected = _store.byKey(_selectedKey ?? '');
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 420, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const Center(child: Text('Choose an entry.'))
                          : ListView(
                              key: ValueKey('detail-${selected.key}'),
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                32,
                              ),
                              children: [_card(selected)],
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _controls(BuildContext context, int count) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const ValueKey('apologetics-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search subjects, answers and passages',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: SegmentedButton<ApologeticsIndex>(
            key: const ValueKey('apologetics-index'),
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(
                value: ApologeticsIndex.subjects,
                label: Text('Subjects'),
              ),
              if (_store.topics.isNotEmpty)
                const ButtonSegment(
                  value: ApologeticsIndex.topics,
                  label: Text('Topics'),
                ),
              if (_store.audiences.isNotEmpty)
                const ButtonSegment(
                  value: ApologeticsIndex.audiences,
                  label: Text('Talking with'),
                ),
            ],
            selected: {_index},
            onSelectionChanged: (chosen) =>
                setState(() => _index = chosen.single),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              for (final (key, label, tooltip) in _choices())
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('apologetics-${_index.name}-${key ?? 'all'}'),
                    label: Text(label),
                    tooltip: tooltip,
                    selected: _chosen == key,
                    onSelected: (_) => setState(() => _chosen = key),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 6,
            children: [
              for (final k in const [null, 'evidence', 'doctrine', 'passage'])
                ChoiceChip(
                  key: ValueKey('apologetics-kind-${k ?? 'all'}'),
                  visualDensity: VisualDensity.compact,
                  label: Text(k == null ? 'All kinds' : apologeticKindLabel(k)),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Text(
            _choosingAudience
                ? 'Choose whom you are talking with'
                : count == 1
                ? '1 entry'
                : '$count entries',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  /// The current index's choice: a subject, topic or audience key, or null.
  String? get _chosen => switch (_index) {
    ApologeticsIndex.subjects => _subject,
    ApologeticsIndex.topics => _topic,
    ApologeticsIndex.audiences => _audience,
  };

  set _chosen(String? key) => switch (_index) {
    ApologeticsIndex.subjects => _subject = key,
    ApologeticsIndex.topics => _topic = key,
    ApologeticsIndex.audiences => _audience = key,
  };

  bool get _choosingAudience =>
      _index == ApologeticsIndex.audiences && _audience == null;

  /// The chips of the current index: key, label and tooltip, all first.
  List<(String?, String, String?)> _choices() => switch (_index) {
    ApologeticsIndex.subjects => [
      (null, 'All subjects', null),
      for (final s in _store.subjects) (s.key, s.title, s.note),
    ],
    ApologeticsIndex.topics => [
      (null, 'All topics', null),
      for (final t in _store.topics) (t.key, t.title, null),
    ],
    ApologeticsIndex.audiences => [
      (null, 'Everyone', null),
      for (final a in _store.audiences) (a.key, a.title, null),
    ],
  };

  /// The headed groups the list shows, of the [shown] entries, by the
  /// current index and its choice.
  List<({String title, List<ApologeticEntry> entries})> _groups(
    List<ApologeticEntry> shown,
  ) {
    final keys = {for (final e in shown) e.key};
    List<ApologeticEntry> only(Iterable<ApologeticEntry> entries) => [
      for (final e in entries)
        if (keys.contains(e.key)) e,
    ];
    final groups = switch (_index) {
      ApologeticsIndex.subjects => [
        for (final s in _store.subjects)
          if (_subject == null || s.key == _subject)
            (
              title: s.title,
              entries: only(shown.where((e) => e.subject == s.key)),
            ),
      ],
      ApologeticsIndex.topics => [
        for (final t in _store.topics)
          if (_topic == null || t.key == _topic)
            (
              title: t.title,
              entries: only(shown.where((e) => e.topics.contains(t.key))),
            ),
      ],
      ApologeticsIndex.audiences => [
        if (_store.audience(_audience ?? '') case final a?) ...[
          (title: 'Common ground', entries: only(_store.byKeys(a.agree))),
          (title: 'Where you differ', entries: only(_store.byKeys(a.differ))),
        ],
      ],
    };
    return [
      for (final g in groups)
        if (g.entries.isNotEmpty) g,
    ];
  }

  Widget _list(
    BuildContext context,
    List<({String title, List<ApologeticEntry> entries})> groups, {
    required bool wide,
  }) {
    final theme = Theme.of(context);
    if (_choosingAudience) {
      return ListView(
        key: const ValueKey('apologetics-audiences'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final a in _store.audiences)
            ListTile(
              key: ValueKey('apologetics-audience-row-${a.key}'),
              title: Text(a.title),
              subtitle: Text(
                a.note,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => _audience = a.key),
            ),
        ],
      );
    }
    final audience = _index == ApologeticsIndex.audiences
        ? _store.audience(_audience ?? '')
        : null;
    final rows = <Widget>[
      if (audience != null)
        Padding(
          key: const ValueKey('apologetics-audience-note'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(audience.note, style: theme.textTheme.bodyMedium),
        ),
    ];
    final listed = <String>{};
    if (groups.isEmpty) {
      rows.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nothing matches.')),
        ),
      );
    }
    for (final group in groups) {
      final entries = group.entries;
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            group.title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
      for (final e in entries) {
        // An entry under several topics is keyed by its first.
        final first = listed.add(e.key);
        rows.add(
          ListTile(
            key: ValueKey(
              first
                  ? 'apologetic-row-${e.key}'
                  : 'apologetic-row-${e.key}@${group.title}',
            ),
            selected: wide && e.key == _selectedKey,
            title: Text(e.title),
            subtitle: Text(
              e.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: ApologeticKindBadge(kind: e.kind),
            onTap: () =>
                wide ? setState(() => _selectedKey = e.key) : _openOwnPage(e),
          ),
        );
      }
    }
    return ListView(
      key: const ValueKey('apologetics-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: rows,
    );
  }
}

/// The entries marking one chapter, or a run of them, with the passages
/// there each marks: a tab of the chapter context.
class ChapterApologeticsSheet extends StatefulWidget {
  const ChapterApologeticsSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.lastChapter,
    this.store,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;
  final int? lastChapter;
  final ApologeticsStore? store;
  final bool useEnglishBookNames;
  final NavigateToPassage? onNavigateToPassage;

  int get toChapter => lastChapter ?? chapter;

  @override
  State<ChapterApologeticsSheet> createState() =>
      _ChapterApologeticsSheetState();
}

class _ChapterApologeticsSheetState extends State<ChapterApologeticsSheet> {
  late final ApologeticsStore _store =
      widget.store ?? ApologeticsStore.instance;

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
    if (!_store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final book = widget.bookIndex + 1;
    final entries = _store.touching(book, widget.chapter, widget.toChapter);
    if (entries.isEmpty) {
      final where = chapterSpanName(
        widget.bookIndex,
        widget.chapter,
        widget.toChapter,
        useEnglish: widget.useEnglishBookNames,
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No apologetics mark $where yet.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('chapter-apologetics'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final e in entries)
          ListTile(
            key: ValueKey('chapter-apologetic-${e.key}'),
            title: Text(e.title),
            subtitle: Text(
              e.passages
                  .where(
                    (p) => passageTouches(
                      p,
                      book,
                      widget.chapter,
                      widget.toChapter,
                    ),
                  )
                  .map(
                    (p) => apologeticPassageLabel(
                      p,
                      useEnglish: widget.useEnglishBookNames,
                    ),
                  )
                  .join(', '),
            ),
            trailing: ApologeticKindBadge(kind: e.kind),
            onTap: () => openApologetic(
              context,
              e,
              store: _store,
              useEnglishBookNames: widget.useEnglishBookNames,
              onNavigateToPassage: widget.onNavigateToPassage,
              closeOwn: true,
            ),
          ),
      ],
    );
  }
}
