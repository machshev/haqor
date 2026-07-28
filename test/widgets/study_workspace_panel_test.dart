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
                onReorderItems: (_, _, _) {},
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
              onReorderItems: (_, _, _) {},
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
    expect(find.byIcon(Icons.translate_outlined), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(3));
    expect(find.byType(ReorderableListView), findsNWidgets(2));
    expect(find.byType(Switch), findsNothing);
    expect(find.byIcon(Icons.highlight), findsNothing);
    expect(find.byIcon(Icons.folder_outlined), findsNothing);

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
}
