import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'prophecy_card.dart';
import 'verse_text_cache.dart';
import 'word_info_sheet.dart'
    show NtTextButton, OccurrenceVerseRow, VerseModeIcon;

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
  required bool ntGreek,
  required bool ntSyriac,
  required ValueChanged<bool> onNtGreekChanged,
  VoidCallback? onClose,
}) => [
  NtTextButton(
    greek: ntGreek,
    syriacScript: ntSyriac,
    onChanged: onNtGreekChanged,
  ),
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

/// Which part of the book the overview lists. Only prophecies are listed
/// across the whole [bible].
enum CrossReferenceScope { chapter, book, bible }

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
///
/// Both views also list prophecies: those of the OT passage, or fulfilled in
/// the NT one, with their fulfilments. The overview can list them for the
/// whole Bible, by theme.
class CrossReferencesPanel extends StatefulWidget {
  const CrossReferencesPanel({
    super.key,
    required this.book,
    required this.chapter,
    this.target,
    this.targetRequest = 0,
    required this.useEnglishBookNames,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNtGreekChanged,
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
    this.sendVerseProphecyRequest,
    this.sendProphecyOverviewRequest,
    this.sendVerseTextsRequest,
  });

  /// 1-based book number and chapter the overview shows. Docked beside the
  /// reader these follow its position, and the overview follows them with
  /// its filters kept.
  final int book;
  final int chapter;

  /// A verse (1-based book) whose links to open: at once, and again whenever
  /// [targetRequest] changes — so asking for the same verse twice reopens it.
  /// Null with a changed request goes back to the overview.
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
  final void Function(GetVerseProphecies)? sendVerseProphecyRequest;
  final void Function(GetProphecies)? sendProphecyOverviewRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  /// The reader shows the NT in Syriac script, so NT verse rows do too.
  final bool ntSyriac;

  /// The reader shows the NT in Greek, so NT verse rows do too, without the
  /// matched words: those are the Peshitta's. The panel's switch between
  /// the two is reported to [onNtGreekChanged], so the reader follows it.
  final bool ntGreek;
  final ValueChanged<bool>? onNtGreekChanged;

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

  /// Prophecies per page of the prophecy overview.
  static const _prophecyPageSize = 30;

  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  StreamSubscription<RustSignalPack<Quotations>>? _sub;
  StreamSubscription<RustSignalPack<ThematicOverview>>? _thematicSub;
  StreamSubscription<RustSignalPack<Prophecies>>? _prophecySub;

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

  /// Whether NT verses are shown in Greek: the reader's setting, which the
  /// panel's own switch changes.
  late bool _ntGreek = widget.ntGreek;

  /// Request ids are handed out app-wide, not per panel: the reply stream is a
  /// broadcast, so a late reply to a closed panel would otherwise carry the id
  /// a new panel waits on and fill it with another book's references.
  static int _nextRequestId = 1;
  int _requestId = 0;
  bool _loading = true;
  int _total = 0;
  final List<QuotationEntry> _entries = [];

  /// The thematic overview's verses so far, and how many there are in all.
  final List<ThematicVerseEntry> _thematicVerses = [];
  int _thematicTotal = 0;

  /// The prophecy overview's prophecies so far, how many there are in all,
  /// and its filters: a theme (empty for any) and which prophecies.
  final List<ProphecyEntry> _prophecies = [];
  int _prophecyTotal = 0;
  String _prophecyTheme = '';
  ProphecyKinds _prophecyKinds = ProphecyKinds.all;
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
      if (reply.requestId != _requestId ||
          reply.book != widget.book ||
          !mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _total = reply.total;
        _entries.addAll(reply.entries);
      });
    });
    _thematicSub = ThematicOverview.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId ||
          reply.book != widget.book ||
          !mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _thematicTotal = reply.total;
        _thematicVerses.addAll(reply.verses);
      });
    });
    _prophecySub = Prophecies.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId || !mounted) return;
      setState(() {
        _loading = false;
        _prophecyTotal = reply.total;
        _prophecies.addAll(reply.entries);
      });
    });
    _requestOverview();
  }

  @override
  void didUpdateWidget(CrossReferencesPanel old) {
    super.didUpdateWidget(old);
    if (widget.ntGreek != old.ntGreek) _ntGreek = widget.ntGreek;
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
    // Asked for no verse, the panel shows the overview.
    if (target == null) {
      _view = null;
      return;
    }
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
    _prophecySub?.cancel();
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
      _prophecies.clear();
      _prophecyTotal = 0;
    }
    _loading = true;
    _overviewLoaded = _overviewSection;
    final chapterScope = _scope == CrossReferenceScope.chapter;
    if (_overviewSection == _Section.prophecy) {
      final everywhere = _scope == CrossReferenceScope.bible;
      final request = GetProphecies(
        requestId: _requestId = _nextRequestId++,
        book: everywhere ? 0 : widget.book,
        firstChapter: everywhere
            ? 0
            : chapterScope
            ? widget.chapter
            : _firstChapter,
        lastChapter: everywhere
            ? 0
            : chapterScope
            ? widget.chapter
            : _lastChapter,
        theme: _prophecyTheme,
        messianic: _prophecyKinds.index,
        limit: _prophecyPageSize,
        offset: _prophecies.length,
      );
      final send = widget.sendProphecyOverviewRequest;
      if (send != null) {
        send(request);
      } else {
        request.sendSignalToRust();
      }
      return;
    }
    if (_overviewSection == _Section.thematic) {
      final request = GetThematicOverview(
        requestId: _requestId = _nextRequestId++,
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
      requestId: _requestId = _nextRequestId++,
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

  /// Shows the NT verses in Greek or the Peshitta, and has the reader follow.
  void _setNtGreek(bool greek) {
    setState(() => _ntGreek = greek);
    widget.onNtGreekChanged?.call(greek);
  }

  /// Whether a verse of [book] (1-based) is shown in Greek.
  bool _greekRow(int book) => _ntGreek && book >= 40;

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
        ntSyriac: widget.ntSyriac,
        ntGreek: _ntGreek,
        onNtGreekChanged: _setNtGreek,
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
        sendProphecyRequest: widget.sendVerseProphecyRequest,
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
    final section = _overviewSection;
    final thematic = section == _Section.thematic;
    final prophecy = section == _Section.prophecy;
    final count = switch (section) {
      _Section.thematic =>
        _thematicTotal == 1 ? '1 verse' : '$_thematicTotal verses',
      _Section.prophecy =>
        _prophecyTotal == 1 ? '1 prophecy' : '$_prophecyTotal prophecies',
      _Section.links => _total == 1 ? '1 link' : '$_total links',
    };
    final loaded = switch (section) {
      _Section.thematic => _thematicVerses.isNotEmpty,
      _Section.prophecy => _prophecies.isNotEmpty,
      _Section.links => _entries.isNotEmpty,
    };
    final everywhere = prophecy && _scope == CrossReferenceScope.bible;
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
                      prophecy
                          ? (everywhere
                                ? 'Prophecies in the Bible'
                                : 'Prophecies in $bookName')
                          : thematic
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
                ntGreek: _ntGreek,
                ntSyriac: widget.ntSyriac,
                onNtGreekChanged: _setNtGreek,
                onClose: widget.onClose,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: _sectionSwitch(
            selected: _overviewSection,
            onSelected: (section) => _update(() {
              _section = section;
              // Only prophecies are listed across the Bible.
              if (section != _Section.prophecy &&
                  _scope == CrossReferenceScope.bible) {
                _scope = CrossReferenceScope.book;
              }
            }),
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
                  if (prophecy)
                    const ButtonSegment(
                      value: CrossReferenceScope.bible,
                      label: Text('Bible'),
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
              if (prophecy) ...[
                DropdownButton<String>(
                  key: const ValueKey('prophecy-theme'),
                  value: _prophecyTheme,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('All themes'),
                    ),
                    for (final theme in prophecyThemes)
                      DropdownMenuItem(
                        value: theme,
                        child: Text(prophecyThemeLabel(theme)),
                      ),
                  ],
                  onChanged: (theme) => _update(() => _prophecyTheme = theme!),
                ),
                SegmentedButton<ProphecyKinds>(
                  key: const ValueKey('prophecy-kinds'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ProphecyKinds.all, label: Text('All')),
                    ButtonSegment(
                      value: ProphecyKinds.messianic,
                      label: Text('Messianic'),
                    ),
                    ButtonSegment(
                      value: ProphecyKinds.general,
                      label: Text('General'),
                    ),
                  ],
                  selected: {_prophecyKinds},
                  onSelectionChanged: (s) =>
                      _update(() => _prophecyKinds = s.single),
                ),
              ],
              // How links are found, ordered and filtered: nothing a
              // thematic reference or prophecy has.
              if (!thematic && !prophecy) ...[
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
          child: switch (section) {
            _Section.thematic => _thematicOverviewList(context),
            _Section.prophecy => _prophecyOverviewList(context),
            _Section.links => _overviewList(context),
          },
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

  /// The prophecies of the chapter, book or Bible, each with its
  /// fulfilments, in the order of their OT passages.
  Widget _prophecyOverviewList(BuildContext context) {
    if (_prophecies.isEmpty) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator()
            : const Text('No prophecies here.'),
      );
    }
    final hasMore = _prophecies.length < _prophecyTotal;
    final controller = ScrollController(initialScrollOffset: _overviewOffset);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _overviewOffset = n.metrics.pixels;
        return false;
      },
      child: ListView.separated(
        key: const ValueKey('prophecy-overview'),
        controller: controller,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: _prophecies.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const Divider(height: 24),
        itemBuilder: (context, i) {
          if (i == _prophecies.length) return _showMore();
          return ProphecyCard(
            prophecy: _prophecies[i],
            cache: _verseTexts,
            useEnglishBookNames: widget.useEnglishBookNames,
            englishOnly: _englishOnly,
            ntSyriac: widget.ntSyriac,
            ntGreek: _ntGreek,
            onNavigateToPassage: widget.onNavigateToPassage,
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
              positions: _greekRow(entry.otherBook)
                  ? const []
                  : entry.otherPositions,
              englishOnly: _englishOnly,
              syriac: widget.ntSyriac && entry.otherBook >= 40,
              greek: _greekRow(entry.otherBook),
              useEnglishBookNames: widget.useEnglishBookNames,
              onTap: () => _openVerse(entry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lists the panel shows, for a verse or a chapter.
enum _Section {
  /// Quotations and parallels found by aligning roots.
  links,

  /// The Treasury of Scripture Knowledge's references for its key phrases.
  thematic,

  /// Prophecies and their fulfilments.
  prophecy,
}

/// The Quotations | Thematic | Prophecy switch, for the overview and a verse
/// alike; a verse's view gives its counts.
Widget _sectionSwitch({
  required _Section selected,
  required ValueChanged<_Section> onSelected,
  int? links,
  int? thematic,
  int? prophecy,
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
    ButtonSegment(
      value: _Section.prophecy,
      label: Text(prophecy == null ? 'Prophecy' : 'Prophecy ($prophecy)'),
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
/// references and the prophecies it belongs to.
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
    required this.ntSyriac,
    required this.ntGreek,
    required this.onNtGreekChanged,
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
    this.sendProphecyRequest,
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
  final bool ntSyriac;
  final bool ntGreek;
  final ValueChanged<bool> onNtGreekChanged;
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
  final void Function(GetVerseProphecies)? sendProphecyRequest;

  @override
  State<_VerseLinks> createState() => _VerseLinksState();
}

class _VerseLinksState extends State<_VerseLinks> {
  /// Whether a verse of [book] (1-based) is shown in Greek.
  bool _greekRow(int book) => widget.ntGreek && book >= 40;

  StreamSubscription<RustSignalPack<CrossReferences>>? _sub;
  StreamSubscription<RustSignalPack<ThematicReferences>>? _thematicSub;
  StreamSubscription<RustSignalPack<VerseProphecies>>? _prophecySub;

  /// Null until the reply arrives.
  List<CrossReferenceEntry>? _entries;

  /// The prophecies the verse belongs to, null until their reply arrives.
  List<ProphecyEntry>? _prophecies;

  /// The verse's thematic references (the Treasury of Scripture Knowledge's),
  /// null until their reply arrives.
  List<ThematicReferenceEntry>? _thematic;

  /// The list the reader picked, if they have.
  late _Section? _chosenSection = widget.chosenSection;

  /// Which list shows: the one picked, else the quotations and parallels —
  /// unless the verse has none, when it is its prophecies, then its thematic
  /// references.
  _Section get _section {
    final chosen = _chosenSection;
    if (chosen != null) return chosen;
    if (!(_entries?.isEmpty ?? false)) return _Section.links;
    if (_prophecies?.isNotEmpty ?? false) return _Section.prophecy;
    if (_thematic?.isNotEmpty ?? false) return _Section.thematic;
    return _Section.links;
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

    _prophecySub = VerseProphecies.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.book != widget.book ||
          reply.chapter != widget.chapter ||
          reply.verse != widget.verse ||
          !mounted) {
        return;
      }
      setState(() => _prophecies = reply.entries);
    });
    final prophecyRequest = GetVerseProphecies(
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
    );
    final sendProphecy = widget.sendProphecyRequest;
    if (sendProphecy != null) {
      sendProphecy(prophecyRequest);
    } else {
      prophecyRequest.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _thematicSub?.cancel();
    _prophecySub?.cancel();
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
    final prophecies = _prophecies;
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
                ntGreek: widget.ntGreek,
                ntSyriac: widget.ntSyriac,
                onNtGreekChanged: widget.onNtGreekChanged,
                onClose: widget.onClose,
              ),
            ],
          ),
        ),
        // The quotations show as soon as they arrive; only whether the verse
        // has nothing at all waits for the thematic references and the
        // prophecies too.
        if (entries == null ||
            (entries.isEmpty && (thematic == null || prophecies == null)))
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (entries.isEmpty &&
            (thematic?.isEmpty ?? false) &&
            (prophecies?.isEmpty ?? false))
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
                positions: entries.isEmpty || _greekRow(widget.book)
                    ? const []
                    : entries[_focused.clamp(0, entries.length - 1)]
                          .sourcePositions,
                isCurrent: true,
                englishOnly: widget.englishOnly,
                syriac: widget.ntSyriac && widget.book >= 40,
                greek: _greekRow(widget.book),
                useEnglishBookNames: widget.useEnglishBookNames,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: _sectionSwitch(
              selected: section,
              links: entries.length,
              thematic: thematic == null ? null : _targetCount(thematic),
              prophecy: prophecies?.length,
              onSelected: (s) {
                setState(() => _chosenSection = s);
                widget.onSectionChanged?.call(s);
              },
            ),
          ),
          const Divider(height: 17),
          Expanded(
            child: switch (section) {
              _Section.links =>
                entries.isEmpty
                    ? const Center(
                        child: Text('No quotations or parallels found.'),
                      )
                    : _entryList(context, entries),
              _Section.thematic =>
                thematic == null
                    ? const Center(child: CircularProgressIndicator())
                    : thematic.isEmpty
                    ? const Center(child: Text('No thematic references.'))
                    : _thematicList(context, thematic),
              _Section.prophecy =>
                prophecies == null
                    ? const Center(child: CircularProgressIndicator())
                    : prophecies.isEmpty
                    ? const Center(child: Text('No prophecies here.'))
                    : ListView.separated(
                        key: const ValueKey('prophecy-list'),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: prophecies.length,
                        separatorBuilder: (_, _) => const Divider(height: 24),
                        itemBuilder: (context, i) => ProphecyCard(
                          prophecy: prophecies[i],
                          cache: widget.cache,
                          useEnglishBookNames: widget.useEnglishBookNames,
                          englishOnly: widget.englishOnly,
                          ntSyriac: widget.ntSyriac,
                          ntGreek: widget.ntGreek,
                          onNavigateToPassage: widget.onNavigateToPassage,
                        ),
                      ),
            },
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
            syriac: widget.ntSyriac && target.book >= 40,
            greek: _greekRow(target.book),
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
          positions: _greekRow(entry.book) ? const [] : entry.positions,
          englishOnly: widget.englishOnly,
          syriac: widget.ntSyriac && entry.book >= 40,
          greek: _greekRow(entry.book),
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
