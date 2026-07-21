import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'bible_data.dart';
import 'bindings/bindings.dart';
import 'issue_reporting.dart';
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
  _ReadingPlan({required this.bookIndex, Map<int, DateTime?>? completed})
    : _completed = completed ?? {};

  final int bookIndex;

  /// Completed chapter -> completion time. Null timestamps come from entries
  /// saved before completion times were recorded.
  final Map<int, DateTime?> _completed;

  int get completedCount => _completed.length;

  bool isCompleted(int chapter) => _completed.containsKey(chapter);

  int? get nextChapter {
    for (var chapter = 1; chapter <= kBooks[bookIndex].chapters; chapter++) {
      if (!_completed.containsKey(chapter)) return chapter;
    }
    return null;
  }

  void completeChapter(int chapter) => _completed[chapter] = DateTime.now();

  /// Rewrites progress so [chapter] becomes the next chapter to read;
  /// `kBooks[bookIndex].chapters + 1` marks the whole book read. Completion
  /// times of chapters that stay completed are preserved.
  void setNextChapter(int chapter) {
    final kept = <int, DateTime?>{
      for (var c = 1; c < chapter; c++) c: _completed[c],
    };
    _completed
      ..clear()
      ..addAll(kept);
  }

  /// Completion times of all timestamped chapters, oldest first.
  List<DateTime> get completionTimes =>
      _completed.values.whereType<DateTime>().toList()..sort();

  String toStorageString() {
    final chapters = _completed.keys.toList()..sort();
    final entries = chapters.map((chapter) {
      final time = _completed[chapter];
      return time == null
          ? '$chapter'
          : '$chapter@${time.millisecondsSinceEpoch}';
    });
    return '$bookIndex|${entries.join(',')}';
  }

  static _ReadingPlan? fromStorageString(String value) {
    final parts = value.split('|');
    if (parts.length != 2) return null;
    final bookIndex = int.tryParse(parts[0]);
    if (bookIndex == null || bookIndex < 0 || bookIndex >= kBooks.length) {
      return null;
    }
    final completed = <int, DateTime?>{};
    for (final entry in parts[1].split(',')) {
      final pieces = entry.split('@');
      final chapter = int.tryParse(pieces[0]);
      if (chapter == null ||
          chapter < 1 ||
          chapter > kBooks[bookIndex].chapters) {
        continue;
      }
      final millis = pieces.length == 2 ? int.tryParse(pieces[1]) : null;
      completed[chapter] = millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return _ReadingPlan(bookIndex: bookIndex, completed: completed);
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

typedef _ChapterRequest = (int, int, bool, bool, bool);

enum _ReaderMenuAction { readingPlan, tutor, reportIssue, settings }

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({super.key, this.sendChapterRequest});

  /// Test seam: how a [GetChapter] request reaches the Rust side. Defaults to
  /// the real rinf signal; widget tests substitute a stub that answers via
  /// `assignRustSignal['ChapterText']`.
  final void Function(GetChapter request)? sendChapterRequest;

  @override
  State<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends State<BibleReaderPage> {
  static const _kBook = 'book';
  static const _kChapter = 'chapter';
  static const _kHistory = 'nav_history';
  static const _kHistoryIndex = 'nav_history_index';
  static const _kNtSyriac = 'nt_syriac';
  static const _kEnglishBookNames = 'english_book_names';
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

  // Gates the generic issue-report menu item, matching the word-info sheet's
  // admin-only flag button.
  bool _adminMode = false;

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

  static const _chapterCacheLimit = 6;

  // Loaded chapters in reading order. The scroll view is anchored on a
  // zero-height `center` sliver placed just before _sections[_centerIndex]:
  // chapters inserted above the center occupy negative scroll offsets, so
  // prepending (and trimming the far ends) never moves on-screen content.
  // No scroll-offset corrections exist anywhere in this page.
  static const _chapterWindow = 8;
  final List<_Section> _sections = [];
  int _centerIndex = 0;
  final Key _centerKey = const ValueKey('reader-center');
  // (1-based book, chapter, Syriac, include glosses, include name flags)
  final Set<_ChapterRequest> _pendingFetches = {};
  final Set<_ChapterRequest> _prefetches = {};
  final Map<_ChapterRequest, Timer> _fetchTimeouts = {};
  final LinkedHashMap<_ChapterRequest, List<VerseEntry>> _chapterCache =
      LinkedHashMap();
  bool _initialLoading = true;
  bool _loadingNext = false;
  bool _loadingPrev = false;

  bool _ntSyriac = false;
  bool _englishBookNames = false;
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
      final fetchKey = (
        msg.book,
        msg.chapter,
        msg.syriac,
        msg.includeGlosses,
        msg.includeNames,
      );
      if (!_pendingFetches.contains(fetchKey)) return;
      _pendingFetches.remove(fetchKey);
      _fetchTimeouts.remove(fetchKey)?.cancel();
      _cacheChapter(fetchKey, msg.verses);
      if (_prefetches.remove(fetchKey)) return;

      _acceptChapter(msg.book - 1, msg.chapter, msg.verses);
    });
    _lexiconOverrideSub = LexiconEntryOverrideStatus.rustSignalStream.listen((
      pack,
    ) {
      if (mounted && pack.message.success) _refreshLoadedOtChapters();
    });
    _loadPrefs();
    _loadAdminMode();
  }

  Future<void> _loadAdminMode() async {
    final enabled = await adminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  void _acceptChapter(int bookIdx, int chapter, List<VerseEntry> verses) {
    // A successful in-app lexicon edit re-requests the loaded OT chapters so
    // their interlinear glosses update behind the word-info sheet. Preserve
    // the existing section/key to avoid disturbing the scroll position.
    final loadedIndex = _sections.indexWhere(
      (s) => s.bookIndex == bookIdx && s.chapter == chapter,
    );
    if (loadedIndex >= 0) {
      setState(() => _sections[loadedIndex].verses = verses);
      return;
    }

    final section = _Section(
      bookIndex: bookIdx,
      chapter: chapter,
      verses: verses,
    );

    if (_sections.isEmpty) {
      int? targetVerse;
      if (_pendingVerse != null &&
          bookIdx == _bookIndex &&
          chapter == _chapter) {
        targetVerse = _pendingVerse;
        _selectedBook = bookIdx;
        _selectedChapter = chapter;
        _selectedVerse = targetVerse;
        _targetVerseKey = GlobalKey();
        _pendingVerse = null;
      }
      setState(() {
        _sections.add(section);
        _centerIndex = 0;
        _initialLoading = false;
        _loadingPrev = false;
        _loadingNext = false;
      });
      _prefetchAdjacentChapters(bookIdx, chapter);
      if (targetVerse != null) _scheduleScrollToVerse(section, targetVerse);
      _scheduleEdgeCheck();
      return;
    }

    final first = _sections.first;
    final last = _sections.last;
    final prev = _previousChapterBefore(first.bookIndex, first.chapter);
    final next = _nextChapterAfter(last.bookIndex, last.chapter);
    if (prev != null && bookIdx == prev.$1 && chapter == prev.$2) {
      setState(() {
        _sections.insert(0, section);
        _centerIndex++;
        _loadingPrev = false;
        _trimTail();
      });
    } else if (next != null && bookIdx == next.$1 && chapter == next.$2) {
      setState(() {
        _sections.add(section);
        _loadingNext = false;
        _trimHead();
      });
    } else {
      // Stale response — e.g. delivered after the window moved elsewhere.
      setState(() {
        _loadingPrev = false;
        _loadingNext = false;
      });
      return;
    }
    _prefetchAdjacentChapters(bookIdx, chapter);
    _scheduleEdgeCheck();
  }

  // A fresh window starts with pixels == minScrollExtent, where clamping
  // physics swallow upward drags without emitting scroll events, so relying
  // on _onScroll alone would leave the reader unable to scroll up. Re-run the
  // edge triggers once the new window has been laid out; this settles after
  // at most one chapter per side because each accept pushes the extents past
  // the trigger distance.
  void _scheduleEdgeCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  bool _isSyriac(int bookIndex) => bookIndex >= 39 && _ntSyriac;

  int? _currentSectionIndex() {
    final idx = _sections.indexWhere(
      (s) => s.bookIndex == _bookIndex && s.chapter == _chapter,
    );
    return idx >= 0 ? idx : null;
  }

  // Trimming is only ever allowed at the far ends, on the side the reader is
  // moving away from, and never at or past the center section. Both rules
  // together guarantee that dropping a section changes only the scroll
  // extents, never the position of laid-out content. Sections between the
  // center and the viewport are intentionally kept: they are cheap (lazy
  // slivers plus verse data) and removing them would require the scroll
  // corrections this design exists to avoid.
  void _trimHead() {
    var currentIdx = _currentSectionIndex();
    if (currentIdx == null) return;
    while (_sections.length > _chapterWindow &&
        _centerIndex > 0 &&
        currentIdx! >= 3) {
      _sections.removeAt(0);
      _centerIndex--;
      currentIdx--;
    }
  }

  void _trimTail() {
    final currentIdx = _currentSectionIndex();
    if (currentIdx == null) return;
    while (_sections.length > _chapterWindow &&
        _sections.length - 1 > _centerIndex &&
        _sections.length - 1 - currentIdx >= 3) {
      _sections.removeLast();
    }
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
      _englishBookNames = prefs.getBool(_kEnglishBookNames) ?? false;
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
              completed: {
                for (final chapter
                    in (prefs.getStringList(_kReadingPlanCompleted) ?? [])
                        .map(int.tryParse)
                        .whereType<int>()
                        .where(
                          (chapter) =>
                              chapter >= 1 &&
                              chapter <= kBooks[planBook].chapters,
                        ))
                  chapter: null,
              },
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
      prefs.setBool(_kEnglishBookNames, _englishBookNames),
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
    final reloadChapter =
        (settings.ntSyriac != _ntSyriac && _bookIndex >= 39) ||
        settings.glossInterlinear != _glossInterlinear ||
        settings.highlightProperNames != _highlightProperNames;
    setState(() {
      _ntSyriac = settings.ntSyriac;
      _englishBookNames = settings.englishBookNames;
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

  Future<void> _showAppSettings() async {
    await showAppSettings(
      context,
      readingSettings: AppReadingSettings(
        ntSyriac: _ntSyriac,
        englishBookNames: _englishBookNames,
        hebrewNumerals: _hebrewNumerals,
        showCantillation: _showCantillation,
        glossInterlinear: _glossInterlinear,
        highlightProperNames: _highlightProperNames,
        fontSize: _fontSize,
        fontFamily: _fontFamily,
      ),
      onReadingSettingsChanged: _applyReadingSettings,
    );
    // Admin mode can be toggled inside the settings sheet; it gates the
    // issue-report menu item.
    _loadAdminMode();
  }

  /// Generic issue entry, not tied to a specific word or card — reachable from
  /// the reader menu so an idea can be logged from anywhere in the app.
  void _reportGeneralIssue() => showIssueReportDialog(
    context,
    source: 'general',
    contextData: {
      'reader': {
        'bookIndex': _bookIndex,
        'book': kBooks[_bookIndex].transliteration,
        'chapter': _chapter,
      },
    },
  );

  Future<void> _showReadingPlan() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => _ReadingPlanSheet(
          plans: _readingPlans,
          useEnglishBookNames: _englishBookNames,
          onChooseBook: () {
            Navigator.pop(ctx);
            _choosePlanBook();
          },
          onOpenNext: (plan) {
            Navigator.pop(ctx);
            final chapter = plan.nextChapter;
            if (chapter != null) _navigateTo(plan.bookIndex, chapter);
          },
          onEdit: (plan) async {
            final position = await _choosePlanPosition(ctx, plan);
            if (position == null) return;
            setState(() => plan.setNextChapter(position));
            setSheetState(() {});
            _saveReadingPlan();
          },
          onClear: (plan) async {
            final confirmed = await _confirmRemovePlan(ctx, plan);
            if (confirmed != true) return;
            setState(() => _readingPlans.remove(plan));
            setSheetState(() {});
            _saveReadingPlan();
          },
        ),
      ),
    );
  }

  Future<bool?> _confirmRemovePlan(BuildContext ctx, _ReadingPlan plan) {
    final book = kBooks[plan.bookIndex];
    return showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'Remove ${bookDisplayName(plan.bookIndex, useEnglish: _englishBookNames)}?',
        ),
        content: Text(
          'Your progress (${plan.completedCount} of ${book.chapters} '
          'chapters) will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  /// Lets the user pick the plan's position: returns the chapter to read
  /// next (1-based), `book.chapters + 1` for "mark all read", or null if
  /// cancelled.
  Future<int?> _choosePlanPosition(BuildContext ctx, _ReadingPlan plan) {
    final book = kBooks[plan.bookIndex];
    return showDialog<int>(
      context: ctx,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        return AlertDialog(
          title: Text(
            bookDisplayName(plan.bookIndex, useEnglish: _englishBookNames),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tap the chapter you want to read next. Earlier chapters '
                    'are marked as read.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var chapter = 1; chapter <= book.chapters; chapter++)
                        _PlanChapterChip(
                          chapter: chapter,
                          isNext: plan.nextChapter == chapter,
                          isCompleted: plan.isCompleted(chapter),
                          onTap: () => Navigator.pop(dialogCtx, chapter),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, book.chapters + 1),
              child: const Text('Mark all read'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _choosePlanBook() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => BookSelectorSheet(
        currentIndex: _bookIndex,
        useEnglishBookNames: _englishBookNames,
      ),
    );
    if (result == null) return;
    if (_readingPlans.any((plan) => plan.bookIndex == result)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${bookDisplayName(result, useEnglish: _englishBookNames)} '
              'is already in your plan.',
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
    setState(() => plan.completeChapter(chapter));
    _saveReadingPlan();
    final nextChapter = plan.nextChapter;
    if (nextChapter != null) {
      _navigateTo(plan.bookIndex, nextChapter);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${bookDisplayName(plan.bookIndex, useEnglish: _englishBookNames)} '
            'complete!',
          ),
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
      _prefetches.clear();
      for (final timeout in _fetchTimeouts.values) {
        timeout.cancel();
      }
      _fetchTimeouts.clear();
      _centerIndex = 0;
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

  _ChapterRequest _chapterRequest(int bookIndex, int chapter) => (
    bookIndex + 1,
    chapter,
    _isSyriac(bookIndex),
    _glossInterlinear,
    _highlightProperNames,
  );

  void _cacheChapter(_ChapterRequest key, List<VerseEntry> verses) {
    _chapterCache.remove(key);
    _chapterCache[key] = List<VerseEntry>.of(verses);
    while (_chapterCache.length > _chapterCacheLimit) {
      _chapterCache.remove(_chapterCache.keys.first);
    }
  }

  List<VerseEntry>? _cachedChapter(_ChapterRequest key) {
    final verses = _chapterCache.remove(key);
    if (verses != null) _chapterCache[key] = verses;
    return verses;
  }

  void _dropCachedChapter(int bookIndex, int chapter) {
    _chapterCache.removeWhere(
      (key, _) => key.$1 == bookIndex + 1 && key.$2 == chapter,
    );
  }

  void _fetchChapter(
    int bookIndex,
    int chapter, {
    bool prefetch = false,
    bool force = false,
  }) {
    final key = _chapterRequest(bookIndex, chapter);
    if (_pendingFetches.contains(key)) {
      if (!prefetch) _prefetches.remove(key);
      return;
    }
    if (!force &&
        _sections.any(
          (s) => s.bookIndex == bookIndex && s.chapter == chapter,
        )) {
      return;
    }
    final cached = _cachedChapter(key);
    if (cached != null) {
      if (!prefetch) _acceptChapter(bookIndex, chapter, cached);
      return;
    }
    _pendingFetches.add(key);
    if (prefetch) _prefetches.add(key);
    _fetchTimeouts[key] = Timer(const Duration(seconds: 10), () {
      _fetchTimeouts.remove(key);
      if (!_pendingFetches.remove(key)) return;
      final wasPrefetch = _prefetches.remove(key);
      if (!mounted || wasPrefetch) return;
      setState(() {
        _initialLoading = false;
        _loadingPrev = false;
        _loadingNext = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not load this chapter.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _fetchChapter(bookIndex, chapter),
          ),
        ),
      );
    });
    final request = GetChapter(
      book: bookIndex + 1,
      chapter: chapter,
      syriac: _isSyriac(bookIndex),
      includeGlosses: _glossInterlinear,
      includeNames: _highlightProperNames,
    );
    final send = widget.sendChapterRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  void _refreshLoadedOtChapters() {
    for (final section in List<_Section>.of(_sections)) {
      if (section.bookIndex >= 39) continue;
      _dropCachedChapter(section.bookIndex, section.chapter);
      _fetchChapter(section.bookIndex, section.chapter, force: true);
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
    final position = _scrollController.position;
    final triggerDistance = math.max(800.0, position.viewportDimension * 2);
    // Content above the center sliver lives at negative offsets, so the top
    // trigger is relative to minScrollExtent rather than zero.
    if (!_loadingPrev &&
        position.pixels <= position.minScrollExtent + triggerDistance) {
      _maybeLoadPrev();
    }
    if (!_loadingNext &&
        position.pixels >= position.maxScrollExtent - triggerDistance) {
      _maybeLoadNext();
    }
  }

  (int, int)? _nextChapterAfter(int bookIndex, int chapter) {
    var nextBook = bookIndex;
    var nextChapter = chapter + 1;
    if (nextChapter > kBooks[nextBook].chapters) {
      nextBook++;
      nextChapter = 1;
    }
    return nextBook < kBooks.length ? (nextBook, nextChapter) : null;
  }

  (int, int)? _previousChapterBefore(int bookIndex, int chapter) {
    var previousBook = bookIndex;
    var previousChapter = chapter - 1;
    if (previousChapter < 1) {
      previousBook--;
      if (previousBook < 0) return null;
      previousChapter = kBooks[previousBook].chapters;
    }
    return (previousBook, previousChapter);
  }

  void _prefetchAdjacentChapters(int bookIndex, int chapter) {
    final previous = _previousChapterBefore(bookIndex, chapter);
    if (previous != null) {
      _fetchChapter(previous.$1, previous.$2, prefetch: true);
    }
    final next = _nextChapterAfter(bookIndex, chapter);
    if (next != null) _fetchChapter(next.$1, next.$2, prefetch: true);
  }

  void _maybeLoadNext() {
    if (_sections.isEmpty) return;
    final last = _sections.last;
    final next = _nextChapterAfter(last.bookIndex, last.chapter);
    if (next == null) return;
    setState(() => _loadingNext = true);
    _fetchChapter(next.$1, next.$2);
  }

  void _maybeLoadPrev() {
    if (_sections.isEmpty) return;
    final first = _sections.first;
    final previous = _previousChapterBefore(first.bookIndex, first.chapter);
    if (previous == null) return;
    setState(() => _loadingPrev = true);
    _fetchChapter(previous.$1, previous.$2);
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
    for (final timeout in _fetchTimeouts.values) {
      timeout.cancel();
    }
    super.dispose();
  }

  Future<void> _showBookSelector() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => BookSelectorSheet(
        currentIndex: _bookIndex,
        useEnglishBookNames: _englishBookNames,
      ),
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
                      bookDisplayName(
                        _bookIndex,
                        useEnglish: _englishBookNames,
                      ),
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
          PopupMenuButton<_ReaderMenuAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More reader options',
            onSelected: (action) {
              switch (action) {
                case _ReaderMenuAction.readingPlan:
                  _showReadingPlan();
                case _ReaderMenuAction.tutor:
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TutorEntryPage()),
                  );
                case _ReaderMenuAction.reportIssue:
                  _reportGeneralIssue();
                case _ReaderMenuAction.settings:
                  _showAppSettings();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _ReaderMenuAction.readingPlan,
                child: ListTile(
                  leading: Icon(Icons.auto_stories_outlined),
                  title: Text('Reading plan'),
                ),
              ),
              const PopupMenuItem(
                value: _ReaderMenuAction.tutor,
                child: ListTile(
                  leading: Icon(Icons.school_outlined),
                  title: Text('Tutor'),
                ),
              ),
              if (_adminMode)
                const PopupMenuItem(
                  value: _ReaderMenuAction.reportIssue,
                  child: ListTile(
                    leading: Icon(Icons.flag_outlined),
                    title: Text('Report an issue'),
                  ),
                ),
              const PopupMenuItem(
                value: _ReaderMenuAction.settings,
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : _sections.isEmpty
          ? const Center(child: Text('No text found'))
          : Stack(
              children: [
                _buildScrollView(),
                if (_loadingPrev)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(child: LinearProgressIndicator()),
                  ),
                if (_loadingNext)
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(child: LinearProgressIndicator()),
                  ),
              ],
            ),
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
      // Anchoring on a zero-height center sliver lets sections above it grow
      // into negative scroll offsets: prepending a chapter extends
      // minScrollExtent instead of shifting the content the reader is looking
      // at, so no scroll-offset correction is ever needed.
      center: _centerKey,
      slivers: [
        for (int i = 0; i < _sections.length; i++) ...[
          if (i == _centerIndex)
            SliverToBoxAdapter(key: _centerKey, child: const SizedBox.shrink()),
          ..._sectionSlivers(_sections[i]),
        ],
        SliverToBoxAdapter(
          key: const ValueKey('reader-bottom-pad'),
          child: SizedBox(height: 88 + bottomPadding),
        ),
      ],
    );
  }

  List<Widget> _sectionSlivers(_Section section) {
    final b = section.bookIndex;
    final c = section.chapter;
    return [
      SliverToBoxAdapter(
        key: ValueKey('divider-$b-$c'),
        child: _ChapterDivider(
          key: section.key,
          bookIndex: b,
          chapter: c,
          useEnglishBookNames: _englishBookNames,
        ),
      ),
      SliverPadding(
        key: ValueKey('verses-$b-$c'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: section.verses.length,
          itemBuilder: (context, j) {
            final entry = section.verses[j];
            final isSelected =
                entry.verse == _selectedVerse &&
                b == _selectedBook &&
                c == _selectedChapter;
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
                  _selectedBook = b;
                  _selectedChapter = c;
                  _selectedVerse = entry.verse;
                }
              }),
              onWordTap: (word, readerGloss) => _showWordInfo(
                word,
                b,
                c,
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
      SliverToBoxAdapter(
        key: ValueKey('plan-$b-$c'),
        child: _completePlanChapterControl(b, c),
      ),
    ];
  }
}

class _ReadingPlanSheet extends StatelessWidget {
  const _ReadingPlanSheet({
    required this.plans,
    required this.useEnglishBookNames,
    required this.onChooseBook,
    required this.onOpenNext,
    required this.onEdit,
    required this.onClear,
  });

  final List<_ReadingPlan> plans;
  final bool useEnglishBookNames;
  final VoidCallback onChooseBook;
  final ValueChanged<_ReadingPlan> onOpenNext;
  final ValueChanged<_ReadingPlan> onEdit;
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
                  useEnglishBookNames: useEnglishBookNames,
                  onOpenNext: () => onOpenNext(plan),
                  onEdit: () => onEdit(plan),
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
    required this.useEnglishBookNames,
    required this.onOpenNext,
    required this.onEdit,
    required this.onClear,
  });

  final _ReadingPlan plan;
  final bool useEnglishBookNames;
  final VoidCallback onOpenNext;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  String _relativeDate(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final year = time.year == now.year ? '' : ' ${time.year}';
    return '${time.day} ${months[time.month - 1]}$year';
  }

  /// Rough finish estimate from the pace between the first and last
  /// timestamped chapter completions; null when there is no usable pace.
  String? _estimate(int remaining) {
    if (remaining <= 0) return null;
    final times = plan.completionTimes;
    if (times.length < 2) return null;
    final spanDays = times.last.difference(times.first).inMinutes / (60 * 24);
    if (spanDays <= 0) return null;
    final perDay = (times.length - 1) / spanDays;
    final daysLeft = (remaining / perDay).ceil();
    if (daysLeft > 999) return null;
    return daysLeft == 1 ? '~1 day left' : '~$daysLeft days left';
  }

  @override
  Widget build(BuildContext context) {
    final book = kBooks[plan.bookIndex];
    final nextChapter = plan.nextChapter;
    final progress = plan.completedCount / book.chapters;
    final remaining = book.chapters - plan.completedCount;
    final lastRead = plan.completionTimes.lastOrNull;
    final stats = [
      if (nextChapter == null) 'Complete' else 'Next: chapter $nextChapter',
      if (lastRead != null) 'read ${_relativeDate(lastRead)}',
      ?_estimate(remaining),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookDisplayName(
                    plan.bookIndex,
                    useEnglish: useEnglishBookNames,
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text(
                  '${plan.completedCount}/${book.chapters} chapters',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  stats,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit position',
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

class _PlanChapterChip extends StatelessWidget {
  const _PlanChapterChip({
    required this.chapter,
    required this.isNext,
    required this.isCompleted,
    required this.onTap,
  });

  final int chapter;
  final bool isNext;
  final bool isCompleted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = isNext
        ? scheme.primary
        : isCompleted
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = isNext
        ? scheme.onPrimary
        : isCompleted
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$chapter', style: TextStyle(color: foreground)),
      ),
    );
  }
}

class _ChapterDivider extends StatelessWidget {
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;

  const _ChapterDivider({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.useEnglishBookNames,
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
                  '${bookDisplayName(bookIndex, useEnglish: useEnglishBookNames)} '
                  '$chapter',
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
