import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverPadding;
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'about_page.dart';
import 'app_settings.dart';
import 'bible_data.dart';
import 'christadelphian_readings.dart';
import 'bindings/bindings.dart' hide StudyItem;
import 'issue_reporting.dart';
import 'prefs_read.dart';
import 'memorise/memorise_page.dart';
import 'study_workspace.dart';
import 'study_workspace_store.dart';
import 'syntax_tree.dart';
import 'tutor/onboarding.dart';
import 'widgets/book_selector.dart';
import 'widgets/chapter_selector.dart';
import 'widgets/cross_references_sheet.dart';
import 'widgets/markdown_note.dart';
import 'widgets/name_details.dart';
import 'widgets/places_page.dart';
import 'widgets/study_workspace_panel.dart';
import 'widgets/study_passage_editor.dart';
import 'widgets/study_section_editor.dart';
import 'widgets/study_timeline_editor.dart';
import 'widgets/timeline_chart.dart';
import 'widgets/syntax_sheet.dart';
import 'widgets/verse_row.dart';
import 'widgets/word_info_sheet.dart';
import 'word_proximity.dart';

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

/// The furthest from the epoch, in milliseconds, that [DateTime] can represent.
const _maxDateMillis = 8640000000000000;

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
      // DateTime throws outside this range; an unreadable time is just unknown.
      completed[chapter] = millis == null || millis.abs() > _maxDateMillis
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
  final Map<int, GlobalKey> verseKeys;

  /// What the verses were fetched as, to tell when a setting has made them
  /// out of date.
  _ChapterRequest request;

  _Section({
    required this.bookIndex,
    required this.chapter,
    required this.verses,
    required this.request,
  }) : key = GlobalKey(),
       verseKeys = {for (final verse in verses) verse.verse: GlobalKey()};
}

typedef _ChapterRequest = (int, int, bool, bool, bool, bool, bool);

class _SelectedWord {
  const _SelectedWord({
    required this.word,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.position,
    required this.root,
    this.readerGloss,
    this.bdbId,
  });

  final String word;
  final int bookIndex;
  final int? chapter;
  final int? verse;
  final int? position;
  final String root;
  final String? readerGloss;
  final String? bdbId;
}

/// The reader top bar's own actions, in the order the bar shows them.
enum _ReaderBarAction {
  crossReferences,
  places,
  people,
  text,
  interlinear,
  rapidReading,
  back,
  forward,
}

enum _ReaderMenuAction {
  studyWorkspace,
  crossReferences,
  readingPlan,
  places,
  tutor,
  memorise,
  reportIssue,
  settings,
  about,
}

enum _ResolvedReaderLayout { focus, split, threePanel }

/// What a verse number's menu offers.
enum _VerseMenuAction {
  crossReferences,
  chapterCrossReferences,
  syntax,
  memoriseChapter,
  addTimelineEvent,
  addTimelineSpan,
}

enum _WordMenuAction {
  open,
  openNewPane,
  bookmarkRoot,
  bookmarkForm,
  addHeading,
  addTimelineEntry,
}

enum _StudyHeadingAction { edit, addSubheading, delete }

/// What a docked side panel shows, switched between when more than one is open.
enum _SidePanelView { study, word, crossReferences }

/// One open word inspector, with its own lexical-navigation history.
class _WordPane {
  _WordPane(this.id, _SelectedWord word) : history = [word];

  final String id;
  final List<_SelectedWord> history;
  int index = 0;

  _SelectedWord get word => history[index];
  bool get canGoBack => index > 0;
  bool get canGoForward => index < history.length - 1;
}

const _workspaceMinimumTileWidth = 260.0;
const _workspacePanelDividerWidth = 9.0;

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({
    super.key,
    this.sendChapterRequest,
    this.sendStudyStateRequest,
    this.saveStudyState,
    this.sendWordInfoRequest,
    this.sendWordOccurrencesRequest,
    this.sendVerseTextsRequest,
    this.sendCrossReferencesRequest,
    this.sendQuotationsRequest,
    this.sendThematicReferencesRequest,
    this.sendThematicOverviewRequest,
    this.sendSyntaxTreesRequest,
    this.sendTranslationRequest,
  });

  final void Function(GetChapter request)? sendChapterRequest;
  final void Function(GetStudyState request)? sendStudyStateRequest;
  final void Function(SaveStudyState request)? saveStudyState;
  final void Function(GetWordInfo request)? sendWordInfoRequest;
  final void Function(GetWordOccurrences request)? sendWordOccurrencesRequest;
  final void Function(GetVerseTexts request)? sendVerseTextsRequest;
  final void Function(GetCrossReferences request)? sendCrossReferencesRequest;
  final void Function(GetQuotations request)? sendQuotationsRequest;
  final void Function(GetThematicReferences request)?
  sendThematicReferencesRequest;
  final void Function(GetThematicOverview request)? sendThematicOverviewRequest;
  final void Function(GetSyntaxTrees request)? sendSyntaxTreesRequest;
  final void Function(GetChapterTranslation request)? sendTranslationRequest;

  @override
  State<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _ReaderTab {
  const _ReaderTab(this.id);

  final String id;
}

class _WorkspaceTile {
  const _WorkspaceTile({required this.id, required this.child});

  final String id;
  final Widget child;
}

class _BibleReaderPageState extends State<BibleReaderPage> {
  static const _kTabs = 'reader_tabs';
  static const _kActiveTab = 'reader_active_tab';
  static const _kTiled = 'reader_tabs_tiled';
  static const _kTiledPanelWidth = 'reader_tiled_panel_width';
  static const _kSidePanelWidth = 'reader_side_panel_width';

  final List<_ReaderTab> _tabs = [const _ReaderTab('primary')];
  final Map<String, GlobalKey<_ReaderSessionState>> _readerKeys = {
    'primary': GlobalKey<_ReaderSessionState>(),
  };
  late PageController _pageController;
  bool? _mobileLayout;
  bool _studyPageSelected = false;
  bool _wordPageSelected = false;
  bool _crossReferencesPageSelected = false;
  int? _pageTarget;
  String _activeTabId = 'primary';
  bool _tiled = false;
  double _tiledPanelWidth = 360;
  // The inspector belongs to the workspace, including while reader pages
  // are switched, removed, or rearranged by the responsive layout.
  final GlobalKey _wordInspectorKey = GlobalKey();
  // Several words can be open at once, one pane each, switched between like
  // studies. The open panes are what a proximity search combines.
  final List<_WordPane> _wordPanes = [];
  String? _activeWordPaneId;
  int _nextWordPaneId = 0;
  final WordProximity _proximity = WordProximity();
  // The study workspaces every reader tab shares.
  late final StudyWorkspaceStore _studyStore;
  _WordPane? get _activeWordPane {
    for (final pane in _wordPanes) {
      if (pane.id == _activeWordPaneId) return pane;
    }
    return null;
  }

  _SelectedWord? get _selectedWord => _activeWordPane?.word;
  bool get _canGoBackWord => _activeWordPane?.canGoBack ?? false;
  bool get _canGoForwardWord => _activeWordPane?.canGoForward ?? false;
  _SidePanelView _sidePanelView = _SidePanelView.study;
  // The cross-reference panel docks beside the reader like the word inspector,
  // and like it belongs to the workspace, so it keeps its filters while the
  // layout moves it around.
  bool _crossReferencesVisible = false;
  final GlobalKey _crossReferencesKey = GlobalKey();
  // The verse it was last asked to open (1-based book), and a count of such
  // requests so asking for the same verse again reopens it.
  ({int book, int chapter, int verse})? _crossReferenceTarget;
  int _crossReferenceRequest = 0;
  double _sidePanelWidth = 360;
  bool _loaded = false;
  bool _mobileBarHidden = false;
  Timer? _mobileBarTransitionTimer;

  @override
  void initState() {
    super.initState();
    _studyStore = StudyWorkspaceStore(
      sendRequest: widget.sendStudyStateRequest,
      save: widget.saveStudyState,
    )..addListener(_onStudyStoreChanged);
    _studyStore.start();
    _loadWorkspace();
  }

  // Study pages and tiled panels are built here, outside any one session.
  void _onStudyStoreChanged() {
    if (mounted) setState(() {});
  }

  int get _readerPageOffset => _mobileLayout == true ? 1 : 0;

  bool get _hasWordPage => _mobileLayout == true && _selectedWord != null;

  int get _wordPageIndex => _tabs.length + _readerPageOffset;

  /// On a phone, open cross references are a page after the word page.
  bool get _hasCrossReferencesPage =>
      _mobileLayout == true && _crossReferencesVisible;

  int get _crossReferencesPageIndex => _wordPageIndex + (_hasWordPage ? 1 : 0);

  int get _activeReaderPage =>
      _tabs.indexWhere((tab) => tab.id == _activeTabId) + _readerPageOffset;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mobile = MediaQuery.sizeOf(context).width < 900;
    if (_mobileLayout == mobile) return;
    if (_mobileLayout != null) {
      final previousController = _pageController;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previousController.dispose();
      });
    }
    _mobileLayout = mobile;
    _studyPageSelected = false;
    _wordPageSelected = false;
    _crossReferencesPageSelected = false;
    _pageTarget = null;
    _pageController = PageController(
      initialPage: _activeReaderPage,
      keepPage: false,
    );
  }

  void _selectPage(int index) {
    setState(() {
      _studyPageSelected = _mobileLayout == true && index == 0;
      _wordPageSelected = _hasWordPage && index == _wordPageIndex;
      _crossReferencesPageSelected =
          _hasCrossReferencesPage && index == _crossReferencesPageIndex;
      if (!_studyPageSelected &&
          !_wordPageSelected &&
          !_crossReferencesPageSelected) {
        _activeTabId = _tabs[index - _readerPageOffset].id;
      }
      _mobileBarHidden = false;
    });
    _saveWorkspace();
  }

  Future<void> _showPage(int index) async {
    final controller = _pageController;
    if (!controller.hasClients) return;
    // Passing another reader during an animation must not change the active
    // reader used by study actions and passage links.
    _pageTarget = index;
    await controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    if (!mounted || controller != _pageController || _pageTarget != index) {
      return;
    }
    _pageTarget = null;
    if (controller.hasClients) _selectPage(controller.page!.round());
  }

  void _showReaderPage() => _showPage(_activeReaderPage);

  Future<void> _loadWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.readStringList(_kTabs) ?? const [];
    final ids = savedIds.where((id) => id.isNotEmpty).toSet().toList();
    if (!ids.contains('primary')) ids.insert(0, 'primary');
    final active = prefs.readString(_kActiveTab);
    if (!mounted) return;
    setState(() {
      _tabs
        ..clear()
        ..addAll(ids.map(_ReaderTab.new));
      for (final tab in _tabs) {
        _readerKeys.putIfAbsent(tab.id, () => GlobalKey<_ReaderSessionState>());
      }
      _activeTabId = ids.contains(active) ? active! : ids.first;
      _tiled = prefs.readBool(_kTiled) ?? false;
      _tiledPanelWidth = prefs.readDouble(_kTiledPanelWidth) ?? 360;
      _sidePanelWidth = (prefs.readDouble(_kSidePanelWidth) ?? 360).clamp(
        280,
        600,
      );
      _loaded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_activeReaderPage);
    });
  }

  Future<void> _saveWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_kTabs, _tabs.map((tab) => tab.id).toList()),
      prefs.setString(_kActiveTab, _activeTabId),
      prefs.setBool(_kTiled, _tiled),
      prefs.setDouble(_kTiledPanelWidth, _tiledPanelWidth),
      prefs.setDouble(_kSidePanelWidth, _sidePanelWidth),
    ]);
  }

  Future<void> _addTab() async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final source = _readerKeys[_activeTabId]?.currentState;
    if (source != null) {
      await _ReaderSession.seedNavigation(
        id,
        source._bookIndex,
        source._chapter,
        source._visibleVerse,
      );
      if (!mounted) return;
    }
    setState(() {
      _tabs.add(_ReaderTab(id));
      _readerKeys[id] = GlobalKey<_ReaderSessionState>();
      _activeTabId = id;
      _mobileBarHidden = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _showReaderPage();
      }
    });
    _saveWorkspace();
  }

  KeyEventResult _handleWorkspaceKey(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_tiled ||
        MediaQuery.sizeOf(context).width < 900) {
      return KeyEventResult.ignored;
    }
    final direction = event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : 0;
    if (direction == 0) return KeyEventResult.ignored;

    final activeIndex = _tabs.indexWhere((tab) => tab.id == _activeTabId);
    final targetIndex = (activeIndex + direction).clamp(0, _tabs.length - 1);
    if (targetIndex != activeIndex) {
      setState(() => _activeTabId = _tabs[targetIndex].id);
      _saveWorkspace();
    }
    return KeyEventResult.handled;
  }

  void _closeTab(String id) {
    if (_tabs.length == 1) return;
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    setState(() {
      _tabs.removeAt(index);
      _mobileBarHidden = false;
      if (_activeTabId == id) {
        _activeTabId = _tabs[math.min(index, _tabs.length - 1)].id;
      }
      // Reader removal shifts page indices, but must leave a global page open.
      _pageTarget = _studyPageSelected
          ? 0
          : _wordPageSelected
          ? _wordPageIndex
          : _crossReferencesPageSelected
          ? _crossReferencesPageIndex
          : _activeReaderPage;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        final target = _pageTarget ?? _activeReaderPage;
        _pageController.jumpToPage(target);
        _selectPage(target);
      }
      _pageTarget = null;
    });
    _saveWorkspace();
  }

  @override
  void dispose() {
    _studyStore.dispose();
    _mobileBarTransitionTimer?.cancel();
    _pageController.dispose();
    _proximity.dispose();
    super.dispose();
  }

  Widget _tabLabel(_ReaderTab tab) {
    final state = _readerKeys[tab.id]?.currentState;
    final label = state == null
        ? 'Reader'
        : '${bookDisplayName(state._bookIndex, useEnglish: state._englishBookNames)} '
              '${state._chapter}';
    return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _reader(_ReaderTab tab, {required bool tiled}) => _ReaderSession(
    key: _readerKeys[tab.id],
    sessionId: tab.id,
    tiled: tiled,
    onWorkspaceTilesChanged: () {
      if (!mounted) return;
      setState(() {
        if (_tiled && _mobileLayout == false) _activeTabId = tab.id;
      });
      if (_tiled && _mobileLayout == false) _saveWorkspace();
    },
    onCrossReferencesRequested: (bookIndex, chapter, verse) {
      setState(() => _activeTabId = tab.id);
      _requestCrossReferences(bookIndex, chapter, verse);
    },
    onWordInfoRequested: (selected, {newPane = false}) {
      setState(() => _activeTabId = tab.id);
      _selectInspectorWord(selected, newPane: newPane);
      if (_mobileLayout == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _hasWordPage) _showPage(_wordPageIndex);
        });
      }
    },
    onScrollChromeChanged: (hidden) {
      if (_studyPageSelected ||
          _wordPageSelected ||
          _crossReferencesPageSelected ||
          tab.id != _activeTabId ||
          MediaQuery.sizeOf(context).width >= 900 ||
          _mobileBarHidden == hidden) {
        return;
      }
      _setMobileBarHidden(hidden);
    },
    sendChapterRequest: widget.sendChapterRequest,
    studyStore: _studyStore,
    sendSyntaxTreesRequest: widget.sendSyntaxTreesRequest,
    sendTranslationRequest: widget.sendTranslationRequest,
    sendVerseTextsRequest: widget.sendVerseTextsRequest,
    onPassageChanged: () {
      if (mounted) setState(() {});
    },
  );

  bool get _studyWorkspaceVisible =>
      _activeReader?._studyWorkspaceVisible ?? false;

  Widget _studyWorkspacePanel() =>
      _activeReader?._studyWorkspacePanel() ?? const SizedBox.shrink();

  /// The single side panel of the focus and split layouts: study, word and
  /// cross references, whichever are open, switched between.
  Widget? _tiledAuxiliaryPanel() => _sidePanel([
    if (_studyWorkspaceVisible) _SidePanelView.study,
    if (_selectedWord != null) _SidePanelView.word,
    if (_crossReferencesVisible) _SidePanelView.crossReferences,
  ]);

  /// A side panel showing one of [views], with a switcher when there are
  /// several. Null when none is open.
  Widget? _sidePanel(List<_SidePanelView> views) {
    if (views.isEmpty) return null;
    final view = views.contains(_sidePanelView) ? _sidePanelView : views.first;
    final single = views.length == 1;
    final body = switch (view) {
      _SidePanelView.study => _studyWorkspacePanel(),
      _SidePanelView.word => _wordInspector(showNavigation: single),
      _SidePanelView.crossReferences => _crossReferencesPanel(),
    };
    if (single) return body;
    return Column(
      children: [
        _wordNavigationToolbar(views: views, current: view),
        const Divider(height: 1),
        Expanded(child: body),
      ],
    );
  }

  /// Opens cross references: docked beside the reader, or on a phone as a
  /// page of its own beside the readers, as study and word info are. With a
  /// verse its links, else the overview, which follows the reader.
  void _requestCrossReferences(int bookIndex, int chapter, int? verse) {
    setState(() {
      _crossReferencesVisible = true;
      _sidePanelView = _SidePanelView.crossReferences;
      // Without a verse the panel goes back to the overview.
      _crossReferenceTarget = verse == null
          ? null
          : (book: bookIndex + 1, chapter: chapter, verse: verse);
      _crossReferenceRequest++;
    });
    if (_mobileLayout == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hasCrossReferencesPage) {
          _showPage(_crossReferencesPageIndex);
        }
      });
    }
  }

  /// Closes cross references, returning a phone to the reader first so the
  /// page leaves without the reader jumping.
  Future<void> _closeCrossReferences() async {
    if (_crossReferencesPageSelected) await _showPage(_activeReaderPage);
    if (mounted) setState(() => _crossReferencesVisible = false);
  }

  /// A panel that moves between a phone's pages and the side panel under
  /// [key], with its own overlay so its tooltips move with it (see
  /// [_ReaderSessionState.build]).
  Widget _movablePanel(GlobalKey key, Widget child) => KeyedSubtree(
    key: key,
    child: Overlay.wrap(child: child),
  );

  Widget _crossReferencesPanel() {
    final reader = _activeReader;
    return _movablePanel(
      _crossReferencesKey,
      Material(
        color: Theme.of(context).colorScheme.surface,
        child: reader == null
            ? const SizedBox.shrink()
            : CrossReferencesPanel(
                book: reader._bookIndex + 1,
                chapter: reader._chapter,
                target: _crossReferenceTarget,
                targetRequest: _crossReferenceRequest,
                useEnglishBookNames: reader._englishBookNames,
                ntSyriac: reader._ntSyriac,
                isLinkBookmarked: reader._isStudyLinkBookmarked,
                onToggleLinkBookmark: reader._toggleStudyLinkBookmark,
                minScore: reader._crossReferenceMinScore,
                onMinScoreChanged: reader._setCrossReferenceMinScore,
                onNavigateToPassage: (book, chapter, verse) {
                  reader._navigateTo(book, chapter, verse: verse);
                  // A phone shows the reader in place of the page.
                  if (_crossReferencesPageSelected) _showReaderPage();
                },
                onClose: _closeCrossReferences,
                sendRequest: widget.sendCrossReferencesRequest,
                sendQuotationsRequest: widget.sendQuotationsRequest,
                sendThematicReferencesRequest:
                    widget.sendThematicReferencesRequest,
                sendThematicOverviewRequest: widget.sendThematicOverviewRequest,
                sendVerseTextsRequest: widget.sendVerseTextsRequest,
              ),
      ),
    );
  }

  /// Shows [selected] in the active word pane, adding to its history, or in a
  /// new pane when asked (or when none is open yet).
  void _selectInspectorWord(_SelectedWord selected, {bool newPane = false}) {
    setState(() {
      final pane = _activeWordPane;
      if (pane == null || newPane) {
        final created = _WordPane('word-${_nextWordPaneId++}', selected);
        _wordPanes.add(created);
        _activeWordPaneId = created.id;
      } else {
        pane.history
          ..removeRange(pane.index + 1, pane.history.length)
          ..add(selected);
        pane.index = pane.history.length - 1;
      }
      _sidePanelView = _SidePanelView.word;
    });
  }

  /// Closes a word pane. The last one stays, as the inspector's only word.
  void _closeWordPane(String id) {
    if (_wordPanes.length < 2) return;
    final index = _wordPanes.indexWhere((pane) => pane.id == id);
    if (index < 0) return;
    setState(() {
      _wordPanes.removeAt(index);
      if (_activeWordPaneId == id) {
        _activeWordPaneId =
            _wordPanes[math.min(index, _wordPanes.length - 1)].id;
      }
    });
    _proximity.forget(id);
  }

  void _openInspectorWord(String word, String? bdbId) {
    final current = _selectedWord;
    if (current == null) return;
    _selectInspectorWord(
      _SelectedWord(
        word: word,
        bookIndex: bdbId == null ? current.bookIndex : 0,
        chapter: null,
        verse: null,
        position: null,
        root: '',
        bdbId: bdbId,
      ),
    );
  }

  void _moveInspectorHistory(int delta) {
    final pane = _activeWordPane;
    if (pane == null) return;
    final index = pane.index + delta;
    if (index < 0 || index >= pane.history.length) return;
    setState(() {
      pane.index = index;
      _sidePanelView = _SidePanelView.word;
    });
  }

  /// The side panel's header: a switcher between the open [views] when there
  /// are several, and the word history arrows while a word is shown. Without
  /// [views] it is the word inspector's own header.
  Widget _wordNavigationToolbar({
    List<_SidePanelView>? views,
    _SidePanelView current = _SidePanelView.word,
  }) => Padding(
    padding: const EdgeInsets.all(8),
    child: Row(
      children: [
        if (views != null)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_SidePanelView>(
                key: const ValueKey('side-panel-switcher'),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                segments: [
                  for (final view in views)
                    switch (view) {
                      _SidePanelView.study => const ButtonSegment(
                        value: _SidePanelView.study,
                        icon: Icon(Icons.account_tree_outlined),
                        label: Text('Study'),
                      ),
                      _SidePanelView.word => const ButtonSegment(
                        value: _SidePanelView.word,
                        icon: Icon(Icons.menu_book_outlined),
                        label: Text('Word'),
                      ),
                      _SidePanelView.crossReferences => const ButtonSegment(
                        value: _SidePanelView.crossReferences,
                        icon: Icon(Icons.link),
                        label: Text('Links'),
                      ),
                    },
                ],
                selected: {current},
                onSelectionChanged: (selection) {
                  setState(() => _sidePanelView = selection.single);
                },
              ),
            ),
          )
        else
          const Spacer(),
        if (current == _SidePanelView.word) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _canGoBackWord ? () => _moveInspectorHistory(-1) : null,
            tooltip: 'Back to previous word',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForwardWord
                ? () => _moveInspectorHistory(1)
                : null,
            tooltip: 'Forward to next word',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    ),
  );

  /// Switches between open word panes, as the study panel switches studies.
  Widget _wordPaneSelector() {
    final active = _activeWordPaneId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('word-pane-selector-$active'),
              initialValue: active,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final pane in _wordPanes)
                  DropdownMenuItem(
                    value: pane.id,
                    child: Text(
                      pane.word.word,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontFamily: 'Cardo',
                        fontFamilyFallback: ['Noto Serif Hebrew'],
                        fontSize: 18,
                      ),
                    ),
                  ),
              ],
              onChanged: (id) {
                if (id != null) setState(() => _activeWordPaneId = id);
              },
            ),
          ),
          IconButton(
            tooltip: 'Close word pane',
            icon: const Icon(Icons.close),
            onPressed: active == null ? null : () => _closeWordPane(active),
          ),
        ],
      ),
    );
  }

  Widget _wordInspector({bool showNavigation = true}) {
    final theme = Theme.of(context);
    final selected = _selectedWord;
    final activeIndex = _wordPanes.indexWhere(
      (pane) => pane.id == _activeWordPaneId,
    );
    return _movablePanel(
      _wordInspectorKey,
      Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          top: false,
          child: selected == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Select a Hebrew or Syriac word to keep its lexicon '
                      'and occurrences beside the passage.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (showNavigation) _wordNavigationToolbar(),
                    if (_wordPanes.length > 1) _wordPaneSelector(),
                    // Every pane stays built, so a hidden one keeps its tab,
                    // filters, and loaded occurrences, and can take part in a
                    // proximity search from the pane on show.
                    Expanded(
                      child: IndexedStack(
                        index: activeIndex,
                        children: [
                          for (final pane in _wordPanes)
                            KeyedSubtree(
                              key: ValueKey(pane.id),
                              child: TickerMode(
                                enabled: pane.id == _activeWordPaneId,
                                child: _wordInfoSheet(pane),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _wordInfoSheet(_WordPane pane) {
    final selected = pane.word;
    return WordInfoSheet(
      sendInfoRequest: widget.sendWordInfoRequest,
      sendOccurrencesRequest: widget.sendWordOccurrencesRequest,
      sendVerseTextsRequest: widget.sendVerseTextsRequest,
      key: ValueKey(
        '${selected.bookIndex}:${selected.chapter}:'
        '${selected.verse}:${selected.position}:${selected.word}:${selected.root}:${selected.bdbId}',
      ),
      docked: true,
      proximity: _proximity,
      proximityId: pane.id,
      word: selected.word,
      bdbId: selected.bdbId,
      onOpenWord: _openInspectorWord,
      initialRoot: selected.root.isEmpty ? null : selected.root,
      syriac: selected.bookIndex >= 39,
      ntSyriac: _activeReader?._ntSyriac ?? false,
      book: selected.chapter == null ? null : selected.bookIndex + 1,
      chapter: selected.chapter,
      verse: selected.verse,
      position: selected.position,
      readerGloss: selected.readerGloss,
      useEnglishBookNames: _activeReader?._englishBookNames ?? false,
      reportContext: {
        if (selected.chapter != null) ...{
          'bookIndex': selected.bookIndex,
          'book': kBooks[selected.bookIndex].transliteration,
          'chapter': selected.chapter,
          'verse': selected.verse,
        },
      },
      isStudyBookmarked: (bookmark) =>
          _activeReader?._activeStudyWorkspace?.wordForBookmark(bookmark) !=
          null,
      onToggleStudyBookmark: (bookmark) async {
        return await _activeReader?._toggleStudyWordBookmark(bookmark) ?? false;
      },
      nameBookmarks: _activeReader?._nameBookmarks,
      onNavigateToPassage: (book, chapter, verse) {
        _activeReader?._navigateTo(book, chapter, verse: verse);
        if (_mobileLayout == true) _showReaderPage();
      },
    );
  }

  double _resolvedSidePanelWidth(double availableWidth) =>
      _sidePanelWidth.clamp(280, math.max(280, availableWidth - 420));

  Widget _sidePanelResizeHandle(double availableWidth) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidePanelWidth = (_sidePanelWidth - details.delta.dx).clamp(
            280,
            math.max(280, availableWidth - 420),
          );
        });
      },
      onHorizontalDragEnd: (_) => _saveWorkspace(),
      child: Tooltip(
        message: 'Drag to resize side panel',
        child: SizedBox(
          width: 9,
          child: Center(
            child: Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _responsiveWorkspaceBody(Widget reader) {
    if (_mobileLayout == true) return reader;
    final layout =
        _activeReader?._resolveReaderLayout(MediaQuery.sizeOf(context).width) ??
        _ResolvedReaderLayout.focus;
    switch (layout) {
      case _ResolvedReaderLayout.focus:
      case _ResolvedReaderLayout.split:
        if (!_studyWorkspaceVisible &&
            _selectedWord == null &&
            !_crossReferencesVisible) {
          return reader;
        }
        return LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(child: reader),
              _sidePanelResizeHandle(constraints.maxWidth),
              SizedBox(
                width: _resolvedSidePanelWidth(constraints.maxWidth),
                child: _tiledAuxiliaryPanel(),
              ),
            ],
          ),
        );
      case _ResolvedReaderLayout.threePanel:
        return LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (_studyWorkspaceVisible) ...[
                SizedBox(width: 300, child: _studyWorkspacePanel()),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: reader),
              _sidePanelResizeHandle(
                constraints.maxWidth - (_studyWorkspaceVisible ? 301 : 0),
              ),
              SizedBox(
                width: _resolvedSidePanelWidth(
                  constraints.maxWidth - (_studyWorkspaceVisible ? 301 : 0),
                ),
                // The word inspector, with its prompt while no word is chosen,
                // sharing the side with cross references when they are open.
                child: _sidePanel([
                  if (_selectedWord != null || !_crossReferencesVisible)
                    _SidePanelView.word,
                  if (_crossReferencesVisible) _SidePanelView.crossReferences,
                ]),
              ),
            ],
          ),
        );
    }
  }

  _ReaderSessionState? get _activeReader =>
      _readerKeys[_activeTabId]?.currentState;

  List<_ReaderMenuAction> get _workspaceActions => [
    _ReaderMenuAction.studyWorkspace,
    _ReaderMenuAction.readingPlan,
    _ReaderMenuAction.places,
    _ReaderMenuAction.tutor,
    _ReaderMenuAction.memorise,
    if (_activeReader?._adminMode ?? false) _ReaderMenuAction.reportIssue,
    _ReaderMenuAction.settings,
    _ReaderMenuAction.about,
  ];

  (IconData, String) _workspaceActionPresentation(_ReaderMenuAction action) =>
      switch (action) {
        _ReaderMenuAction.studyWorkspace => (
          Icons.account_tree_outlined,
          'Study workspace',
        ),
        _ReaderMenuAction.crossReferences => (Icons.link, 'Cross references'),
        _ReaderMenuAction.readingPlan => (
          Icons.auto_stories_outlined,
          'Reading plan',
        ),
        _ReaderMenuAction.places => (Icons.travel_explore, 'Bible places'),
        _ReaderMenuAction.tutor => (Icons.school_outlined, 'Tutor'),
        _ReaderMenuAction.memorise => (Icons.psychology_outlined, 'Memorise'),
        _ReaderMenuAction.reportIssue => (
          Icons.flag_outlined,
          'Report an issue',
        ),
        _ReaderMenuAction.settings => (Icons.settings_outlined, 'Settings'),
        _ReaderMenuAction.about => (Icons.info_outline, 'About'),
      };

  PopupMenuEntry<_ReaderMenuAction> _workspaceMenuItem(
    _ReaderMenuAction action,
  ) {
    final (icon, label) = _workspaceActionPresentation(action);
    return PopupMenuItem(
      value: action,
      child: ListTile(leading: Icon(icon), title: Text(label)),
    );
  }

  Widget _workspaceActionButton(_ReaderMenuAction action) {
    final (icon, label) = _workspaceActionPresentation(action);
    final studySelected =
        action == _ReaderMenuAction.studyWorkspace &&
        (_mobileLayout == true
            ? _studyPageSelected
            : (_activeReader?._studyWorkspaceVisible ?? false));
    final crossReferencesSelected =
        action == _ReaderMenuAction.crossReferences &&
        _mobileLayout != true &&
        _crossReferencesVisible;
    return IconButton(
      isSelected: studySelected || crossReferencesSelected,
      selectedIcon: action == _ReaderMenuAction.studyWorkspace
          ? const Icon(Icons.account_tree)
          : null,
      icon: Icon(icon),
      tooltip: label,
      onPressed: () => _handleWorkspaceMenuAction(action),
    );
  }

  Future<void> _showSharedReaderSettings() async {
    final active = _activeReader;
    if (active == null) return;
    await showAppSettings(
      context,
      readingSettings: active._readingSettings,
      onReadingSettingsChanged: (settings) {
        for (final key in _readerKeys.values) {
          key.currentState?._applyReadingSettings(settings);
        }
        if (mounted) setState(() {});
      },
    );
    for (final key in _readerKeys.values) {
      key.currentState?._loadAdminMode();
    }
  }

  void _handleWorkspaceMenuAction(_ReaderMenuAction action) {
    if (action == _ReaderMenuAction.studyWorkspace && _mobileLayout == true) {
      _showPage(_studyPageSelected ? _activeReaderPage : 0);
      return;
    }
    if (action == _ReaderMenuAction.settings) {
      _showSharedReaderSettings();
      return;
    }
    // Docked, the toolbar button shows and hides the panel as the study
    // button does; opening it starts on the selected verse, if any.
    if (action == _ReaderMenuAction.crossReferences &&
        _mobileLayout != true &&
        _crossReferencesVisible) {
      setState(() => _crossReferencesVisible = false);
      return;
    }
    if (action == _ReaderMenuAction.studyWorkspace) {
      setState(() => _sidePanelView = _SidePanelView.study);
    }
    _activeReader?._handleReaderMenuAction(action);
  }

  void _setMobileBarHidden(bool hidden) {
    if (_mobileBarTransitionTimer?.isActive ?? false) return;
    setState(() => _mobileBarHidden = hidden);
    _mobileBarTransitionTimer = Timer(const Duration(milliseconds: 200), () {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final canTile = !mobile;
    final tiled = _tiled && canTile && _tabs.length > 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: AnimatedContainer(
                key: const ValueKey('reader-workspace-bar'),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: mobile && _mobileBarHidden ? 0 : 48,
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final actions = _workspaceActions;
                      final tabWidth = math.min(
                        constraints.maxWidth * 0.7,
                        _tabs.length * 150.0,
                      );
                      final fixedWidth = 48.0 + (canTile ? 48 : 0) + 48;
                      final directActionCount = mobile
                          ? 1
                          : ((constraints.maxWidth - tabWidth - fixedWidth) ~/
                                    48)
                                .clamp(0, actions.length);
                      final directActions = actions.take(directActionCount);
                      final overflowActions = actions.skip(directActionCount);

                      return Row(
                        children: [
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              scrollDirection: Axis.horizontal,
                              itemCount: _tabs.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 4),
                              itemBuilder: (context, index) {
                                final tab = _tabs[index];
                                return InputChip(
                                  label: _tabLabel(tab),
                                  selected:
                                      !_studyPageSelected &&
                                      !_wordPageSelected &&
                                      !_crossReferencesPageSelected &&
                                      tab.id == _activeTabId,
                                  onPressed: () {
                                    setState(() => _activeTabId = tab.id);
                                    _showReaderPage();
                                    _saveWorkspace();
                                  },
                                  onDeleted: _tabs.length > 1
                                      ? () => _closeTab(tab.id)
                                      : null,
                                  deleteButtonTooltipMessage:
                                      'Close reader tab',
                                );
                              },
                            ),
                          ),
                          for (final action in directActions)
                            _workspaceActionButton(action),
                          if (_hasWordPage)
                            IconButton(
                              isSelected: _wordPageSelected,
                              selectedIcon: const Icon(Icons.menu_book),
                              icon: const Icon(Icons.menu_book_outlined),
                              tooltip: 'Word info',
                              onPressed: () => _showPage(
                                _wordPageSelected
                                    ? _activeReaderPage
                                    : _wordPageIndex,
                              ),
                            ),
                          if (_hasCrossReferencesPage)
                            IconButton(
                              isSelected: _crossReferencesPageSelected,
                              icon: const Icon(Icons.link),
                              tooltip: 'Cross references',
                              onPressed: () => _showPage(
                                _crossReferencesPageSelected
                                    ? _activeReaderPage
                                    : _crossReferencesPageIndex,
                              ),
                            ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'New reader tab',
                            onPressed: _addTab,
                          ),
                          if (canTile)
                            IconButton(
                              isSelected: tiled,
                              selectedIcon: const Icon(Icons.view_column),
                              icon: const Icon(Icons.view_column_outlined),
                              tooltip: tiled
                                  ? 'Show reader tabs'
                                  : 'Tile reader tabs',
                              onPressed: _tabs.length > 1
                                  ? () {
                                      setState(() => _tiled = !_tiled);
                                      _saveWorkspace();
                                    }
                                  : null,
                            ),
                          if (overflowActions.isNotEmpty)
                            PopupMenuButton<_ReaderMenuAction>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: 'Reader options',
                              enabled: _activeReader != null,
                              onSelected: _handleWorkspaceMenuAction,
                              itemBuilder: (_) => [
                                for (final action in overflowActions)
                                  _workspaceMenuItem(action),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              child: Focus(
                onKeyEvent: _handleWorkspaceKey,
                child: tiled
                    ? _ResponsiveTiledWorkspace(
                        readers: [
                          for (final tab in _tabs)
                            _WorkspaceTile(
                              id: 'reader:${tab.id}',
                              child: _reader(tab, tiled: true),
                            ),
                        ],
                        activeReaderId: 'reader:$_activeTabId',
                        auxiliaryPanel: _tiledAuxiliaryPanel(),
                        auxiliaryPanelWidth: _tiledPanelWidth,
                        onAuxiliaryPanelWidthChanged: (width) {
                          setState(() => _tiledPanelWidth = width);
                        },
                        onAuxiliaryPanelResizeEnd: _saveWorkspace,
                      )
                    : _responsiveWorkspaceBody(
                        PageView(
                          key: ValueKey(mobile),
                          controller: _pageController,
                          onPageChanged: (index) {
                            if (_pageTarget == null) _selectPage(index);
                          },
                          children: [
                            if (mobile)
                              Material(
                                key: const ValueKey('study-workspace-page'),
                                child:
                                    _activeReader?._studyWorkspacePanel(
                                      onOpenReader: _showReaderPage,
                                    ) ??
                                    const SizedBox.shrink(),
                              ),
                            for (final tab in _tabs) _reader(tab, tiled: false),
                            if (_hasWordPage)
                              _WordInfoPage(
                                key: const ValueKey('word-info-page'),
                                active: _wordPageSelected,
                                // Leave a swipe margin outside the inspector's
                                // text selection and lexicon/occurrence tabs.
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: _wordInspector(),
                                ),
                              ),
                            if (_hasCrossReferencesPage)
                              _WordInfoPage(
                                key: const ValueKey('cross-references-page'),
                                active: _crossReferencesPageSelected,
                                child: _crossReferencesPanel(),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Keep lexicon/occurrence tabs, filters, and loaded results (and the cross
// references page's) when swiping back to a reader. Reader sessions have their own independent keep-alive state.
class _WordInfoPage extends StatefulWidget {
  const _WordInfoPage({super.key, required this.child, required this.active});

  final Widget child;
  final bool active;

  @override
  State<_WordInfoPage> createState() => _WordInfoPageState();
}

class _WordInfoPageState extends State<_WordInfoPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(enabled: widget.active, child: widget.child);
  }
}

class _ResponsiveTiledWorkspace extends StatelessWidget {
  const _ResponsiveTiledWorkspace({
    required this.readers,
    required this.activeReaderId,
    required this.auxiliaryPanel,
    required this.auxiliaryPanelWidth,
    required this.onAuxiliaryPanelWidthChanged,
    required this.onAuxiliaryPanelResizeEnd,
  });

  final List<_WorkspaceTile> readers;
  final String activeReaderId;
  final Widget? auxiliaryPanel;
  final double auxiliaryPanelWidth;
  final ValueChanged<double> onAuxiliaryPanelWidthChanged;
  final VoidCallback onAuxiliaryPanelResizeEnd;

  List<_WorkspaceTile> _visibleReaders(int count) {
    if (count >= readers.length) return readers;
    final activeIndex = readers.indexWhere(
      (reader) => reader.id == activeReaderId,
    );
    final start = (activeIndex - count + 1).clamp(0, readers.length - count);
    return readers.sublist(start, start + count);
  }

  Widget _divider(BuildContext context, double availableWidth) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        onAuxiliaryPanelWidthChanged(
          (auxiliaryPanelWidth - details.delta.dx).clamp(
            _workspaceMinimumTileWidth,
            availableWidth -
                _workspaceMinimumTileWidth -
                _workspacePanelDividerWidth,
          ),
        );
      },
      onHorizontalDragEnd: (_) => onAuxiliaryPanelResizeEnd(),
      child: Tooltip(
        message: 'Drag to resize study and word panel',
        child: SizedBox(
          width: _workspacePanelDividerWidth,
          child: Center(
            child: Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final hasPanel = auxiliaryPanel != null;
      final panelWidth = hasPanel
          ? auxiliaryPanelWidth.clamp(
              _workspaceMinimumTileWidth,
              constraints.maxWidth -
                  _workspaceMinimumTileWidth -
                  _workspacePanelDividerWidth,
            )
          : 0.0;
      final readerSpace =
          constraints.maxWidth -
          panelWidth -
          (hasPanel ? _workspacePanelDividerWidth : 0);
      final visibleCount = math.min(
        readers.length,
        math.max(1, readerSpace ~/ _workspaceMinimumTileWidth),
      );
      final visibleReaders = _visibleReaders(visibleCount);

      return Row(
        children: [
          for (var index = 0; index < visibleReaders.length; index++) ...[
            if (index > 0) const VerticalDivider(width: 1),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(visibleReaders[index].id),
                child: visibleReaders[index].child,
              ),
            ),
          ],
          if (hasPanel) ...[
            _divider(context, constraints.maxWidth),
            SizedBox(
              key: const ValueKey('study-word-panel'),
              width: panelWidth,
              child: auxiliaryPanel,
            ),
          ],
        ],
      );
    },
  );
}

class _ReaderSession extends StatefulWidget {
  const _ReaderSession({
    super.key,
    required this.sessionId,
    required this.onPassageChanged,
    required this.onScrollChromeChanged,
    required this.tiled,
    required this.onWorkspaceTilesChanged,
    required this.onWordInfoRequested,
    required this.onCrossReferencesRequested,
    required this.studyStore,
    this.sendChapterRequest,
    this.sendSyntaxTreesRequest,
    this.sendTranslationRequest,
    this.sendVerseTextsRequest,
  });

  final String sessionId;

  /// The study workspaces, shared with the other readers.
  final StudyWorkspaceStore studyStore;
  final VoidCallback onPassageChanged;
  final ValueChanged<bool> onScrollChromeChanged;
  final bool tiled;
  final VoidCallback onWorkspaceTilesChanged;

  /// Shows a word in the active word pane, or in a new one beside it.
  final void Function(_SelectedWord selected, {bool newPane})
  onWordInfoRequested;

  /// A verse's cross references (0-based book), or with no verse the overview
  /// of a chapter: docked beside the reader where there is room.
  final void Function(int bookIndex, int chapter, int? verse)
  onCrossReferencesRequested;

  /// Test seam: how a [GetChapter] request reaches the Rust side. Defaults to
  /// the real rinf signal; widget tests substitute a stub that answers via
  /// `assignRustSignal['ChapterText']`.
  final void Function(GetChapter request)? sendChapterRequest;

  /// Test seam: how a [GetSyntaxTrees] request for the reader's role
  /// colouring reaches the Rust side.
  final void Function(GetSyntaxTrees request)? sendSyntaxTreesRequest;

  /// Test seam: how a [GetChapterTranslation] request for the reader's
  /// English reaches the Rust side.
  final void Function(GetChapterTranslation request)? sendTranslationRequest;

  /// Test seam: how the Syntax sheet asks for its verse's words.
  final void Function(GetVerseTexts request)? sendVerseTextsRequest;

  static Future<void> seedNavigation(
    String sessionId,
    int book,
    int chapter,
    int verse,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'reader_session_${sessionId}_';
    await Future.wait([
      prefs.setInt('${prefix}book', book),
      prefs.setInt('${prefix}chapter', chapter),
      prefs.setInt('${prefix}verse', verse),
    ]);
  }

  @override
  State<_ReaderSession> createState() => _ReaderSessionState();
}

class _ReaderSessionState extends State<_ReaderSession>
    with AutomaticKeepAliveClientMixin {
  static const _kBook = 'book';
  static const _kChapter = 'chapter';
  static const _kVerse = 'verse';
  static const _kHistory = 'nav_history';
  static const _kHistoryIndex = 'nav_history_index';
  static const _kCrossReferenceMinScore = 'cross_reference_min_score';
  static const _kReadingPlanBook = 'reading_plan_book';
  static const _kReadingPlanCompleted = 'reading_plan_completed';
  static const _kReadingPlans = 'reading_plans';
  static const _kStudyWorkspaceVisible = 'study_workspace_visible';

  // Displayed in AppBar — tracks the chapter currently at the top of the viewport
  int _bookIndex = 0;
  int _chapter = 1;
  int _visibleVerse = 1;

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
  // Requests in flight when a lexicon correction landed: their replies may hold
  // the old gloss, so they are not cached.
  final Set<_ChapterRequest> _staleFetches = {};
  // Requests that timed out, by whether they were prefetches, in case the
  // reply still comes.
  final Map<_ChapterRequest, bool> _lateFetches = {};
  final LinkedHashMap<_ChapterRequest, List<VerseEntry>> _chapterCache =
      LinkedHashMap();
  bool _initialLoading = true;
  bool _loadingNext = false;
  bool _loadingPrev = false;

  bool _ntSyriac = false;
  bool _englishBookNames = false;
  bool _hebrewNumerals = true;

  // How strong a cross reference must be to be listed or marked; shared by
  // the panel's strength filter and the verse-number markers.
  double _crossReferenceMinScore = 0;
  double _fontSize = 20.0;
  String _fontFamily = 'Cardo';
  bool _showCantillation = true;
  bool _glossInterlinear = false;
  bool _morphologyInterlinear = false;
  bool _rapidReading = false;
  bool _showInterlinear = true;
  RapidReveal _rapidReveal = RapidReveal.verse;

  // What rapid reading has revealed, by (book index, chapter, verse): the
  // lexical positions shown, or null for the whole verse.
  final Map<(int, int, int), Set<int>?> _revealed = {};
  bool _highlightProperNames = false;
  bool _syntaxRoles = false;
  SyntaxView _syntaxView = SyntaxView.outline;
  ReaderText _readerText = ReaderText.source;
  bool _studyWorkspaceVisible = false;
  KetivDisplay _ketivDisplay = KetivDisplay.superscript;
  ReaderLayoutMode _readerLayoutMode = ReaderLayoutMode.automatic;
  List<_ReadingPlan> _readingPlans = [];
  List<StudyWorkspace> get _studyWorkspaces => widget.studyStore.workspaces;
  String? get _activeStudyWorkspaceId => widget.studyStore.activeId;
  double _chromeScrollDelta = 0;
  double? _lastChromeScrollPixels;
  Timer? _positionSaveTimer;
  final _scrollViewKey = GlobalKey();
  bool _passageUpdateScheduled = false;

  @override
  bool get wantKeepAlive => true;

  String _sessionKey(String key) => widget.sessionId == 'primary'
      ? key
      : 'reader_session_${widget.sessionId}_$key';

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
  StreamSubscription<RustSignalPack<SyntaxTrees>>? _syntaxSub;

  /// Each OT chapter's syntax marks by verse, keyed by (0-based book,
  /// chapter), once asked for: the reader asks the first time a row of the
  /// chapter shows with [_syntaxRoles] on.
  final Map<(int, int), Map<int, VerseSyntaxMarks>> _syntaxMarks = {};

  /// The chapters whose trees are on their way, by request id.
  final Map<int, (int, int)> _syntaxRequests = {};
  static int _nextSyntaxRequestId = 1;

  StreamSubscription<RustSignalPack<ChapterTranslation>>? _translationSub;

  /// Each OT chapter's English by verse, keyed by (0-based book, chapter),
  /// once asked for: the reader asks the first time a row of the chapter
  /// shows with the English on.
  final Map<(int, int), Map<int, List<TranslationSpanEntry>>> _translations =
      {};

  /// The chapters whose English is on its way, by request id.
  final Map<int, (int, int)> _translationRequests = {};
  static int _nextTranslationRequestId = 1;
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
        msg.includeMorphology,
        msg.includeNames,
        msg.includeRoots,
      );
      // A reply after the timeout is still the chapter, so it is kept and, if
      // the chapter is still wanted, shown in place of the error.
      final late = _lateFetches.remove(fetchKey);
      if (!_pendingFetches.remove(fetchKey) && late == null) return;
      _fetchTimeouts.remove(fetchKey)?.cancel();
      final prefetch = _prefetches.remove(fetchKey) || late == true;
      if (_staleFetches.remove(fetchKey)) {
        if (!prefetch) _fetchChapter(msg.book - 1, msg.chapter, force: true);
        return;
      }
      _cacheChapter(fetchKey, msg.verses);
      if (prefetch) return;
      final bookIdx = msg.book - 1;
      // Asked for before a setting changed: the verses would lack what the
      // setting now shows, so ask again as the page now wants them.
      if (fetchKey != _chapterRequest(bookIdx, msg.chapter)) {
        _fetchChapter(bookIdx, msg.chapter, force: true);
        return;
      }
      if (late == false && mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      _acceptChapter(bookIdx, msg.chapter, msg.verses, fetchKey);
    });
    _syntaxSub = SyntaxTrees.rustSignalStream.listen((pack) {
      final chapter = _syntaxRequests.remove(pack.message.requestId);
      if (chapter == null || !mounted) return;
      setState(() {
        _syntaxMarks[chapter] = {
          for (final verse in pack.message.verses)
            if (SyntaxTreeNode.fromEntry(verse) case final tree?)
              verse.verse: VerseSyntaxMarks.of(tree),
        };
      });
    });
    _translationSub = ChapterTranslation.rustSignalStream.listen((pack) {
      final chapter = _translationRequests.remove(pack.message.requestId);
      if (chapter == null || !mounted) return;
      setState(() {
        _translations[chapter] = {
          for (final verse in pack.message.verses) verse.verse: verse.spans,
        };
      });
    });
    _lexiconOverrideSub = LexiconEntryOverrideStatus.rustSignalStream.listen((
      pack,
    ) {
      if (mounted && pack.message.success) _refreshLoadedOtChapters();
    });
    widget.studyStore.addListener(_onStudyStoreChanged);
    _loadPrefs();
    _loadAdminMode();
  }

  void _onStudyStoreChanged() {
    if (!mounted) return;
    setState(() {});
    // Workspaces from Rust can turn root highlighting on or off.
    _refreshLoadedChaptersForStudyRoots();
  }

  Future<void> _loadAdminMode() async {
    final enabled = await adminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  /// A verse's syntax marks while the reader colours roles; null otherwise,
  /// and while its chapter's trees are on their way, which the first row to
  /// ask for them sends for.
  VerseSyntaxMarks? _syntaxMarksFor(int bookIndex, int chapter, int verse) {
    if (!_syntaxRoles || bookIndex >= 39) return null;
    final marks = _syntaxMarks[(bookIndex, chapter)];
    if (marks == null) {
      _requestSyntax(bookIndex, chapter);
      return null;
    }
    return marks[verse] ?? VerseSyntaxMarks.empty;
  }

  /// A verse's English while the reader shows it, and whether it is still on
  /// its way, which the first row to ask for its chapter sends for. Null and
  /// not pending for a verse without English, the New Testament's included.
  ({List<TranslationSpanEntry>? spans, bool pending}) _translationFor(
    int bookIndex,
    int chapter,
    int verse,
  ) {
    if (_readerText == ReaderText.source || bookIndex >= 39) {
      return (spans: null, pending: false);
    }
    final verses = _translations[(bookIndex, chapter)];
    if (verses == null) {
      _requestTranslation(bookIndex, chapter);
      return (spans: null, pending: true);
    }
    return (spans: verses[verse], pending: false);
  }

  void _requestTranslation(int bookIndex, int chapter) {
    if (_translationRequests.containsValue((bookIndex, chapter))) return;
    final id = _nextTranslationRequestId++;
    _translationRequests[id] = (bookIndex, chapter);
    final request = GetChapterTranslation(
      requestId: id,
      book: bookIndex + 1,
      chapter: chapter,
    );
    final send = widget.sendTranslationRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  /// The Hebrew word an English word renders, as a word tap would name it:
  /// its text, gloss and root, read from its verse's row. Null when that
  /// verse is not loaded, which a word of the verse beside it rarely is not.
  ({String word, String? gloss, String root})? _translatedWord(
    int bookIndex,
    TranslationWordEntry target,
  ) {
    final section = _sections
        .where((s) => s.bookIndex == bookIndex && s.chapter == target.chapter)
        .firstOrNull;
    final entry = section?.verses
        .where((v) => v.verse == target.verse)
        .firstOrNull;
    if (entry == null) return null;
    final words = entry.text.split(' ').where((w) => w.isNotEmpty).toList();
    final positions = verseGlossPositions(words);
    final index = positions.indexOf(target.position);
    if (index < 0) return null;
    final position = target.position;
    return (
      word: words[index],
      gloss: position < entry.glosses.length ? entry.glosses[position] : null,
      root: position < entry.roots.length ? entry.roots[position] : '',
    );
  }

  void _cycleReaderText() => _setReaderText(_readerText.next);

  void _setReaderText(ReaderText text) {
    setState(() => _readerText = text);
    _savePrefs();
  }

  /// The reader's top-bar actions, as many as [width] leaves room for beside
  /// the title. Rapid reading always keeps its button, being the toggle a
  /// reader reaches for mid-passage; the rest give way in [_barPriority]
  /// order to one overflow menu.
  List<Widget> _barActions(double width) {
    const titleRoom = 200.0;
    final slots = ((width - titleRoom) / kMinInteractiveDimension).floor();
    final others = _ReaderBarAction.values
        .where((action) => action != _ReaderBarAction.rapidReading)
        .toList();
    final Set<_ReaderBarAction> shown;
    if (slots >= _ReaderBarAction.values.length) {
      shown = _ReaderBarAction.values.toSet();
    } else {
      // One slot for rapid reading and one for the menu.
      shown = {
        _ReaderBarAction.rapidReading,
        ..._barPriority.take(math.max(0, slots - 2)),
      };
    }
    final overflow = others.where((action) => !shown.contains(action));
    return [
      for (final action in _ReaderBarAction.values)
        if (shown.contains(action)) _barButton(action),
      if (overflow.isNotEmpty)
        PopupMenuButton<Object>(
          key: const ValueKey('reader-view-menu'),
          icon: const Icon(Icons.more_vert),
          tooltip: 'More',
          onSelected: (choice) => switch (choice) {
            ReaderText text => _setReaderText(text),
            _ReaderBarAction action => _runBarAction(action),
            _ => null,
          },
          itemBuilder: (context) => [
            for (final action in overflow) ..._barMenuItems(action),
          ],
        ),
    ];
  }

  /// Which actions stay in the bar as it narrows, the first kept longest.
  static const _barPriority = [
    _ReaderBarAction.interlinear,
    _ReaderBarAction.text,
    _ReaderBarAction.back,
    _ReaderBarAction.forward,
    _ReaderBarAction.crossReferences,
    _ReaderBarAction.places,
    _ReaderBarAction.people,
  ];

  void _runBarAction(_ReaderBarAction action) => switch (action) {
    _ReaderBarAction.crossReferences => widget.onCrossReferencesRequested(
      _bookIndex,
      _chapter,
      null,
    ),
    _ReaderBarAction.places => _showChapterPlaces(),
    _ReaderBarAction.people => _showChapterPeople(),
    _ReaderBarAction.text => _cycleReaderText(),
    _ReaderBarAction.interlinear => _toggleInterlinear(),
    _ReaderBarAction.rapidReading => _toggleRapidReading(),
    _ReaderBarAction.back => _canGoBack ? _goBack() : null,
    _ReaderBarAction.forward => _canGoForward ? _goForward() : null,
  };

  Widget _barButton(_ReaderBarAction action) => switch (action) {
    _ReaderBarAction.crossReferences => IconButton(
      key: const ValueKey('reader-cross-references'),
      icon: const Icon(Icons.link),
      onPressed: () => _runBarAction(action),
      tooltip: 'Cross references in this chapter',
    ),
    _ReaderBarAction.places => IconButton(
      key: const ValueKey('reader-places'),
      icon: const Icon(Icons.map_outlined),
      onPressed: _isOldTestament ? () => _runBarAction(action) : null,
      tooltip: 'Places in this chapter',
    ),
    _ReaderBarAction.people => IconButton(
      key: const ValueKey('reader-people'),
      icon: const Icon(Icons.people_outline),
      onPressed: _isOldTestament ? () => _runBarAction(action) : null,
      tooltip: 'People in this chapter',
    ),
    _ReaderBarAction.text => IconButton(
      key: const ValueKey('reader-text-toggle'),
      icon: Icon(switch (_readerText) {
        ReaderText.source => Icons.format_textdirection_r_to_l,
        ReaderText.english => Icons.format_textdirection_l_to_r,
        ReaderText.parallel => Icons.vertical_split_outlined,
      }),
      onPressed: _cycleReaderText,
      tooltip: '${_readerText.label} · switch to ${_readerText.next.label}',
    ),
    _ReaderBarAction.interlinear => IconButton(
      key: const ValueKey('reader-interlinear-toggle'),
      isSelected: _interlinearShown,
      icon: const Icon(Icons.subtitles_off_outlined),
      selectedIcon: const Icon(Icons.subtitles),
      onPressed: _toggleInterlinear,
      tooltip: _interlinearShown ? 'Hide interlinear' : 'Show interlinear',
    ),
    _ReaderBarAction.rapidReading => IconButton(
      key: const ValueKey('reader-rapid-toggle'),
      isSelected: _rapidReading,
      icon: const Icon(Icons.touch_app_outlined),
      selectedIcon: const Icon(Icons.touch_app),
      onPressed: _toggleRapidReading,
      tooltip: _rapidReading ? 'Stop rapid reading' : 'Rapid reading',
    ),
    _ReaderBarAction.back => IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: _canGoBack ? _goBack : null,
      tooltip: 'Back',
    ),
    _ReaderBarAction.forward => IconButton(
      icon: const Icon(Icons.arrow_forward),
      onPressed: _canGoForward ? _goForward : null,
      tooltip: 'Forward',
    ),
  };

  List<PopupMenuEntry<Object>> _barMenuItems(_ReaderBarAction action) {
    PopupMenuItem<Object> item(IconData icon, String label, {bool? enabled}) =>
        PopupMenuItem(
          value: action,
          enabled: enabled ?? true,
          child: ListTile(leading: Icon(icon), title: Text(label)),
        );
    return switch (action) {
      _ReaderBarAction.crossReferences => [
        item(Icons.link, 'Cross references'),
      ],
      _ReaderBarAction.places => [
        item(Icons.map_outlined, 'Places', enabled: _isOldTestament),
      ],
      _ReaderBarAction.people => [
        item(Icons.people_outline, 'People', enabled: _isOldTestament),
      ],
      _ReaderBarAction.text => [
        for (final text in ReaderText.values)
          CheckedPopupMenuItem(
            value: text,
            checked: text == _readerText,
            child: Text(text.label),
          ),
        const PopupMenuDivider(),
      ],
      _ReaderBarAction.interlinear => [
        CheckedPopupMenuItem(
          value: action,
          checked: _interlinearShown,
          child: const Text('Interlinear'),
        ),
      ],
      _ReaderBarAction.rapidReading => const [],
      _ReaderBarAction.back => [
        item(Icons.arrow_back, 'Back', enabled: _canGoBack),
      ],
      _ReaderBarAction.forward => [
        item(Icons.arrow_forward, 'Forward', enabled: _canGoForward),
      ],
    };
  }

  void _requestSyntax(int bookIndex, int chapter) {
    if (_syntaxRequests.containsValue((bookIndex, chapter))) return;
    final id = _nextSyntaxRequestId++;
    _syntaxRequests[id] = (bookIndex, chapter);
    final request = GetSyntaxTrees(
      requestId: id,
      book: bookIndex + 1,
      chapter: chapter,
      firstVerse: 0,
      lastVerse: 0,
    );
    final send = widget.sendSyntaxTreesRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  void _acceptChapter(
    int bookIdx,
    int chapter,
    List<VerseEntry> verses,
    _ChapterRequest request,
  ) {
    // A successful in-app lexicon edit re-requests the loaded OT chapters so
    // their interlinear glosses update behind the word-info sheet. Preserve
    // the existing section/key to avoid disturbing the scroll position.
    final loadedIndex = _sections.indexWhere(
      (s) => s.bookIndex == bookIdx && s.chapter == chapter,
    );
    if (loadedIndex >= 0) {
      setState(() {
        final loaded = _sections[loadedIndex];
        loaded.verses = verses;
        loaded.request = request;
        for (final verse in verses) {
          loaded.verseKeys.putIfAbsent(verse.verse, GlobalKey.new);
        }
      });
      return;
    }

    final section = _Section(
      bookIndex: bookIdx,
      chapter: chapter,
      verses: verses,
      request: request,
    );

    if (_sections.isEmpty) {
      // A reply for a chapter the reader has since left is not the one wanted.
      if (bookIdx != _bookIndex || chapter != _chapter) return;
      int? targetVerse;
      if (_pendingVerse != null &&
          bookIdx == _bookIndex &&
          chapter == _chapter) {
        targetVerse = _pendingVerse;
        _selectedBook = bookIdx;
        _selectedChapter = chapter;
        _selectedVerse = targetVerse;
        _targetVerseKey = section.verseKeys[targetVerse];
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
    if (!mounted) return;
    final reading = readReadingSettings(prefs);
    setState(() {
      _bookIndex = (prefs.readInt(_sessionKey(_kBook)) ?? 0).clamp(
        0,
        kBooks.length - 1,
      );
      _chapter = (prefs.readInt(_sessionKey(_kChapter)) ?? 1).clamp(
        1,
        kBooks[_bookIndex].chapters,
      );
      _visibleVerse = (prefs.readInt(_sessionKey(_kVerse)) ?? 1).clamp(1, 999);
      _adoptReadingSettings(reading);
      _crossReferenceMinScore = prefs.readDouble(_kCrossReferenceMinScore) ?? 0;
      _studyWorkspaceVisible = prefs.readBool(_kStudyWorkspaceVisible) ?? false;
      final savedPlans = prefs.readStringList(_kReadingPlans);
      if (savedPlans != null) {
        _readingPlans = savedPlans
            .map(_ReadingPlan.fromStorageString)
            .whereType<_ReadingPlan>()
            .toList();
      } else {
        final planBook = prefs.readInt(_kReadingPlanBook);
        if (planBook != null && planBook >= 0 && planBook < kBooks.length) {
          _readingPlans = [
            _ReadingPlan(
              bookIndex: planBook,
              completed: {
                for (final chapter
                    in (prefs.readStringList(_kReadingPlanCompleted) ?? [])
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
    final rawHistory = prefs.readStringList(_sessionKey(_kHistory)) ?? [];
    final savedIndex = prefs.readInt(_sessionKey(_kHistoryIndex)) ?? -1;
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
        widget.onPassageChanged();
        return;
      }
    }
    _history.clear();
    _pendingVerse = _visibleVerse;
    _history.add(
      _PassageRef(
        bookIndex: _bookIndex,
        chapter: _chapter,
        verse: _visibleVerse,
      ),
    );
    _historyIndex = 0;
    _startAt(_bookIndex, _chapter);
    widget.onPassageChanged();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(
        _sessionKey(_kHistory),
        _history.map((r) => r.toStorageString()).toList(),
      ),
      prefs.setInt(_sessionKey(_kHistoryIndex), _historyIndex),
    ]);
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setInt(_sessionKey(_kBook), _bookIndex),
      prefs.setInt(_sessionKey(_kChapter), _chapter),
      prefs.setInt(_sessionKey(_kVerse), _visibleVerse),
      writeReadingSettings(prefs, _readingSettings),
      prefs.setDouble(_kCrossReferenceMinScore, _crossReferenceMinScore),
      prefs.setBool(_kStudyWorkspaceVisible, _studyWorkspaceVisible),
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
        settings.morphologyInterlinear != _morphologyInterlinear ||
        settings.highlightProperNames != _highlightProperNames;
    setState(() {
      if (settings.rapidReading != _rapidReading ||
          settings.rapidReveal != _rapidReveal) {
        _revealed.clear();
      }
      _adoptReadingSettings(settings);
    });
    if (reloadChapter) {
      _pendingVerse = _visibleVerse;
      _startAt(_bookIndex, _chapter);
    } else {
      _savePrefs();
    }
  }

  void _adoptReadingSettings(AppReadingSettings settings) {
    _ntSyriac = settings.ntSyriac;
    _englishBookNames = settings.englishBookNames;
    _hebrewNumerals = settings.hebrewNumerals;
    _showCantillation = settings.showCantillation;
    _glossInterlinear = settings.glossInterlinear;
    _morphologyInterlinear = settings.morphologyInterlinear;
    _highlightProperNames = settings.highlightProperNames;
    _syntaxRoles = settings.syntaxRoles;
    _syntaxView = settings.syntaxView;
    _readerText = settings.readerText;
    _rapidReading = settings.rapidReading;
    _showInterlinear = settings.showInterlinear;
    _rapidReveal = settings.rapidReveal;
    _ketivDisplay = settings.ketivDisplay;
    _fontSize = settings.fontSize;
    _fontFamily = settings.fontFamily;
    _readerLayoutMode = settings.readerLayoutMode;
  }

  AppReadingSettings get _readingSettings => AppReadingSettings(
    ntSyriac: _ntSyriac,
    englishBookNames: _englishBookNames,
    hebrewNumerals: _hebrewNumerals,
    showCantillation: _showCantillation,
    glossInterlinear: _glossInterlinear,
    morphologyInterlinear: _morphologyInterlinear,
    highlightProperNames: _highlightProperNames,
    rapidReveal: _rapidReveal,
    ketivDisplay: _ketivDisplay,
    fontSize: _fontSize,
    fontFamily: _fontFamily,
    readerLayoutMode: _readerLayoutMode,
    syntaxRoles: _syntaxRoles,
    syntaxView: _syntaxView,
    readerText: _readerText,
    rapidReading: _rapidReading,
    showInterlinear: _showInterlinear,
  );

  /// Whether the interlinear shows beneath every word: on, and not hidden
  /// behind rapid reading's taps.
  bool get _interlinearShown => _showInterlinear && !_rapidReading;

  /// Shows or hides the interlinear. Showing it leaves rapid reading, whose
  /// whole point is that the interlinear stays hidden until asked for.
  void _toggleInterlinear() {
    final show = !_interlinearShown;
    setState(() {
      _showInterlinear = show;
      if (show && _rapidReading) {
        _rapidReading = false;
        _revealed.clear();
      }
    });
    _ensureInterlinearLayer(show);
  }

  /// Starts or ends rapid reading: the Hebrew alone, a tap revealing the
  /// interlinear where it is needed. Ending it returns to the interlinear as
  /// it was before.
  void _toggleRapidReading() {
    final rapid = !_rapidReading;
    setState(() {
      _rapidReading = rapid;
      _revealed.clear();
    });
    _ensureInterlinearLayer(rapid || _showInterlinear);
  }

  /// An interlinear with no layers enabled would look just like the bare
  /// text, so asking for one turns the glosses on.
  void _ensureInterlinearLayer(bool wanted) {
    if (wanted && !_glossInterlinear && !_morphologyInterlinear) {
      _applyReadingSettings(_readingSettings.copyWith(glossInterlinear: true));
    } else {
      _savePrefs();
    }
  }

  /// Shows or hides the interlinear a rapid-reading tap on the word at
  /// [position] asks for: the word's own, or its verse's.
  void _toggleReveal(int bookIndex, int chapter, int verse, int position) {
    final key = (bookIndex, chapter, verse);
    setState(() {
      switch (_rapidReveal) {
        case RapidReveal.verse:
          if (_revealed.containsKey(key)) {
            _revealed.remove(key);
          } else {
            _revealed[key] = null;
          }
        case RapidReveal.word:
          if (!_revealed.containsKey(key)) {
            _revealed[key] = {position};
            break;
          }
          final positions = _revealed[key];
          if (positions == null) {
            // Revealed whole before the setting changed: hide it all.
            _revealed.remove(key);
          } else if (!positions.remove(position)) {
            positions.add(position);
          } else if (positions.isEmpty) {
            _revealed.remove(key);
          }
      }
    });
  }

  Set<int>? _interlinearPositions(int bookIndex, int chapter, int verse) =>
      _rapidReading
      ? (_revealed.containsKey((bookIndex, chapter, verse))
            ? _revealed[(bookIndex, chapter, verse)]
            : const <int>{})
      : _showInterlinear
      ? null
      : const <int>{};

  Future<void> _showAppSettings() async {
    await showAppSettings(
      context,
      readingSettings: _readingSettings,
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

  StudyWorkspace? get _activeStudyWorkspace {
    for (final workspace in _studyWorkspaces) {
      if (workspace.id == _activeStudyWorkspaceId) return workspace;
    }
    return null;
  }

  StudyPassage get _currentStudyPassage {
    if (_selectedBook != null &&
        _selectedChapter != null &&
        _selectedVerse != null) {
      return StudyPassage(
        bookIndex: _selectedBook!,
        chapter: _selectedChapter!,
        verse: _selectedVerse!,
      );
    }
    return StudyPassage(
      bookIndex: _bookIndex,
      chapter: _chapter,
      verse: _visibleVerse,
    );
  }

  // Study edits go through the store every reader shares, which keeps and
  // sends them. The tiled panels and study pages are built by the outer
  // workspace, outside this session's setState scope, so refresh them too.
  void _replaceStudyWorkspace(StudyWorkspace updated) {
    widget.onWorkspaceTilesChanged();
    widget.studyStore.replace(updated);
  }

  Future<String?> _askForText({
    required String title,
    required String initialValue,
    required String label,
    int maxLines = 1,
    String confirmLabel = 'Save',
  }) async {
    var value = initialValue;
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initialValue,
          autofocus: true,
          maxLines: maxLines,
          minLines: maxLines > 1 ? 3 : 1,
          decoration: InputDecoration(labelText: label),
          onChanged: (text) => value = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = value.trim();
              if (trimmed.isNotEmpty || maxLines > 1) {
                Navigator.pop(dialogContext, trimmed);
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<StudyWorkspace?> _createStudyWorkspace() async {
    final passage = _currentStudyPassage;
    final defaultName =
        '${bookDisplayName(passage.bookIndex, useEnglish: _englishBookNames)} '
        '${passage.chapter}:${passage.verse} study';
    final name = await _askForText(
      title: 'New study workspace',
      initialValue: defaultName,
      label: 'Workspace name',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return null;
    final workspace = StudyWorkspace(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
    );
    widget.onWorkspaceTilesChanged();
    await widget.studyStore.add(workspace);
    return workspace;
  }

  void _selectStudyWorkspace(String id) {
    widget.onWorkspaceTilesChanged();
    widget.studyStore.select(id);
  }

  Future<StudyWorkspace?> _ensureStudyWorkspace() async =>
      _activeStudyWorkspace ?? await _createStudyWorkspace();

  Future<void> _renameStudyWorkspace() async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final name = await _askForText(
      title: 'Rename workspace',
      initialValue: workspace.name,
      label: 'Workspace name',
    );
    if (name != null && mounted) {
      _replaceStudyWorkspace(workspace.copyWith(name: name));
    }
  }

  Future<void> _deleteStudyWorkspace() async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${workspace.name}?'),
        content: const Text(
          'Its passage links, highlights and notes will be removed from '
          'this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.onWorkspaceTilesChanged();
    widget.studyStore.remove(workspace.id);
  }

  Future<void> _createStudyGroup(String? parentId) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return;
    final name = await _askForText(
      title: parentId == null ? 'New study group' : 'New subgroup',
      initialValue: '',
      label: 'Group name',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return;
    _replaceStudyWorkspace(
      workspace.putGroup(
        StudyGroup(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name,
          parentId: parentId,
        ),
      ),
    );
  }

  Future<void> _editStudyGroup(StudyGroup group) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final name = await _askForText(
      title: 'Edit study group',
      initialValue: group.name,
      label: 'Group name',
      confirmLabel: 'Save',
    );
    if (name != null && mounted) {
      _replaceStudyWorkspace(workspace.putGroup(group.copyWith(name: name)));
    }
  }

  Future<void> _deleteStudyGroup(StudyGroup group) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${group.name}?'),
        content: const Text(
          'Its study items and subgroups will be kept and moved up one level.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _replaceStudyWorkspace(workspace.removeGroup(group));
    }
  }

  Future<List<VerseEntry>> _loadStudyChapter(int book, int chapter) async {
    for (final section in _sections) {
      if (section.bookIndex == book && section.chapter == chapter) {
        return section.verses;
      }
    }
    final request = GetChapter(
      book: book + 1,
      chapter: chapter,
      syriac: _isSyriac(book),
      includeGlosses: false,
      includeMorphology: false,
      includeNames: false,
      includeRoots: false,
    );
    final result = Completer<List<VerseEntry>>();
    final subscription = ChapterText.rustSignalStream.listen((pack) {
      final msg = pack.message;
      if (msg.book == request.book &&
          msg.chapter == chapter &&
          msg.syriac == request.syriac &&
          !result.isCompleted) {
        result.complete(msg.verses);
      }
    });
    try {
      final send = widget.sendChapterRequest;
      if (send != null) {
        send(request);
      } else {
        request.sendSignalToRust();
      }
      return await result.future.timeout(const Duration(seconds: 10));
    } finally {
      await subscription.cancel();
    }
  }

  Future<StudyPassage?> _askForStudyPassage(
    StudyWorkspace workspace,
    StudyPassage passage, {
    required bool creating,
  }) => showDialog<StudyPassage>(
    context: context,
    builder: (_) => StudyPassageEditor(
      initial: passage,
      creating: creating,
      useEnglishBookNames: _englishBookNames,
      loadChapter: _loadStudyChapter,
      isDuplicate: (ref) =>
          (_studyWorkspaces.where((w) => w.id == workspace.id).firstOrNull ??
                  workspace)
              .passages
              .any(
                (p) =>
                    p.locationKey == ref.locationKey &&
                    (creating || p.locationKey != passage.locationKey),
              ),
    ),
  );

  Future<void> _bookmarkCurrentStudyPassage(String? groupId) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final passage = await _askForStudyPassage(
      workspace,
      _currentStudyPassage.copyWith(groupId: () => groupId),
      creating: true,
    );
    if (passage == null || !mounted) return;
    final current = _studyWorkspaces
        .where((w) => w.id == workspace.id)
        .firstOrNull;
    if (current != null) _replaceStudyWorkspace(current.putPassage(passage));
  }

  Future<void> _editStudyPassage(StudyPassage passage) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final edited = await _askForStudyPassage(
      workspace,
      passage,
      creating: false,
    );
    if (edited == null || !mounted) return;
    final current = _studyWorkspaces
        .where((w) => w.id == workspace.id)
        .firstOrNull;
    if (current != null) {
      _replaceStudyWorkspace(current.replacePassage(passage, edited));
    }
  }

  void _updateStudyPassage(StudyPassage passage) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.putPassage(passage));
  }

  void _removeStudyPassage(StudyPassage passage) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.removePassage(passage));
  }

  void _toggleStudyHighlights(bool enabled) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.copyWith(highlightsEnabled: enabled));
    if (enabled) _refreshLoadedChaptersForStudyRoots();
  }

  Future<bool> _toggleStudyWordBookmark(StudyWord bookmark) async {
    if (bookmark.kind == StudyWordKind.root && bookmark.root.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This word has no resolved root.')),
        );
      }
      return false;
    }
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return false;
    final existing = workspace.wordForBookmark(bookmark);
    if (existing == null) {
      _replaceStudyWorkspace(workspace.putWord(bookmark));
      _refreshLoadedChaptersForStudyRoots();
      return true;
    }
    _replaceStudyWorkspace(workspace.removeWord(existing));
    return false;
  }

  Future<void> _editStudyWord(StudyWord word) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final note = await showMarkdownNoteDialog(
      context,
      title: word.title,
      initialValue: word.note,
      label: 'Word note',
    );
    if (note == null || !mounted) return;
    _replaceStudyWorkspace(workspace.putWord(word.copyWith(note: note)));
  }

  void _updateStudyWord(StudyWord word) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.putWord(word));
    if (word.highlightEnabled) _refreshLoadedChaptersForStudyRoots();
  }

  void _switchStudyWordKind(StudyWord word) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null || !workspace.canSwitchWordKind(word)) return;
    _replaceStudyWorkspace(workspace.switchWordKind(word));
    if (word.highlightEnabled) _refreshLoadedChaptersForStudyRoots();
  }

  void _removeStudyWord(StudyWord word) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.removeWord(word));
  }

  /// Bookmarks a cross reference in the active study (creating one if need
  /// be), or removes it when it is already there. True when it was added.
  Future<bool> _toggleStudyLinkBookmark(StudyLink link) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return false;
    final existing = workspace.linkBetween(link.earlier, link.later);
    if (existing == null) {
      _replaceStudyWorkspace(workspace.putLink(link));
      return true;
    }
    _replaceStudyWorkspace(workspace.removeLink(existing));
    return false;
  }

  bool _isStudyLinkBookmarked(StudyLinkVerse earlier, StudyLinkVerse later) =>
      _activeStudyWorkspace?.linkBetween(earlier, later) != null;

  Future<void> _editStudyLink(StudyLink link) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final note = await showMarkdownNoteDialog(
      context,
      title: 'Cross-reference note',
      initialValue: link.note,
      label: 'Note',
    );
    if (note == null || !mounted) return;
    _replaceStudyWorkspace(workspace.putLink(link.copyWith(note: note)));
  }

  void _updateStudyLink(StudyLink link) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.putLink(link));
  }

  void _removeStudyLink(StudyLink link) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.removeLink(link));
  }

  /// Bookmarking a person or place, on its page, in the active study.
  NameBookmarks get _nameBookmarks => NameBookmarks(
    isBookmarked: (id) => _activeStudyWorkspace?.nameFor(id) != null,
    toggle: _toggleStudyNameBookmark,
  );

  /// Bookmarks a person or place in the active study (creating one if need
  /// be), or removes it when it is already there. True when it was added.
  Future<bool> _toggleStudyNameBookmark(StudyName name) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return false;
    final existing = workspace.nameFor(name.id);
    if (existing == null) {
      _replaceStudyWorkspace(workspace.putName(name));
      return true;
    }
    _replaceStudyWorkspace(workspace.removeName(existing));
    return false;
  }

  Future<void> _editStudyName(StudyName name) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final note = await showMarkdownNoteDialog(
      context,
      title: 'Note on ${name.name}',
      initialValue: name.note,
      label: 'Note',
    );
    if (note == null || !mounted) return;
    _replaceStudyWorkspace(workspace.putName(name.copyWith(note: note)));
  }

  void _removeStudyName(StudyName name) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.removeName(name));
  }

  void _openStudyName(StudyName name) => NameDetailsPage.open(
    context,
    id: name.id,
    title: name.name,
    useEnglishBookNames: _englishBookNames,
    bookmarks: _nameBookmarks,
    onNavigateToPassage: (book, chapter, verse) =>
        _navigateTo(book, chapter, verse: verse),
  );

  Future<void> _createStudyNote(String? groupId) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return;
    final text = await showMarkdownNoteDialog(
      context,
      title: 'New study note',
      initialValue: '',
      label: 'Note',
      confirmLabel: 'Add',
    );
    if (text == null || !mounted) return;
    _replaceStudyWorkspace(
      workspace.putNote(
        StudyNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: text,
          groupId: groupId,
        ),
      ),
    );
  }

  Future<void> _editStudyNote(StudyNote note) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final text = await showMarkdownNoteDialog(
      context,
      title: 'Edit study note',
      initialValue: note.text,
      label: 'Note',
    );
    if (text != null && mounted) {
      _replaceStudyWorkspace(workspace.putNote(note.copyWith(text: text)));
    }
  }

  void _updateStudyNote(StudyNote note) {
    final workspace = _activeStudyWorkspace;
    if (workspace != null) {
      _replaceStudyWorkspace(workspace.putNote(note));
    }
  }

  void _removeStudyNote(StudyNote note) {
    final workspace = _activeStudyWorkspace;
    if (workspace != null) {
      _replaceStudyWorkspace(workspace.removeNote(note));
    }
  }

  void _toggleStudyHeadings(bool enabled) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.copyWith(headingsEnabled: enabled));
  }

  Future<StudySection?> _askForStudySection(
    StudySection section, {
    required bool creating,
    List<StudySection> parents = const [],
  }) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return Future.value();
    final parent = workspace.sectionById(section.parentId);
    return showDialog<StudySection>(
      context: context,
      builder: (_) => StudySectionEditor(
        initial: section,
        creating: creating,
        useEnglishBookNames: _englishBookNames,
        loadChapter: _loadStudyChapter,
        summary: section.isSummary || parent == null
            ? null
            : workspace.summaryOf(parent),
        parents: parents,
        // Checked against the workspace as it is when saving.
        validate: (edited) =>
            (_activeStudyWorkspace ?? workspace).sectionProblem(edited),
      ),
    );
  }

  /// Adds a section heading to the section [parentId], or else a passage
  /// summary, of the reader's current chapter, to [parentId] or the top.
  Future<void> _createStudySection(String? parentId) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final current = _currentStudyPassage;
    final parent = workspace.sectionById(parentId);
    final StudySection initial;
    if (parent == null) {
      initial = StudySection(
        id: id,
        title: '',
        chapter: current.chapter,
        verse: 1,
        bookIndex: current.bookIndex,
        wholeChapter: true,
        parentId: parentId,
      );
    } else {
      // The verse being read, where a heading may start there.
      final summary = workspace.summaryOf(parent);
      final here = (chapter: current.chapter, verse: current.verse);
      final start =
          summary?.bookIndex == current.bookIndex &&
              workspace.canPlaceHeading(parent.id, here)
          ? here
          : parent.start;
      initial = StudySection(
        id: id,
        title: '',
        chapter: start.chapter,
        verse: start.verse,
        parentId: parentId,
      );
    }
    final created = await _askForStudySection(initial, creating: true);
    final latest = _activeStudyWorkspace;
    if (created == null || latest == null || !mounted) return;
    _replaceStudyWorkspace(latest.putSection(created));
  }

  /// Adds, from the reader, a heading starting at a verse to the summary
  /// covering it (asking which heading to put it under), or else a new
  /// summary starting there. Its headings are then shown, to see it land.
  Future<void> _addStudyHeadingAt(int book, int chapter, int verse) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final covering = workspace.sectionsCovering(book, chapter, verse);
    final parent = workspace.headingParentAt(covering, (
      chapter: chapter,
      verse: verse,
    ));
    final created = await _askForStudySection(
      parent == null
          ? StudySection(
              id: id,
              title: '',
              chapter: chapter,
              verse: verse,
              bookIndex: book,
              // From the top of a chapter, the whole chapter by default.
              wholeChapter: verse == 1,
              endChapter: verse == 1 ? null : chapter,
              endVerse: verse == 1 ? null : verse,
            )
          : StudySection(
              id: id,
              title: '',
              chapter: chapter,
              verse: verse,
              parentId: parent.id,
            ),
      creating: true,
      parents: covering,
    );
    final latest = _activeStudyWorkspace;
    if (created == null || latest == null || !mounted) return;
    var updated = latest.putSection(created).copyWith(headingsEnabled: true);
    final summary = updated.summaryOf(created);
    if (summary != null && !summary.showInReader) {
      updated = updated.putSection(summary.copyWith(showInReader: true));
    }
    _replaceStudyWorkspace(updated);
  }

  Future<void> _editStudySection(StudySection section) async {
    final edited = await _askForStudySection(section, creating: false);
    final workspace = _activeStudyWorkspace;
    if (edited == null || workspace == null || !mounted) return;
    _replaceStudyWorkspace(workspace.putSection(edited));
  }

  void _updateStudySection(StudySection section) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.putSection(section));
  }

  Future<void> _deleteStudySection(StudySection section) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${section.title}?'),
        content: Text(
          section.isSummary
              ? 'Its section headings will be deleted. Its other study items '
                    'will be kept and moved up one level.'
              : 'Its study items and subheadings will be kept and moved up '
                    'one level.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    final latest = _activeStudyWorkspace;
    if (confirmed == true && latest != null && mounted) {
      _replaceStudyWorkspace(latest.removeSection(section));
    }
  }

  void _openStudySection(StudySection section) {
    final summary = _activeStudyWorkspace?.summaryOf(section);
    final book = summary?.bookIndex;
    if (book == null) return;
    _navigateTo(
      book,
      section.chapter,
      verse: section.isSummary && section.wholeChapter ? null : section.verse,
    );
  }

  Future<StudyTimeline?> _askForStudyTimeline(
    StudyTimeline timeline, {
    required bool creating,
  }) => showDialog<StudyTimeline>(
    context: context,
    builder: (_) => StudyTimelineEditor(initial: timeline, creating: creating),
  );

  /// Adds a timeline to the container [parentId], or the top, returning it.
  Future<StudyTimeline?> _createStudyTimeline(String? parentId) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return null;
    final created = await _askForStudyTimeline(
      StudyTimeline(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: '',
        scale: TimelineScale.calendar,
        parentId: parentId,
      ),
      creating: true,
    );
    final latest = _activeStudyWorkspace;
    if (created == null || latest == null || !mounted) return null;
    _replaceStudyWorkspace(latest.putTimeline(created));
    return created;
  }

  Future<void> _editStudyTimeline(StudyTimeline timeline) async {
    final edited = await _askForStudyTimeline(timeline, creating: false);
    final workspace = _activeStudyWorkspace;
    if (edited == null || workspace == null || !mounted) return;
    _replaceStudyWorkspace(workspace.putTimeline(edited));
  }

  Future<void> _deleteStudyTimeline(StudyTimeline timeline) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${timeline.title}?'),
        content: const Text(
          'Its events and spans will be deleted. Its other study items will '
          'be kept and moved up one level.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    final latest = _activeStudyWorkspace;
    if (confirmed == true && latest != null && mounted) {
      _replaceStudyWorkspace(latest.removeTimeline(timeline));
    }
  }

  /// Opens a timeline's full view; its verses open in the reader, and then
  /// [onOpenReader] brings the reader forward.
  void _openStudyTimeline(
    StudyTimeline timeline, {
    String? selectedId,
    VoidCallback? onOpenReader,
  }) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TimelinePage(
          timeline: timeline,
          entries: workspace.entriesOf(timeline.id),
          useEnglishBookNames: _englishBookNames,
          initialSelectedId: selectedId,
          onOpenPassage: (passage) {
            _navigateTo(
              passage.bookIndex,
              passage.chapter,
              verse: passage.wholeChapter ? null : passage.verse,
            );
            onOpenReader?.call();
          },
          reload: () {
            final workspace = _activeStudyWorkspace;
            final current = workspace?.timelineById(timeline.id);
            if (workspace == null || current == null) return null;
            return (
              timeline: current,
              entries: workspace.entriesOf(timeline.id),
            );
          },
          onEditTimeline: () async {
            final current = _activeStudyWorkspace?.timelineById(timeline.id);
            if (current != null) await _editStudyTimeline(current);
          },
          // The verse being read is no clue to an entry added here.
          onAddEntry: (span) =>
              _createStudyTimelineEntry(timeline.id, span, linkVerse: false),
          onEditEntry: _editStudyTimelineEntry,
          onRemoveEntry: (entry) async => _removeStudyTimelineEntry(entry),
        ),
      ),
    );
  }

  Future<void> _askForStudyTimelineEntry(
    StudyTimelineEntry entry, {
    required bool creating,
  }) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null || workspace.timelines.isEmpty) return;
    final edited = await showDialog<StudyTimelineEntry>(
      context: context,
      builder: (_) => StudyTimelineEntryEditor(
        initial: entry,
        creating: creating,
        timelines: workspace.timelines,
        useEnglishBookNames: _englishBookNames,
        loadChapter: _loadStudyChapter,
      ),
    );
    final latest = _activeStudyWorkspace;
    if (edited == null || latest == null || !mounted) return;
    _replaceStudyWorkspace(latest.putTimelineEntry(edited));
  }

  StudyTimelineEntry _newStudyTimelineEntry(
    String timelineId, {
    required bool span,
    StudyPassage? verse,
  }) => StudyTimelineEntry(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    title: '',
    timelineId: timelineId,
    start: const TimelineTime(0),
    end: span ? const TimelineTime(0) : null,
    verses: [
      if (verse != null)
        StudyPassage(
          bookIndex: verse.bookIndex,
          chapter: verse.chapter,
          verse: verse.verse,
        ),
    ],
  );

  /// Adds an event or span to a timeline, linked to the verse being read
  /// unless [linkVerse] is false.
  Future<void> _createStudyTimelineEntry(
    String timelineId,
    bool span, {
    bool linkVerse = true,
  }) => _askForStudyTimelineEntry(
    _newStudyTimelineEntry(
      timelineId,
      span: span,
      verse: linkVerse ? _currentStudyPassage : null,
    ),
    creating: true,
  );

  /// Adds, from the reader, an event or span linked to a verse: to the
  /// timeline last given an entry in its book, else the newest timeline,
  /// else a new one. Markers are then shown, to see it land.
  Future<void> _addStudyTimelineEntryAt(
    int book,
    int chapter,
    int verse, {
    required bool span,
  }) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return;
    StudyTimeline? timeline;
    for (final entry in workspace.timelineEntries.reversed) {
      if (entry.verses.any((p) => p.bookIndex == book)) {
        timeline = workspace.timelineById(entry.timelineId);
        break;
      }
    }
    timeline ??= workspace.timelines.lastOrNull;
    timeline ??= await _createStudyTimeline(null);
    if (timeline == null || !mounted) return;
    await _askForStudyTimelineEntry(
      _newStudyTimelineEntry(
        timeline.id,
        span: span,
        verse: StudyPassage(bookIndex: book, chapter: chapter, verse: verse),
      ),
      creating: true,
    );
    final latest = _activeStudyWorkspace;
    if (latest != null &&
        !latest.timelineMarkersEnabled &&
        latest.timelineEntriesAt(book, chapter, verse).isNotEmpty) {
      _replaceStudyWorkspace(latest.copyWith(timelineMarkersEnabled: true));
    }
  }

  Future<void> _editStudyTimelineEntry(StudyTimelineEntry entry) =>
      _askForStudyTimelineEntry(entry, creating: false);

  void _removeStudyTimelineEntry(StudyTimelineEntry entry) {
    final workspace = _activeStudyWorkspace;
    if (workspace != null) {
      _replaceStudyWorkspace(workspace.removeTimelineEntry(entry));
    }
  }

  void _toggleStudyTimelineMarkers(bool enabled) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.copyWith(timelineMarkersEnabled: enabled));
  }

  /// The events and spans linked to a verse, from its marker: each opens its
  /// timeline, picked out there, or its editor.
  Future<void> _showStudyTimelineEntriesAt(
    int book,
    int chapter,
    int verse,
  ) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final entries = workspace.timelineEntriesAt(book, chapter, verse);
    if (entries.isEmpty) return;
    final choice = await showModalBottomSheet<(StudyTimelineEntry, bool)>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in entries)
              if (workspace.timelineById(entry.timelineId) case final timeline?)
                ListTile(
                  leading: Icon(
                    entry.isSpan
                        ? Icons.linear_scale
                        : Icons.radio_button_checked,
                  ),
                  title: Text(entry.title),
                  subtitle: Text(
                    '${timeline.title} · '
                    '${timelineEntryTime(timeline, entry)}',
                  ),
                  onTap: () => Navigator.pop(sheetContext, (entry, false)),
                  trailing: IconButton(
                    tooltip: entry.isSpan ? 'Edit span' : 'Edit event',
                    icon: const Icon(Icons.edit_note),
                    onPressed: () => Navigator.pop(sheetContext, (entry, true)),
                  ),
                ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final (entry, edit) = choice;
    if (edit) {
      await _editStudyTimelineEntry(entry);
      return;
    }
    final timeline = _activeStudyWorkspace?.timelineById(entry.timelineId);
    if (timeline != null) _openStudyTimeline(timeline, selectedId: entry.id);
  }

  void _moveStudyItem(StudyItem item, String? groupId, int? index) {
    final workspace = _activeStudyWorkspace;
    if (workspace != null) {
      _replaceStudyWorkspace(workspace.moveItem(item, groupId, index: index));
    }
  }

  void _openStudyWord(StudyWord word) {
    final passage = _currentStudyPassage;
    _showWordInfo(
      word.surface,
      passage.bookIndex,
      passage.chapter,
      passage.verse,
      root: word.root,
    );
  }

  void _refreshLoadedChaptersForStudyRoots() {
    for (final section in List<_Section>.of(_sections)) {
      // Nothing to ask again when the verses came with what is wanted now.
      if (section.request ==
          _chapterRequest(section.bookIndex, section.chapter)) {
        continue;
      }
      _fetchChapter(section.bookIndex, section.chapter, force: true);
    }
  }

  void _toggleStudyWorkspacePanel() {
    final enabled = !_studyWorkspaceVisible;
    setState(() {
      _studyWorkspaceVisible = enabled;
    });
    widget.onWorkspaceTilesChanged();
    _savePrefs();
    if (enabled) _refreshLoadedChaptersForStudyRoots();
  }

  void _setCrossReferenceMinScore(double score) {
    setState(() => _crossReferenceMinScore = score);
    _savePrefs();
  }

  /// The toolbar's cross references: the selected verse's links, or the
  /// overview of the chapter being read when no verse is selected. The
  /// workspace docks the panel beside the reader, or asks for the sheet.
  void _openCrossReferences() {
    final book = _selectedBook;
    final chapter = _selectedChapter;
    final verse = _selectedVerse;
    if (book != null && chapter != null && verse != null) {
      widget.onCrossReferencesRequested(book, chapter, verse);
    } else {
      widget.onCrossReferencesRequested(_bookIndex, _chapter, null);
    }
  }

  /// Whether the chapter at the top of the reader is in the Hebrew Bible,
  /// whose words alone are linked to the people and places they name.
  bool get _isOldTestament => _bookIndex < 39;

  /// The places the chapter at the top of the reader names, on a map.
  Future<void> _showChapterPlaces() async {
    if (!_isOldTestament) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.82,
        child: ChapterPlacesSheet(
          bookIndex: _bookIndex,
          chapter: _chapter,
          useEnglishBookNames: _englishBookNames,
          bookmarks: _nameBookmarks,
          onNavigateToPassage: (book, chapter, verse) =>
              _navigateTo(book, chapter, verse: verse),
        ),
      ),
    );
  }

  /// The people the chapter at the top of the reader names, and how they are
  /// related.
  Future<void> _showChapterPeople() async {
    if (!_isOldTestament) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.82,
        child: ChapterPeopleSheet(
          bookIndex: _bookIndex,
          chapter: _chapter,
          useEnglishBookNames: _englishBookNames,
          bookmarks: _nameBookmarks,
          onNavigateToPassage: (book, chapter, verse) =>
              _navigateTo(book, chapter, verse: verse),
        ),
      ),
    );
  }

  Future<void> _showStudyWorkspaceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.82,
          child: StudyWorkspacePanel(
            workspaces: _studyWorkspaces,
            activeWorkspace: _activeStudyWorkspace,
            currentPassage: _currentStudyPassage,
            useEnglishBookNames: _englishBookNames,
            onCreate: () async {
              await _createStudyWorkspace();
              setSheetState(() {});
            },
            onSelect: (id) {
              _selectStudyWorkspace(id);
              _refreshLoadedChaptersForStudyRoots();
              setSheetState(() {});
            },
            onRename: () async {
              await _renameStudyWorkspace();
              setSheetState(() {});
            },
            onDelete: () async {
              await _deleteStudyWorkspace();
              setSheetState(() {});
            },
            onToggleHighlights: (enabled) {
              _toggleStudyHighlights(enabled);
              setSheetState(() {});
            },
            onCreateGroup: (parentId) async {
              await _createStudyGroup(parentId);
              setSheetState(() {});
            },
            onEditGroup: (group) async {
              await _editStudyGroup(group);
              setSheetState(() {});
            },
            onDeleteGroup: (group) async {
              await _deleteStudyGroup(group);
              setSheetState(() {});
            },
            onBookmarkCurrent: (groupId) async {
              await _bookmarkCurrentStudyPassage(groupId);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onOpenPassage: (passage) {
              Navigator.pop(sheetContext);
              _navigateTo(
                passage.bookIndex,
                passage.chapter,
                verse: passage.wholeChapter ? null : passage.verse,
              );
            },
            onEditPassage: (passage) async {
              await _editStudyPassage(passage);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onUpdatePassage: (passage) {
              _updateStudyPassage(passage);
              setSheetState(() {});
            },
            onRemovePassage: (passage) {
              _removeStudyPassage(passage);
              setSheetState(() {});
            },
            onEditWord: (word) async {
              await _editStudyWord(word);
              setSheetState(() {});
            },
            onUpdateWord: (word) {
              _updateStudyWord(word);
              setSheetState(() {});
            },
            onSwitchWordKind: (word) {
              _switchStudyWordKind(word);
              setSheetState(() {});
            },
            onRemoveWord: (word) {
              _removeStudyWord(word);
              setSheetState(() {});
            },
            onOpenWord: (word) {
              Navigator.pop(sheetContext);
              _openStudyWord(word);
            },
            onCreateNote: (groupId) async {
              await _createStudyNote(groupId);
              setSheetState(() {});
            },
            onEditNote: (note) async {
              await _editStudyNote(note);
              setSheetState(() {});
            },
            onUpdateNote: (note) {
              _updateStudyNote(note);
              setSheetState(() {});
            },
            onRemoveNote: (note) {
              _removeStudyNote(note);
              setSheetState(() {});
            },
            onMoveItem: (item, groupId, index) {
              _moveStudyItem(item, groupId, index);
              setSheetState(() {});
            },
            onOpenLinkVerse: (link, verse) {
              Navigator.pop(sheetContext);
              _navigateTo(verse.bookIndex, verse.chapter, verse: verse.verse);
            },
            onShowLink: (link) {
              Navigator.pop(sheetContext);
              widget.onCrossReferencesRequested(
                link.later.bookIndex,
                link.later.chapter,
                link.later.verse,
              );
            },
            onEditLink: (link) async {
              await _editStudyLink(link);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onUpdateLink: (link) {
              _updateStudyLink(link);
              setSheetState(() {});
            },
            onRemoveLink: (link) {
              _removeStudyLink(link);
              setSheetState(() {});
            },
            onOpenName: (name) {
              Navigator.pop(sheetContext);
              _openStudyName(name);
            },
            onEditName: (name) async {
              await _editStudyName(name);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onRemoveName: (name) {
              _removeStudyName(name);
              setSheetState(() {});
            },
            onToggleHeadings: (enabled) {
              _toggleStudyHeadings(enabled);
              setSheetState(() {});
            },
            onCreateSection: (parentId) async {
              await _createStudySection(parentId);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onEditSection: (section) async {
              await _editStudySection(section);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onUpdateSection: (section) {
              _updateStudySection(section);
              setSheetState(() {});
            },
            onDeleteSection: (section) async {
              await _deleteStudySection(section);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onOpenSection: (section) {
              Navigator.pop(sheetContext);
              _openStudySection(section);
            },
            onToggleTimelineMarkers: (enabled) {
              _toggleStudyTimelineMarkers(enabled);
              setSheetState(() {});
            },
            onCreateTimeline: (parentId) async {
              await _createStudyTimeline(parentId);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onEditTimeline: (timeline) async {
              await _editStudyTimeline(timeline);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onDeleteTimeline: (timeline) async {
              await _deleteStudyTimeline(timeline);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onOpenTimeline: (timeline) => _openStudyTimeline(
              timeline,
              onOpenReader: () {
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            onCreateTimelineEntry: (timelineId, span) async {
              await _createStudyTimelineEntry(timelineId, span);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onEditTimelineEntry: (entry) async {
              await _editStudyTimelineEntry(entry);
              if (sheetContext.mounted) setSheetState(() {});
            },
            onRemoveTimelineEntry: (entry) {
              _removeStudyTimelineEntry(entry);
              setSheetState(() {});
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showReadingPlan() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => _ReadingPlanSheet(
          plans: _readingPlans,
          christadelphianReadings: christadelphianReadingsFor(DateTime.now()),
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
          onOpenChristadelphianReading: (reading) {
            Navigator.pop(ctx);
            _navigateTo(
              reading.bookIndex,
              reading.chapter,
              verse: reading.verse,
            );
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
    setState(() {
      _pendingVerse = verse;
      _visibleVerse = verse ?? 1;
    });
    widget.onWorkspaceTilesChanged();
    _startAt(bookIndex, chapter);
    _saveHistory();
    widget.onPassageChanged();
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
      _lastChromeScrollPixels = null;
      _chromeScrollDelta = 0;
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
    _morphologyInterlinear,
    _highlightProperNames,
    _studyWorkspaceVisible ||
        (_activeStudyWorkspace?.words.any(
              (word) => word.highlightEnabled && word.root.isNotEmpty,
            ) ??
            false),
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
      if (!prefetch) _acceptChapter(bookIndex, chapter, cached, key);
      return;
    }
    _pendingFetches.add(key);
    _lateFetches.remove(key);
    if (prefetch) _prefetches.add(key);
    _fetchTimeouts[key] = Timer(const Duration(seconds: 10), () {
      _fetchTimeouts.remove(key);
      if (!_pendingFetches.remove(key)) return;
      final wasPrefetch = _prefetches.remove(key);
      _lateFetches[key] = wasPrefetch;
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
      includeMorphology: _morphologyInterlinear,
      includeNames: _highlightProperNames,
      includeRoots: key.$7,
    );
    final send = widget.sendChapterRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  void _refreshLoadedOtChapters() {
    // Chapters cached or prefetched outside the window hold the old gloss too,
    // and so may any reply still on its way.
    _chapterCache.clear();
    _staleFetches
      ..addAll(_pendingFetches)
      ..addAll(_lateFetches.keys);
    for (final section in List<_Section>.of(_sections)) {
      if (section.bookIndex >= 39) continue;
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

  /// Where the verses of [section] start, and how far they extend, in scroll
  /// offsets. Null while none of its rows is built, or when it lies above the
  /// center, whose verses grow the other way.
  ({double start, double extent})? _verseSpan(_Section section) {
    if (_sections.indexOf(section) < _centerIndex) return null;
    for (final key in section.verseKeys.values) {
      final sliver = key.currentContext
          ?.findAncestorRenderObjectOfType<RenderSliverPadding>();
      final geometry = sliver?.geometry;
      if (sliver == null || geometry == null) continue;
      return (
        start:
            _scrollController.position.pixels - sliver.constraints.scrollOffset,
        extent: geometry.scrollExtent,
      );
    }
    return null;
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
      // Verse not yet built; jump proportionally within the chapter's own
      // verses (Flutter extrapolates their extent from laid-out items, so it
      // improves each retry). The whole scroll extent would also count any
      // chapter appended after it.
      final span = _scrollController.hasClients ? _verseSpan(section) : null;
      if (span != null) {
        final position = _scrollController.position;
        final offset =
            span.start + verseIdx / section.verses.length * span.extent;
        _scrollController.jumpTo(
          offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
      }
      _attemptScrollToVerse(section, verseIdx, retriesLeft: retriesLeft - 1);
    });
  }

  void _onScroll() {
    // Scroll listeners run before layout; measure the final visible content
    // once the frame has laid out, including any changes to the reader chrome.
    if (!_passageUpdateScheduled) {
      _passageUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _passageUpdateScheduled = false;
        _updateCurrentPassage();
      });
    }
    if (!_scrollController.hasClients || _sections.isEmpty) return;
    final position = _scrollController.position;
    final previousPixels = _lastChromeScrollPixels;
    _lastChromeScrollPixels = position.pixels;
    if (previousPixels != null) {
      final delta = position.pixels - previousPixels;
      if (_chromeScrollDelta != 0 &&
          delta != 0 &&
          _chromeScrollDelta.sign != delta.sign) {
        _chromeScrollDelta = 0;
      }
      _chromeScrollDelta += delta;
      if (_chromeScrollDelta > 24) {
        widget.onScrollChromeChanged(true);
        _chromeScrollDelta = 0;
      } else if (_chromeScrollDelta < -24) {
        widget.onScrollChromeChanged(false);
        _chromeScrollDelta = 0;
      }
    }
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

  KeyEventResult _handleReaderKey(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final distance = key == LogicalKeyboardKey.arrowUp
        ? -verseRowScrollExtent(fontSize: _fontSize, fontFamily: _fontFamily)
        : key == LogicalKeyboardKey.arrowDown
        ? verseRowScrollExtent(fontSize: _fontSize, fontFamily: _fontFamily)
        : key == LogicalKeyboardKey.pageUp
        ? -_scrollController.position.viewportDimension * 0.9
        : key == LogicalKeyboardKey.pageDown
        ? _scrollController.position.viewportDimension * 0.9
        : null;
    if (distance == null) return KeyEventResult.ignored;

    final position = _scrollController.position;
    final target = (position.pixels + distance).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _scrollController.jumpTo(target);
    } else {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
    return KeyEventResult.handled;
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

  void _updateCurrentPassage() {
    if (!mounted || _sections.isEmpty) return;
    final viewport =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.attached) return;
    final readingLine = viewport.localToGlobal(Offset.zero).dy + 8;
    _Section? visibleSection;
    for (int i = _sections.length - 1; i >= 0; i--) {
      final ctx = _sections[i].key.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= readingLine) {
        visibleSection = _sections[i];
        break;
      }
    }
    if (visibleSection == null) return;

    // Lazy slivers can keep children from adjacent chapters mounted while
    // scrolling. Resolve the chapter from its divider first, then inspect only
    // that chapter's verse rows; otherwise a retained neighbour can make the
    // indicator alternate between books at a boundary.
    ({int verse, double y})? firstVisibleVerse;
    for (final entry in visibleSection.verses) {
      final ctx = visibleSection.verseKeys[entry.verse]?.currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height <= readingLine) continue;
      if (firstVisibleVerse == null || y < firstVisibleVerse.y) {
        firstVisibleVerse = (verse: entry.verse, y: y);
      }
    }
    final book = visibleSection.bookIndex;
    final chapter = visibleSection.chapter;
    final verse = firstVisibleVerse?.verse ?? _visibleVerse;
    if (_bookIndex == book && _chapter == chapter && _visibleVerse == verse) {
      return;
    }
    setState(() {
      _bookIndex = book;
      _chapter = chapter;
      _visibleVerse = verse;
      if (_historyIndex >= 0 && _historyIndex < _history.length) {
        _history[_historyIndex] = _PassageRef(
          bookIndex: book,
          chapter: chapter,
          verse: verse,
        );
      }
    });
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(const Duration(milliseconds: 250), () {
      _savePrefs();
      _saveHistory();
    });
    widget.onPassageChanged();
  }

  @override
  void dispose() {
    _positionSaveTimer?.cancel();
    _scrollController.dispose();
    _sub?.cancel();
    _lexiconOverrideSub?.cancel();
    _syntaxSub?.cancel();
    _translationSub?.cancel();
    widget.studyStore.removeListener(_onStudyStoreChanged);
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
    int? position,
    String root = '',
    bool newPane = false,
  }) {
    final selected = _SelectedWord(
      word: word,
      bookIndex: bookIndex,
      chapter: chapter,
      verse: verse,
      position: position,
      root: root,
      readerGloss: readerGloss,
    );
    widget.onWordInfoRequested(selected, newPane: newPane);
  }

  /// A verse's syntax tree, in a sheet over the reader. Tapping a word in it
  /// closes the sheet and shows the word's details.
  Future<void> _showSyntax(int bookIndex, int chapter, int verse) =>
      showSyntaxSheet(
        context,
        book: bookIndex + 1,
        chapter: chapter,
        verse: verse,
        title:
            '${bookDisplayName(bookIndex, useEnglish: _englishBookNames)} '
            '$chapter:$verse',
        initialView: _syntaxView,
        fontFamily: _fontFamily,
        onViewChanged: (view) {
          setState(() => _syntaxView = view);
          _savePrefs();
        },
        onWordTap: (word, position, gloss) {
          Navigator.of(context).pop();
          _showWordInfo(
            word,
            bookIndex,
            chapter,
            verse,
            readerGloss: gloss.isEmpty ? null : gloss,
            position: position,
          );
        },
        sendRequest: widget.sendSyntaxTreesRequest,
        sendVerseTextsRequest: widget.sendVerseTextsRequest,
      );

  /// A word's long-press (or secondary-click) menu: open it in the active word
  /// pane or a new one, or bookmark it in the active study.
  /// A verse's menu, from a long press or a secondary click on its number:
  /// its cross references, or the chapter's.
  Future<void> _showVerseMenu(
    int bookIndex,
    int chapter,
    int verse,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = overlay.globalToLocal(globalPosition);
    final theme = Theme.of(context);
    final action = await showMenu<_VerseMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(at.dx, at.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          height: 36,
          child: Text(
            '${bookDisplayName(bookIndex, useEnglish: _englishBookNames)} '
            '$chapter:$verse',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const PopupMenuItem(
          value: _VerseMenuAction.crossReferences,
          child: ListTile(
            leading: Icon(Icons.link),
            title: Text('Cross references'),
          ),
        ),
        const PopupMenuItem(
          value: _VerseMenuAction.chapterCrossReferences,
          child: ListTile(
            leading: Icon(Icons.format_list_bulleted),
            title: Text('Chapter cross references'),
          ),
        ),
        // The trees cover the Hebrew Bible only.
        if (bookIndex < 39)
          const PopupMenuItem(
            value: _VerseMenuAction.syntax,
            child: ListTile(
              leading: Icon(Icons.lan_outlined),
              title: Text('Syntax'),
            ),
          ),
        const PopupMenuItem(
          value: _VerseMenuAction.memoriseChapter,
          child: ListTile(
            leading: Icon(Icons.psychology_outlined),
            title: Text('Memorise this chapter'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _VerseMenuAction.addTimelineEvent,
          child: ListTile(
            leading: Icon(Icons.radio_button_checked),
            title: Text('Add timeline event here'),
          ),
        ),
        const PopupMenuItem(
          value: _VerseMenuAction.addTimelineSpan,
          child: ListTile(
            leading: Icon(Icons.linear_scale),
            title: Text('Add timeline span here'),
          ),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case _VerseMenuAction.crossReferences:
        widget.onCrossReferencesRequested(bookIndex, chapter, verse);
      case _VerseMenuAction.chapterCrossReferences:
        widget.onCrossReferencesRequested(bookIndex, chapter, null);
      case _VerseMenuAction.syntax:
        await _showSyntax(bookIndex, chapter, verse);
      case _VerseMenuAction.memoriseChapter:
        await memoriseChapter(context, bookIndex, chapter);
      case _VerseMenuAction.addTimelineEvent:
      case _VerseMenuAction.addTimelineSpan:
        await _addStudyTimelineEntryAt(
          bookIndex,
          chapter,
          verse,
          span: action == _VerseMenuAction.addTimelineSpan,
        );
      case null:
        break;
    }
  }

  Future<void> _showWordMenu(
    String word,
    int bookIndex,
    int chapter,
    int verse, {
    required Offset globalPosition,
    String? readerGloss,
    int? position,
    String root = '',
  }) async {
    final workspace = _activeStudyWorkspace;
    StudyWord bookmark(StudyWordKind kind) =>
        StudyWord(root: root, surface: word, kind: kind);
    bool bookmarked(StudyWordKind kind) =>
        workspace?.wordForBookmark(bookmark(kind)) != null;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = overlay.globalToLocal(globalPosition);
    final theme = Theme.of(context);
    final action = await showMenu<_WordMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(at.dx, at.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          height: 36,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              word,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontFamily: 'Cardo',
                fontFamilyFallback: const ['Noto Serif Hebrew'],
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const PopupMenuItem(
          value: _WordMenuAction.open,
          child: ListTile(
            leading: Icon(Icons.menu_book_outlined),
            title: Text('Word info'),
          ),
        ),
        const PopupMenuItem(
          value: _WordMenuAction.openNewPane,
          child: ListTile(
            leading: Icon(Icons.library_add_outlined),
            title: Text('Open in new word pane'),
          ),
        ),
        const PopupMenuDivider(),
        if (root.isNotEmpty)
          PopupMenuItem(
            value: _WordMenuAction.bookmarkRoot,
            child: ListTile(
              leading: Icon(
                bookmarked(StudyWordKind.root)
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              title: Text(
                bookmarked(StudyWordKind.root)
                    ? 'Remove root bookmark'
                    : 'Bookmark this root',
              ),
            ),
          ),
        PopupMenuItem(
          value: _WordMenuAction.bookmarkForm,
          child: ListTile(
            leading: Icon(
              bookmarked(StudyWordKind.form)
                  ? Icons.bookmark_remove_outlined
                  : Icons.bookmark_add_outlined,
            ),
            title: Text(
              bookmarked(StudyWordKind.form)
                  ? 'Remove form bookmark'
                  : 'Bookmark this form',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _WordMenuAction.addHeading,
          child: ListTile(
            leading: const Icon(Icons.toc),
            title: Text(
              workspace == null ||
                      workspace
                          .sectionsCovering(bookIndex, chapter, verse)
                          .isEmpty
                  ? 'Start a passage summary here'
                  : 'Add heading at $chapter:$verse',
            ),
          ),
        ),
        PopupMenuItem(
          value: _WordMenuAction.addTimelineEntry,
          child: ListTile(
            leading: const Icon(Icons.timeline),
            title: Text('Add to timeline at $chapter:$verse'),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _WordMenuAction.addHeading:
        await _addStudyHeadingAt(bookIndex, chapter, verse);
      case _WordMenuAction.addTimelineEntry:
        await _addStudyTimelineEntryAt(bookIndex, chapter, verse, span: false);
      case _WordMenuAction.open:
      case _WordMenuAction.openNewPane:
        _showWordInfo(
          word,
          bookIndex,
          chapter,
          verse,
          readerGloss: readerGloss,
          position: position,
          root: root,
          newPane: action == _WordMenuAction.openNewPane,
        );
      case _WordMenuAction.bookmarkRoot:
      case _WordMenuAction.bookmarkForm:
        final kind = action == _WordMenuAction.bookmarkRoot
            ? StudyWordKind.root
            : StudyWordKind.form;
        final wasBookmarked = bookmarked(kind);
        final added = await _toggleStudyWordBookmark(bookmark(kind));
        // Neither added nor removed: no study was chosen to hold it.
        if (!mounted || (!added && !wasBookmarked)) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              added
                  ? 'Bookmarked ${kind.name}'
                  : 'Removed ${kind.name} bookmark',
            ),
          ),
        );
    }
  }

  _ResolvedReaderLayout _resolveReaderLayout(double width) {
    switch (_readerLayoutMode) {
      case ReaderLayoutMode.automatic:
        if (width >= 1320) return _ResolvedReaderLayout.threePanel;
        if (width >= 900) return _ResolvedReaderLayout.split;
        return _ResolvedReaderLayout.focus;
      case ReaderLayoutMode.focus:
        return _ResolvedReaderLayout.focus;
      case ReaderLayoutMode.split:
        return width >= 900
            ? _ResolvedReaderLayout.split
            : _ResolvedReaderLayout.focus;
      case ReaderLayoutMode.threePanel:
        if (width >= 1180) return _ResolvedReaderLayout.threePanel;
        if (width >= 900) return _ResolvedReaderLayout.split;
        return _ResolvedReaderLayout.focus;
    }
  }

  Widget _studyWorkspacePanel({VoidCallback? onOpenReader}) =>
      StudyWorkspacePanel(
        workspaces: _studyWorkspaces,
        activeWorkspace: _activeStudyWorkspace,
        currentPassage: _currentStudyPassage,
        useEnglishBookNames: _englishBookNames,
        onCreate: _createStudyWorkspace,
        onSelect: (id) {
          _selectStudyWorkspace(id);
          _refreshLoadedChaptersForStudyRoots();
        },
        onRename: _renameStudyWorkspace,
        onDelete: _deleteStudyWorkspace,
        onToggleHighlights: _toggleStudyHighlights,
        onCreateGroup: _createStudyGroup,
        onEditGroup: _editStudyGroup,
        onDeleteGroup: _deleteStudyGroup,
        onBookmarkCurrent: _bookmarkCurrentStudyPassage,
        onOpenPassage: (passage) {
          _navigateTo(
            passage.bookIndex,
            passage.chapter,
            verse: passage.wholeChapter ? null : passage.verse,
          );
          onOpenReader?.call();
        },
        onEditPassage: _editStudyPassage,
        onUpdatePassage: _updateStudyPassage,
        onRemovePassage: _removeStudyPassage,
        onEditWord: _editStudyWord,
        onUpdateWord: _updateStudyWord,
        onSwitchWordKind: _switchStudyWordKind,
        onRemoveWord: _removeStudyWord,
        onOpenWord: (word) {
          onOpenReader?.call();
          _openStudyWord(word);
        },
        onCreateNote: _createStudyNote,
        onEditNote: _editStudyNote,
        onUpdateNote: _updateStudyNote,
        onRemoveNote: _removeStudyNote,
        onMoveItem: _moveStudyItem,
        onOpenLinkVerse: (link, verse) {
          _navigateTo(verse.bookIndex, verse.chapter, verse: verse.verse);
          onOpenReader?.call();
        },
        // The later verse's links, where the bookmarked one is found again.
        onShowLink: (link) => widget.onCrossReferencesRequested(
          link.later.bookIndex,
          link.later.chapter,
          link.later.verse,
        ),
        onEditLink: _editStudyLink,
        onUpdateLink: _updateStudyLink,
        onRemoveLink: _removeStudyLink,
        onOpenName: _openStudyName,
        onEditName: _editStudyName,
        onRemoveName: _removeStudyName,
        onToggleHeadings: _toggleStudyHeadings,
        onCreateSection: _createStudySection,
        onEditSection: _editStudySection,
        onUpdateSection: _updateStudySection,
        onDeleteSection: _deleteStudySection,
        onOpenSection: (section) {
          _openStudySection(section);
          onOpenReader?.call();
        },
        onToggleTimelineMarkers: _toggleStudyTimelineMarkers,
        onCreateTimeline: _createStudyTimeline,
        onEditTimeline: _editStudyTimeline,
        onDeleteTimeline: _deleteStudyTimeline,
        onOpenTimeline: (timeline) =>
            _openStudyTimeline(timeline, onOpenReader: onOpenReader),
        onCreateTimelineEntry: _createStudyTimelineEntry,
        onEditTimelineEntry: _editStudyTimelineEntry,
        onRemoveTimelineEntry: _removeStudyTimelineEntry,
      );

  Widget _readerSurface() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sections.isEmpty) return const Center(child: Text('No text found'));
    return Focus(
      autofocus: true,
      onKeyEvent: _handleReaderKey,
      child: Stack(
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

  void _handleReaderMenuAction(_ReaderMenuAction action) {
    final layout = widget.tiled
        ? _ResolvedReaderLayout.split
        : _resolveReaderLayout(MediaQuery.sizeOf(context).width);
    switch (action) {
      case _ReaderMenuAction.studyWorkspace:
        if (layout == _ResolvedReaderLayout.focus) {
          _showStudyWorkspaceSheet();
        } else {
          _toggleStudyWorkspacePanel();
        }
      case _ReaderMenuAction.crossReferences:
        _openCrossReferences();
      case _ReaderMenuAction.readingPlan:
        _showReadingPlan();
      case _ReaderMenuAction.places:
        PlacesPage.open(
          context,
          useEnglishBookNames: _englishBookNames,
          bookmarks: _nameBookmarks,
          onNavigateToPassage: (book, chapter, verse) =>
              _navigateTo(book, chapter, verse: verse),
        );
      case _ReaderMenuAction.tutor:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TutorEntryPage()));
      case _ReaderMenuAction.memorise:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MemorisePage()));
      case _ReaderMenuAction.reportIssue:
        _reportGeneralIssue();
      case _ReaderMenuAction.settings:
        _showAppSettings();
      case _ReaderMenuAction.about:
        showAbout(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // The session moves between the reader pages, the tiled workspace and
    // their layouts under its global key, and a page view or layout builder
    // adopts it during layout. An open tooltip then re-attaching to the app's
    // overlay, outside that layout, fails, so its tooltips move with it.
    return Overlay.wrap(child: _session(context));
  }

  Widget _session(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _sessionScaffold(context, width: constraints.maxWidth),
  );

  Widget _sessionScaffold(BuildContext context, {required double width}) {
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
        actions: _barActions(width),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _readerSurface(),
        ),
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
      key: _scrollViewKey,
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
          ..._sectionSlivers(_sections[i], reverseVerseOrder: i < _centerIndex),
        ],
        SliverToBoxAdapter(
          key: const ValueKey('reader-bottom-pad'),
          child: SizedBox(height: 88 + bottomPadding),
        ),
      ],
    );
  }

  List<Widget> _sectionSlivers(
    _Section section, {
    required bool reverseVerseOrder,
  }) {
    final b = section.bookIndex;
    final c = section.chapter;
    final workspace = _activeStudyWorkspace;
    final chapterBookmarks =
        workspace?.passages
            .where((p) => p.wholeChapter && p.bookIndex == b && p.chapter == c)
            .toList() ??
        const <StudyPassage>[];
    final chapterHighlight = (workspace?.highlightsEnabled ?? false)
        ? chapterBookmarks.where((p) => p.highlightEnabled).lastOrNull
        : null;
    // Each study heading stands before the first verse it covers here.
    final headingsBefore = <int, List<StudyReaderHeading>>{};
    for (final heading in workspace?.readerHeadings(b, c) ?? const []) {
      final index = section.verses.indexWhere(
        (entry) => entry.verse >= heading.section.verse,
      );
      if (index >= 0) (headingsBefore[index] ??= []).add(heading);
    }
    return [
      SliverToBoxAdapter(
        key: ValueKey('divider-$b-$c'),
        child: _ChapterDivider(
          key: section.key,
          bookIndex: b,
          chapter: c,
          highlightColor: chapterHighlight == null
              ? null
              : Color(chapterHighlight.colorValue),
          studyNote: chapterBookmarks.any((p) => p.note.isNotEmpty),
          useEnglishBookNames: _englishBookNames,
        ),
      ),
      SliverPadding(
        key: ValueKey('verses-$b-$c'),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.builder(
          itemCount: section.verses.length,
          itemBuilder: (context, j) {
            // Sliver children before CustomScrollView.center grow in reverse
            // order. Feed those lists from the end so every chapter still
            // reads from verse 1 through its final verse on screen.
            final verseIndex = reverseVerseOrder
                ? section.verses.length - 1 - j
                : j;
            final entry = section.verses[verseIndex];
            final isSelected =
                entry.verse == _selectedVerse &&
                b == _selectedBook &&
                c == _selectedChapter;
            final workspace = _activeStudyWorkspace;
            final studyPassages =
                workspace
                    ?.passagesAt(b, c, entry.verse)
                    .where((p) => !p.wholeChapter)
                    .toList() ??
                const <StudyPassage>[];
            final studyPassage = studyPassages
                .where((p) => !p.isPhrase && p.highlightEnabled)
                .lastOrNull;
            final lexicalPositions = verseGlossPositions(
              entry.text.split(' ').where((w) => w.isNotEmpty).toList(),
            );
            final studyWordHighlightColors = <String, Color>{
              for (final word in workspace?.words ?? const <StudyWord>[])
                if ((workspace?.highlightsEnabled ?? false) &&
                    word.highlightEnabled &&
                    word.kind == StudyWordKind.root &&
                    word.root.isNotEmpty)
                  word.root: Color(word.colorValue),
            };
            final timelineEntries = workspace?.timelineMarkersEnabled ?? false
                ? workspace!.timelineEntriesAt(b, c, entry.verse)
                : const <StudyTimelineEntry>[];
            final translation = _translationFor(b, c, entry.verse);
            final row = VerseRow(
              key: section.verseKeys[entry.verse],
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
              onWordTap: (word, readerGloss, position, root) {
                if (_rapidReading) {
                  if (position != null) {
                    _toggleReveal(b, c, entry.verse, position);
                  }
                  return;
                }
                _showWordInfo(
                  word,
                  b,
                  c,
                  entry.verse,
                  readerGloss: readerGloss,
                  position: position,
                  root: root,
                );
              },
              onWordMenu: (word, readerGloss, position, root, globalPosition) =>
                  _showWordMenu(
                    word,
                    b,
                    c,
                    entry.verse,
                    globalPosition: globalPosition,
                    readerGloss: readerGloss,
                    position: position,
                    root: root,
                  ),
              onCrossReferences: () =>
                  widget.onCrossReferencesRequested(b, c, entry.verse),
              onVerseMenu: (globalPosition) =>
                  _showVerseMenu(b, c, entry.verse, globalPosition),
              crossReferenceMinScore: _crossReferenceMinScore,
              fontSize: _fontSize,
              fontFamily: _fontFamily,
              showCantillation: _showCantillation,
              glossInterlinear: _glossInterlinear,
              morphologyInterlinear: _morphologyInterlinear,
              interlinearPositions: _interlinearPositions(b, c, entry.verse),
              highlightProperNames: _highlightProperNames,
              studyHighlighted:
                  (workspace?.highlightsEnabled ?? false) &&
                  (studyPassage?.highlightEnabled ?? false),
              studyNote: studyPassages.any((p) => p.note.isNotEmpty),
              studyTimeline: timelineEntries.isEmpty
                  ? null
                  : timelineEntries.map((e) => e.title).join('\n'),
              onStudyTimeline: () =>
                  _showStudyTimelineEntriesAt(b, c, entry.verse),
              studyPhraseHighlightColors: {
                if (workspace?.highlightsEnabled ?? false)
                  for (final p in studyPassages)
                    if (p.isPhrase && p.highlightEnabled)
                      for (final position in lexicalPositions.whereType<int>())
                        if (p.containsWord(b, c, entry.verse, position))
                          position: Color(p.colorValue),
              },
              studyWordHighlightColors: studyWordHighlightColors,
              studyFormHighlightColors: {
                for (final word in workspace?.words ?? const <StudyWord>[])
                  if ((workspace?.highlightsEnabled ?? false) &&
                      word.highlightEnabled &&
                      word.kind == StudyWordKind.form)
                    StudyWord.formKey(word.root, word.surface): Color(
                      word.colorValue,
                    ),
              },
              studyPassageHighlightColor: studyPassage == null
                  ? null
                  : Color(studyPassage.colorValue),
              ketivDisplay: _ketivDisplay,
              syntaxMarks: _syntaxMarksFor(b, c, entry.verse),
              readerText: _readerText,
              translation: translation.spans,
              translationPending: translation.pending,
              onTranslationWordTap: (target) {
                final word = _translatedWord(b, target);
                if (word == null) return;
                _showWordInfo(
                  word.word,
                  b,
                  target.chapter,
                  target.verse,
                  readerGloss: word.gloss,
                  position: target.position,
                  root: word.root,
                );
              },
              onTranslationWordMenu: (target, globalPosition) {
                final word = _translatedWord(b, target);
                if (word == null) return;
                _showWordMenu(
                  word.word,
                  b,
                  target.chapter,
                  target.verse,
                  globalPosition: globalPosition,
                  readerGloss: word.gloss,
                  position: target.position,
                  root: word.root,
                );
              },
            );
            final headings = headingsBefore[verseIndex];
            if (headings == null) return row;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final heading in headings)
                  _StudyHeading(
                    key: ValueKey('study-heading-${heading.section.id}'),
                    heading: heading,
                    useEnglishBookNames: _englishBookNames,
                    textSize: _fontSize,
                    onAction: (action) => switch (action) {
                      _StudyHeadingAction.edit => _editStudySection(
                        heading.section,
                      ),
                      _StudyHeadingAction.addSubheading => _createStudySection(
                        heading.section.id,
                      ),
                      _StudyHeadingAction.delete => _deleteStudySection(
                        heading.section,
                      ),
                    },
                  ),
                row,
              ],
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
    required this.christadelphianReadings,
    required this.useEnglishBookNames,
    required this.onChooseBook,
    required this.onOpenNext,
    required this.onEdit,
    required this.onClear,
    required this.onOpenChristadelphianReading,
  });

  final List<_ReadingPlan> plans;
  final List<ChristadelphianReading> christadelphianReadings;
  final bool useEnglishBookNames;
  final VoidCallback onChooseBook;
  final ValueChanged<_ReadingPlan> onOpenNext;
  final ValueChanged<_ReadingPlan> onEdit;
  final ValueChanged<_ReadingPlan> onClear;
  final ValueChanged<ChristadelphianReading> onOpenChristadelphianReading;

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
            const SizedBox(height: 28),
            Text(
              'Christadelphian daily readings',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Today’s Bible Companion readings',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final reading in christadelphianReadings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(reading.reference),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenChristadelphianReading(reading),
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

/// A study summary's title, or one of its section headings, set inline
/// before the verse it starts at, with its note beneath. Tapping it offers
/// to edit it, add a subheading beneath it, or delete it.
class _StudyHeading extends StatelessWidget {
  const _StudyHeading({
    super.key,
    required this.heading,
    required this.useEnglishBookNames,
    required this.textSize,
    required this.onAction,
  });

  /// Title sizes by depth, as multiples of the verse text's size: a step
  /// smaller for each level down, never below the text itself, which the
  /// deepest levels share.
  static const _headingScales = [1.4, 1.3, 1.2, 1.1, 1.0];

  final StudyReaderHeading heading;
  final bool useEnglishBookNames;

  /// The reader's verse text size.
  final double textSize;
  final ValueChanged<_StudyHeadingAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = heading.section;
    final isSummary = heading.depth == 0;
    final range = heading.summary.range!;
    final content = Padding(
      padding: EdgeInsetsDirectional.only(
        start: (heading.depth - 1).clamp(0, 6) * 16.0,
        top: isSummary ? 16 : 12,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize:
                  textSize *
                  _headingScales[heading.depth.clamp(
                    0,
                    _headingScales.length - 1,
                  )],
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          if (isSummary)
            Text(
              '${bookDisplayName(range.bookIndex, useEnglish: useEnglishBookNames)} '
              '${range.reference}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (section.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: MarkdownNote(
                section.note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
    return PopupMenuButton<_StudyHeadingAction>(
      tooltip: 'Study heading options',
      position: PopupMenuPosition.under,
      onSelected: onAction,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _StudyHeadingAction.edit,
          child: ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(isSummary ? 'Edit summary' : 'Edit heading'),
          ),
        ),
        const PopupMenuItem(
          value: _StudyHeadingAction.addSubheading,
          child: ListTile(
            leading: Icon(Icons.subdirectory_arrow_right),
            title: Text('Add subheading'),
          ),
        ),
        PopupMenuItem(
          value: _StudyHeadingAction.delete,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(isSummary ? 'Delete summary' : 'Delete heading'),
          ),
        ),
      ],
      child: SizedBox(width: double.infinity, child: content),
    );
  }
}

class _ChapterDivider extends StatelessWidget {
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;
  final Color? highlightColor;
  final bool studyNote;

  const _ChapterDivider({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.useEnglishBookNames,
    this.highlightColor,
    this.studyNote = false,
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
          Container(
            key: ValueKey('chapter-heading-$bookIndex-$chapter'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: highlightColor == null
                  ? null
                  : theme.brightness == Brightness.dark
                  ? studyHighlightBackground(highlightColor!, theme)
                  : highlightColor!.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                if (studyNote)
                  const Icon(Icons.sticky_note_2_outlined, size: 12),
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
