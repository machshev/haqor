import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/app_settings.dart' show ReaderText;
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/reader_page.dart';
import 'package:haqor/src/study_workspace.dart' as study;
import 'package:haqor/src/widgets/cross_references_sheet.dart';
import 'package:haqor/src/widgets/syntax_sheet.dart';
import 'package:haqor/src/widgets/verse_row.dart';
import 'package:haqor/src/widgets/study_workspace_panel.dart';
import 'package:haqor/src/widgets/timeline_chart.dart' show TimelinePage;
import 'package:haqor/src/widgets/word_info_sheet.dart';

import '../syntax_tree_test.dart' show node;

/// Answers [GetChapter] requests the way the Rust side would, but only when
/// the test asks for it, so tests can observe the exact frame where a chapter
/// lands in the sliver tree.
class _FakeRust {
  final List<GetChapter> pending = [];
  final List<GetStudyState> studyRequests = [];
  final List<SaveStudyState> studySaves = [];
  final List<GetWordInfo> wordRequests = [];
  final List<GetWordOccurrences> occurrenceRequests = [];
  final List<GetVerseTexts> verseTextRequests = [];
  final List<GetCrossReferences> crossReferenceRequests = [];
  final List<GetQuotations> quotationRequests = [];
  final List<GetThematicReferences> thematicRequests = [];
  final List<GetSyntaxTrees> syntaxRequests = [];
  final List<GetChapterTranslation> translationRequests = [];

  void onWordInfo(GetWordInfo request) => wordRequests.add(request);
  void onOccurrences(GetWordOccurrences request) =>
      occurrenceRequests.add(request);
  void onVerseTexts(GetVerseTexts request) => verseTextRequests.add(request);

  void onStudyRequest(GetStudyState request) => studyRequests.add(request);
  void onStudySave(SaveStudyState request) => studySaves.add(request);

  void onRequest(GetChapter request) => pending.add(request);

  /// Serialize-and-deliver every pending chapter through the same
  /// [assignRustSignal] entry point rinf uses for real signals.
  void deliverAll() {
    final requests = List<GetChapter>.of(pending);
    pending.clear();
    for (final request in requests) {
      final response = ChapterText(
        book: request.book,
        chapter: request.chapter,
        syriac: request.syriac,
        includeGlosses: request.includeGlosses,
        includeMorphology: request.includeMorphology,
        includeNames: request.includeNames,
        includeRoots: request.includeRoots,
        verses: [
          for (var v = 1; v <= 20; v++)
            VerseEntry(
              verse: v,
              text:
                  'ספר${request.book} פרק${request.chapter} פסוק$v '
                  'מלה מלה מלה מלה מלה מלה מלה מלה',
              glosses: const [],
              morphologies: const [],
              names: const [],
              roots: const [],
              ketivs: const [],
              crossReferenceScores: const [],
            ),
        ],
      );
      assignRustSignal['ChapterText']!(
        response.bincodeSerialize(),
        Uint8List(0),
      );
    }
  }
}

Finder _verse(int book, int chapter, int verse) => find.byWidgetPredicate(
  (w) =>
      w is VerseRow &&
      w.entry.text.startsWith('ספר$book פרק$chapter פסוק$verse '),
);

Finder _anyVisibleVerse(WidgetTester tester) => find.byType(VerseRow).first;

Future<_FakeRust> _pumpReader(
  WidgetTester tester, {
  int book = 0,
  required int chapter,
  bool englishBookNames = false,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'book': book,
    'chapter': chapter,
    'english_book_names': englishBookNames,
    ...prefs,
  });
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: BibleReaderPage(
        sendChapterRequest: rust.onRequest,
        sendStudyStateRequest: rust.onStudyRequest,
        saveStudyState: rust.onStudySave,
        sendWordInfoRequest: rust.onWordInfo,
        sendWordOccurrencesRequest: rust.onOccurrences,
        sendVerseTextsRequest: rust.onVerseTexts,
      ),
    ),
  );
  await tester.pump();
  rust.deliverAll();
  await tester.pump();
  return rust;
}

/// Delivers all pending chapters and asserts that the first visible verse did
/// not move on screen — the core no-jump guarantee of the reader.
Future<void> _deliverExpectingNoShift(
  WidgetTester tester,
  _FakeRust rust,
) async {
  final anchor = _anyVisibleVerse(tester);
  final entryBefore = tester.widget<VerseRow>(anchor).entry;
  final topBefore = tester.getTopLeft(anchor);
  rust.deliverAll();
  await tester.pump();
  final after = find.byWidgetPredicate(
    (w) => w is VerseRow && identical(w.entry, entryBefore),
  );
  expect(after, findsOneWidget);
  expect(tester.getTopLeft(after), topBefore);
}

void main() {
  crossReferenceDockTests();
  syntaxTests();
  translationTests();
  compactViewMenuTests();
  readerViewTests();

  for (final enabled in [true, false]) {
    testWidgets(
      'chapter headings and phrase endpoints highlight independently ($enabled)',
      (tester) async {
        final workspace = study.StudyWorkspace(
          id: 'study',
          name: 'Study',
          highlightsEnabled: enabled,
          passages: const [
            study.StudyPassage(
              bookIndex: 0,
              chapter: 1,
              verse: 1,
              wholeChapter: true,
              colorValue: 0xff112233,
              note: 'Chapter note',
            ),
            study.StudyPassage(
              bookIndex: 0,
              chapter: 1,
              verse: 1,
              endVerse: 3,
              startWord: 2,
              endWord: 1,
              colorValue: 0xff445566,
            ),
            study.StudyPassage(
              bookIndex: 0,
              chapter: 1,
              verse: 4,
              endVerse: 5,
              colorValue: 0xff778899,
            ),
          ],
        );
        SharedPreferences.setMockInitialValues({
          'book': 0,
          'chapter': 1,
          study.studyWorkspacesKey: study.encodeStudyWorkspaces([workspace]),
          study.activeStudyWorkspaceKey: 'study',
        });
        final rust = _FakeRust();
        await tester.pumpWidget(
          MaterialApp(
            home: BibleReaderPage(
              sendChapterRequest: rust.onRequest,
              sendStudyStateRequest: rust.onStudyRequest,
              saveStudyState: rust.onStudySave,
              sendWordInfoRequest: rust.onWordInfo,
              sendWordOccurrencesRequest: rust.onOccurrences,
              sendVerseTextsRequest: rust.onVerseTexts,
            ),
          ),
        );
        await tester.pump();
        rust.deliverAll();
        await tester.pumpAndSettle();
        final heading = tester.widget<Container>(
          find.byKey(const ValueKey('chapter-heading-0-1')),
        );
        expect(
          (heading.decoration as BoxDecoration).color,
          enabled ? const Color(0xff112233).withValues(alpha: 0.55) : null,
        );
        final first = tester.widget<VerseRow>(_verse(1, 1, 1));
        final middle = tester.widget<VerseRow>(_verse(1, 1, 2));
        final last = tester.widget<VerseRow>(_verse(1, 1, 3));
        final whole = tester.widget<VerseRow>(_verse(1, 1, 4));
        expect(first.studyHighlighted, false);
        expect(middle.studyHighlighted, false);
        expect(last.studyHighlighted, false);
        expect(first.studyNote, false); // Chapter notes belong on the heading.
        expect(
          first.studyPhraseHighlightColors.keys,
          enabled ? List.generate(9, (i) => i + 2) : isEmpty,
        );
        expect(
          middle.studyPhraseHighlightColors.keys,
          enabled ? List.generate(11, (i) => i) : isEmpty,
        );
        expect(
          last.studyPhraseHighlightColors.keys,
          enabled ? [0, 1] : isEmpty,
        );
        expect(whole.studyHighlighted, enabled);
        expect(whole.studyPhraseHighlightColors, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final shown in [true, false]) {
    testWidgets('study headings stand before their verses ($shown)', (
      tester,
    ) async {
      final workspace = study.StudyWorkspace(
        id: 'study',
        name: 'Study',
        headingsEnabled: shown,
        sections: const [
          study.StudySection(
            id: 'sum',
            title: 'Creation',
            chapter: 1,
            verse: 1,
            bookIndex: 0,
            wholeChapter: true,
            note: 'Six days',
          ),
          study.StudySection(
            id: 'light',
            title: 'Light',
            chapter: 1,
            verse: 3,
            parentId: 'sum',
            note: 'Day one',
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        'book': 0,
        'chapter': 1,
        study.studyWorkspacesKey: study.encodeStudyWorkspaces([workspace]),
        study.activeStudyWorkspaceKey: 'study',
      });
      final rust = _FakeRust();
      await tester.pumpWidget(
        MaterialApp(
          home: BibleReaderPage(
            sendChapterRequest: rust.onRequest,
            sendStudyStateRequest: rust.onStudyRequest,
            saveStudyState: rust.onStudySave,
            sendWordInfoRequest: rust.onWordInfo,
            sendWordOccurrencesRequest: rust.onOccurrences,
            sendVerseTextsRequest: rust.onVerseTexts,
          ),
        ),
      );
      await tester.pump();
      rust.deliverAll();
      await tester.pumpAndSettle();
      final summary = find.byKey(const ValueKey('study-heading-sum'));
      final light = find.byKey(const ValueKey('study-heading-light'));
      if (!shown) {
        expect(summary, findsNothing);
        expect(light, findsNothing);
        return;
      }
      expect(find.text('Six days'), findsOneWidget);
      expect(find.text('Day one'), findsOneWidget);
      final y = tester.getTopLeft;
      expect(y(summary).dy, lessThan(y(_verse(1, 1, 1)).dy));
      expect(y(light).dy, greaterThan(y(_verse(1, 1, 2)).dy));
      expect(y(light).dy, lessThan(y(_verse(1, 1, 3)).dy));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('headings are added and edited from the reader', (tester) async {
    const workspace = study.StudyWorkspace(
      id: 'study',
      name: 'Study',
      // Hidden, and shown once a heading is added from the reader.
      headingsEnabled: false,
      sections: [
        study.StudySection(
          id: 'sum',
          title: 'Creation',
          chapter: 1,
          verse: 1,
          bookIndex: 0,
          wholeChapter: true,
        ),
        study.StudySection(
          id: 'light',
          title: 'Light',
          chapter: 1,
          verse: 3,
          parentId: 'sum',
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      study.studyWorkspacesKey: study.encodeStudyWorkspaces([workspace]),
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-heading-light')), findsNothing);

    tester.widget<VerseRow>(_verse(1, 1, 5)).onWordMenu!(
      'מלה',
      null,
      3,
      '',
      const Offset(300, 200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add heading at 1:5'));
    await tester.pumpAndSettle();
    expect(find.text('New section heading'), findsOneWidget);
    // Beside Light by default, dividing it at verse 5.
    expect(find.byKey(const ValueKey('section-parent')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('section-title')),
      'Firmament',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final saved = study
        .decodeStudyWorkspaces(
          (await SharedPreferences.getInstance()).getString(
            study.studyWorkspacesKey,
          ),
        )
        .single;
    expect(saved.headingsEnabled, isTrue);
    final added = saved.sections.firstWhere((s) => s.title == 'Firmament');
    expect(added.parentId, 'sum');
    expect(added.start, (chapter: 1, verse: 5));
    final heading = find.byKey(ValueKey('study-heading-${added.id}'));
    expect(
      tester.getTopLeft(heading).dy,
      lessThan(tester.getTopLeft(_verse(1, 1, 5)).dy),
    );
    expect(
      tester.getTopLeft(heading).dy,
      greaterThan(tester.getTopLeft(_verse(1, 1, 4)).dy),
    );

    // Clear any chapter-load notice lying over the heading.
    ScaffoldMessenger.of(tester.element(heading)).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Firmament'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firmament'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit heading'));
    await tester.pumpAndSettle();
    expect(find.text('Edit section heading'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline events are added from a verse and marked there', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      study.studyWorkspacesKey: study.encodeStudyWorkspaces([
        const study.StudyWorkspace(id: 'study', name: 'Study'),
      ]),
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('verse-timeline-3')), findsNothing);

    await tester.longPress(find.byKey(const ValueKey('verse-number-3')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add timeline event here'));
    await tester.pumpAndSettle();
    // Without a timeline, one is made first.
    expect(find.text('New timeline'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('timeline-title')),
      'Creation',
    );
    await tester.tap(find.byKey(const ValueKey('timeline-scale')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another unit, such as days').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('timeline-unit')), 'Day');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('New timeline event'), findsOneWidget);
    expect(find.text('Bereshit 1:3'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-title')),
      'Light',
    );
    await tester.enterText(
      find.byKey(const ValueKey('timeline-entry-start')),
      '1',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final saved = study
        .decodeStudyWorkspaces(
          (await SharedPreferences.getInstance()).getString(
            study.studyWorkspacesKey,
          ),
        )
        .single;
    final timeline = saved.timelines.single;
    expect(timeline.formatTime(const study.TimelineTime(1)), 'Day 1');
    final entry = saved.timelineEntries.single;
    expect(
      (entry.title, entry.start, entry.timelineId),
      ('Light', const study.TimelineTime(1), timeline.id),
    );
    expect(entry.verses.single.locationKey, '0:1:3');

    final marker = find.byKey(const ValueKey('verse-timeline-3'));
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await tester.pumpAndSettle();
    expect(find.text('Creation · Day 1'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    // Its timeline opens, drawn with the event picked out.
    expect(find.byType(TimelinePage), findsOneWidget);
    expect(find.byKey(ValueKey('timeline-mark-${entry.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial load shows the requested chapter with its divider', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    expect(rust.studyRequests, hasLength(1));
    expect(_verse(1, 5, 1), findsOneWidget);
    expect(find.text('Bereshit 5'), findsNWidgets(2)); // header and tab chip
    rust.deliverAll(); // prefetched neighbours
    await tester.pump();
  });

  testWidgets('uses saved English book names in reader labels', (tester) async {
    final rust = await _pumpReader(tester, chapter: 5, englishBookNames: true);
    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('Genesis 5'), findsNWidgets(2)); // header and tab chip
    expect(find.text('Bereshit 5'), findsNothing);
    rust.deliverAll(); // prefetched neighbours
    await tester.pump();
  });

  testWidgets('opens independent reader tabs and tiles them into columns', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(tester, chapter: 5);

    expect(find.byTooltip('New reader tab'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);

    await tester.tap(find.byTooltip('New reader tab'));
    await tester.pump();
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.byTooltip('Tile reader tabs'), findsOneWidget);

    await tester.tap(find.byTooltip('Tile reader tabs'));
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    expect(find.byTooltip('Show reader tabs'), findsOneWidget);
    expect(find.byTooltip('Study workspace'), findsOneWidget);
    final readers = find.byType(CustomScrollView);
    expect(tester.getTopLeft(readers.at(0)).dx, 0);
    expect(tester.getTopLeft(readers.at(1)).dx, greaterThan(500));

    await tester.tap(find.byTooltip('Study workspace'));
    await tester.pump();

    final readerTile = find.byKey(const ValueKey('reader:primary'));
    final secondReaderTile = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('reader:') &&
              (widget.key! as ValueKey<String>).value != 'reader:primary',
        )
        .first;
    final studyTile = find.byKey(const ValueKey('study-word-panel'));
    expect(readerTile, findsOneWidget);
    expect(studyTile, findsOneWidget);
    expect(
      tester.getTopLeft(studyTile).dx,
      greaterThan(tester.getTopLeft(readerTile).dx),
    );

    final widthBefore = tester.getSize(readerTile).width;
    final panelWidthBefore = tester.getSize(studyTile).width;
    await tester.drag(
      find.byTooltip('Drag to resize study and word panel'),
      const Offset(60, 0),
    );
    await tester.pump();
    expect(tester.getSize(readerTile).width, greaterThan(widthBefore));
    expect(tester.getSize(studyTile).width, lessThan(panelWidthBefore));
    expect(
      tester.getSize(readerTile).width,
      tester.getSize(secondReaderTile).width,
    );
  });

  testWidgets('mobile shows a lone tab without close and swipes between tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(tester, chapter: 5);

    expect(find.byType(InputChip), findsOneWidget);
    expect(find.byTooltip('Close reader tab'), findsNothing);
    expect(find.byTooltip('Reader options'), findsOneWidget);
    expect(find.byIcon(Icons.view_column_outlined), findsNothing);

    final readerPosition = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!
        .position;
    expect(readerPosition.axis, Axis.vertical);
    expect(
      readerPosition.maxScrollExtent - readerPosition.pixels,
      greaterThan(31),
    );
    readerPosition.jumpTo(
      (readerPosition.pixels + 1).clamp(
        readerPosition.minScrollExtent,
        readerPosition.maxScrollExtent,
      ),
    );
    readerPosition.jumpTo(
      (readerPosition.pixels + 30).clamp(
        readerPosition.minScrollExtent,
        readerPosition.maxScrollExtent,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.getSize(find.byKey(const ValueKey('reader-workspace-bar'))).height,
      0,
    );

    readerPosition.jumpTo(
      (readerPosition.pixels - 30).clamp(
        readerPosition.minScrollExtent,
        readerPosition.maxScrollExtent,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.getSize(find.byKey(const ValueKey('reader-workspace-bar'))).height,
      48,
    );

    await tester.tap(find.byTooltip('Reader options'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tapAt(const Offset(10, 200));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('New reader tab'));
    await tester.pump();
    await tester.pump();
    rust.deliverAll();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(InputChip), findsNWidgets(2));
    var chips = tester.widgetList<InputChip>(find.byType(InputChip)).toList();
    expect(chips[1].selected, isTrue);

    await tester.drag(find.byType(PageView), const Offset(400, 0));
    await tester.pumpAndSettle();

    chips = tester.widgetList<InputChip>(find.byType(InputChip)).toList();
    expect(chips[0].selected, isTrue);

    await tester.ensureVisible(find.byTooltip('Close reader tab').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close reader tab').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(InputChip), findsOneWidget);
    expect(tester.widget<InputChip>(find.byType(InputChip)).onDeleted, isNull);
  });

  testWidgets('mobile study is a swipeable page with a pinned toolbar action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(tester, chapter: 5);
    await tester.pumpAndSettle();
    // Rust's answer to the startup request, so that what follows is a later
    // update and not that answer.
    assignRustSignal['StudyState']!(
      StudyState(
        found: false,
        workspacesJson: '[]',
        activeWorkspaceId: '',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();

    final studyButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Study workspace',
    );
    expect(studyButton.hitTestable(), findsOneWidget);
    expect(find.byType(StudyWorkspacePanel).hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Reader options'));
    await tester.pumpAndSettle();
    expect(find.text('Study workspace'), findsNothing);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
    // Start in the reader margin, outside selectable verse text.
    await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    await tester.pumpAndSettle();
    expect(find.byType(StudyWorkspacePanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.getSize(find.byType(StudyWorkspacePanel)).width, 360);
    expect(tester.getTopLeft(find.byType(StudyWorkspacePanel)).dy, 48);
    expect(tester.widget<IconButton>(studyButton).isSelected, isTrue);

    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Mobile study');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('Mobile study'), findsOneWidget);
    expect(rust.studySaves, isNotEmpty);

    // Incoming core updates must also refresh the study page while it is open.
    const passage = study.StudyPassage(bookIndex: 0, chapter: 7, verse: 1);
    const workspace = study.StudyWorkspace(
      id: 'synced',
      name: 'Synced study',
      passages: [passage],
    );
    final response = StudyState(
      found: true,
      workspacesJson: study.encodeStudyWorkspaces([workspace]),
      activeWorkspaceId: workspace.id,
    );
    assignRustSignal['StudyState']!(response.bincodeSerialize(), Uint8List(0));
    await tester.pumpAndSettle();
    expect(find.text('Synced study'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('passage-${passage.locationKey}')).last,
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(studyButton).isSelected, isFalse);
    expect(find.byType(StudyWorkspacePanel).hitTestable(), findsNothing);
    expect(_verse(1, 7, 1), findsOneWidget);

    await tester.tap(studyButton);
    await tester.pumpAndSettle();
    expect(find.byType(StudyWorkspacePanel), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(_verse(1, 7, 1), findsOneWidget);
    expect(tester.widget<IconButton>(studyButton).isSelected, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('study paging preserves the active reader across window sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_tabs': ['primary', 'two'],
      'reader_active_tab': 'two',
      'reader_session_two_book': 0,
      'reader_session_two_chapter': 7,
      'study_workspace_visible': true,
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<InputChip>(find.byType(InputChip)).last.selected,
      isTrue,
    );

    await tester.tap(find.byTooltip('Study workspace'));
    // Exercise the intermediate animation frames between the second reader
    // and study, so they cannot silently change the study's source reader.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(
      tester
          .widget<StudyWorkspacePanel>(find.byType(StudyWorkspacePanel))
          .currentPassage
          .chapter,
      7,
    );
    await tester.tap(find.byTooltip('Study workspace'));
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<InputChip>(find.byType(InputChip)).last.selected,
      isTrue,
    );

    for (final width in [1200.0, 500.0, 1400.0, 500.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      rust.deliverAll();
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<InputChip>(find.byType(InputChip)).last.selected,
        isTrue,
      );
      expect(_verse(1, 7, 1).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await tester.tap(find.byTooltip('Study workspace'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byType(StudyWorkspacePanel), findsOneWidget);
    expect(
      tester.widgetList<InputChip>(find.byType(InputChip)).last.selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('active mobile word info is a swipeable page with history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(tester, chapter: 5);
    await tester.pumpAndSettle();

    // Word requests deliberately remain pending; advance page animations
    // without waiting for the inspector's loading indicator to settle.
    Future<void> finishNavigation() async {
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    double page() =>
        tester.widget<PageView>(find.byType(PageView).first).controller!.page!;
    WordInfoSheet current() =>
        tester.widget<WordInfoSheet>(find.byType(WordInfoSheet));
    expect(find.byTooltip('Word info'), findsNothing);
    tester
        .widget<VerseRow>(find.byType(VerseRow).first)
        .onWordTap('מלה', 'original gloss', 3, 'מלל');
    await finishNavigation();
    expect(page(), 2);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Word info').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Study workspace').hitTestable(), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('word-info-page'))).width,
      360,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('word-info-page'))).dy,
      48,
    );
    expect(current().docked, isTrue);
    expect(current().chapter, 5);
    expect(current().position, 3);
    expect(current().readerGloss, 'original gloss');
    expect(current().initialRoot, 'מלל');

    current().onOpenWord!('יָעַד', null);
    await tester.pump();
    expect(current().word, 'יָעַד');
    expect(rust.wordRequests.last.word, 'יָעַד');
    await tester.tap(find.byTooltip('Back to previous word'));
    await tester.pump();
    expect(current().word, 'מלה');
    expect(current().position, 3);
    await tester.tap(find.byTooltip('Forward to next word'));
    await tester.pump();
    expect(current().word, 'יָעַד');

    final info = WordInfo(
      requestId: rust.wordRequests.last.requestId,
      found: true,
      word: current().word,
      root: '',
      gloss: 'appoint',
      vavCon: false,
      lexemes: const [],
      roots: const [],
    );
    assignRustSignal['WordInfo']!(info.bincodeSerialize(), Uint8List(0));
    await tester.pump();
    expect(find.text('Lexicon'), findsOneWidget);
    // Swipe outside text selection and the inspector's own tab gestures.
    await tester.dragFrom(const Offset(5, 400), const Offset(300, 0));
    await finishNavigation();
    expect(page(), 1);
    await tester.dragFrom(const Offset(355, 400), const Offset(-300, 0));
    await finishNavigation();
    expect(page(), 2);
    expect(current().word, 'יָעַד');

    await tester.tap(find.byTooltip('Word info'));
    await finishNavigation();
    expect(page(), 1);
    await tester.tap(find.byTooltip('Word info'));
    await finishNavigation();
    expect(page(), 2);
    current().onNavigateToPassage!(0, 7, 1);
    await finishNavigation();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(page(), 1);
    expect(find.byTooltip('Word info'), findsOneWidget);
    await tester.tap(find.byTooltip('Word info'));
    await finishNavigation();
    expect(current().word, 'יָעַד');
    await tester.tap(find.byTooltip('Back to previous word'));
    await tester.pump();
    expect(current().chapter, 5);
    await tester.tap(find.byTooltip('Word info'));
    await finishNavigation();
    expect(_verse(1, 7, 1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'global mobile word page survives resizing and passage navigation',
    (tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rust = await _pumpReader(tester, chapter: 5);
      await tester.tap(find.byTooltip('New reader tab'));
      await tester.pump();
      await tester.pump();
      rust.deliverAll();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InputChip).first);
      await tester.pumpAndSettle();

      Future<void> finishNavigation() async {
        await tester.pump();
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      tester
          .widget<VerseRow>(find.byType(VerseRow).first)
          .onWordTap('מלה', null, 0, '');
      await finishNavigation();
      WordInfoSheet current() =>
          tester.widget<WordInfoSheet>(find.byType(WordInfoSheet));
      expect(current().word, 'מלה');
      expect(
        tester
            .widgetList<InputChip>(find.byType(InputChip))
            .every((chip) => !chip.selected),
        isTrue,
      );

      await tester.tap(find.byTooltip('Study workspace'));
      await finishNavigation();
      await tester.tap(find.byTooltip('Word info'));
      await finishNavigation();
      expect(current().word, 'מלה');

      for (final width in [1200.0, 500.0]) {
        tester.view.physicalSize = Size(width, 800);
        await finishNavigation();
        rust.deliverAll();
        await tester.pump();
        expect(
          tester.widgetList<InputChip>(find.byType(InputChip)).first.selected,
          isTrue,
        );
        if (width < 900) {
          await tester.tap(find.byTooltip('Word info'));
          await finishNavigation();
        }
        expect(current().word, 'מלה');
        expect(tester.takeException(), isNull);
      }

      // Passage links return to the active reader while keeping word info.
      current().onNavigateToPassage!(0, 7, 1);
      await finishNavigation();
      rust.deliverAll();
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<InputChip>(find.byType(InputChip)).first.selected,
        isTrue,
      );
      expect(_verse(1, 7, 1), findsOneWidget);
      expect(find.byTooltip('Word info'), findsOneWidget);
      await tester.tap(find.byTooltip('Word info'));
      await finishNavigation();
      expect(current().word, 'מלה');
      expect(current().chapter, 5);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, tiled, layout) in [
    (500.0, false, 'automatic'),
    (1100.0, false, 'automatic'),
    (1500.0, false, 'automatic'),
    (1366.0, true, 'automatic'),
    (1100.0, false, 'focus'),
  ]) {
    testWidgets(
      'word panel is global across reader tabs ($width, $tiled, $layout)',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          'book': 0,
          'chapter': 5,
          'reader_tabs': ['primary', 'two'],
          'reader_active_tab': 'primary',
          'reader_session_two_book': 1,
          'reader_session_two_chapter': 7,
          'reader_tabs_tiled': tiled,
          'reader_layout_mode': layout,
        });
        final rust = _FakeRust();
        await tester.pumpWidget(
          MaterialApp(
            home: BibleReaderPage(
              sendChapterRequest: rust.onRequest,
              sendStudyStateRequest: rust.onStudyRequest,
              saveStudyState: rust.onStudySave,
              sendWordInfoRequest: rust.onWordInfo,
              sendWordOccurrencesRequest: rust.onOccurrences,
              sendVerseTextsRequest: rust.onVerseTexts,
            ),
          ),
        );
        Future<void> finishNavigation() async {
          await tester.pump();
          for (var i = 0; i < 40; i++) {
            rust.deliverAll();
            await tester.pump(const Duration(milliseconds: 20));
          }
        }

        Future<void> showWordPage() async {
          if (width < 900) {
            await tester.dragFrom(
              Offset(width - 5, 400),
              Offset(-width * 0.8, 0),
            );
            await finishNavigation();
          }
        }

        WordInfoSheet current() =>
            tester.widget<WordInfoSheet>(find.byType(WordInfoSheet));
        await finishNavigation();
        tester
            .widget<VerseRow>(_verse(1, 5, 1))
            .onWordTap('מלה', 'original gloss', 3, 'מלל');
        await finishNavigation();
        final originalState = tester.state(find.byType(WordInfoSheet));

        // A different passage/tab must neither replace nor refetch the lookup.
        await tester.tap(find.byType(InputChip).last);
        await finishNavigation();
        await showWordPage();
        expect(current().word, 'מלה');
        expect(current().book, 1);
        expect(current().chapter, 5);
        expect(current().position, 3);
        expect(current().readerGloss, 'original gloss');
        expect(tester.state(find.byType(WordInfoSheet)), same(originalState));
        expect(rust.wordRequests, hasLength(1));

        // A word from another reader joins the same back/forward history.
        if (width < 900) {
          await tester.tap(find.byType(InputChip).last);
          await finishNavigation();
        }
        tester
            .widget<VerseRow>(_verse(2, 7, 1))
            .onWordTap('בָּרָא', 'second gloss', 1, 'ברא');
        await finishNavigation();
        expect(current().word, 'בָּרָא');
        expect(current().book, 2);
        await tester.tap(find.byTooltip('Back to previous word'));
        await tester.pump();
        expect(current().word, 'מלה');
        expect(current().initialRoot, 'מלל');

        // Closing the source reader leaves the global panel open, with its
        // loaded results and history intact (including after untile).
        final stateBeforeClose = tester.state(find.byType(WordInfoSheet));
        tester.widgetList<InputChip>(find.byType(InputChip)).first.onDeleted!();
        await finishNavigation();
        expect(
          tester.state(find.byType(WordInfoSheet)),
          same(stateBeforeClose),
        );
        expect(
          find.byTooltip('Forward to next word').hitTestable(),
          findsOneWidget,
        );
        expect(current().word, 'מלה');
        expect(current().chapter, 5);
        await tester.tap(find.byTooltip('Forward to next word'));
        await tester.pump();
        expect(current().word, 'בָּרָא');

        // A passage link targets the remaining active reader, without clearing
        // the word or replacing its original passage metadata.
        current().onNavigateToPassage!(2, 9, 1);
        await finishNavigation();
        expect(_verse(3, 9, 1), findsOneWidget);
        await showWordPage();
        expect(current().word, 'בָּרָא');
        expect(current().book, 2);
        expect(current().chapter, 7);
        await tester.tap(find.byTooltip('Back to previous word'));
        await tester.pump();
        expect(current().word, 'מלה');

        await tester.tap(find.byTooltip('New reader tab'));
        await finishNavigation();
        await showWordPage();
        expect(current().word, 'מלה');
        expect(current().chapter, 5);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('shows only the reader tiles that fit their minimum width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_tabs': ['primary', 'two', 'three', 'four'],
      'reader_active_tab': 'primary',
      'reader_tabs_tiled': true,
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    Finder readerTiles() => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('reader:'),
    );

    expect(readerTiles(), findsNWidgets(4));
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Reader options'), findsNothing);

    tester.view.physicalSize = const Size(900, 800);
    await tester.pump();
    expect(readerTiles(), findsNWidgets(3));
    expect(find.byKey(const ValueKey('reader:primary')), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip('Reader options'), findsOneWidget);
  });

  testWidgets(
    'adds overflow readers as tabs and arrows between tiled readers',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'book': 0,
        'chapter': 1,
        'reader_tabs': ['primary', 'two', 'three'],
        'reader_active_tab': 'three',
        'reader_tabs_tiled': true,
      });
      final rust = _FakeRust();
      await tester.pumpWidget(
        MaterialApp(
          home: BibleReaderPage(
            sendChapterRequest: rust.onRequest,
            sendStudyStateRequest: rust.onStudyRequest,
            saveStudyState: rust.onStudySave,
            sendWordInfoRequest: rust.onWordInfo,
            sendWordOccurrencesRequest: rust.onOccurrences,
            sendVerseTextsRequest: rust.onVerseTexts,
          ),
        ),
      );
      await tester.pump();
      rust.deliverAll();
      await tester.pump();

      await tester.tap(find.byTooltip('New reader tab'));
      await tester.pump();
      rust.deliverAll();
      await tester.pump();

      expect(find.byType(InputChip), findsNWidgets(4));
      expect(find.byKey(const ValueKey('reader:primary')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      final chips = tester
          .widgetList<InputChip>(find.byType(InputChip))
          .toList();
      expect(chips[2].selected, isTrue);
      expect(find.byKey(const ValueKey('reader:primary')), findsOneWidget);
    },
  );

  for (final tiled in [false, true]) {
    testWidgets('sidebar word history shares the toolbar (tiled: $tiled)', (
      tester,
    ) async {
      tester.view.physicalSize = Size(tiled ? 1366 : 1000, 744);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'book': 0,
        'chapter': 1,
        'reader_tabs': ['primary', 'two'],
        'reader_active_tab': 'primary',
        'reader_tabs_tiled': tiled,
        'study_workspace_visible': true,
        'reader_side_panel_width': 280.0,
      });
      final rust = _FakeRust();
      await tester.pumpWidget(
        MaterialApp(
          home: BibleReaderPage(
            sendChapterRequest: rust.onRequest,
            sendStudyStateRequest: rust.onStudyRequest,
            saveStudyState: rust.onStudySave,
            sendWordInfoRequest: rust.onWordInfo,
            sendWordOccurrencesRequest: rust.onOccurrences,
            sendVerseTextsRequest: rust.onVerseTexts,
          ),
        ),
      );
      await tester.pump();
      rust.deliverAll();
      await tester.pumpAndSettle();
      tester
          .widget<VerseRow>(find.byType(VerseRow).first)
          .onWordTap('מלה', 'original gloss', 3, 'מלל');
      await tester.pump();

      WordInfoSheet current() =>
          tester.widget<WordInfoSheet>(find.byType(WordInfoSheet));
      final original = current();
      final back = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Back to previous word',
      );
      final forward = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Forward to next word',
      );
      final switcher = find.byKey(const ValueKey('side-panel-switcher'));
      expect(tester.widget<IconButton>(back).onPressed, isNull);
      expect(tester.widget<IconButton>(forward).onPressed, isNull);
      expect(
        tester.getCenter(back).dy,
        closeTo(tester.getCenter(switcher).dy, 1),
      );
      expect(
        tester.getCenter(forward).dy,
        closeTo(tester.getCenter(switcher).dy, 1),
      );

      expect(
        tester.getCenter(back).dx,
        greaterThan(tester.getCenter(switcher).dx),
      );
      expect(
        tester.getCenter(forward).dx,
        greaterThan(tester.getCenter(back).dx),
      );

      original.onOpenWord!('יָעַד', null);
      await tester.pump();
      expect(current().word, 'יָעַד');
      expect(rust.wordRequests.last.word, 'יָעַד');
      expect(current().docked, isTrue);
      expect(current().book, isNull);
      expect(current().chapter, isNull);
      expect(current().verse, isNull);
      expect(current().position, isNull);
      expect(current().readerGloss, isNull);
      expect(current().initialRoot, isNull);
      expect(find.byType(BottomSheet), findsNothing);

      current().onOpenWord!('מוֹעֵד', null);
      await tester.pump();
      await tester.tap(back);
      await tester.pump();
      expect(current().word, 'יָעַד');
      await tester.tap(back);
      await tester.pump();
      expect(current().word, original.word);
      expect(current().book, original.book);
      expect(current().chapter, original.chapter);
      expect(current().verse, original.verse);
      expect(current().position, 3);
      expect(current().readerGloss, 'original gloss');
      expect(current().initialRoot, 'מלל');
      expect(tester.widget<IconButton>(back).onPressed, isNull);

      await tester.tap(forward);
      await tester.pump();
      expect(current().word, 'יָעַד');
      await tester.tap(forward);
      await tester.pump();
      expect(current().word, 'מוֹעֵד');
      expect(tester.widget<IconButton>(forward).onPressed, isNull);

      await tester.tap(back);
      await tester.pump();
      current().onOpenWord!('בָּרָא', null);
      await tester.pump();
      expect(current().word, 'בָּרָא');
      expect(tester.widget<IconButton>(forward).onPressed, isNull);
      await tester.tap(
        find.descendant(of: switcher, matching: find.text('Study')),
      );
      await tester.pump();
      expect(find.byType(StudyWorkspacePanel), findsOneWidget);
      expect(back, findsNothing);
      expect(forward, findsNothing);
      await tester.tap(
        find.descendant(of: switcher, matching: find.text('Word')),
      );
      await tester.pump();
      await tester.tap(back);
      await tester.pump();
      expect(current().word, 'יָעַד');
      expect(_sidePanelShown(tester, switcher), 'word');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tiled panel switches between Study and Word immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 744);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_tabs': ['primary', 'two'],
      'reader_active_tab': 'primary',
      'reader_tabs_tiled': true,
      'study_workspace_visible': true,
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(find.byType(StudyWorkspacePanel), findsOneWidget);

    tester
        .widget<VerseRow>(find.byType(VerseRow).first)
        .onWordTap('מלה', null, 0, '');
    await tester.pump();
    expect(find.byType(WordInfoSheet), findsOneWidget);
    expect(find.byType(StudyWorkspacePanel), findsNothing);

    final switcher = find.byKey(const ValueKey('side-panel-switcher'));
    await tester.tap(
      find.descendant(of: switcher, matching: find.text('Study')),
    );
    await tester.pump();
    expect(find.byType(StudyWorkspacePanel), findsOneWidget);
    expect(find.byType(WordInfoSheet), findsNothing);
    expect(_sidePanelShown(tester, switcher), 'study');

    await tester.tap(
      find.descendant(of: switcher, matching: find.text('Word')),
    );
    await tester.pump();
    expect(find.byType(WordInfoSheet), findsOneWidget);
    expect(find.byType(StudyWorkspacePanel), findsNothing);
    expect(
      tester.widget<WordInfoSheet>(find.byType(WordInfoSheet)).word,
      'מלה',
    );
    expect(_sidePanelShown(tester, switcher), 'word');
    expect(tester.takeException(), isNull);
  });

  testWidgets('study edits in one reader tab are kept by the others', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const workspace = study.StudyWorkspace(id: 'study', name: 'Study');
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_tabs': ['primary', 'two'],
      'reader_active_tab': 'primary',
      'study_workspace_visible': true,
      study.studyWorkspacesKey: study.encodeStudyWorkspaces([workspace]),
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    // One request for the workspaces, however many tabs are open.
    expect(rust.studyRequests, hasLength(1));

    Future<void> toggleHighlights() async {
      await tester.tap(find.byTooltip('Workspace options'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byWidgetPredicate((widget) => widget is CheckedPopupMenuItem)
            .first,
      );
      await tester.pumpAndSettle();
    }

    bool? savedHighlights() => study
        .decodeStudyWorkspaces(rust.studySaves.last.workspacesJson)
        .single
        .highlightsEnabled;

    await toggleHighlights();
    expect(savedHighlights(), isFalse);

    // The second tab starts from what the first saved, not from its own older
    // copy, so this turns them back on instead of repeating the first edit.
    await tester.tap(find.byType(InputChip).last);
    await tester.pumpAndSettle();
    await toggleHighlights();
    expect(rust.studySaves, hasLength(2));
    expect(savedHighlights(), isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the startup answer does not discard an edit made before it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const workspace = study.StudyWorkspace(id: 'study', name: 'Study');
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'study_workspace_visible': true,
      study.studyWorkspacesKey: study.encodeStudyWorkspaces([workspace]),
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Workspace options'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((widget) => widget is CheckedPopupMenuItem).first,
    );
    await tester.pumpAndSettle();
    expect(rust.studySaves, hasLength(1));

    // Rust answers the startup request only now, with what it held before.
    assignRustSignal['StudyState']!(
      StudyState(
        found: true,
        workspacesJson: study.encodeStudyWorkspaces([
          const study.StudyWorkspace(id: 'study', name: 'Older'),
        ]),
        activeWorkspaceId: 'study',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Study'), findsWidgets);
    expect(find.text('Older'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    final kept = study
        .decodeStudyWorkspaces(prefs.getString(study.studyWorkspacesKey))
        .single;
    expect(kept.name, 'Study');
    expect(kept.highlightsEnabled, isFalse);

    // Later answers are applied.
    assignRustSignal['StudyState']!(
      StudyState(
        found: true,
        workspacesJson: study.encodeStudyWorkspaces([
          const study.StudyWorkspace(id: 'study', name: 'Synced'),
        ]),
        activeWorkspaceId: 'study',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an unreadable answer leaves the workspaces and their backup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const workspace = study.StudyWorkspace(id: 'study', name: 'Study');
    final saved = study.encodeStudyWorkspaces([workspace]);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'study_workspace_visible': true,
      study.studyWorkspacesKey: saved,
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(find.text('Study'), findsWidgets);

    for (final payload in ['{not json', '', '{"id": "study"}']) {
      assignRustSignal['StudyState']!(
        StudyState(
          found: true,
          workspacesJson: payload,
          activeWorkspaceId: '',
        ).bincodeSerialize(),
        Uint8List(0),
      );
      await tester.pumpAndSettle();
    }
    expect(find.text('Study'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(study.studyWorkspacesKey), saved);
    expect(rust.studySaves, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the local copy moves to Rust once, however many tabs are open', (
    tester,
  ) async {
    const workspace = study.StudyWorkspace(id: 'study', name: 'Study');
    final saved = study.encodeStudyWorkspaces([workspace]);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_tabs': ['primary', 'two', 'three'],
      study.studyWorkspacesKey: saved,
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();

    final notFound = StudyState(
      found: false,
      workspacesJson: '[]',
      activeWorkspaceId: '',
    ).bincodeSerialize();
    assignRustSignal['StudyState']!(notFound, Uint8List(0));
    await tester.pumpAndSettle();
    expect(rust.studySaves, hasLength(1));
    expect(rust.studySaves.single.workspacesJson, saved);
    assignRustSignal['StudyState']!(notFound, Uint8List(0));
    await tester.pumpAndSettle();
    expect(rust.studySaves, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('tiled study reordering updates visible rows immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 744);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const workspace = study.StudyWorkspace(
      id: 'study',
      name: 'Study',
      groups: [
        study.StudyGroup(id: 'first', name: 'First group', order: 0),
        study.StudyGroup(id: 'second', name: 'Second group', order: 1),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_tabs': ['primary', 'two'],
      'reader_active_tab': 'primary',
      'reader_tabs_tiled': true,
      'study_workspace_visible': true,
      study.studyWorkspacesKey: study.encodeStudyWorkspaces([workspace]),
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-word-panel')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('First group')).dy,
      lessThan(tester.getTopLeft(find.text('Second group')).dy),
    );

    Future<void> dragSecondOntoFirst() async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('drag-group-second'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey('drag-group-first'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    await dragSecondOntoFirst();
    final prefs = await SharedPreferences.getInstance();
    expect(rust.studySaves, hasLength(1));
    expect(rust.studySaves.single.activeWorkspaceId, 'study');
    expect(
      rust.studySaves.single.workspacesJson,
      prefs.getString(study.studyWorkspacesKey),
    );
    expect(
      study
          .decodeStudyWorkspaces(prefs.getString(study.studyWorkspacesKey))
          .single
          .childGroups(null)
          .map((group) => group.id),
      ['second', 'first'],
    );
    expect(
      tester.getTopLeft(find.text('Second group')).dy,
      lessThan(tester.getTopLeft(find.text('First group')).dy),
    );

    // A second drag uses the refreshed outline, without reopening the panel.
    await dragSecondOntoFirst();
    expect(
      tester.getTopLeft(find.text('First group')).dy,
      lessThan(tester.getTopLeft(find.text('Second group')).dy),
    );
    expect(
      study
          .decodeStudyWorkspaces(prefs.getString(study.studyWorkspacesKey))
          .single
          .childGroups(null)
          .map((group) => group.id),
      ['first', 'second'],
    );
    // Drain the sync debounce only after verifying the immediate visual updates.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizes and persists the reader side panel', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_layout_mode': 'split',
      'study_workspace_visible': true,
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    final handle = find.byTooltip('Drag to resize side panel');
    expect(handle, findsOneWidget);
    await tester.drag(handle, const Offset(-80, 0));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('reader_side_panel_width'), greaterThan(400));
  });

  testWidgets('prepending the previous chapter does not shift content', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    // Neighbour prefetches (4 and 6) are pending. A first scroll tick asks
    // for the previous chapter; hold the response, then deliver it and
    // require the visible verse to stay exactly where it was.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await tester.pump();
    await _deliverExpectingNoShift(tester, rust);

    // The prepended chapter is really there: scrolling up reveals chapter 4.
    for (var i = 0; i < 30 && _verse(1, 4, 20).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
      await tester.pump();
      rust.deliverAll();
      await tester.pump();
    }
    expect(_verse(1, 4, 20), findsOneWidget);
    expect(
      tester.getTopLeft(_verse(1, 4, 19)).dy,
      lessThan(tester.getTopLeft(_verse(1, 4, 20)).dy),
      reason: 'the previous chapter should still read from verse 1 onward',
    );
  });

  testWidgets('a lexicon correction drops the cached chapters too', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    final before = <int>{};
    for (var i = 0; i < 5 && rust.pending.isNotEmpty; i++) {
      before.addAll(rust.pending.map((r) => r.chapter));
      rust.deliverAll();
      await tester.pump();
    }
    // The furthest chapter was only prefetched, so it is cached, not shown.
    final furthest = before.reduce(math.max);

    assignRustSignal['LexiconEntryOverrideStatus']!(
      LexiconEntryOverrideStatus(
        surface: 'מלה',
        success: true,
        message: '',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    final after = <int>{};
    for (var i = 0; i < 40 && !after.contains(furthest); i++) {
      after.addAll(rust.pending.map((r) => r.chapter));
      rust.deliverAll();
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
    }
    expect(after, contains(furthest), reason: 'asked for again, not cached');
  });

  testWidgets('a chapter in flight during a lexicon correction is not cached', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    // The neighbours' requests are still out when the correction lands.
    final inFlight = rust.pending.map((r) => r.chapter).toSet();
    expect(inFlight, isNotEmpty);

    assignRustSignal['LexiconEntryOverrideStatus']!(
      LexiconEntryOverrideStatus(
        surface: 'מלה',
        success: true,
        message: '',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    // Their replies may hold the old gloss. Reading on must ask again for
    // each of them rather than find it in the cache.
    final after = <int>{};
    for (var i = 0; i < 40 && !after.containsAll(inFlight); i++) {
      rust.deliverAll();
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
      after.addAll(rust.pending.map((r) => r.chapter));
    }
    expect(after, containsAll(inFlight));
  });

  testWidgets('workspaces from Rust with a highlighted root ask for roots', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 1);
    for (var i = 0; i < 5 && rust.pending.isNotEmpty; i++) {
      rust.deliverAll();
      await tester.pump();
    }
    expect(rust.pending, isEmpty);

    assignRustSignal['StudyState']!(
      StudyState(
        found: true,
        workspacesJson: study.encodeStudyWorkspaces([
          const study.StudyWorkspace(
            id: 'study',
            name: 'Synced',
            words: [study.StudyWord(root: 'אמר', surface: 'אמר')],
          ),
        ]),
        activeWorkspaceId: 'study',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(
      rust.pending.where((r) => r.chapter == 1 && r.includeRoots),
      isNotEmpty,
    );

    // The chapter's verses now come with roots, so a further answer that
    // changes nothing about the request does not ask again.
    for (var i = 0; i < 5 && rust.pending.isNotEmpty; i++) {
      rust.deliverAll();
      await tester.pump();
    }
    assignRustSignal['StudyState']!(
      StudyState(
        found: true,
        workspacesJson: study.encodeStudyWorkspaces([
          const study.StudyWorkspace(
            id: 'study',
            name: 'Synced again',
            words: [study.StudyWord(root: 'אמר', surface: 'אמר')],
          ),
        ]),
        activeWorkspaceId: 'study',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(rust.pending, isEmpty);
  });

  testWidgets(
    'a chapter reply after the timeout is shown in place of the error',
    (tester) async {
      SharedPreferences.setMockInitialValues({'book': 0, 'chapter': 1});
      final rust = _FakeRust();
      await tester.pumpWidget(
        MaterialApp(
          home: BibleReaderPage(
            sendChapterRequest: rust.onRequest,
            sendStudyStateRequest: rust.onStudyRequest,
            saveStudyState: rust.onStudySave,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      expect(find.text('Could not load this chapter.'), findsOneWidget);
      expect(_verse(1, 1, 1), findsNothing);

      rust.deliverAll();
      await tester.pump();
      await tester.pump();
      expect(_verse(1, 1, 1), findsOneWidget);
      expect(find.text('Could not load this chapter.'), findsNothing);
    },
  );

  testWidgets(
    'opening at a late verse scrolls to it with a next chapter loaded',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'book': 0,
        'chapter': 5,
        'verse': 18,
      });
      final rust = _FakeRust();
      await tester.pumpWidget(
        MaterialApp(
          home: BibleReaderPage(
            sendChapterRequest: rust.onRequest,
            sendStudyStateRequest: rust.onStudyRequest,
            saveStudyState: rust.onStudySave,
          ),
        ),
      );
      await tester.pump();
      // The neighbours arrive along with, and lengthen the scroll view beyond,
      // the chapter the verse is in.
      for (var i = 0; i < 6; i++) {
        rust.deliverAll();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(_verse(1, 5, 18), findsOneWidget);
      expect(_verse(1, 5, 1), findsNothing, reason: 'scrolled past the start');
      final top = tester.getTopLeft(_verse(1, 5, 18)).dy;
      expect(top, inInclusiveRange(viewport.top, viewport.bottom));
    },
  );

  testWidgets('scrolling forward across many chapters never shifts content', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 1);
    // Read forward through enough chapters to exceed the retained window.
    for (var i = 0; i < 120 && _verse(1, 10, 1).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump();
      await _deliverExpectingNoShift(tester, rust);
    }
    expect(_verse(1, 10, 1), findsOneWidget);
  });

  testWidgets('scrolling backward across many chapters never shifts content', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 15);
    for (var i = 0; i < 120 && _verse(1, 8, 1).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pump();
      await _deliverExpectingNoShift(tester, rust);
    }
    expect(_verse(1, 8, 1), findsOneWidget);
  });

  testWidgets('three-panel study notes toggle and store a grouped passage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'reader_layout_mode': 'threePanel',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    expect(find.text('Study notes'), findsNothing);
    expect(find.text('Word study'), findsNothing);
    expect(
      find.textContaining('Select a Hebrew or Syriac word'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Study workspace'));
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    expect(find.text('Study notes'), findsNothing);
    expect(find.text('Create workspace'), findsOneWidget);

    await tester.tap(find.text('Create workspace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Outline'), findsOneWidget);

    await tester.tap(find.byTooltip('Add study item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Creation');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Creation'), findsOneWidget);

    await tester.tap(find.byTooltip('Group options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add current passage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Passage note'),
      'Opening passage',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Bookmark'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString('study_workspaces_v1')!) as List<dynamic>;
    final savedWorkspace = stored.single as Map<String, dynamic>;
    final savedGroup =
        (savedWorkspace['groups'] as List<dynamic>).single
            as Map<String, dynamic>;
    final savedPassage =
        (savedWorkspace['passages'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(savedPassage['note'], 'Opening passage');
    expect(savedPassage['verse'], 1);
    expect(savedPassage['group'], savedGroup['id']);

    await tester.tap(find.byTooltip('Passage options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit reference and note'));
    await tester.pumpAndSettle();
    final endVerse = find.ancestor(
      of: find.text('End verse'),
      matching: find.byType(DropdownButtonFormField<int>),
    );
    await tester.tap(endVerse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final edited = study
        .decodeStudyWorkspaces(prefs.getString(study.studyWorkspacesKey))
        .single
        .passages
        .single;
    expect(edited.reference, '1:1–2');
    expect(edited.groupId, savedGroup['id']);
    expect(edited.note, 'Opening passage');
    expect(find.text('Bereshit 1:1–2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling persists the first visible verse', (tester) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(tester, chapter: 5);
    rust.deliverAll();
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('book'), 0);
    expect(prefs.getInt('chapter'), 5);
    expect(prefs.getInt('verse'), greaterThan(1));
    final history = prefs.getStringList('nav_history');
    expect(history?.last, '0,5,${prefs.getInt('verse')}');
  });

  for (final width in [500.0, 1200.0]) {
    testWidgets('chapter header updates the title at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rust = await _pumpReader(tester, chapter: 5);
      rust.deliverAll();
      await tester.pump();
      final scroll = find.byType(CustomScrollView);
      final controller = tester.widget<CustomScrollView>(scroll).controller!;
      final heading = find.byKey(const ValueKey('chapter-heading-0-6'));
      final indicator = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(Chip),
      );

      // Approach the boundary while the last verse of chapter 5 is visible.
      for (var i = 0; i < 40; i++) {
        final viewportTop = tester.getTopLeft(scroll).dy;
        if (heading.evaluate().isNotEmpty &&
            tester.getTopLeft(heading).dy < viewportTop + 200) {
          break;
        }
        controller.jumpTo(controller.offset + 100);
        await tester.pump();
        rust.deliverAll();
        await tester.pump();
      }
      expect(
        find.descendant(of: indicator, matching: find.text('5')),
        findsOneWidget,
      );

      // Put the chapter divider at the top, before verse 1 reaches it.
      // The heading has 24 pixels of padding above it.
      controller.jumpTo(
        controller.offset +
            tester.getTopLeft(heading).dy -
            tester.getTopLeft(scroll).dy -
            24,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.getTopLeft(heading).dy,
        closeTo(tester.getTopLeft(scroll).dy + 24, 0.01),
      );
      if (_verse(1, 5, 20).evaluate().isNotEmpty) {
        expect(
          tester.getBottomLeft(_verse(1, 5, 20)).dy,
          lessThanOrEqualTo(tester.getTopLeft(scroll).dy),
        );
      }
      expect(
        tester.getTopLeft(_verse(1, 6, 1)).dy,
        greaterThan(tester.getTopLeft(heading).dy),
      );
      expect(
        find.descendant(of: indicator, matching: find.text('6')),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('chapter'), 6);
      expect(prefs.getInt('verse'), 1);

      // Scrolling back to the preceding verse restores the previous chapter.
      controller.jumpTo(controller.offset - 100);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.descendant(of: indicator, matching: find.text('5')),
        findsOneWidget,
      );
    });
  }

  testWidgets('chapter indicator stays on 1 Samuel after crossing books', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(
      tester,
      book: 6,
      chapter: 21,
      englishBookNames: true,
    );
    rust.deliverAll();
    await tester.pump();

    for (var i = 0; i < 40 && find.text('1 Samuel').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
      rust.deliverAll();
      await tester.pump();
    }
    expect(find.text('1 Samuel'), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pump();
      expect(find.text('1 Samuel'), findsOneWidget);
      expect(find.text('Judges'), findsNothing);
    }
  });

  testWidgets('word menu opens, switches, and closes word panes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 744);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      study.studyWorkspacesKey: study.encodeStudyWorkspaces([
        const study.StudyWorkspace(id: 'study', name: 'Study'),
      ]),
      study.activeStudyWorkspaceKey: 'study',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pumpAndSettle();

    // Word requests stay pending, so the inspector's spinner never settles.
    // Chapters are answered as the reader prefetches them.
    Future<void> settle() async {
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        rust.deliverAll();
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    VerseRow row() => tester.widget<VerseRow>(find.byType(VerseRow).first);
    WordInfoSheet current() =>
        tester.widget<WordInfoSheet>(find.byType(WordInfoSheet));
    final close = find.byTooltip('Close word pane');

    row().onWordTap('מלה', null, 3, 'מלל');
    await settle();
    expect(current().word, 'מלה');
    expect(close, findsNothing);

    row().onWordMenu!('דבר', null, 4, 'דבר', const Offset(300, 200));
    await settle();
    await tester.tap(find.text('Open in new word pane'));
    await settle();
    expect(current().word, 'דבר');
    expect(current().chapter, 1);
    expect(current().position, 4);
    expect(current().proximity, isNotNull);
    expect(close, findsOneWidget);
    // The first pane stays built behind the new one, keeping its state.
    expect(find.byType(WordInfoSheet, skipOffstage: false), findsNWidgets(2));
    // History belongs to a pane: the new one has nothing to go back to.
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Back to previous word',
            ),
          )
          .onPressed,
      isNull,
    );

    // A plain tap replaces the active pane's word, not the other pane's.
    row().onWordTap('יָעַד', null, 5, 'יעד');
    await settle();
    expect(current().word, 'יָעַד');
    expect(find.byType(WordInfoSheet, skipOffstage: false), findsNWidgets(2));

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await settle();
    await tester.tap(find.text('מלה').last);
    await settle();
    expect(current().word, 'מלה');

    await tester.tap(close);
    await settle();
    expect(current().word, 'יָעַד');
    expect(close, findsNothing);
    expect(find.byType(WordInfoSheet, skipOffstage: false), findsOneWidget);

    // Clear any chapter-load notice queued ahead of the bookmark's.
    ScaffoldMessenger.of(
      tester.element(find.byType(VerseRow).first),
    ).clearSnackBars();
    row().onWordMenu!('מלה', null, 3, 'מלל', const Offset(300, 200));
    await settle();
    await tester.tap(find.text('Bookmark this root'));
    await settle();
    expect(find.text('Bookmarked root'), findsOneWidget);
    final saved = study.decodeStudyWorkspaces(
      (await SharedPreferences.getInstance()).getString(
        study.studyWorkspacesKey,
      ),
    );
    expect(saved.single.words.single.root, 'מלל');
    expect(saved.single.words.single.kind, study.StudyWordKind.root);

    row().onWordMenu!('מלה', null, 3, 'מלל', const Offset(300, 200));
    await settle();
    expect(find.text('Remove root bookmark'), findsOneWidget);
    expect(find.text('Bookmark this form'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Which view the side panel's switcher has selected, by name.
String _sidePanelShown(WidgetTester tester, Finder switcher) => tester
    .widget<SegmentedButton<Object?>>(switcher)
    .selected
    .single
    .toString()
    .split('.')
    .last;

Future<_FakeRust> _pumpWorkspace(
  WidgetTester tester,
  Size size, {
  Map<String, Object> prefs = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({'book': 0, 'chapter': 1, ...prefs});
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: BibleReaderPage(
        sendChapterRequest: rust.onRequest,
        sendStudyStateRequest: rust.onStudyRequest,
        saveStudyState: rust.onStudySave,
        sendWordInfoRequest: rust.onWordInfo,
        sendWordOccurrencesRequest: rust.onOccurrences,
        sendVerseTextsRequest: rust.onVerseTexts,
        sendCrossReferencesRequest: rust.crossReferenceRequests.add,
        sendQuotationsRequest: rust.quotationRequests.add,
        sendThematicReferencesRequest: rust.thematicRequests.add,
        sendSyntaxTreesRequest: rust.syntaxRequests.add,
        sendTranslationRequest: rust.translationRequests.add,
      ),
    ),
  );
  await tester.pump();
  rust.deliverAll();
  await tester.pumpAndSettle();
  return rust;
}

void crossReferenceDockTests() {
  testWidgets('cross references dock beside the reader from its toolbar', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(tester, const Size(1366, 744));
    expect(find.byType(CrossReferencesPanel), findsNothing);
    // The workspace bar no longer carries it: the reader's own toolbar does.
    expect(find.byTooltip('Cross references'), findsNothing);

    await tester.tap(find.byTooltip('Cross references in this chapter'));
    await tester.pump();
    expect(find.byType(CrossReferencesPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing, reason: 'docked');
    final request = rust.quotationRequests.single;
    expect((request.book, request.firstChapter), (1, 1));

    await tester.tap(find.byTooltip('Close cross references'));
    await tester.pump();
    expect(find.byType(CrossReferencesPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a verse number\'s menu opens its cross references', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(tester, const Size(1366, 744));
    await tester.longPress(find.byKey(const ValueKey('verse-number-2')).first);
    await tester.pumpAndSettle();
    expect(find.text('Chapter cross references'), findsOneWidget);
    await tester.tap(find.text('Cross references'));
    // The panel opens on its loading spinner, which never settles.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CrossReferencesPanel), findsOneWidget);
    final request = rust.crossReferenceRequests.single;
    expect((request.book, request.chapter, request.verse), (1, 1, 2));
    expect(rust.thematicRequests.single.verse, 2);

    // The reader's toolbar button brings the docked panel back to the
    // chapter's overview.
    await tester.tap(find.byTooltip('Cross references in this chapter'));
    await tester.pump();
    expect(find.byTooltip('All cross references'), findsNothing);
    expect(find.text('Quotations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a verse marker opens its links beside an open word', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(tester, const Size(1366, 744));
    final row = tester.widget<VerseRow>(find.byType(VerseRow).first);
    row.onWordTap('מלה', null, 0, '');
    await tester.pump();
    expect(find.byType(WordInfoSheet), findsOneWidget);

    row.onCrossReferences!();
    await tester.pump();
    final switcher = find.byKey(const ValueKey('side-panel-switcher'));
    expect(_sidePanelShown(tester, switcher), 'crossReferences');
    expect(find.byType(CrossReferencesPanel), findsOneWidget);
    final request = rust.crossReferenceRequests.single;
    expect((request.book, request.chapter, request.verse), (1, 1, 1));

    await tester.tap(
      find.descendant(of: switcher, matching: find.text('Word')),
    );
    await tester.pump();
    expect(find.byType(WordInfoSheet), findsOneWidget);
    expect(find.byType(CrossReferencesPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone cross references are a page beside the reader', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(tester, const Size(420, 800));
    expect(find.byKey(const ValueKey('cross-references-page')), findsNothing);
    tester.widget<VerseRow>(find.byType(VerseRow).first).onCrossReferences!();
    // The panel opens on its loading spinner, which never settles.
    await _turnPage(tester);
    expect(find.byType(BottomSheet), findsNothing);
    final page = find.byKey(const ValueKey('cross-references-page'));
    expect(page.hitTestable(), findsOneWidget);
    expect(
      find.descendant(of: page, matching: find.byType(CrossReferencesPanel)),
      findsOneWidget,
    );
    expect(rust.crossReferenceRequests.last.verse, 1);

    // Its bar button goes back to the reader and returns to the page.
    final button = find.byTooltip('Cross references');
    await tester.tap(button);
    await _turnPage(tester);
    expect(page.hitTestable(), findsNothing);
    expect(find.byType(VerseRow).hitTestable(), findsWidgets);
    await tester.tap(button);
    await _turnPage(tester);
    expect(page.hitTestable(), findsOneWidget);

    // Closing it returns to the reader and removes the page.
    await tester.tap(find.byTooltip('Close cross references'));
    await _turnPage(tester);
    expect(page, findsNothing);
    expect(find.byTooltip('Cross references'), findsNothing);
    expect(find.byType(VerseRow).hitTestable(), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // A page view, or the tiled workspace's layout builder, adopts a reader
  // (and the word and cross reference panels) during layout when the window
  // crosses between phone and desktop widths. A tooltip open inside it must
  // not re-attach to the app's overlay then.
  for (final tiled in [false, true]) {
    testWidgets('an open tooltip survives resizing (tiled: $tiled)', (
      tester,
    ) async {
      final rust = await _pumpWorkspace(
        tester,
        const Size(420, 800),
        prefs: {
          'reader_tabs': ['primary', 'two'],
          'reader_tabs_tiled': tiled,
          'study_workspace_visible': true,
        },
      );
      final row = tester.widget<VerseRow>(find.byType(VerseRow).first);
      row.onWordTap('מלה', null, 0, '');
      row.onCrossReferences!();
      await _turnPage(tester);
      await tester.tap(find.byType(InputChip).first);
      rust.deliverAll();
      await _turnPage(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      for (final width in [1400.0, 420.0, 1400.0]) {
        await mouse.moveTo(
          tester.getCenter(find.byTooltip('Rapid reading').hitTestable().first),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Rapid reading'), findsOneWidget);
        tester.view.physicalSize = Size(width, 800);
        await _turnPage(tester);
        expect(tester.takeException(), isNull, reason: 'at $width');
      }
    });
  }
}

void readerViewTests() {
  VerseRow verseRow(WidgetTester tester) =>
      tester.widget<VerseRow>(_verse(1, 1, 1));

  Future<void> tapToggle(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('the top bar toggles the interlinear and rapid reading apart', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 1);
    expect(verseRow(tester).interlinearPositions, isNull);

    await tapToggle(tester, 'reader-interlinear-toggle');
    expect(verseRow(tester).interlinearPositions, isEmpty);

    // No layers were enabled, so rapid reading turned the glosses on.
    await tapToggle(tester, 'reader-rapid-toggle');
    expect(rust.pending.any((r) => r.chapter == 1 && r.includeGlosses), isTrue);
    rust.deliverAll();
    await tester.pump();
    expect(verseRow(tester).glossInterlinear, isTrue);
    expect(verseRow(tester).interlinearPositions, isEmpty);

    // By default a tap reveals its whole verse rather than opening the word's
    // details, and a tap on any of its words hides it again.
    verseRow(tester).onWordTap('מלה', null, 3, '');
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, isNull);
    expect(rust.wordRequests, isEmpty);
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 2)).interlinearPositions,
      isEmpty,
    );
    verseRow(tester).onWordTap('מלה', null, 5, '');
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, isEmpty);
    verseRow(tester).onWordTap('מלה', null, 3, '');
    await tester.pump();

    // Leaving rapid reading forgets what it revealed and returns to the
    // interlinear as it was: hidden.
    await tapToggle(tester, 'reader-rapid-toggle');
    expect(verseRow(tester).interlinearPositions, isEmpty);

    // Showing the interlinear from rapid reading leaves it.
    await tapToggle(tester, 'reader-rapid-toggle');
    await tapToggle(tester, 'reader-interlinear-toggle');
    expect(verseRow(tester).interlinearPositions, isNull);
    verseRow(tester).onWordTap('מלה', null, 3, '');
    await tester.pump();
    expect(rust.wordRequests, hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('rapid_reading'), isFalse);
    expect(prefs.getBool('show_interlinear'), isTrue);
  });

  testWidgets('an old three-way view choice is carried over', (tester) async {
    final rust = await _pumpReader(
      tester,
      chapter: 1,
      prefs: {'reader_view': 'plain', 'gloss_interlinear': true},
    );
    rust.deliverAll();
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, isEmpty);
    await tapToggle(tester, 'reader-rapid-toggle');
    await tapToggle(tester, 'reader-rapid-toggle');
    expect(verseRow(tester).interlinearPositions, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_interlinear'), isFalse);
    expect(prefs.containsKey('reader_view'), isFalse);
  });

  testWidgets('rapid reading can reveal single words', (tester) async {
    SharedPreferences.setMockInitialValues({
      'book': 0,
      'chapter': 1,
      'gloss_interlinear': true,
      'reader_view': 'rapid',
      'rapid_reveal': 'word',
    });
    final rust = _FakeRust();
    await tester.pumpWidget(
      MaterialApp(
        home: BibleReaderPage(
          sendChapterRequest: rust.onRequest,
          sendStudyStateRequest: rust.onStudyRequest,
          saveStudyState: rust.onStudySave,
          sendWordInfoRequest: rust.onWordInfo,
          sendWordOccurrencesRequest: rust.onOccurrences,
          sendVerseTextsRequest: rust.onVerseTexts,
        ),
      ),
    );
    await tester.pump();
    rust.deliverAll();
    await tester.pump();

    // Each tap shows or hides its own word's interlinear.
    expect(verseRow(tester).interlinearPositions, isEmpty);
    verseRow(tester).onWordTap('מלה', null, 3, '');
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, {3});
    verseRow(tester).onWordTap('מלה', null, 4, '');
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, {3, 4});
    verseRow(tester).onWordTap('מלה', null, 3, '');
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, {4});
    verseRow(tester).onWordTap('מלה', null, 4, '');
    await tester.pump();
    expect(verseRow(tester).interlinearPositions, isEmpty);
    expect(rust.wordRequests, isEmpty);
  });
}

/// Frames enough for a page turn, which takes several: a pump that settles
/// never ends while a panel shows its loading spinner.
Future<void> _turnPage(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void syntaxTests() {
  testWidgets('colouring syntax roles asks for the chapter\'s trees', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(
      tester,
      const Size(1366, 744),
      prefs: {'syntax_roles': true},
    );
    final request = rust.syntaxRequests.single;
    expect((request.book, request.chapter), (1, 1));
    expect((request.firstVerse, request.lastVerse), (0, 0));

    // Verse 1's second word is the subject, and a clause starts at its
    // fourth.
    assignRustSignal['SyntaxTrees']!(
      SyntaxTrees(
        requestId: request.requestId,
        book: 1,
        chapter: 1,
        verses: [
          VerseSyntaxEntry(
            verse: 1,
            nodes: [
              node(-1),
              node(0, kind: 'cl'),
              node(1, role: 'v', position: 0),
              node(1, role: 's', position: 1),
              node(0, kind: 'cl'),
              node(4, role: 'v', position: 3),
            ],
          ),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    // The reply reaches the stream a microtask later.
    await tester.pump();
    final row = tester.widget<VerseRow>(_verse(1, 1, 1));
    expect(row.syntaxMarks!.roles, {0: 'v', 1: 's', 3: 'v'});
    expect(row.syntaxMarks!.clauseStarts, {3});
    expect(tester.widget<VerseRow>(_verse(1, 1, 2)).syntaxMarks!.roles, {});
    // The chapter is asked for once, not once per row.
    expect(rust.syntaxRequests, hasLength(1));
  });

  testWidgets('without the setting the reader asks for no trees', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(tester, const Size(1366, 744));
    expect(rust.syntaxRequests, isEmpty);
    expect(tester.widget<VerseRow>(_verse(1, 1, 1)).syntaxMarks, isNull);
  });

  testWidgets('a verse number\'s menu opens its syntax', (tester) async {
    final rust = await _pumpWorkspace(tester, const Size(1366, 744));
    await tester.longPress(find.byKey(const ValueKey('verse-number-2')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Syntax'));
    // The sheet opens on its loading spinner, which never settles.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SyntaxPanel), findsOneWidget);
    final request = rust.syntaxRequests.single;
    expect(
      (request.book, request.chapter, request.firstVerse, request.lastVerse),
      (1, 1, 2, 2),
    );
    expect(tester.takeException(), isNull);
  });
}

void translationTests() {
  testWidgets('the text toggle cycles Hebrew, English and side by side', (
    tester,
  ) async {
    final rust = await _pumpWorkspace(tester, const Size(1366, 744));
    expect(rust.translationRequests, isEmpty);
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 1)).readerText,
      ReaderText.source,
    );

    await tester.tap(find.byKey(const ValueKey('reader-text-toggle')));
    await tester.pump();
    final row = tester.widget<VerseRow>(_verse(1, 1, 1));
    expect(row.readerText, ReaderText.english);
    expect(row.translationPending, isTrue);
    final request = rust.translationRequests.single;
    expect((request.book, request.chapter), (1, 1));

    TranslationWordEntry at(int verse, int position) =>
        TranslationWordEntry(chapter: 1, verse: verse, position: position);
    assignRustSignal['ChapterTranslation']!(
      ChapterTranslation(
        requestId: request.requestId,
        book: 1,
        chapter: 1,
        verses: [
          VerseTranslationEntry(
            verse: 1,
            spans: [
              TranslationSpanEntry(
                text: 'Book',
                supplied: false,
                words: [at(1, 0)],
              ),
              const TranslationSpanEntry(text: ' ', supplied: false, words: []),
              // Renders a word of the next verse.
              TranslationSpanEntry(
                text: 'chapter',
                supplied: false,
                words: [at(2, 1)],
              ),
            ],
          ),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    final english = tester.widget<VerseRow>(_verse(1, 1, 1));
    expect(english.translationPending, isFalse);
    expect(english.translation!.map((s) => s.text).join(), 'Book chapter');
    // A verse the translation lacks keeps its source text.
    expect(tester.widget<VerseRow>(_verse(1, 1, 2)).translation, isNull);
    // The chapter is asked for once, not once per row.
    expect(rust.translationRequests, hasLength(1));

    // An English word opens the Hebrew word it renders, in its own verse.
    english.onTranslationWordTap!(at(2, 1));
    await tester.pump();
    final word = rust.wordRequests.last;
    expect(word.word, 'פרק1');
    expect((word.chapter, word.verse, word.position), (1, 2, 1));

    await tester.tap(find.byKey(const ValueKey('reader-text-toggle')));
    await tester.pump();
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 1)).readerText,
      ReaderText.parallel,
    );
    await tester.tap(find.byKey(const ValueKey('reader-text-toggle')));
    await tester.pump();
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 1)).readerText,
      ReaderText.source,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the text mode is remembered', (tester) async {
    final rust = await _pumpWorkspace(
      tester,
      const Size(1366, 744),
      prefs: {'reader_text': 'parallel'},
    );
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 1)).readerText,
      ReaderText.parallel,
    );
    expect(rust.translationRequests.single.chapter, 1);
  });
}

void compactViewMenuTests() {
  testWidgets('a narrow reader keeps rapid reading and gathers the rest', (
    tester,
  ) async {
    await _pumpWorkspace(tester, const Size(320, 800));
    expect(find.byKey(const ValueKey('reader-rapid-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-text-toggle')), findsNothing);
    expect(
      find.byKey(const ValueKey('reader-interlinear-toggle')),
      findsNothing,
    );
    expect(find.byTooltip('Back'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reader-view-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Cross references'), findsOneWidget);
    expect(find.text('Forward'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<Object>, 'Side by side'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 1)).readerText,
      ReaderText.parallel,
    );

    await tester.tap(find.byKey(const ValueKey('reader-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<Object>, 'Interlinear'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<VerseRow>(_verse(1, 1, 1)).interlinearPositions,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wide reader shows every action in its bar', (tester) async {
    await _pumpWorkspace(tester, const Size(1366, 744));
    for (final key in [
      'reader-rapid-toggle',
      'reader-interlinear-toggle',
      'reader-text-toggle',
      'reader-cross-references',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const ValueKey('reader-view-menu')), findsNothing);
  });
}
