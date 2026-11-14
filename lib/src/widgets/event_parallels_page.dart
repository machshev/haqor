import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import '../verse_counts.dart';
import 'verse_row.dart';

/// How wide each account's column need be for them to stand side by side,
/// one text in each; narrower, each is a tab of its own.
const _columnWidth = 260.0;

/// The same with the original and the English side by side in each.
const _parallelColumnWidth = 520.0;

/// The most verses a column shows, so that a passage of chapters does not
/// ask for a book's text.
const _mostVerses = 200;

/// An event's accounts side by side, a column each, the Gospels in their
/// order and then the others by book: the parallels of a harmony. Each
/// column heads its passage, which opens it in the reader, over its verses
/// as the reader shows them: the original, the English, or both side by
/// side, with or without the interlinear, the New Testament in Aramaic or
/// Greek. These start as the reader is set and are changed here for this
/// page alone. On a phone the page turns to landscape, for room.
class EventParallelsPage extends StatefulWidget {
  const EventParallelsPage({
    super.key,
    required this.title,
    required this.passages,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.sendChapterRequest,
    this.sendTranslationRequest,
  });

  final String title;
  final List<ThematicTarget> passages;
  final bool useEnglishBookNames;

  /// Opens a passage in the reader, this page closed first.
  final ValueChanged<StudyPassage> onOpenPassage;

  /// How the chapters' text and English reach Rust; a test passes its own.
  final void Function(GetChapter)? sendChapterRequest;
  final void Function(GetChapterTranslation)? sendTranslationRequest;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required List<ThematicTarget> passages,
    required bool useEnglishBookNames,
    required ValueChanged<StudyPassage> onOpenPassage,
    void Function(GetChapter)? sendChapterRequest,
    void Function(GetChapterTranslation)? sendTranslationRequest,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => EventParallelsPage(
        title: title,
        passages: passages,
        useEnglishBookNames: useEnglishBookNames,
        onOpenPassage: onOpenPassage,
        sendChapterRequest: sendChapterRequest,
        sendTranslationRequest: sendTranslationRequest,
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

/// A chapter as asked of Rust: book (1-based), chapter, Syriac, Greek,
/// glosses, morphology and names, as [ChapterText] answers it.
typedef _ChapterKey = (int, int, bool, bool, bool, bool, bool);

/// A chapter's English: book (1-based), chapter, and whether from the
/// Greek.
typedef _TranslationKey = (int, int, bool);

/// Translation request ids, far from the reader's own, so that neither
/// takes the other's answer.
int _nextTranslationRequestId = 1 << 29;

class _EventParallelsPageState extends State<EventParallelsPage> {
  AppReadingSettings _settings = kDefaultReadingSettings;
  bool _loaded = false;

  ReaderText _text = ReaderText.source;
  bool _interlinear = false;
  bool _glosses = false;
  bool _morphology = false;
  bool _ntGreek = false;
  bool _ntSyriac = false;

  /// Whether this is a phone, which the page turns to landscape while
  /// [_landscape] holds.
  bool _phone = false;
  bool _landscape = false;
  bool _orientationChecked = false;

  final _chapters = <_ChapterKey, Map<int, VerseEntry>>{};
  final _askedChapters = <_ChapterKey>{};
  final _translations =
      <_TranslationKey, Map<int, List<TranslationSpanEntry>>>{};
  final _translationRequests = <int, _TranslationKey>{};
  StreamSubscription<RustSignalPack<ChapterText>>? _chapterSub;
  StreamSubscription<RustSignalPack<ChapterTranslation>>? _translationSub;

  /// The accounts, the Gospels first in their order, then by book.
  late final List<ThematicTarget> _accounts = [...widget.passages]
    ..sort((a, b) {
      final c = a.book.compareTo(b.book);
      if (c != 0) return c;
      final ch = a.chapter.compareTo(b.chapter);
      return ch != 0 ? ch : a.verse.compareTo(b.verse);
    });

  bool get _anyNewTestament => _accounts.any((p) => p.book >= 40);

  @override
  void initState() {
    super.initState();
    _chapterSub = ChapterText.rustSignalStream.listen((pack) {
      final m = pack.message;
      final key = (
        m.book,
        m.chapter,
        m.syriac,
        m.greek,
        m.includeGlosses,
        m.includeMorphology,
        m.includeNames,
      );
      if (!mounted || m.includeRoots || !_askedChapters.remove(key)) return;
      setState(() => _chapters[key] = {for (final v in m.verses) v.verse: v});
    });
    _translationSub = ChapterTranslation.rustSignalStream.listen((pack) {
      final key = _translationRequests.remove(pack.message.requestId);
      if (key == null || !mounted) return;
      setState(
        () => _translations[key] = {
          for (final v in pack.message.verses) v.verse: v.spans,
        },
      );
    });
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orientationChecked) return;
    _orientationChecked = true;
    final mobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    _phone = mobile && MediaQuery.sizeOf(context).shortestSide < 600;
    if (_phone) _setLandscape(true);
  }

  void _setLandscape(bool landscape) {
    setState(() => _landscape = landscape);
    SystemChrome.setPreferredOrientations(
      landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [],
    );
  }

  Future<void> _loadSettings() async {
    var settings = kDefaultReadingSettings;
    try {
      settings = readReadingSettings(await SharedPreferences.getInstance());
    } catch (_) {
      // Without stored settings, the reader's defaults stand.
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _text = settings.readerText;
      _interlinear = settings.showInterlinear && !settings.rapidReading;
      _glosses = settings.glossInterlinear;
      _morphology = settings.morphologyInterlinear;
      _ntGreek = settings.ntGreek;
      _ntSyriac = settings.ntSyriac;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _chapterSub?.cancel();
    _translationSub?.cancel();
    // Back to whatever the app allows.
    if (_landscape) SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  bool _greek(int book) => book >= 40 && _ntGreek;
  bool _syriac(int book) => book >= 40 && _ntSyriac && !_ntGreek;

  /// [book]'s (1-based) verse, asking for its chapter as now shown if it
  /// is not here; null until it comes.
  VerseEntry? _verse(int book, int chapter, int verse) {
    final key = (
      book,
      chapter,
      _syriac(book),
      _greek(book),
      _glosses,
      _morphology,
      _settings.highlightProperNames,
    );
    final verses = _chapters[key];
    if (verses != null) return verses[verse];
    if (_askedChapters.add(key)) {
      final request = GetChapter(
        book: book,
        chapter: chapter,
        syriac: key.$3,
        greek: key.$4,
        includeGlosses: key.$5,
        includeMorphology: key.$6,
        includeNames: key.$7,
        includeRoots: false,
      );
      final send = widget.sendChapterRequest;
      if (send != null) {
        send(request);
      } else {
        request.sendSignalToRust();
      }
    }
    return null;
  }

  /// [book]'s (1-based) verse in English, asking for its chapter's if it
  /// is not here: none for the original alone, pending until it comes.
  ({List<TranslationSpanEntry>? spans, bool pending}) _english(
    int book,
    int chapter,
    int verse,
  ) {
    if (_text == ReaderText.source) return (spans: null, pending: false);
    final key = (book, chapter, _greek(book));
    final verses = _translations[key];
    if (verses != null) return (spans: verses[verse], pending: false);
    if (!_translationRequests.containsValue(key)) {
      final id = _nextTranslationRequestId++;
      _translationRequests[id] = key;
      final request = GetChapterTranslation(
        requestId: id,
        book: book,
        chapter: chapter,
        greek: key.$3,
      );
      final send = widget.sendTranslationRequest;
      if (send != null) {
        send(request);
      } else {
        request.sendSignalToRust();
      }
    }
    return (spans: null, pending: true);
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

  Widget _verses(ThemeData theme, int i, ThematicTarget p) {
    final verses = parallelVerses(p);
    return ListView.builder(
      key: ValueKey('parallels-column-$i'),
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemCount: verses.length,
      itemBuilder: (context, n) {
        final (chapter, verse) = verses[n];
        // A passage running into the next chapter says so where it does.
        final newChapter = n > 0 && verses[n - 1].$1 != chapter;
        final entry = _loaded ? _verse(p.book, chapter, verse) : null;
        final Widget row;
        if (entry == null) {
          row = Padding(
            key: ValueKey('parallels-verse-$i-$chapter:$verse'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '$chapter:$verse …',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        } else {
          final english = _english(p.book, chapter, verse);
          void open() => _open(_passage(p, chapter: chapter, verse: verse));
          row = VerseRow(
            key: ValueKey('parallels-verse-$i-$chapter:$verse'),
            entry: entry,
            isSelected: false,
            hebrewNumerals: _settings.hebrewNumerals,
            onTap: open,
            onWordTap: (_, _, _, _) => open(),
            fontSize: _settings.fontSize,
            fontFamily: _settings.fontFamily,
            sourceDirection: _greek(p.book)
                ? TextDirection.ltr
                : TextDirection.rtl,
            showCantillation: _settings.showCantillation,
            glossInterlinear: _glosses,
            morphologyInterlinear: _morphology,
            interlinearPositions: _interlinear ? null : const {},
            highlightProperNames: _settings.highlightProperNames,
            ketivDisplay: _settings.ketivDisplay,
            readerText: _text,
            translation: english.spans,
            translationPending: english.pending,
          );
        }
        if (!newChapter) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                '${_book(p)} $chapter',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            row,
          ],
        );
      },
    );
  }

  String _textLabel(ReaderText text) => switch (text) {
    ReaderText.source => 'Original',
    ReaderText.english => 'English',
    ReaderText.parallel => 'Original and English',
  };

  List<Widget> _actions() => [
    PopupMenuButton<ReaderText>(
      key: const ValueKey('parallels-text'),
      tooltip: 'Text: ${_textLabel(_text)}',
      icon: Icon(switch (_text) {
        ReaderText.source => Icons.format_textdirection_r_to_l,
        ReaderText.english => Icons.format_textdirection_l_to_r,
        ReaderText.parallel => Icons.vertical_split_outlined,
      }),
      onSelected: (text) => setState(() => _text = text),
      itemBuilder: (_) => [
        for (final text in ReaderText.values)
          CheckedPopupMenuItem(
            key: ValueKey('parallels-text-${text.name}'),
            value: text,
            checked: text == _text,
            child: Text(_textLabel(text)),
          ),
      ],
    ),
    // The English alone has no interlinear.
    if (_text != ReaderText.english)
      IconButton(
        key: const ValueKey('parallels-interlinear'),
        isSelected: _interlinear,
        icon: const Icon(Icons.subtitles_off_outlined),
        selectedIcon: const Icon(Icons.subtitles),
        tooltip: _interlinear ? 'Hide interlinear' : 'Show interlinear',
        onPressed: () => setState(() {
          _interlinear = !_interlinear;
          // An interlinear with no layer would be the bare text.
          if (_interlinear && !_glosses && !_morphology) _glosses = true;
        }),
      ),
    if (_anyNewTestament)
      IconButton(
        key: const ValueKey('parallels-nt-text'),
        tooltip: _ntGreek
            ? 'Greek · switch to Aramaic'
            : 'Aramaic · switch to Greek',
        icon: SizedBox.square(
          dimension: 24,
          child: Center(
            child: Text(
              _ntGreek ? 'α' : (_ntSyriac ? 'ܐ' : 'א'),
              style: const TextStyle(
                fontFamily: 'Cardo',
                fontFamilyFallback: ['Noto Serif Hebrew'],
                fontSize: 20,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        onPressed: () => setState(() => _ntGreek = !_ntGreek),
      ),
    if (_phone)
      IconButton(
        key: const ValueKey('parallels-landscape'),
        isSelected: _landscape,
        icon: const Icon(Icons.screen_rotation_outlined),
        selectedIcon: const Icon(Icons.screen_lock_landscape),
        tooltip: _landscape ? 'Allow portrait' : 'Turn to landscape',
        onPressed: () => _setLandscape(!_landscape),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = Text(
      _accounts.length == 1 ? '1 account' : '${_accounts.length} accounts',
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, overflow: TextOverflow.ellipsis),
        subtitle,
      ],
    );
    final width = _text == ReaderText.parallel
        ? _parallelColumnWidth
        : _columnWidth;
    Widget account(int i, ThematicTarget p) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(theme, i, p),
        Expanded(child: _verses(theme, i, p)),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= width * _accounts.length) {
          return Scaffold(
            appBar: AppBar(title: title, actions: _actions()),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, p) in _accounts.indexed) ...[
                  if (i > 0) const VerticalDivider(width: 1),
                  Expanded(child: account(i, p)),
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
              actions: _actions(),
              bottom: TabBar(
                isScrollable: _accounts.length > 3,
                tabs: [
                  for (final (i, p) in _accounts.indexed)
                    Tab(key: ValueKey('parallels-tab-$i'), text: _book(p)),
                ],
              ),
            ),
            body: TabBarView(
              children: [for (final (i, p) in _accounts.indexed) account(i, p)],
            ),
          ),
        );
      },
    );
  }
}
