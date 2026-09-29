import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/memorise/memorise_charts.dart';
import 'package:haqor/src/memorise/memorise_drill.dart';
import 'package:haqor/src/memorise/memorise_page.dart';

MemoryCard _card({
  required int stage,
  List<bool>? hidden,
  List<String>? hints,
}) {
  const text = ['יְהוָה', 'רֹעִי', 'לֹא', 'אֶחְסָר׃'];
  return MemoryCard(
    passageId: 'p',
    book: 27,
    chapter: 23,
    verse: 1,
    stage: stage,
    words: [
      for (var i = 0; i < text.length; i++)
        MemoryWord(
          text: text[i],
          hidden: hidden?[i] ?? false,
          hint: hints?[i] ?? '',
          gloss: 'g$i',
          translit: 't$i',
        ),
    ],
    cue: '',
    translation: 'Yahweh my shepherd not I lack',
    isNew: stage == 0,
    isReview: false,
    position: 1,
    total: 6,
    dueRemaining: 0,
  );
}

Future<List<int>> _pumpDrill(WidgetTester tester, MemoryCard card) async {
  final grades = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MemoryVerseDrill(
          card: card,
          runThrough: false,
          runPosition: null,
          onGrade: grades.add,
        ),
      ),
    ),
  );
  return grades;
}

void main() {
  test('a check suggests a grade from the share of hidden words missed', () {
    expect(suggestedMemoryGrade(0, 8), 2);
    expect(suggestedMemoryGrade(2, 8), 1);
    expect(suggestedMemoryGrade(3, 8), 0);
    expect(suggestedMemoryGrade(1, 2), 1, reason: 'one slip is never Forgot');
    expect(suggestedMemoryGrade(2, 2), 0);
  });

  test(
    'passage references name one verse, a range, or a cross-chapter run',
    () {
      MemoryPassageEntry p(int sc, int sv, int ec, int ev) =>
          MemoryPassageEntry(
            id: 'x',
            book: 27,
            startChapter: sc,
            startVerse: sv,
            endChapter: ec,
            endVerse: ev,
            title: '',
            createdEpoch: 0,
            verses: const [],
            learnt: 0,
            mature: 0,
            due: 0,
            masteryPct: 0,
            lastStudiedEpoch: 0,
          );
      expect(
        passageReference(p(23, 1, 23, 6), useEnglish: true),
        'Psalms 23:1–6',
      );
      expect(
        passageReference(p(23, 4, 23, 4), useEnglish: true),
        'Psalms 23:4',
      );
      expect(
        passageReference(p(22, 30, 23, 2), useEnglish: true),
        'Psalms 22:30–23:2',
      );
    },
  );

  testWidgets('reading a new verse shows every word with its help', (
    tester,
  ) async {
    final grades = await _pumpDrill(tester, _card(stage: 0));
    expect(find.text('רֹעִי'), findsOneWidget);
    expect(find.text('t1'), findsOneWidget);
    expect(find.text('g1'), findsOneWidget);
    await tester.tap(find.text('I have read it aloud'));
    expect(grades, [2]);
  });

  testWidgets('peeking at a gap counts it as missed and lowers the grade', (
    tester,
  ) async {
    final grades = await _pumpDrill(
      tester,
      _card(
        stage: 3,
        hidden: [true, true, true, true],
        hints: ['י', 'ר', 'ל', 'א'],
      ),
    );
    // First letters are shown; the words themselves are laid out invisibly.
    expect(find.text('ר'), findsOneWidget);
    final hidden = tester.widget<Opacity>(
      find.ancestor(of: find.text('רֹעִי'), matching: find.byType(Opacity)),
    );
    expect(hidden.opacity, 0);

    // Peek at one word of four, then check: a quarter missed suggests Hard.
    await tester.tap(find.text('ר'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    expect(find.text('1 missed — tap a word to change it.'), findsOneWidget);
    final hard = tester.widget<FilledButton>(
      find.ancestor(of: find.text('Hard'), matching: find.byType(FilledButton)),
    );
    expect(hard, isNotNull);

    // Un-marking it after the check makes it word perfect again.
    await tester.tap(find.text('רֹעִי'));
    await tester.pump();
    expect(find.textContaining('Word perfect'), findsOneWidget);
    await tester.tap(find.text('Good'));
    expect(grades, [2]);
  });

  testWidgets('a chart shows a point\'s value when tapped', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: MiniChart(
              points: const [
                ChartPoint('a', 1),
                ChartPoint('b', 5, tooltip: 'b: 5 XP'),
                ChartPoint('c', 2),
              ],
              reference: 4,
              referenceLabel: 'goal',
            ),
          ),
        ),
      ),
    );
    expect(find.text('b: 5 XP'), findsNothing);
    // The middle third of the plot (right of the 32px axis gutter) is "b".
    final box = tester.getRect(find.byType(MiniChart));
    await tester.tapAt(Offset(box.left + 32 + (320 - 32) / 2, box.center.dy));
    await tester.pump();
    expect(find.text('b: 5 XP'), findsOneWidget);
  });
}
