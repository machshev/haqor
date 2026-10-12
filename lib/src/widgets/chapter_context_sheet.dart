import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'archaeology_page.dart';
import 'chapter_span.dart';
import 'name_details.dart';

/// The tabs of [ChapterContextSheet], in the order it shows them.
enum ChapterContextTab {
  places('Places', Icons.map_outlined),
  people('People', Icons.people_outline),
  archaeology('Archaeology', Icons.account_balance_outlined);

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

/// What surrounds a chapter, one tab each: the places it names on a map, the
/// people it names and how they are related, and the finds bearing on it.
class ChapterContextSheet extends StatefulWidget {
  const ChapterContextSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.initialTab = ChapterContextTab.places,
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

  @override
  State<ChapterContextSheet> createState() => _ChapterContextSheetState();
}

class _ChapterContextSheetState extends State<ChapterContextSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: ChapterContextTab.values.length,
    initialIndex: widget.initialTab.index,
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
    widget.onTabChanged?.call(ChapterContextTab.values[_tabs.index]);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _tab(ChapterContextTab tab) {
    final (first, last) = _span(_scope);
    // A new span is a new request.
    final key = ValueKey((tab, first, last));
    return switch (tab) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                if (scopes.length > 1)
                  SegmentedButton<ChapterContextScope>(
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
                  ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: [
              for (final tab in ChapterContextTab.values)
                Tab(
                  key: ValueKey('chapter-context-${tab.name}'),
                  icon: Icon(tab.icon),
                  text: tab.label,
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              // A swipe would fight the map's own panning.
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final tab in ChapterContextTab.values)
                  _KeepAlive(child: _tab(tab)),
              ],
            ),
          ),
        ],
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
