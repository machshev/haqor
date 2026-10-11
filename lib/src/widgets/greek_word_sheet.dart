import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../issue_reporting.dart';
import '../study_workspace.dart';
import '../word_proximity.dart';
import 'equivalents.dart';
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
    this.book,
    this.chapter,
    this.verse,
    this.position,
    this.lemma = '',
    this.matchSpelling = false,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.onNavigateToPassage,
    this.nameBookmarks,
    this.onNtGreekChanged,
    this.isStudyBookmarked,
    this.onToggleStudyBookmark,
    this.onOpenLemma,
    this.reportContext,
    this.proximity,
    this.proximityId,
    this.sendRequest,
    this.sendVerseTextsRequest,
    this.sendDictionaryRequest,
  });

  /// The word as the reader shows it, shown until its details arrive.
  final String word;

  /// Where the word stands: its book (40 Matthew … 66 Revelation), chapter,
  /// verse and its position in the verse, from 0. Null for a word with no
  /// place given, a bookmarked one, found by [lemma] instead.
  final int? book;
  final int? chapter;
  final int? verse;
  final int? position;

  /// A placeless word's dictionary form, and whether the first word of the
  /// text spelled as [word] is wanted (a bookmarked form) rather than the
  /// first of all.
  final String lemma;
  final bool matchSpelling;

  /// Whether the word was given its place in the text.
  bool get _placed =>
      book != null && chapter != null && verse != null && position != null;
  final bool useEnglishBookNames;

  /// The Peshitta's script, for the pages of a person or place it opens.
  final bool ntSyriac;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final NameBookmarks? nameBookmarks;

  /// Where a person's or place's page reports its switch between the Greek
  /// and the Peshitta: the page opens on the Greek, as this pane is.
  final ValueChanged<bool>? onNtGreekChanged;

  /// Whether the word, as a root (its dictionary form) or as this form, is
  /// bookmarked in the active study, and how to bookmark or unbookmark it
  /// (true when it ends up bookmarked). Without them it has no bookmark.
  final bool Function(StudyWord word)? isStudyBookmarked;
  final Future<bool> Function(StudyWord word)? onToggleStudyBookmark;

  /// Opens another dictionary form of the root in this pane's place.
  final ValueChanged<String>? onOpenLemma;

  /// Where the reader was, for an issue logged about the word.
  final Map<String, Object?>? reportContext;

  /// The open word panes a proximity search combines: this word joins it,
  /// under [proximityId], with the other Greek words open.
  final WordProximity? proximity;
  final String? proximityId;

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
  late final TabController _tabController;
  StreamSubscription<RustSignalPack<GreekWordInfo>>? _sub;
  GreekWordInfo? _info;
  bool _englishOnly = false;

  /// The root the word is read under, empty for its first.
  String _root = '';

  /// Which words the occurrence list holds: those parsed as this one is, its
  /// dictionary form's, or every word built on its root.
  _GreekScope _scope = _GreekScope.word;

  /// The values each dimension of the occurrence filter keeps; a dimension
  /// with none selected keeps every word.
  final Map<_GreekDimension, Set<String>> _filters = {};

  /// The dictionary forms whose entries are shown or hidden against their
  /// default: the word's own shown, the rest hidden.
  final Set<String> _toggledLexemes = {};

  /// The books the occurrence list is narrowed to, by 1-based number; empty
  /// for all of them.
  final Set<int> _books = {};
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );

  /// The kinds the word is bookmarked as in the active study.
  final Set<StudyWordKind> _studyBookmarks = {};
  bool _bookmarkPending = false;

  /// Admin mode offers to log an issue about the word.
  bool _adminMode = false;
  ProximitySource? _proximitySource;

  @override
  void initState() {
    super.initState();
    // Made at once: a pane replaced before its word arrives disposes it.
    _tabController = TabController(length: 2, vsync: this);
    _sub = GreekWordInfo.rustSignalStream.listen((pack) {
      if (pack.message.requestId != _requestId || !mounted) return;
      setState(() {
        _info = pack.message;
        _readStudyBookmarks();
      });
      _occurrencesChanged();
    });
    _request();
    unawaited(
      occurrenceVerseEnglishOnlyEnabled().then((enabled) {
        if (mounted) setState(() => _englishOnly = enabled);
      }),
    );
    unawaited(
      adminModeEnabled().then((enabled) {
        if (mounted) setState(() => _adminMode = enabled);
      }),
    );
    final proximity = widget.proximity;
    final id = widget.proximityId;
    if (proximity != null && id != null) {
      final source = ProximitySource(
        id: id,
        label: () =>
            _info?.word.isNotEmpty ?? false ? _info!.word : widget.word,
        hits: _proximityHits,
        greek: true,
      );
      _proximitySource = source;
      proximity
        ..register(source)
        ..addListener(_onProximityChanged);
    }
  }

  @override
  void didUpdateWidget(covariant GreekWordSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _readStudyBookmarks();
  }

  void _onProximityChanged() {
    if (mounted) setState(() {});
  }

  /// The word's own list has changed, and with it any proximity search it
  /// takes part in.
  void _occurrencesChanged() => widget.proximity?.changed();

  /// The word as a study bookmark: its root is its dictionary form, as the
  /// reader marks the Greek.
  StudyWord? _studyWord(StudyWordKind kind) {
    final info = _info;
    if (info == null || !info.found) return null;
    return StudyWord(
      root: info.lemma,
      surface: info.word.isNotEmpty ? info.word : widget.word,
      kind: kind,
      language: StudyWordLanguage.greek,
    );
  }

  void _readStudyBookmarks() {
    _studyBookmarks.clear();
    for (final kind in StudyWordKind.values) {
      final word = _studyWord(kind);
      if (word != null && (widget.isStudyBookmarked?.call(word) ?? false)) {
        _studyBookmarks.add(kind);
      }
    }
  }

  Future<void> _toggleStudyBookmark(StudyWordKind kind) async {
    final callback = widget.onToggleStudyBookmark;
    final word = _studyWord(kind);
    if (callback == null || word == null || _bookmarkPending) return;
    setState(() => _bookmarkPending = true);
    try {
      final bookmarked = await callback(word);
      if (mounted) {
        setState(() {
          if (bookmarked) {
            _studyBookmarks.add(kind);
          } else {
            _studyBookmarks.remove(kind);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _bookmarkPending = false);
    }
  }

  Widget _studyBookmarkMenu(GreekWordInfo info) =>
      PopupMenuButton<StudyWordKind>(
        tooltip: 'Study bookmarks',
        enabled: !_bookmarkPending,
        icon: Icon(
          _studyBookmarks.isEmpty
              ? Icons.bookmark_add_outlined
              : Icons.bookmark,
        ),
        iconSize: 20,
        padding: EdgeInsets.zero,
        onSelected: _toggleStudyBookmark,
        itemBuilder: (_) => [
          for (final kind in StudyWordKind.values)
            if (kind == StudyWordKind.form || info.lemma.isNotEmpty)
              CheckedPopupMenuItem(
                value: kind,
                checked: _studyBookmarks.contains(kind),
                child: Text(
                  _studyBookmarks.contains(kind)
                      ? 'Remove ${kind.name} bookmark'
                      : 'Bookmark this ${kind.name}',
                ),
              ),
        ],
      );

  Map<String, Object?> _issueContext(GreekWordInfo info) => {
    if (widget.reportContext != null) 'reader': widget.reportContext,
    'lookup': {
      'word': widget.word,
      'greek': true,
      if (widget._placed) ...{
        'book': widget.book,
        'chapter': widget.chapter,
        'verse': widget.verse,
        'position': widget.position,
      } else
        'lemma': widget.lemma,
    },
    'result': {
      'found': info.found,
      'word': info.word,
      'lemma': info.lemma,
      'gloss': info.gloss,
      'english': info.english,
      'grammar': info.grammar,
      'grammarDescription': info.grammarDescription,
      'root': info.root,
      'roots': info.roots,
      'lexemes': [
        for (final lexeme in info.lexemes)
          {
            'lemma': lexeme.lemma,
            'gloss': lexeme.gloss,
            if (lexeme.isCurrent) 'isCurrent': true,
            'sources': [for (final entry in lexeme.entries) entry.source],
          },
      ],
    },
  };

  void _request() {
    final placed = widget._placed;
    final request = GetGreekWord(
      requestId: _requestId,
      book: placed ? widget.book! : 0,
      chapter: placed ? widget.chapter! : 0,
      verse: placed ? widget.verse! : 0,
      position: placed ? widget.position! : 0,
      root: _root,
      lemma: placed ? '' : widget.lemma,
      word: !placed && widget.matchSpelling ? widget.word : '',
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
    final source = _proximitySource;
    if (source != null) {
      widget.proximity
        ?..removeListener(_onProximityChanged)
        ..unregister(source);
    }
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
    ntGreek: true,
    onNtGreekChanged: widget.onNtGreekChanged,
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
                  if (widget.onToggleStudyBookmark != null) ...[
                    _studyBookmarkMenu(info),
                    const SizedBox(width: 8),
                  ],
                  if (_adminMode) ...[
                    IssueReportButton(
                      source: 'greek_word',
                      contextData: _issueContext(info),
                      tooltip: 'Log an issue or idea about this word',
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                  ],
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
        // The Peshitta words its dictionary form is rendered by.
        if (info.syriacEquivalents.isNotEmpty)
          EquivalentsSection(
            title: 'Peshitta equivalents',
            equivalents: [
              for (final e in info.syriacEquivalents)
                (
                  text: widget.ntSyriac ? e.lexemeSyriac : e.lexeme,
                  gloss: e.meaning,
                  links: e.links,
                  onOpen: () => openSyriacWordSheet(
                    context,
                    word: e.word,
                    useEnglishBookNames: widget.useEnglishBookNames,
                    ntSyriac: widget.ntSyriac,
                    onNavigateToPassage: widget.onNavigateToPassage,
                  ),
                ),
            ],
          ),
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
    final open = widget.onOpenLemma;
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
            // Another word of the root opens in the pane, as a Hebrew
            // headword does; the row around it unfolds its entries.
            if (open != null && !lexeme.isCurrent)
              Tooltip(
                message: 'Open ${lexeme.lemma}',
                child: InkWell(
                  key: ValueKey('open-lemma-${lexeme.lemma}'),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => open(lexeme.lemma),
                  child: Text(
                    lexeme.lemma,
                    style: TextStyle(
                      fontFamily: 'Cardo',
                      fontSize: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              )
            else
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
                      onNtGreekChanged: widget.onNtGreekChanged,
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
    final (
      :parses,
      :own,
      :sameParse,
      :rootWide,
      :scopes,
      :scope,
      :inScope,
      :scoped,
    ) = _occurrenceScope(
      info,
    );
    if (inScope.isEmpty && !rootWide) return const SizedBox.shrink();
    final proximity = _proximityResult();
    final List<_GreekVerse> verses;
    final Map<int, int> bookCounts;
    if (proximity == null) {
      bookCounts = <int, int>{};
      for (final o in scoped) {
        bookCounts[o.book] = (bookCounts[o.book] ?? 0) + 1;
      }
      final all = _verses(scoped);
      verses = _books.isEmpty
          ? all
          : all.where((v) => _books.contains(v.book)).toList();
    } else {
      // The distribution counts the combined results, and the book filter
      // narrows them, as it narrows the word's own list.
      bookCounts = <int, int>{};
      for (final v in proximity.verses) {
        bookCounts[v.book] = (bookCounts[v.book] ?? 0) + 1;
      }
      verses = [
        for (final v in proximity.verses)
          if (_books.isEmpty || _books.contains(v.book)) v,
      ];
    }
    final hits = verses.fold(0, (sum, v) => sum + v.positions.length);
    final versePart = '${verses.length} verse${verses.length == 1 ? '' : 's'}';
    final passages = proximity == null
        ? 0
        : {for (final v in verses) proximity.passageOf[v]}.length;
    final countLabel = proximity == null
        ? (hits == verses.length ? versePart : '$versePart · $hits×')
        : widget.proximity!.distance == ProximityDistance.sameVerse
        ? versePart
        : '$passages passage${passages == 1 ? '' : 's'} · $versePart';
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
              if (scopes.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: SegmentedButton<_GreekScope>(
                    segments: [
                      for (final s in scopes)
                        ButtonSegment(
                          value: s,
                          label: switch (s) {
                            _GreekScope.parse => segment(
                              'This parse',
                              sameParse.length,
                            ),
                            _GreekScope.word => segment(
                              info.lemma,
                              own.length,
                              greek: true,
                            ),
                            _GreekScope.root => segment(
                              'All of ${info.root}',
                              info.occurrences.length,
                              greek: true,
                            ),
                          },
                        ),
                    ],
                    selected: {scope},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                    onSelectionChanged: (selection) => setState(() {
                      _scope = selection.first;
                      _books.clear();
                      _occurrencesChanged();
                    }),
                  ),
                ),
              Row(
                children: [
                  Flexible(
                    child: ActionChip(
                      avatar: const Icon(Icons.filter_list, size: 18),
                      label: Text(
                        _filterSummary(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'Cardo'),
                      ),
                      onPressed: () => _openFilterSheet(
                        context,
                        occurrences: inScope,
                        parses: parses,
                        withLemma: scope == _GreekScope.root,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      countLabel,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_proximityAvailable) _proximityToggle(),
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
              if (proximity != null) _proximityControls(context),
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
          child: proximity != null && verses.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      proximity.loading
                          ? 'Gathering the other words\u2019 occurrences…'
                          : proximity.noPartners
                          ? 'Include another Greek word to search with.'
                          : 'No passages hold all these words.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : verses.isEmpty
              ? Center(
                  child: Text(
                    'No occurrences match this filter',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _occurrenceVerseList(
                  verses,
                  bottomPad: bottomPad,
                  passageOf: proximity?.passageOf,
                ),
        ),
      ],
    );
  }

  /// Whether a word passes every dimension of the filter.
  bool _passes(GreekOccurrenceEntry o, Map<String, GreekParseEntry> parses) =>
      _filters.entries.every(
        (f) => f.value.isEmpty || f.value.contains(f.key.of(o, parses)),
      );

  /// The filter in brief, for its button: what it keeps, or "Filter".
  String _filterSummary() {
    final kept = [
      for (final dimension in _GreekDimension.values)
        ...?_filters[dimension]?.toList()?..sort(),
    ];
    if (kept.isEmpty) return 'Filter';
    return kept.length <= 3
        ? kept.join(' · ')
        : '${kept.take(2).join(' · ')} +${kept.length - 2}';
  }

  /// The filter: every dimension the words in scope have, each value with
  /// how many words selecting it would leave.
  void _openFilterSheet(
    BuildContext context, {
    required List<GreekOccurrenceEntry> occurrences,
    required Map<String, GreekParseEntry> parses,
    required bool withLemma,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => _GreekFilterSheet(
        occurrences: occurrences,
        parses: parses,
        dimensions: [
          for (final d in _GreekDimension.values)
            if (withLemma || d != _GreekDimension.lemma) d,
        ],
        filters: _filters,
        onChanged: (filters) => setState(() {
          _filters
            ..clear()
            ..addAll(filters);
          _books.clear();
          _occurrencesChanged();
        }),
      ),
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
    Map<_GreekVerse, int>? passageOf,
  }) {
    final anchor = verses.indexWhere(_isCurrentVerse);
    final centre = anchor < 0 ? 0 : anchor;
    final identity = '$centre-${verses.length}-${passageOf != null}';
    // A proximity search's passages are set apart, as in the Hebrew pane.
    Widget row(int i) {
      final verse = verses[i];
      final passage = passageOf?[verse];
      final startsPassage =
          passage != null && i > 0 && passageOf?[verses[i - 1]] != passage;
      if (!startsPassage) return _occurrenceVerseRow(verse);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const Divider(height: 16), _occurrenceVerseRow(verse)],
      );
    }

    return CustomScrollView(
      key: ValueKey('occurrences-$identity'),
      center: ValueKey('occurrence-centre-$identity'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: centre,
            itemBuilder: (context, i) => row(centre - 1 - i),
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
            itemBuilder: (context, i) => row(centre + i),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8 + bottomPad)),
      ],
    );
  }

  /// Which of the root's words the occurrence list holds, under the scope
  /// and the filter: shared by the list and the proximity search.
  ({
    Map<String, GreekParseEntry> parses,
    List<GreekOccurrenceEntry> own,
    List<GreekOccurrenceEntry> sameParse,
    bool rootWide,
    List<_GreekScope> scopes,
    _GreekScope scope,
    List<GreekOccurrenceEntry> inScope,
    List<GreekOccurrenceEntry> scoped,
  })
  _occurrenceScope(GreekWordInfo info) {
    final parses = <String, GreekParseEntry>{
      for (final p in info.parses) p.code: p,
    };
    final own = info.occurrences.where((o) => o.lemma == info.lemma).toList();
    final sameParse = own
        .where((o) => o.grammar.isNotEmpty && o.grammar == info.grammar)
        .toList();
    // The root's other words: the choice of scope only where it has some.
    final rootWide = info.occurrences.length > own.length;
    final scopes = [
      if (sameParse.isNotEmpty && sameParse.length < own.length)
        _GreekScope.parse,
      _GreekScope.word,
      if (rootWide) _GreekScope.root,
    ];
    final scope = scopes.contains(_scope) ? _scope : _GreekScope.word;
    final inScope = switch (scope) {
      _GreekScope.parse => sameParse,
      _GreekScope.word => own,
      _GreekScope.root => info.occurrences,
    };
    return (
      parses: parses,
      own: own,
      sameParse: sameParse,
      rootWide: rootWide,
      scopes: scopes,
      scope: scope,
      inScope: inScope,
      scoped: inScope.where((o) => _passes(o, parses)).toList(),
    );
  }

  /// The verses this word brings to a proximity search: its own list under
  /// its scope and filter, before any book filter. Null until it has loaded.
  List<ProximityHit>? _proximityHits() {
    final info = _info;
    if (info == null) return null;
    if (!info.found) return const [];
    return [
      for (final v in _verses(_occurrenceScope(info).scoped))
        ProximityHit(
          book: v.book,
          chapter: v.chapter,
          verse: v.verse,
          positions: v.positions,
        ),
    ];
  }

  /// The other Greek panes open, which a proximity search can take in.
  List<ProximitySource> get _partners => [
    for (final source
        in widget.proximity?.sourcesOf(greek: true) ??
            const <ProximitySource>[])
      if (source.id != widget.proximityId) source,
  ];

  /// A proximity search can only be offered with another Greek pane open.
  bool get _proximityAvailable =>
      widget.proximityId != null && _partners.isNotEmpty;

  /// The combined results when the proximity search is on: this word's list
  /// against every other Greek pane included. Null when it is off.
  _GreekProximity? _proximityResult() {
    final proximity = widget.proximity;
    if (proximity == null || !proximity.enabled || !_proximityAvailable) {
      return null;
    }
    final others = [
      for (final source in _partners)
        if (proximity.isIncluded(source.id)) source,
    ];
    if (others.isEmpty) return const _GreekProximity.noPartners();
    final own = _proximityHits();
    if (own == null) return const _GreekProximity.loading();
    final terms = [own];
    for (final source in others) {
      final hits = source.hits();
      if (hits == null) return const _GreekProximity.loading();
      terms.add(hits);
    }
    final passageOf = <_GreekVerse, int>{};
    final verses = <_GreekVerse>[];
    for (final match in proximityMatches(terms, proximity.distance)) {
      final verse = (
        book: match.book,
        chapter: match.chapter,
        verse: match.verse,
        positions: match.positions,
      );
      verses.add(verse);
      passageOf[verse] = match.passage;
    }
    return _GreekProximity(verses, passageOf);
  }

  Widget _proximityToggle() {
    final enabled = widget.proximity!.enabled;
    return IconButton(
      tooltip: enabled
          ? 'Show only this word'
          : 'Find passages with the other open words',
      isSelected: enabled,
      icon: const Icon(Icons.join_inner, size: 20),
      onPressed: () => widget.proximity!.enabled = !enabled,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minHeight: 40),
    );
  }

  /// Which open Greek words take part, and how close they must stand. This
  /// word is always part of its own search, so its chip is shown on but
  /// fixed.
  Widget _proximityControls(BuildContext context) {
    final theme = Theme.of(context);
    final proximity = widget.proximity!;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final source in proximity.sourcesOf(greek: true))
            FilterChip(
              key: ValueKey('proximity-word-${source.id}'),
              label: Text(
                source.label(),
                style: const TextStyle(fontFamily: 'Cardo'),
              ),
              selected:
                  source.id == widget.proximityId ||
                  proximity.isIncluded(source.id),
              visualDensity: VisualDensity.compact,
              tooltip: source.id == widget.proximityId
                  ? 'This word'
                  : proximity.isIncluded(source.id)
                  ? 'Leave this word out'
                  : 'Include this word',
              onSelected: source.id == widget.proximityId
                  ? null
                  : (included) => proximity.setIncluded(source.id, included),
            ),
          DropdownButton<ProximityDistance>(
            key: const ValueKey('proximity-distance'),
            value: proximity.distance,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: theme.textTheme.labelLarge,
            items: [
              for (final distance in ProximityDistance.options)
                DropdownMenuItem(value: distance, child: Text(distance.label)),
            ],
            onChanged: (distance) {
              if (distance != null) proximity.distance = distance;
            },
          ),
        ],
      ),
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

/// Which words of a Greek word's root the occurrence list holds.
enum _GreekScope { parse, word, root }

/// One dimension of the Greek occurrence filter: a word's dictionary form,
/// or a part of its grammar code.
enum _GreekDimension {
  lemma('Word'),
  partOfSpeech('Part of speech'),
  tense('Tense'),
  voice('Voice'),
  mood('Mood'),
  case_('Case'),
  person('Person'),
  number('Number'),
  gender('Gender');

  const _GreekDimension(this.label);

  /// Section heading in the filter sheet.
  final String label;

  /// This dimension's value for a word, empty where its code has none.
  String of(GreekOccurrenceEntry o, Map<String, GreekParseEntry> parses) {
    if (this == _GreekDimension.lemma) return o.lemma;
    final p = parses[o.grammar];
    if (p == null) return '';
    return switch (this) {
      _GreekDimension.lemma => o.lemma,
      _GreekDimension.partOfSpeech => p.partOfSpeech,
      _GreekDimension.tense => p.tense,
      _GreekDimension.voice => p.voice,
      _GreekDimension.mood => p.mood,
      _GreekDimension.case_ => p.grammaticalCase,
      _GreekDimension.person => p.person,
      _GreekDimension.number => p.number,
      _GreekDimension.gender => p.gender,
    };
  }
}

/// The Greek occurrence filter. Each value's count is of the words the
/// other dimensions' selections admit, so it says what selecting it would
/// leave; a dimension with fewer than two values among them is not offered
/// unless something in it is selected.
class _GreekFilterSheet extends StatefulWidget {
  const _GreekFilterSheet({
    required this.occurrences,
    required this.parses,
    required this.dimensions,
    required this.filters,
    required this.onChanged,
  });

  final List<GreekOccurrenceEntry> occurrences;
  final Map<String, GreekParseEntry> parses;
  final List<_GreekDimension> dimensions;
  final Map<_GreekDimension, Set<String>> filters;
  final ValueChanged<Map<_GreekDimension, Set<String>>> onChanged;

  @override
  State<_GreekFilterSheet> createState() => _GreekFilterSheetState();
}

class _GreekFilterSheetState extends State<_GreekFilterSheet> {
  late final Map<_GreekDimension, Set<String>> _filters = {
    for (final entry in widget.filters.entries) entry.key: {...entry.value},
  };

  void _changed() {
    _filters.removeWhere((_, values) => values.isEmpty);
    widget.onChanged(_filters);
  }

  /// Each value of `dimension` with how many words have it among those the
  /// other dimensions admit, the most common first.
  List<MapEntry<String, int>> _counts(_GreekDimension dimension) {
    final counts = <String, int>{};
    for (final o in widget.occurrences) {
      final admitted = _filters.entries.every(
        (f) =>
            f.key == dimension ||
            f.value.isEmpty ||
            f.value.contains(f.key.of(o, widget.parses)),
      );
      if (!admitted) continue;
      final value = dimension.of(o, widget.parses);
      if (value.isEmpty) continue;
      counts[value] = (counts[value] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value - a.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = <Widget>[];
    for (final dimension in widget.dimensions) {
      final counts = _counts(dimension);
      final selected = _filters[dimension] ?? const <String>{};
      if (counts.length < 2 && selected.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            dimension.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
      sections.add(
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final MapEntry(key: value, value: count) in counts)
              FilterChip(
                label: Text(
                  '$value · $count',
                  style: dimension == _GreekDimension.lemma
                      ? const TextStyle(fontFamily: 'Cardo')
                      : null,
                ),
                selected: selected.contains(value),
                visualDensity: VisualDensity.compact,
                onSelected: (on) => setState(() {
                  final values = _filters.putIfAbsent(dimension, () => {});
                  on ? values.add(value) : values.remove(value);
                  _changed();
                }),
              ),
          ],
        ),
      );
    }
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter occurrences',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _filters.isEmpty
                      ? null
                      : () => setState(() {
                          _filters.clear();
                          _changed();
                        }),
                  child: const Text('Clear'),
                ),
              ],
            ),
            if (sections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'These words are all parsed alike.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ...sections,
          ],
        ),
      ),
    );
  }
}

/// A proximity search's results in the Greek pane: the verses, each with the
/// passage it belongs to, or why there are none yet.
class _GreekProximity {
  const _GreekProximity(this.verses, this.passageOf)
    : loading = false,
      noPartners = false;
  const _GreekProximity.loading()
    : verses = const [],
      passageOf = const {},
      loading = true,
      noPartners = false;
  const _GreekProximity.noPartners()
    : verses = const [],
      passageOf = const {},
      loading = false,
      noPartners = true;

  final List<_GreekVerse> verses;
  final Map<_GreekVerse, int> passageOf;
  final bool loading;
  final bool noPartners;
}
