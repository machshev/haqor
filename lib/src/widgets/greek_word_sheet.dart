import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'name_details.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart'
    show CanonDistribution, OccurrenceVerseRow, VerseModeIcon;

/// A word of the Greek New Testament (the TR), laid out as the Hebrew and
/// Aramaic word pane is: its gloss and the word over its dictionary form, its
/// grammar as chips, and two tabs, one for what the lexicon says of it, the
/// other for every word sharing its dictionary form, each in its verse.
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

  /// Test seams: how the word and the occurrences' verses are asked for.
  final void Function(GetGreekWord request)? sendRequest;
  final void Function(GetVerseTexts request)? sendVerseTextsRequest;

  @override
  State<GreekWordSheet> createState() => _GreekWordSheetState();
}

/// One verse of the occurrence list, with every position in it that shares
/// the word's dictionary form.
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
    final request = GetGreekWord(
      requestId: _requestId,
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
      position: widget.position,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
    unawaited(
      occurrenceVerseEnglishOnlyEnabled().then((enabled) {
        if (mounted) setState(() => _englishOnly = enabled);
      }),
    );
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
  List<_GreekVerse> _verses(List<GreekOccurrenceEntry> occurrences) {
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        info.word.isNotEmpty ? info.word : widget.word,
                        style: _wordStyle(theme),
                      ),
                      if (info.lemma.isNotEmpty)
                        Text(
                          info.lemma,
                          style: TextStyle(
                            fontFamily: 'Cardo',
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
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

  Widget _buildLexiconTab(
    BuildContext context,
    GreekWordInfo info,
    double bottomPad,
  ) {
    final theme = Theme.of(context);
    Widget sectionHeading(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [
        // Who or what the word names here: the lexicon can only say what
        // the name means.
        if (info.name case final name?) ...[
          NameCard(name: name, onOpen: () => _openName(name)),
          const SizedBox(height: 16),
        ],
        if (info.lemma.isNotEmpty) ...[
          sectionHeading('Dictionary form'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: info.lemma,
                    style: TextStyle(
                      fontFamily: 'Cardo',
                      fontSize: 20,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (info.gloss.isNotEmpty)
                    TextSpan(
                      text: '  ${info.gloss}',
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (info.grammar.isNotEmpty) ...[
          sectionHeading('Grammar'),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: info.grammarDescription,
                  style: theme.textTheme.bodyMedium,
                ),
                TextSpan(
                  text: '  ${info.grammar}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// A header with the count, the verse-text switch and the canon
  /// distribution over the verses, as the Hebrew pane's Occurrences tab has.
  Widget _buildOccurrencesTab(
    BuildContext context,
    GreekWordInfo info,
    double bottomPad,
  ) {
    final theme = Theme.of(context);
    final all = _verses(info.occurrences);
    if (all.isEmpty) return const SizedBox.shrink();
    final bookCounts = <int, int>{};
    for (final o in info.occurrences) {
      bookCounts[o.book] = (bookCounts[o.book] ?? 0) + 1;
    }
    final verses = _books.isEmpty
        ? all
        : all.where((v) => _books.contains(v.book)).toList();
    final hits = verses.fold(0, (sum, v) => sum + v.positions.length);
    final versePart = '${verses.length} verse${verses.length == 1 ? '' : 's'}';
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
