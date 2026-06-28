import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bindings/bindings.dart';
import '../bible_data.dart';

const _kFlaggedWordsKey = 'debug_flagged_words';

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
    this.onNavigateToPassage,
  });

  final String word;
  final bool syriac;
  final void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage;

  @override
  State<WordInfoSheet> createState() => _WordInfoSheetState();
}

class _WordInfoSheetState extends State<WordInfoSheet>
    with SingleTickerProviderStateMixin {
  StreamSubscription<RustSignalPack<WordInfo>>? _sub;
  WordInfo? _info;
  final Set<int> _expandedBdb = {};
  late final TabController _tabController;
  bool _isFlagged = false;
  // OT-only: which surface forms of the root are shown in the occurrences list.
  // Null until first built, then defaults to the looked-up word's form. Empty
  // set means "show all forms".
  Set<String>? _otForms;
  // NT-only: which lexeme indices (positions in info.sedraEntries) are shown in
  // the occurrences list. Null until first built, then defaults to the looked-up
  // lexeme. Empty set means "show all".
  Set<int>? _selectedLexemes;
  // NT-only: when true the occurrences list shows OT (Hebrew Bible) verses of
  // the same consonantal root instead of the SEDRA-based NT occurrences.
  bool _otSelected = false;
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
    _sub = WordInfo.rustSignalStream.listen((pack) {
      if (mounted) {
        setState(() => _info = pack.message);
        _sub?.cancel();
        // Preload the occurrence scans in the background as soon as the lexicon
        // data lands, so the Occurrences tab is already populated (or at least
        // loading) by the time the user switches to it.
        if (pack.message.found) _fetchOccurrences();
      }
    });
    GetWordInfo(word: widget.word, syriac: widget.syriac).sendSignalToRust();
    _loadFlagState();
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
    GetWordOccurrences(word: widget.word, syriac: widget.syriac)
        .sendSignalToRust();
  }

  Future<void> _loadFlagState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFlaggedWordsKey) ?? [];
    final flagged = raw.any((e) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        return map['word'] == widget.word;
      } catch (_) {
        return false;
      }
    });
    if (mounted) setState(() => _isFlagged = flagged);
  }

  Future<void> _openFlagDialog(BuildContext context, WordInfo info) async {
    String existingNote = '';
    if (_isFlagged) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kFlaggedWordsKey) ?? [];
      for (final e in raw) {
        try {
          final map = jsonDecode(e) as Map<String, dynamic>;
          if (map['word'] == widget.word) {
            existingNote = map['note'] as String? ?? '';
            break;
          }
        } catch (_) {}
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => _FlagNoteDialog(
        word: info.word,
        isFlagged: _isFlagged,
        existingNote: existingNote,
        onSave: (note) => _saveFlag(info, note),
        onRemove: _removeFlag,
      ),
    );
  }

  Future<void> _saveFlag(WordInfo info, String note) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFlaggedWordsKey) ?? [];
    final filtered = raw.where((e) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        return map['word'] != widget.word;
      } catch (_) {
        return true;
      }
    }).toList();
    final entry = {
      'word': widget.word,
      'displayWord': info.word,
      'gloss': info.gloss,
      'root': info.root,
      'syriac': widget.syriac,
      'note': note,
      'flaggedAt': DateTime.now().toIso8601String(),
      'morphology': {
        if (info.gender != null) 'gender': info.gender,
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
    };
    filtered.add(jsonEncode(entry));
    await prefs.setStringList(_kFlaggedWordsKey, filtered);
    if (mounted) setState(() => _isFlagged = true);
  }

  Future<void> _removeFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFlaggedWordsKey) ?? [];
    final updated = raw.where((e) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        return map['word'] != widget.word;
      } catch (_) {
        return true;
      }
    }).toList();
    await prefs.setStringList(_kFlaggedWordsKey, updated);
    if (mounted) setState(() => _isFlagged = false);
  }

  Future<void> _showFlaggedExport(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kFlaggedWordsKey) ?? [];
    final entries = raw
        .map((e) {
          try {
            return jsonDecode(e) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();

    if (!mounted) return;
    final exportJson =
        const JsonEncoder.withIndent('  ').convert({'flaggedWords': entries});
    showDialog<void>(
      context: context,
      builder: (_) => _FlaggedWordsExportDialog(json: exportJson),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sub?.cancel();
    _occSub?.cancel();
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
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 12),
            Text(
              'Not found in database',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
                  GestureDetector(
                    onLongPress: () => _showFlaggedExport(context),
                    child: IconButton(
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: _isFlagged
                          ? 'Flagged — long-press to export all'
                          : 'Flag word as having issues',
                      icon: Icon(
                        _isFlagged ? Icons.flag : Icons.flag_outlined,
                        color: _isFlagged
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => _openFlagDialog(context, info),
                    ),
                  ),
                  const SizedBox(width: 4),
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
    // common and proper-noun groups below.
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
                      child: Text(
                        '${e.gloss} —',
                        style: theme.textTheme.bodyMedium,
                      ),
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

    // Proper names crowd out a root's actual meaning, so list them under their
    // own heading after the common lexemes.
    final common = info.bdbEntries.indexed
        .where((p) => !p.$2.properNoun)
        .toList();
    final proper = info.bdbEntries.indexed
        .where((p) => p.$2.properNoun)
        .toList();

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [
        if (common.isNotEmpty) ...[
          sectionHeading('BDB Entries'),
          const SizedBox(height: 4),
          ...common.map((p) => buildBdbRow(p.$1, p.$2)),
        ],
        if (proper.isNotEmpty) ...[
          if (common.isNotEmpty) const SizedBox(height: 12),
          sectionHeading('Proper nouns'),
          const SizedBox(height: 4),
          ...proper.map((p) => buildBdbRow(p.$1, p.$2)),
        ],
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
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
                          color: theme.colorScheme.primaryContainer
                              .withOpacity(0.6),
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

    if (occ.occurrences.isNotEmpty || occ.rootOccurrences.isNotEmpty) {
      return _buildHebrewOccurrencesTab(context, info, occ, bottomPad);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: const [],
    );
  }

  /// OT counterpart of [_buildSedraOccurrencesTab]: a pinned filter header with
  /// a verse count over a merged-by-verse list. The NT side filters by lexeme;
  /// the OT side filters by surface form (the inflected forms sharing the root),
  /// since the parse data carries no per-occurrence lexeme.
  Widget _buildHebrewOccurrencesTab(
    BuildContext context,
    WordInfo info,
    WordOccurrences occ,
    double bottomPad,
  ) {
    final theme = Theme.of(context);

    // Older/edge data (e.g. an NT lookup with no detailed occurrences) has no
    // per-form tagging — fall back to a flat root list highlighting the word.
    if (occ.hebrewOccurrences.isEmpty) {
      final flat = [
        for (final o in (occ.rootOccurrences.isNotEmpty
            ? occ.rootOccurrences
            : occ.occurrences))
          _VerseOccurrence(
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            words: [widget.word],
          ),
      ];
      return ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
        children: _occurrenceVerseRows(flat),
      );
    }

    // Distinct-verse counts per surface form, for the chip labels. The detailed
    // query already returns one row per (verse, form).
    final counts = <String, int>{};
    for (final o in occ.hebrewOccurrences) {
      counts[o.form] = (counts[o.form] ?? 0) + 1;
    }
    final forms = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });

    // Lazily default the filter to the looked-up word's form.
    if (_otForms == null) {
      final key = _surfaceKey(widget.word);
      final match = forms.firstWhere(
        (f) => _surfaceKey(f) == key,
        orElse: () => '',
      );
      _otForms = match.isEmpty ? {} : {match};
    }
    final selected = _otForms!;
    final showAll = selected.isEmpty;

    // Apply the filter, then merge rows on the same verse so a verse appears
    // once with all matched forms highlighted.
    final byVerse = <String, _VerseOccurrence>{};
    for (final o in occ.hebrewOccurrences) {
      if (!showAll && !selected.contains(o.form)) continue;
      final key = '${o.book}:${o.chapter}:${o.verse}';
      final existing = byVerse[key];
      if (existing == null) {
        byVerse[key] = _VerseOccurrence(
          book: o.book,
          chapter: o.chapter,
          verse: o.verse,
          words: [o.form],
        );
      } else if (!existing.words.contains(o.form)) {
        existing.words.add(o.form);
      }
    }
    final verses = byVerse.values.toList();
    verses.sort((a, b) {
      if (a.book != b.book) return a.book.compareTo(b.book);
      if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
      return a.verse.compareTo(b.verse);
    });

    final String filterSummary;
    if (showAll) {
      filterSummary = 'All forms';
    } else if (selected.length == 1) {
      filterSummary = selected.first;
    } else {
      filterSummary = '${selected.length} forms';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
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
                      _openHebrewFilterSheet(context, forms, counts),
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
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
            children: _occurrenceVerseRows(verses),
          ),
        ),
      ],
    );
  }

  Future<void> _openHebrewFilterSheet(
    BuildContext context,
    List<String> forms,
    Map<String, int> counts,
  ) async {
    final theme = Theme.of(context);
    const formStyle = TextStyle(
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
            final selected = _otForms ?? {};
            final showAll = selected.isEmpty;
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
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          CheckboxListTile(
                            dense: true,
                            title: const Text('All forms'),
                            value: showAll,
                            onChanged: (_) => apply(() {
                              _otForms = {};
                            }),
                          ),
                          for (final form in forms)
                            CheckboxListTile(
                              dense: true,
                              title: Text(
                                '$form (${counts[form] ?? 0})',
                                style: formStyle,
                                textDirection: TextDirection.rtl,
                              ),
                              value: selected.contains(form),
                              onChanged: (on) => apply(() {
                                final next = {...selected};
                                if (on ?? false) {
                                  next.add(form);
                                } else {
                                  next.remove(form);
                                }
                                _otForms = next;
                              }),
                            ),
                        ],
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
    final filtered = occ.sedraOccurrences
        .where((o) => showAll || selected.contains(o.lexemeIndex));
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
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
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
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
            children: _occurrenceVerseRows(verses),
          ),
        ),
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
                      child: ListView(
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
                          for (var i = 0; i < info.sedraEntries.length; i++)
                            CheckboxListTile(
                              dense: true,
                              title: Text(
                                '${info.sedraEntries[i].lexeme} (${counts[i] ?? 0})',
                                style: lexStyle,
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
                            ),
                        ],
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

  List<Widget> _occurrenceVerseRows(List<_VerseOccurrence> verses) {
    return verses.map((v) {
      final bookIndex = v.book - 1;
      final bookName = bookIndex >= 0 && bookIndex < kBooks.length
          ? kBooks[bookIndex].transliteration
          : 'Book ${v.book}';
      final ref = '$bookName ${v.chapter}:${v.verse}';
      return _OccurrenceRow(
        // Stable identity per verse so Flutter never re-binds a row's State
        // (which caches the fetched verse text) to a different verse on rebuild.
        key: ValueKey('${v.book}:${v.chapter}:${v.verse}'),
        displayRef: ref,
        bookIndex: bookIndex,
        chapter: v.chapter,
        verse: v.verse,
        highlightWords: v.words,
        onTap: widget.onNavigateToPassage == null
            ? null
            : () => widget.onNavigateToPassage!(bookIndex, v.chapter, v.verse),
      );
    }).toList();
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
class _VerseOccurrence {
  _VerseOccurrence({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.words,
  });

  final int book;
  final int chapter;
  final int verse;
  final List<String> words;
}

class _OccurrenceRow extends StatefulWidget {
  const _OccurrenceRow({
    super.key,
    required this.displayRef,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.highlightWords,
    this.onTap,
  });

  final String displayRef;
  final int bookIndex;
  final int chapter;
  final int verse;
  final List<String> highlightWords;
  final VoidCallback? onTap;

  @override
  State<_OccurrenceRow> createState() => _OccurrenceRowState();
}

class _OccurrenceRowState extends State<_OccurrenceRow> {
  StreamSubscription<RustSignalPack<VerseText>>? _sub;
  String? _text;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(_OccurrenceRow old) {
    super.didUpdateWidget(old);
    // Defensive: if this State is ever re-bound to a different verse, drop the
    // cached text and fetch again rather than rendering the previous verse.
    if (old.bookIndex != widget.bookIndex ||
        old.chapter != widget.chapter ||
        old.verse != widget.verse) {
      _sub?.cancel();
      _text = null;
      _fetch();
    }
  }

  void _fetch() {
    final targetBook = widget.bookIndex + 1;
    _sub = VerseText.rustSignalStream.listen((pack) {
      final msg = pack.message;
      if (mounted &&
          msg.book == targetBook &&
          msg.chapter == widget.chapter &&
          msg.verse == widget.verse) {
        setState(() => _text = msg.text);
        _sub?.cancel();
      }
    });
    GetVerseText(
      book: targetBook,
      chapter: widget.chapter,
      verse: widget.verse,
    ).sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _compactRef() {
    final book = widget.bookIndex >= 0 && widget.bookIndex < kBooks.length
        ? kBooks[widget.bookIndex]
        : null;
    if (book == null) return widget.displayRef;
    return '${book.hebrew} ${widget.chapter}:${widget.verse}';
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (text == null)
              SizedBox(
                height: 20,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              )
            else
              _buildHighlightedText(context, text),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedText(BuildContext context, String text) {
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
      color: theme.colorScheme.primary,
    );
    final strippedTargets =
        widget.highlightWords.map(_stripTrope).toSet();
    final keyTargets = widget.highlightWords.map(_surfaceKey).toSet();
    final tokens = text.split(' ');
    final spans = <InlineSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final token = tokens[i];
      if (strippedTargets.contains(_stripTrope(token)) ||
          keyTargets.contains(_surfaceKey(token))) {
        spans.add(TextSpan(
          text: token,
          style: baseStyle.copyWith(
            backgroundColor: theme.colorScheme.primaryContainer,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ));
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
    }
    spans.insert(0, TextSpan(text: '${_compactRef()}  ', style: refStyle));
    return SelectableText.rich(
      TextSpan(children: spans),
      textDirection: TextDirection.rtl,
      // SelectableText swallows taps, so the wrapping InkWell never sees them;
      // forward single taps to keep click-to-navigate working.
      onTap: widget.onTap,
    );
  }
}

class _BdbContent extends StatelessWidget {
  const _BdbContent({
    required this.contentJson,
    required this.onBibleRefTap,
  });

  final String contentJson;
  final void Function(String href) onBibleRefTap;

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
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
      padding: EdgeInsets.only(
        left: depth * 12.0,
        bottom: 4,
      ),
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
              (s) => _buildSense(
                context,
                s as Map<String, dynamic>,
                depth + 1,
              ),
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

      TextStyle style = (baseStyle ?? const TextStyle()).copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
        fontSize: small ? (baseStyle?.fontSize ?? 12) * 0.85 : null,
        fontFamily: rtl ? 'Cardo' : null,
        fontFamilyFallback: rtl ? const ['Noto Serif Hebrew'] : null,
        color: href != null ? theme.colorScheme.primary : null,
        decoration: href != null ? TextDecoration.underline : null,
        decorationColor: href != null ? theme.colorScheme.primary : null,
      );

      if (href != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onBibleRefTap(href);
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
      final run = kept.sublist(start, i)
        ..sort((a, b) => _hebCombiningClass(a).compareTo(_hebCombiningClass(b)));
      out.addAll(run);
    }
  }
  return String.fromCharCodes(out);
}

class _FlagNoteDialog extends StatefulWidget {
  const _FlagNoteDialog({
    required this.word,
    required this.isFlagged,
    required this.existingNote,
    required this.onSave,
    required this.onRemove,
  });

  final String word;
  final bool isFlagged;
  final String existingNote;
  final void Function(String note) onSave;
  final VoidCallback onRemove;

  @override
  State<_FlagNoteDialog> createState() => _FlagNoteDialogState();
}

class _FlagNoteDialogState extends State<_FlagNoteDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.existingNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.word,
        style: const TextStyle(
          fontFamily: 'Cardo',
          fontFamilyFallback: ['Noto Serif Hebrew'],
          fontSize: 24,
        ),
        textDirection: TextDirection.rtl,
      ),
      content: TextField(
        controller: _controller,
        maxLines: 4,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Describe the issue…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        if (widget.isFlagged)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(context);
              widget.onRemove();
            },
            child: const Text('Remove flag'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onSave(_controller.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _FlaggedWordsExportDialog extends StatelessWidget {
  const _FlaggedWordsExportDialog({required this.json});

  final String json;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = (jsonDecode(json)['flaggedWords'] as List).length;
    return AlertDialog(
      title: Text('Flagged words ($count)'),
      content: SizedBox(
        width: double.maxFinite,
        child: count == 0
            ? Text(
                'No words flagged yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : SingleChildScrollView(
                child: SelectableText(
                  json,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (count > 0)
          FilledButton.tonal(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: json));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy JSON'),
          ),
      ],
    );
  }
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
  State<_BibleRefPreviewDialog> createState() =>
      _BibleRefPreviewDialogState();
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
          msg.verse == widget.verse) {
        setState(() => _verseText = msg.text);
        _sub?.cancel();
      }
    });
    GetVerseText(
      book: targetBook,
      chapter: widget.chapter,
      verse: widget.verse,
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
          Text(
            widget.displayRef,
            style: theme.textTheme.titleMedium,
          ),
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
