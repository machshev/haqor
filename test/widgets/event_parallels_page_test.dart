import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/event_parallels_page.dart';

ThematicTarget _span(int book, int c, int v, int lc, int lv) => ThematicTarget(
  book: book,
  chapter: c,
  verse: v,
  lastChapter: lc,
  lastVerse: lv,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The feeding of the five thousand, John first to show they are ordered.
  final passages = [
    _span(43, 6, 1, 6, 3),
    _span(40, 14, 13, 14, 14),
    _span(41, 6, 32, 6, 33),
  ];

  Future<(List<StudyPassage>, List<GetVerseTexts>)> open(
    WidgetTester tester,
    Size size,
  ) async {
    final opened = <StudyPassage>[];
    final sent = <GetVerseTexts>[];
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
              sendVerseTextsRequest: sent.add,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return (opened, sent);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  test('a passage of chapters runs through each to its last verse', () {
    final verses = parallelVerses(_span(42, 1, 79, 2, 2));
    expect(verses, [(1, 79), (1, 80), (2, 1), (2, 2)]);
  });

  testWidgets('wide, the accounts stand side by side in canonical order', (
    tester,
  ) async {
    final (opened, sent) = await open(tester, const Size(1200, 800));
    expect(find.text('3 accounts'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    final xs = [
      for (var i = 0; i < 3; i++)
        tester.getTopLeft(key('parallels-column-$i')).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(find.text('Matthew 14:13–14'), findsOneWidget);
    expect(key('parallels-verse-2-6:3'), findsOneWidget);
    // Every verse shown asked for, in one round-trip.
    expect(sent, hasLength(1));
    expect(sent.single.refs, hasLength(7));

    await tester.tap(key('parallels-heading-0'));
    await tester.pumpAndSettle();
    expect(opened.single.bookIndex, 39);
    expect(opened.single.reference, '14:13–14');
  });

  testWidgets('narrow, each account is a tab of its own', (tester) async {
    final (opened, _) = await open(tester, const Size(400, 800));
    expect(find.byType(TabBar), findsOneWidget);
    expect(key('parallels-column-0'), findsOneWidget);
    expect(key('parallels-column-2'), findsNothing);
    await tester.tap(key('parallels-tab-2'));
    await tester.pumpAndSettle();
    expect(find.text('John 6:1–3'), findsOneWidget);
    await tester.tap(key('parallels-verse-2-6:2'));
    await tester.pumpAndSettle();
    expect(opened.single.bookIndex, 42);
    expect(opened.single.reference, '6:2');
  });
}
