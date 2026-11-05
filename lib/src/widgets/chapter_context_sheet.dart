import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../apologetics.dart';
import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../outlines.dart';
import 'apologetics_page.dart';
import 'archaeology_page.dart';
import 'chapter_span.dart';
import 'name_details.dart';
import 'outlines_page.dart';

/// The tabs of [ChapterContextSheet], in the order it shows them.
enum ChapterContextTab {
  crossReferences('Cross refs', Icons.link),
  structure('Structure', Icons.toc),
  places('Places', Icons.map_outlined),
  people('People', Icons.people_outline),
  archaeology('Archaeology', Icons.account_balance_outlined),
  apologetics('Apologetics', Icons.shield_outlined);

  const ChapterContextTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// How far around its chapter [ChapterContextSheet] looks.
enum ChapterContextScope {
  chapter('Chapter'),
  nearby('Nearby'),
  book('Book');

  const ChapterContextScope(this.label);

  final String label;

  /// How many chapters either side [nearby] takes in.
  static const nearbyReach = 2;

  /// The first and last chapter it takes in around chapter [at] of a book of
  /// [chapters].
  (int, int) span(int at, int chapters) => switch (this) {
    chapter => (at, at),
    nearby => (
      math.max(1, at - nearbyReach),
      math.min(chapters, at + nearbyReach),
    ),
    book => (1, chapters),
  };
}

/// What surrounds a chapter, one tab each: its cross references, where it
/// stands in the book outlines, the places it names on a map, the people it names and how they are related, the
/// finds bearing on it, and the apologetics on its passages. It can widen to the chapters nearby or the book.
class ChapterContextSheet extends StatefulWidget {
  const ChapterContextSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.initialTab = ChapterContextTab.crossReferences,
    this.onTabChanged,
    this.initialScope = ChapterContextScope.chapter,
    this.onScopeChanged,
    this.useEnglishBookNames = false,
    this.ntSyriac = false,
    this.ntGreek = false,
    this.onNtGreekChanged,
    this.bookmarks,
    this.onNavigateToPassage,
    this.sendPlacesRequest,
    this.sendPeopleRequest,
    this.sendArtifactsRequest,
    this.crossReferencesBuilder,
    this.onClose,
  });

  /// Zero-based, as the reader counts books.
  final int bookIndex;
  final int chapter;

  /// The tab first shown, and where a switch to another is reported, so the
  /// reader can open on the one last read.
  final ChapterContextTab initialTab;
  final ValueChanged<ChapterContextTab>? onTabChanged;

  /// How far around the chapter it first looks, and where a change is
  /// reported, likewise.
  final ChapterContextScope initialScope;
  final ValueChanged<ChapterContextScope>? onScopeChanged;

  final bool useEnglishBookNames;
  final bool ntSyriac;
  final bool ntGreek;
  final ValueChanged<bool>? onNtGreekChanged;
  final NameBookmarks? bookmarks;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;

  /// Where each tab sends its request, in place of Rust, for tests.
  final void Function(GetChapterPlaces)? sendPlacesRequest;
  final void Function(GetChapterPeople)? sendPeopleRequest;
  final void Function(GetChapterArtifacts)? sendArtifactsRequest;

  /// The cross references of the chapters [first] to [last], which the
  /// reader builds with its own bookmarks and strength filter. Without it
  /// the sheet has no cross-references tab.
  final Widget Function(BuildContext context, int first, int last)?
  crossReferencesBuilder;

  /// What its close button does: by default it leaves the sheet's route, but
  /// docked beside the reader it hides the panel.
  final VoidCallback? onClose;

  @override
  State<ChapterContextSheet> createState() => _ChapterContextSheetState();
}

class _ChapterContextSheetState extends State<ChapterContextSheet>
    with SingleTickerProviderStateMixin {
  /// The tabs shown: cross references only where the reader builds them.
  late final List<ChapterContextTab> _shown = [
    for (final tab in ChapterContextTab.values)
      if (tab != ChapterContextTab.crossReferences ||
          widget.crossReferencesBuilder != null)
        tab,
  ];

  late final TabController _tabs = TabController(
    length: _shown.length,
    initialIndex: math.max(0, _shown.indexOf(widget.initialTab)),
    vsync: this,
  )..addListener(_tabChanged);

  late ChapterContextScope _scope = widget.initialScope;

  /// The chapters [scope] takes in.
  (int, int) _span(ChapterContextScope scope) =>
      scope.span(widget.chapter, kBooks[widget.bookIndex].chapters);

  /// The scopes worth offering: of those taking in the same chapters (all
  /// of a short book is nearby), the broadest.
  List<ChapterContextScope> get _scopes {
    final scopes = <ChapterContextScope>[];
    for (final scope in ChapterContextScope.values) {
      if (scopes.isNotEmpty && _span(scope) == _span(scopes.last)) {
        scopes.removeLast();
      }
      scopes.add(scope);
    }
    return scopes;
  }

  void _setScope(ChapterContextScope scope) {
    setState(() => _scope = scope);
    widget.onScopeChanged?.call(scope);
    _probe();
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    widget.onTabChanged?.call(_shown[_tabs.index]);
  }

  /// The probes' request ids, apart from those the tabs number from one, so
  /// that neither takes the other's reply for its own.
  static int _nextProbeId = 1 << 30;

  /// Whether the places, people and archaeology tabs have anything over the
  /// span, as their probes have answered; absent until then.
  final Map<ChapterContextTab, bool> _found = {};
  int? _placesProbe;
  int? _peopleProbe;
  int? _findsProbe;
  late final List<StreamSubscription<dynamic>> _probeReplies = [
    ChapterPlaces.rustSignalStream.listen((pack) {
      if (pack.message.requestId == _placesProbe) {
        _answer(ChapterContextTab.places, pack.message.places.isNotEmpty);
      }
    }),
    ChapterPeople.rustSignalStream.listen((pack) {
      if (pack.message.requestId == _peopleProbe) {
        _answer(ChapterContextTab.people, pack.message.people.isNotEmpty);
      }
    }),
    ChapterArtifacts.rustSignalStream.listen((pack) {
      if (pack.message.requestId == _findsProbe) {
        _answer(ChapterContextTab.archaeology, pack.message.entries.isNotEmpty);
      }
    }),
  ];

  void _answer(ChapterContextTab tab, bool found) {
    if (mounted) setState(() => _found[tab] = found);
  }

  /// Asks whether the places, people and archaeology tabs have anything over
  /// the span, so that the empty ones can be greyed out without opening
  /// them.
  void _probe() {
    _probeReplies; // Listening before the replies can come.
    final (first, last) = _span(_scope);
    final book = widget.bookIndex + 1;
    _found.clear();
    final places = GetChapterPlaces(
      requestId: _placesProbe = _nextProbeId++,
      book: book,
      chapter: first,
      lastChapter: last,
    );
    final people = GetChapterPeople(
      requestId: _peopleProbe = _nextProbeId++,
      book: book,
      chapter: first,
      lastChapter: last,
    );
    final finds = GetChapterArtifacts(
      requestId: _findsProbe = _nextProbeId++,
      book: book,
      chapter: first,
      lastChapter: last,
    );
    _send(places, widget.sendPlacesRequest, places.sendSignalToRust);
    _send(people, widget.sendPeopleRequest, people.sendSignalToRust);
    _send(finds, widget.sendArtifactsRequest, finds.sendSignalToRust);
  }

  /// Sends a probe by [send], or else to Rust. A probe is only a hint: one
  /// that cannot be sent, where there is no Rust to send it to, leaves its
  /// tab as it is rather than failing the sheet.
  static void _send<T>(
    T request,
    void Function(T)? send,
    void Function() toRust,
  ) {
    if (send != null) return send(request);
    try {
      toRust();
    } on ArgumentError {
      // No Rust library loaded: the tab is not judged.
    }
  }

  /// Whether [tab] has nothing over the span: false while it is not known.
  /// The apologetics and outlines are held whole, so are known once loaded;
  /// cross references are never judged.
  bool _empty(ChapterContextTab tab) {
    final (first, last) = _span(_scope);
    final book = widget.bookIndex + 1;
    return switch (tab) {
      ChapterContextTab.crossReferences => false,
      ChapterContextTab.structure =>
        OutlinesStore.instance.loaded &&
            OutlinesStore.instance.touching(book, first, last).isEmpty,
      ChapterContextTab.apologetics =>
        ApologeticsStore.instance.loaded &&
            ApologeticsStore.instance.touching(book, first, last).isEmpty,
      _ => _found[tab] == false,
    };
  }

  void _storeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    OutlinesStore.instance.addListener(_storeChanged);
    ApologeticsStore.instance.addListener(_storeChanged);
    _probe();
  }

  @override
  void didUpdateWidget(ChapterContextSheet old) {
    super.didUpdateWidget(old);
    if (old.bookIndex != widget.bookIndex || old.chapter != widget.chapter) {
      _probe();
    }
  }

  @override
  void dispose() {
    for (final s in _probeReplies) {
      s.cancel();
    }
    OutlinesStore.instance.removeListener(_storeChanged);
    ApologeticsStore.instance.removeListener(_storeChanged);
    _tabs.dispose();
    super.dispose();
  }

  Widget _tab(ChapterContextTab tab) {
    final (first, last) = _span(_scope);
    // A new span is a new request, as is another book, which a docked panel
    // follows the reader to.
    final key = ValueKey((tab, widget.bookIndex, first, last));
    return switch (tab) {
      ChapterContextTab.crossReferences => KeyedSubtree(
        key: key,
        child: widget.crossReferencesBuilder!(context, first, last),
      ),
      ChapterContextTab.structure => ChapterOutlinesSheet(
        key: key,
        bookIndex: widget.bookIndex,
        chapter: first,
        lastChapter: last,
        useEnglishBookNames: widget.useEnglishBookNames,
        onNavigateToPassage: widget.onNavigateToPassage,
      ),
      ChapterContextTab.places => ChapterPlacesSheet(
        bookIndex: widget.bookIndex,
        key: key,
        chapter: first,
        lastChapter: last,
        useEnglishBookNames: widget.useEnglishBookNames,
        ntSyriac: widget.ntSyriac,
        ntGreek: widget.ntGreek,
        onNtGreekChanged: widget.onNtGreekChanged,
        bookmarks: widget.bookmarks,
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendPlacesRequest,
        showTitle: false,
      ),
      ChapterContextTab.people => ChapterPeopleSheet(
        bookIndex: widget.bookIndex,
        key: key,
        chapter: first,
        lastChapter: last,
        useEnglishBookNames: widget.useEnglishBookNames,
        ntSyriac: widget.ntSyriac,
        ntGreek: widget.ntGreek,
        onNtGreekChanged: widget.onNtGreekChanged,
        bookmarks: widget.bookmarks,
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendPeopleRequest,
        showTitle: false,
      ),
      ChapterContextTab.archaeology => ChapterArtifactsSheet(
        bookIndex: widget.bookIndex,
        key: key,
        chapter: first,
        lastChapter: last,
        useEnglishBookNames: widget.useEnglishBookNames,
        ntSyriac: widget.ntSyriac,
        ntGreek: widget.ntGreek,
        onNtGreekChanged: widget.onNtGreekChanged,
        bookmarks: widget.bookmarks,
        onNavigateToPassage: widget.onNavigateToPassage,
        sendRequest: widget.sendArtifactsRequest,
        showTitle: false,
      ),
      ChapterContextTab.apologetics => ChapterApologeticsSheet(
        key: key,
        bookIndex: widget.bookIndex,
        chapter: first,
        lastChapter: last,
        useEnglishBookNames: widget.useEnglishBookNames,
        onNavigateToPassage: widget.onNavigateToPassage,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (first, last) = _span(_scope);
    final title = chapterSpanName(
      widget.bookIndex,
      first,
      last,
      useEnglish: widget.useEnglishBookNames,
    );
    final scopes = _scopes;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scope = scopes.length > 1
                  ? SegmentedButton<ChapterContextScope>(
                      key: const ValueKey('chapter-context-scope'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      segments: [
                        for (final scope in scopes)
                          ButtonSegment(
                            value: scope,
                            label: Text(scope.label),
                            tooltip: chapterSpanName(
                              widget.bookIndex,
                              _span(scope).$1,
                              _span(scope).$2,
                              useEnglish: widget.useEnglishBookNames,
                            ),
                          ),
                      ],
                      selected: {
                        scopes.firstWhere((s) => _span(s) == _span(_scope)),
                      },
                      onSelectionChanged: (picked) => _setScope(picked.single),
                    )
                  : null;
              // Docked in a narrow side panel, the scope goes under the
              // title.
              final narrow = constraints.maxWidth < 480;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        if (scope != null && !narrow) scope,
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close),
                          onPressed:
                              widget.onClose ??
                              () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                    if (scope != null && narrow)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: scope,
                      ),
                  ],
                ),
              );
            },
          ),
          _tabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              // A swipe would fight the map's own panning.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final tab in _shown) _KeepAlive(child: _tab(tab)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The tabs as icons sharing the width, named by their tooltips: there are
  /// too many for their labels to fit a side panel.
  ///
  /// Not a [TabBar]: it moves its tabs to new parents as the selection
  /// changes, and a tooltip's overlay cannot be moved while the reader lays
  /// out its panels, so a [TabBar] of tooltips crashes there. Plain buttons
  /// on the same controller are never moved.
  Widget _tabBar() {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _tabs,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            for (final (i, tab) in _shown.indexed)
              Expanded(child: _tabButton(tab, selected: i == _tabs.index)),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(ChapterContextTab tab, {required bool selected}) {
    final scheme = Theme.of(context).colorScheme;
    // Greyed out, but still there to open: the tabs keep their places as
    // the reader moves from chapter to chapter.
    final empty = _empty(tab);
    final name = empty ? '${tab.label}: none here' : tab.label;
    final color = empty
        ? scheme.onSurface.withValues(alpha: 0.3)
        : selected
        ? scheme.primary
        : scheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: selected ? scheme.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Semantics(
        selected: selected,
        child: IconButton(
          key: ValueKey('chapter-context-${tab.name}'),
          tooltip: name,
          icon: Icon(tab.icon, color: color),
          onPressed: () => _tabs.animateTo(_shown.indexOf(tab)),
        ),
      ),
    );
  }
}

/// Keeps a tab's reply from Rust while another tab is shown, so switching
/// back does not ask for it again.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
