import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'lexicon_source.dart';
import 'name_details.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart'
    show CanonDistribution, LexiconEntryView, OccurrenceVerseRow, VerseModeIcon;

/// A word of the Greek New Testament (the TR), laid out as the Hebrew and
/// Aramaic word pane is: its gloss and the word over its root, its grammar as
/// chips, and two tabs, one for the words built on its root with Abbott-Smith's
/// and Thayer's entries for each, the other for their occurrences, each in its
/// verse.
class GreekWordSheet extends StatefulWidget {
  const GreekWordSheet({
    super.key,
    required this.word,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.position,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.onNavigateToPassage,
    this.nameBookmarks,
    this.sendRequest,
    this.sendVerseTextsRequest,
    this.sendDictionaryRequest,
  });

  /// The word as the reader shows it, shown until its details arrive.
  final String word;

  /// Where the word stands: its book (40 Matthew … 66 Revelation), chapter,
  /// verse and its position in the verse, from 0.
  final int book;
  final int chapter;
  final int verse;
  final int position;
  final bool useEnglishBookNames;

  /// The Peshitta's script, for the pages of a person or place it opens.
  final bool ntSyriac;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final NameBookmarks? nameBookmarks;

  /// Test seams: how the word, the occurrences' verses and a linked lexicon
  /// entry are asked for.
  final void Function(GetGreekWord request)? sendRequest;
  final void Function(GetVerseTexts request)? sendVerseTextsRequest;
  final void Function(GetDictionaryEntry request)? sendDictionaryRequest;

  @override
  State<GreekWordSheet> createState() => _GreekWordSheetState();
}

/// One verse of the occurrence list, with the positions in it to highlight.
typedef _GreekVerse = ({int book, int chapter, int verse, List<int> positions});

class _GreekWordSheetState extends State<GreekWordSheet>
    with SingleTickerProviderStateMixin {
  /// Request ids are handed out app-wide: replies are broadcast, and two
  /// panes must not take each other's.
  static int _nextRequestId = 1;

  late final int _requestId = _nextRequestId++;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  StreamSubscription<RustSignalPack<GreekWordInfo>>? _sub;
  GreekWordInfo? _info;
  bool _englishOnly = false;

  /// The root the word is read under, empty for its first.
  String _root = '';

  /// Whether the occurrence list holds every word built on the root, rather
  /// than the word's own dictionary form alone.
  bool _wholeRoot = false;

  /// The dictionary forms whose entries are shown or hidden against their
  /// default: the word's own shown, the rest hidden.
  final Set<String> _toggledLexemes = {};

  /// The books the occurrence list is narrowed to, by 1-based number; empty
  /// for all of them.
  final Set<int> _books = {};
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );

  @override
  void initState() {
    super.initState();
    _sub = GreekWordInfo.rustSignalStream.listen((pack) {
      if (pack.message.requestId != _requestId || !mounted) return;
      setState(() => _info = pack.message);
    });
    _request();
    unawaited(
      occurrenceVerseEnglishOnlyEnabled().then((enabled) {
        if (mounted) setState(() => _englishOnly = enabled);
      }),
    );
  }

  void _request() {
    final request = GetGreekWord(
      requestId: _requestId,
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
      position: widget.position,
      root: _root,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  /// Read the word under another of its roots: both tabs move to it.
  void _selectRoot(String root) {
    if (root == _info?.root) return;
    setState(() {
      _root = root;
      _toggledLexemes.clear();
      _books.clear();
    });
    _request();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tabController.dispose();
    _verseTexts.dispose();
    super.dispose();
  }

  void _toggleEnglishOnly() {
    setState(() => _englishOnly = !_englishOnly);
    unawaited(setOccurrenceVerseEnglishOnlyEnabled(_englishOnly));
  }

  String _reference(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  void _openName(NameSummaryEntry name) => NameDetailsPage.open(
    context,
    id: name.id,
    title: name.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    ntSyriac: widget.ntSyriac,
    onNavigateToPassage: widget.onNavigateToPassage,
    bookmarks: widget.nameBookmarks,
  );

  /// The occurrences merged by verse, in canonical order as they come.
  List<_GreekVerse> _verses(Iterable<GreekOccurrenceEntry> occurrences) {
    final verses = <_GreekVerse>[];
    for (final o in occurrences) {
      final last = verses.lastOrNull;
      if (last != null &&
          last.book == o.book &&
          last.chapter == o.chapter &&
          last.verse == o.verse) {
        last.positions.add(o.position);
      } else {
        verses.add((
          book: o.book,
          chapter: o.chapter,
          verse: o.verse,
          positions: [o.position],
        ));
      }
    }
    return verses;
  }

  bool _isCurrentVerse(_GreekVerse v) =>
      v.book == widget.book &&
      v.chapter == widget.chapter &&
      v.verse == widget.verse;

  Future<void> _copyReferences(List<_GreekVerse> verses) async {
    final refs = verses
        .map((v) => _reference(v.book, v.chapter, v.verse))
        .join('\n');
    await Clipboard.setData(ClipboardData(text: refs));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${verses.length} reference${verses.length == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: SelectionArea(
        child: info == null
            ? _buildLoading(context)
            : !info.found
            ? _buildNotFound(context)
            : _buildContent(context, info),
      ),
    );
  }

  TextStyle _wordStyle(ThemeData theme) => TextStyle(
    fontFamily: 'Cardo',
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: theme.colorScheme.onSurface,
  );

  /// The tapped word, as the reader had it, while its details are asked for.
  Widget _buildLoading(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(widget.word, style: _wordStyle(theme)),
          ),
        ),
        const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _buildNotFound(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          Text(widget.word, style: _wordStyle(theme)),
          const SizedBox(height: 8),
          Text(
            'Not found in lexicon',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, GreekWordInfo info) {
    final theme = Theme.of(context);
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (info.gloss.isNotEmpty)
                    Expanded(
                      child: Text(
                        info.gloss,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  // Greek words run long: the word shrinks to fit a narrow
                  // pane rather than overflow it.
                  Flexible(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            info.word.isNotEmpty ? info.word : widget.word,
                            style: _wordStyle(theme),
                          ),
                        ),
                        if (info.roots.length > 1)
                          _rootSelector(context, info)
                        else if (info.root.isNotEmpty || info.lemma.isNotEmpty)
                          Text(
                            info.root.isNotEmpty ? info.root : info.lemma,
                            style: TextStyle(
                              fontFamily: 'Cardo',
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // "verb, second aorist active participle, nominative singular
              // masculine": a chip for each part, as the Hebrew parse has.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final part in info.grammarDescription.split(', '))
                    if (part.isNotEmpty) _chip(context, part),
                ],
              ),
              if (info.english.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Here “${info.english}”',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Lexicon', height: 32),
            Tab(text: 'Occurrences', height: 32),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildLexiconTab(context, info, bottomPad),
              _buildOccurrencesTab(context, info, bottomPad),
            ],
          ),
        ),
      ],
    );
  }

  /// The roots a compound is built on, the one it is read under lit; tapping
  /// another reads it under that one.
  Widget _rootSelector(BuildContext context, GreekWordInfo info) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      children: [
        for (final root in info.roots)
          Tooltip(
            message: 'Read this word under $root',
            child: InkWell(
              onTap: () => _selectRoot(root),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: root == info.root
                      ? theme.colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: root == info.root
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  root,
                  style: TextStyle(
                    fontFamily: 'Cardo',
                    fontSize: 13,
                    color: root == info.root
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _lexemeExpanded(GreekLexemeEntry lexeme) =>
      lexeme.isCurrent != _toggledLexemes.contains(lexeme.lemma);

  /// Who or what the word names, then every dictionary form built on its
  /// root, the word's own opened on Abbott-Smith's and Thayer's entries and
  /// the rest folded to a line.
  Widget _buildLexiconTab(
    BuildContext context,
    GreekWordInfo info,
    double bottomPad,
  ) {
    final theme = Theme.of(context);
    final lexemes = info.lexemes;
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [
        // Who or what the word names here: the lexicon can only say what
        // the name means.
        if (info.name case final name?) ...[
          NameCard(name: name, onOpen: () => _openName(name)),
          const SizedBox(height: 16),
        ],
        if (lexemes.length > 1 && info.root.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Built on '),
                  TextSpan(
                    text: info.root,
                    style: const TextStyle(fontFamily: 'Cardo'),
                  ),
                ],
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final lexeme in lexemes) _lexemeRow(context, lexeme),
      ],
    );
  }

  Widget _lexemeRow(BuildContext context, GreekLexemeEntry lexeme) {
    final theme = Theme.of(context);
    final expanded = _lexemeExpanded(lexeme);
    final header = InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(() {
        if (!_toggledLexemes.remove(lexeme.lemma)) {
          _toggledLexemes.add(lexeme.lemma);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              lexeme.lemma,
              style: TextStyle(
                fontFamily: 'Cardo',
                fontSize: 18,
                fontWeight: lexeme.isCurrent ? FontWeight.bold : null,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                lexeme.gloss,
                maxLines: expanded ? null : 1,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              '${lexeme.occurrences}×',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (expanded) ...[
          if (lexeme.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 0, 8),
              child: Text(
                'No lexicon entry for this word.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final entry in lexeme.entries)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LexiconSourceBadge(source: entry.source),
                  const SizedBox(width: 6),
                  Expanded(
                    child: LexiconEntryView(
                      entry: entry,
                      onNavigateToPassage: widget.onNavigateToPassage,
                      sendDictionaryRequest: widget.sendDictionaryRequest,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
    if (!lexeme.isCurrent) return row;
    return Container(
      key: ValueKey('current-lexeme-${lexeme.lemma}'),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }

  /// A header with the scope, the count, the verse-text switch and the canon
  /// distribution over the verses, as the Hebrew pane's Occurrences tab has.
  Widget _buildOccurrencesTab(
    BuildContext context,
    GreekWordInfo info,
    double bottomPad,
  ) {
    final theme = Theme.of(context);
    final own = info.occurrences.where((o) => o.lemma == info.lemma).toList();
    // The root's other words: the choice of scope only where it has some.
    final rootWide = info.occurrences.length > own.length;
    final scoped = _wholeRoot && rootWide ? info.occurrences : own;
    final all = _verses(scoped);
    if (all.isEmpty && !rootWide) return const SizedBox.shrink();
    final bookCounts = <int, int>{};
    for (final o in scoped) {
      bookCounts[o.book] = (bookCounts[o.book] ?? 0) + 1;
    }
    final verses = _books.isEmpty
        ? all
        : all.where((v) => _books.contains(v.book)).toList();
    final hits = verses.fold(0, (sum, v) => sum + v.positions.length);
    final versePart = '${verses.length} verse${verses.length == 1 ? '' : 's'}';
    final countStyle = theme.textTheme.labelSmall;
    Widget segment(String name, int count, {bool greek = false}) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: greek ? const TextStyle(fontFamily: 'Cardo') : null,
        ),
        Text('$count', maxLines: 1, style: countStyle),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rootWide)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: segment(info.lemma, own.length, greek: true),
                      ),
                      ButtonSegment(
                        value: true,
                        label: segment(
                          'All of ${info.root}',
                          info.occurrences.length,
                          greek: true,
                        ),
                      ),
                    ],
                    selected: {_wholeRoot},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                    onSelectionChanged: (selection) => setState(() {
                      _wholeRoot = selection.first;
                      _books.clear();
                    }),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hits == verses.length ? versePart : '$versePart · $hits×',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy references',
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                    onPressed: verses.isEmpty
                        ? null
                        : () => _copyReferences(verses),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minHeight: 40),
                  ),
                  IconButton(
                    tooltip: _englishOnly
                        ? 'Show Greek verse text'
                        : 'Show English-only verse text',
                    icon: VerseModeIcon(
                      englishOnly: _englishOnly,
                      sourceLetter: 'α',
                    ),
                    onPressed: _toggleEnglishOnly,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerRight,
                    constraints: const BoxConstraints(minHeight: 40),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              CanonDistribution(
                countsByBook: bookCounts,
                selectedBooks: _books,
                useEnglishBookNames: widget.useEnglishBookNames,
                onSelect: (books) => setState(() {
                  _books
                    ..clear()
                    ..addAll(books);
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: verses.isEmpty
              ? Center(
                  child: Text(
                    'No occurrences match this filter',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _occurrenceVerseList(verses, bottomPad: bottomPad),
        ),
      ],
    );
  }

  Widget _occurrenceVerseRow(_GreekVerse v) {
    final bookIndex = v.book - 1;
    return OccurrenceVerseRow(
      key: ValueKey('${v.book}:${v.chapter}:${v.verse}'),
      cache: _verseTexts,
      displayRef: _reference(v.book, v.chapter, v.verse),
      bookIndex: bookIndex,
      chapter: v.chapter,
      verse: v.verse,
      highlightWords: const [],
      positions: v.positions,
      isCurrent: _isCurrentVerse(v),
      englishOnly: _englishOnly,
      greek: true,
      useEnglishBookNames: widget.useEnglishBookNames,
      onTap: widget.onNavigateToPassage == null
          ? null
          : () => widget.onNavigateToPassage!(bookIndex, v.chapter, v.verse),
    );
  }

  /// The occurrence list, opened at the reader's own verse: the verses before
  /// it grow backwards from a zero-height centre, as in the Hebrew pane.
  Widget _occurrenceVerseList(
    List<_GreekVerse> verses, {
    required double bottomPad,
  }) {
    final anchor = verses.indexWhere(_isCurrentVerse);
    final centre = anchor < 0 ? 0 : anchor;
    final identity = '$centre-${verses.length}';
    return CustomScrollView(
      key: ValueKey('occurrences-$identity'),
      center: ValueKey('occurrence-centre-$identity'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: centre,
            itemBuilder: (context, i) =>
                _occurrenceVerseRow(verses[centre - 1 - i]),
          ),
        ),
        SliverToBoxAdapter(
          key: ValueKey('occurrence-centre-$identity'),
          child: const SizedBox.shrink(),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: verses.length - centre,
            itemBuilder: (context, i) =>
                _occurrenceVerseRow(verses[centre + i]),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8 + bottomPad)),
      ],
    );
  }

  Widget _chip(BuildContext context, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
    );
  }
}
