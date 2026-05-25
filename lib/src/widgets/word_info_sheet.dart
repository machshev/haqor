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
  bool _thisFormExpanded = true;
  bool _byRootExpanded = true;
  bool _isFlagged = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _sub = WordInfo.rustSignalStream.listen((pack) {
      if (mounted) {
        setState(() => _info = pack.message);
        _sub?.cancel();
      }
    });
    GetWordInfo(word: widget.word, syriac: widget.syriac).sendSignalToRust();
    _loadFlagState();
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
      initialChildSize: 0.65,
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
                child: info == null
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(context, scrollController, info),
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
                          fontFamily: 'Cardo',
                          fontFamilyFallback: const ['Noto Serif Hebrew'],
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
                            fontFamily: 'Cardo',
                            fontFamilyFallback: const ['Noto Serif Hebrew'],
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
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [
        if (info.bdbEntries.isNotEmpty) ...[
          Text(
            'BDB Entries',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          ...info.bdbEntries.indexed.map((entry) {
            final (i, e) = entry;
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
                        Text(
                          e.headword,
                          style: TextStyle(
                            fontFamily: 'Cardo',
                            fontFamilyFallback: const ['Noto Serif Hebrew'],
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        if (e.gloss.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '— ${e.gloss}',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
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
          }),
        ],
        if (info.sedraEntries.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Sedra Lexicon',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
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
                          color: theme.colorScheme.onSurface,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.meaning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    final both =
        info.occurrences.isNotEmpty && info.rootOccurrences.isNotEmpty;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [
        if (info.occurrences.isNotEmpty) ...[
          if (both)
            _sectionHeader(
              context,
              'This form (${info.occurrences.length})',
              _thisFormExpanded,
              () => setState(() => _thisFormExpanded = !_thisFormExpanded),
            ),
          if (!both || _thisFormExpanded) ..._occurrenceRows(info.occurrences),
        ],
        if (info.rootOccurrences.isNotEmpty) ...[
          if (both) ...[
            const SizedBox(height: 8),
            _sectionHeader(
              context,
              'By root (${info.rootOccurrences.length})',
              _byRootExpanded,
              () => setState(() => _byRootExpanded = !_byRootExpanded),
            ),
          ],
          if (!both || _byRootExpanded) ..._occurrenceRows(info.rootOccurrences),
        ],
      ],
    );
  }

  List<Widget> _occurrenceRows(List<WordOccurrence> occurrences) {
    return occurrences.map((o) {
      final bookIndex = o.book - 1;
      final bookName = bookIndex >= 0 && bookIndex < kBooks.length
          ? kBooks[bookIndex].transliteration
          : 'Book ${o.book}';
      final ref = '$bookName ${o.chapter}:${o.verse}';
      return _OccurrenceRow(
        displayRef: ref,
        bookIndex: bookIndex,
        chapter: o.chapter,
        verse: o.verse,
        highlightWord: widget.word,
        onTap: widget.onNavigateToPassage == null
            ? null
            : () => widget.onNavigateToPassage!(
                  bookIndex,
                  o.chapter,
                  o.verse,
                ),
      );
    }).toList();
  }

  Widget _sectionHeader(
    BuildContext context,
    String title,
    bool expanded,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
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

class _OccurrenceRow extends StatefulWidget {
  const _OccurrenceRow({
    required this.displayRef,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.highlightWord,
    this.onTap,
  });

  final String displayRef;
  final int bookIndex;
  final int chapter;
  final int verse;
  final String highlightWord;
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
    final theme = Theme.of(context);
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
    final strippedTarget = _stripTrope(widget.highlightWord);
    final tokens = text.split(' ');
    final spans = <InlineSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final token = tokens[i];
      if (_stripTrope(token) == strippedTarget) {
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
    return RichText(
      text: TextSpan(children: spans),
      textDirection: TextDirection.rtl,
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
            RichText(
              text: TextSpan(
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
    return Text(
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
