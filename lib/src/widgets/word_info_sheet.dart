import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';

import '../app_settings.dart';
import '../bindings/bindings.dart';
import '../bible_data.dart';
import '../issue_reporting.dart';
import '../request_failure.dart';
import '../surface.dart';
import '../study_workspace.dart';
import '../tutor/progress_sync.dart';
import '../word_proximity.dart';
import 'lexicon_source.dart';
import 'verse_row.dart' show verseGlossPositions;
import 'verse_text_cache.dart';

const Map<String, int> _kBdbBookToIndex = {
  'Genesis': 0,
  'Exodus': 1,
  'Leviticus': 2,
  'Numbers': 3,
  'Deuteronomy': 4,
  'Joshua': 5,
  'Judges': 6,
  'I Samuel': 7,
  'II Samuel': 8,
  'I Kings': 9,
  'II Kings': 10,
  'Isaiah': 11,
  'Jeremiah': 12,
  'Ezekiel': 13,
  'Hosea': 14,
  'Joel': 15,
  'Amos': 16,
  'Obadiah': 17,
  'Jonah': 18,
  'Micah': 19,
  'Nahum': 20,
  'Habakkuk': 21,
  'Zephaniah': 22,
  'Haggai': 23,
  'Zechariah': 24,
  'Malachi': 25,
  'Psalms': 26,
  'Proverbs': 27,
  'Job': 28,
  'Song of Songs': 29,
  'Ruth': 30,
  'Lamentations': 31,
  'Ecclesiastes': 32,
  'Esther': 33,
  'Daniel': 34,
  'Ezra': 35,
  'Nehemiah': 36,
  'I Chronicles': 37,
  'II Chronicles': 38,
};

({int bookIndex, int chapter, int verse})? _parseBibleRef(String href) {
  final match = RegExp(r'^(.+) (\d+):(\d+)$').firstMatch(href);
  if (match == null) return null;
  final bookName = match.group(1)!;
  final chapter = int.tryParse(match.group(2)!) ?? 0;
  final verse = int.tryParse(match.group(3)!) ?? 0;
  final bookIndex = _kBdbBookToIndex[bookName];
  if (bookIndex == null || chapter == 0 || verse == 0) return null;
  return (bookIndex: bookIndex, chapter: chapter, verse: verse);
}

/// How long a sheet stays open on its Lexicon tab before it preloads the
/// word's occurrences. Long enough that a glance at a gloss costs no root scan,
/// short enough that the list is normally ready when the tab is opened.
const occurrencePrefetchDelay = Duration(milliseconds: 400);

// Ids for word-info and occurrence requests, shared by every sheet so no two
// open panes ever wait on the same id. Wraps as the u32 it is sent as.
int _lastRequestId = 0;
int _nextRequestId() => _lastRequestId = (_lastRequestId + 1) & 0xffffffff;

class WordInfoSheet extends StatefulWidget {
  const WordInfoSheet({
    super.key,
    required this.word,
    required this.syriac,
    this.bdbId,
    this.initialRoot,
    this.readerGloss,
    this.book,
    this.chapter,
    this.verse,
    this.position,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.onOpenWord,
    this.isStudyBookmarked,
    this.onToggleStudyBookmark,
    this.reportContext,
    this.sendInfoRequest,
    this.sendOccurrencesRequest,
    this.sendVerseTextsRequest,
    this.sendDictionaryRequest,
    this.docked = false,
    this.proximity,
    this.proximityId,
  });

  final String word;
  final bool syriac;
  final String? initialRoot;

  /// Lets the reader replace a docked inspector and retain its word history.
  /// A null entry ID requests normal surface word info.
  final void Function(String word, String? bdbId)? onOpenWord;

  /// How the sheet's requests reach Rust. Injectable so a widget test can
  /// drive the sheet without the native library loaded, as the reader does.
  final void Function(GetWordInfo)? sendInfoRequest;
  final void Function(GetWordOccurrences)? sendOccurrencesRequest;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;
  final void Function(GetDictionaryEntry)? sendDictionaryRequest;

  /// Renders as a bounded side-panel body instead of a draggable bottom sheet.
  final bool docked;

  /// The open word panes this sheet can search near, and this sheet's pane id
  /// among them. The sheet contributes its filtered occurrences under that id
  /// and, with another pane open, offers a proximity search over them.
  final WordProximity? proximity;
  final String? proximityId;

  /// When set, the sheet shows the BDB entry with this id (a Lexicon
  /// cross-reference target) rather than parsing [word] as a surface form;
  /// [word] is then just the target headword for the title.
  final String? bdbId;

  /// The exact gloss currently rendered underneath this token in the reader.
  /// It can intentionally differ from the descriptive Lexicon header.
  final String? readerGloss;

  /// Concrete reader location for the tapped token's own morphology.
  final int? book;
  final int? chapter;
  final int? verse;
  final int? position;

  /// Whether references in the Occurrences tab use standard English names.
  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final bool Function(StudyWord word)? isStudyBookmarked;
  final Future<bool> Function(StudyWord word)? onToggleStudyBookmark;
  final Map<String, Object?>? reportContext;

  @override
  State<WordInfoSheet> createState() => _WordInfoSheetState();
}

class _WordInfoSheetState extends State<WordInfoSheet>
    with SingleTickerProviderStateMixin {
  StreamSubscription<RustSignalPack<WordInfo>>? _sub;
  WordInfo? _info;
  final Set<(int, int)> _expandedBdb = {};
  // Lexemes with several entries start folded to one summary row, the looked-up
  // word's own open (see [_lexemeExpanded]); these are the ones the reader has
  // toggled from that.
  final Set<int> _toggledLexemes = {};
  late final TabController _tabController;
  bool _adminMode = false;
  // OT-only: which of the word's roots the Lexicon and Occurrences tabs show.
  // Null means the root the parse resolved to, which is what Rust answers with
  // when the request names none. A compound name is built from two roots
  // (אֱלִיעֶזֶר from אל "god" and עזר "help") and belongs to both lists, so which
  // of them to read it under is the reader's to choose.
  String? _selectedRoot;
  // Which surface forms of the root are shown in the occurrences list. Empty
  // means "every form". The tab starts on the tapped word's own form (see
  // [_exactFormKey]) when the root's list holds it, and the header's scope
  // toggle (see [_FormScope]) moves between that, the tapped token's parse and
  // every form in one tap; the filter sheet widens or narrows from any of them.
  final Set<String> _forms = {};
  // The parse filter, one selection per morphology dimension. A dimension with
  // no selection admits everything; within a dimension the selections are
  // alternatives, and across dimensions they all have to hold — so "Qal" plus
  // "plural" plus "participle" narrows, where a list of whole labels would have
  // needed the exact combination to exist as an entry. OT and NT tokens share
  // the one vocabulary, so a selection cuts across both testaments.
  final Map<_ParseDimension, Set<String>> _parse = {};
  final ScrollController _dockedScrollController = ScrollController();
  // Restrict the list to any selected books (1-based, matching the
  // occurrence rows). Empty shows the whole canon.
  final Set<int> _books = {};
  // Every occurrence row reads its verse text through this one cache, which
  // batches the requests of a layout pass into a single round-trip.
  late final VerseTextCache _verseTexts = VerseTextCache(
    send: widget.sendVerseTextsRequest,
  );
  // False shows Hebrew verse text, true shows the aligned English reader
  // glosses instead.
  bool _occurrenceVerseEnglishOnly = false;
  // Occurrence lists are full-text root scans, and Rust answers requests one at
  // a time with no way to cancel one, so a scan nobody looks at still holds up
  // the chapter the reader turns to next. They are fetched when the
  // Occurrences tab is opened, or once the sheet has stayed open for
  // [occurrencePrefetchDelay]. Null until that fetch completes.
  StreamSubscription<RustSignalPack<WordOccurrences>>? _occSub;
  WordOccurrences? _occ;
  bool _occRequested = false;
  Timer? _occPrefetch;
  // The ids of this sheet's outstanding requests. Replies name the request
  // they answer, and any other reply — an earlier root's, or another open
  // pane's — is not this sheet's to show.
  int? _infoRequestId;
  int? _occRequestId;
  final Set<StudyWordKind> _studyBookmarks = {};
  bool _bookmarkPending = false;
  ProximitySource? _proximitySource;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.animation?.addListener(_onTabAnimation);
    _selectedRoot = widget.initialRoot;
    _sub = WordInfo.rustSignalStream.listen(_onWordInfo);
    _occSub = WordOccurrences.rustSignalStream.listen(_onWordOccurrences);
    _requestInfo();
    _loadAdminMode();
    _loadOccurrenceVerseMode();
    final proximity = widget.proximity;
    final id = widget.proximityId;
    if (proximity != null && id != null) {
      final source = ProximitySource(
        id: id,
        label: () => widget.word,
        hits: _proximityHits,
      );
      _proximitySource = source;
      proximity
        ..register(source)
        ..addListener(_onProximityChanged);
    }
  }

  void _onProximityChanged() {
    if (mounted) setState(() {});
  }

  /// This word's filtered occurrences have changed, and with them any
  /// proximity search it takes part in.
  void _occurrenceFilterChanged() => widget.proximity?.changed();

  void _onWordInfo(RustSignalPack<WordInfo> pack) {
    final info = pack.message;
    if (!mounted || info.requestId != _infoRequestId) return;
    _infoRequestId = null;
    setState(() {
      _info = info;
      _readStudyBookmarks(info);
    });
    // An unparsed word shows nothing but its occurrences, so it needs them
    // now. Otherwise preload them only if the reader stays on this word: the
    // Occurrences tab is then populated (or at least loading) by the time
    // they switch to it, without a glance at a gloss costing a root scan.
    if (!info.found || _tabController.index == 1) {
      _fetchOccurrences();
    } else if (!_occRequested) {
      _occPrefetch?.cancel();
      _occPrefetch = Timer(occurrencePrefetchDelay, _fetchOccurrences);
    }
  }

  void _onWordOccurrences(RustSignalPack<WordOccurrences> pack) {
    final occ = pack.message;
    if (!mounted || occ.requestId != _occRequestId) return;
    _occRequestId = null;
    setState(() {
      _occ = occ;
      final exact = _exactFormKey();
      if (exact != null && _forms.isEmpty && _parse.isEmpty) {
        _forms.add(exact);
      }
    });
    _occurrenceFilterChanged();
  }

  /// Heading for the Occurrences tab fetches its lists at once.
  void _onTabAnimation() {
    if ((_tabController.animation?.value ?? 0) > 0) _fetchOccurrences();
  }

  void _requestInfo() {
    final id = _infoRequestId = _nextRequestId();
    final request = GetWordInfo(
      requestId: id,
      word: widget.word,
      syriac: widget.syriac,
      bdbId: widget.bdbId,
      book: widget.book,
      chapter: widget.chapter,
      verse: widget.verse,
      position: widget.position,
      root: _selectedRoot,
    );
    final send = widget.sendInfoRequest;
    if (send == null) {
      request.sendSignalToRust();
    } else {
      send(request);
    }
  }

  StudyWord _studyWord(WordInfo info, StudyWordKind kind) =>
      StudyWord(root: info.root, surface: widget.word, kind: kind);

  void _readStudyBookmarks(WordInfo info) {
    _studyBookmarks.clear();
    for (final kind in StudyWordKind.values) {
      if (widget.isStudyBookmarked?.call(_studyWord(info, kind)) ?? false) {
        _studyBookmarks.add(kind);
      }
    }
  }

  @override
  void didUpdateWidget(covariant WordInfoSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_info != null) _readStudyBookmarks(_info!);
  }

  Future<void> _toggleStudyBookmark(WordInfo info, StudyWordKind kind) async {
    final callback = widget.onToggleStudyBookmark;
    if (callback == null || _bookmarkPending) return;
    setState(() => _bookmarkPending = true);
    try {
      final bookmarked = await callback(_studyWord(info, kind));
      if (mounted && identical(info, _info)) {
        setState(() {
          if (bookmarked) {
            _studyBookmarks.add(kind);
          } else {
            _studyBookmarks.remove(kind);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _bookmarkPending = false);
    }
  }

  Widget _studyBookmarkMenu(WordInfo info) => PopupMenuButton<StudyWordKind>(
    tooltip: 'Study bookmarks',
    enabled: !_bookmarkPending,
    icon: Icon(
      _studyBookmarks.isEmpty ? Icons.bookmark_add_outlined : Icons.bookmark,
    ),
    iconSize: 20,
    padding: EdgeInsets.zero,
    onSelected: (kind) => _toggleStudyBookmark(info, kind),
    itemBuilder: (_) => [
      for (final kind in StudyWordKind.values)
        if (kind == StudyWordKind.form || info.root.isNotEmpty)
          CheckedPopupMenuItem(
            value: kind,
            checked: _studyBookmarks.contains(kind),
            child: Text(
              _studyBookmarks.contains(kind)
                  ? 'Remove ${kind.name} bookmark'
                  : 'Bookmark this ${kind.name}',
            ),
          ),
    ],
  );

  // Fetch the occurrence lists (full-text root scans). Idempotent via
  // [_occRequested] so the preload and the tab can't both fire it.
  void _fetchOccurrences() {
    _occPrefetch?.cancel();
    _occPrefetch = null;
    if (_occRequested || !mounted) return;
    _occRequested = true;
    final id = _occRequestId = _nextRequestId();
    final request = GetWordOccurrences(
      requestId: id,
      word: widget.word,
      syriac: widget.syriac,
      root: _selectedRoot,
    );
    final send = widget.sendOccurrencesRequest;
    if (send == null) {
      request.sendSignalToRust();
    } else {
      send(request);
    }
  }

  // Read the word under another of its roots. Both tabs are re-fetched, since
  // both answer per root: the Lexicon shows that root's lexeme tree and the
  // Occurrences its concordance. The occurrence filters go with them — a stem or
  // parse chosen among עזר's forms means nothing among אלה's.
  void _selectRoot(String root) {
    if ((_selectedRoot ?? _primaryRoot()) == root) return;
    setState(() {
      _selectedRoot = root;
      _forms.clear();
      _parse.clear();
      _books.clear();
      _expandedBdb.clear();
      _toggledLexemes.clear();
      _occ = null;
      _occRequested = false;
    });
    // Replies still on their way for the previous root are ignored: the
    // requests below take new ids.
    _occurrenceFilterChanged();
    _requestInfo();
    _fetchOccurrences();
  }

  /// The tapped word's own surface form, when it stands among the selected
  /// root's occurrences. Null otherwise — a headword that is never attested,
  /// or a root the word was switched away from — and the exact-match toggle is
  /// then not offered, since it could only show an empty list.
  ///
  /// It and [_tappedParse] depend on nothing but the loaded lists, so each is
  /// worked out once per reply rather than rescanned on every rebuild.
  ///
  /// The form is the list's own spelling of it: the tokens are matched on their
  /// normalised key, since an NT token is spelled as SEDRA vocalises it.
  String? _exactFormKey() => _exactFormMemo.get([_occ], () {
    final key = hebrewSurfaceKey(widget.word);
    for (final o in _occ?.tokens ?? const <Occurrence>[]) {
      if (o.surface == key || hebrewSurfaceKey(o.surface) == key) {
        return o.surface;
      }
    }
    return null;
  });
  final _exactFormMemo = _Memo<String?>();
  final _tappedParseMemo = _Memo<Map<_ParseDimension, String>?>();

  /// The tapped token's own morphology, one value per dimension it carries —
  /// what the Same parse scope sets as the parse filter.
  ///
  /// Read from the token's occurrence row when the reader said where it stands,
  /// so an ambiguous spelling gives the analysis of *this* token. Without a
  /// location the surface's most common analysis stands in. Null when neither
  /// is there, or the token carries no parse at all.
  Map<_ParseDimension, String>? _tappedParse() =>
      _tappedParseMemo.get([_occ], _computeTappedParse);

  Map<_ParseDimension, String>? _computeTappedParse() {
    final key = _exactFormKey();
    final own = [
      for (final o in _occ?.tokens ?? const <Occurrence>[])
        if (o.surface == key) o,
    ];
    Occurrence? token;
    if (widget.position != null) {
      for (final o in own) {
        if (o.book == widget.book &&
            o.chapter == widget.chapter &&
            o.verse == widget.verse &&
            o.position == widget.position) {
          token = o;
          break;
        }
      }
    }
    if (token == null) {
      final counts = <String, int>{};
      final byParse = <String, Occurrence>{};
      for (final o in own) {
        final signature = [
          for (final dimension in _ParseDimension.values) dimension.of(o),
        ].join('|');
        counts[signature] = (counts[signature] ?? 0) + 1;
        byParse.putIfAbsent(signature, () => o);
      }
      String? best;
      for (final entry in counts.entries) {
        if (best == null || entry.value > counts[best]!) best = entry.key;
      }
      token = best == null ? null : byParse[best];
    }
    if (token == null) return null;
    final parse = {
      for (final dimension in _ParseDimension.values)
        if (dimension.of(token).isNotEmpty) dimension: dimension.of(token),
    };
    return parse.isEmpty ? null : parse;
  }

  /// Which scope the form and parse filters currently amount to, or null when
  /// the filter sheet has cut some other way. A dimension released back to
  /// "Any" leaves an empty selection behind, which admits everything and so
  /// counts as no selection.
  _FormScope? _currentScope(
    String? exactForm,
    Map<_ParseDimension, String>? tappedParse,
  ) {
    final parse = {
      for (final entry in _parse.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
    if (_forms.isEmpty && parse.isEmpty) return _FormScope.all;
    if (exactForm != null &&
        parse.isEmpty &&
        _forms.length == 1 &&
        _forms.contains(exactForm)) {
      return _FormScope.exact;
    }
    if (tappedParse != null &&
        _forms.isEmpty &&
        parse.length == tappedParse.length &&
        tappedParse.entries.every(
          (entry) =>
              parse[entry.key]?.length == 1 &&
              parse[entry.key]!.contains(entry.value),
        )) {
      return _FormScope.parse;
    }
    return null;
  }

  /// Replace the form and parse filters with [scope]; the book filter is a
  /// separate cut and stays.
  void _applyScope(
    _FormScope scope,
    String? exactForm,
    Map<_ParseDimension, String>? tappedParse,
  ) {
    setState(() {
      _forms.clear();
      _parse.clear();
      switch (scope) {
        case _FormScope.exact:
          if (exactForm != null) _forms.add(exactForm);
        case _FormScope.parse:
          tappedParse?.forEach((dimension, value) {
            _parse[dimension] = {value};
          });
        case _FormScope.all:
          break;
      }
    });
    _occurrenceFilterChanged();
  }

  /// The root the parse resolved to, which the sheet opens on.
  String? _primaryRoot() {
    final roots = _info?.roots ?? const <RootChoice>[];
    for (final option in roots) {
      if (option.isPrimary) return option.root;
    }
    return roots.isEmpty ? null : roots.first.root;
  }

  Future<void> _loadAdminMode() async {
    final enabled = await adminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  Future<void> _loadOccurrenceVerseMode() async {
    final enabled = await occurrenceVerseEnglishOnlyEnabled();
    if (mounted) setState(() => _occurrenceVerseEnglishOnly = enabled);
  }

  Future<void> _setOccurrenceVerseMode(bool enabled) async {
    setState(() => _occurrenceVerseEnglishOnly = enabled);
    await setOccurrenceVerseEnglishOnlyEnabled(enabled);
  }

  Future<void> _openLexiconEditor(WordInfo info) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LexiconEntryOverrideEditor(
        surface: info.word,
        // The override records what this surface resolves to, which is the
        // parse's root — not whichever of a name's roots is being browsed.
        root: _primaryRoot() ?? info.root,
        gloss: info.gloss,
        readerGloss: widget.readerGloss,
      ),
    );
    if (!mounted || message == null) return;
    _requestInfo();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<String, Object?> _issueContext(WordInfo info) => {
    if (widget.reportContext != null) 'reader': widget.reportContext,
    'lookup': {
      'word': widget.word,
      'syriac': widget.syriac,
      if (widget.bdbId != null) 'bdbId': widget.bdbId,
    },
    'result': {
      'found': info.found,
      'word': info.word,
      'root': info.root,
      'gloss': info.gloss,
      'morphology': {
        if (info.gender != null) 'gender': info.gender,
        if (info.partOfSpeech != null) 'partOfSpeech': info.partOfSpeech,
        if (info.person != null) 'person': info.person,
        if (info.number != null) 'number': info.number,
        if (info.state != null) 'state': info.state,
        if (info.tense != null) 'tense': info.tense,
        if (info.form != null) 'form': info.form,
        if (info.prefix != null) 'prefix': info.prefix,
        if (info.suffix != null) 'suffix': info.suffix,
        if (info.prepositions != null) 'prepositions': info.prepositions,
        'article': info.article,
        'vavCon': info.vavCon,
      },
      'lexemes': [
        for (final lexeme in info.lexemes)
          {
            'headword': lexeme.headword,
            'posCategory': lexeme.posCategory,
            if (lexeme.isCurrent) 'isCurrent': true,
            'entries': [
              for (final entry in lexeme.entries)
                {
                  'gloss': entry.gloss,
                  'posCategory': entry.posCategory,
                  'source': entry.source,
                  if (entry.homograph.isNotEmpty) 'homograph': entry.homograph,
                },
            ],
          },
      ],
    },
  };

  @override
  void dispose() {
    _occPrefetch?.cancel();
    _tabController.animation?.removeListener(_onTabAnimation);
    _tabController.dispose();
    _dockedScrollController.dispose();
    _sub?.cancel();
    _occSub?.cancel();
    _verseTexts.dispose();
    final source = _proximitySource;
    if (source != null) {
      widget.proximity
        ?..removeListener(_onProximityChanged)
        ..unregister(source);
    }
    super.dispose();
  }

  void _onBibleRefTap(BuildContext context, String href) {
    final parsed = _parseBibleRef(href);
    if (parsed == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => BibleRefPreviewDialog(
        displayRef: href,
        bookIndex: parsed.bookIndex,
        chapter: parsed.chapter,
        verse: parsed.verse,
        onNavigate: widget.onNavigateToPassage == null
            ? null
            : () => widget.onNavigateToPassage!(
                parsed.bookIndex,
                parsed.chapter,
                parsed.verse,
              ),
      ),
    );
  }

  void _onXrefTap(String bdbId, String headword) =>
      _openWordInfo(headword, bdbId: bdbId);

  /// A Klein or Jastrow link opens its target in a preview over the sheet, as
  /// a Bible reference does. The target's own links open further previews
  /// on top, so a chain of derivations can be followed and walked back.
  void _onDictionaryLinkTap(
    BuildContext context,
    String source,
    String key,
    String text,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _DictionaryEntryPreviewDialog(
        source: source,
        entryKey: key,
        linkText: text,
        send: widget.sendDictionaryRequest,
        onBibleRefTap: (href) => _onBibleRefTap(context, href),
        onXrefTap: _onXrefTap,
        onDictionaryLinkTap: (source, key, text) =>
            _onDictionaryLinkTap(ctx, source, key, text),
      ),
    );
  }

  // A lexical form uses the same surface lookup as a word in the reader.
  // Only dictionary cross-references supply an entry ID. Do not carry the
  // original token's root, gloss, or location into the new word's analysis.
  // Stacking sheets preserves the trail when returning to the original word.
  void _openWordInfo(String word, {String? bdbId}) {
    final open = widget.onOpenWord;
    if (open != null) {
      open(word, bdbId);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordInfoSheet(
        word: word,
        syriac: bdbId == null ? widget.syriac : false,
        bdbId: bdbId,
        sendInfoRequest: widget.sendInfoRequest,
        sendOccurrencesRequest: widget.sendOccurrencesRequest,
        sendVerseTextsRequest: widget.sendVerseTextsRequest,
        sendDictionaryRequest: widget.sendDictionaryRequest,
        isStudyBookmarked: widget.isStudyBookmarked,
        onToggleStudyBookmark: widget.onToggleStudyBookmark,
        useEnglishBookNames: widget.useEnglishBookNames,
        reportContext: {
          ...?widget.reportContext,
          if (bdbId != null)
            'crossReference': {'bdbId': bdbId, 'headword': word}
          else
            'lexicalForm': word,
        },
        onNavigateToPassage: widget.onNavigateToPassage == null
            ? null
            : (bi, chapter, verse) {
                Navigator.pop(ctx);
                widget.onNavigateToPassage!(bi, chapter, verse);
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;

    if (widget.docked) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: SelectionArea(
          child: info == null
              ? _buildLoading(context)
              : _buildContent(context, _dockedScrollController, info),
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SelectionArea(
                  child: info == null
                      ? _buildLoading(context)
                      : _buildContent(context, scrollController, info),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// What the sheet shows before the lexicon reply lands: the tapped word and
  /// the gloss the reader already had, in the places the reply will fill, so
  /// the sheet is readable at once even when Rust is busy with earlier work.
  Widget _buildLoading(BuildContext context) {
    final theme = Theme.of(context);
    final gloss = widget.readerGloss ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  gloss,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.word,
                style: TextStyle(
                  fontFamily: 'Noto Serif Hebrew',
                  fontFamilyFallback: const ['Cardo'],
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
        const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    ScrollController scrollController,
    WordInfo info,
  ) {
    final theme = Theme.of(context);

    if (!info.found) {
      // No lexicon data, but the word is still a surface form of the text —
      // show its occurrences so the sheet stays useful (and the reader can
      // study the word in its other contexts).
      final occ = _occ;
      final occurrences = occ == null
          ? const <_VerseOccurrence>[]
          : _flatVerses(occ);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              children: [
                Text(
                  widget.word,
                  style: TextStyle(
                    fontFamily: 'Cardo',
                    fontFamilyFallback: const ['Noto Serif Hebrew'],
                    fontSize: 28,
                    color: theme.colorScheme.onSurface,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                if (widget.onToggleStudyBookmark != null)
                  _studyBookmarkMenu(info),
                const SizedBox(height: 8),
                Text(
                  'Not found in lexicon',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: occ == null
                ? const Center(child: CircularProgressIndicator())
                : occurrences.isEmpty
                ? const SizedBox.shrink()
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      8 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    // Header plus one row per verse, built on demand: an
                    // unparsed but common surface still has a long list.
                    itemCount: occurrences.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              'Occurrences',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : _occurrenceVerseRow(occurrences[i - 1]),
                  ),
          ),
        ],
      );
    }

    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (widget.onToggleStudyBookmark != null) ...[
                    _studyBookmarkMenu(info),
                    const SizedBox(width: 8),
                  ],
                  if (_adminMode) ...[
                    if (!widget.syriac && widget.bdbId == null) ...[
                      IconButton(
                        onPressed: () => _openLexiconEditor(info),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit this lexicon override',
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                    ],
                    IssueReportButton(
                      source: 'word_info',
                      contextData: _issueContext(info),
                      tooltip: 'Log an issue or idea about this word',
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (info.gloss.isNotEmpty)
                    Expanded(
                      child: Text(
                        info.gloss,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        info.word,
                        style: TextStyle(
                          fontFamily: 'Noto Serif Hebrew',
                          fontFamilyFallback: const ['Cardo'],
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                      if (info.roots.length > 1)
                        _rootSelector(context, info)
                      else if (info.root.isNotEmpty)
                        Text(
                          info.root,
                          style: TextStyle(
                            fontFamily: 'Noto Serif Hebrew',
                            fontFamilyFallback: const ['Cardo'],
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (info.partOfSpeech != null)
                    _chip(context, 'Part of speech', info.partOfSpeech!),
                  if (info.gender != null)
                    _chip(context, 'Gender', info.gender!),
                  if (info.person != null)
                    _chip(context, 'Person', info.person!),
                  if (info.number != null)
                    _chip(context, 'Number', info.number!),
                  if (info.state != null) _chip(context, 'State', info.state!),
                  if (info.tense != null) _chip(context, 'Tense', info.tense!),
                  if (info.form != null) _chip(context, 'Form', info.form!),
                  if (info.prefix != null)
                    _chip(context, 'Prefix', info.prefix!),
                  if (info.suffix != null)
                    _chip(context, 'Suffix', info.suffix!),
                  if (info.prepositions != null)
                    _chip(context, 'Prep', info.prepositions!),
                  if (info.article) _chip(context, 'Article', 'ה'),
                  if (info.vavCon) _chip(context, 'Vav', 'consecutive'),
                ],
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Lexicon', height: 32),
            Tab(text: 'Occurrences', height: 32),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildLexiconTab(context, scrollController, info, bottomPad),
              _buildOccurrencesTab(context, info, bottomPad),
            ],
          ),
        ),
      ],
    );
  }

  bool _lexemeExpanded(int i, LexemeSummary lexeme) =>
      lexeme.isCurrent != _toggledLexemes.contains(i);

  /// The gloss a folded lexeme reads as: the longest of its entries', which
  /// tends to be the fullest. Cross-references ("see שׂרה", filed under another
  /// part of speech) and Jastrow's clipped citation excerpts (ending in "…")
  /// give way to a real definition when the lexeme has one.
  static String _lexemeGloss(LexemeSummary lexeme) {
    final entries = lexeme.entries.where((e) => e.gloss.isNotEmpty);
    for (final keep in <bool Function(BdbSummary)>[
      (e) => e.posCategory == lexeme.posCategory && !e.gloss.endsWith('…'),
      (e) => !e.gloss.endsWith('…'),
      (e) => true,
    ]) {
      final candidates = entries.where(keep);
      if (candidates.isNotEmpty) {
        return candidates
            .reduce((a, b) => b.gloss.length > a.gloss.length ? b : a)
            .gloss;
      }
    }
    return '';
  }

  Widget _buildLexiconTab(
    BuildContext context,
    ScrollController scrollController,
    WordInfo info,
    double bottomPad,
  ) {
    final theme = Theme.of(context);

    // The lexeme's headword, which opens that word's own sheet.
    Widget headwordButton(String headword) => TextButton(
      onPressed: headword.isEmpty ? null : () => _openWordInfo(headword),
      child: Text(
        _normalizeHebrewCombining(headword),
        style: TextStyle(
          fontFamily: 'Noto Serif Hebrew',
          fontFamilyFallback: const ['Cardo'],
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
        textDirection: TextDirection.rtl,
      ),
    );

    // One collapsible lexicon entry row, badged with the lexicon it comes
    // from and numbered with the source's own homograph mark, which tells its
    // entries for the word apart. Its (lexeme, entry) index pair keys its
    // expansion state, so it stays stable when the lexemes are split into the
    // part-of-speech groups below. [headword] ends the row when the entry is
    // its lexeme's only one, which then needs no heading of its own.
    Widget buildBdbRow((int, int) i, BdbSummary e, {String? headword}) {
      final expanded = _expandedBdb.contains(i);
      final lang = LexiconPeriodLabel.of(e.lang);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() {
              if (expanded) {
                _expandedBdb.remove(i);
              } else {
                _expandedBdb.add(i);
              }
            }),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: headword == null ? 10 : 6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  LexiconSourceBadge(source: e.source),
                  if (e.homograph.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(
                      e.homograph,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (lang != null) ...[const SizedBox(width: 4), lang],
                  if (e.gloss.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e.gloss, style: theme.textTheme.bodyMedium),
                    ),
                  ] else
                    const Spacer(),
                  if (headword != null) ...[
                    const SizedBox(width: 8),
                    headwordButton(headword),
                  ],
                ],
              ),
            ),
          ),
          if (expanded && e.contentJson.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BdbContent(
                contentJson: e.contentJson,
                source: e.source,
                onBibleRefTap: (href) => _onBibleRefTap(context, href),
                onXrefTap: _onXrefTap,
                onDictionaryLinkTap: (source, key, text) =>
                    _onDictionaryLinkTap(context, source, key, text),
              ),
            ),
        ],
      );
    }

    // One word of the root family: its lone entry as a single row, or its
    // headword over every lexicon's entries for it, indented beneath. An entry
    // spelled otherwise (a bare root, or a form that only refers to this
    // word) keeps its own headword on its row.
    Widget buildLexemeRows(int i, LexemeSummary lexeme) {
      if (lexeme.entries.length == 1) {
        return buildBdbRow(
          (i, 0),
          lexeme.entries.single,
          headword: lexeme.headword,
        );
      }
      final expanded = _lexemeExpanded(i, lexeme);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('lexeme-group-$i'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() {
              if (!_toggledLexemes.remove(i)) _toggledLexemes.add(i);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: '${lexeme.entries.length} entries',
                    child: Text(
                      '×${lexeme.entries.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Folded, the group reads as its fullest gloss; open, its
                  // entries below give their own.
                  Expanded(
                    child: expanded
                        ? Divider(color: theme.colorScheme.outlineVariant)
                        : Text(
                            _lexemeGloss(lexeme),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                  ),
                  const SizedBox(width: 8),
                  headwordButton(lexeme.headword),
                ],
              ),
            ),
          ),
          if (expanded)
            Container(
              margin: const EdgeInsetsDirectional.only(start: 8, bottom: 4),
              padding: const EdgeInsetsDirectional.only(start: 4),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (j, e) in lexeme.entries.indexed)
                    buildBdbRow(
                      (i, j),
                      e,
                      headword: _sameHeadword(e.headword, lexeme.headword)
                          ? null
                          : e.headword,
                    ),
                ],
              ),
            ),
        ],
      );
    }

    // The looked-up word's own lexeme (SEDRA files a Peshitta word under one)
    // is tinted, so it stands out among its root's family.
    Widget buildLexeme(int i, LexemeSummary lexeme) {
      final row = buildLexemeRows(i, lexeme);
      if (!lexeme.isCurrent) return row;
      return Container(
        key: ValueKey('current-lexeme-$i'),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
        ),
        child: row,
      );
    }

    Widget sectionHeading(String label) => Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    // Head a root's lexemes under their grammatical class. Proper names in
    // particular crowd out the root's actual meaning, so they sit last under
    // their own heading. `posCategory` is the BDB part-of-speech bucket set in
    // the hub crate; the order here fixes how the groups stack.
    const groups = <(String, String)>[
      ('root', 'Roots'),
      ('verb', 'Verbs'),
      ('noun', 'Nouns'),
      ('adjective', 'Adjectives'),
      ('adverb', 'Adverbs'),
      ('proper', 'Proper nouns'),
      ('other', 'Other'),
    ];

    final rows = <Widget>[];
    for (final (key, label) in groups) {
      final lexemes = info.lexemes.indexed
          .where((p) => p.$2.posCategory == key)
          .toList();
      if (lexemes.isEmpty) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(sectionHeading(label));
      rows.add(const SizedBox(height: 4));
      rows.addAll(lexemes.map((p) => buildLexeme(p.$1, p.$2)));
    }

    // A resolved word with no dictionary entry (curated function words such
    // as בָּהּ bridge to no BDB lexeme) would otherwise render a blank tab.
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No dictionary entry for this form.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + bottomPad),
      children: [...rows],
    );
  }

  /// A filter header and a canon distribution over a merged-by-verse list,
  /// the same whichever testament the word was read in: its root's tokens
  /// across the canon, filtered by surface form, by lexeme, by parse and by
  /// book.
  Widget _buildOccurrencesTab(
    BuildContext context,
    WordInfo info,
    double bottomPad,
  ) {
    // Occurrences are fetched lazily when this tab is first opened; show a
    // spinner until the scan completes.
    final occ = _occ;
    if (occ == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (occ.occurrences.isEmpty && occ.tokens.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    // Edge data (e.g. a word with no readable root) has no per-token tagging —
    // fall back to a flat list of the surface's own verses.
    if (occ.tokens.isEmpty) {
      return _occurrenceVerseList(_flatVerses(occ), bottomPad: bottomPad);
    }

    final forms = _forms;

    // Each filter's own inventory is counted over what the *other* filters
    // admit, so a number says what selecting that entry would actually yield.
    // The bar is counted here; the sheet counts forms and parses itself, since
    // those have to move as selections change inside it.
    //
    // A common root runs to thousands of tokens, and this tab is rebuilt for
    // every toggle, so each derived list is memoised on what it depends on.
    final exactForm = _exactFormKey();
    final tappedParse = _tappedParse();
    final (:inScope, :scopeCounts) = _tokenScope(occ);
    final scopes = [
      if (exactForm != null) _FormScope.exact,
      if (tappedParse != null) _FormScope.parse,
      _FormScope.all,
    ];
    final proximity = _proximityResult();
    final Map<int, int> bookCounts;
    final List<_VerseOccurrence> verses;
    final int hits;
    if (proximity == null) {
      bookCounts = _tokenMatches(occ).bookCounts;
      final shown = _tokensShown(occ);
      verses = shown.verses;
      hits = shown.hits;
    } else {
      // The distribution counts the combined results, and the book filter
      // narrows them, as it narrows the word's own list.
      bookCounts = _proximityBookCounts.get([proximity], () {
        final counts = <int, int>{};
        for (final v in proximity.verses) {
          counts[v.book] = (counts[v.book] ?? 0) + 1;
        }
        return counts;
      });
      verses = _markPassageStarts(
        proximity.verses.where((v) => _passesBook(v.book)).toList(),
      );
      hits = verses.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // "All forms" alone would be no choice at all.
              if (scopes.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: _FormScopeToggle(
                    scopes: scopes,
                    // No segment is lit when the filter sheet has cut some
                    // other way; any tap replaces that choice.
                    selected: _currentScope(exactForm, tappedParse),
                    counts: scopeCounts,
                    onChanged: (scope) =>
                        _applyScope(scope, exactForm, tappedParse),
                  ),
                ),
              Row(
                children: [
                  Flexible(
                    child: ActionChip(
                      avatar: const Icon(Icons.filter_list, size: 18),
                      label: Text(
                        _filterSummary(forms, exactForm: exactForm),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Cardo',
                          fontFamilyFallback: ['Noto Serif Hebrew'],
                        ),
                      ),
                      onPressed: () =>
                          _openFilterSheet(context, occurrences: inScope),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      proximity == null
                          ? _occurrenceCountLabel(verses.length, hits)
                          : _proximityCountLabel(verses),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (_proximityAvailable) _proximityToggle(),
                  IconButton(
                    tooltip: 'Copy references',
                    icon: const Icon(Icons.copy_all_outlined, size: 20),
                    onPressed: verses.isEmpty
                        ? null
                        : () => _copyReferences(verses),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minHeight: 40),
                  ),
                  IconButton(
                    tooltip: _occurrenceVerseEnglishOnly
                        ? 'Show Hebrew verse text'
                        : 'Show English-only verse text',
                    icon: VerseModeIcon(
                      englishOnly: _occurrenceVerseEnglishOnly,
                    ),
                    onPressed: () {
                      _setOccurrenceVerseMode(!_occurrenceVerseEnglishOnly);
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerRight,
                    constraints: const BoxConstraints(minHeight: 40),
                  ),
                ],
              ),
              if (proximity != null) _proximityControls(context),
              const SizedBox(height: 2),
              _CanonDistribution(
                countsByBook: bookCounts,
                selectedBooks: _books,
                useEnglishBookNames: widget.useEnglishBookNames,
                onSelect: (books) => setState(() {
                  _books
                    ..clear()
                    ..addAll(books);
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: proximity != null && verses.isEmpty
              ? _proximityEmpty(context, proximity)
              : verses.isEmpty
              ? Center(
                  child: Text(
                    'No occurrences match this filter',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : _occurrenceVerseList(verses, bottomPad: bottomPad),
        ),
      ],
    );
  }

  bool _passesFormAndParse(Occurrence o) =>
      (_forms.isEmpty || _forms.contains(o.surface)) &&
      _parse.entries.every(
        (selection) =>
            selection.value.isEmpty ||
            selection.value.contains(selection.key.of(o)),
      );

  bool _passesBook(int book) => _books.isEmpty || _books.contains(book);

  /// The form and parse filters as a value, for memo keys: the sets are
  /// mutated in place, so their identity says nothing about their contents.
  String get _formParseKey => [
    (_forms.toList()..sort()).join('\u0001'),
    for (final dimension in _ParseDimension.values)
      ((_parse[dimension] ?? const <String>{}).toList()..sort()).join('\u0001'),
  ].join('\u0002');

  /// The book filter as a value, as [_formParseKey] is.
  String get _booksKey => (_books.toList()..sort()).join(',');

  final _tokenMatchesMemo =
      _Memo<
        ({
          List<Occurrence> matching,
          ({List<_VerseOccurrence> verses, int hits}) merged,
          Map<int, int> bookCounts,
        })
      >();
  final _tokenScopeMemo =
      _Memo<({List<Occurrence> inScope, Map<_FormScope, int> scopeCounts})>();
  final _tokensShownMemo = _Memo<({List<_VerseOccurrence> verses, int hits})>();
  final _flatVersesMemo = _Memo<List<_VerseOccurrence>>();
  final _proximityHitsMemo = _Memo<List<ProximityHit>?>();
  final _proximityResultMemo = _Memo<_ProximityResult>();
  final _proximityBookCounts = _Memo<Map<int, int>>();

  /// The tokens the form and parse filters admit, merged by verse, with their
  /// per-book token counts for the distribution bar.
  ({
    List<Occurrence> matching,
    ({List<_VerseOccurrence> verses, int hits}) merged,
    Map<int, int> bookCounts,
  })
  _tokenMatches(WordOccurrences occ) =>
      _tokenMatchesMemo.get([occ, _formParseKey], () {
        final matching = occ.tokens.where(_passesFormAndParse).toList();
        final bookCounts = <int, int>{};
        for (final o in matching) {
          bookCounts[o.book] = (bookCounts[o.book] ?? 0) + 1;
        }
        return (
          matching: matching,
          merged: _mergeTokens(matching),
          bookCounts: bookCounts,
        );
      });

  /// The tokens the book filter admits, and what each scope would list among
  /// them: a scope replaces the form and parse filters but keeps the book one.
  ({List<Occurrence> inScope, Map<_FormScope, int> scopeCounts}) _tokenScope(
    WordOccurrences occ,
  ) => _tokenScopeMemo.get([occ, _booksKey], () {
    final exactForm = _exactFormKey();
    final tappedParse = _tappedParse();
    final inScope = occ.tokens.where((o) => _passesBook(o.book)).toList();
    final scopeCounts = {for (final scope in _FormScope.values) scope: 0};
    for (final o in inScope) {
      scopeCounts[_FormScope.all] = scopeCounts[_FormScope.all]! + 1;
      if (o.surface == exactForm) {
        scopeCounts[_FormScope.exact] = scopeCounts[_FormScope.exact]! + 1;
      }
      if (tappedParse != null &&
          tappedParse.entries.every((e) => e.key.of(o) == e.value)) {
        scopeCounts[_FormScope.parse] = scopeCounts[_FormScope.parse]! + 1;
      }
    }
    return (inScope: inScope, scopeCounts: scopeCounts);
  });

  /// The list as shown: every filter applied, merged by verse so a verse
  /// appears once with all its matches highlighted.
  ({List<_VerseOccurrence> verses, int hits}) _tokensShown(
    WordOccurrences occ,
  ) {
    final matches = _tokenMatches(occ);
    if (_books.isEmpty) return matches.merged;
    return _tokensShownMemo.get([
      matches.matching,
      _booksKey,
    ], () => _mergeTokens(matches.matching.where((o) => _passesBook(o.book))));
  }

  /// Tokens merged by verse, in canonical order, so a verse appears once with
  /// all its matches highlighted; [hits] counts the tokens.
  ({List<_VerseOccurrence> verses, int hits}) _mergeTokens(
    Iterable<Occurrence> tokens,
  ) {
    final byVerse = <int, _VerseOccurrence>{};
    var hits = 0;
    for (final o in tokens) {
      hits++;
      final key = _verseKey(o.book, o.chapter, o.verse);
      final existing = byVerse[key];
      if (existing == null) {
        byVerse[key] = _VerseOccurrence(
          book: o.book,
          chapter: o.chapter,
          verse: o.verse,
          words: [o.surface],
          positions: [o.position],
        );
      } else {
        if (!existing.words.contains(o.surface)) existing.words.add(o.surface);
        existing.positions.add(o.position);
      }
    }
    return (verses: _sortCanonically(byVerse.values.toList()), hits: hits);
  }

  static int _verseKey(int book, int chapter, int verse) =>
      (book << 16) | (chapter << 8) | verse;

  static List<_VerseOccurrence> _sortCanonically(
    List<_VerseOccurrence> verses,
  ) => verses
    ..sort((a, b) {
      if (a.book != b.book) return a.book.compareTo(b.book);
      if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
      return a.verse.compareTo(b.verse);
    });

  /// The verses this word contributes to a proximity search: what its own
  /// list shows under its form, parse, or lexeme filters, before any book
  /// filter. Null until the occurrences have loaded.
  ///
  /// Memoised on the verses it is made from, so every pane reading it gets the
  /// same list back until this word's filters change — which is also what
  /// lets [_proximityResult] tell that nothing needs recombining.
  List<ProximityHit>? _proximityHits() {
    final occ = _occ;
    if (occ == null) return null;
    final verses = _ownVerses(occ);
    return _proximityHitsMemo.get([verses], () {
      return [for (final v in verses) v.toHit()];
    });
  }

  /// This word's own list under its form, parse, or lexeme filters, before
  /// any book filter.
  List<_VerseOccurrence> _ownVerses(WordOccurrences occ) {
    if (occ.tokens.isNotEmpty) {
      return _tokenMatches(occ).merged.verses;
    }
    return _flatVerses(occ);
  }

  /// The surface's own verses, for data with no per-token tagging.
  List<_VerseOccurrence> _flatVerses(WordOccurrences occ) =>
      _flatVersesMemo.get([occ], () {
        return [
          for (final o in occ.occurrences)
            _VerseOccurrence(
              book: o.book,
              chapter: o.chapter,
              verse: o.verse,
              words: [widget.word],
            ),
        ];
      });

  /// A proximity search can only be offered with another word pane open.
  bool get _proximityAvailable {
    final proximity = widget.proximity;
    final id = widget.proximityId;
    return proximity != null &&
        id != null &&
        proximity.sources.any((source) => source.id != id);
  }

  /// The combined results when the proximity search is on: this word's list
  /// against every other included pane. Null when it is off.
  ///
  /// Every pane's hits are memoised, so the combination is recomputed only
  /// when one of them, or the distance, actually changes — not on each of the
  /// rebuilds a filter tap in any pane sets off in all of them.
  _ProximityResult? _proximityResult() {
    final proximity = widget.proximity;
    if (proximity == null || !proximity.enabled || !_proximityAvailable) {
      return null;
    }
    final others = [
      for (final source in proximity.sources)
        if (source.id != widget.proximityId && proximity.isIncluded(source.id))
          source,
    ];
    if (others.isEmpty) return const _ProximityResult.noPartners();
    final own = _proximityHits();
    if (own == null) return const _ProximityResult.loading();
    final terms = [own];
    for (final source in others) {
      final hits = source.hits();
      if (hits == null) return const _ProximityResult.loading();
      terms.add(hits);
    }
    return _proximityResultMemo.get([proximity.distance, ...terms], () {
      return _ProximityResult([
        for (final match in proximityMatches(terms, proximity.distance))
          _VerseOccurrence(
            book: match.book,
            chapter: match.chapter,
            verse: match.verse,
            words: match.words,
            positions: match.positions,
            passage: match.passage,
          ),
      ]);
    });
  }

  /// Marks where each passage of a verse-window or chapter search begins, so
  /// the list separates them. Verses are passages of their own otherwise.
  ///
  /// The verses are the memoised result's own rows, so every flag is set
  /// afresh: the book filter may have put a different verse first.
  List<_VerseOccurrence> _markPassageStarts(List<_VerseOccurrence> verses) {
    if (widget.proximity?.distance == ProximityDistance.sameVerse) {
      return verses;
    }
    if (verses.isNotEmpty) verses.first.passageStart = false;
    for (var i = 1; i < verses.length; i++) {
      verses[i].passageStart = verses[i].passage != verses[i - 1].passage;
    }
    return verses;
  }

  String _proximityCountLabel(List<_VerseOccurrence> verses) {
    final versePart = '${verses.length} verse${verses.length == 1 ? '' : 's'}';
    if (widget.proximity?.distance == ProximityDistance.sameVerse) {
      return versePart;
    }
    final passages = verses.map((v) => v.passage).toSet().length;
    return '$passages passage${passages == 1 ? '' : 's'} · $versePart';
  }

  Widget _proximityToggle() {
    final enabled = widget.proximity!.enabled;
    return IconButton(
      tooltip: enabled
          ? 'Show only this word'
          : 'Find passages with the other open words',
      isSelected: enabled,
      icon: const Icon(Icons.join_inner, size: 20),
      onPressed: () => widget.proximity!.enabled = !enabled,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minHeight: 40),
    );
  }

  /// Which open words take part, and how close they must stand. This word is
  /// always part of its own search, so its chip is shown on but fixed.
  Widget _proximityControls(BuildContext context) {
    final theme = Theme.of(context);
    final proximity = widget.proximity!;
    const hebrew = TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: ['Noto Serif Hebrew'],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final source in proximity.sources)
            FilterChip(
              key: ValueKey('proximity-word-${source.id}'),
              label: Text(
                source.label(),
                style: hebrew,
                textDirection: TextDirection.rtl,
              ),
              selected:
                  source.id == widget.proximityId ||
                  proximity.isIncluded(source.id),
              visualDensity: VisualDensity.compact,
              tooltip: source.id == widget.proximityId
                  ? 'This word'
                  : proximity.isIncluded(source.id)
                  ? 'Leave this word out'
                  : 'Include this word',
              onSelected: source.id == widget.proximityId
                  ? null
                  : (included) => proximity.setIncluded(source.id, included),
            ),
          DropdownButton<ProximityDistance>(
            key: const ValueKey('proximity-distance'),
            value: proximity.distance,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: theme.textTheme.labelLarge,
            items: [
              for (final distance in ProximityDistance.options)
                DropdownMenuItem(value: distance, child: Text(distance.label)),
            ],
            onChanged: (distance) {
              if (distance != null) proximity.distance = distance;
            },
          ),
        ],
      ),
    );
  }

  Widget _proximityEmpty(BuildContext context, _ProximityResult result) {
    if (result.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          result.noPartners
              ? 'Include another open word to find passages with it'
              : 'These words never stand this close together',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// The active filter, in the order the sheet's tabs offer it. Nothing selected
  /// is the tab's starting state, and covers every dimension at once.
  ///
  /// A single selection reads as itself ("Qal", "Piel · plural"), so the chip
  /// says what is being looked at rather than how many boxes are ticked; a
  /// dimension with several selected collapses to a count, since spelling them
  /// all out would not fit.
  String _filterSummary(Set<String> forms, {String? exactForm}) {
    // The scope toggle already says "exact match", so the chip need not.
    final exact =
        exactForm != null && forms.length == 1 && forms.contains(exactForm);
    final parts = <String>[
      for (final dimension in _ParseDimension.values)
        if (_parse[dimension] case final selected? when selected.isNotEmpty)
          if (selected.length == 1)
            selected.first.toLowerCase()
          else
            '${selected.length} ${dimension.label.toLowerCase()}',
      if (!exact && forms.length == 1)
        forms.first
      else if (forms.length > 1)
        '${forms.length} forms',
      ?_booksSummary(),
    ];
    if (parts.isEmpty) return exact ? 'Filter' : 'All occurrences';
    return parts.join(' · ');
  }

  /// The book filter's part of a filter summary; null when it admits every
  /// book.
  String? _booksSummary() {
    if (_books.isEmpty) return null;
    if (_books.length > 1) return '${_books.length} books';
    return bookDisplayName(
      _books.first - 1,
      useEnglish: widget.useEnglishBookNames,
    );
  }

  /// Verses *and* tokens: a root can stand twice in one verse, and a reader
  /// asking how common a word is means the second number.
  static String _occurrenceCountLabel(int verses, int hits) {
    final versePart = '$verses verse${verses == 1 ? '' : 's'}';
    return hits == verses ? versePart : '$versePart · $hits×';
  }

  Future<void> _copyReferences(List<_VerseOccurrence> verses) async {
    final refs = verses
        .map((v) {
          final bookIndex = v.book - 1;
          final name = bookIndex >= 0 && bookIndex < kBooks.length
              ? bookDisplayName(
                  bookIndex,
                  useEnglish: widget.useEnglishBookNames,
                )
              : 'Book ${v.book}';
          return '$name ${v.chapter}:${v.verse}';
        })
        .join('\n');
    await Clipboard.setData(ClipboardData(text: refs));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${verses.length} reference${verses.length == 1 ? '' : 's'}',
        ),
      ),
    );
  }

  /// The filter sheet: forms on one tab, parses on the other, each searchable
  /// because a common root has hundreds of forms (בוא alone has 320) and a wall
  /// of unsorted checkboxes is not a filter anyone can use.
  Future<void> _openFilterSheet(
    BuildContext context, {
    required List<Occurrence> occurrences,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _OccurrenceFilterSheet(
        occurrences: occurrences,
        selectedForms: _forms,
        selectedParse: _parse,
        onChanged: (forms, parse) {
          setState(() {
            _forms
              ..clear()
              ..addAll(forms);
            _parse
              ..clear()
              ..addAll(parse);
          });
          _occurrenceFilterChanged();
        },
      ),
    );
  }

  /// One row of an occurrence list. Built on demand by the lazy lists below, so
  /// only the verses on screen ever ask for their text.
  Widget _occurrenceVerseRow(_VerseOccurrence v) {
    final bookIndex = v.book - 1;
    final bookName = bookIndex >= 0 && bookIndex < kBooks.length
        ? bookDisplayName(bookIndex, useEnglish: widget.useEnglishBookNames)
        : 'Book ${v.book}';
    final key = ValueKey('${v.book}:${v.chapter}:${v.verse}');
    final row = OccurrenceVerseRow(
      key: v.passageStart ? null : key,
      cache: _verseTexts,
      displayRef: '$bookName ${v.chapter}:${v.verse}',
      bookIndex: bookIndex,
      chapter: v.chapter,
      verse: v.verse,
      highlightWords: v.words,
      positions: v.positions,
      isCurrent: _isCurrentVerse(v),
      englishOnly: _occurrenceVerseEnglishOnly,
      useEnglishBookNames: widget.useEnglishBookNames,
      onTap: widget.onNavigateToPassage == null
          ? null
          : () => widget.onNavigateToPassage!(bookIndex, v.chapter, v.verse),
    );
    if (!v.passageStart) return row;
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const Divider(height: 17), row],
    );
  }

  /// Whether this is the verse the reader was on when the sheet opened.
  bool _isCurrentVerse(_VerseOccurrence v) =>
      widget.book == v.book &&
      widget.chapter == v.chapter &&
      widget.verse == v.verse;

  /// An occurrence list as a lazy, scrollable list opened at the verse the
  /// reader came from.
  ///
  /// Two slivers meeting at a zero-height centre: the verses before the anchor
  /// grow backwards into negative scroll offsets, so the list opens on the
  /// reader's own verse with no scroll-offset correction, however tall the rows
  /// above it turn out to be. Same anchoring the reader itself uses.
  Widget _occurrenceVerseList(
    List<_VerseOccurrence> verses, {
    required double bottomPad,
  }) {
    final anchor = verses.indexWhere(_isCurrentVerse);
    final centre = anchor < 0 ? 0 : anchor;
    // Keyed on the anchor, so changing a filter (and with it the anchor's index)
    // builds a fresh viewport rather than keeping a scroll offset that now
    // points at some other verse.
    final identity = '$centre-${verses.length}';
    return CustomScrollView(
      key: ValueKey('occurrences-$identity'),
      center: ValueKey('occurrence-centre-$identity'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.builder(
            itemCount: centre,
            // Children before the centre grow in reverse order, so feed this
            // list from the end for the verses to read downwards on screen.
            itemBuilder: (context, i) =>
                _occurrenceVerseRow(verses[centre - 1 - i]),
          ),
        ),
        SliverToBoxAdapter(
          key: ValueKey('occurrence-centre-$identity'),
          child: const SizedBox.shrink(),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          sliver: SliverList.builder(
            itemCount: verses.length - centre,
            itemBuilder: (context, i) =>
                _occurrenceVerseRow(verses[centre + i]),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 8 + bottomPad)),
      ],
    );
  }

  /// The root line, when the word has more than one root to be read under.
  ///
  /// A compound name belongs to each of its elements — אֱלִיעֶזֶר is אל "god" and
  /// עזר "help" — and BDB could only print it under the first. Tapping a root
  /// moves both tabs to it: its lexeme tree, and its concordance with the name
  /// standing among the other words built from it.
  Widget _rootSelector(BuildContext context, WordInfo info) {
    final theme = Theme.of(context);
    final selected = _selectedRoot ?? _primaryRoot();
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      children: [
        for (final option in info.roots)
          Tooltip(
            message: option.gloss.isEmpty
                ? 'Read ${option.root} as this word’s root'
                : '${option.root} — ${option.gloss}',
            child: InkWell(
              onTap: () => _selectRoot(option.root),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: option.root == selected
                      ? theme.colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: option.root == selected
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                child: Text(
                  option.root,
                  style: TextStyle(
                    fontFamily: 'Noto Serif Hebrew',
                    fontFamilyFallback: const ['Cardo'],
                    fontSize: 13,
                    color: option.root == selected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// One dimension of the parse filter.
///
/// The tab filters on the components of a parse rather than on whole labels: a
/// verb root has a dozen stems times half a dozen tenses times nine
/// person/gender/number cells, and a reader after "every Hiphil" or "every
/// plural participle" should not have to find that exact combination in a list.
///
/// Hebrew and Aramaic tokens answer in one vocabulary, so a selection cuts
/// across both testaments. Their stems keep their own names under [stem];
/// [stemFamily] is where they meet (Qal and Peal are both Simple, Hiphil and
/// Aphel both Causative). [lexeme] is SEDRA's, carried by NT tokens only; a
/// dimension with no values among the tokens is not offered.
enum _ParseDimension {
  partOfSpeech('Part of speech'),
  lexeme('Lexeme'),
  stemFamily('Stem family'),
  stem('Stem'),
  tense('Tense'),
  person('Person'),
  gender('Gender'),
  number('Number'),
  state('State');

  const _ParseDimension(this.label);

  /// Section heading in the filter sheet.
  final String label;

  /// This dimension's value for a token, empty where the analysis has none (an
  /// infinitive has no person, a verb no state).
  String of(Occurrence o) => switch (this) {
    _ParseDimension.partOfSpeech => o.parse.partOfSpeech,
    _ParseDimension.lexeme => o.lexeme,
    _ParseDimension.stemFamily => o.parse.stemFamily,
    _ParseDimension.stem => o.parse.stem,
    _ParseDimension.tense => o.parse.tense,
    _ParseDimension.person => o.parse.person,
    _ParseDimension.gender => o.parse.gender,
    _ParseDimension.number => o.parse.number,
    _ParseDimension.state => o.parse.state,
  };
}

/// One remembered result, recomputed only when its keys change.
///
/// Keys compare by identity, except for plain values (strings, numbers,
/// booleans, and [ProximityDistance]), which compare by value. Identity is the
/// point for the rest: a signal message's generated `==` compares every row,
/// which would cost as much as the work the memo saves.
class _Memo<T> {
  List<Object?>? _keys;
  late T _value;

  T get(List<Object?> keys, T Function() compute) {
    final previous = _keys;
    if (previous != null && previous.length == keys.length) {
      var same = true;
      for (var i = 0; i < keys.length && same; i++) {
        same = _sameKey(previous[i], keys[i]);
      }
      if (same) return _value;
    }
    _value = compute();
    _keys = keys;
    return _value;
  }

  static bool _sameKey(Object? a, Object? b) =>
      identical(a, b) ||
      ((a is String || a is num || a is bool || a is ProximityDistance) &&
          a == b);
}

/// A proximity search's combined verses, or why there are none yet.
class _ProximityResult {
  const _ProximityResult(this.verses) : loading = false, noPartners = false;

  /// Another included word's occurrences are still loading.
  const _ProximityResult.loading()
    : verses = const [],
      loading = true,
      noPartners = false;

  /// Every other open word has been left out.
  const _ProximityResult.noPartners()
    : verses = const [],
      loading = false,
      noPartners = true;

  final List<_VerseOccurrence> verses;
  final bool loading;
  final bool noPartners;
}

/// One verse of an occurrence list, with everything matched inside it.
class _VerseOccurrence {
  _VerseOccurrence({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.words,
    List<int>? positions,
    this.passage = 0,
  }) : positions = positions ?? [];

  final int book;
  final int chapter;
  final int verse;

  /// Which passage of a proximity search the verse belongs to.
  final int passage;

  /// Whether a separator goes above this verse, where a new passage of a
  /// verse-window or chapter proximity search begins.
  bool passageStart = false;

  ProximityHit toHit() => ProximityHit(
    book: book,
    chapter: chapter,
    verse: verse,
    words: words,
    positions: positions,
  );

  /// The surface forms matched here. Used to highlight by text where no
  /// positions are known.
  final List<String> words;

  /// Lexical positions of the matched words, when the occurrence data carries
  /// them. Highlighting prefers these: a verse can hold a homograph of the
  /// looked-up word that is *not* an occurrence of its root, and text matching
  /// cannot tell the two apart.
  final List<int> positions;
}

/// The Occurrences tab's one-tap scopes, from narrowest to widest. Each sets
/// the form and parse filters outright, so the filter sheet can then release
/// what it does not need — Same parse is the usual start for that, since
/// dropping one dimension ("any person") broadens along the grammar.
enum _FormScope {
  /// The tapped word's own surface form.
  exact('Exact'),

  /// Every form of the root carrying the tapped token's parse, as one parse
  /// filter selection per dimension.
  parse('Same parse'),

  /// Every form of the root.
  all('All forms');

  const _FormScope(this.label);

  final String label;
}

/// The segmented switch between the [_FormScope]s on offer. [selected] is null
/// when the filters match none of them.
class _FormScopeToggle extends StatelessWidget {
  const _FormScopeToggle({
    required this.scopes,
    required this.selected,
    required this.counts,
    required this.onChanged,
  });

  final List<_FormScope> scopes;
  final _FormScope? selected;
  final Map<_FormScope, int> counts;
  final ValueChanged<_FormScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final countStyle = Theme.of(context).textTheme.labelSmall;
    // Name over count: three segments with the count inline do not fit a
    // phone's width.
    return SegmentedButton<_FormScope>(
      segments: [
        for (final scope in scopes)
          ButtonSegment(
            value: scope,
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(scope.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${counts[scope] ?? 0}', maxLines: 1, style: countStyle),
              ],
            ),
          ),
      ],
      selected: {?selected},
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
      ),
      onSelectionChanged: (selection) {
        // Tapping the lit segment would empty the selection; keep it instead.
        if (selection.isNotEmpty) onChanged(selection.first);
      },
    );
  }
}

/// The Hebrew / English verse-text switch icon, shared by the verse lists.
class VerseModeIcon extends StatelessWidget {
  const VerseModeIcon({super.key, required this.englishOnly});

  final bool englishOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget segment(String label, bool active, String fontFamily) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.0,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
          fontFamilyFallback: const ['Noto Serif Hebrew'],
          color: active
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment('א', !englishOnly, 'Cardo'),
          const SizedBox(width: 1),
          segment('EN', englishOnly, 'Cardo'),
        ],
      ),
    );
  }
}

/// One verse of an occurrence list, with the looked-up word highlighted.
///
/// Stateless: the verse text comes from the shared [VerseTextCache], so a row
/// scrolling into view costs a slot in the next batched request rather than a
/// round-trip and a stream listener of its own.
class OccurrenceVerseRow extends StatelessWidget {
  const OccurrenceVerseRow({
    super.key,
    required this.cache,
    required this.displayRef,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.highlightWords,
    required this.englishOnly,
    required this.useEnglishBookNames,
    this.positions = const [],
    this.isCurrent = false,
    this.onTap,
  });

  final VerseTextCache cache;
  final String displayRef;
  final int bookIndex;
  final int chapter;
  final int verse;
  final List<String> highlightWords;

  /// Lexical positions to highlight. Preferred over [highlightWords] when
  /// known, since text matching cannot tell an occurrence of the root from an
  /// unrelated homograph standing in the same verse.
  final List<int> positions;
  final bool englishOnly;
  final bool useEnglishBookNames;

  /// The verse the reader was looking at when the sheet opened.
  final bool isCurrent;
  final VoidCallback? onTap;

  String _compactRef() {
    final book = bookIndex >= 0 && bookIndex < kBooks.length
        ? kBooks[bookIndex]
        : null;
    if (book == null) return displayRef;
    return '${bookDisplayName(bookIndex, useEnglish: useEnglishBookNames)} '
        '$chapter:$verse';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<VerseTextData?>(
      valueListenable: cache.textFor(
        book: bookIndex + 1,
        chapter: chapter,
        verse: verse,
        englishOnly: englishOnly,
      ),
      builder: (context, data, _) {
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            decoration: isCurrent
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: theme.colorScheme.surfaceContainerHighest,
                  )
                : null,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A settled-but-empty verse is one the core could not read;
                // leaving the placeholder in place would spin forever.
                if (data == null)
                  const _VersePlaceholder()
                else
                  _buildHighlightedText(context, data),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHighlightedText(BuildContext context, VerseTextData data) {
    final theme = Theme.of(context);
    final baseStyle = TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: 15,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    );
    final refStyle = TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: const ['Noto Serif Hebrew'],
      fontSize: 12,
      fontWeight: FontWeight.bold,
      color: theme.colorScheme.primary,
    );
    final strippedTargets = highlightWords.map(_stripTrope).toSet();
    final keyTargets = highlightWords.map(hebrewSurfaceKey).toSet();
    // Hebrew mode matches the displayed words themselves. English-only shows
    // glosses, which never match a Hebrew surface, so match on the word each
    // gloss was made from and highlight the English standing in for it.
    final useGlosses =
        englishOnly &&
        data.glossWords.isNotEmpty &&
        data.sourceWords.length == data.glossWords.length;
    final tokens = useGlosses ? data.glossWords : data.text.split(' ');
    // Glosses come one per lexical word, so a position indexes them directly.
    // The Hebrew text also carries standalone punctuation, which has no lexical
    // position of its own — the same mapping the reader applies.
    final lexicalOf = useGlosses
        ? [for (var i = 0; i < tokens.length; i++) i]
        : verseGlossPositions(tokens);
    final targetPositions = positions.toSet();
    bool isTarget(int i) {
      if (targetPositions.isNotEmpty) {
        final lexical = lexicalOf[i];
        return lexical != null && targetPositions.contains(lexical);
      }
      // No positions known (an occurrence list that predates them, or a bare
      // surface lookup) — fall back to matching the text.
      final word = useGlosses ? data.sourceWords[i] : tokens[i];
      if (word.isEmpty) return false;
      return strippedTargets.contains(_stripTrope(word)) ||
          keyTargets.contains(hebrewSurfaceKey(word));
    }

    final spans = <InlineSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      final token = tokens[i];
      if (isTarget(i)) {
        spans.add(
          TextSpan(
            text: token,
            style: baseStyle.copyWith(
              backgroundColor: theme.colorScheme.primaryContainer,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: token, style: baseStyle));
      }
    }
    spans.insert(0, TextSpan(text: '${_compactRef()}  ', style: refStyle));
    return SelectableText.rich(
      TextSpan(children: spans),
      textDirection: englishOnly ? TextDirection.ltr : TextDirection.rtl,
      // SelectableText swallows taps, so the wrapping InkWell never sees them;
      // forward single taps to keep click-to-navigate working.
      onTap: onTap,
    );
  }
}

/// A compact, all-books overview. Tapping it opens the labelled distribution
/// and book/category multi-select; the small chart itself stays useful as a
/// histogram instead of asking touch users to aim at an unnamed bar.
class _CanonDistribution extends StatelessWidget {
  const _CanonDistribution({
    required this.countsByBook,
    required this.selectedBooks,
    required this.onSelect,
    required this.useEnglishBookNames,
  });

  /// Occurrence counts keyed by 1-based book number.
  final Map<int, int> countsByBook;
  final Set<int> selectedBooks;
  final void Function(Set<int> books) onSelect;
  final bool useEnglishBookNames;

  static const _height = 30.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = List.generate(kBooks.length, (index) => index + 1);
    final peak = countsByBook.values.fold<int>(
      0,
      (highest, count) => count > highest ? count : highest,
    );
    return Semantics(
      button: true,
      label: 'Book distribution. Tap to filter by books.',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _BookDistributionFilterSheet(
            countsByBook: countsByBook,
            selectedBooks: selectedBooks,
            useEnglishBookNames: useEnglishBookNames,
            onChanged: onSelect,
          ),
        ),
        child: Tooltip(
          message: 'Open book distribution and filters',
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final book in books)
                        Expanded(
                          child: _bar(
                            theme,
                            book,
                            countsByBook[book] ?? 0,
                            peak,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                selectedBooks.isEmpty
                    ? 'Books'
                    : '${selectedBooks.length} selected',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Icon(Icons.open_in_full, size: 15),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(ThemeData theme, int book, int count, int peak) {
    final selected = selectedBooks.contains(book);
    final fraction = peak == 0 ? 0.0 : count / peak;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.5),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: count == 0 ? 1 : 3 + (_height - 5) * fraction,
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.primary.withValues(alpha: 0.35),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(1.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// The canon's categories, in book order: the Tanakh's three divisions, then
/// the New Testament's.
const List<({String label, String? hebrew, int start, int end})>
_kCanonSections = [
  (label: 'Torah', hebrew: 'תּוֹרָה', start: 1, end: 5),
  (label: "Nevi'im", hebrew: 'נְבִיאִים', start: 6, end: 26),
  (label: 'Ketuvim', hebrew: 'כְּתוּבִים', start: 27, end: 39),
  (label: 'Gospels and Acts', hebrew: null, start: 40, end: 44),
  (label: 'Pauline Epistles', hebrew: null, start: 45, end: 57),
  (label: 'General Epistles and Revelation', hebrew: null, start: 58, end: 66),
];

class _BookDistributionFilterSheet extends StatefulWidget {
  const _BookDistributionFilterSheet({
    required this.countsByBook,
    required this.selectedBooks,
    required this.useEnglishBookNames,
    required this.onChanged,
  });

  final Map<int, int> countsByBook;
  final Set<int> selectedBooks;
  final bool useEnglishBookNames;
  final void Function(Set<int> books) onChanged;

  @override
  State<_BookDistributionFilterSheet> createState() =>
      _BookDistributionFilterSheetState();
}

class _BookDistributionFilterSheetState
    extends State<_BookDistributionFilterSheet> {
  late final Set<int> _selected = {...widget.selectedBooks};
  final ScrollController _distributionScroll = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = true;

  @override
  void initState() {
    super.initState();
    _distributionScroll.addListener(_updateScrollIndicators);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollIndicators();
    });
  }

  @override
  void dispose() {
    _distributionScroll
      ..removeListener(_updateScrollIndicators)
      ..dispose();
    super.dispose();
  }

  void _updateScrollIndicators() {
    if (!mounted || !_distributionScroll.hasClients) return;
    final position = _distributionScroll.position;
    final canScrollBack = position.pixels > position.minScrollExtent + 1;
    final canScrollForward = position.pixels < position.maxScrollExtent - 1;
    if (_canScrollBack == canScrollBack &&
        _canScrollForward == canScrollForward) {
      return;
    }
    setState(() {
      _canScrollBack = canScrollBack;
      _canScrollForward = canScrollForward;
    });
  }

  void _scrollDistribution(bool forward) {
    final position = _distributionScroll.position;
    final distance = position.viewportDimension * 0.8;
    _distributionScroll.animateTo(
      (position.pixels + (forward ? distance : -distance)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _change(VoidCallback change) {
    setState(change);
    widget.onChanged({..._selected});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = widget.countsByBook.values.fold<int>(
      0,
      (highest, count) => count > highest ? count : highest,
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Occurrence distribution',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: () => _change(_selected.clear),
                      child: const Text('Show all'),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    'Scroll to see all ${kBooks.length} books',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Earlier books',
                    onPressed: _canScrollBack
                        ? () => _scrollDistribution(false)
                        : null,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Later books',
                    onPressed: _canScrollForward
                        ? () => _scrollDistribution(true)
                        : null,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 150,
              child: Scrollbar(
                controller: _distributionScroll,
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _distributionScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var book = 1; book <= kBooks.length; book++)
                        _ExpandedBookBar(
                          book: book,
                          count: widget.countsByBook[book] ?? 0,
                          peak: peak,
                          selected: _selected.contains(book),
                          useEnglishBookNames: widget.useEnglishBookNames,
                          onTap: () => _change(() {
                            if (!_selected.remove(book)) _selected.add(book);
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  for (final section in _kCanonSections) ...[
                    _BookCategoryHeader(
                      label: section.label,
                      hebrew: section.hebrew,
                      selectedCount: [
                        for (
                          var book = section.start;
                          book <= section.end;
                          book++
                        )
                          if (_selected.contains(book)) book,
                      ].length,
                      bookCount: section.end - section.start + 1,
                      onTap: () => _change(() {
                        final books = {
                          for (
                            var book = section.start;
                            book <= section.end;
                            book++
                          )
                            book,
                        };
                        if (_selected.containsAll(books)) {
                          _selected.removeAll(books);
                        } else {
                          _selected.addAll(books);
                        }
                      }),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (
                          var book = section.start;
                          book <= section.end;
                          book++
                        )
                          FilterChip(
                            selected: _selected.contains(book),
                            label: Text(
                              '${bookDisplayName(book - 1, useEnglish: widget.useEnglishBookNames)} '
                              '(${widget.countsByBook[book] ?? 0})',
                            ),
                            onSelected: (_) => _change(() {
                              if (!_selected.remove(book)) _selected.add(book);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedBookBar extends StatelessWidget {
  const _ExpandedBookBar({
    required this.book,
    required this.count,
    required this.peak,
    required this.selected,
    required this.useEnglishBookNames,
    required this.onTap,
  });

  final int book;
  final int count;
  final int peak;
  final bool selected;
  final bool useEnglishBookNames;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = peak == 0 ? 0.0 : count / peak;
    return Tooltip(
      message:
          '${bookDisplayName(book - 1, useEnglish: useEnglishBookNames)} · $count',
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 42,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('$count', style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Container(
                width: 24,
                height: count == 0 ? 1 : 8 + 76 * fraction,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.35),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                bookSelectorLabel(book - 1, useEnglish: useEnglishBookNames),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCategoryHeader extends StatelessWidget {
  const _BookCategoryHeader({
    required this.label,
    required this.hebrew,
    required this.selectedCount,
    required this.bookCount,
    required this.onTap,
  });

  final String label;
  final String? hebrew;
  final int selectedCount;
  final int bookCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == bookCount;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      tristate: true,
      value: selectedCount == 0 ? false : (allSelected ? true : null),
      onChanged: (_) => onTap(),
      title: Text(hebrew == null ? label : '$label  $hebrew'),
      subtitle: Text(
        selectedCount == 0 ? 'Select category' : '$selectedCount selected',
      ),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

/// The occurrence filter: the parse by morphology dimension on one tab,
/// surface forms on the other.
///
/// The parse tab groups its entries under Part of speech / Lexeme / Stem family
/// / Stem / Tense / Person / Gender / Number / State rather than listing whole
/// parse labels.
/// Within a group the entries are alternatives; across groups they all have to
/// hold. So "every Hiphil plural participle" is three taps, where a flat list of
/// labels needed that exact combination to exist as one entry — and a verb root
/// has more combinations than a reader can scan.
///
/// Every count is faceted against the *other* selections, so a number says what
/// selecting that entry would actually yield, and both lists are searchable.
class _OccurrenceFilterSheet extends StatefulWidget {
  const _OccurrenceFilterSheet({
    required this.occurrences,
    required this.selectedForms,
    required this.selectedParse,
    required this.onChanged,
  });

  /// Every token the current book filter admits. The sheet counts its own
  /// facets from these rather than taking totals computed when it opened —
  /// those go stale the moment a selection changes, which is the one thing the
  /// sheet exists to do.
  final List<Occurrence> occurrences;
  final Set<String> selectedForms;
  final Map<_ParseDimension, Set<String>> selectedParse;
  final void Function(
    Set<String> forms,
    Map<_ParseDimension, Set<String>> parse,
  )
  onChanged;

  @override
  State<_OccurrenceFilterSheet> createState() => _OccurrenceFilterSheetState();
}

class _OccurrenceFilterSheetState extends State<_OccurrenceFilterSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Set<String> _forms = {...widget.selectedForms};
  late final Map<_ParseDimension, Set<String>> _parse = {
    for (final entry in widget.selectedParse.entries)
      entry.key: {...entry.value},
  };
  final _search = TextEditingController();
  // The search the lists are filtered by. It trails the field by
  // [_searchDebounce], so typing a word re-sorts the lists once rather than
  // on every keystroke.
  String _query = '';
  Timer? _searchTimer;
  static const _searchDebounce = Duration(milliseconds: 150);
  // Entry keys with their points stripped, for matching a typed search; the
  // same few hundred keys are matched on every search.
  final Map<String, String> _strippedKeys = {};

  @override
  void dispose() {
    _searchTimer?.cancel();
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (mounted) setState(() => _query = text.trim());
    });
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _search.clear();
    setState(() => _query = '');
  }

  void _apply(VoidCallback change) {
    setState(change);
    widget.onChanged(_forms, _parse);
  }

  int get _parseSelectionCount =>
      _parse.values.fold(0, (sum, selected) => sum + selected.length);

  Set<String> _selected(_ParseDimension dimension) =>
      _parse[dimension] ?? const {};

  final _facetsMemo =
      _Memo<
        ({Map<_ParseDimension, Map<String, int>> parse, Map<String, int> forms})
      >();

  /// Every facet's values and counts, each over the tokens the *other*
  /// filters admit, so a number says what changing only that one would yield.
  ///
  /// Values the analysis does not carry are left out of the parse facets: a
  /// dimension only lists what can actually be selected, and a token with no
  /// value there is simply excluded once that dimension is used.
  ///
  /// One pass over the tokens serves all of them — a token failing no parse
  /// dimension counts in every facet, one failing exactly one counts only in
  /// that one — and the result is kept until a selection changes, since the
  /// search box re-renders the lists far more often than that.
  ({Map<_ParseDimension, Map<String, int>> parse, Map<String, int> forms})
  _facets() {
    final key = [
      (_forms.toList()..sort()).join('\u0001'),
      for (final dimension in _ParseDimension.values)
        (_selected(dimension).toList()..sort()).join('\u0001'),
    ].join('\u0002');
    return _facetsMemo.get([widget.occurrences, key], () {
      final parse = {
        for (final dimension in _ParseDimension.values)
          dimension: <String, int>{},
      };
      final forms = <String, int>{};
      final active = [
        for (final dimension in _ParseDimension.values)
          if (_selected(dimension).isNotEmpty) dimension,
      ];
      for (final o in widget.occurrences) {
        _ParseDimension? failed;
        var failures = 0;
        for (final dimension in active) {
          if (!_selected(dimension).contains(dimension.of(o))) {
            failed = dimension;
            if (++failures > 1) break;
          }
        }
        if (failures > 1) continue;
        if (failures == 0) {
          forms[o.surface] = (forms[o.surface] ?? 0) + 1;
        }
        if (_forms.isNotEmpty && !_forms.contains(o.surface)) continue;
        for (final dimension in _ParseDimension.values) {
          if (failures == 1 && dimension != failed) continue;
          final value = dimension.of(o);
          if (value.isEmpty) continue;
          final counts = parse[dimension]!;
          counts[value] = (counts[value] ?? 0) + 1;
        }
      }
      return (parse: parse, forms: forms);
    });
  }

  bool _matchesSearch(String key) {
    final query = _query;
    if (query.isEmpty) return true;
    // Hebrew is matched ignoring points, so a reader can type consonants.
    return key.contains(query) ||
        _strippedKeys
            .putIfAbsent(key, () => _stripTrope(key))
            .contains(_stripTrope(query)) ||
        key.toLowerCase().contains(query.toLowerCase());
  }

  /// Most frequent first, and alphabetically within a count, so the entries a
  /// reader is most likely to want are the ones they do not have to search for.
  List<String> _entries(Map<String, int> counts) {
    final keys = counts.keys.where(_matchesSearch).toList();
    keys.sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
    return keys;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Text('Filter occurrences', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: _forms.isEmpty && _parseSelectionCount == 0
                        ? null
                        : () => _apply(() {
                            _forms = {};
                            _parse.clear();
                          }),
                    child: const Text('Reset'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            // Parse first: a root's morphology is what a reader wants to slice
            // by, where its inflected forms can run to hundreds and mostly say
            // the same thing.
            TabBar(
              controller: _tabs,
              tabs: [
                Tab(
                  height: 36,
                  text: _parseSelectionCount == 0
                      ? 'Parse'
                      : 'Parse ($_parseSelectionCount)',
                ),
                Tab(
                  height: 36,
                  text: _forms.isEmpty ? 'Form' : 'Form (${_forms.length})',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              // Only the field follows each keystroke (for its clear button);
              // the lists wait for the debounced [_query].
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _search,
                builder: (context, value, _) => TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search',
                    border: const OutlineInputBorder(),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: _clearSearch,
                          ),
                  ),
                ),
              ),
            ),
            Flexible(
              child: TabBarView(
                controller: _tabs,
                children: [_parseTab(context), _formTab(context)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _parseTab(BuildContext context) {
    final theme = Theme.of(context);
    // A dimension with nothing to offer is left out entirely — nouns have no
    // stem, verbs no state, and an empty heading is just noise.
    final sections = <(_ParseDimension, Map<String, int>, List<String>)>[];
    for (final dimension in _ParseDimension.values) {
      final counts = _facets().parse[dimension]!;
      final entries = _entries(counts);
      // Kept when a search hides its entries but a selection of it is live, so
      // the reader can always see and undo what is filtering the list.
      if (entries.isEmpty && _selected(dimension).isEmpty) continue;
      sections.add((dimension, counts, entries));
    }
    if (sections.isEmpty) {
      return Center(
        child: Text(
          'Nothing to filter on',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final (dimension, counts, entries) = sections[i];
        final selected = _selected(dimension);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, i == 0 ? 4 : 14, 16, 2),
              child: Row(
                children: [
                  Text(
                    dimension.label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  if (selected.isNotEmpty)
                    TextButton(
                      onPressed: () => _apply(() => _parse.remove(dimension)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                      ),
                      child: const Text('Any'),
                    ),
                ],
              ),
            ),
            // Wrapped chips rather than a column of checkboxes: a dimension has
            // a handful of short values, and seven stacked lists would bury the
            // later ones under a page of scrolling.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final value in entries)
                    FilterChip(
                      label: Text('$value  ${counts[value] ?? 0}'),
                      selected: selected.contains(value),
                      visualDensity: VisualDensity.compact,
                      onSelected: (on) => _apply(() {
                        final next = {...selected};
                        on ? next.add(value) : next.remove(value);
                        if (next.isEmpty) {
                          _parse.remove(dimension);
                        } else {
                          _parse[dimension] = next;
                        }
                      }),
                    ),
                  // A live selection whose entry the search or another filter
                  // has hidden still needs to be visible to be turned off.
                  for (final value in selected)
                    if (!entries.contains(value))
                      FilterChip(
                        label: Text(value),
                        selected: true,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => _apply(() {
                          final next = {...selected}..remove(value);
                          if (next.isEmpty) {
                            _parse.remove(dimension);
                          } else {
                            _parse[dimension] = next;
                          }
                        }),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _formTab(BuildContext context) {
    final counts = _facets().forms;
    final entries = _entries(counts);
    final formStyle = const TextStyle(
      fontFamily: 'Cardo',
      fontFamilyFallback: ['Noto Serif Hebrew'],
    );
    return ListView.builder(
      // One tile per row: a 300-entry list packed into columns has no order
      // anyone can scan.
      itemCount: entries.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return CheckboxListTile(
            dense: true,
            title: const Text('All forms'),
            value: _forms.isEmpty,
            onChanged: (_) => _apply(() => _forms = {}),
          );
        }
        final form = entries[i - 1];
        return CheckboxListTile(
          dense: true,
          title: Text(
            form,
            style: formStyle,
            textDirection: TextDirection.rtl,
            overflow: TextOverflow.ellipsis,
          ),
          secondary: Text('${counts[form] ?? 0}'),
          value: _forms.contains(form),
          onChanged: (on) => _apply(() {
            final next = {..._forms};
            (on ?? false) ? next.add(form) : next.remove(form);
            _forms = next;
          }),
        );
      },
    );
  }
}

/// Stands in for a verse whose text has not arrived. A static bar rather than a
/// spinner: a screenful of rows means a screenful of these, and animating them
/// all costs a repaint every frame for no information.
class _VersePlaceholder extends StatelessWidget {
  const _VersePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _BdbContent extends StatelessWidget {
  const _BdbContent({
    required this.contentJson,
    required this.source,
    required this.onBibleRefTap,
    required this.onXrefTap,
    required this.onDictionaryLinkTap,
  });

  final String contentJson;

  /// The lexicon the entry is from, which is also where its `dref` links
  /// point: Klein links only to Klein, Jastrow only to Jastrow.
  final String source;
  final void Function(String href) onBibleRefTap;
  final void Function(String bdbId, String headword) onXrefTap;
  final void Function(String source, String key, String text)
  onDictionaryLinkTap;

  // Decoded entries, most recently shown last. A large entry (אמר, עשׂה) is
  // tens of kilobytes of JSON, and the sheet rebuilds every expanded entry on
  // each change anywhere in it, so each is decoded once and kept.
  static final Map<String, Map<String, dynamic>?> _decoded = {};
  static const _decodedLimit = 32;

  /// The decoded entry, or null when its JSON is unreadable.
  static Map<String, dynamic>? _entry(String contentJson) {
    if (_decoded.containsKey(contentJson)) {
      // Move it to the most recent end.
      return _decoded[contentJson] = _decoded.remove(contentJson);
    }
    Map<String, dynamic>? entry;
    try {
      entry = jsonDecode(contentJson) as Map<String, dynamic>;
    } catch (_) {
      entry = null;
    }
    if (_decoded.length >= _decodedLimit) _decoded.remove(_decoded.keys.first);
    return _decoded[contentJson] = entry;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _entry(contentJson);
    if (entry == null) return const SizedBox.shrink();
    final senses = entry['senses'] as List<dynamic>? ?? const [];
    final alternatives = (entry['alternatives'] as List<dynamic>? ?? const [])
        .cast<String>();

    // What Klein and Jastrow carry beyond BDB's senses, each under a label.
    Widget section(String label, List<dynamic> spans) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
            ..._spansFromDefinition(context, spans),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...senses.map<Widget>(
            (s) => _buildSense(context, s as Map<String, dynamic>, 0),
          ),
          if (entry['plural'] case final List<dynamic> plural)
            section('Plural', plural),
          if (alternatives.isNotEmpty)
            section('Also spelled', [
              {'t': alternatives.join(', '), 'rtl': true},
            ]),
          if (entry['etymology'] case final List<dynamic> etymology)
            section('Etymology', etymology),
          if (entry['derivatives'] case final List<dynamic> derivatives)
            section('Derivatives', derivatives),
        ],
      ),
    );
  }

  Widget _buildSense(
    BuildContext context,
    Map<String, dynamic> sense,
    int depth,
  ) {
    final theme = Theme.of(context);
    final num = sense['num'] as String?;
    final form = sense['form'] as String?;
    final definition = sense['definition'] as List<dynamic>?;
    final subSenses = sense['senses'] as List<dynamic>?;
    // Klein dates a sense when it entered the language later than the word.
    final lang = LexiconPeriodLabel.of(sense['lang'] as String? ?? '');

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (form != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                form,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (lang != null)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: lang),
          if (definition != null)
            SelectableText.rich(
              TextSpan(
                children: [
                  if (num != null)
                    TextSpan(
                      text: '$num ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ..._spansFromDefinition(context, definition),
                ],
              ),
            ),
          if (subSenses != null)
            ...subSenses.map<Widget>(
              (s) => _buildSense(context, s as Map<String, dynamic>, depth + 1),
            ),
        ],
      ),
    );
  }

  List<InlineSpan> _spansFromDefinition(
    BuildContext context,
    List<dynamic> definition,
  ) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface,
      height: 1.5,
    );

    return definition.map<InlineSpan>((spanData) {
      final span = spanData as Map<String, dynamic>;
      final text = span['t'] as String? ?? '';
      final bold = span['b'] == true;
      final italic = span['i'] == true;
      final small = span['s'] == true;
      final rtl = span['rtl'] == true;
      final href = span['href'] as String?;
      // A <w src> cross-reference: tappable, navigates to the target entry.
      final xref = span['xref'] as String?;
      // A Klein or Jastrow link to another entry of the same lexicon.
      final dref = span['dref'] as String?;
      final isLink = href != null || xref != null || dref != null;

      TextStyle style = (baseStyle ?? const TextStyle()).copyWith(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
        fontSize: small ? (baseStyle?.fontSize ?? 12) * 0.85 : null,
        fontFamily: rtl ? 'Cardo' : null,
        fontFamilyFallback: rtl ? const ['Noto Serif Hebrew'] : null,
        color: isLink ? theme.colorScheme.primary : null,
        decoration: isLink ? TextDecoration.underline : null,
        decorationColor: isLink ? theme.colorScheme.primary : null,
      );

      if (href != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onBibleRefTap(href);
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }

      if (xref != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onXrefTap(xref, text);
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }

      if (dref != null) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => onDictionaryLinkTap(source, dref, text);
        return TextSpan(text: text, style: style, recognizer: recognizer);
      }

      return TextSpan(text: text, style: style);
    }).toList();
  }
}

/// BDB headwords are stored in Unicode NFC canonical order (vowel CCC=17 before
/// dagesh/shin-dot CCC=21-24), but Cardo expects the traditional Hebrew encoding
/// order (dagesh/shin-dot before vowel). Bubble-swap any such pairs.
String _normalizeHebrewCombining(String text) {
  final chars = text.runes.toList();
  var i = 0;
  while (i + 1 < chars.length) {
    if (_isHebVowel(chars[i]) && _isHebDot(chars[i + 1])) {
      final tmp = chars[i];
      chars[i] = chars[i + 1];
      chars[i + 1] = tmp;
    } else {
      i++;
    }
  }
  return String.fromCharCodes(chars);
}

bool _isHebVowel(int cp) =>
    (cp >= 0x05B0 && cp <= 0x05BD && cp != 0x05BC) || cp == 0x05C7;

bool _isHebDot(int cp) => cp == 0x05BC || cp == 0x05C1 || cp == 0x05C2;

/// Whether two headwords spell one word, whatever their accents or the order
/// their points are stored in.
bool _sameHeadword(String a, String b) {
  List<int> points(String s) => _stripTrope(s).runes.toList()..sort();
  return listEquals(points(a), points(b));
}

String _stripTrope(String word) {
  return String.fromCharCodes(
    word.runes.where((cp) {
      return !((cp >= 0x0591 && cp <= 0x05AF) ||
          cp == 0x05BD ||
          cp == 0x05BE ||
          cp == 0x05C0 ||
          cp == 0x05C3 ||
          cp == 0x05C4 ||
          cp == 0x05C5 ||
          cp == 0x05C6);
    }),
  );
}

class _LexiconEntryOverrideEditor extends StatefulWidget {
  const _LexiconEntryOverrideEditor({
    required this.surface,
    required this.root,
    required this.gloss,
    this.readerGloss,
  });

  final String surface;
  final String root;
  final String gloss;
  final String? readerGloss;

  @override
  State<_LexiconEntryOverrideEditor> createState() =>
      _LexiconEntryOverrideEditorState();
}

class _LexiconEntryOverrideEditorState
    extends State<_LexiconEntryOverrideEditor> {
  late final TextEditingController _root = TextEditingController(
    text: widget.root,
  );
  late final TextEditingController _gloss = TextEditingController(
    text: widget.gloss,
  );
  late final TextEditingController _readerGloss = TextEditingController(
    text: widget.readerGloss ?? widget.gloss,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _root.dispose();
    _gloss.dispose();
    _readerGloss.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final gloss = _gloss.text.trim();
    final readerGloss = _readerGloss.text.trim();
    if (gloss.isEmpty) {
      setState(() => _error = 'A lexicon gloss is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final statusFuture = firstWithin(
      LexiconEntryOverrideStatus.rustSignalStream,
      (pack) => pack.message.surface == widget.surface,
      const Duration(seconds: 8),
    );
    SaveLexiconEntryOverride(
      surface: widget.surface,
      root: _root.text.trim(),
      gloss: gloss,
      readerGloss: readerGloss,
    ).sendSignalToRust();
    try {
      final status = (await statusFuture).message;
      if (!mounted) return;
      if (!status.success) {
        setState(() {
          _saving = false;
          _error = status.message;
        });
        return;
      }
      scheduleProgressSync();
      Navigator.pop(context, status.message);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'The app did not confirm that the correction was saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Edit word glosses',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              widget.surface,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontFamily: 'Cardo',
                fontFamilyFallback: ['Noto Serif Hebrew'],
                fontSize: 36,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _root,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(
                labelText: 'Root (optional)',
                helperText: 'Leave blank for particles and rootless entries.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gloss,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Lexicon header gloss',
                helperText: 'The descriptive gloss shown in word information.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _readerGloss,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Interlinear gloss',
                helperText:
                    'The compact gloss shown below this word in the reader.',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save correction'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One Klein or Jastrow entry, fetched by key when a link to it is tapped.
class _DictionaryEntryPreviewDialog extends StatefulWidget {
  const _DictionaryEntryPreviewDialog({
    required this.source,
    required this.entryKey,
    required this.linkText,
    required this.send,
    required this.onBibleRefTap,
    required this.onXrefTap,
    required this.onDictionaryLinkTap,
  });

  final String source;
  final String entryKey;

  /// The link's own text, shown as the title until the entry arrives.
  final String linkText;
  final void Function(GetDictionaryEntry)? send;
  final void Function(String href) onBibleRefTap;
  final void Function(String bdbId, String headword) onXrefTap;
  final void Function(String source, String key, String text)
  onDictionaryLinkTap;

  @override
  State<_DictionaryEntryPreviewDialog> createState() =>
      _DictionaryEntryPreviewDialogState();
}

class _DictionaryEntryPreviewDialogState
    extends State<_DictionaryEntryPreviewDialog> {
  // Replies are broadcast to every open preview; the id picks out this one's.
  static int _nextRequestId = 1;
  late final int _requestId = _nextRequestId++;
  StreamSubscription<RustSignalPack<DictionaryEntry>>? _sub;
  DictionaryEntry? _reply;

  @override
  void initState() {
    super.initState();
    _sub = DictionaryEntry.rustSignalStream.listen((pack) {
      if (!mounted || pack.message.requestId != _requestId) return;
      setState(() => _reply = pack.message);
      _sub?.cancel();
    });
    final request = GetDictionaryEntry(
      requestId: _requestId,
      source: widget.source,
      key: widget.entryKey,
    );
    final send = widget.send;
    if (send == null) {
      request.sendSignalToRust();
    } else {
      send(request);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _reply?.entry;
    final lang = entry == null ? null : LexiconPeriodLabel.of(entry.lang);
    return AlertDialog(
      title: Row(
        children: [
          LexiconSourceBadge(source: widget.source),
          if (lang != null) ...[const SizedBox(width: 4), lang],
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _normalizeHebrewCombining(
                    entry == null
                        ? widget.linkText
                        : '${entry.headword} ${entry.homograph}'.trim(),
                  ),
                  style: TextStyle(
                    fontFamily: 'Noto Serif Hebrew',
                    fontFamilyFallback: const ['Cardo'],
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                if (entry != null && entry.gloss.isNotEmpty)
                  Text(entry.gloss, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
      content: switch (_reply) {
        null => const SizedBox(
          height: 60,
          child: Center(child: CircularProgressIndicator()),
        ),
        DictionaryEntry(entry: final entry?) => SingleChildScrollView(
          child: _BdbContent(
            contentJson: entry.contentJson,
            source: entry.source,
            onBibleRefTap: widget.onBibleRefTap,
            onXrefTap: widget.onXrefTap,
            onDictionaryLinkTap: widget.onDictionaryLinkTap,
          ),
        ),
        _ => Text(
          'This entry is not in the installed dictionary.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      },
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A Bible reference's verse, previewed over the word sheet.
class BibleRefPreviewDialog extends StatefulWidget {
  const BibleRefPreviewDialog({
    super.key,
    required this.displayRef,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    this.onNavigate,
    this.sendVerseText,
  });

  final String displayRef;
  final int bookIndex;
  final int chapter;
  final int verse;
  final VoidCallback? onNavigate;

  /// Stands in for the signal to Rust so a test can capture the request.
  final void Function(GetVerseText)? sendVerseText;

  @override
  State<BibleRefPreviewDialog> createState() => _BibleRefPreviewDialogState();
}

class _BibleRefPreviewDialogState extends State<BibleRefPreviewDialog> {
  StreamSubscription<RustSignalPack<VerseText>>? _sub;
  StreamSubscription<RequestFailed>? _failureSub;
  final RequestTimer _timer = RequestTimer();
  String? _verseText;
  // Set when the verse could not be fetched; shown in place of the spinner.
  String? _error;

  @override
  void initState() {
    super.initState();
    _request();
  }

  void _request() {
    _sub?.cancel();
    _failureSub?.cancel();
    if (_error != null) setState(() => _error = null);
    final targetBook = widget.bookIndex + 1;
    _sub = VerseText.rustSignalStream.listen((pack) {
      final msg = pack.message;
      if (mounted &&
          msg.book == targetBook &&
          msg.chapter == widget.chapter &&
          msg.verse == widget.verse &&
          !msg.englishOnly) {
        _timer.stop();
        setState(() => _verseText = msg.text);
        _sub?.cancel();
        _failureSub?.cancel();
      }
    });
    _failureSub = listenForFailure(requestVerseText, (failure) {
      if (mounted) _fail(failure.message);
    }, key: '$targetBook:${widget.chapter}:${widget.verse}');
    _timer.start(() {
      if (mounted && _verseText == null) _fail('Haqor did not answer.');
    });
    final request = GetVerseText(
      book: targetBook,
      chapter: widget.chapter,
      verse: widget.verse,
      englishOnly: false,
    );
    final send = widget.sendVerseText;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  void _fail(String message) {
    _timer.stop();
    setState(() => _error = message);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _failureSub?.cancel();
    _timer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = kBooks[widget.bookIndex];
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.displayRef, style: theme.textTheme.titleMedium),
          Text(
            '${book.transliteration} ${widget.chapter}:${widget.verse}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: _error != null
          ? RequestErrorView(
              message: 'Could not load this verse: $_error',
              onRetry: _request,
            )
          : _verseText == null
          ? const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            )
          : _buildVerseText(context, _verseText!),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (widget.onNavigate != null)
          FilledButton.tonal(
            onPressed: () {
              Navigator.pop(context);
              widget.onNavigate!();
            },
            child: const Text('Go to passage'),
          ),
      ],
    );
  }

  Widget _buildVerseText(BuildContext context, String text) {
    return SelectableText(
      text,
      style: TextStyle(
        fontFamily: 'Cardo',
        fontFamilyFallback: const ['Noto Serif Hebrew'],
        fontSize: 18,
        height: 1.6,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      textDirection: TextDirection.rtl,
    );
  }
}
