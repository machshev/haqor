import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart' show OccurrenceVerseRow;

/// How strongly a quotation's words line up, in words a reader can use. The
/// cut-offs follow the build's score scale: its weakest stored matches sit at
/// 7, and nearly every link above 15 is a recognised quotation.
String crossReferenceStrength(double score) {
  if (score >= 15) return 'Strong match';
  if (score >= 10) return 'Likely match';
  return 'Possible echo';
}

String _words(int n) => n == 1 ? '1 word' : '$n words';

/// Which part of the book the overview lists.
enum CrossReferenceScope { chapter, book }

/// The quotations linking the OT and the NT, seen from where the reader is.
///
/// Two views share the panel. The overview lists every quotation touching the
/// current chapter — or the whole book, optionally narrowed to a chapter range —
/// grouped by verse. A verse's own view lists its links strongest first, with
/// the matched words highlighted on both sides; its back button returns to the
/// overview. Tapping a linked verse opens it in the reader.
class CrossReferencesPanel extends StatefulWidget {
  const CrossReferencesPanel({
    super.key,
    required this.book,
    required this.chapter,
    this.verse,
    required this.useEnglishBookNames,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendQuotationsRequest,
    this.sendVerseTextsRequest,
  });

  /// 1-based book number and chapter the overview starts on.
  final int book;
  final int chapter;

  /// Opens straight onto this verse's links when given.
  final int? verse;
  final bool useEnglishBookNames;

  /// Opens a linked verse: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Test seams: how requests reach Rust, which a widget test cannot load.
  final void Function(GetCrossReferences)? sendRequest;
  final void Function(GetQuotations)? sendQuotationsRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  @override
  State<CrossReferencesPanel> createState() => _CrossReferencesPanelState();
}

/// A verse whose links are shown, and the link to focus first.
typedef _VerseView = ({
  int chapter,
  int verse,
  ({int book, int chapter, int verse})? focus,
});

class _CrossReferencesPanelState extends State<CrossReferencesPanel> {
  static const _pageSize = 100;

  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  StreamSubscription<RustSignalPack<Quotations>>? _sub;

  _VerseView? _view;

  CrossReferenceScope _scope = CrossReferenceScope.chapter;
  late int _firstChapter = 1;
  late int _lastChapter = _chapterCount;
  bool _byReference = true;

  int _requestId = 0;
  bool _loading = true;
  int _total = 0;
  final List<QuotationEntry> _entries = [];
  double _overviewOffset = 0;

  int get _chapterCount => kBooks[widget.book - 1].chapters;

  @override
  void initState() {
    super.initState();
    if (widget.verse case final verse?) {
      _view = (chapter: widget.chapter, verse: verse, focus: null);
    }
    _sub = Quotations.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId || !mounted) return;
      setState(() {
        _loading = false;
        _total = reply.total;
        _entries.addAll(reply.entries);
      });
    });
    _requestOverview();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _verseTexts.dispose();
    super.dispose();
  }

  /// Ask for the first page of the overview, or with [more] the next one.
  void _requestOverview({bool more = false}) {
    if (!more) {
      _entries.clear();
      _total = 0;
    }
    _loading = true;
    final chapterScope = _scope == CrossReferenceScope.chapter;
    final request = GetQuotations(
      requestId: ++_requestId,
      book: widget.book,
      firstChapter: chapterScope ? widget.chapter : _firstChapter,
      lastChapter: chapterScope ? widget.chapter : _lastChapter,
      byReference: _byReference,
      limit: _pageSize,
      offset: _entries.length,
    );
    final send = widget.sendQuotationsRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  void _update(void Function() change) {
    setState(() {
      change();
      _overviewOffset = 0;
      _requestOverview();
    });
  }

  String _ref(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view != null) {
      return _VerseLinks(
        key: ValueKey('${view.chapter}:${view.verse}'),
        cache: _verseTexts,
        book: widget.book,
        chapter: view.chapter,
        verse: view.verse,
        focus: view.focus,
        useEnglishBookNames: widget.useEnglishBookNames,
        onBack: () => setState(() => _view = null),
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendRequest,
      );
    }
    return _overview(context);
  }

  Widget _overview(BuildContext context) {
    final theme = Theme.of(context);
    final fromNt = widget.book >= 40;
    final bookName = bookDisplayName(
      widget.book - 1,
      useEnglish: widget.useEnglishBookNames,
    );
    final chapters = [for (var c = 1; c <= _chapterCount; c++) c];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cross references', style: theme.textTheme.titleMedium),
              Text(
                fromNt
                    ? '$bookName quoting the OT'
                    : '$bookName quoted in the NT',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<CrossReferenceScope>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: CrossReferenceScope.chapter,
                    label: Text('Chapter ${widget.chapter}'),
                  ),
                  const ButtonSegment(
                    value: CrossReferenceScope.book,
                    label: Text('Book'),
                  ),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => _update(() => _scope = s.single),
              ),
              if (_scope == CrossReferenceScope.book)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Chapters '),
                    DropdownButton<int>(
                      key: const ValueKey('first-chapter'),
                      value: _firstChapter,
                      items: [
                        for (final c in chapters)
                          DropdownMenuItem(value: c, child: Text('$c')),
                      ],
                      onChanged: (c) => _update(() {
                        _firstChapter = c!;
                        if (_lastChapter < c) _lastChapter = c;
                      }),
                    ),
                    const Text(' – '),
                    DropdownButton<int>(
                      key: const ValueKey('last-chapter'),
                      value: _lastChapter,
                      items: [
                        for (final c in chapters)
                          DropdownMenuItem(value: c, child: Text('$c')),
                      ],
                      onChanged: (c) => _update(() {
                        _lastChapter = c!;
                        if (_firstChapter > c) _firstChapter = c;
                      }),
                    ),
                  ],
                ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: true, label: Text('In order')),
                  ButtonSegment(value: false, label: Text('Strongest')),
                ],
                selected: {_byReference},
                onSelectionChanged: (s) =>
                    _update(() => _byReference = s.single),
              ),
            ],
          ),
        ),
        if (!_loading || _entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              _total == 1 ? '1 quotation' : '$_total quotations',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: 13),
        Expanded(child: _overviewList(context)),
      ],
    );
  }

  Widget _overviewList(BuildContext context) {
    if (_entries.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('No quotations found here.'),
      );
    }
    final hasMore = _entries.length < _total;
    final controller = ScrollController(initialScrollOffset: _overviewOffset);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _overviewOffset = n.metrics.pixels;
        return false;
      },
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: _entries.length + (hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _entries.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () =>
                            setState(() => _requestOverview(more: true)),
                        child: const Text('Show more'),
                      ),
              ),
            );
          }
          final entry = _entries[i];
          final previous = i == 0 ? null : _entries[i - 1];
          final newVerse =
              previous == null ||
              previous.chapter != entry.chapter ||
              previous.verse != entry.verse;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (newVerse && _byReference) _verseHeading(context, entry),
              _overviewRow(context, entry),
            ],
          );
        },
      ),
    );
  }

  void _openVerse(QuotationEntry entry, {bool focusLink = true}) {
    setState(() {
      _view = (
        chapter: entry.chapter,
        verse: entry.verse,
        focus: focusLink
            ? (
                book: entry.otherBook,
                chapter: entry.otherChapter,
                verse: entry.otherVerse,
              )
            : null,
      );
    });
  }

  Widget _verseHeading(BuildContext context, QuotationEntry entry) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openVerse(entry, focusLink: false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _ref(widget.book, entry.chapter, entry.verse),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewRow(BuildContext context, QuotationEntry entry) {
    final theme = Theme.of(context);
    // Listed by strength the rows carry no verse heading, so each names its
    // own verse.
    final own = _byReference
        ? ''
        : '${_ref(widget.book, entry.chapter, entry.verse)} · ';
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openVerse(entry),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '$own${crossReferenceStrength(entry.score)} · '
                '${_words(entry.positions.length)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            OccurrenceVerseRow(
              cache: _verseTexts,
              displayRef: _ref(
                entry.otherBook,
                entry.otherChapter,
                entry.otherVerse,
              ),
              bookIndex: entry.otherBook - 1,
              chapter: entry.otherChapter,
              verse: entry.otherVerse,
              highlightWords: const [],
              positions: entry.otherPositions,
              englishOnly: false,
              useEnglishBookNames: widget.useEnglishBookNames,
              onTap: () => _openVerse(entry),
            ),
          ],
        ),
      ),
    );
  }
}

/// One verse's links, strongest first, with the matched words highlighted on
/// both sides. Choosing a link shows its words on the verse itself; tapping
/// the linked verse opens it in the reader.
class _VerseLinks extends StatefulWidget {
  const _VerseLinks({
    super.key,
    required this.cache,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.focus,
    required this.useEnglishBookNames,
    required this.onBack,
    this.onNavigateToPassage,
    this.sendRequest,
  });

  final VerseTextCache cache;
  final int book;
  final int chapter;
  final int verse;
  final ({int book, int chapter, int verse})? focus;
  final bool useEnglishBookNames;
  final VoidCallback onBack;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(GetCrossReferences)? sendRequest;

  @override
  State<_VerseLinks> createState() => _VerseLinksState();
}

class _VerseLinksState extends State<_VerseLinks> {
  StreamSubscription<RustSignalPack<CrossReferences>>? _sub;

  /// Null until the reply arrives.
  List<CrossReferenceEntry>? _entries;

  /// The linked verse whose matched words are shown on the source verse.
  int _focused = 0;

  bool get _fromNt => widget.book >= 40;

  @override
  void initState() {
    super.initState();
    _sub = CrossReferences.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.book != widget.book ||
          reply.chapter != widget.chapter ||
          reply.verse != widget.verse ||
          !mounted) {
        return;
      }
      final focus = widget.focus;
      final focused = focus == null
          ? 0
          : reply.entries.indexWhere(
              (e) =>
                  e.book == focus.book &&
                  e.chapter == focus.chapter &&
                  e.verse == focus.verse,
            );
      setState(() {
        _entries = reply.entries;
        _focused = focused < 0 ? 0 : focused;
      });
    });
    final request = GetCrossReferences(
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
    );
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _ref(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;
    final title = _fromNt ? 'Quotes from the OT' : 'Quoted in the NT';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'All cross references',
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    Text(
                      _ref(widget.book, widget.chapter, widget.verse),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (entries == null)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (entries.isEmpty)
          const Expanded(
            child: Center(child: Text('No quotations found for this verse.')),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: OccurrenceVerseRow(
              key: ValueKey('source-$_focused'),
              cache: widget.cache,
              displayRef: _ref(widget.book, widget.chapter, widget.verse),
              bookIndex: widget.book - 1,
              chapter: widget.chapter,
              verse: widget.verse,
              highlightWords: const [],
              positions: entries[_focused.clamp(0, entries.length - 1)]
                  .sourcePositions,
              isCurrent: true,
              englishOnly: false,
              useEnglishBookNames: widget.useEnglishBookNames,
            ),
          ),
          const Divider(height: 17),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _entryRow(context, entries, i),
            ),
          ),
        ],
      ],
    );
  }

  Widget _entryRow(
    BuildContext context,
    List<CrossReferenceEntry> entries,
    int i,
  ) {
    final theme = Theme.of(context);
    final entry = entries[i];
    final navigate = widget.onNavigateToPassage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _focused = i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Icon(
                  i == _focused ? Icons.link : Icons.link_outlined,
                  size: 14,
                  color: i == _focused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${crossReferenceStrength(entry.score)} · '
                    '${_words(entry.positions.length)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        OccurrenceVerseRow(
          cache: widget.cache,
          displayRef: _ref(entry.book, entry.chapter, entry.verse),
          bookIndex: entry.book - 1,
          chapter: entry.chapter,
          verse: entry.verse,
          highlightWords: const [],
          positions: entry.positions,
          englishOnly: false,
          useEnglishBookNames: widget.useEnglishBookNames,
          onTap: navigate == null
              ? null
              : () => navigate(entry.book - 1, entry.chapter, entry.verse),
        ),
      ],
    );
  }
}
