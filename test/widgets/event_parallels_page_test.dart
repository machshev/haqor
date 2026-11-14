import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/app_settings.dart' show ReaderText;
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/event_parallels_page.dart';
import 'package:haqor/src/widgets/verse_row.dart';

ThematicTarget _span(int book, int c, int v, int lc, int lv) => ThematicTarget(
  book: book,
  chapter: c,
  verse: v,
  lastChapter: lc,
  lastVerse: lv,
);

/// What the page asks of Rust, answered when the test says.
class _FakeRust {
  final chapters = <GetChapter>[];
  final translations = <GetChapterTranslation>[];

  void answerChapters() {
    for (final r in chapters) {
      assignRustSignal['ChapterText']!(
        ChapterText(
          book: r.book,
          chapter: r.chapter,
          syriac: r.syriac,
          greek: r.greek,
          includeGlosses: r.includeGlosses,
          includeMorphology: r.includeMorphology,
          includeNames: r.includeNames,
          includeRoots: r.includeRoots,
          verses: [
            for (var v = 1; v <= 40; v++)
              VerseEntry(
                verse: v,
                text: 'ספר${r.book} פרק${r.chapter} פסוק$v',
                glosses: const [],
                morphologies: const [],
                names: const [],
                roots: const [],
                ketivs: const [],
                crossReferenceScores: const [],
              ),
          ],
        ).bincodeSerialize(),
        Uint8List(0),
      );
    }
  }

  void answerTranslations() {
    for (final r in translations) {
      assignRustSignal['ChapterTranslation']!(
        ChapterTranslation(
          requestId: r.requestId,
          book: r.book,
          chapter: r.chapter,
          verses: [
            for (var v = 1; v <= 40; v++)
              VerseTranslationEntry(
                verse: v,
                spans: [
                  TranslationSpanEntry(
                    text: 'English ${r.book} ${r.chapter}:$v',
                    supplied: false,
                    words: const [],
                  ),
                ],
              ),
          ],
        ).bincodeSerialize(),
        Uint8List(0),
      );
    }
  }
}

void main() {
  // The original alone, no interlinear, the NT in Aramaic: as a reader
  // might be set.
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'reader_text': 'source',
      'show_interlinear': false,
    }),
  );

  // The feeding of the five thousand, John first to show they are ordered.
  final passages = [
    _span(43, 6, 1, 6, 3),
    _span(40, 14, 13, 14, 14),
    _span(41, 6, 32, 6, 33),
  ];

  Future<(List<StudyPassage>, _FakeRust)> open(
    WidgetTester tester,
    Size size,
  ) async {
    final opened = <StudyPassage>[];
    final rust = _FakeRust();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => EventParallelsPage.open(
              context,
              title: 'Feeding of Five Thousand',
              passages: passages,
              useEnglishBookNames: true,
              onOpenPassage: opened.add,
              sendChapterRequest: rust.chapters.add,
              sendTranslationRequest: rust.translations.add,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    rust.answerChapters();
    await tester.pumpAndSettle();
    return (opened, rust);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  test('a passage of chapters runs through each to its last verse', () {
    final verses = parallelVerses(_span(42, 1, 79, 2, 2));
    expect(verses, [(1, 79), (1, 80), (2, 1), (2, 2)]);
  });

  testWidgets('wide, the accounts stand side by side in canonical order', (
    tester,
  ) async {
    final (opened, rust) = await open(tester, const Size(1200, 800));
    expect(find.text('3 accounts'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    final xs = [
      for (var i = 0; i < 3; i++)
        tester.getTopLeft(key('parallels-column-$i')).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(find.text('Matthew 14:13–14'), findsOneWidget);
    // A chapter asked for each account, in the reader's text.
    expect(rust.chapters.map((r) => (r.book, r.chapter)), {
      (40, 14),
      (41, 6),
      (43, 6),
    });
    expect(rust.translations, isEmpty);
    expect(
      tester.widget(key('parallels-verse-2-6:3')),
      isA<VerseRow>().having((r) => r.entry.verse, 'verse', 3),
    );
    // Not a phone: no turning.
    expect(key('parallels-landscape'), findsNothing);

    await tester.tap(key('parallels-heading-0'));
    await tester.pumpAndSettle();
    expect(opened.single.bookIndex, 39);
    expect(opened.single.reference, '14:13–14');
  });

  testWidgets('the original and English stand together where they fit', (
    tester,
  ) async {
    final (_, rust) = await open(tester, const Size(1800, 800));
    await tester.tap(key('parallels-text'));
    await tester.pumpAndSettle();
    await tester.tap(key('parallels-text-parallel'));
    await tester.pumpAndSettle();
    expect(rust.translations, hasLength(3));
    rust.answerTranslations();
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsNothing);
    final row = tester.widget<VerseRow>(key('parallels-verse-2-6:3'));
    expect(row.readerText, ReaderText.parallel);
    expect(row.translation!.single.text, 'English 43 6:3');
    expect(find.textContaining('English 43 6:3'), findsOneWidget);

    // Too narrow for three pairs, each is a tab.
    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
  });

  testWidgets('the interlinear and the Greek are asked for as switched', (
    tester,
  ) async {
    final (_, rust) = await open(tester, const Size(1200, 800));
    rust.chapters.clear();
    await tester.tap(key('parallels-interlinear'));
    await tester.pumpAndSettle();
    expect(rust.chapters, hasLength(3));
    expect(rust.chapters.every((r) => r.includeGlosses), isTrue);
    rust.answerChapters();
    await tester.pumpAndSettle();
    expect(
      tester.widget<VerseRow>(key('parallels-verse-0-14:13')).glossInterlinear,
      isTrue,
    );

    rust.chapters.clear();
    await tester.tap(key('parallels-nt-text'));
    await tester.pumpAndSettle();
    expect(rust.chapters, hasLength(3));
    expect(rust.chapters.every((r) => r.greek), isTrue);
    rust.answerChapters();
    await tester.pumpAndSettle();
    expect(
      tester.widget<VerseRow>(key('parallels-verse-0-14:13')).sourceDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('narrow, a phone turns to landscape and each account is a tab', (
    tester,
  ) async {
    final orientations = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final (opened, rust) = await open(tester, const Size(400, 800));
    expect(orientations, [
      ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
    ]);
    expect(find.byType(TabBar), findsOneWidget);
    expect(key('parallels-column-0'), findsOneWidget);
    expect(key('parallels-column-2'), findsNothing);

    // Turned back, and again.
    await tester.tap(key('parallels-landscape'));
    await tester.pumpAndSettle();
    expect(orientations.last, isEmpty);
    await tester.tap(key('parallels-landscape'));
    await tester.pumpAndSettle();

    await tester.tap(key('parallels-tab-2'));
    await tester.pumpAndSettle();
    rust.answerChapters();
    await tester.pumpAndSettle();
    expect(find.text('John 6:1–3'), findsOneWidget);
    await tester.tap(key('parallels-verse-2-6:2'));
    await tester.pumpAndSettle();
    expect(opened.single.bookIndex, 42);
    expect(opened.single.reference, '6:2');
    // Leaving lets the phone turn again.
    expect(orientations.last, isEmpty);
  });
}
