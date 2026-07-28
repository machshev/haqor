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
    const group = StudyGroup(
      id: 'creation',
      name: 'Creation',
      note: 'Trace creation language.',
    );
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
    );
    String? bookmarkedIn = 'unset';
    StudyWord? updatedWord;
    bool? highlightsEnabled;

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
            ),
          ),
        ),
      ),
    );

    expect(find.text('Study notes'), findsOneWidget);
    expect(find.text('ברא · בָּרָא'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Trace creation language.'), findsOneWidget);
    expect(find.text('Genesis 1:1'), findsOneWidget);
    expect(find.text('Creation begins'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    expect(highlightsEnabled, isFalse);

    await tester.tap(find.text('Bookmark current'));
    expect(bookmarkedIn, isNull);

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
