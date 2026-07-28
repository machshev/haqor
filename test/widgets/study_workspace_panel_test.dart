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
                onWordColorChanged: (_) {},
                onPassageColorChanged: (_) {},
                onCreateTheme: () {},
                onEditTheme: (_) {},
                onDeleteTheme: (_) {},
                onAddCurrentToTheme: (_) {},
                onOpenPassage: (_) {},
                onEditPassage: (_, _) {},
                onTogglePassage: (_, _) {},
                onRemovePassage: (_, _) {},
                onEditWord: (_) {},
                onToggleWord: (_) {},
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

  testWidgets('panel shows root notes and themed passages with quick add', (
    tester,
  ) async {
    const passage = StudyPassage(
      bookIndex: 0,
      chapter: 1,
      verse: 1,
      note: 'Creation begins',
    );
    const studyTheme = StudyTheme(
      id: 'creation',
      name: 'Creation',
      headerNote: 'Trace creation language.',
      passages: [passage],
    );
    const workspace = StudyWorkspace(
      id: 'study',
      name: 'Study',
      words: [StudyWord(root: 'ברא', surface: 'בָּרָא', note: 'Create')],
      themes: [studyTheme],
    );
    StudyTheme? addedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 720,
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
              onWordColorChanged: (_) {},
              onPassageColorChanged: (_) {},
              onCreateTheme: () {},
              onEditTheme: (_) {},
              onDeleteTheme: (_) {},
              onAddCurrentToTheme: (value) => addedTo = value,
              onOpenPassage: (_) {},
              onEditPassage: (_, _) {},
              onTogglePassage: (_, _) {},
              onRemovePassage: (_, _) {},
              onEditWord: (_) {},
              onToggleWord: (_) {},
              onRemoveWord: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('ברא · בָּרָא'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Trace creation language.'), findsOneWidget);
    expect(find.text('Genesis 1:1'), findsOneWidget);
    expect(find.text('Creation begins'), findsOneWidget);

    await tester.tap(find.text('Add current passage'));
    expect(addedTo?.id, 'creation');
  });
}
