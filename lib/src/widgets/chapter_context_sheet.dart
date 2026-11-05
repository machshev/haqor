import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
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
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    widget.onTabChanged?.call(_shown[_tabs.index]);
  }

  @override
  void dispose() {
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
          LayoutBuilder(
            builder: (context, constraints) => _tabBar(
              // Docked in a narrow side panel the labels would be squeezed.
              scrollable: constraints.maxWidth < 440,
            ),
          ),
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

  Widget _tabBar({required bool scrollable}) => TabBar(
    controller: _tabs,
    isScrollable: scrollable,
    tabAlignment: scrollable ? TabAlignment.start : null,
    tabs: [
      for (final tab in _shown)
        Tab(
          key: ValueKey('chapter-context-${tab.name}'),
          icon: Icon(tab.icon),
          text: tab.label,
        ),
    ],
  );
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
