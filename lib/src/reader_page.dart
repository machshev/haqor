import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'bible_data.dart';
import 'bindings/bindings.dart';
import 'tutor/onboarding.dart';
import 'widgets/book_selector.dart';
import 'widgets/chapter_selector.dart';
import 'widgets/verse_row.dart';
import 'widgets/word_info_sheet.dart';

class _PassageRef {
  final int bookIndex;
  final int chapter;
  final int? verse;
  const _PassageRef({
    required this.bookIndex,
    required this.chapter,
    this.verse,
  });

  String toStorageString() =>
      verse != null ? '$bookIndex,$chapter,$verse' : '$bookIndex,$chapter';

  static _PassageRef? fromStorageString(String s) {
    final parts = s.split(',');
    if (parts.length < 2) return null;
    final b = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    if (b == null || c == null) return null;
    if (b < 0 || b >= kBooks.length) return null;
    if (c < 1 || c > kBooks[b].chapters) return null;
    final v = parts.length >= 3 ? int.tryParse(parts[2]) : null;
    return _PassageRef(bookIndex: b, chapter: c, verse: v);
  }
}

class _ReadingPlan {
  _ReadingPlan({required this.bookIndex, Set<int>? completedChapters})
    : completedChapters = completedChapters ?? {};

  final int bookIndex;
  final Set<int> completedChapters;

  int? get nextChapter {
    for (var chapter = 1; chapter <= kBooks[bookIndex].chapters; chapter++) {
      if (!completedChapters.contains(chapter)) return chapter;
    }
    return null;
  }

  String toStorageString() {
    final chapters = completedChapters.toList()..sort();
    return '$bookIndex|${chapters.join(',')}';
  }

  static _ReadingPlan? fromStorageString(String value) {
    final parts = value.split('|');
    if (parts.length != 2) return null;
    final bookIndex = int.tryParse(parts[0]);
    if (bookIndex == null || bookIndex < 0 || bookIndex >= kBooks.length) {
      return null;
    }
    final completedChapters = parts[1]
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .where(
          (chapter) => chapter >= 1 && chapter <= kBooks[bookIndex].chapters,
        )
        .toSet();
    return _ReadingPlan(
      bookIndex: bookIndex,
      completedChapters: completedChapters,
    );
  }
}

class _Section {
  final int bookIndex; // 0-based
  final int chapter; // 1-based
  List<VerseEntry> verses;
  final GlobalKey key;

  _Section({
    required this.bookIndex,
    required this.chapter,
    required this.verses,
  }) : key = GlobalKey();
}

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({super.key});

  @override
  State<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends State<BibleReaderPage> {
  static const _kBook = 'book';
  static const _kChapter = 'chapter';
  static const _kHistory = 'nav_history';
  static const _kHistoryIndex = 'nav_history_index';
  static const _kNtSyriac = 'nt_syriac';
  static const _kHebrewNumerals = 'hebrew_numerals';
  static const _kFontSize = 'font_size';
  static const _kFontFamily = 'font_family';
  static const _kShowCantillation = 'show_cantillation';
  static const _kGlossInterlinear = 'gloss_interlinear';
  static const _kHighlightProperNames = 'highlight_proper_names';
  static const _kReadingPlanBook = 'reading_plan_book';
  static const _kReadingPlanCompleted = 'reading_plan_completed';
  static const _kReadingPlans = 'reading_plans';

  static const _fontFamilies = ['Cardo', 'David Libre', 'Frank Ruhl Libre'];

  // Displayed in AppBar — tracks the chapter currently at the top of the viewport
  int _bookIndex = 0;
  int _chapter = 1;

  // Selected verse (across any section)
  int? _selectedBook;
  int? _selectedChapter;
  int? _selectedVerse;
  int? _pendingVerse;
  GlobalKey? _targetVerseKey;

  final List<_PassageRef> _history = [];
  int _historyIndex = -1;
  bool _navigatingHistory = false;

  bool get _canGoBack => _historyIndex > 0;
  bool get _canGoForward => _historyIndex < _history.length - 1;

  final List<_Section> _sections = [];
  final Set<(int, int)> _pendingFetches = {}; // (1-based book, chapter)
  bool _initialLoading = true;
  bool _loadingNext = false;
  bool _loadingPrev = false;

  bool _ntSyriac = false;
  bool _hebrewNumerals = true;
  double _fontSize = 20.0;
  String _fontFamily = 'Cardo';
  bool _showCantillation = true;
  bool _glossInterlinear = false;
  bool _highlightProperNames = false;
  List<_ReadingPlan> _readingPlans = [];

  _ReadingPlan? _planForChapter(int bookIndex, int chapter) {
    for (final plan in _readingPlans) {
      if (plan.bookIndex == bookIndex && plan.nextChapter == chapter) {
        return plan;
      }
    }
    return null;
  }

  StreamSubscription<RustSignalPack<ChapterText>>? _sub;
  StreamSubscription<RustSignalPack<LexiconEntryOverrideStatus>>?
  _lexiconOverrideSub;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _sub = ChapterText.rustSignalStream.listen((pack) {
      final msg = pack.message;
      final fetchKey = (msg.book, msg.chapter);
      if (!_pendingFetches.contains(fetchKey)) return;
      if (msg.syriac != _isSyriac(msg.book - 1)) return;
      _pendingFetches.remove(fetchKey);

      final bookIdx = msg.book - 1;
      // A successful in-app lexicon edit re-requests the loaded OT chapters so
      // their interlinear glosses update behind the word-info sheet. Preserve
      // the existing section/key to avoid disturbing the scroll position.
      final loadedIndex = _sections.indexWhere(
        (s) => s.bookIndex == bookIdx && s.chapter == msg.chapter,
      );
      if (loadedIndex >= 0) {
        setState(() => _sections[loadedIndex].verses = msg.verses);
        return;
      }
      final goesOnTop =
          _sections.isNotEmpty &&
          (bookIdx < _sections.first.bookIndex ||
              (bookIdx == _sections.first.bookIndex &&
                  msg.chapter < _sections.first.chapter));

      final section = _Section(
        bookIndex: bookIdx,
        chapter: msg.chapter,
        verses: msg.verses,
      );

      int? targetVerse;
      if (_pendingVerse != null &&
          bookIdx == _bookIndex &&
          msg.chapter == _chapter) {
        targetVerse = _pendingVerse;
        _selectedBook = bookIdx;
        _selectedChapter = msg.chapter;
        _selectedVerse = targetVerse;
        _targetVerseKey = GlobalKey();
        _pendingVerse = null;
      }

      if (goesOnTop) {
        _prependSection(section);
      } else {
        _appendSection(section);
      }

      if (targetVerse != null) {
        _scheduleScrollToVerse(section, targetVerse);
      }
    });
    _lexiconOverrideSub = LexiconEntryOverrideStatus.rustSignalStream.listen((
      pack,
    ) {
      if (mounted && pack.message.success) _refreshLoadedOtChapters();
    });
    _loadPrefs();
  }

  bool _isSyriac(int bookIndex) => bookIndex >= 39 && _ntSyriac;

  // Appends a section at the bottom; evicts the top section first if over limit.
  void _appendSection(_Section section) {
    if (_sections.length >= 3) {
      // Evict top section (content above viewport shrinks → compensate scroll).
      final oldOffset = _scrollController.hasClients
          ? _scrollController.offset
          : 0.0;
      final oldExtent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      setState(() {
        _sections.removeAt(0);
        _initialLoading = false;
        // Keep _loadingNext = true until the section actually lands.
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final removedHeight =
            oldExtent - _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          (oldOffset - removedHeight).clamp(
            0.0,
            _scrollController.position.maxScrollExtent,
          ),
        );
        setState(() {
          _sections.add(section);
          _loadingNext = false;
        });
      });
    } else {
      setState(() {
        _sections.add(section);
        _initialLoading = false;
        _loadingNext = false;
      });
    }
  }

  // Prepends a section at the top; evicts the bottom section first if over
  // limit (no scroll compensation needed for bottom eviction), then compensates
  // for the content inserted above the current viewport position.
  void _prependSection(_Section section) {
    if (_sections.length >= 3) {
      // Evict bottom first (scroll unaffected).
      // Keep _loadingPrev = true until _doPrepend adds the section.
      setState(() {
        _sections.removeLast();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _doPrepend(section);
      });
    } else {
      _doPrepend(section);
    }
  }

  void _doPrepend(_Section section) {
    final oldOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    setState(() {
      _sections.insert(0, section);
      _initialLoading = false;
      _loadingPrev = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final addedHeight =
          _scrollController.position.maxScrollExtent - oldExtent;
      _scrollController.jumpTo(
        (oldOffset + addedHeight).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bookIndex = (prefs.getInt(_kBook) ?? 0).clamp(0, kBooks.length - 1);
      _chapter = (prefs.getInt(_kChapter) ?? 1).clamp(
        1,
        kBooks[_bookIndex].chapters,
      );
      _ntSyriac = prefs.getBool(_kNtSyriac) ?? false;
      _hebrewNumerals = prefs.getBool(_kHebrewNumerals) ?? true;
      _fontSize = (prefs.getDouble(_kFontSize) ?? 20.0).clamp(16.0, 28.0);
      final savedFamily = prefs.getString(_kFontFamily) ?? 'Cardo';
      _fontFamily = _fontFamilies.contains(savedFamily) ? savedFamily : 'Cardo';
      _showCantillation = prefs.getBool(_kShowCantillation) ?? true;
      _glossInterlinear = prefs.getBool(_kGlossInterlinear) ?? false;
      _highlightProperNames = prefs.getBool(_kHighlightProperNames) ?? false;
      final savedPlans = prefs.getStringList(_kReadingPlans);
      if (savedPlans != null) {
        _readingPlans = savedPlans
            .map(_ReadingPlan.fromStorageString)
            .whereType<_ReadingPlan>()
            .toList();
      } else {
        final planBook = prefs.getInt(_kReadingPlanBook);
        if (planBook != null && planBook >= 0 && planBook < kBooks.length) {
          _readingPlans = [
            _ReadingPlan(
              bookIndex: planBook,
              completedChapters:
                  (prefs.getStringList(_kReadingPlanCompleted) ?? [])
                      .map(int.tryParse)
                      .whereType<int>()
                      .where(
                        (chapter) =>
                            chapter >= 1 &&
                            chapter <= kBooks[planBook].chapters,
                      )
                      .toSet(),
            ),
          ];
        }
      }
    });
    final rawHistory = prefs.getStringList(_kHistory) ?? [];
    final savedIndex = prefs.getInt(_kHistoryIndex) ?? -1;
    if (rawHistory.isNotEmpty &&
        savedIndex >= 0 &&
        savedIndex < rawHistory.length) {
      _history.clear();
      for (final s in rawHistory) {
        final ref = _PassageRef.fromStorageString(s);
        if (ref != null) _history.add(ref);
      }
      if (_history.isNotEmpty) {
        _historyIndex = savedIndex.clamp(0, _history.length - 1);
        final current = _history[_historyIndex];
        _bookIndex = current.bookIndex;
        _chapter = current.chapter;
        if (current.verse != null) {
          setState(() => _pendingVerse = current.verse);
        }
        _startAt(_bookIndex, _chapter);
        return;
      }
    }
    _history.clear();
    _history.add(_PassageRef(bookIndex: _bookIndex, chapter: _chapter));
    _historyIndex = 0;
    _startAt(_bookIndex, _chapter);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(
        _kHistory,
        _history.map((r) => r.toStorageString()).toList(),
      ),
      prefs.setInt(_kHistoryIndex, _historyIndex),
    ]);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_kBook, _bookIndex),
      prefs.setInt(_kChapter, _chapter),
      prefs.setBool(_kNtSyriac, _ntSyriac),
      prefs.setBool(_kHebrewNumerals, _hebrewNumerals),
      prefs.setDouble(_kFontSize, _fontSize),
      prefs.setString(_kFontFamily, _fontFamily),
      prefs.setBool(_kShowCantillation, _showCantillation),
      prefs.setBool(_kGlossInterlinear, _glossInterlinear),
      prefs.setBool(_kHighlightProperNames, _highlightProperNames),
    ]);
  }

  Future<void> _saveReadingPlan() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(
        _kReadingPlans,
        _readingPlans.map((plan) => plan.toStorageString()).toList(),
      ),
      prefs.remove(_kReadingPlanBook),
      prefs.remove(_kReadingPlanCompleted),
    ]);
  }

  void _applyReadingSettings(AppReadingSettings settings) {
    final reloadChapter = settings.ntSyriac != _ntSyriac && _bookIndex >= 39;
    setState(() {
      _ntSyriac = settings.ntSyriac;
      _hebrewNumerals = settings.hebrewNumerals;
      _showCantillation = settings.showCantillation;
      _glossInterlinear = settings.glossInterlinear;
      _highlightProperNames = settings.highlightProperNames;
      _fontSize = settings.fontSize;
      _fontFamily = settings.fontFamily;
    });
    if (reloadChapter) {
      _startAt(_bookIndex, _chapter);
    } else {
      _savePrefs();
    }
  }

  void _showAppSettings() => showAppSettings(
    context,
    readingSettings: AppReadingSettings(
      ntSyriac: _ntSyriac,
      hebrewNumerals: _hebrewNumerals,
      showCantillation: _showCantillation,
      glossInterlinear: _glossInterlinear,
      highlightProperNames: _highlightProperNames,
      fontSize: _fontSize,
      fontFamily: _fontFamily,
    ),
    onReadingSettingsChanged: _applyReadingSettings,
  );

  Future<void> _showReadingPlan() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => _ReadingPlanSheet(
        plans: _readingPlans,
        onChooseBook: () {
          Navigator.pop(ctx);
          _choosePlanBook();
        },
        onOpenNext: (plan) {
          Navigator.pop(ctx);
          final chapter = plan.nextChapter;
          if (chapter != null) _navigateTo(plan.bookIndex, chapter);
        },
        onClear: (plan) {
          Navigator.pop(ctx);
          setState(() => _readingPlans.remove(plan));
          _saveReadingPlan();
        },
      ),
    );
  }

  Future<void> _choosePlanBook() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => BookSelectorSheet(currentIndex: _bookIndex),
    );
    if (result == null) return;
    if (_readingPlans.any((plan) => plan.bookIndex == result)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${kBooks[result].transliteration} is already in your plan.',
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _readingPlans.add(_ReadingPlan(bookIndex: result));
    });
    _saveReadingPlan();
  }

  void _completePlanChapter(_ReadingPlan plan) {
    final chapter = plan.nextChapter;
    if (chapter == null) return;
    setState(() => plan.completedChapters.add(chapter));
    _saveReadingPlan();
    final nextChapter = plan.nextChapter;
    if (nextChapter != null) {
      _navigateTo(plan.bookIndex, nextChapter);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${kBooks[plan.bookIndex].transliteration} complete!'),
        ),
      );
    }
  }

  void _navigateTo(int bookIndex, int chapter, {int? verse}) {
    if (!_navigatingHistory) {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(
        _PassageRef(bookIndex: bookIndex, chapter: chapter, verse: verse),
      );
      if (_history.length > 10) _history.removeAt(0);
      _historyIndex = _history.length - 1;
    }
    if (verse != null) setState(() => _pendingVerse = verse);
    _startAt(bookIndex, chapter);
    _saveHistory();
  }

  void _goBack() {
    if (!_canGoBack) return;
    _historyIndex--;
    final ref = _history[_historyIndex];
    _navigatingHistory = true;
    _navigateTo(ref.bookIndex, ref.chapter, verse: ref.verse);
    _navigatingHistory = false;
  }

  void _goForward() {
    if (!_canGoForward) return;
    _historyIndex++;
    final ref = _history[_historyIndex];
    _navigatingHistory = true;
    _navigateTo(ref.bookIndex, ref.chapter, verse: ref.verse);
    _navigatingHistory = false;
  }

  void _startAt(int bookIndex, int chapter) {
    setState(() {
      _sections.clear();
      _pendingFetches.clear();
      _bookIndex = bookIndex;
      _chapter = chapter;
      _initialLoading = true;
      _loadingNext = false;
      _loadingPrev = false;
      _selectedBook = null;
      _selectedChapter = null;
      _selectedVerse = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _savePrefs();
    _fetchChapter(bookIndex, chapter);
  }

  void _fetchChapter(int bookIndex, int chapter) {
    final key = (bookIndex + 1, chapter);
    if (_pendingFetches.contains(key)) return;
    if (_sections.any(
      (s) => s.bookIndex == bookIndex && s.chapter == chapter,
    )) {
      return;
    }
    _pendingFetches.add(key);
    GetChapter(
      book: bookIndex + 1,
      chapter: chapter,
      syriac: _isSyriac(bookIndex),
    ).sendSignalToRust();
  }

  void _refreshLoadedOtChapters() {
    for (final section in List<_Section>.of(_sections)) {
      if (section.bookIndex >= 39) continue;
      final key = (section.bookIndex + 1, section.chapter);
      if (!_pendingFetches.add(key)) continue;
      GetChapter(
        book: section.bookIndex + 1,
        chapter: section.chapter,
        syriac: false,
      ).sendSignalToRust();
    }
  }

  void _scheduleScrollToVerse(_Section section, int verse) {
    final verseIdx = section.verses.indexWhere((v) => v.verse == verse);
    if (verseIdx <= 0) {
      // First verse is already at the top after navigation; nothing to do.
      _targetVerseKey = null;
      return;
    }
    _attemptScrollToVerse(section, verseIdx, retriesLeft: 3);
  }

  void _attemptScrollToVerse(
    _Section section,
    int verseIdx, {
    required int retriesLeft,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _targetVerseKey?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        _targetVerseKey = null;
        return;
      }
      if (retriesLeft <= 0) {
        _targetVerseKey = null;
        return;
      }
      // Verse not yet built; jump proportionally based on current maxScrollExtent
      // (Flutter extrapolates this from laid-out items, so it improves each retry).
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        if (maxExtent > 0) {
          final ratio = verseIdx / section.verses.length;
          _scrollController.jumpTo((ratio * maxExtent).clamp(0.0, maxExtent));
        }
      }
      _attemptScrollToVerse(section, verseIdx, retriesLeft: retriesLeft - 1);
    });
  }

  void _onScroll() {
    _updateCurrentChapter();
    if (!_scrollController.hasClients || _sections.isEmpty) return;
    final pixels = _scrollController.position.pixels;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (!_loadingPrev && pixels <= 800) {
      _maybeLoadPrev();
    }
    if (!_loadingNext && pixels >= maxExtent - 800) {
      _maybeLoadNext();
    }
  }

  void _maybeLoadNext() {
    if (_sections.isEmpty) return;
    final last = _sections.last;
    var nextBook = last.bookIndex;
    var nextChapter = last.chapter + 1;
    if (nextChapter > kBooks[nextBook].chapters) {
      nextBook++;
      nextChapter = 1;
    }
    if (nextBook >= kBooks.length) return;
    setState(() => _loadingNext = true);
    _fetchChapter(nextBook, nextChapter);
  }

  void _maybeLoadPrev() {
    if (_sections.isEmpty) return;
    final first = _sections.first;
    var prevBook = first.bookIndex;
    var prevChapter = first.chapter - 1;
    if (prevChapter < 1) {
      prevBook--;
      if (prevBook < 0) return; // already at Genesis 1
      prevChapter = kBooks[prevBook].chapters;
    }
    setState(() => _loadingPrev = true);
    _fetchChapter(prevBook, prevChapter);
  }

  void _updateCurrentChapter() {
    if (!mounted || _sections.isEmpty) return;
    final appBarBottom = kToolbarHeight + MediaQuery.of(context).padding.top;
    for (int i = _sections.length - 1; i >= 0; i--) {
      final ctx = _sections[i].key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= appBarBottom + 8) {
        final b = _sections[i].bookIndex;
        final c = _sections[i].chapter;
        if (_bookIndex != b || _chapter != c) {
          setState(() {
            _bookIndex = b;
            _chapter = c;
          });
          _savePrefs();
        }
        return;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _sub?.cancel();
    _lexiconOverrideSub?.cancel();
    super.dispose();
  }

  Future<void> _showBookSelector() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => BookSelectorSheet(currentIndex: _bookIndex),
    );
    if (result == null || result == _bookIndex) return;
    int newChapter = 1;
    if (kBooks[result].chapters > 1) {
      if (!mounted) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (ctx) =>
            ChapterSelectorSheet(total: kBooks[result].chapters, current: 1),
      );
      newChapter = picked ?? 1;
    }
    _navigateTo(result, newChapter);
  }

  Future<void> _selectChapter() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => ChapterSelectorSheet(
        total: kBooks[_bookIndex].chapters,
        current: _chapter,
      ),
    );
    if (result != null && result != _chapter) {
      _navigateTo(_bookIndex, result);
    }
  }

  void _showWordInfo(
    String word,
    int bookIndex,
    int chapter,
    int verse, {
    String? readerGloss,
  }) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordInfoSheet(
        word: word,
        syriac: bookIndex >= 39,
        readerGloss: readerGloss,
        reportContext: {
          'bookIndex': bookIndex,
          'book': kBooks[bookIndex].transliteration,
          'chapter': chapter,
          'verse': verse,
        },
        onNavigateToPassage: (bi, chapter, verse) {
          Navigator.pop(ctx);
          _navigateTo(bi, chapter, verse: verse);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = kBooks[_bookIndex];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: _showBookSelector,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.hebrew,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cardo',
                        fontFamilyFallback: ['Noto Serif Hebrew'],
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      book.transliteration,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _selectChapter,
              child: Chip(
                label: Text(
                  '$_chapter',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: theme.colorScheme.primaryContainer,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBack ? _goBack : null,
            tooltip: 'Back',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward ? _goForward : null,
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined),
            tooltip: 'Reading plan',
            onPressed: _showReadingPlan,
          ),
          IconButton(
            icon: const Icon(Icons.school_outlined),
            tooltip: 'Tutor',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TutorEntryPage())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _showAppSettings,
          ),
        ],
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : _sections.isEmpty
          ? const Center(child: Text('No text found'))
          : _buildScrollView(),
    );
  }

  Widget _completePlanChapterControl(int bookIndex, int chapter) {
    final plan = _planForChapter(bookIndex, chapter);
    if (plan == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Center(
        child: FilledButton.icon(
          onPressed: () => _completePlanChapter(plan),
          icon: const Icon(Icons.check),
          label: Text('Complete chapter $chapter'),
        ),
      ),
    );
  }

  Widget _buildScrollView() {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (_loadingPrev)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        for (int i = 0; i < _sections.length; i++) ...[
          if (i > 0)
            SliverToBoxAdapter(
              child: _completePlanChapterControl(
                _sections[i - 1].bookIndex,
                _sections[i - 1].chapter,
              ),
            ),
          SliverToBoxAdapter(
            child: i == 0
                ? SizedBox(key: _sections[0].key)
                : _ChapterDivider(
                    key: _sections[i].key,
                    bookIndex: _sections[i].bookIndex,
                    chapter: _sections[i].chapter,
                  ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: _sections[i].verses.length,
              itemBuilder: (context, j) {
                final section = _sections[i];
                final entry = section.verses[j];
                final isSelected =
                    entry.verse == _selectedVerse &&
                    section.bookIndex == _selectedBook &&
                    section.chapter == _selectedChapter;
                return VerseRow(
                  key: isSelected ? _targetVerseKey : null,
                  entry: entry,
                  isSelected: isSelected,
                  hebrewNumerals: _hebrewNumerals,
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selectedBook = null;
                      _selectedChapter = null;
                      _selectedVerse = null;
                    } else {
                      _selectedBook = section.bookIndex;
                      _selectedChapter = section.chapter;
                      _selectedVerse = entry.verse;
                    }
                  }),
                  onWordTap: (word, readerGloss) => _showWordInfo(
                    word,
                    section.bookIndex,
                    section.chapter,
                    entry.verse,
                    readerGloss: readerGloss,
                  ),
                  fontSize: _fontSize,
                  fontFamily: _fontFamily,
                  showCantillation: _showCantillation,
                  glossInterlinear: _glossInterlinear,
                  highlightProperNames: _highlightProperNames,
                );
              },
            ),
          ),
        ],
        if (_loadingNext)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 88 + bottomPadding)),
      ],
    );
  }
}

class _ReadingPlanSheet extends StatelessWidget {
  const _ReadingPlanSheet({
    required this.plans,
    required this.onChooseBook,
    required this.onOpenNext,
    required this.onClear,
  });

  final List<_ReadingPlan> plans;
  final VoidCallback onChooseBook;
  final ValueChanged<_ReadingPlan> onOpenNext;
  final ValueChanged<_ReadingPlan> onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Passage reading plan', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            if (plans.isEmpty)
              Text(
                'Add a book to start a reading plan.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final plan in plans)
                _PlanProgressRow(
                  plan: plan,
                  onOpenNext: () => onOpenNext(plan),
                  onClear: () => onClear(plan),
                ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onChooseBook,
              icon: const Icon(Icons.add),
              label: const Text('Add book'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanProgressRow extends StatelessWidget {
  const _PlanProgressRow({
    required this.plan,
    required this.onOpenNext,
    required this.onClear,
  });

  final _ReadingPlan plan;
  final VoidCallback onOpenNext;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final book = kBooks[plan.bookIndex];
    final nextChapter = plan.nextChapter;
    final progress = plan.completedChapters.length / book.chapters;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.transliteration,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text(
                  '${plan.completedChapters.length}/${book.chapters} chapters',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove plan',
          ),
          IconButton(
            onPressed: nextChapter == null ? null : onOpenNext,
            icon: const Icon(Icons.play_arrow),
            tooltip: nextChapter == null
                ? 'Plan complete'
                : 'Open chapter $nextChapter',
          ),
        ],
      ),
    );
  }
}

class _ChapterDivider extends StatelessWidget {
  final int bookIndex;
  final int chapter;

  const _ChapterDivider({
    super.key,
    required this.bookIndex,
    required this.chapter,
  });

  @override
  Widget build(BuildContext context) {
    final book = kBooks[bookIndex];
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Text(
                  book.hebrew,
                  style: TextStyle(
                    fontFamily: 'Cardo',
                    fontFamilyFallback: const ['Noto Serif Hebrew'],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '${book.transliteration} $chapter',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
