import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bindings/bindings.dart';
import '../bible_data.dart';
import '../issue_reporting.dart';
import '../tutor/progress_sync.dart';
import 'verse_row.dart' show verseGlossPositions;
import 'verse_text_cache.dart';

const Map<String, int> _kBdbBookToIndex = {
  'Genesis': 0,
  'Exodus': 1,
  'Leviticus': 2,
  'Numbers': 3,
  'Deuteronomy': 4,
  'Joshua': 5,
  'Judges': 6,
  'I Samuel': 7,
  'II Samuel': 8,
  'I Kings': 9,
  'II Kings': 10,
  'Isaiah': 11,
  'Jeremiah': 12,
  'Ezekiel': 13,
  'Hosea': 14,
  'Joel': 15,
  'Amos': 16,
  'Obadiah': 17,
  'Jonah': 18,
  'Micah': 19,
  'Nahum': 20,
  'Habakkuk': 21,
  'Zephaniah': 22,
  'Haggai': 23,
  'Zechariah': 24,
  'Malachi': 25,
  'Psalms': 26,
  'Proverbs': 27,
  'Job': 28,
  'Song of Songs': 29,
  'Ruth': 30,
  'Lamentations': 31,
  'Ecclesiastes': 32,
  'Esther': 33,
  'Daniel': 34,
  'Ezra': 35,
  'Nehemiah': 36,
  'I Chronicles': 37,
  'II Chronicles': 38,
};

({int bookIndex, int chapter, int verse})? _parseBibleRef(String href) {
  final match = RegExp(r'^(.+) (\d+):(\d+)$').firstMatch(href);
  if (match == null) return null;
  final bookName = match.group(1)!;
  final chapter = int.tryParse(match.group(2)!) ?? 0;
  final verse = int.tryParse(match.group(3)!) ?? 0;
  final bookIndex = _kBdbBookToIndex[bookName];
  if (bookIndex == null || chapter == 0 || verse == 0) return null;
  return (bookIndex: bookIndex, chapter: chapter, verse: verse);
}

class WordInfoSheet extends StatefulWidget {
  const WordInfoSheet({
    super.key,
    required this.word,
    required this.syriac,
    this.bdbId,
    this.readerGloss,
    this.book,
    this.chapter,
    this.verse,
    this.position,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.reportContext,
    this.sendInfoRequest,
    this.sendOccurrencesRequest,
    this.sendVerseTextsRequest,
  });

  final String word;
  final bool syriac;

  /// How the sheet's three requests reach Rust. Injectable so a widget test can
  /// drive the sheet without the native library loaded, as the reader does.
  final void Function(GetWordInfo)? sendInfoRequest;
  final void Function(GetWordOccurrences)? sendOccurrencesRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  /// When set, the sheet shows the BDB entry with this id (a Lexicon
  /// cross-reference target) rather than parsing [word] as a surface form;
  /// [word] is then just the target headword for the title.
  final String? bdbId;

  /// The exact gloss currently rendered underneath this token in the reader.
  /// It can intentionally differ from the descriptive Lexicon header.
  final String? readerGloss;

  /// Concrete reader location for occurrence-level OT morphology.
  final int? book;
  final int? chapter;
  final int? verse;
  final int? position;

  /// Whether references in the Occurrences tab use standard English names.
  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final Map<String, Object?>? reportContext;

  @override
  State<WordInfoSheet> createState() => _WordInfoSheetState();
}

class _WordInfoSheetState extends State<WordInfoSheet>
    with SingleTickerProviderStateMixin {
  StreamSubscription<RustSignalPack<WordInfo>>? _sub;
  WordInfo? _info;
  final Set<int> _expandedBdb = {};
  late final TabController _tabController;
  bool _adminMode = false;
  // OT-only: which surface forms of the root are shown in the occurrences list.
  // Null until first built, then defaults to the looked-up word's form. Empty
  // set means "show all forms".
  Set<String>? _otForms;
  // OT-only: which parse labels are shown. Empty means "every parse".
  final Set<String> _otParses = {};
  // OT-only: restrict the list to one book (1-based, matching the occurrence
  // rows). Null shows the whole canon.
  int? _otBook;
  // Every occurrence row reads its verse text through this one cache, which
  // batches the requests of a layout pass into a single round-trip.
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  // NT-only: which lexeme indices (positions in info.sedraEntries) are shown in
  // the occurrences list. Null until first built, then defaults to the looked-up
  // lexeme. Empty set means "show all".
  Set<int>? _selectedLexemes;
  // NT-only: when true the occurrences list shows OT (Hebrew Bible) verses of
  // the same consonantal root instead of the SEDRA-based NT occurrences.
  bool _otSelected = false;
  // Shared across both occurrences tabs: false shows Hebrew verse text, true
  // shows the aligned English reader glosses instead.
  bool _occurrenceVerseEnglishOnly = false;
  // Occurrence lists are fetched lazily (full-text root scans) the first time
  // the Occurrences tab is opened, so the sheet pops up on the lexicon data
  // alone. Null until that fetch completes.
  StreamSubscription<RustSignalPack<WordOccurrences>>? _occSub;
  WordOccurrences? _occ;
  bool _occRequested = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requestInfo();
    _loadAdminMode();
    _loadOccurrenceVerseMode();
  }

  void _requestInfo() {
    _sub?.cancel();
    _sub = WordInfo.rustSignalStream.listen((pack) {
      if (mounted) {
        setState(() => _info = pack.message);
        _sub?.cancel();
        // Preload the occurrence scans in the background as soon as the lexicon
        // data lands, so the Occurrences tab is already populated (or at least
        // loading) by the time the user switches to it. Fetched even when the
        // lexicon lookup failed: an unparsed word is still a surface form of
        // the text, and its occurrences are the one thing we can always show.
        _fetchOccurrences();
      }
    });
    final request = GetWordInfo(
      word: widget.word,
      syriac: widget.syriac,
      bdbId: widget.bdbId,
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
      position: widget.position,
    );
    final send = widget.sendInfoRequest;
    if (send == null) {
      request.sendSignalToRust();
    } else {
      send(request);
    }
  }

  // Fetch the occurrence lists (full-text root scans). Idempotent via
  // [_occRequested] so the preload can't double-fire.
  void _fetchOccurrences() {
    if (_occRequested) return;
    _occRequested = true;
    _occSub = WordOccurrences.rustSignalStream.listen((pack) {
      if (mounted) {
        setState(() => _occ = pack.message);
        _occSub?.cancel();
      }
    });
    final request = GetWordOccurrences(
      word: widget.word,
      syriac: widget.syriac,
    );
    final send = widget.sendOccurrencesRequest;
    if (send == null) {
      request.sendSignalToRust();
    } else {
      send(request);
    }
  }

  Future<void> _loadAdminMode() async {
    final enabled = await adminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  Future<void> _loadOccurrenceVerseMode() async {
    final enabled = await occurrenceVerseEnglishOnlyEnabled();
    if (mounted) setState(() => _occurrenceVerseEnglishOnly = enabled);
  }

  Future<void> _setOccurrenceVerseMode(bool enabled) async {
    setState(() => _occurrenceVerseEnglishOnly = enabled);
    await setOccurrenceVerseEnglishOnlyEnabled(enabled);
  }

  Future<void> _openLexiconEditor(WordInfo info) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LexiconEntryOverrideEditor(
        surface: info.word,
        root: info.root,
        gloss: info.gloss,
        readerGloss: widget.readerGloss,
      ),
    );
    if (!mounted || message == null) return;
    _requestInfo();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, Object?> _issueContext(WordInfo info) => {
    if (widget.reportContext != null) 'reader': widget.reportContext,
    'lookup': {
      'word': widget.word,
      'syriac': widget.syriac,
      if (widget.bdbId != null) 'bdbId': widget.bdbId,
    },
    'result': {
      'found': info.found,
      'word': info.word,
      'root': info.root,
      'gloss': info.gloss,
      'morphology': {
        if (info.gender != null) 'gender': info.gender,
        if (info.partOfSpeech != null) 'partOfSpeech': info.partOfSpeech,
        if (info.person != null) 'person': info.person,
        if (info.number != null) 'number': info.number,
        if (info.state != null) 'state': info.state,
        if (info.tense != null) 'tense': info.tense,
        if (info.form != null) 'form': info.form,
        if (info.prefix != null) 'prefix': info.prefix,
        if (info.suffix != null) 'suffix': info.suffix,
        if (info.prepositions != null) 'prepositions': info.prepositions,
        'article': info.article,
        'vavCon': info.vavCon,
      },
      'bdbEntries': [
        for (final entry in info.bdbEntries)
          {
            'headword': entry.headword,
            'gloss': entry.gloss,
            'posCategory': entry.posCategory,
          },
      ],
      'sedraEntries': [
        for (final entry in info.sedraEntries)
          {
            'lexeme': entry.lexeme,
            'meaning': entry.meaning,
            'isCurrent': entry.isCurrent,
          },
      ],
    },
  };

  @override
  void dispose() {
    _tabController.dispose();
    _sub?.cancel();
    _occSub?.cancel();
    _verseTexts.dispose();
    super.dispose();
  }

  void _onBibleRefTap(BuildContext context, String href) {
    final parsed = _parseBibleRef(href);
    if (parsed == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _BibleRefPreviewDialog(
        displayRef: href,
        bookIndex: parsed.bookIndex,
        chapter: parsed.chapter,
        verse: parsed.verse,
        onNavigate: widget.onNavigateToPassage == null
            ? null
            : () => widget.onNavigateToPassage!(
                parsed.bookIndex,
                parsed.chapter,
                parsed.verse,
              ),
      ),
    );
  }

  // Follow a Lexicon cross-reference: open the target BDB entry in a stacked
  // sheet. Drilling in keeps the trail (back returns here); navigating to a
  // passage from the target closes both sheets first.
  void _onXrefTap(String bdbId, String headword) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordInfoSheet(
        word: headword,
        syriac: false,
        bdbId: bdbId,
        useEnglishBookNames: widget.useEnglishBookNames,
        reportContext: {
          ...?widget.reportContext,
          'crossReference': {'bdbId': bdbId, 'headword': headword},
        },
        onNavigateToPassage: widget.onNavigateToPassage == null
            ? null
            : (bi, chapter, verse) {
                Navigator.pop(ctx);
                widget.onNavigateToPassage!(bi, chapter, verse);
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SelectionArea(
                  child: info == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContent(context, scrollController, info),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ScrollController scrollController,
    WordInfo info,
  ) {
    final theme = Theme.of(context);

    if (!info.found) {
      // No lexicon data, but the word is still a surface form of the text —
      // show its occurrences so the sheet stays useful (and the reader can
      // study the word in its other contexts).
      final occ = _occ;
      final occurrences = [
        for (final o in occ?.occurrences ?? const <WordOccurrence>[])
          _VerseOccurrence(
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            words: [widget.word],
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              children: [
                Text(
                  widget.word,
                  style: TextStyle(
                    fontFamily: 'Cardo',
                    fontFamilyFallback: const ['Noto Serif Hebrew'],
                    fontSize: 28,
                    color: theme.colorScheme.onSurface,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 8),
                Text(
                  'Not found in lexicon',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: occ == null
                ? const Center(child: CircularProgressIndicator())
                : occurrences.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      8 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    // Header plus one row per verse, built on demand: an
                    // unparsed but common surface still has a long list.
                    itemCount: occurrences.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Occurrences',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _occurrenceVerseRow(occurrences[i - 1]),
                  ),
          ),
        ],
      );
    }

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
                  if (_adminMode) ...[
                    if (!widget.syriac && widget.bdbId == null) ...[
                      IconButton(
                        onPressed: () => _openLexiconEditor(info),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit this lexicon override',
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IssueReportButton(
                      source: 'word_info',
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        info.word,
                        style: TextStyle(
                          fontFamily: 'Noto Serif Hebrew',
                          fontFamilyFallback: const ['Cardo'],
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      if (info.root.isNotEmpty)
                        Text(
                          info.root,
                          style: TextStyle(
                            fontFamily: 'Noto Serif Hebrew',
                            fontFamilyFallback: const ['Cardo'],
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (info.partOfSpeech != null)
                    _chip(context, 'Part of speech', info.partOfSpeech!),
                  if (info.gender != null)
                    _chip(context, 'Gender', info.gender!),
                  if (info.person != null)
                    _chip(context, 'Person', info.person!),
                  if (info.number != null)
                    _chip(context, 'Number', info.number!),
                  if (info.state != null) _chip(context, 'State', info.state!),
                  if (info.tense != null) _chip(context, 'Tense', info.tense!),
                  if (info.form != null) _chip(context, 'Form', info.form!),
                  if (info.prefix != null)
                    _chip(context, 'Prefix', info.prefix!),
                  if (info.suffix != null)
                    _chip(context, 'Suffix', info.suffix!),
                  if (info.prepositions != null)
                    _chip(context, 'Prep', info.prepositions!),
                  if (info.article) _chip(context, 'Article', 'ה'),
                  if (info.vavCon) _chip(context, 'Vav', 'consecutive'),
                ],
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
              _buildLexiconTab(context, scrollController, info, bottomPad),
              _buildOccurrencesTab(context, info, bottomPad),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLexiconTab(
    BuildContext context,
    ScrollController scrollController,
    WordInfo info,
    double bottomPad,
  ) {
    final theme = Theme.of(context);

    // One collapsible BDB lexeme row. The original list index keys its
    // expansion state, so it stays stable when the list is split into the
    // part-of-speech groups below.
    Widget buildBdbRow(int i, BdbSummary e) {
      final expanded = _expandedBdb.contains(i);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() {
              if (expanded) {
                _expandedBdb.remove(i);
              } else {
                _expandedBdb.add(i);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  if (e.gloss.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.gloss, style: theme.textTheme.bodyMedium),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 8),
                  Text(
                    _normalizeHebrewCombining(e.headword),
                    style: TextStyle(
                      fontFamily: 'Noto Serif Hebrew',
                      fontFamilyFallback: const ['Cardo'],
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ),
          if (expanded && e.contentJson.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BdbContent(
                contentJson: e.contentJson,
                onBibleRefTap: (href) => _onBibleRefTap(context, href),
                onXrefTap: _onXrefTap,
              ),
            ),
        ],
      );
    }

    Widget sectionHeading(String label) => Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    // Head a root's lexemes under their grammatical class. Proper names in
    // particular crowd out the root's actual meaning, so they sit last under
    // their own heading. `posCategory` is the BDB part-of-speech bucket set in
    // the hub crate; the order here fixes how the groups stack.
    const groups = <(String, String)>[
      ('root', 'Roots'),
      ('verb', 'Verbs'),
      ('noun', 'Nouns'),
      ('adjective', 'Adjectives'),
      ('adverb', 'Adverbs'),
      ('proper', 'Proper nouns'),
      ('other', 'Other'),
    ];

    final rows = <Widget>[];
    for (final (key, label) in groups) {
      final entries = info.bdbEntries.indexed
          .where((p) => p.$2.posCategory == key)
          .toList();
      if (entries.isEmpty) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(sectionHeading(label));
      rows.add(const SizedBox(height: 4));
      rows.addAll(entries.map((p) => buildBdbRow(p.$1, p.$2)));
    }

    // A resolved word with no dictionary entry (curated function words such
    // as בָּהּ bridge to no BDB lexeme) would otherwise render a blank tab.
    if (rows.isEmpty && info.sedraEntries.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No dictionary entry for this form.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [
        ...rows,
        if (info.sedraEntries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Root tree',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (info.root.isNotEmpty)
                Text(
                  '${info.root}  ·  ${info.sedraEntries.length} lexemes',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textDirection: TextDirection.rtl,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: info.sedraEntries.map((e) {
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: e.isCurrent
                      ? BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(
                            alpha: 0.6,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        e.lexeme,
                        style: TextStyle(
                          fontFamily: 'Cardo',
                          fontFamilyFallback: const ['Noto Serif Hebrew'],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: e.isCurrent
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.meaning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: e.isCurrent
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOccurrencesTab(
    BuildContext context,
    WordInfo info,
    double bottomPad,
  ) {
    // Occurrences are fetched lazily when this tab is first opened; show a
    // spinner until the scan completes.
    final occ = _occ;
    if (occ == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // NT: lexeme-filterable list backed by the detailed SEDRA occurrences.
    if (widget.syriac && occ.sedraOccurrences.isNotEmpty) {
      return _buildSedraOccurrencesTab(context, info, occ, bottomPad);
    }

    if (occ.occurrences.isNotEmpty || occ.hebrewOccurrences.isNotEmpty) {
      return _buildHebrewOccurrencesTab(context, info, occ, bottomPad);
    }

    return const SizedBox.shrink();
  }

  /// OT counterpart of [_buildSedraOccurrencesTab]: a filter header and a canon
  /// distribution over a merged-by-verse list. The NT side filters by lexeme;
  /// the OT side filters by surface form, by parse, and by book.
  Widget _buildHebrewOccurrencesTab(
    BuildContext context,
    WordInfo info,
    WordOccurrences occ,
    double bottomPad,
  ) {
    final theme = Theme.of(context);

    // Older/edge data (e.g. a word with no readable root) has no per-token
    // tagging — fall back to a flat list of the surface's own verses.
    if (occ.hebrewOccurrences.isEmpty) {
      final flat = [
        for (final o in occ.occurrences)
          _VerseOccurrence(
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            words: [widget.word],
          ),
      ];
      return _occurrenceVerseList(flat, bottomPad: bottomPad);
    }

    final all = occ.hebrewOccurrences;

    // Lazily default the form filter to the looked-up word's own form.
    if (_otForms == null) {
      final key = _surfaceKey(widget.word);
      final match = all
          .map((o) => o.surface)
          .firstWhere((s) => _surfaceKey(s) == key, orElse: () => '');
      _otForms = match.isEmpty ? {} : {match};
    }
    final forms = _otForms!;
    final parses = _otParses;

    bool passesForm(HebrewOccurrence o) =>
        forms.isEmpty || forms.contains(o.surface);
    bool passesParse(HebrewOccurrence o) =>
        parses.isEmpty || parses.contains(_parseLabel(o));
    bool passesBook(HebrewOccurrence o) => _otBook == null || o.book == _otBook;

    // Each filter's own inventory is counted over what the *other* filters
    // admit, so a number says what selecting that entry would actually yield.
    // The bar is counted here; the sheet counts forms and parses itself, since
    // those have to move as selections change inside it.
    final inScope = all.where(passesBook).toList();
    final bookCounts = <int, int>{};
    for (final o in all.where((o) => passesForm(o) && passesParse(o))) {
      bookCounts[o.book] = (bookCounts[o.book] ?? 0) + 1;
    }

    // Apply every filter, then merge tokens standing in the same verse so it
    // appears once with all its matches highlighted.
    final byVerse = <String, _VerseOccurrence>{};
    var hits = 0;
    for (final o in all) {
      if (!passesForm(o) || !passesParse(o) || !passesBook(o)) continue;
      hits++;
      final key = '${o.book}:${o.chapter}:${o.verse}';
      final existing = byVerse[key];
      if (existing == null) {
        byVerse[key] = _VerseOccurrence(
          book: o.book,
          chapter: o.chapter,
          verse: o.verse,
          words: [o.surface],
          positions: [o.position],
        );
      } else {
        if (!existing.words.contains(o.surface)) existing.words.add(o.surface);
        existing.positions.add(o.position);
      }
    }
    final verses = byVerse.values.toList()
      ..sort((a, b) {
        if (a.book != b.book) return a.book.compareTo(b.book);
        if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
        return a.verse.compareTo(b.verse);
      });

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
                  Flexible(
                    child: ActionChip(
                      avatar: const Icon(Icons.filter_list, size: 18),
                      label: Text(
                        _hebrewFilterSummary(forms, parses),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Cardo',
                          fontFamilyFallback: ['Noto Serif Hebrew'],
                        ),
                      ),
                      onPressed: () =>
                          _openHebrewFilterSheet(context, occurrences: inScope),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _occurrenceCountLabel(verses.length, hits),
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
                    tooltip: _occurrenceVerseEnglishOnly
                        ? 'Show Hebrew verse text'
                        : 'Show English-only verse text',
                    icon: _VerseModeIcon(
                      englishOnly: _occurrenceVerseEnglishOnly,
                    ),
                    onPressed: () {
                      _setOccurrenceVerseMode(!_occurrenceVerseEnglishOnly);
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerRight,
                    constraints: const BoxConstraints(minHeight: 40),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              _CanonDistribution(
                countsByBook: bookCounts,
                selectedBook: _otBook,
                useEnglishBookNames: widget.useEnglishBookNames,
                onSelect: (book) => setState(() => _otBook = book),
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

  /// The parse a filter chip stands for. Tokens the build could not analyse
  /// still need a bucket, or filtering by parse would silently drop them.
  static String _parseLabel(HebrewOccurrence o) =>
      o.parse.isEmpty ? 'unparsed' : o.parse;

  String _hebrewFilterSummary(Set<String> forms, Set<String> parses) {
    final parts = [
      if (forms.length == 1)
        forms.first
      else if (forms.length > 1)
        '${forms.length} forms',
      if (parses.length == 1)
        parses.first
      else if (parses.length > 1)
        '${parses.length} parses',
    ];
    return parts.isEmpty ? 'All forms' : parts.join(' · ');
  }

  /// Verses *and* tokens: a root can stand twice in one verse, and a reader
  /// asking how common a word is means the second number.
  static String _occurrenceCountLabel(int verses, int hits) {
    final versePart = '$verses verse${verses == 1 ? '' : 's'}';
    return hits == verses ? versePart : '$versePart · $hits×';
  }

  Future<void> _copyReferences(List<_VerseOccurrence> verses) async {
    final refs = verses
        .map((v) {
          final bookIndex = v.book - 1;
          final name = bookIndex >= 0 && bookIndex < kBooks.length
              ? bookDisplayName(
                  bookIndex,
                  useEnglish: widget.useEnglishBookNames,
                )
              : 'Book ${v.book}';
          return '$name ${v.chapter}:${v.verse}';
        })
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

  /// The OT filter sheet: forms on one tab, parses on the other, each searchable
  /// because a common root has hundreds of forms (בוא alone has 320) and a wall
  /// of unsorted checkboxes is not a filter anyone can use.
  Future<void> _openHebrewFilterSheet(
    BuildContext context, {
    required List<HebrewOccurrence> occurrences,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _OccurrenceFilterSheet(
        occurrences: occurrences,
        parseLabel: _parseLabel,
        selectedForms: _otForms ?? {},
        selectedParses: _otParses,
        onChanged: (forms, parses) => setState(() {
          _otForms = forms;
          _otParses
            ..clear()
            ..addAll(parses);
        }),
      ),
    );
  }

  Widget _buildSedraOccurrencesTab(
    BuildContext context,
    WordInfo info,
    WordOccurrences occ,
    double bottomPad,
  ) {
    // Lazily default the filter to the looked-up lexeme.
    if (_selectedLexemes == null) {
      final current = info.sedraEntries.indexWhere((e) => e.isCurrent);
      _selectedLexemes = {current >= 0 ? current : 0};
    }
    final selected = _selectedLexemes!;
    final showAll = selected.isEmpty;

    // Distinct-verse counts per lexeme index, for the chip labels.
    final counts = <int, int>{};
    for (final o in occ.sedraOccurrences) {
      counts[o.lexemeIndex] = (counts[o.lexemeIndex] ?? 0) + 1;
    }

    // Apply the filter, then merge rows that fall on the same verse so a verse
    // appears once with all matched word forms highlighted.
    final filtered = occ.sedraOccurrences.where(
      (o) => showAll || selected.contains(o.lexemeIndex),
    );
    final byVerse = <String, _VerseOccurrence>{};
    for (final o in filtered) {
      final key = '${o.book}:${o.chapter}:${o.verse}';
      final existing = byVerse[key];
      if (existing == null) {
        byVerse[key] = _VerseOccurrence(
          book: o.book,
          chapter: o.chapter,
          verse: o.verse,
          words: [...o.words],
        );
      } else {
        for (final w in o.words) {
          if (!existing.words.contains(w)) existing.words.add(w);
        }
      }
    }
    // When the OT filter is active, fold in the Hebrew-Bible occurrences of the
    // same root alongside the NT (SEDRA) ones, then sort canonically. OT books
    // (1–39) sort ahead of NT books (40–66), so the list reads in natural
    // OT→NT order.
    final verses = <_VerseOccurrence>[
      if (_otSelected)
        for (final o in occ.otOccurrences)
          _VerseOccurrence(
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            words: const [],
          ),
      ...byVerse.values,
    ];
    verses.sort((a, b) {
      if (a.book != b.book) return a.book.compareTo(b.book);
      if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
      return a.verse.compareTo(b.verse);
    });

    final theme = Theme.of(context);

    // Compact summary of the active filter, shown on the filter button so the
    // full chip list can live in a popup instead of eating vertical space.
    final String lexemeSummary;
    if (showAll) {
      lexemeSummary = 'All lexemes';
    } else if (selected.length == 1) {
      final i = selected.first;
      lexemeSummary = (i >= 0 && i < info.sedraEntries.length)
          ? info.sedraEntries[i].lexeme
          : 'All lexemes';
    } else {
      lexemeSummary = '${selected.length} lexemes';
    }
    final filterSummary = _otSelected ? '$lexemeSummary + OT' : lexemeSummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pinned filter header — a single compact row so it stays out of the
        // way on narrow screens. Tapping the button opens the lexeme picker.
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: ActionChip(
                        avatar: const Icon(Icons.filter_list, size: 18),
                        label: Text(
                          filterSummary,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Cardo',
                            fontFamilyFallback: ['Noto Serif Hebrew'],
                          ),
                        ),
                        onPressed: () =>
                            _openLexemeFilterSheet(context, info, occ, counts),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${verses.length} verse${verses.length == 1 ? '' : 's'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _occurrenceVerseEnglishOnly
                    ? 'Show Hebrew verse text'
                    : 'Show English-only verse text',
                icon: _VerseModeIcon(englishOnly: _occurrenceVerseEnglishOnly),
                onPressed: () {
                  _setOccurrenceVerseMode(!_occurrenceVerseEnglishOnly);
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                alignment: Alignment.centerRight,
                constraints: const BoxConstraints(minHeight: 40),
              ),
            ],
          ),
        ),
        Expanded(child: _occurrenceVerseList(verses, bottomPad: bottomPad)),
      ],
    );
  }

  Future<void> _openLexemeFilterSheet(
    BuildContext context,
    WordInfo info,
    WordOccurrences occ,
    Map<int, int> counts,
  ) async {
    final theme = Theme.of(context);
    const lexStyle = TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: ['Noto Serif Hebrew'],
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final selected = _selectedLexemes ?? {};
            final showAll = selected.isEmpty;
            // Toggle filter state on both the sheet and the underlying tab so
            // the verse list stays in sync as selections change.
            void apply(VoidCallback fn) {
              setState(fn);
              setSheetState(() {});
            }

            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                      child: Row(
                        children: [
                          Text(
                            'Filter occurrences',
                            style: theme.textTheme.titleSmall,
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Pack the short lexeme labels into as many columns as
                          // the sheet width comfortably allows (~200px each).
                          final columns = (constraints.maxWidth / 200)
                              .floor()
                              .clamp(1, 3);
                          CheckboxListTile buildLexemeTile(int i) {
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              title: Text(
                                '${info.sedraEntries[i].lexeme} (${counts[i] ?? 0})',
                                style: lexStyle,
                                overflow: TextOverflow.ellipsis,
                              ),
                              value: selected.contains(i),
                              onChanged: (on) => apply(() {
                                final next = {...selected};
                                if (on ?? false) {
                                  next.add(i);
                                } else {
                                  next.remove(i);
                                }
                                _selectedLexemes = next;
                              }),
                            );
                          }

                          return ListView(
                            shrinkWrap: true,
                            children: [
                              CheckboxListTile(
                                dense: true,
                                title: const Text('All lexemes'),
                                value: showAll,
                                onChanged: (_) => apply(() {
                                  _selectedLexemes = {};
                                }),
                              ),
                              if (occ.otOccurrences.isNotEmpty)
                                CheckboxListTile(
                                  dense: true,
                                  title: Text(
                                    'Old Testament (${occ.otOccurrences.length})',
                                  ),
                                  value: _otSelected,
                                  onChanged: (on) => apply(() {
                                    _otSelected = on ?? false;
                                  }),
                                ),
                              for (
                                var i = 0;
                                i < info.sedraEntries.length;
                                i += columns
                              )
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var j = i; j < i + columns; j++)
                                      Expanded(
                                        child: j < info.sedraEntries.length
                                            ? buildLexemeTile(j)
                                            : const SizedBox.shrink(),
                                      ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// One row of an occurrence list. Built on demand by the lazy lists below, so
  /// only the verses on screen ever ask for their text.
  Widget _occurrenceVerseRow(_VerseOccurrence v) {
    final bookIndex = v.book - 1;
    final bookName = bookIndex >= 0 && bookIndex < kBooks.length
        ? bookDisplayName(bookIndex, useEnglish: widget.useEnglishBookNames)
        : 'Book ${v.book}';
    return _OccurrenceRow(
      key: ValueKey('${v.book}:${v.chapter}:${v.verse}'),
      cache: _verseTexts,
      displayRef: '$bookName ${v.chapter}:${v.verse}',
      bookIndex: bookIndex,
      chapter: v.chapter,
      verse: v.verse,
      highlightWords: v.words,
      positions: v.positions,
      isCurrent: _isCurrentVerse(v),
      englishOnly: _occurrenceVerseEnglishOnly,
      useEnglishBookNames: widget.useEnglishBookNames,
      onTap: widget.onNavigateToPassage == null
          ? null
          : () => widget.onNavigateToPassage!(bookIndex, v.chapter, v.verse),
    );
  }

  /// Whether this is the verse the reader was on when the sheet opened.
  bool _isCurrentVerse(_VerseOccurrence v) =>
      widget.book == v.book &&
      widget.chapter == v.chapter &&
      widget.verse == v.verse;

  /// An occurrence list as a lazy, scrollable list opened at the verse the
  /// reader came from.
  ///
  /// Two slivers meeting at a zero-height centre: the verses before the anchor
  /// grow backwards into negative scroll offsets, so the list opens on the
  /// reader's own verse with no scroll-offset correction, however tall the rows
  /// above it turn out to be. Same anchoring the reader itself uses.
  Widget _occurrenceVerseList(
    List<_VerseOccurrence> verses, {
    required double bottomPad,
  }) {
    final anchor = verses.indexWhere(_isCurrentVerse);
    final centre = anchor < 0 ? 0 : anchor;
    // Keyed on the anchor, so changing a filter (and with it the anchor's index)
    // builds a fresh viewport rather than keeping a scroll offset that now
    // points at some other verse.
    final identity = '$centre-${verses.length}';
    return CustomScrollView(
      key: ValueKey('occurrences-$identity'),
      center: ValueKey('occurrence-centre-$identity'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: centre,
            // Children before the centre grow in reverse order, so feed this
            // list from the end for the verses to read downwards on screen.
            itemBuilder: (context, i) =>
                _occurrenceVerseRow(verses[centre - 1 - i]),
          ),
        ),
        SliverToBoxAdapter(
          key: ValueKey('occurrence-centre-$identity'),
          child: const SizedBox.shrink(),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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

  Widget _chip(BuildContext context, String label, String value) {
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

/// A merged NT occurrence: a single verse with all the matched word forms to
/// highlight within it.
/// One verse of an occurrence list, with everything matched inside it.
class _VerseOccurrence {
  _VerseOccurrence({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.words,
    List<int>? positions,
  }) : positions = positions ?? [];

  final int book;
  final int chapter;
  final int verse;

  /// The surface forms matched here. Used to highlight by text where no
  /// positions are known.
  final List<String> words;

  /// Lexical positions of the matched words, when the occurrence data carries
  /// them. Highlighting prefers these: a verse can hold a homograph of the
  /// looked-up word that is *not* an occurrence of its root, and text matching
  /// cannot tell the two apart.
  final List<int> positions;
}

class _VerseModeIcon extends StatelessWidget {
  const _VerseModeIcon({required this.englishOnly});

  final bool englishOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget segment(String label, bool active, String fontFamily) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.0,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
          fontFamilyFallback: const ['Noto Serif Hebrew'],
          color: active
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('א', !englishOnly, 'Cardo'),
          const SizedBox(width: 1),
          segment('EN', englishOnly, 'Cardo'),
        ],
      ),
    );
  }
}

/// One verse of an occurrence list, with the looked-up word highlighted.
///
/// Stateless: the verse text comes from the shared [VerseTextCache], so a row
/// scrolling into view costs a slot in the next batched request rather than a
/// round-trip and a stream listener of its own.
class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({
    super.key,
    required this.cache,
    required this.displayRef,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.highlightWords,
    required this.englishOnly,
    required this.useEnglishBookNames,
    this.positions = const [],
    this.isCurrent = false,
    this.onTap,
  });

  final VerseTextCache cache;
  final String displayRef;
  final int bookIndex;
  final int chapter;
  final int verse;
  final List<String> highlightWords;

  /// Lexical positions to highlight. Preferred over [highlightWords] when
  /// known, since text matching cannot tell an occurrence of the root from an
  /// unrelated homograph standing in the same verse.
  final List<int> positions;
  final bool englishOnly;
  final bool useEnglishBookNames;

  /// The verse the reader was looking at when the sheet opened.
  final bool isCurrent;
  final VoidCallback? onTap;

  String _compactRef() {
    final book = bookIndex >= 0 && bookIndex < kBooks.length
        ? kBooks[bookIndex]
        : null;
    if (book == null) return displayRef;
    return '${bookDisplayName(bookIndex, useEnglish: useEnglishBookNames)} '
        '$chapter:$verse';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<VerseTextData?>(
      valueListenable: cache.textFor(
        book: bookIndex + 1,
        chapter: chapter,
        verse: verse,
        englishOnly: englishOnly,
      ),
      builder: (context, data, _) {
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            decoration: isCurrent
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: theme.colorScheme.surfaceContainerHighest,
                  )
                : null,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A settled-but-empty verse is one the core could not read;
                // leaving the placeholder in place would spin forever.
                if (data == null)
                  const _VersePlaceholder()
                else
                  _buildHighlightedText(context, data),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHighlightedText(BuildContext context, VerseTextData data) {
    final theme = Theme.of(context);
    final baseStyle = TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: 15,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    final refStyle = TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
    final strippedTargets = highlightWords.map(_stripTrope).toSet();
    final keyTargets = highlightWords.map(_surfaceKey).toSet();
    // Hebrew mode matches the displayed words themselves. English-only shows
    // glosses, which never match a Hebrew surface, so match on the word each
    // gloss was made from and highlight the English standing in for it.
    final useGlosses =
        englishOnly &&
        data.glossWords.isNotEmpty &&
        data.sourceWords.length == data.glossWords.length;
    final tokens = useGlosses ? data.glossWords : data.text.split(' ');
    // Glosses come one per lexical word, so a position indexes them directly.
    // The Hebrew text also carries standalone punctuation, which has no lexical
    // position of its own — the same mapping the reader applies.
    final lexicalOf = useGlosses
        ? [for (var i = 0; i < tokens.length; i++) i]
        : verseGlossPositions(tokens);
    final targetPositions = positions.toSet();
    bool isTarget(int i) {
      if (targetPositions.isNotEmpty) {
        final lexical = lexicalOf[i];
        return lexical != null && targetPositions.contains(lexical);
      }
      // No positions known (an occurrence list that predates them, or a bare
      // surface lookup) — fall back to matching the text.
      final word = useGlosses ? data.sourceWords[i] : tokens[i];
      if (word.isEmpty) return false;
      return strippedTargets.contains(_stripTrope(word)) ||
          keyTargets.contains(_surfaceKey(word));
    }

    final spans = <InlineSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final token = tokens[i];
      if (isTarget(i)) {
        spans.add(
          TextSpan(
            text: token,
            style: baseStyle.copyWith(
              backgroundColor: theme.colorScheme.primaryContainer,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
    }
    spans.insert(0, TextSpan(text: '${_compactRef()}  ', style: refStyle));
    return SelectableText.rich(
      TextSpan(children: spans),
      textDirection: englishOnly ? TextDirection.ltr : TextDirection.rtl,
      // SelectableText swallows taps, so the wrapping InkWell never sees them;
      // forward single taps to keep click-to-navigate working.
      onTap: onTap,
    );
  }
}

/// Where a word falls across the canon, as one bar per book in Tanakh order.
///
/// A root's verse list answers "where does this occur" one screen at a time;
/// this answers it at a glance — and doubles as the book filter, since the
/// bar you want to look into is the one you just noticed was tall.
class _CanonDistribution extends StatelessWidget {
  const _CanonDistribution({
    required this.countsByBook,
    required this.selectedBook,
    required this.onSelect,
    required this.useEnglishBookNames,
  });

  /// Occurrence counts keyed by 1-based book number.
  final Map<int, int> countsByBook;
  final int? selectedBook;
  final void Function(int? book) onSelect;
  final bool useEnglishBookNames;

  static const _height = 26.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = countsByBook.keys.toList()..sort();
    if (books.isEmpty) return const SizedBox.shrink();
    final peak = countsByBook.values.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final book in books)
            Expanded(
              child: _bar(context, theme, book, countsByBook[book]!, peak),
            ),
          if (selectedBook != null)
            IconButton(
              tooltip: 'Whole Bible',
              icon: const Icon(Icons.close, size: 14),
              onPressed: () => onSelect(null),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 24,
                minHeight: _height,
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(
    BuildContext context,
    ThemeData theme,
    int book,
    int count,
    int peak,
  ) {
    final bookIndex = book - 1;
    final name = bookIndex >= 0 && bookIndex < kBooks.length
        ? bookDisplayName(bookIndex, useEnglish: useEnglishBookNames)
        : 'Book $book';
    final selected = selectedBook == book;
    // A floor under the height, so a book with a single occurrence is still
    // something you can see and aim at.
    final fraction = peak == 0 ? 0.0 : count / peak;
    return Tooltip(
      message: '$name · $count',
      child: GestureDetector(
        onTap: () => onSelect(selected ? null : book),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0.5),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 4 + (_height - 6) * fraction,
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.primary.withValues(alpha: 0.35),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The OT occurrence filter: surface forms on one tab, parses on the other.
///
/// Both lists are searchable and both report counts faceted by the other tab's
/// selection, so the numbers say what selecting an entry would actually yield.
class _OccurrenceFilterSheet extends StatefulWidget {
  const _OccurrenceFilterSheet({
    required this.occurrences,
    required this.parseLabel,
    required this.selectedForms,
    required this.selectedParses,
    required this.onChanged,
  });

  /// Every token the current book filter admits. The sheet counts its own
  /// facets from these rather than taking totals computed when it opened —
  /// those go stale the moment a selection changes, which is the one thing the
  /// sheet exists to do.
  final List<HebrewOccurrence> occurrences;
  final String Function(HebrewOccurrence) parseLabel;
  final Set<String> selectedForms;
  final Set<String> selectedParses;
  final void Function(Set<String> forms, Set<String> parses) onChanged;

  @override
  State<_OccurrenceFilterSheet> createState() => _OccurrenceFilterSheetState();
}

class _OccurrenceFilterSheetState extends State<_OccurrenceFilterSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Set<String> _forms = {...widget.selectedForms};
  late Set<String> _parses = {...widget.selectedParses};
  final _search = TextEditingController();

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _apply(VoidCallback change) {
    setState(change);
    widget.onChanged(_forms, _parses);
  }

  /// Counts for one dimension over the tokens the *other* dimension admits, so
  /// a number says what selecting that entry would actually yield.
  Map<String, int> _facet({
    required String Function(HebrewOccurrence) label,
    required String Function(HebrewOccurrence) otherLabel,
    required Set<String> otherSelection,
  }) {
    final counts = <String, int>{};
    for (final o in widget.occurrences) {
      if (otherSelection.isNotEmpty &&
          !otherSelection.contains(otherLabel(o))) {
        continue;
      }
      final key = label(o);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  static String _formOf(HebrewOccurrence o) => o.surface;

  /// Most frequent first, and alphabetically within a count, so the entries a
  /// reader is most likely to want are the ones they do not have to search for.
  List<String> _entries(Map<String, int> counts) {
    final query = _search.text.trim();
    final keys = counts.keys.where((key) {
      if (query.isEmpty) return true;
      // Hebrew is matched ignoring points, so a reader can type consonants.
      return key.contains(query) ||
          _stripTrope(key).contains(_stripTrope(query)) ||
          key.toLowerCase().contains(query.toLowerCase());
    }).toList();
    keys.sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formCounts = _facet(
      label: _formOf,
      otherLabel: widget.parseLabel,
      otherSelection: _parses,
    );
    final parseCounts = _facet(
      label: widget.parseLabel,
      otherLabel: _formOf,
      otherSelection: _forms,
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Text('Filter occurrences', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: _forms.isEmpty && _parses.isEmpty
                        ? null
                        : () => _apply(() {
                            _forms = {};
                            _parses = {};
                          }),
                    child: const Text('Reset'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(
                  height: 36,
                  text: _forms.isEmpty ? 'Form' : 'Form (${_forms.length})',
                ),
                Tab(
                  height: 36,
                  text: _parses.isEmpty ? 'Parse' : 'Parse (${_parses.length})',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Search',
                  border: const OutlineInputBorder(),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(_search.clear),
                        ),
                ),
              ),
            ),
            Flexible(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _list(
                    counts: formCounts,
                    selected: _forms,
                    allLabel: 'All forms',
                    hebrew: true,
                    onToggle: (key, on) => _apply(() {
                      final next = {..._forms};
                      on ? next.add(key) : next.remove(key);
                      _forms = next;
                    }),
                    onAll: () => _apply(() => _forms = {}),
                  ),
                  _list(
                    counts: parseCounts,
                    selected: _parses,
                    allLabel: 'All parses',
                    hebrew: false,
                    onToggle: (key, on) => _apply(() {
                      final next = {..._parses};
                      on ? next.add(key) : next.remove(key);
                      _parses = next;
                    }),
                    onAll: () => _apply(() => _parses = {}),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list({
    required Map<String, int> counts,
    required Set<String> selected,
    required String allLabel,
    required bool hebrew,
    required void Function(String key, bool on) onToggle,
    required VoidCallback onAll,
  }) {
    final entries = _entries(counts);
    final style = hebrew
        ? const TextStyle(
            fontFamily: 'Cardo',
            fontFamilyFallback: ['Noto Serif Hebrew'],
          )
        : null;
    return ListView.builder(
      // One tile per row: the previous multi-column grid packed more onto the
      // screen but gave a 300-entry list no order anyone could scan.
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return CheckboxListTile(
            dense: true,
            title: Text(allLabel),
            value: selected.isEmpty,
            onChanged: (_) => onAll(),
          );
        }
        final key = entries[i - 1];
        return CheckboxListTile(
          dense: true,
          title: Text(
            key,
            style: style,
            textDirection: hebrew ? TextDirection.rtl : TextDirection.ltr,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Text('${counts[key] ?? 0}'),
          value: selected.contains(key),
          onChanged: (on) => onToggle(key, on ?? false),
        );
      },
    );
  }
}

/// Stands in for a verse whose text has not arrived. A static bar rather than a
/// spinner: a screenful of rows means a screenful of these, and animating them
/// all costs a repaint every frame for no information.
class _VersePlaceholder extends StatelessWidget {
  const _VersePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _BdbContent extends StatelessWidget {
  const _BdbContent({
    required this.contentJson,
    required this.onBibleRefTap,
    required this.onXrefTap,
  });

  final String contentJson;
  final void Function(String href) onBibleRefTap;
  final void Function(String bdbId, String headword) onXrefTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(contentJson) as Map<String, dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    final senses = data['senses'] as List<dynamic>? ?? [];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: senses
            .map<Widget>(
              (s) => _buildSense(context, s as Map<String, dynamic>, 0),
            )
            .toList(),
      ),
    );
  }

  Widget _buildSense(
    BuildContext context,
    Map<String, dynamic> sense,
    int depth,
  ) {
    final theme = Theme.of(context);
    final num = sense['num'] as String?;
    final form = sense['form'] as String?;
    final definition = sense['definition'] as List<dynamic>?;
    final subSenses = sense['senses'] as List<dynamic>?;

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (form != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                form,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (definition != null)
            SelectableText.rich(
              TextSpan(
                children: [
                  if (num != null)
                    TextSpan(
                      text: '$num ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ..._spansFromDefinition(context, definition),
                ],
              ),
            ),
          if (subSenses != null)
            ...subSenses.map<Widget>(
              (s) => _buildSense(context, s as Map<String, dynamic>, depth + 1),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _spansFromDefinition(
    BuildContext context,
    List<dynamic> definition,
  ) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );

    return definition.map<InlineSpan>((spanData) {
      final span = spanData as Map<String, dynamic>;
      final text = span['t'] as String? ?? '';
      final bold = span['b'] == true;
      final italic = span['i'] == true;
      final small = span['s'] == true;
      final rtl = span['rtl'] == true;
      final href = span['href'] as String?;
      // A <w src> cross-reference: tappable, navigates to the target entry.
      final xref = span['xref'] as String?;
      final isLink = href != null || xref != null;

      TextStyle style = (baseStyle ?? const TextStyle()).copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
        fontSize: small ? (baseStyle?.fontSize ?? 12) * 0.85 : null,
        fontFamily: rtl ? 'Cardo' : null,
        fontFamilyFallback: rtl ? const ['Noto Serif Hebrew'] : null,
        color: isLink ? theme.colorScheme.primary : null,
        decoration: isLink ? TextDecoration.underline : null,
        decorationColor: isLink ? theme.colorScheme.primary : null,
      );

      if (href != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onBibleRefTap(href);
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }

      if (xref != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onXrefTap(xref, text);
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }

      return TextSpan(text: text, style: style);
    }).toList();
  }
}

/// BDB headwords are stored in Unicode NFC canonical order (vowel CCC=17 before
/// dagesh/shin-dot CCC=21-24), but Cardo expects the traditional Hebrew encoding
/// order (dagesh/shin-dot before vowel). Bubble-swap any such pairs.
String _normalizeHebrewCombining(String text) {
  final chars = text.runes.toList();
  var i = 0;
  while (i + 1 < chars.length) {
    if (_isHebVowel(chars[i]) && _isHebDot(chars[i + 1])) {
      final tmp = chars[i];
      chars[i] = chars[i + 1];
      chars[i + 1] = tmp;
    } else {
      i++;
    }
  }
  return String.fromCharCodes(chars);
}

bool _isHebVowel(int cp) =>
    (cp >= 0x05B0 && cp <= 0x05BD && cp != 0x05BC) || cp == 0x05C7;

bool _isHebDot(int cp) => cp == 0x05BC || cp == 0x05C1 || cp == 0x05C2;

String _stripTrope(String word) {
  return String.fromCharCodes(
    word.runes.where((cp) {
      return !((cp >= 0x0591 && cp <= 0x05AF) ||
          cp == 0x05BD ||
          cp == 0x05BE ||
          cp == 0x05C0 ||
          cp == 0x05C3 ||
          cp == 0x05C4 ||
          cp == 0x05C5 ||
          cp == 0x05C6);
    }),
  );
}

int _hebCombiningClass(int cp) {
  switch (cp) {
    case 0x05B0:
      return 10;
    case 0x05B1:
      return 11;
    case 0x05B2:
      return 12;
    case 0x05B3:
      return 13;
    case 0x05B4:
      return 14;
    case 0x05B5:
      return 15;
    case 0x05B6:
      return 16;
    case 0x05B7:
      return 17;
    case 0x05B8:
    case 0x05C7:
      return 18;
    case 0x05B9:
      return 19;
    case 0x05BB:
      return 20;
    case 0x05BC:
      return 21;
    case 0x05C1:
      return 24;
    case 0x05C2:
      return 25;
    default:
      return 0;
  }
}

/// Canonical surface key mirroring the Rust `normalize_surface`: keep only
/// consonants and pointing (dropping cantillation/maqaf/etc.), then stable-sort
/// each run of combining marks by combining class. Used to match the looked-up
/// word and verse tokens against the DB's normalised surface forms regardless
/// of trope or combining-mark order.
String _surfaceKey(String word) {
  final kept = word.runes.where((cp) {
    return (cp >= 0x05D0 && cp <= 0x05EA) ||
        (cp >= 0x05B0 && cp <= 0x05B9) ||
        cp == 0x05BB ||
        cp == 0x05BC ||
        cp == 0x05C1 ||
        cp == 0x05C2 ||
        cp == 0x05C7;
  }).toList();

  final out = <int>[];
  var i = 0;
  while (i < kept.length) {
    if (_hebCombiningClass(kept[i]) == 0) {
      out.add(kept[i]);
      i++;
    } else {
      final start = i;
      while (i < kept.length && _hebCombiningClass(kept[i]) != 0) {
        i++;
      }
      final run = kept.sublist(
        start,
        i,
      )..sort((a, b) => _hebCombiningClass(a).compareTo(_hebCombiningClass(b)));
      out.addAll(run);
    }
  }
  return String.fromCharCodes(out);
}

class _LexiconEntryOverrideEditor extends StatefulWidget {
  const _LexiconEntryOverrideEditor({
    required this.surface,
    required this.root,
    required this.gloss,
    this.readerGloss,
  });

  final String surface;
  final String root;
  final String gloss;
  final String? readerGloss;

  @override
  State<_LexiconEntryOverrideEditor> createState() =>
      _LexiconEntryOverrideEditorState();
}

class _LexiconEntryOverrideEditorState
    extends State<_LexiconEntryOverrideEditor> {
  late final TextEditingController _root = TextEditingController(
    text: widget.root,
  );
  late final TextEditingController _gloss = TextEditingController(
    text: widget.gloss,
  );
  late final TextEditingController _readerGloss = TextEditingController(
    text: widget.readerGloss ?? widget.gloss,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _root.dispose();
    _gloss.dispose();
    _readerGloss.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final gloss = _gloss.text.trim();
    final readerGloss = _readerGloss.text.trim();
    if (gloss.isEmpty) {
      setState(() => _error = 'A lexicon gloss is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final statusFuture = LexiconEntryOverrideStatus.rustSignalStream
        .firstWhere((pack) => pack.message.surface == widget.surface)
        .timeout(const Duration(seconds: 8));
    SaveLexiconEntryOverride(
      surface: widget.surface,
      root: _root.text.trim(),
      gloss: gloss,
      readerGloss: readerGloss,
    ).sendSignalToRust();
    try {
      final status = (await statusFuture).message;
      if (!mounted) return;
      if (!status.success) {
        setState(() {
          _saving = false;
          _error = status.message;
        });
        return;
      }
      scheduleProgressSync();
      Navigator.pop(context, status.message);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'The app did not confirm that the correction was saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit word glosses',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              widget.surface,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontFamily: 'Cardo',
                fontFamilyFallback: ['Noto Serif Hebrew'],
                fontSize: 36,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _root,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'Root (optional)',
                helperText: 'Leave blank for particles and rootless entries.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gloss,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Lexicon header gloss',
                helperText: 'The descriptive gloss shown in word information.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _readerGloss,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Interlinear gloss',
                helperText:
                    'The compact gloss shown below this word in the reader.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save correction'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BibleRefPreviewDialog extends StatefulWidget {
  const _BibleRefPreviewDialog({
    required this.displayRef,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    this.onNavigate,
  });

  final String displayRef;
  final int bookIndex;
  final int chapter;
  final int verse;
  final VoidCallback? onNavigate;

  @override
  State<_BibleRefPreviewDialog> createState() => _BibleRefPreviewDialogState();
}

class _BibleRefPreviewDialogState extends State<_BibleRefPreviewDialog> {
  StreamSubscription<RustSignalPack<VerseText>>? _sub;
  String? _verseText;

  @override
  void initState() {
    super.initState();
    final targetBook = widget.bookIndex + 1;
    _sub = VerseText.rustSignalStream.listen((pack) {
      final msg = pack.message;
      if (mounted &&
          msg.book == targetBook &&
          msg.chapter == widget.chapter &&
          msg.verse == widget.verse &&
          !msg.englishOnly) {
        setState(() => _verseText = msg.text);
        _sub?.cancel();
      }
    });
    GetVerseText(
      book: targetBook,
      chapter: widget.chapter,
      verse: widget.verse,
      englishOnly: false,
    ).sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = kBooks[widget.bookIndex];
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.displayRef, style: theme.textTheme.titleMedium),
          Text(
            '${book.transliteration} ${widget.chapter}:${widget.verse}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: _verseText == null
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            )
          : _buildVerseText(context, _verseText!),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (widget.onNavigate != null)
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(context);
              widget.onNavigate!();
            },
            child: const Text('Go to passage'),
          ),
      ],
    );
  }

  Widget _buildVerseText(BuildContext context, String text) {
    return SelectableText(
      text,
      style: TextStyle(
        fontFamily: 'Cardo',
        fontFamilyFallback: const ['Noto Serif Hebrew'],
        fontSize: 18,
        height: 1.6,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      textDirection: TextDirection.rtl,
    );
  }
}
