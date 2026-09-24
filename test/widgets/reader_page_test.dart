import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/reader_page.dart';
import 'package:haqor/src/study_workspace.dart' as study;
import 'package:haqor/src/widgets/verse_row.dart';
import 'package:haqor/src/widgets/study_workspace_panel.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

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
}) async {
  SharedPreferences.setMockInitialValues({
    'book': book,
    'chapter': chapter,
    'english_book_names': englishBookNames,
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

  testWidgets('initial load shows the requested chapter with its divider', (
    tester,
  ) async {
    final rust = await _pumpReader(tester, chapter: 5);
    expect(rust.studyRequests, hasLength(1));
    expect(_verse(1, 5, 1), findsOneWidget);
    expect(find.text('Bereshit 5'), findsOneWidget);
    rust.deliverAll(); // prefetched neighbours
    await tester.pump();
  });

  testWidgets('uses saved English book names in reader labels', (tester) async {
    final rust = await _pumpReader(tester, chapter: 5, englishBookNames: true);
    expect(find.text('Genesis'), findsOneWidget);
    expect(find.text('Genesis 5'), findsOneWidget);
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

  testWidgets('mobile hides a lone tab and swipes between reader tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rust = await _pumpReader(tester, chapter: 5);

    expect(find.byType(InputChip), findsNothing);
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
    expect(find.byType(InputChip), findsNothing);
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
      found: true,
      word: current().word,
      root: '',
      gloss: 'appoint',
      article: false,
      vavCon: false,
      bdbEntries: const [],
      sedraEntries: const [],
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
      final switcher = find.byType(SegmentedButton<bool>);
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
      expect(tester.widget<SegmentedButton<bool>>(switcher).selected, {true});
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

    final switcher = find.byType(SegmentedButton<bool>);
    await tester.tap(
      find.descendant(of: switcher, matching: find.text('Study')),
    );
    await tester.pump();
    expect(find.byType(StudyWorkspacePanel), findsOneWidget);
    expect(find.byType(WordInfoSheet), findsNothing);
    expect(tester.widget<SegmentedButton<bool>>(switcher).selected, {false});

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
    expect(tester.widget<SegmentedButton<bool>>(switcher).selected, {true});
    expect(tester.takeException(), isNull);
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
}
