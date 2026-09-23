import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/study_workspace_panel.dart';

void main() {
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
              onRemoveWord: (_) {},
              onOpenWord: (word) => openedWord = word,
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
    await tester.tap(find.text('Bookmark current passage'));
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

    expect(updatedWord?.groupId, 'creation');
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
