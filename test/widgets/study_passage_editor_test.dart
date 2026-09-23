import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/study_passage_editor.dart';

const _verses = [
  VerseEntry(
    verse: 1,
    text: 'אב ׀ גד־ הו זח',
    glosses: [],
    morphologies: [],
    roots: [],
    names: [],
    ketivs: [],
  ),
  VerseEntry(
    verse: 2,
    text: 'טי כל מנ',
    glosses: [],
    morphologies: [],
    roots: [],
    names: [],
    ketivs: [],
  ),
];

Future<void> _choose(WidgetTester tester, String label, String choice) async {
  final field = find
      .ancestor(
        of: find.text(label).first,
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      )
      .first;
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
}

void main() {
  Future<void> open(
    WidgetTester tester, {
    StudyPassage initial = const StudyPassage(
      bookIndex: 0,
      chapter: 1,
      verse: 1,
    ),
    bool creating = true,
    bool duplicate = false,
    bool fails = false,
    required ValueChanged<StudyPassage?> saved,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved(
                await showDialog<StudyPassage>(
                  context: context,
                  builder: (_) => StudyPassageEditor(
                    initial: initial,
                    creating: creating,
                    useEnglishBookNames: true,
                    isDuplicate: (_) => duplicate,
                    loadChapter: (_, _) async {
                      if (fails) throw StateError('Unavailable');
                      return _verses;
                    },
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('creates a whole chapter and a verse range', (tester) async {
    StudyPassage? result;
    await open(tester, saved: (p) => result = p);
    await _choose(tester, 'Bookmark', 'Whole chapter');
    await tester.tap(find.widgetWithText(FilledButton, 'Bookmark'));
    await tester.pumpAndSettle();
    expect(result!.wholeChapter, true);
    expect(result!.reference, '1');
    await open(tester, saved: (p) => result = p);
    await _choose(tester, 'End verse', '2');
    await tester.tap(find.widgetWithText(FilledButton, 'Bookmark'));
    await tester.pumpAndSettle();
    expect(result!.reference, '1:1–2');
  });

  testWidgets(
    'selects consecutive words across verses and keeps annotations on edit',
    (tester) async {
      StudyPassage? result;
      await open(
        tester,
        creating: false,
        initial: const StudyPassage(
          bookIndex: 0,
          chapter: 1,
          verse: 1,
          note: 'Keep',
          groupId: 'g',
          order: 4,
          colorValue: 0xff123456,
          highlightEnabled: false,
        ),
        saved: (p) => result = p,
      );
      await _choose(tester, 'Bookmark', 'Phrase');
      expect(find.widgetWithText(ChoiceChip, '׀'), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'הו').first);
      await _choose(tester, 'End verse', '2');
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'כל'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'כל'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result!.startWord, 2);
      expect(result!.endWord, 1);
      expect(result!.lastVerse, 2);
      expect(result!.note, 'Keep');
      expect(result!.groupId, 'g');
      expect(result!.order, 4);
      expect(result!.colorValue, 0xff123456);
      expect(result!.highlightEnabled, false);
    },
  );

  testWidgets('rejects reversed phrases and duplicate references', (
    tester,
  ) async {
    StudyPassage? result;
    await open(tester, saved: (p) => result = p);
    await _choose(tester, 'Bookmark', 'Phrase');
    await tester.tap(find.widgetWithText(ChoiceChip, 'הו').first);
    await tester.tap(find.widgetWithText(FilledButton, 'Bookmark'));
    await tester.pumpAndSettle();
    expect(
      find.text('The end of the passage must be at or after the start.'),
      findsOneWidget,
    );
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(tester, duplicate: true, saved: (p) => result = p);
    await tester.tap(find.widgetWithText(FilledButton, 'Bookmark'));
    await tester.pumpAndSettle();
    expect(
      find.text('This reference is already bookmarked in this study.'),
      findsOneWidget,
    );
    expect(result, isNull);
  });

  testWidgets(
    'phrase editing fits a phone and cancellation keeps the original',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      StudyPassage? result;
      await open(
        tester,
        creating: false,
        initial: const StudyPassage(
          bookIndex: 0,
          chapter: 1,
          verse: 1,
          startWord: 1,
          endWord: 2,
        ),
        saved: (p) => result = p,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'גד־').first)
            .selected,
        true,
      );
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'הו').last);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'הו').last)
            .selected,
        true,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('load failures prevent saving and offer retry', (tester) async {
    await open(tester, fails: true, saved: (_) {});
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
