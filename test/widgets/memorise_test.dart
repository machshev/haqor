import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/memorise/memorise_charts.dart';
import 'package:haqor/src/memorise/memorise_drill.dart';
import 'package:haqor/src/memorise/memorise_page.dart';

MemorySegment _segment(int verse, List<String> words, {int line = 0}) =>
    MemorySegment(
      chapter: 23,
      verse: verse,
      line: line,
      lineCount: 1,
      words: [
        for (var i = 0; i < words.length; i++)
          MemoryWord(
            text: words[i],
            gloss: 'g$verse.$i',
            translit: 't$verse.$i',
          ),
      ],
    );

MemoryCard _card(String purpose, List<MemorySegment> segments) => MemoryCard(
  passageId: 'p',
  book: 27,
  purpose: purpose,
  title: 'Title',
  prompt: 'Picture the scene.',
  segments: segments,
  cue: '…הַמָּיִם',
  targetChapter: 23,
  targetVerse: segments.last.verse,
  step: 1,
  stepCount: 4,
  isNew: false,
  position: 1,
  total: 6,
  section: 1,
  sectionCount: 2,
);

typedef _Submitted = List<(int, List<(int, int, int)>)>;

Future<_Submitted> _pump(WidgetTester tester, MemoryCard card) async {
  final submitted = <(int, List<(int, int, int)>)>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MemoryRecitalView(
          card: card,
          onSubmit: (grade, verses) => submitted.add((grade, verses)),
        ),
      ),
    ),
  );
  await tester.pump();
  return submitted;
}

bool _visible(WidgetTester tester, String word) {
  final opacity = find.ancestor(
    of: find.text(word),
    matching: find.byType(Opacity),
  );
  return opacity.evaluate().isEmpty ||
      tester.widget<Opacity>(opacity.first).opacity > 0;
}

void main() {
  test('a check suggests a grade from the share of words missed', () {
    expect(suggestedMemoryGrade(0, 8), 2);
    expect(suggestedMemoryGrade(2, 8), 1);
    expect(suggestedMemoryGrade(3, 8), 0);
    expect(suggestedMemoryGrade(1, 2), 1, reason: 'one slip is never Forgot');
  });

  test('each verse is graded on its own misses, shifted by the choice', () {
    // Verse 1 perfect, verse 2 mostly forgotten; overall suggestion Forgot.
    expect(
      memoryVerseGrades(
        missedPerVerse: [0, 3],
        wordsPerVerse: [4, 4],
        chosen: 0,
      ),
      [2, 0],
    );
    // Choosing Hard over the suggested Forgot lifts both a step.
    expect(
      memoryVerseGrades(
        missedPerVerse: [0, 3],
        wordsPerVerse: [4, 4],
        chosen: 1,
      ),
      [3, 1],
    );
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
            needsShaping: false,
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

  testWidgets('a read card shows every word with its help', (tester) async {
    final submitted = await _pump(
      tester,
      _card('read', [
        _segment(1, ['יְהוָה', 'רֹעִי']),
      ]),
    );
    expect(_visible(tester, 'רֹעִי'), isTrue);
    expect(find.text('t1.1'), findsOneWidget);
    expect(find.text('g1.1'), findsOneWidget);
    expect(find.text('Picture the scene.'), findsOneWidget);
    expect(find.text('…הַמָּיִם'), findsOneWidget, reason: 'the cue line');
    await tester.tap(find.text('I have read it aloud'));
    expect(submitted.single.$1, 2);
    expect(submitted.single.$2, [(23, 1, 2)]);
  });

  testWidgets('a recital hides every word and reveals them in order', (
    tester,
  ) async {
    final submitted = await _pump(
      tester,
      _card('chain', [
        _segment(1, ['יְהוָה', 'רֹעִי', 'לֹא', 'אֶחְסָר']),
        _segment(2, ['בִּנְאוֹת', 'דֶּשֶׁא', 'יַרְבִּיצֵנִי', 'עַל']),
      ]),
    );
    for (final w in ['יְהוָה', 'רֹעִי', 'בִּנְאוֹת']) {
      expect(_visible(tester, w), isFalse, reason: 'all hidden, no gaps');
    }
    expect(find.text('Forgot'), findsNothing);

    // Recite verse 1 word by word; tapping the next gap works too.
    await tester.tap(find.text('Next word'));
    await tester.pump();
    expect(_visible(tester, 'יְהוָה'), isTrue);
    expect(_visible(tester, 'רֹעִי'), isFalse);
    await tester.tap(find.text('רֹעִי'));
    await tester.pump();
    expect(_visible(tester, 'רֹעִי'), isTrue);
    await tester.tap(find.text('Next word'));
    await tester.tap(find.text('Next word'));
    await tester.pump();
    // Verse 2: miss the first word, then reveal the rest.
    await tester.tap(find.text('Missed it'));
    await tester.pump();
    expect(_visible(tester, 'בִּנְאוֹת'), isTrue);
    await tester.tap(find.text('Reveal the rest'));
    await tester.pump();
    expect(_visible(tester, 'עַל'), isTrue);
    expect(find.text('1 missed — tap a word to change it.'), findsOneWidget);

    // One slip in eight words suggests Hard overall; verse 1 was perfect.
    final hard = find.ancestor(
      of: find.text('Hard'),
      matching: find.byType(FilledButton),
    );
    expect(hard, findsOneWidget);
    await tester.tap(find.text('Hard'));
    expect(submitted.single.$1, 1);
    expect(submitted.single.$2, [(23, 1, 2), (23, 2, 1)]);
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
