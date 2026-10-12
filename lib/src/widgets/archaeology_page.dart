import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../external_link.dart';
import 'multi_select_chip.dart';
import 'name_details.dart';

/// The eras the index groups finds by, each the years it starts at (the
/// first from the beginning), in order.
const archaeologyEras = <(int, String)>[
  (-100000, 'Before the kings'),
  (-1000, 'The kings of Israel and Judah'),
  (-722, 'Assyria and Judah'),
  (-586, 'Babylon and Persia'),
  (-332, 'The Greeks and Romans'),
  (1, 'The New Testament'),
];

/// The era a find's year falls in.
String archaeologyEra(int year) =>
    archaeologyEras.lastWhere((era) => year >= era.$1).$2;

/// A link's strength as the reader sees it.
String strengthLabel(String strength) => switch (strength) {
  'strong' => 'Strong',
  'reasonable' => 'Reasonable',
  _ => 'Possible',
};

/// What each strength means, for its tooltip.
String strengthMeaning(String strength) => switch (strength) {
  'strong' =>
    'Names them in a way that can only be the Bible\'s, or matches the '
        'passage directly',
  'reasonable' =>
    'Likely, but the reading is restored or damaged, the identification '
        'debated, or the match is to the circumstances',
  _ => 'Argued for by some, doubted by many',
};

/// The strongest of a find's links.
String strongestOf(ArtifactEntry a) {
  final all = [
    ...a.attestations.map((t) => t.strength),
    ...a.passages.map((p) => p.strength),
  ];
  for (final s in ['strong', 'reasonable', 'possible']) {
    if (all.contains(s)) return s;
  }
  return '';
}

/// A small coloured label for a link's strength.
class StrengthBadge extends StatelessWidget {
  const StrengthBadge({super.key, required this.strength});

  final String strength;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (strength) {
      'strong' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'reasonable' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Tooltip(
      message: strengthMeaning(strength),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          strengthLabel(strength),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

String _passage(PassageSpan s, {required bool useEnglish}) {
  final start =
      '${bookDisplayName(s.book - 1, useEnglish: useEnglish)} '
      '${s.chapter}:${s.verse}';
  if (s.lastChapter == s.chapter && s.lastVerse == s.verse) return start;
  if (s.lastChapter == s.chapter) return '$start–${s.lastVerse}';
  return '$start–${s.lastChapter}:${s.lastVerse}';
}

/// Everything known of a find: what it is and says, the people it names
/// and the passages it bears on, each with its strength, how it matches and
/// its source; where it was found and is now; and its Wikipedia article.
class ArtifactCard extends StatelessWidget {
  const ArtifactCard({
    super.key,
    required this.artifact,
    required this.sources,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.onOpenPerson,
  });

  final ArtifactEntry artifact;
  final List<ArtifactSourceEntry> sources;
  final bool useEnglishBookNames;

  /// Opens a passage in the reader: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(NameSummaryEntry person)? onOpenPerson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final a = artifact;
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
    Widget link({
      required String strength,
      required Widget title,
      required String how,
      required String source,
      VoidCallback? onTap,
    }) => ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: onTap,
      title: Row(
        children: [
          Flexible(child: title),
          const SizedBox(width: 8),
          StrengthBadge(strength: strength),
        ],
      ),
      subtitle: Text([how, ?_citation(source)].join('\n')),
    );
    final found = [
      if (a.foundSite.isNotEmpty) a.foundSite,
      if (a.foundYear != 0) '${a.foundYear}',
    ].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(a.name, style: theme.textTheme.titleLarge),
        if (a.otherNames.isNotEmpty)
          Text('Also: ${a.otherNames.join(', ')}', style: muted),
        const SizedBox(height: 4),
        Text(
          [a.date, a.kind, if (a.script.isNotEmpty) a.script].join(' · '),
          style: muted,
        ),
        const SizedBox(height: 12),
        Text(a.summary, style: theme.textTheme.bodyMedium),
        if (a.attestations.isNotEmpty)
          section('Names', [
            for (final t in a.attestations)
              link(
                strength: t.strength,
                title: Text(
                  t.person.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onOpenPerson == null
                        ? null
                        : theme.colorScheme.primary,
                  ),
                ),
                how: t.how,
                source: t.source,
                onTap: onOpenPerson == null
                    ? null
                    : () => onOpenPerson!(t.person),
              ),
          ]),
        if (a.passages.isNotEmpty)
          section('Bears on', [
            for (final p in a.passages)
              link(
                strength: p.strength,
                title: Text(
                  _passage(p.passage, useEnglish: useEnglishBookNames),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: onNavigateToPassage == null
                        ? null
                        : theme.colorScheme.primary,
                  ),
                ),
                how: p.how,
                source: p.source,
                onTap: onNavigateToPassage == null
                    ? null
                    : () => onNavigateToPassage!(
                        p.passage.book - 1,
                        p.passage.chapter,
                        p.passage.verse,
                      ),
              ),
          ]),
        section('Where it is', [
          if (found.isNotEmpty) Text('Found: $found'),
          Text(a.museum.isEmpty ? 'Now: not recorded' : 'Now: ${a.museum}'),
        ]),
        if (a.wikipedia.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Wikipedia'),
              onPressed: () => openExternalLink(
                Uri.https(
                  'en.wikipedia.org',
                  '/wiki/${a.wikipedia.replaceAll(' ', '_')}',
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// A link's source, briefly: "Source: Mykytiuk, BAR 2014".
  String? _citation(String id) {
    final source = sources.where((s) => s.id == id).firstOrNull;
    if (source == null) return null;
    return 'Source: ${source.citation}';
  }
}

/// Every archaeological find that bears on the Bible, grouped by era: the
/// inscriptions naming its people, the sites it describes and the early
/// copies of its text. Searched by name, person, place or passage, and
/// filtered by kind and by how strong a link must be. A find shows beside
/// the list on a wide screen and on its own page on a narrow one; a passage
/// opens in the reader, closing the page.
class ArchaeologyPage extends StatefulWidget {
  const ArchaeologyPage({
    super.key,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNtGreekChanged,
    this.bookmarks,
    this.onNavigateToPassage,
    this.sendRequest,
  });

  final bool useEnglishBookNames;
  final bool ntSyriac;
  final bool ntGreek;
  final ValueChanged<bool>? onNtGreekChanged;
  final NameBookmarks? bookmarks;

  /// Opens a passage in the reader: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Stands in for the signal to Rust, for tests.
  final void Function(GetArtifacts)? sendRequest;

  static Future<void> open(
    BuildContext context, {
    bool useEnglishBookNames = false,
    bool ntSyriac = false,
    bool ntGreek = false,
    ValueChanged<bool>? onNtGreekChanged,
    NameBookmarks? bookmarks,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ArchaeologyPage(
        useEnglishBookNames: useEnglishBookNames,
        ntSyriac: ntSyriac,
        ntGreek: ntGreek,
        onNtGreekChanged: onNtGreekChanged,
        bookmarks: bookmarks,
        onNavigateToPassage: onNavigateToPassage,
      ),
    ),
  );

  @override
  State<ArchaeologyPage> createState() => _ArchaeologyPageState();
}

class _ArchaeologyPageState extends State<ArchaeologyPage> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<Artifacts>>? _sub;
  int _requestId = 0;
  Artifacts? _reply;

  String _query = '';

  /// The kinds of find shown, none for all.
  Set<String> _kindsShown = {};

  /// Only finds with a strong link.
  bool _strongOnly = false;

  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _sub = Artifacts.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId || !mounted) return;
      setState(() => _reply = reply);
    });
    final request = GetArtifacts(requestId: _requestId = _nextRequestId++);
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
    super.dispose();
  }

  /// The kinds of find there are, most common first.
  List<String> _kinds(List<ArtifactEntry> all) {
    final counts = <String, int>{};
    for (final a in all) {
      counts[a.kind] = (counts[a.kind] ?? 0) + 1;
    }
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  bool _matches(ArtifactEntry a) {
    if (_kindsShown.isNotEmpty && !_kindsShown.contains(a.kind)) return false;
    if (_strongOnly && strongestOf(a) != 'strong') return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      a.name,
      ...a.otherNames,
      a.summary,
      a.foundSite,
      a.museum,
      a.script,
      for (final t in a.attestations) t.person.name,
      for (final p in a.passages)
        _passage(p.passage, useEnglish: widget.useEnglishBookNames),
    ].any((text) => text.toLowerCase().contains(query));
  }

  /// Opens a passage in the reader, closing the page (and a find's own
  /// page above it).
  void Function(int, int, int)? get _navigate {
    final navigate = widget.onNavigateToPassage;
    if (navigate == null) return null;
    return (book, chapter, verse) {
      final page = ModalRoute.of(context);
      Navigator.of(context)
        ..popUntil((route) => route == page)
        ..maybePop();
      navigate(book, chapter, verse);
    };
  }

  void _openPerson(NameSummaryEntry person) => NameDetailsPage.open(
    context,
    id: person.id,
    title: person.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    ntSyriac: widget.ntSyriac,
    ntGreek: widget.ntGreek,
    onNtGreekChanged: widget.onNtGreekChanged,
    bookmarks: widget.bookmarks,
    onNavigateToPassage: _navigate,
  );

  Widget _card(ArtifactEntry a) => ArtifactCard(
    key: ValueKey('artifact-${a.id}'),
    artifact: a,
    sources: _reply?.sources ?? const [],
    useEnglishBookNames: widget.useEnglishBookNames,
    onNavigateToPassage: _navigate,
    onOpenPerson: _openPerson,
  );

  void _openOwnPage(ArtifactEntry a) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(a.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [_card(a)],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final all = _reply?.entries;
    return Scaffold(
      appBar: AppBar(title: const Text('Bible archaeology')),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This database has no archaeological finds. Update the '
                  'app\'s data to see them.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 840;
                final shown = all.where(_matches).toList();
                final list = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _controls(context, all, shown.length),
                    const Divider(height: 1),
                    Expanded(child: _list(context, shown, wide: wide)),
                  ],
                );
                if (!wide) return list;
                final selected = all
                    .where((a) => a.id == _selectedId)
                    .firstOrNull;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 420, child: list),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: selected == null
                          ? const Center(child: Text('Choose a find.'))
                          : ListView(
                              key: ValueKey('detail-${selected.id}'),
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                24,
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

  Widget _controls(BuildContext context, List<ArtifactEntry> all, int count) {
    final theme = Theme.of(context);
    String kindLabel(String kind) =>
        kind.isEmpty ? kind : kind[0].toUpperCase() + kind.substring(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const ValueKey('artifact-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search finds, people, places and references',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                key: const ValueKey('artifact-strong-only'),
                label: const Text('Strong links only'),
                selected: _strongOnly,
                onSelected: (on) => setState(() => _strongOnly = on),
              ),
              MultiSelectChip<String>(
                key: const ValueKey('artifact-kinds'),
                icon: Icons.category_outlined,
                options: [
                  for (final k in _kinds(all))
                    MultiSelectOption(k, kindLabel(k)),
                ],
                selected: _kindsShown,
                onChanged: (kinds) => setState(() => _kindsShown = kinds),
                allLabel: 'All kinds',
                plural: (n) => '$n kinds',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Text(
            count == 1 ? '1 find' : '$count finds',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(
    BuildContext context,
    List<ArtifactEntry> shown, {
    required bool wide,
  }) {
    if (shown.isEmpty) {
      return const Center(child: Text('No finds match.'));
    }
    final theme = Theme.of(context);
    final rows = <Widget>[];
    String? era;
    for (final a in shown) {
      final thisEra = archaeologyEra(a.year);
      if (thisEra != era) {
        era = thisEra;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              thisEra,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final names = a.attestations.map((t) => t.person.name).toSet();
      rows.add(
        ListTile(
          key: ValueKey('artifact-row-${a.id}'),
          dense: true,
          selected: wide && a.id == _selectedId,
          title: Text(a.name),
          subtitle: Text(
            [a.date, if (names.isNotEmpty) names.join(', ')].join(' · '),
          ),
          trailing: StrengthBadge(strength: strongestOf(a)),
          onTap: () =>
              wide ? setState(() => _selectedId = a.id) : _openOwnPage(a),
        ),
      );
    }
    return ListView(
      key: const ValueKey('artifact-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: rows,
    );
  }
}

/// The finds bearing on one chapter: first those tied to a passage in it,
/// with the verses they cover, then those naming someone the chapter names.
class ChapterArtifactsSheet extends StatefulWidget {
  const ChapterArtifactsSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNtGreekChanged,
    this.bookmarks,
    this.onNavigateToPassage,
    this.sendRequest,
    this.showTitle = true,
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;
  final bool ntSyriac;
  final bool ntGreek;
  final ValueChanged<bool>? onNtGreekChanged;
  final NameBookmarks? bookmarks;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(GetChapterArtifacts)? sendRequest;

  /// Whether the sheet names its chapter, as it does standing alone; a
  /// tab of [ChapterContextSheet] leaves that to the tabs' own heading.
  final bool showTitle;

  @override
  State<ChapterArtifactsSheet> createState() => _ChapterArtifactsSheetState();
}

class _ChapterArtifactsSheetState extends State<ChapterArtifactsSheet> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<ChapterArtifacts>>? _sub;
  int? _requestId;
  ChapterArtifacts? _reply;

  @override
  void initState() {
    super.initState();
    _sub = ChapterArtifacts.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (!mounted || reply.requestId != _requestId) return;
      setState(() => _reply = reply);
    });
    final request = GetChapterArtifacts(
      requestId: _requestId = _nextRequestId++,
      book: widget.bookIndex + 1,
      chapter: widget.chapter,
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
    super.dispose();
  }

  /// Closes the sheet (and any page above it) and opens a passage.
  void Function(int, int, int)? get _navigate {
    final navigate = widget.onNavigateToPassage;
    if (navigate == null) return null;
    return (book, chapter, verse) {
      final sheet = ModalRoute.of(context);
      Navigator.of(context)
        ..popUntil((route) => route == sheet)
        ..maybePop();
      navigate(book, chapter, verse);
    };
  }

  void _openPerson(NameSummaryEntry person) => NameDetailsPage.open(
    context,
    id: person.id,
    title: person.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    ntSyriac: widget.ntSyriac,
    ntGreek: widget.ntGreek,
    onNtGreekChanged: widget.onNtGreekChanged,
    bookmarks: widget.bookmarks,
    onNavigateToPassage: _navigate,
  );

  void _openFind(ArtifactEntry a) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(a.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            ArtifactCard(
              artifact: a,
              sources: _reply?.sources ?? const [],
              useEnglishBookNames: widget.useEnglishBookNames,
              onNavigateToPassage: _navigate,
              onOpenPerson: _openPerson,
            ),
          ],
        ),
      ),
    ),
  );

  /// "Verses 13–37", "Verses 2, 5 and 7–9".
  static String versesLabel(List<int> verses) {
    final runs = <String>[];
    var i = 0;
    while (i < verses.length) {
      var j = i;
      while (j + 1 < verses.length && verses[j + 1] == verses[j] + 1) {
        j++;
      }
      runs.add(i == j ? '${verses[i]}' : '${verses[i]}–${verses[j]}');
      i = j + 1;
    }
    final word = verses.length == 1 ? 'Verse' : 'Verses';
    if (runs.length == 1) return '$word ${runs.single}';
    return '$word ${runs.sublist(0, runs.length - 1).join(', ')} and ${runs.last}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reply = _reply;
    final title =
        'Archaeology in ${bookDisplayName(widget.bookIndex, useEnglish: widget.useEnglishBookNames)} '
        '${widget.chapter}';
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    final byPassage =
        reply?.entries.where((e) => e.verses.isNotEmpty).toList() ?? [];
    final byPerson =
        reply?.entries.where((e) => e.verses.isEmpty).toList() ?? [];
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Expanded(
            child: reply == null
                ? const Center(child: CircularProgressIndicator())
                : reply.entries.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No archaeological find bears on this chapter.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    key: const ValueKey('chapter-artifacts'),
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      if (byPassage.isNotEmpty) ...[
                        heading('About this passage'),
                        for (final e in byPassage)
                          ListTile(
                            key: ValueKey('chapter-artifact-${e.artifact.id}'),
                            title: Text(e.artifact.name),
                            subtitle: Text(
                              '${versesLabel(e.verses)} · ${e.artifact.date}',
                            ),
                            trailing: StrengthBadge(
                              strength: strongestOf(e.artifact),
                            ),
                            onTap: () => _openFind(e.artifact),
                          ),
                      ],
                      if (byPerson.isNotEmpty) ...[
                        heading('Naming someone in this chapter'),
                        for (final e in byPerson)
                          ListTile(
                            key: ValueKey('chapter-artifact-${e.artifact.id}'),
                            title: Text(e.artifact.name),
                            subtitle: Text(
                              '${e.people.map((p) => p.name).join(', ')} · '
                              '${e.artifact.date}',
                            ),
                            trailing: StrengthBadge(
                              strength: strongestOf(e.artifact),
                            ),
                            onTap: () => _openFind(e.artifact),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
