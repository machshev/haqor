import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import '../verse_counts.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart' show OccurrenceVerseRow;

/// How wide each account's column need be for them to stand side by side;
/// narrower, each is a tab of its own.
const _columnWidth = 300.0;

/// The most verses a column shows, so that a passage of chapters does not
/// ask for a book's text.
const _mostVerses = 200;

/// An event's accounts side by side, a column each, the Gospels in their
/// order and then the others by book: the parallels of a harmony. Each
/// column heads its passage, which opens it in the reader, over its verses
/// in the reader's text.
class EventParallelsPage extends StatefulWidget {
  const EventParallelsPage({
    super.key,
    required this.title,
    required this.passages,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.sendVerseTextsRequest,
  });

  final String title;
  final List<ThematicTarget> passages;
  final bool useEnglishBookNames;

  /// Opens a passage in the reader, this page closed first.
  final ValueChanged<StudyPassage> onOpenPassage;

  /// How verse requests reach Rust; a test passes its own.
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required List<ThematicTarget> passages,
    required bool useEnglishBookNames,
    required ValueChanged<StudyPassage> onOpenPassage,
    void Function(GetVerseTexts)? sendVerseTextsRequest,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventParallelsPage(
        title: title,
        passages: passages,
        useEnglishBookNames: useEnglishBookNames,
        onOpenPassage: onOpenPassage,
        sendVerseTextsRequest: sendVerseTextsRequest,
      ),
    ),
  );

  @override
  State<EventParallelsPage> createState() => _EventParallelsPageState();
}

/// The verses of [p], in order, from its first to its last; at most
/// [_mostVerses].
List<(int, int)> parallelVerses(ThematicTarget p) {
  final verses = <(int, int)>[];
  for (var c = p.chapter; c <= p.lastChapter; c++) {
    final first = c == p.chapter ? p.verse : 1;
    final last = c == p.lastChapter
        ? p.lastVerse
        : (verseCount(p.book - 1, c) ?? first);
    for (var v = first; v <= last; v++) {
      verses.add((c, v));
      if (verses.length == _mostVerses) return verses;
    }
  }
  return verses;
}

class _EventParallelsPageState extends State<EventParallelsPage> {
  late final VerseTextCache _cache = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );

  /// The reader's text: English glosses as the occurrence lists show them,
  /// or the original, the NT in Syriac or Greek as the reader is set.
  bool _englishOnly = false;
  bool _ntSyriac = false;
  bool _ntGreek = false;

  /// The accounts, the Gospels first in their order, then by book.
  late final List<ThematicTarget> _accounts = [...widget.passages]
    ..sort((a, b) {
      final c = a.book.compareTo(b.book);
      if (c != 0) return c;
      final ch = a.chapter.compareTo(b.chapter);
      return ch != 0 ? ch : a.verse.compareTo(b.verse);
    });

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final english = await occurrenceVerseEnglishOnlyEnabled();
      final prefs = await SharedPreferences.getInstance();
      final reading = readReadingSettings(prefs);
      if (!mounted) return;
      setState(() {
        _englishOnly = english;
        _ntSyriac = reading.ntSyriac;
        _ntGreek = reading.ntGreek;
      });
    } catch (_) {
      // Without stored settings, the original text stands.
    }
  }

  @override
  void dispose() {
    _cache.dispose();
    super.dispose();
  }

  String _book(ThematicTarget p) =>
      bookDisplayName(p.book - 1, useEnglish: widget.useEnglishBookNames);

  String _reference(ThematicTarget p) {
    final start = '${_book(p)} ${p.chapter}:${p.verse}';
    if (p.lastChapter == p.chapter && p.lastVerse == p.verse) return start;
    if (p.lastChapter == p.chapter) return '$start–${p.lastVerse}';
    return '$start–${p.lastChapter}:${p.lastVerse}';
  }

  StudyPassage _passage(ThematicTarget p, {int? chapter, int? verse}) =>
      chapter != null
      ? StudyPassage(bookIndex: p.book - 1, chapter: chapter, verse: verse!)
      : StudyPassage(
          bookIndex: p.book - 1,
          chapter: p.chapter,
          verse: p.verse,
          endChapter: p.lastChapter == p.chapter ? null : p.lastChapter,
          endVerse: p.lastChapter == p.chapter && p.lastVerse == p.verse
              ? null
              : p.lastVerse,
        );

  void _open(StudyPassage passage) {
    Navigator.pop(context);
    widget.onOpenPassage(passage);
  }

  Widget _heading(ThemeData theme, int i, ThematicTarget p) => Material(
    color: theme.colorScheme.surfaceContainerLow,
    child: InkWell(
      key: ValueKey('parallels-heading-$i'),
      onTap: () => _open(_passage(p)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _reference(p),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Icon(
              Icons.menu_book_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _verses(int i, ThematicTarget p) {
    final verses = parallelVerses(p);
    return ListView.builder(
      key: ValueKey('parallels-column-$i'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
      itemCount: verses.length,
      itemBuilder: (context, n) {
        final (chapter, verse) = verses[n];
        return OccurrenceVerseRow(
          key: ValueKey('parallels-verse-$i-$chapter:$verse'),
          cache: _cache,
          displayRef: '$chapter:$verse',
          bookIndex: p.book - 1,
          chapter: chapter,
          verse: verse,
          highlightWords: const [],
          englishOnly: _englishOnly,
          syriac: _ntSyriac && p.book >= 40,
          greek: _ntGreek && p.book >= 40,
          useEnglishBookNames: widget.useEnglishBookNames,
          onTap: () => _open(_passage(p, chapter: chapter, verse: verse)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toggle = IconButton(
      key: const ValueKey('parallels-english'),
      tooltip: _englishOnly ? 'Show the original' : 'Show the English',
      isSelected: _englishOnly,
      icon: const Icon(Icons.translate),
      onPressed: () {
        setState(() => _englishOnly = !_englishOnly);
        setOccurrenceVerseEnglishOnlyEnabled(_englishOnly);
      },
    );
    final subtitle = Text(
      _accounts.length == 1 ? '1 account' : '${_accounts.length} accounts',
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(widget.title), subtitle],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _columnWidth * _accounts.length) {
          return Scaffold(
            appBar: AppBar(title: title, actions: [toggle]),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, p) in _accounts.indexed) ...[
                  if (i > 0) const VerticalDivider(width: 1),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _heading(theme, i, p),
                        Expanded(child: _verses(i, p)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }
        return DefaultTabController(
          length: _accounts.length,
          child: Scaffold(
            appBar: AppBar(
              title: title,
              actions: [toggle],
              bottom: TabBar(
                isScrollable: _accounts.length > 3,
                tabs: [
                  for (final (i, p) in _accounts.indexed)
                    Tab(key: ValueKey('parallels-tab-$i'), text: _book(p)),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                for (final (i, p) in _accounts.indexed)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heading(theme, i, p),
                      Expanded(child: _verses(i, p)),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
