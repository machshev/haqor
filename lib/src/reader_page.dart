import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _Section {
  final int bookIndex; // 0-based
  final int chapter; // 1-based
  final List<VerseEntry> verses;
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

  StreamSubscription<RustSignalPack<ChapterText>>? _sub;
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
      // Ignore stale duplicate responses for chapters already loaded.
      if (_sections.any(
        (s) => s.bookIndex == bookIdx && s.chapter == msg.chapter,
      )) {
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
    ]);
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

  void _showWordInfo(String word, int bookIndex) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordInfoSheet(
        word: word,
        syriac: bookIndex >= 39,
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
            icon: const Icon(Icons.school_outlined),
            tooltip: 'Tutor',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const TutorEntryPage())),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Settings',
            onSelected: (value) {
              if (value == 'hebrew' || value == 'syriac') {
                final useSyriac = value == 'syriac';
                if (useSyriac != _ntSyriac) {
                  setState(() => _ntSyriac = useSyriac);
                  if (_bookIndex >= 39) {
                    _startAt(_bookIndex, _chapter);
                  } else {
                    _savePrefs();
                  }
                }
              } else if (value == 'numeral_hebrew' ||
                  value == 'numeral_english') {
                setState(() => _hebrewNumerals = value == 'numeral_hebrew');
                _savePrefs();
              } else if (value.startsWith('size_')) {
                final size = double.tryParse(value.substring(5));
                if (size != null) {
                  setState(() => _fontSize = size);
                  _savePrefs();
                }
              } else if (value.startsWith('font_')) {
                setState(() => _fontFamily = value.substring(5));
                _savePrefs();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                enabled: false,
                child: Text('NT Text Source'),
              ),
              CheckedPopupMenuItem(
                value: 'hebrew',
                checked: !_ntSyriac,
                child: const Text('Hebrew (Peshitta)'),
              ),
              CheckedPopupMenuItem(
                value: 'syriac',
                checked: _ntSyriac,
                child: const Text('Syriac (Peshitta)'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Verse Numbers')),
              CheckedPopupMenuItem(
                value: 'numeral_hebrew',
                checked: _hebrewNumerals,
                child: const Text('Hebrew (א׳ ב׳ ג׳)'),
              ),
              CheckedPopupMenuItem(
                value: 'numeral_english',
                checked: !_hebrewNumerals,
                child: const Text('English (1 2 3)'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Font Size')),
              CheckedPopupMenuItem(
                value: 'size_16.0',
                checked: _fontSize == 16.0,
                child: const Text('Small'),
              ),
              CheckedPopupMenuItem(
                value: 'size_20.0',
                checked: _fontSize == 20.0,
                child: const Text('Medium'),
              ),
              CheckedPopupMenuItem(
                value: 'size_24.0',
                checked: _fontSize == 24.0,
                child: const Text('Large'),
              ),
              CheckedPopupMenuItem(
                value: 'size_28.0',
                checked: _fontSize == 28.0,
                child: const Text('Extra Large'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(enabled: false, child: Text('Font')),
              CheckedPopupMenuItem(
                value: 'font_Cardo',
                checked: _fontFamily == 'Cardo',
                child: const Text('Cardo'),
              ),
              CheckedPopupMenuItem(
                value: 'font_David Libre',
                checked: _fontFamily == 'David Libre',
                child: const Text('David Libre'),
              ),
              CheckedPopupMenuItem(
                value: 'font_Frank Ruhl Libre',
                checked: _fontFamily == 'Frank Ruhl Libre',
                child: const Text('Frank Ruhl Libre'),
              ),
            ],
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
                  onWordTap: (word) => _showWordInfo(word, section.bookIndex),
                  fontSize: _fontSize,
                  fontFamily: _fontFamily,
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
        SliverToBoxAdapter(child: SizedBox(height: 8 + bottomPadding)),
      ],
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
