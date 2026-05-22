import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import 'bible_data.dart';
import 'bindings/bindings.dart';
import 'widgets/book_selector.dart';
import 'widgets/chapter_selector.dart';
import 'widgets/verse_row.dart';
import 'widgets/word_info_sheet.dart';

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({super.key});

  @override
  State<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends State<BibleReaderPage> {
  // book index is 0-based in kBooks, but the DB uses 1-based book numbers
  int _bookIndex = 0;
  int _chapter = 1; // 1-based
  int? _selectedVerse; // 1-based verse number
  List<VerseEntry> _verses = [];
  bool _loading = true;
  // NT corpus: false = Hebrew (transliteration), true = Syriac (Peshitta)
  bool _ntSyriac = false;
  bool _hebrewNumerals = true;

  StreamSubscription<RustSignalPack<ChapterText>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ChapterText.rustSignalStream.listen((pack) {
      if (pack.message.book == _bookIndex + 1 &&
          pack.message.chapter == _chapter &&
          pack.message.syriac == _activeSyriac) {
        setState(() {
          _verses = pack.message.verses;
          _loading = false;
        });
      }
    });
    _loadChapter();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // Only NT books (index >= 39) can use Syriac
  bool get _activeSyriac => _bookIndex >= 39 && _ntSyriac;

  void _loadChapter() {
    setState(() {
      _loading = true;
      _selectedVerse = null;
      _verses = [];
    });
    GetChapter(
      book: _bookIndex + 1,
      chapter: _chapter,
      syriac: _activeSyriac,
    ).sendSignalToRust();
  }

  void _prevChapter() {
    if (_chapter > 1) {
      setState(() => _chapter--);
      _loadChapter();
    } else if (_bookIndex > 0) {
      setState(() {
        _bookIndex--;
        _chapter = kBooks[_bookIndex].chapters;
      });
      _loadChapter();
    }
  }

  void _nextChapter() {
    if (_chapter < kBooks[_bookIndex].chapters) {
      setState(() => _chapter++);
      _loadChapter();
    } else if (_bookIndex < kBooks.length - 1) {
      setState(() {
        _bookIndex++;
        _chapter = 1;
      });
      _loadChapter();
    }
  }

  bool get _hasPrev => _bookIndex > 0 || _chapter > 1;
  bool get _hasNext =>
      _bookIndex < kBooks.length - 1 ||
      _chapter < kBooks[_bookIndex].chapters;

  Future<void> _showBookSelector() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => BookSelectorSheet(currentIndex: _bookIndex),
    );
    if (result != null && result != _bookIndex) {
      setState(() {
        _bookIndex = result;
        _chapter = 1;
      });
      _loadChapter();
    }
  }

  Future<void> _showChapterSelector() async {
    final total = kBooks[_bookIndex].chapters;
    final result = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => ChapterSelectorSheet(
        total: total,
        current: _chapter,
      ),
    );
    if (result != null && result != _chapter) {
      setState(() => _chapter = result);
      _loadChapter();
    }
  }

  void _showWordInfo(String word) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordInfoSheet(word: word),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = kBooks[_bookIndex];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _showBookSelector,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    book.hebrew,
                    style: const TextStyle(
                      fontFamily: 'Cardo',
                      fontFamilyFallback: ['Noto Serif Hebrew'],
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    book.transliteration,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showChapterSelector,
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          tooltip: 'Previous chapter',
          onPressed: _hasPrev ? _prevChapter : null,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            tooltip: 'Next chapter',
            onPressed: _hasNext ? _nextChapter : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Settings',
            onSelected: (value) {
              if (value == 'hebrew' || value == 'syriac') {
                final useSyriac = value == 'syriac';
                if (useSyriac != _ntSyriac) {
                  setState(() => _ntSyriac = useSyriac);
                  if (_bookIndex >= 39) _loadChapter();
                }
              } else if (value == 'numeral_hebrew' || value == 'numeral_english') {
                setState(() => _hebrewNumerals = value == 'numeral_hebrew');
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
              const PopupMenuItem(
                enabled: false,
                child: Text('Verse Numbers'),
              ),
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
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _verses.isEmpty
              ? const Center(child: Text('No text found'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _verses.length,
                  itemBuilder: (context, i) {
                    final entry = _verses[i];
                    final isSelected = entry.verse == _selectedVerse;
                    return VerseRow(
                      entry: entry,
                      isSelected: isSelected,
                      hebrewNumerals: _hebrewNumerals,
                      onTap: () => setState(() {
                        _selectedVerse = isSelected ? null : entry.verse;
                      }),
                      onWordTap: (word) => _showWordInfo(word),
                    );
                  },
                ),
    );
  }
}
