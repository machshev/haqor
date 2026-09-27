import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
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
/// top ~550 of ~60k OT/NT links) and 31 at least [kLikelyCrossReference] (top
/// ~5k). Links within one testament are scaled onto the same scale.
const kLikelyCrossReference = 10.0;
const kStrongCrossReference = 13.0;

/// How strongly a quotation's words line up, in words a reader can use.
String crossReferenceStrength(double score) {
  if (score >= kStrongCrossReference) return 'Strong match';
  if (score >= kLikelyCrossReference) return 'Likely match';
  return 'Possible echo';
}

String _words(int n) => n == 1 ? '1 word' : '$n words';

/// `Parallel · ` for a link between two verses of one testament (1-based
/// books), naming what kind of link it is; nothing for an OT/NT quotation.
String _parallel(int book, int otherBook) =>
    (book >= 40) == (otherBook >= 40) ? 'Parallel · ' : '';

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

/// Which links the overview lists, by the testaments of their two verses. The
/// index is the [GetQuotations.scope] code.
enum CrossReferenceLinks { all, otherTestament, sameTestament }

/// The cross references of where the reader is: quotations linking the OT and
/// the NT, and parallels within one testament (parallel accounts, repeated
/// oracles, synoptic parallels).
///
/// Two views share the panel. The overview lists every quotation touching the
/// current chapter — or the whole book, optionally narrowed to a chapter range —
/// grouped by verse. A verse's own view lists its links strongest first, with
/// the matched words highlighted on both sides, and beside them the verse's
/// thematic references: the passages the Treasury of Scripture Knowledge
/// links to each of its key phrases. Its back button returns to the overview.
/// Tapping a linked verse opens it in the reader.
class CrossReferencesPanel extends StatefulWidget {
  const CrossReferencesPanel({
    super.key,
    required this.book,
    required this.chapter,
    this.target,
    this.targetRequest = 0,
    required this.useEnglishBookNames,
    this.onClose,
    this.isLinkBookmarked,
    this.onToggleLinkBookmark,
    this.minScore = 0,
    this.onMinScoreChanged,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendQuotationsRequest,
    this.sendThematicReferencesRequest,
    this.sendThematicOverviewRequest,
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

  /// Whether a link is bookmarked in the active study, and how to bookmark or
  /// unbookmark it (true when it ends up bookmarked). Without them the links
  /// carry no bookmark button.
  final bool Function(StudyLinkVerse earlier, StudyLinkVerse later)?
  isLinkBookmarked;
  final Future<bool> Function(StudyLink link)? onToggleLinkBookmark;

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
  final void Function(GetThematicReferences)? sendThematicReferencesRequest;
  final void Function(GetThematicOverview)? sendThematicOverviewRequest;
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

  /// Verses per page of the thematic overview: a verse has a dozen targets on
  /// average.
  static const _thematicPageSize = 40;

  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  StreamSubscription<RustSignalPack<Quotations>>? _sub;
  StreamSubscription<RustSignalPack<ThematicOverview>>? _thematicSub;

  _VerseView? _view;

  /// The list picked — quotations or thematic references — shared by the
  /// overview and a verse's view. Null until the reader picks one: a verse
  /// then picks for itself, and the overview shows quotations.
  _Section? _section;
  _Section get _overviewSection => _section ?? _Section.links;

  /// The list the overview last asked for.
  _Section? _overviewLoaded;

  CrossReferenceScope _scope = CrossReferenceScope.chapter;
  CrossReferenceLinks _links = CrossReferenceLinks.all;
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

  /// The thematic overview's verses so far, and how many there are in all.
  final List<ThematicVerseEntry> _thematicVerses = [];
  int _thematicTotal = 0;
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
    _thematicSub = ThematicOverview.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId || !mounted) return;
      setState(() {
        _loading = false;
        _thematicTotal = reply.total;
        _thematicVerses.addAll(reply.verses);
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
    _thematicSub?.cancel();
    _verseTexts.dispose();
    super.dispose();
  }

  /// Ask for the first page of the overview, or with [more] the next one.
  void _requestOverview({bool more = false}) {
    if (!more) {
      _entries.clear();
      _total = 0;
      _thematicVerses.clear();
      _thematicTotal = 0;
    }
    _loading = true;
    _overviewLoaded = _overviewSection;
    final chapterScope = _scope == CrossReferenceScope.chapter;
    if (_overviewSection == _Section.thematic) {
      final request = GetThematicOverview(
        requestId: ++_requestId,
        book: widget.book,
        firstChapter: chapterScope ? widget.chapter : _firstChapter,
        lastChapter: chapterScope ? widget.chapter : _lastChapter,
        limit: _thematicPageSize,
        offset: _thematicVerses.length,
      );
      final send = widget.sendThematicOverviewRequest;
      if (send != null) {
        send(request);
      } else {
        request.sendSignalToRust();
      }
      return;
    }
    final request = GetQuotations(
      requestId: ++_requestId,
      book: widget.book,
      firstChapter: chapterScope ? widget.chapter : _firstChapter,
      lastChapter: chapterScope ? widget.chapter : _lastChapter,
      byReference: _byReference,
      minScore: _minScore,
      scope: _links.index,
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
        chosenSection: _section,
        onSectionChanged: (section) => _section = section,
        onBack: () => setState(() {
          _view = null;
          // The overview follows the list the verse was left on.
          if (_overviewSection != _overviewLoaded) {
            _overviewOffset = 0;
            _requestOverview();
          }
        }),
        onClose: widget.onClose,
        isLinkBookmarked: widget.isLinkBookmarked,
        onToggleLinkBookmark: widget.onToggleLinkBookmark,
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendRequest,
        sendThematicRequest: widget.sendThematicReferencesRequest,
      );
    }
    return _overview(context);
  }

  Widget _overview(BuildContext context) {
    final theme = Theme.of(context);
    final fromNt = widget.book >= 40;
    final testament = fromNt ? 'NT' : 'OT';
    final bookName = bookDisplayName(
      widget.book - 1,
      useEnglish: widget.useEnglishBookNames,
    );
    final chapters = [for (var c = 1; c <= _chapterCount; c++) c];
    final thematic = _overviewSection == _Section.thematic;
    final count = thematic
        ? (_thematicTotal == 1 ? '1 verse' : '$_thematicTotal verses')
        : (_total == 1 ? '1 link' : '$_total links');
    final loaded = thematic ? _thematicVerses.isNotEmpty : _entries.isNotEmpty;
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
                      thematic
                          ? 'Thematic references in $bookName'
                          : switch (_links) {
                              CrossReferenceLinks.all =>
                                'Quotations and parallels in $bookName',
                              CrossReferenceLinks.otherTestament =>
                                fromNt
                                    ? '$bookName quoting the OT'
                                    : '$bookName quoted in the NT',
                              CrossReferenceLinks.sameTestament =>
                                '$bookName and the rest of the $testament',
                            },
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
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: _sectionSwitch(
            selected: _overviewSection,
            onSelected: (section) => _update(() => _section = section),
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
              // How links are found, ordered and filtered: nothing a
              // thematic reference has.
              if (!thematic) ...[
                SegmentedButton<CrossReferenceLinks>(
                  key: const ValueKey('links'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                      value: CrossReferenceLinks.all,
                      label: Text('All links'),
                    ),
                    const ButtonSegment(
                      value: CrossReferenceLinks.otherTestament,
                      label: Text('OT ↔ NT'),
                    ),
                    ButtonSegment(
                      value: CrossReferenceLinks.sameTestament,
                      label: Text('Within $testament'),
                    ),
                  ],
                  selected: {_links},
                  onSelectionChanged: (s) => _update(() => _links = s.single),
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
            ],
          ),
        ),
        if (!_loading || loaded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              count,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        const Divider(height: 13),
        Expanded(
          child: thematic
              ? _thematicOverviewList(context)
              : _overviewList(context),
        ),
      ],
    );
  }

  /// A "Show more" button, or a spinner while the next page is coming.
  Widget _showMore() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: _loading
          ? const CircularProgressIndicator()
          : OutlinedButton(
              onPressed: () => setState(() => _requestOverview(more: true)),
              child: const Text('Show more'),
            ),
    ),
  );

  /// The thematic references of the chapter or book, verse by verse, the way
  /// a wide-margin Bible prints them: each key phrase and the passages it
  /// points to, compactly. A verse's heading opens its own view, with the
  /// target verses' text; a reference opens that passage in the reader.
  Widget _thematicOverviewList(BuildContext context) {
    if (_thematicVerses.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('No thematic references here.'),
      );
    }
    final hasMore = _thematicVerses.length < _thematicTotal;
    final controller = ScrollController(initialScrollOffset: _overviewOffset);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _overviewOffset = n.metrics.pixels;
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('thematic-overview'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: _thematicVerses.length + (hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == _thematicVerses.length) return _showMore();
          final verse = _thematicVerses[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _verseHeadingFor(
                context,
                chapter: verse.chapter,
                verse: verse.verse,
              ),
              for (final entry in verse.entries)
                _ThematicMarginEntry(
                  entry: entry,
                  label: _targetLabel,
                  onOpen: widget.onNavigateToPassage,
                ),
            ],
          );
        },
      ),
    );
  }

  /// A target's reference, shortened within the book the panel shows.
  String _targetLabel(ThematicTarget t) {
    final start = t.book == widget.book
        ? '${t.chapter}:${t.verse}'
        : _ref(t.book, t.chapter, t.verse);
    if (t.lastChapter == t.chapter && t.lastVerse == t.verse) return start;
    if (t.lastChapter == t.chapter) return '$start–${t.lastVerse}';
    return '$start–${t.lastChapter}:${t.lastVerse}';
  }

  Widget _overviewList(BuildContext context) {
    if (_entries.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('No cross references found here.'),
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
          if (i == _entries.length) return _showMore();
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

  Widget _verseHeading(BuildContext context, QuotationEntry entry) =>
      _verseHeadingFor(context, chapter: entry.chapter, verse: entry.verse);

  /// A verse of the book the panel shows, opening its own view.
  Widget _verseHeadingFor(
    BuildContext context, {
    required int chapter,
    required int verse,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => setState(
        () => _view = (
          book: widget.book,
          chapter: chapter,
          verse: verse,
          focus: null,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _ref(widget.book, chapter, verse),
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$own${_parallel(widget.book, entry.otherBook)}'
                      '${crossReferenceStrength(entry.score)} · '
                      '${_words(entry.positions.length)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (widget.isLinkBookmarked case final isBookmarked?)
                    if (widget.onToggleLinkBookmark case final onToggle?)
                      _LinkBookmarkButton(
                        link: _studyLink(
                          ownBook: widget.book,
                          ownChapter: entry.chapter,
                          ownVerse: entry.verse,
                          ownPositions: entry.positions,
                          otherBook: entry.otherBook,
                          otherChapter: entry.otherChapter,
                          otherVerse: entry.otherVerse,
                          otherPositions: entry.otherPositions,
                          score: entry.score,
                        ),
                        isBookmarked: isBookmarked,
                        onToggle: onToggle,
                      ),
                ],
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

/// The two lists the panel shows, for a verse or a chapter.
enum _Section {
  /// Quotations and parallels found by aligning roots.
  links,

  /// The Treasury of Scripture Knowledge's references for its key phrases.
  thematic,
}

/// The Quotations | Thematic switch, for the overview and a verse alike; a
/// verse's view gives its counts.
Widget _sectionSwitch({
  required _Section selected,
  required ValueChanged<_Section> onSelected,
  int? links,
  int? thematic,
}) => SegmentedButton<_Section>(
  key: const ValueKey('section'),
  showSelectedIcon: false,
  segments: [
    ButtonSegment(
      value: _Section.links,
      label: Text(links == null ? 'Quotations' : 'Quotations ($links)'),
    ),
    ButtonSegment(
      value: _Section.thematic,
      label: Text(thematic == null ? 'Thematic' : 'Thematic ($thematic)'),
    ),
  ],
  selected: {selected},
  onSelectionChanged: (s) => onSelected(s.single),
);

/// One key phrase of a verse in the thematic overview: the phrase, then the
/// passages it points to as compact references, each opening its passage.
class _ThematicMarginEntry extends StatelessWidget {
  const _ThematicMarginEntry({
    required this.entry,
    required this.label,
    this.onOpen,
  });

  final ThematicReferenceEntry entry;
  final String Function(ThematicTarget) label;

  /// Opens a passage: 0-based book index, chapter, verse.
  final void Function(int bookIndex, int chapter, int verse)? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Wrap(
        spacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              entry.phrase,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final (i, target) in entry.targets.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: onOpen == null
                  ? null
                  : () =>
                        onOpen!(target.book - 1, target.chapter, target.verse),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Text(
                  i + 1 < entry.targets.length
                      ? '${label(target)};'
                      : label(target),
                  style: linkStyle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One verse's links, strongest first, with the matched words highlighted on
/// both sides. Choosing a link shows its words on the verse itself; tapping
/// the linked verse opens it in the reader. Beside them, its thematic
/// references.
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
    this.chosenSection,
    this.onSectionChanged,
    this.onClose,
    this.isLinkBookmarked,
    this.onToggleLinkBookmark,
    this.onNavigateToPassage,
    this.sendRequest,
    this.sendThematicRequest,
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

  /// The list the reader last picked in the panel, if any, and where a new
  /// pick is reported.
  final _Section? chosenSection;
  final ValueChanged<_Section>? onSectionChanged;
  final VoidCallback? onClose;
  final bool Function(StudyLinkVerse earlier, StudyLinkVerse later)?
  isLinkBookmarked;
  final Future<bool> Function(StudyLink link)? onToggleLinkBookmark;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final void Function(GetCrossReferences)? sendRequest;
  final void Function(GetThematicReferences)? sendThematicRequest;

  @override
  State<_VerseLinks> createState() => _VerseLinksState();
}

class _VerseLinksState extends State<_VerseLinks> {
  StreamSubscription<RustSignalPack<CrossReferences>>? _sub;
  StreamSubscription<RustSignalPack<ThematicReferences>>? _thematicSub;

  /// Null until the reply arrives.
  List<CrossReferenceEntry>? _entries;

  /// The verse's thematic references (the Treasury of Scripture Knowledge's),
  /// null until their reply arrives.
  List<ThematicReferenceEntry>? _thematic;

  /// The list the reader picked, if they have.
  late _Section? _chosenSection = widget.chosenSection;

  /// Which list shows: the one picked, else the quotations and parallels —
  /// unless the verse has none and does have thematic references.
  _Section get _section {
    final chosen = _chosenSection;
    if (chosen != null) return chosen;
    final noLinks = _entries?.isEmpty ?? false;
    final thematic = _thematic?.isNotEmpty ?? false;
    return noLinks && thematic ? _Section.thematic : _Section.links;
  }

  /// The linked verse whose matched words are shown on the source verse.
  int _focused = 0;

  /// Whether the links below [_VerseLinks.minScore] are shown.
  bool _showWeaker = false;

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

    _thematicSub = ThematicReferences.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.book != widget.book ||
          reply.chapter != widget.chapter ||
          reply.verse != widget.verse ||
          !mounted) {
        return;
      }
      setState(() => _thematic = reply.entries);
    });
    final thematicRequest = GetThematicReferences(
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
    );
    final sendThematic = widget.sendThematicRequest;
    if (sendThematic != null) {
      sendThematic(thematicRequest);
    } else {
      thematicRequest.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _thematicSub?.cancel();
    super.dispose();
  }

  String _ref(int book, int chapter, int verse) =>
      '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
      '$chapter:$verse';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries;
    final thematic = _thematic;
    final section = _section;
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
                    Text(
                      'Cross references',
                      style: theme.textTheme.titleMedium,
                    ),
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
        // The quotations show as soon as they arrive; only whether the verse
        // has nothing at all waits for the thematic references too.
        if (entries == null || (entries.isEmpty && thematic == null))
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (entries.isEmpty && (thematic?.isEmpty ?? false))
          const Expanded(
            child: Center(
              child: Text('No cross references found for this verse.'),
            ),
          )
        else ...[
          // The verse itself, with the focused link's matched words. The
          // thematic list has no words to show on it, and the header already
          // names the verse.
          if (section == _Section.links)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: OccurrenceVerseRow(
                key: ValueKey('source-$_focused'),
                cache: widget.cache,
                displayRef: _ref(widget.book, widget.chapter, widget.verse),
                bookIndex: widget.book - 1,
                chapter: widget.chapter,
                verse: widget.verse,
                highlightWords: const [],
                positions: entries.isEmpty
                    ? const []
                    : entries[_focused.clamp(0, entries.length - 1)]
                          .sourcePositions,
                isCurrent: true,
                englishOnly: widget.englishOnly,
                useEnglishBookNames: widget.useEnglishBookNames,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: _sectionSwitch(
              selected: section,
              links: entries.length,
              thematic: thematic == null ? null : _targetCount(thematic),
              onSelected: (s) {
                setState(() => _chosenSection = s);
                widget.onSectionChanged?.call(s);
              },
            ),
          ),
          const Divider(height: 17),
          Expanded(
            child: section == _Section.links
                ? entries.isEmpty
                      ? const Center(
                          child: Text('No quotations or parallels found.'),
                        )
                      : _entryList(context, entries)
                : thematic == null
                ? const Center(child: CircularProgressIndicator())
                : thematic.isEmpty
                ? const Center(child: Text('No thematic references.'))
                : _thematicList(context, thematic),
          ),
        ],
      ],
    );
  }

  static int _targetCount(List<ThematicReferenceEntry> thematic) =>
      thematic.fold(0, (n, e) => n + e.targets.length);

  /// A target's reference: one verse, or a run of verses.
  String _targetRef(ThematicTarget t) {
    final start = _ref(t.book, t.chapter, t.verse);
    if (t.lastChapter == t.chapter && t.lastVerse == t.verse) return start;
    if (t.lastChapter == t.chapter) return '$start–${t.lastVerse}';
    return '$start–${t.lastChapter}:${t.lastVerse}';
  }

  /// The Treasury of Scripture Knowledge's references: each key phrase of the
  /// verse, in its King James wording, then the passages it points to, each
  /// shown by its first verse.
  Widget _thematicList(
    BuildContext context,
    List<ThematicReferenceEntry> thematic,
  ) {
    final theme = Theme.of(context);
    final navigate = widget.onNavigateToPassage;
    final rows = <Widget Function()>[];
    for (final entry in thematic) {
      rows.add(
        () => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            '“${entry.phrase}”',
            style: theme.textTheme.titleSmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
      for (final target in entry.targets) {
        final ranged =
            target.lastChapter != target.chapter ||
            target.lastVerse != target.verse;
        if (ranged) {
          // The verse row names only the first verse it shows.
          rows.add(
            () => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _targetRef(target),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        rows.add(
          () => OccurrenceVerseRow(
            cache: widget.cache,
            displayRef: _targetRef(target),
            bookIndex: target.book - 1,
            chapter: target.chapter,
            verse: target.verse,
            highlightWords: const [],
            englishOnly: widget.englishOnly,
            useEnglishBookNames: widget.useEnglishBookNames,
            onTap: navigate == null
                ? null
                : () => navigate(target.book - 1, target.chapter, target.verse),
          ),
        );
      }
    }
    rows.add(
      () => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'From the Treasury of Scripture Knowledge.',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    return ListView.separated(
      key: const ValueKey('thematic-list'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => rows[i](),
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
                    '${_parallel(widget.book, entry.book)}'
                    '${crossReferenceStrength(entry.score)} · '
                    '${_words(entry.positions.length)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (widget.isLinkBookmarked case final isBookmarked?)
                  if (widget.onToggleLinkBookmark case final onToggle?)
                    _LinkBookmarkButton(
                      link: _studyLink(
                        ownBook: widget.book,
                        ownChapter: widget.chapter,
                        ownVerse: widget.verse,
                        ownPositions: entry.sourcePositions,
                        otherBook: entry.book,
                        otherChapter: entry.chapter,
                        otherVerse: entry.verse,
                        otherPositions: entry.positions,
                        score: entry.score,
                      ),
                      isBookmarked: isBookmarked,
                      onToggle: onToggle,
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

/// A link between two verses, in the study document's canonical order
/// whichever side the panel was opened from.
StudyLink _studyLink({
  required int ownBook,
  required int ownChapter,
  required int ownVerse,
  required List<int> ownPositions,
  required int otherBook,
  required int otherChapter,
  required int otherVerse,
  required List<int> otherPositions,
  required double score,
}) {
  final own = (bookIndex: ownBook - 1, chapter: ownChapter, verse: ownVerse);
  final other = (
    bookIndex: otherBook - 1,
    chapter: otherChapter,
    verse: otherVerse,
  );
  int order(StudyLinkVerse v) =>
      (v.bookIndex << 16) | (v.chapter << 8) | v.verse;
  final ownFirst = order(own) < order(other);
  return StudyLink(
    earlier: ownFirst ? own : other,
    later: ownFirst ? other : own,
    earlierPositions: ownFirst ? ownPositions : otherPositions,
    laterPositions: ownFirst ? otherPositions : ownPositions,
    score: score,
  );
}

/// Bookmarks a link in the active study, showing whether it is bookmarked.
class _LinkBookmarkButton extends StatefulWidget {
  const _LinkBookmarkButton({
    required this.link,
    required this.isBookmarked,
    required this.onToggle,
  });

  final StudyLink link;
  final bool Function(StudyLinkVerse earlier, StudyLinkVerse later)
  isBookmarked;
  final Future<bool> Function(StudyLink link) onToggle;

  @override
  State<_LinkBookmarkButton> createState() => _LinkBookmarkButtonState();
}

class _LinkBookmarkButtonState extends State<_LinkBookmarkButton> {
  late bool _bookmarked = widget.isBookmarked(
    widget.link.earlier,
    widget.link.later,
  );

  @override
  void didUpdateWidget(_LinkBookmarkButton old) {
    super.didUpdateWidget(old);
    _bookmarked = widget.isBookmarked(widget.link.earlier, widget.link.later);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _bookmarked ? 'Remove link bookmark' : 'Bookmark this link',
    iconSize: 16,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    icon: Icon(
      _bookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
      color: _bookmarked ? Theme.of(context).colorScheme.primary : null,
    ),
    onPressed: () async {
      final bookmarked = await widget.onToggle(widget.link);
      if (mounted) setState(() => _bookmarked = bookmarked);
    },
  );
}
