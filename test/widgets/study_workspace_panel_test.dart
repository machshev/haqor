import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/study_workspace_panel.dart';

void main() {
  linkTileTests();
  sectionTileTests();

  testWidgets('word menu switches type and explains unavailable conversions', (
    tester,
  ) async {
    const root = StudyWord(root: 'ברא', surface: 'בָּרָא', note: 'Creation');
    var workspace = const StudyWorkspace(id: 's', name: 'Study', words: [root]);
    late StateSetter rebuild;
    var switches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 760,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return StudyWorkspacePanel(
                  workspaces: [workspace],
                  activeWorkspace: workspace,
                  currentPassage: const StudyPassage(
                    bookIndex: 0,
                    chapter: 1,
                    verse: 1,
                  ),
                  useEnglishBookNames: true,
                  onCreate: () {},
                  onSelect: (_) {},
                  onRename: () {},
                  onDelete: () {},
                  onToggleHighlights: (_) {},
                  onCreateGroup: (_) {},
                  onEditGroup: (_) {},
                  onDeleteGroup: (_) {},
                  onBookmarkCurrent: (_) {},
                  onOpenPassage: (_) {},
                  onEditPassage: (_) {},
                  onUpdatePassage: (_) {},
                  onRemovePassage: (_) {},
                  onEditWord: (_) {},
                  onUpdateWord: (_) {},
                  onRemoveWord: (_) {},
                  onOpenWord: (_) {},
                  onCreateNote: (_) {},
                  onEditNote: (_) {},
                  onUpdateNote: (_) {},
                  onRemoveNote: (_) {},
                  onMoveItem: (_, _, _) {},
                  onSwitchWordKind: (word) => setState(() {
                    workspace = workspace.switchWordKind(word);
                    switches++;
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
    for (final kind in [StudyWordKind.form, StudyWordKind.root]) {
      await tester.tap(find.byTooltip('Word options'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          kind == StudyWordKind.form ? 'Highlight root' : 'Highlight form',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Switch to ${kind.name} bookmark'));
      await tester.pumpAndSettle();
      expect(workspace.words.single.kind, kind);
      expect(find.text('Creation'), findsOneWidget);
      expect(
        find.byTooltip(
          kind == StudyWordKind.form ? 'Form bookmark' : 'Root bookmark',
        ),
        findsOneWidget,
      );
    }
    expect(switches, 2);

    for (final unresolved in [false, true]) {
      rebuild(() {
        workspace = workspace.copyWith(
          words: unresolved
              ? [
                  const StudyWord(
                    root: '',
                    surface: 'בָּרָא',
                    kind: StudyWordKind.form,
                  ),
                ]
              : [root, root.copyWith(kind: StudyWordKind.form)],
        );
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Word options').first);
      await tester.pumpAndSettle();
      final label = unresolved
          ? 'Switch to root bookmark'
          : 'Switch to form bookmark';
      final item = tester.widget<PopupMenuItem>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            )
            .first,
      );
      expect(item.enabled, isFalse);
      expect(
        find.text(unresolved ? 'Root not resolved' : 'Already bookmarked'),
        findsOneWidget,
      );
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(switches, 2);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty workspace state scrolls at constrained heights', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 220,
              child: StudyWorkspacePanel(
                workspaces: const [],
                activeWorkspace: null,
                currentPassage: const StudyPassage(
                  bookIndex: 0,
                  chapter: 1,
                  verse: 1,
                ),
                useEnglishBookNames: false,
                onCreate: () {},
                onSelect: (_) {},
                onRename: () {},
                onDelete: () {},
                onToggleHighlights: (_) {},
                onCreateGroup: (_) {},
                onEditGroup: (_) {},
                onDeleteGroup: (_) {},
                onBookmarkCurrent: (_) {},
                onOpenPassage: (_) {},
                onEditPassage: (_) {},
                onUpdatePassage: (_) {},
                onRemovePassage: (_) {},
                onEditWord: (_) {},
                onUpdateWord: (_) {},
                onSwitchWordKind: (_) {},
                onRemoveWord: (_) {},
                onOpenWord: (_) {},
                onCreateNote: (_) {},
                onEditNote: (_) {},
                onUpdateNote: (_) {},
                onRemoveNote: (_) {},
                onMoveItem: (_, _, _) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Create workspace'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('outline shows unfiled and grouped items and can move a word', (
    tester,
  ) async {
    const group = StudyGroup(id: 'creation', name: 'Creation');
    const workspace = StudyWorkspace(
      id: 'study',
      name: 'Study',
      groups: [group],
      passages: [
        StudyPassage(
          bookIndex: 0,
          chapter: 1,
          verse: 1,
          groupId: 'creation',
          note: 'Creation begins',
        ),
      ],
      words: [StudyWord(root: 'ברא', surface: 'בָּרָא', note: 'Create')],
      notes: [
        StudyNote(
          id: 'creation-note',
          text: 'Trace creation language.',
          groupId: 'creation',
        ),
      ],
    );
    String? bookmarkedIn = 'unset';
    StudyWord? updatedWord;
    StudyWord? openedWord;
    (String, String?, int?)? moved;
    bool? highlightsEnabled;
    var createdWorkspace = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 760,
            child: StudyWorkspacePanel(
              workspaces: const [workspace],
              activeWorkspace: workspace,
              currentPassage: const StudyPassage(
                bookIndex: 0,
                chapter: 1,
                verse: 2,
              ),
              useEnglishBookNames: true,
              onCreate: () => createdWorkspace = true,
              onSelect: (_) {},
              onRename: () {},
              onDelete: () {},
              onToggleHighlights: (enabled) => highlightsEnabled = enabled,
              onCreateGroup: (_) {},
              onEditGroup: (_) {},
              onDeleteGroup: (_) {},
              onBookmarkCurrent: (groupId) => bookmarkedIn = groupId,
              onOpenPassage: (_) {},
              onEditPassage: (_) {},
              onUpdatePassage: (_) {},
              onRemovePassage: (_) {},
              onEditWord: (_) {},
              onUpdateWord: (word) => updatedWord = word,
              onSwitchWordKind: (_) {},
              onRemoveWord: (_) {},
              onOpenWord: (word) => openedWord = word,
              onCreateNote: (_) {},
              onEditNote: (_) {},
              onUpdateNote: (_) {},
              onRemoveNote: (_) {},
              onMoveItem: (item, groupId, index) =>
                  moved = (item.key, groupId, index),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Study notes'), findsNothing);
    expect(find.text('ברא · בָּרָא'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Trace creation language.'), findsOneWidget);
    expect(find.text('Genesis 1:1'), findsOneWidget);
    expect(find.text('Creation begins'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.byIcon(Icons.park_outlined), findsOneWidget);
    expect(find.byTooltip('Root bookmark'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));
    expect(find.byType(Switch), findsNothing);
    expect(find.byIcon(Icons.highlight), findsNothing);
    expect(find.byIcon(Icons.folder_outlined), findsNothing);

    for (var cycle = 0; cycle < 2; cycle++) {
      await tester.tap(find.text('Creation'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Trace creation language.'), findsNothing);
      expect(find.text('Genesis 1:1'), findsNothing);
      expect(find.text('ברא · בָּרָא'), findsOneWidget);

      await tester.tap(find.text('Creation'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Trace creation language.'), findsOneWidget);
      expect(find.text('Genesis 1:1'), findsOneWidget);
    }

    await tester.tap(find.text('ברא · בָּרָא'));
    expect(openedWord?.root, 'ברא');

    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
    expect(find.text('New workspace'), findsOneWidget);
    expect(find.text('Show study highlights'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem),
    );
    await tester.pumpAndSettle();
    expect(highlightsEnabled, isFalse);

    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New workspace'));
    await tester.pumpAndSettle();
    expect(createdWorkspace, isTrue);

    await tester.tap(find.byTooltip('Add study item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bookmark passage'));
    await tester.pumpAndSettle();
    expect(bookmarkedIn, isNull);

    await tester.tap(find.byTooltip('Word options'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem),
    );
    await tester.pumpAndSettle();
    expect(updatedWord?.highlightEnabled, isFalse);

    await tester.tap(find.byTooltip('Word options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to group'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text('Creation'),
      ),
    );
    await tester.pumpAndSettle();

    // The move goes through the workspace's own move, not a rewrite of the
    // item as the menu saw it.
    expect(moved, ('word-root-ברא', 'creation', null));
    expect(updatedWord?.groupId, isNull);
  });
  testWidgets(
    'dragging reorders groups and moves items through nested groups',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 744);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var workspace = const StudyWorkspace(id: 'drag-study', name: 'Drag study')
          .putNote(const StudyNote(id: 'note', text: 'Opening note'))
          .putGroup(const StudyGroup(id: 'a', name: 'First group'))
          .putGroup(const StudyGroup(id: 'b', name: 'Second group'))
          .putGroup(
            const StudyGroup(id: 'nested', name: 'Nested group', parentId: 'a'),
          );
      var moves = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 380,
                child: StatefulBuilder(
                  builder: (context, setState) => StudyWorkspacePanel(
                    workspaces: [workspace],
                    activeWorkspace: workspace,
                    currentPassage: const StudyPassage(
                      bookIndex: 0,
                      chapter: 1,
                      verse: 1,
                    ),
                    useEnglishBookNames: true,
                    onCreate: () {},
                    onSelect: (_) {},
                    onRename: () {},
                    onDelete: () {},
                    onToggleHighlights: (_) {},
                    onCreateGroup: (_) {},
                    onEditGroup: (_) {},
                    onDeleteGroup: (_) {},
                    onBookmarkCurrent: (_) {},
                    onOpenPassage: (_) {},
                    onEditPassage: (_) {},
                    onUpdatePassage: (_) {},
                    onRemovePassage: (_) {},
                    onEditWord: (_) {},
                    onUpdateWord: (_) {},
                    onSwitchWordKind: (_) {},
                    onRemoveWord: (_) {},
                    onOpenWord: (_) {},
                    onCreateNote: (_) {},
                    onEditNote: (_) {},
                    onUpdateNote: (_) {},
                    onRemoveNote: (_) {},
                    onMoveItem: (item, groupId, index) => setState(() {
                      workspace = workspace.moveItem(
                        item,
                        groupId,
                        index: index,
                      );
                      moves++;
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> drag(String item, String target) async {
        final source = find.byKey(ValueKey('drag-$item'));
        final destination = find.byKey(ValueKey('drop-$target'));
        final gesture = await tester.startGesture(tester.getCenter(source));
        await gesture.moveBy(const Offset(-20, 0));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(destination));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      Future<void> dragGroupOntoHandle(String sourceId, String targetId) async {
        final source = find.byKey(ValueKey('drag-group-$sourceId'));
        final target = find.byKey(ValueKey('drag-group-$targetId'));
        final gesture = await tester.startGesture(
          tester.getCenter(source),
          kind: PointerDeviceKind.mouse,
        );
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
        await gesture.moveTo(tester.getCenter(target));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      // A normal vertical mouse drag lands on another row, not a narrow gap.
      await dragGroupOntoHandle('b', 'a');
      expect(workspace.itemsIn(null).map((item) => item.key), [
        'note-note',
        'group-b',
        'group-a',
      ]);
      await dragGroupOntoHandle('b', 'a');
      expect(workspace.itemsIn(null).map((item) => item.key), [
        'note-note',
        'group-a',
        'group-b',
      ]);

      // Groups can move above and below ordinary items.
      await drag('group-b', 'top-0');
      expect(workspace.itemsIn(null).map((item) => item.key), [
        'group-b',
        'note-note',
        'group-a',
      ]);
      await drag('group-b', 'top-3');
      expect(workspace.itemsIn(null).map((item) => item.key), [
        'note-note',
        'group-a',
        'group-b',
      ]);

      // A collapsed group remains a drop destination and reopens normally.
      await tester.tap(find.text('First group'));
      await tester.pumpAndSettle();
      await drag('note-note', 'a-inside');
      expect(workspace.notes.single.groupId, 'a');
      expect(find.text('Opening note'), findsNothing);
      await tester.tap(find.text('First group'));
      await tester.pumpAndSettle();
      expect(find.text('Opening note'), findsOneWidget);
      await drag('note-note', 'nested-inside');
      expect(workspace.notes.single.groupId, 'nested');
      await drag('note-note', 'top-inside');
      expect(workspace.notes.single.groupId, isNull);

      // Invalid descendant drops leave the outline intact.
      final previousMoves = moves;
      await drag('group-a', 'nested-inside');
      expect(moves, previousMoves);
      expect(workspace.groupById('a')!.parentId, isNull);
      await drag('group-b', 'nested-inside');
      expect(workspace.groupById('b')!.parentId, 'nested');
      await drag('group-b', 'top-inside');
      expect(workspace.groupById('b')!.parentId, isNull);
    },
  );
  testWidgets('dragging near the edge scrolls to an offscreen group', (
    tester,
  ) async {
    final workspace = StudyWorkspace(
      id: 'long',
      name: 'Long outline',
      notes: [
        for (var i = 0; i < 25; i++)
          StudyNote(id: '$i', text: 'Note $i', order: i),
      ],
      groups: const [StudyGroup(id: 'last', name: 'Last group', order: 25)],
    );
    String? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 440,
            child: StudyWorkspacePanel(
              workspaces: [workspace],
              activeWorkspace: workspace,
              currentPassage: const StudyPassage(
                bookIndex: 0,
                chapter: 1,
                verse: 1,
              ),
              useEnglishBookNames: true,
              onCreate: () {},
              onSelect: (_) {},
              onRename: () {},
              onDelete: () {},
              onToggleHighlights: (_) {},
              onCreateGroup: (_) {},
              onEditGroup: (_) {},
              onDeleteGroup: (_) {},
              onBookmarkCurrent: (_) {},
              onOpenPassage: (_) {},
              onEditPassage: (_) {},
              onUpdatePassage: (_) {},
              onRemovePassage: (_) {},
              onEditWord: (_) {},
              onUpdateWord: (_) {},
              onSwitchWordKind: (_) {},
              onRemoveWord: (_) {},
              onOpenWord: (_) {},
              onCreateNote: (_) {},
              onEditNote: (_) {},
              onUpdateNote: (_) {},
              onRemoveNote: (_) {},
              onMoveItem: (item, groupId, index) => destination = groupId,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('drag-note-0'))),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    final viewport = tester.getRect(find.byType(ListView));
    await gesture.moveTo(Offset(viewport.center.dx, viewport.bottom - 2));
    for (
      var i = 0;
      i < 120 &&
          scrollable.position.pixels < scrollable.position.maxScrollExtent;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(scrollable.position.pixels, greaterThan(0));
    final target = find.byKey(const ValueKey('drop-last-inside'));
    expect(target.hitTestable(), findsOneWidget);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(destination, 'last');
    expect(tester.takeException(), isNull);
  });
}

void linkTileTests() {
  testWidgets('a bookmarked link opens either verse and can be removed', (
    tester,
  ) async {
    const link = StudyLink(
      earlier: (bookIndex: 11, chapter: 7, verse: 14),
      later: (bookIndex: 39, chapter: 1, verse: 23),
      score: 14.69,
      note: 'Emmanuel',
    );
    const workspace = StudyWorkspace(id: 's', name: 'Study', links: [link]);
    final opened = <StudyLinkVerse>[];
    final shown = <StudyLink>[];
    final removed = <StudyLink>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyWorkspacePanel(
            workspaces: const [workspace],
            activeWorkspace: workspace,
            currentPassage: const StudyPassage(
              bookIndex: 0,
              chapter: 1,
              verse: 1,
            ),
            useEnglishBookNames: true,
            onCreate: () {},
            onSelect: (_) {},
            onRename: () {},
            onDelete: () {},
            onToggleHighlights: (_) {},
            onCreateGroup: (_) {},
            onEditGroup: (_) {},
            onDeleteGroup: (_) {},
            onBookmarkCurrent: (_) {},
            onOpenPassage: (_) {},
            onEditPassage: (_) {},
            onUpdatePassage: (_) {},
            onRemovePassage: (_) {},
            onEditWord: (_) {},
            onUpdateWord: (_) {},
            onSwitchWordKind: (_) {},
            onRemoveWord: (_) {},
            onOpenWord: (_) {},
            onCreateNote: (_) {},
            onEditNote: (_) {},
            onUpdateNote: (_) {},
            onRemoveNote: (_) {},
            onMoveItem: (_, _, _) {},
            onOpenLinkVerse: (_, verse) => opened.add(verse),
            onShowLink: shown.add,
            onRemoveLink: removed.add,
          ),
        ),
      ),
    );

    expect(find.text('Strong match'), findsOneWidget);
    expect(find.text('Emmanuel', findRichText: true), findsOneWidget);
    expect(find.textContaining('Bookmark a passage or word'), findsNothing);
    await tester.tap(find.text('Isaiah 7:14'));
    await tester.tap(find.text('Matthew 1:23'));
    expect(opened, [link.earlier, link.later]);

    await tester.tap(find.byTooltip('Link options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show cross references'));
    await tester.pumpAndSettle();
    expect(shown, [link]);

    await tester.tap(find.byTooltip('Link options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(removed, [link]);
  });
}

void sectionTileTests() {
  testWidgets('a summary shows its headings, opens them and toggles them in '
      'the reader', (tester) async {
    const workspace = StudyWorkspace(
      id: 'study',
      name: 'Study',
      sections: [
        StudySection(
          id: 'sum',
          title: 'Creation',
          chapter: 1,
          verse: 1,
          bookIndex: 0,
          endChapter: 2,
          endVerse: 3,
          note: 'Six days',
        ),
        StudySection(
          id: 'light',
          title: 'Light',
          chapter: 1,
          verse: 3,
          parentId: 'sum',
        ),
        StudySection(
          id: 'land',
          title: 'Land',
          chapter: 1,
          verse: 9,
          parentId: 'sum',
        ),
      ],
      notes: [StudyNote(id: 'n', text: 'Before the days', groupId: 'sum')],
    );
    final created = <String?>[];
    StudySection? updated, opened, edited, deleted;
    bool? headingsEnabled;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 760,
            child: StudyWorkspacePanel(
              workspaces: const [workspace],
              activeWorkspace: workspace,
              currentPassage: const StudyPassage(
                bookIndex: 0,
                chapter: 1,
                verse: 2,
              ),
              useEnglishBookNames: true,
              onCreate: () {},
              onSelect: (_) {},
              onRename: () {},
              onDelete: () {},
              onToggleHighlights: (_) {},
              onCreateGroup: (_) {},
              onEditGroup: (_) {},
              onDeleteGroup: (_) {},
              onBookmarkCurrent: (_) {},
              onOpenPassage: (_) {},
              onEditPassage: (_) {},
              onUpdatePassage: (_) {},
              onRemovePassage: (_) {},
              onEditWord: (_) {},
              onUpdateWord: (_) {},
              onSwitchWordKind: (_) {},
              onRemoveWord: (_) {},
              onOpenWord: (_) {},
              onCreateNote: (_) {},
              onEditNote: (_) {},
              onUpdateNote: (_) {},
              onRemoveNote: (_) {},
              onMoveItem: (_, _, _) {},
              onToggleHeadings: (enabled) => headingsEnabled = enabled,
              onCreateSection: created.add,
              onEditSection: (s) => edited = s,
              onUpdateSection: (s) => updated = s,
              onDeleteSection: (s) => deleted = s,
              onOpenSection: (s) => opened = s,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Genesis 1:1–2:3'), findsOneWidget);
    expect(find.text('Six days'), findsOneWidget);
    expect(find.text('Genesis 1:3–8'), findsOneWidget);
    expect(find.text('Genesis 1:9–2:3'), findsOneWidget);
    // The summary's own note comes before its headings.
    final y = tester.getTopLeft;
    expect(
      y(find.text('Before the days')).dy,
      lessThan(y(find.text('Light')).dy),
    );
    expect(y(find.text('Light')).dy, lessThan(y(find.text('Land')).dy));

    await tester.tap(find.text('Genesis 1:9–2:3'));
    expect(opened?.id, 'land');

    await tester.tap(find.byTooltip('Summary options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show headings in reader'));
    await tester.pumpAndSettle();
    expect(updated?.id, 'sum');
    expect(updated?.showInReader, isFalse);

    await tester.tap(find.byTooltip('Summary options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add section heading'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Heading options').first);
    await tester.pumpAndSettle();
    expect(find.text('Show headings in reader'), findsNothing);
    await tester.tap(find.text('Edit heading'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Heading options').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete heading'));
    await tester.pumpAndSettle();
    expect(edited?.id, 'light');
    expect(deleted?.id, 'land');

    await tester.tap(find.byTooltip('Add study item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New passage summary'));
    await tester.pumpAndSettle();
    expect(created, ['sum', null]);

    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show study headings'));
    await tester.pumpAndSettle();
    expect(headingsEnabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the indent band under the pointer picks the level', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 744);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var workspace = const StudyWorkspace(id: 'indent', name: 'Indent study')
        .putGroup(const StudyGroup(id: 'a', name: 'First group'))
        .putGroup(const StudyGroup(id: 'inner', name: 'Inner', parentId: 'a'))
        .putNote(const StudyNote(id: 'loose', text: 'Loose note'));
    workspace = workspace.moveItem(
      workspace.itemsIn(null).firstWhere((item) => item.key == 'note-loose'),
      null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 380,
              child: StatefulBuilder(
                builder: (context, setState) => StudyWorkspacePanel(
                  workspaces: [workspace],
                  activeWorkspace: workspace,
                  currentPassage: const StudyPassage(
                    bookIndex: 0,
                    chapter: 1,
                    verse: 1,
                  ),
                  useEnglishBookNames: true,
                  onCreate: () {},
                  onSelect: (_) {},
                  onRename: () {},
                  onDelete: () {},
                  onToggleHighlights: (_) {},
                  onCreateGroup: (_) {},
                  onEditGroup: (_) {},
                  onDeleteGroup: (_) {},
                  onBookmarkCurrent: (_) {},
                  onOpenPassage: (_) {},
                  onEditPassage: (_) {},
                  onUpdatePassage: (_) {},
                  onRemovePassage: (_) {},
                  onEditWord: (_) {},
                  onUpdateWord: (_) {},
                  onSwitchWordKind: (_) {},
                  onRemoveWord: (_) {},
                  onOpenWord: (_) {},
                  onCreateNote: (_) {},
                  onEditNote: (_) {},
                  onUpdateNote: (_) {},
                  onRemoveNote: (_) {},
                  onMoveItem: (item, groupId, index) => setState(() {
                    workspace = workspace.moveItem(item, groupId, index: index);
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'group-a',
      'note-loose',
    ]);

    // The middle of level [depth]'s band in the indent area.
    double band(int depth) =>
        tester.getRect(find.byType(ListView)).left + 8 + depth * 28 + 14;

    // Picks [item] up by its handle, moves left to [depth]'s band on its own
    // row, and drops it there.
    Future<void> moveTo(String item, int depth, {String? expectLabel}) async {
      final handle = tester.getCenter(find.byKey(ValueKey('drag-$item')));
      final gesture = await tester.startGesture(
        handle,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveTo(Offset(band(depth), handle.dy));
      await tester.pump();
      if (expectLabel != null) {
        expect(find.text('→ $expectLabel'), findsOneWidget);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // Deeper bands, though left of the handle, nest the note in the group
    // above, then in that group's last group.
    await moveTo('note-loose', 1, expectLabel: 'In First group');
    expect(workspace.itemsIn('a').map((item) => item.key), [
      'group-inner',
      'note-loose',
    ]);
    await moveTo('note-loose', 2, expectLabel: 'In Inner');
    expect(workspace.itemsIn('inner').map((item) => item.key), ['note-loose']);

    // Shallower bands place it just after each enclosing group.
    await moveTo('note-loose', 1, expectLabel: 'In First group');
    expect(workspace.itemsIn('a').map((item) => item.key), [
      'group-inner',
      'note-loose',
    ]);
    await moveTo('note-loose', 0, expectLabel: 'Top level');
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'group-a',
      'note-loose',
    ]);

    // Dragging away from the indent area keeps the level, and on its own
    // row changes nothing, however far the pointer wanders.
    final loose = tester.getCenter(
      find.byKey(const ValueKey('drag-note-loose')),
    );
    var gesture = await tester.startGesture(
      loose,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'group-a',
      'note-loose',
    ]);

    // Over a gap the band picks the level too: after the group's last item,
    // the top band lands at the top level.
    final inner = tester.getCenter(
      find.byKey(const ValueKey('drag-group-inner')),
    );
    gesture = await tester.startGesture(inner, kind: PointerDeviceKind.mouse);
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump();
    final gap = tester.getCenter(find.byKey(const ValueKey('drop-a-1')));
    await gesture.moveTo(Offset(band(0), gap.dy));
    await tester.pump();
    expect(find.text('Top level'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'group-a',
      'group-inner',
      'note-loose',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapse all and expand all set every group at once', (
    tester,
  ) async {
    final workspace = const StudyWorkspace(id: 'fold', name: 'Fold study')
        .putGroup(const StudyGroup(id: 'a', name: 'First group'))
        .putGroup(const StudyGroup(id: 'inner', name: 'Inner', parentId: 'a'))
        .putNote(
          const StudyNote(id: 'deep', text: 'Deep note', groupId: 'inner'),
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            height: 760,
            child: StudyWorkspacePanel(
              workspaces: [workspace],
              activeWorkspace: workspace,
              currentPassage: const StudyPassage(
                bookIndex: 0,
                chapter: 1,
                verse: 1,
              ),
              useEnglishBookNames: true,
              onCreate: () {},
              onSelect: (_) {},
              onRename: () {},
              onDelete: () {},
              onToggleHighlights: (_) {},
              onCreateGroup: (_) {},
              onEditGroup: (_) {},
              onDeleteGroup: (_) {},
              onBookmarkCurrent: (_) {},
              onOpenPassage: (_) {},
              onEditPassage: (_) {},
              onUpdatePassage: (_) {},
              onRemovePassage: (_) {},
              onEditWord: (_) {},
              onUpdateWord: (_) {},
              onSwitchWordKind: (_) {},
              onRemoveWord: (_) {},
              onOpenWord: (_) {},
              onCreateNote: (_) {},
              onEditNote: (_) {},
              onUpdateNote: (_) {},
              onRemoveNote: (_) {},
              onMoveItem: (_, _, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inner'), findsOneWidget);
    expect(find.text('Deep note'), findsOneWidget);

    await tester.tap(find.byTooltip('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('First group'), findsOneWidget);
    expect(find.text('Inner'), findsNothing);
    expect(find.text('Deep note'), findsNothing);

    // Opening one group by hand leaves the ones inside it collapsed.
    await tester.tap(find.text('First group'));
    await tester.pumpAndSettle();
    expect(find.text('Inner'), findsOneWidget);
    expect(find.text('Deep note'), findsNothing);

    await tester.tap(find.byTooltip('Expand all'));
    await tester.pumpAndSettle();
    expect(find.text('Inner'), findsOneWidget);
    expect(find.text('Deep note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
