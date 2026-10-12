import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'archaeology_page.dart';
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

/// What surrounds a chapter, one tab each: the places it names on a map, the
/// people it names and how they are related, and the finds bearing on it.
class ChapterContextSheet extends StatefulWidget {
  const ChapterContextSheet({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.initialTab = ChapterContextTab.places,
    this.onTabChanged,
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

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    widget.onTabChanged?.call(ChapterContextTab.values[_tabs.index]);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _tab(ChapterContextTab tab) => switch (tab) {
    ChapterContextTab.places => ChapterPlacesSheet(
      bookIndex: widget.bookIndex,
      chapter: widget.chapter,
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
      chapter: widget.chapter,
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
      chapter: widget.chapter,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        '${bookDisplayName(widget.bookIndex, useEnglish: widget.useEnglishBookNames)} '
        '${widget.chapter}';
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
