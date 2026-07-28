import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'about_page.dart';
import 'app_settings.dart';
import 'bible_data.dart';
import 'christadelphian_readings.dart';
import 'bindings/bindings.dart';
import 'issue_reporting.dart';
import 'study_workspace.dart';
import 'tutor/onboarding.dart';
import 'tutor/progress_sync.dart';
import 'widgets/book_selector.dart';
import 'widgets/chapter_selector.dart';
import 'widgets/study_workspace_panel.dart';
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
  final Map<int, GlobalKey> verseKeys;

  _Section({
    required this.bookIndex,
    required this.chapter,
    required this.verses,
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
  });

  final String word;
  final int bookIndex;
  final int chapter;
  final int verse;
  final int? position;
  final String root;
  final String? readerGloss;
}

enum _ReaderMenuAction {
  studyWorkspace,
  readingPlan,
  tutor,
  reportIssue,
  settings,
  about,
}

enum _ResolvedReaderLayout { focus, split, threePanel }

const _workspaceMinimumTileWidth = 260.0;
const _workspacePanelDividerWidth = 9.0;

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({super.key, this.sendChapterRequest});

  final void Function(GetChapter request)? sendChapterRequest;

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

  final List<_ReaderTab> _tabs = [const _ReaderTab('primary')];
  final Map<String, GlobalKey<_ReaderSessionState>> _readerKeys = {
    'primary': GlobalKey<_ReaderSessionState>(),
  };
  final PageController _pageController = PageController();
  String _activeTabId = 'primary';
  bool _tiled = false;
  double _tiledPanelWidth = 360;
  bool _loaded = false;
  bool _mobileBarHidden = false;
  Timer? _mobileBarTransitionTimer;

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  Future<void> _loadWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIds = prefs.getStringList(_kTabs) ?? const [];
    final ids = savedIds.where((id) => id.isNotEmpty).toSet().toList();
    if (!ids.contains('primary')) ids.insert(0, 'primary');
    final active = prefs.getString(_kActiveTab);
    if (!mounted) return;
    setState(() {
      _tabs
        ..clear()
        ..addAll(ids.map(_ReaderTab.new));
      for (final tab in _tabs) {
        _readerKeys.putIfAbsent(tab.id, () => GlobalKey<_ReaderSessionState>());
      }
      _activeTabId = ids.contains(active) ? active! : ids.first;
      _tiled = prefs.getBool(_kTiled) ?? false;
      _tiledPanelWidth = prefs.getDouble(_kTiledPanelWidth) ?? 360;
      _loaded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(
        _tabs.indexWhere((tab) => tab.id == _activeTabId),
      );
    });
  }

  Future<void> _saveWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setStringList(_kTabs, _tabs.map((tab) => tab.id).toList()),
      prefs.setString(_kActiveTab, _activeTabId),
      prefs.setBool(_kTiled, _tiled),
      prefs.setDouble(_kTiledPanelWidth, _tiledPanelWidth),
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
        _pageController.animateToPage(
          _tabs.length - 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
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
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(
          _tabs.indexWhere((tab) => tab.id == _activeTabId),
        );
      }
    });
    _saveWorkspace();
  }

  @override
  void dispose() {
    _mobileBarTransitionTimer?.cancel();
    _pageController.dispose();
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
      if (mounted && _tiled) {
        setState(() => _activeTabId = tab.id);
        _saveWorkspace();
      }
    },
    onScrollChromeChanged: (hidden) {
      if (MediaQuery.sizeOf(context).width >= 900 ||
          _mobileBarHidden == hidden) {
        return;
      }
      _setMobileBarHidden(hidden);
    },
    sendChapterRequest: widget.sendChapterRequest,
    onPassageChanged: () {
      if (mounted) setState(() {});
    },
  );

  Widget? _tiledAuxiliaryPanel() {
    final state = _activeReader;
    if (state == null ||
        (!state._studyWorkspaceVisible && state._selectedWord == null)) {
      return null;
    }
    return state._tiledAuxiliaryPanel();
  }

  _ReaderSessionState? get _activeReader =>
      _readerKeys[_activeTabId]?.currentState;

  List<_ReaderMenuAction> get _workspaceActions => [
    _ReaderMenuAction.studyWorkspace,
    _ReaderMenuAction.readingPlan,
    _ReaderMenuAction.tutor,
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
        _ReaderMenuAction.readingPlan => (
          Icons.auto_stories_outlined,
          'Reading plan',
        ),
        _ReaderMenuAction.tutor => (Icons.school_outlined, 'Tutor'),
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
        (_activeReader?._studyWorkspaceVisible ?? false);
    return IconButton(
      isSelected: studySelected,
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
    if (action == _ReaderMenuAction.settings) {
      _showSharedReaderSettings();
      return;
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
    final showTabStrip = !mobile || _tabs.length > 1;
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
                      final tabWidth = showTabStrip
                          ? math.min(
                              constraints.maxWidth * 0.7,
                              _tabs.length * 150.0,
                            )
                          : 0.0;
                      final fixedWidth = 48.0 + (canTile ? 48 : 0) + 48;
                      final directActionCount = mobile
                          ? 0
                          : ((constraints.maxWidth - tabWidth - fixedWidth) ~/
                                    48)
                                .clamp(0, actions.length);
                      final directActions = actions.take(directActionCount);
                      final overflowActions = actions.skip(directActionCount);

                      return Row(
                        children: [
                          Expanded(
                            child: showTabStrip
                                ? ListView.separated(
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
                                        selected: tab.id == _activeTabId,
                                        onPressed: () {
                                          setState(() => _activeTabId = tab.id);
                                          _pageController.animateToPage(
                                            index,
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            curve: Curves.easeOut,
                                          );
                                          _saveWorkspace();
                                        },
                                        onDeleted: _tabs.length > 1
                                            ? () => _closeTab(tab.id)
                                            : null,
                                        deleteButtonTooltipMessage:
                                            'Close reader tab',
                                      );
                                    },
                                  )
                                : const SizedBox.shrink(),
                          ),
                          for (final action in directActions)
                            _workspaceActionButton(action),
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
                    : PageView(
                        controller: _pageController,
                        onPageChanged: (index) {
                          setState(() {
                            _activeTabId = _tabs[index].id;
                            _mobileBarHidden = false;
                          });
                          _saveWorkspace();
                        },
                        children: [
                          for (final tab in _tabs) _reader(tab, tiled: false),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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
    this.sendChapterRequest,
  });

  final String sessionId;
  final VoidCallback onPassageChanged;
  final ValueChanged<bool> onScrollChromeChanged;
  final bool tiled;
  final VoidCallback onWorkspaceTilesChanged;

  /// Test seam: how a [GetChapter] request reaches the Rust side. Defaults to
  /// the real rinf signal; widget tests substitute a stub that answers via
  /// `assignRustSignal['ChapterText']`.
  final void Function(GetChapter request)? sendChapterRequest;

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
  static const _kNtSyriac = 'nt_syriac';
  static const _kEnglishBookNames = 'english_book_names';
  static const _kHebrewNumerals = 'hebrew_numerals';
  static const _kFontSize = 'font_size';
  static const _kFontFamily = 'font_family';
  static const _kShowCantillation = 'show_cantillation';
  static const _kGlossInterlinear = 'gloss_interlinear';
  static const _kMorphologyInterlinear = 'morphology_interlinear';
  static const _kHighlightProperNames = 'highlight_proper_names';
  static const _kKetivDisplay = 'ketiv_display';
  static const _kReadingPlanBook = 'reading_plan_book';
  static const _kReadingPlanCompleted = 'reading_plan_completed';
  static const _kReadingPlans = 'reading_plans';
  static const _kReaderLayoutMode = 'reader_layout_mode';
  static const _kStudyWorkspaceVisible = 'study_workspace_visible';
  static const _kSidePanelWidth = 'reader_side_panel_width';

  static const _fontFamilies = ['Cardo', 'David Libre', 'Frank Ruhl Libre'];

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
  bool _morphologyInterlinear = false;
  bool _highlightProperNames = false;
  bool _studyWorkspaceVisible = false;
  KetivDisplay _ketivDisplay = KetivDisplay.superscript;
  ReaderLayoutMode _readerLayoutMode = ReaderLayoutMode.automatic;
  List<_ReadingPlan> _readingPlans = [];
  List<StudyWorkspace> _studyWorkspaces = [];
  String? _activeStudyWorkspaceId;
  _SelectedWord? _selectedWord;
  bool _splitShowsWord = false;
  double _sidePanelWidth = 360;
  double _chromeScrollDelta = 0;
  double? _lastChromeScrollPixels;
  Timer? _positionSaveTimer;

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
  StreamSubscription<RustSignalPack<StudyState>>? _studyStateSub;
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
    _studyStateSub = StudyState.rustSignalStream.listen((pack) async {
      if (!mounted) return;
      final message = pack.message;
      if (!message.found) {
        final prefs = await SharedPreferences.getInstance();
        final legacyJson = prefs.getString(studyWorkspacesKey);
        if (legacyJson != null && legacyJson.isNotEmpty) {
          SaveStudyState(
            workspacesJson: legacyJson,
            activeWorkspaceId: prefs.getString(activeStudyWorkspaceKey) ?? '',
          ).sendSignalToRust();
          scheduleProgressSync();
        }
        return;
      }
      final workspaces = decodeStudyWorkspaces(message.workspacesJson);
      final activeId =
          workspaces.any(
            (workspace) => workspace.id == message.activeWorkspaceId,
          )
          ? message.activeWorkspaceId
          : workspaces.isEmpty
          ? null
          : workspaces.first.id;
      setState(() {
        _studyWorkspaces = workspaces;
        _activeStudyWorkspaceId = activeId;
      });
      final prefs = await SharedPreferences.getInstance();
      await saveStudyWorkspaces(prefs, workspaces, activeId);
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
      setState(() {
        final loaded = _sections[loadedIndex];
        loaded.verses = verses;
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
    setState(() {
      _bookIndex = (prefs.getInt(_sessionKey(_kBook)) ?? 0).clamp(
        0,
        kBooks.length - 1,
      );
      _chapter = (prefs.getInt(_sessionKey(_kChapter)) ?? 1).clamp(
        1,
        kBooks[_bookIndex].chapters,
      );
      _visibleVerse = (prefs.getInt(_sessionKey(_kVerse)) ?? 1).clamp(1, 999);
      _ntSyriac = prefs.getBool(_kNtSyriac) ?? false;
      _englishBookNames = prefs.getBool(_kEnglishBookNames) ?? false;
      _hebrewNumerals = prefs.getBool(_kHebrewNumerals) ?? true;
      _fontSize = (prefs.getDouble(_kFontSize) ?? 20.0).clamp(16.0, 28.0);
      final savedFamily = prefs.getString(_kFontFamily) ?? 'Cardo';
      _fontFamily = _fontFamilies.contains(savedFamily) ? savedFamily : 'Cardo';
      _showCantillation = prefs.getBool(_kShowCantillation) ?? true;
      _glossInterlinear = prefs.getBool(_kGlossInterlinear) ?? false;
      _morphologyInterlinear = prefs.getBool(_kMorphologyInterlinear) ?? false;
      _highlightProperNames = prefs.getBool(_kHighlightProperNames) ?? false;
      _studyWorkspaceVisible = prefs.getBool(_kStudyWorkspaceVisible) ?? false;
      _sidePanelWidth = (prefs.getDouble(_kSidePanelWidth) ?? 360).clamp(
        280,
        600,
      );
      _ketivDisplay = KetivDisplay.values.firstWhere(
        (option) => option.name == prefs.getString(_kKetivDisplay),
        orElse: () => KetivDisplay.superscript,
      );
      _readerLayoutMode = ReaderLayoutMode.values.firstWhere(
        (option) => option.name == prefs.getString(_kReaderLayoutMode),
        orElse: () => ReaderLayoutMode.automatic,
      );
      _studyWorkspaces = decodeStudyWorkspaces(
        prefs.getString(studyWorkspacesKey),
      );
      final savedWorkspace = prefs.getString(activeStudyWorkspaceKey);
      _activeStudyWorkspaceId =
          _studyWorkspaces.any((workspace) => workspace.id == savedWorkspace)
          ? savedWorkspace
          : _studyWorkspaces.isEmpty
          ? null
          : _studyWorkspaces.first.id;
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
    GetStudyState().sendSignalToRust();
    final rawHistory = prefs.getStringList(_sessionKey(_kHistory)) ?? [];
    final savedIndex = prefs.getInt(_sessionKey(_kHistoryIndex)) ?? -1;
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
      prefs.setBool(_kNtSyriac, _ntSyriac),
      prefs.setBool(_kEnglishBookNames, _englishBookNames),
      prefs.setBool(_kHebrewNumerals, _hebrewNumerals),
      prefs.setDouble(_kFontSize, _fontSize),
      prefs.setString(_kFontFamily, _fontFamily),
      prefs.setBool(_kShowCantillation, _showCantillation),
      prefs.setBool(_kGlossInterlinear, _glossInterlinear),
      prefs.setBool(_kMorphologyInterlinear, _morphologyInterlinear),
      prefs.setBool(_kHighlightProperNames, _highlightProperNames),
      prefs.setBool(_kStudyWorkspaceVisible, _studyWorkspaceVisible),
      prefs.setDouble(_kSidePanelWidth, _sidePanelWidth),
      prefs.setString(_kKetivDisplay, _ketivDisplay.name),
      prefs.setString(_kReaderLayoutMode, _readerLayoutMode.name),
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
      _ntSyriac = settings.ntSyriac;
      _englishBookNames = settings.englishBookNames;
      _hebrewNumerals = settings.hebrewNumerals;
      _showCantillation = settings.showCantillation;
      _glossInterlinear = settings.glossInterlinear;
      _morphologyInterlinear = settings.morphologyInterlinear;
      _highlightProperNames = settings.highlightProperNames;
      _ketivDisplay = settings.ketivDisplay;
      _fontSize = settings.fontSize;
      _fontFamily = settings.fontFamily;
      _readerLayoutMode = settings.readerLayoutMode;
    });
    if (reloadChapter) {
      _pendingVerse = _visibleVerse;
      _startAt(_bookIndex, _chapter);
    } else {
      _savePrefs();
    }
  }

  AppReadingSettings get _readingSettings => AppReadingSettings(
    ntSyriac: _ntSyriac,
    englishBookNames: _englishBookNames,
    hebrewNumerals: _hebrewNumerals,
    showCantillation: _showCantillation,
    glossInterlinear: _glossInterlinear,
    morphologyInterlinear: _morphologyInterlinear,
    highlightProperNames: _highlightProperNames,
    ketivDisplay: _ketivDisplay,
    fontSize: _fontSize,
    fontFamily: _fontFamily,
    readerLayoutMode: _readerLayoutMode,
  );

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

  Future<void> _saveStudyState() async {
    final prefs = await SharedPreferences.getInstance();
    await saveStudyWorkspaces(prefs, _studyWorkspaces, _activeStudyWorkspaceId);
    SaveStudyState(
      workspacesJson: encodeStudyWorkspaces(_studyWorkspaces),
      activeWorkspaceId: _activeStudyWorkspaceId ?? '',
    ).sendSignalToRust();
    scheduleProgressSync();
  }

  void _replaceStudyWorkspace(StudyWorkspace updated) {
    final index = _studyWorkspaces.indexWhere(
      (workspace) => workspace.id == updated.id,
    );
    if (index < 0) return;
    setState(() => _studyWorkspaces[index] = updated);
    _saveStudyState();
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
    setState(() {
      _studyWorkspaces.add(workspace);
      _activeStudyWorkspaceId = workspace.id;
    });
    await _saveStudyState();
    return workspace;
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
    setState(() {
      _studyWorkspaces.removeWhere((candidate) => candidate.id == workspace.id);
      _activeStudyWorkspaceId = _studyWorkspaces.isEmpty
          ? null
          : _studyWorkspaces.first.id;
    });
    _saveStudyState();
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

  void _bookmarkCurrentStudyPassage(String? groupId) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final current = _currentStudyPassage;
    final existing = workspace.passageAt(
      current.bookIndex,
      current.chapter,
      current.verse,
    );
    _replaceStudyWorkspace(
      workspace.putPassage(
        (existing ?? current).copyWith(groupId: () => groupId),
      ),
    );
  }

  Future<void> _editStudyPassage(StudyPassage passage) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final note = await _askForText(
      title:
          '${bookDisplayName(passage.bookIndex, useEnglish: _englishBookNames)} '
          '${passage.chapter}:${passage.verse}',
      initialValue: passage.note,
      label: 'Passage note',
      maxLines: 5,
    );
    if (note != null && mounted) {
      _replaceStudyWorkspace(
        workspace.putPassage(passage.copyWith(note: note)),
      );
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

  Future<bool> _toggleStudyWordBookmark(String root, String surface) async {
    if (root.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This word has no resolved root.')),
        );
      }
      return false;
    }
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return false;
    final existing = workspace.wordForRoot(root);
    if (existing == null) {
      _replaceStudyWorkspace(
        workspace.putWord(StudyWord(root: root, surface: surface)),
      );
      _refreshLoadedChaptersForStudyRoots();
      return true;
    }
    _replaceStudyWorkspace(workspace.removeWord(existing));
    return false;
  }

  Future<void> _editStudyWord(StudyWord word) async {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    final note = await _askForText(
      title: word.root.isEmpty ? word.surface : word.root,
      initialValue: word.note,
      label: 'Word note',
      maxLines: 5,
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

  void _removeStudyWord(StudyWord word) {
    final workspace = _activeStudyWorkspace;
    if (workspace == null) return;
    _replaceStudyWorkspace(workspace.removeWord(word));
  }

  Future<void> _createStudyNote(String? groupId) async {
    final workspace = await _ensureStudyWorkspace();
    if (workspace == null || !mounted) return;
    final text = await _askForText(
      title: 'New study note',
      initialValue: '',
      label: 'Note',
      maxLines: 8,
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
    final text = await _askForText(
      title: 'Edit study note',
      initialValue: note.text,
      label: 'Note',
      maxLines: 8,
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

  void _reorderStudyItems(String? groupId, int oldIndex, int newIndex) {
    final workspace = _activeStudyWorkspace;
    if (workspace != null) {
      _replaceStudyWorkspace(
        workspace.reorderItems(groupId, oldIndex, newIndex),
      );
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
      _dropCachedChapter(section.bookIndex, section.chapter);
      _fetchChapter(section.bookIndex, section.chapter, force: true);
    }
  }

  void _toggleStudyWorkspacePanel() {
    final enabled = !_studyWorkspaceVisible;
    setState(() {
      _studyWorkspaceVisible = enabled;
      if (enabled) _splitShowsWord = false;
    });
    widget.onWorkspaceTilesChanged();
    _savePrefs();
    if (enabled) _refreshLoadedChaptersForStudyRoots();
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
              setState(() => _activeStudyWorkspaceId = id);
              _saveStudyState();
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
            onBookmarkCurrent: (groupId) {
              _bookmarkCurrentStudyPassage(groupId);
              setSheetState(() {});
            },
            onOpenPassage: (passage) {
              Navigator.pop(sheetContext);
              _navigateTo(
                passage.bookIndex,
                passage.chapter,
                verse: passage.verse,
              );
            },
            onEditPassage: (passage) async {
              await _editStudyPassage(passage);
              setSheetState(() {});
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
            onReorderItems: (groupId, oldIndex, newIndex) {
              _reorderStudyItems(groupId, oldIndex, newIndex);
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
      _selectedWord = null;
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
    _updateCurrentPassage();
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
        ? -verseRowScrollExtent(
            fontSize: _fontSize,
            fontFamily: _fontFamily,
            interlinear: _glossInterlinear || _morphologyInterlinear,
          )
        : key == LogicalKeyboardKey.arrowDown
        ? verseRowScrollExtent(
            fontSize: _fontSize,
            fontFamily: _fontFamily,
            interlinear: _glossInterlinear || _morphologyInterlinear,
          )
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
    final appBarBottom = kToolbarHeight + MediaQuery.of(context).padding.top;
    final readingLine = appBarBottom + 8;
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
    _studyStateSub?.cancel();
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
    final layout = widget.tiled
        ? _ResolvedReaderLayout.split
        : _resolveReaderLayout(MediaQuery.sizeOf(context).width);
    if (widget.tiled || layout != _ResolvedReaderLayout.focus) {
      setState(() {
        _selectedWord = selected;
        _splitShowsWord = true;
      });
      widget.onWorkspaceTilesChanged();
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WordInfoSheet(
        word: word,
        syriac: bookIndex >= 39,
        book: bookIndex + 1,
        chapter: chapter,
        verse: verse,
        position: position,
        readerGloss: readerGloss,
        useEnglishBookNames: _englishBookNames,
        reportContext: {
          'bookIndex': bookIndex,
          'book': kBooks[bookIndex].transliteration,
          'chapter': chapter,
          'verse': verse,
        },
        isStudyBookmarked: (resolvedRoot) =>
            _activeStudyWorkspace?.wordForRoot(resolvedRoot) != null,
        onToggleStudyBookmark: _toggleStudyWordBookmark,
        onNavigateToPassage: (bi, chapter, verse) {
          Navigator.pop(ctx);
          _navigateTo(bi, chapter, verse: verse);
        },
      ),
    );
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

  Widget _studyWorkspacePanel() => StudyWorkspacePanel(
    workspaces: _studyWorkspaces,
    activeWorkspace: _activeStudyWorkspace,
    currentPassage: _currentStudyPassage,
    useEnglishBookNames: _englishBookNames,
    onCreate: _createStudyWorkspace,
    onSelect: (id) {
      setState(() => _activeStudyWorkspaceId = id);
      _saveStudyState();
      _refreshLoadedChaptersForStudyRoots();
    },
    onRename: _renameStudyWorkspace,
    onDelete: _deleteStudyWorkspace,
    onToggleHighlights: _toggleStudyHighlights,
    onCreateGroup: _createStudyGroup,
    onEditGroup: _editStudyGroup,
    onDeleteGroup: _deleteStudyGroup,
    onBookmarkCurrent: _bookmarkCurrentStudyPassage,
    onOpenPassage: (passage) =>
        _navigateTo(passage.bookIndex, passage.chapter, verse: passage.verse),
    onEditPassage: _editStudyPassage,
    onUpdatePassage: _updateStudyPassage,
    onRemovePassage: _removeStudyPassage,
    onEditWord: _editStudyWord,
    onUpdateWord: _updateStudyWord,
    onRemoveWord: _removeStudyWord,
    onOpenWord: _openStudyWord,
    onCreateNote: _createStudyNote,
    onEditNote: _editStudyNote,
    onUpdateNote: _updateStudyNote,
    onRemoveNote: _removeStudyNote,
    onReorderItems: _reorderStudyItems,
  );

  Widget _tiledAuxiliaryPanel() {
    if (!_studyWorkspaceVisible) return _wordInspector();
    if (_selectedWord == null) return _studyWorkspacePanel();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.account_tree_outlined),
                label: Text('Study'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.menu_book_outlined),
                label: Text('Word'),
              ),
            ],
            selected: {_splitShowsWord},
            onSelectionChanged: (selection) =>
                setState(() => _splitShowsWord = selection.single),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _splitShowsWord ? _wordInspector() : _studyWorkspacePanel(),
        ),
      ],
    );
  }

  Widget _wordInspector() {
    final theme = Theme.of(context);
    final selected = _selectedWord;
    return Material(
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
            : WordInfoSheet(
                key: ValueKey(
                  '${selected.bookIndex}:${selected.chapter}:'
                  '${selected.verse}:${selected.position}:${selected.word}',
                ),
                docked: true,
                word: selected.word,
                syriac: selected.bookIndex >= 39,
                book: selected.bookIndex + 1,
                chapter: selected.chapter,
                verse: selected.verse,
                position: selected.position,
                readerGloss: selected.readerGloss,
                useEnglishBookNames: _englishBookNames,
                reportContext: {
                  'bookIndex': selected.bookIndex,
                  'book': kBooks[selected.bookIndex].transliteration,
                  'chapter': selected.chapter,
                  'verse': selected.verse,
                },
                isStudyBookmarked: (root) =>
                    _activeStudyWorkspace?.wordForRoot(root) != null,
                onToggleStudyBookmark: _toggleStudyWordBookmark,
                onNavigateToPassage: (book, chapter, verse) {
                  setState(() => _selectedWord = null);
                  widget.onWorkspaceTilesChanged();
                  _navigateTo(book, chapter, verse: verse);
                },
              ),
      ),
    );
  }

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
      onHorizontalDragEnd: (_) => _savePrefs(),
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

  Widget _responsiveReaderBody(_ResolvedReaderLayout layout) {
    final reader = _readerSurface();
    if (widget.tiled) return reader;
    switch (layout) {
      case _ResolvedReaderLayout.focus:
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: reader,
          ),
        );
      case _ResolvedReaderLayout.split:
        if (!_studyWorkspaceVisible && _selectedWord == null) {
          return reader;
        }
        return LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Expanded(child: reader),
              _sidePanelResizeHandle(constraints.maxWidth),
              SizedBox(
                width: _resolvedSidePanelWidth(constraints.maxWidth),
                child: !_studyWorkspaceVisible
                    ? _wordInspector()
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  icon: Icon(Icons.account_tree_outlined),
                                  label: Text('Study'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  icon: Icon(Icons.menu_book_outlined),
                                  label: Text('Word'),
                                ),
                              ],
                              selected: {_splitShowsWord},
                              onSelectionChanged: (selection) => setState(
                                () => _splitShowsWord = selection.single,
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _splitShowsWord
                                ? _wordInspector()
                                : _studyWorkspacePanel(),
                          ),
                        ],
                      ),
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
                child: _wordInspector(),
              ),
            ],
          ),
        );
    }
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
      case _ReaderMenuAction.readingPlan:
        _showReadingPlan();
      case _ReaderMenuAction.tutor:
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TutorEntryPage()));
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
    final book = kBooks[_bookIndex];
    final theme = Theme.of(context);
    final layout = _resolveReaderLayout(MediaQuery.sizeOf(context).width);
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
        ],
      ),
      body: _responsiveReaderBody(layout),
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
            final studyPassage = workspace?.passageAt(b, c, entry.verse);
            final studyWordHighlightColors = <String, Color>{
              for (final word in workspace?.words ?? const <StudyWord>[])
                if ((workspace?.highlightsEnabled ?? false) &&
                    word.highlightEnabled &&
                    word.root.isNotEmpty)
                  word.root: Color(word.colorValue),
            };
            return VerseRow(
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
              onWordTap: (word, readerGloss, position, root) => _showWordInfo(
                word,
                b,
                c,
                entry.verse,
                readerGloss: readerGloss,
                position: position,
                root: root,
              ),
              fontSize: _fontSize,
              fontFamily: _fontFamily,
              showCantillation: _showCantillation,
              glossInterlinear: _glossInterlinear,
              morphologyInterlinear: _morphologyInterlinear,
              highlightProperNames: _highlightProperNames,
              studyHighlighted:
                  (workspace?.highlightsEnabled ?? false) &&
                  (studyPassage?.highlightEnabled ?? false),
              studyNote: studyPassage?.note.isNotEmpty ?? false,
              studyWordHighlightColors: studyWordHighlightColors,
              studyPassageHighlightColor: studyPassage == null
                  ? null
                  : Color(studyPassage.colorValue),
              ketivDisplay: _ketivDisplay,
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
