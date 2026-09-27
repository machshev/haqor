import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/study_section_editor.dart';

List<VerseEntry> _chapter(int count) => [
  for (var v = 1; v <= count; v++)
    VerseEntry(
      verse: v,
      text: 'אב גד',
      glosses: const [],
      morphologies: const [],
      roots: const [],
      names: const [],
      ketivs: const [],
      crossReferenceScores: const [],
    ),
];

Future<void> _open(
  WidgetTester tester, {
  required StudySection initial,
  StudySection? summary,
  String? Function(StudySection)? validate,
  required ValueChanged<StudySection?> saved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved(
              await showDialog<StudySection>(
                context: context,
                builder: (_) => StudySectionEditor(
                  initial: initial,
                  creating: true,
                  useEnglishBookNames: true,
                  loadChapter: (_, _) async => _chapter(10),
                  validate: validate ?? (_) => null,
                  summary: summary,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a summary needs a title and passes the validator', (
    tester,
  ) async {
    StudySection? result;
    var problem = 'Its headings must stay within the passage.';
    await _open(
      tester,
      initial: const StudySection(
        id: 'sum',
        title: '',
        chapter: 1,
        verse: 1,
        bookIndex: 0,
        wholeChapter: true,
      ),
      validate: (_) => problem.isEmpty ? null : problem,
      saved: (s) => result = s,
    );
    expect(find.text('New passage summary'), findsOneWidget);
    expect(find.text('Genesis 1'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Give the section a title.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('section-title')), 'Day');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text(problem), findsOneWidget);

    problem = '';
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result?.title, 'Day');
    expect(result?.range?.reference, '1');
  });

  testWidgets('a heading chooses only verses within its summary', (
    tester,
  ) async {
    StudySection? result;
    await _open(
      tester,
      initial: const StudySection(
        id: 'h',
        title: 'Light',
        chapter: 1,
        verse: 3,
        parentId: 'sum',
      ),
      summary: const StudySection(
        id: 'sum',
        title: 'Creation',
        chapter: 1,
        verse: 3,
        bookIndex: 0,
        endVerse: 5,
      ),
      saved: (s) => result = s,
    );
    expect(find.text('New section heading'), findsOneWidget);
    expect(find.text('From Genesis 1:3'), findsOneWidget);
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    // Verses 3–5 of the summary's one chapter, the choice shown twice.
    expect(find.text('2'), findsNothing);
    expect(find.text('6'), findsNothing);
    await tester.tap(find.text('5').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(result?.start, (chapter: 1, verse: 5));
    expect(result?.isSummary, isFalse);
    expect(result?.parentId, 'sum');
  });
}
