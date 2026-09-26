import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart' show OccurrenceVerseRow, VerseModeIcon;

/// The strength filter's settings: the minimum score each keeps, and its name.
/// The database holds a deliberately loose set, echoes and allusions
/// included, so how strict to be is the reader's choice.
const crossReferenceStrengths = <(double, String)>[
  (0, 'All'),
  (kLikelyCrossReference, 'Likely'),
  (kStrongCrossReference, 'Strong'),
];

/// Score cut-offs on the build's scale, set where the known quotations fall:
/// of the 37 the build finds, 27 score at least [kStrongCrossReference] (the
/// top ~550 of ~60k links) and 31 at least [kLikelyCrossReference] (top ~5k).
const kLikelyCrossReference = 10.0;
const kStrongCrossReference = 13.0;

/// How strongly a quotation's words line up, in words a reader can use.
String crossReferenceStrength(double score) {
  if (score >= kStrongCrossReference) return 'Strong match';
  if (score >= kLikelyCrossReference) return 'Likely match';
  return 'Possible echo';
}

String _words(int n) => n == 1 ? '1 word' : '$n words';

/// The header buttons both views share: the Hebrew / English verse switch, as
/// in the word sheet's occurrence lists, and a docked panel's close button.
List<Widget> _headerActions({
  required bool englishOnly,
  required VoidCallback onToggleEnglishOnly,
  VoidCallback? onClose,
}) => [
  IconButton(
    tooltip: englishOnly
        ? 'Show Hebrew verse text'
        : 'Show English-only verse text',
    icon: VerseModeIcon(englishOnly: englishOnly),
    onPressed: onToggleEnglishOnly,
  ),
  if (onClose != null)
    IconButton(
      tooltip: 'Close cross references',
      icon: const Icon(Icons.close),
      onPressed: onClose,
    ),
];

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
    this.target,
    this.targetRequest = 0,
    required this.useEnglishBookNames,
    this.onClose,
    this.minScore = 0,
    this.onMinScoreChanged,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendQuotationsRequest,
    this.sendVerseTextsRequest,
  });

  /// 1-based book number and chapter the overview shows. Docked beside the
  /// reader these follow its position, and the overview follows them with
  /// its filters kept.
  final int book;
  final int chapter;

  /// A verse (1-based book) whose links to open: at once, and again whenever
  /// [targetRequest] changes — so asking for the same verse twice reopens it.
  final ({int book, int chapter, int verse})? target;
  final int targetRequest;
  final bool useEnglishBookNames;

  /// Closes a docked panel; shown as a close button when given.
  final VoidCallback? onClose;

  /// The strength filter the panel opens with (one of
  /// [crossReferenceStrengths]), and where a change to it is reported — the
  /// reader shares it with its verse markers.
  final double minScore;
  final ValueChanged<double>? onMinScoreChanged;

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
  int book,
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
  late double _minScore = widget.minScore;

  /// Verse text as Hebrew, or as the English reader glosses: the same setting
  /// as the word sheet's occurrence lists.
  bool _englishOnly = false;

  int _requestId = 0;
  bool _loading = true;
  int _total = 0;
  final List<QuotationEntry> _entries = [];
  double _overviewOffset = 0;

  int get _chapterCount => kBooks[widget.book - 1].chapters;

  @override
  void initState() {
    super.initState();
    _openTarget();
    occurrenceVerseEnglishOnlyEnabled().then((enabled) {
      if (mounted) setState(() => _englishOnly = enabled);
    });
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
  void didUpdateWidget(CrossReferencesPanel old) {
    super.didUpdateWidget(old);
    if (widget.targetRequest != old.targetRequest) _openTarget();
    // Docked, the panel follows the reader: a new book resets the chapter
    // range to the whole of it, and the overview is asked for again with the
    // other filters kept.
    final newBook = widget.book != old.book;
    if (newBook) {
      _firstChapter = 1;
      _lastChapter = _chapterCount;
    }
    if (newBook ||
        (widget.chapter != old.chapter &&
            _scope == CrossReferenceScope.chapter)) {
      _overviewOffset = 0;
      _requestOverview();
    }
  }

  void _openTarget() {
    final target = widget.target;
    if (target == null) return;
    _view = (
      book: target.book,
      chapter: target.chapter,
      verse: target.verse,
      focus: null,
    );
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
      minScore: _minScore,
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

  void _toggleEnglishOnly() {
    setState(() => _englishOnly = !_englishOnly);
    setOccurrenceVerseEnglishOnlyEnabled(_englishOnly);
  }

  String _ref(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view != null) {
      return _VerseLinks(
        key: ValueKey('${view.book}:${view.chapter}:${view.verse}'),
        cache: _verseTexts,
        book: view.book,
        chapter: view.chapter,
        verse: view.verse,
        focus: view.focus,
        minScore: _minScore,
        useEnglishBookNames: widget.useEnglishBookNames,
        englishOnly: _englishOnly,
        onToggleEnglishOnly: _toggleEnglishOnly,
        onBack: () => setState(() => _view = null),
        onClose: widget.onClose,
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
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cross references',
                      style: theme.textTheme.titleMedium,
                    ),
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
              ..._headerActions(
                englishOnly: _englishOnly,
                onToggleEnglishOnly: _toggleEnglishOnly,
                onClose: widget.onClose,
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
              SegmentedButton<double>(
                key: const ValueKey('strength'),
                showSelectedIcon: false,
                segments: [
                  for (final (score, label) in crossReferenceStrengths)
                    ButtonSegment(value: score, label: Text(label)),
                ],
                selected: {_minScore},
                onSelectionChanged: (s) {
                  _update(() => _minScore = s.single);
                  widget.onMinScoreChanged?.call(_minScore);
                },
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
        book: widget.book,
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
              englishOnly: _englishOnly,
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
    required this.minScore,
    required this.useEnglishBookNames,
    required this.englishOnly,
    required this.onToggleEnglishOnly,
    required this.onBack,
    this.onClose,
    this.onNavigateToPassage,
    this.sendRequest,
  });

  final VerseTextCache cache;
  final int book;
  final int chapter;
  final int verse;
  final ({int book, int chapter, int verse})? focus;

  /// Links below this are folded behind a "Show weaker links" button: all
  /// are fetched, so widening costs no round-trip.
  final double minScore;
  final bool useEnglishBookNames;
  final bool englishOnly;
  final VoidCallback onToggleEnglishOnly;
  final VoidCallback onBack;
  final VoidCallback? onClose;
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

  /// Whether the links below [_VerseLinks.minScore] are shown.
  bool _showWeaker = false;

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
        // A link opened from the overview is shown even when it is weaker.
        _showWeaker =
            _focused < reply.entries.length &&
            reply.entries[_focused].score < widget.minScore;
      });
    });
    final request = GetCrossReferences(
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
      // Every link, whatever the filter: the weaker ones are folded, not lost.
      minScore: 0,
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
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
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
              ..._headerActions(
                englishOnly: widget.englishOnly,
                onToggleEnglishOnly: widget.onToggleEnglishOnly,
                onClose: widget.onClose,
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
              englishOnly: widget.englishOnly,
              useEnglishBookNames: widget.useEnglishBookNames,
            ),
          ),
          const Divider(height: 17),
          Expanded(child: _entryList(context, entries)),
        ],
      ],
    );
  }

  /// The links as strong as the filter, then a button for the rest. Links
  /// arrive strongest first, so the ones shown are always a prefix.
  Widget _entryList(BuildContext context, List<CrossReferenceEntry> entries) {
    final strong = entries.where((e) => e.score >= widget.minScore).length;
    final shown = _showWeaker ? entries.length : strong;
    final weaker = entries.length - strong;
    final fold = !_showWeaker && weaker > 0;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: shown + (fold ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i < shown) return _entryRow(context, entries, i);
        return Column(
          children: [
            if (shown == 0)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('No links this strong.'),
              ),
            TextButton(
              onPressed: () => setState(() => _showWeaker = true),
              child: Text(
                weaker == 1
                    ? 'Show 1 weaker link'
                    : 'Show $weaker weaker links',
              ),
            ),
          ],
        );
      },
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
          englishOnly: widget.englishOnly,
          useEnglishBookNames: widget.useEnglishBookNames,
          onTap: navigate == null
              ? null
              : () => navigate(entry.book - 1, entry.chapter, entry.verse),
        ),
      ],
    );
  }
}
