import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/verse_row.dart';

void main() {
  test('standalone paseq does not consume an interlinear gloss', () {
    final words = 'וַיִּקְרָא אֱלֹהִים ׀ לָאוֹר יּוֹם'.split(' ');

    expect(verseGlossPositions(words), [0, 1, null, 2, 3]);
  });

  test('maqaf is its own interlinear item', () {
    final words = 'עַל־ פְּנֵי'.split(' ');

    expect(interlinearVerseWords(words), ['עַל', '־', 'פְּנֵי']);
    expect(verseGlossPositions(interlinearVerseWords(words)), [0, null, 1]);
  });

  test('Syriac words consume interlinear gloss positions', () {
    final words = 'ܟܬܒܐ ܕܝܫܘܥ ܡܫܝܚܐ'.split(' ');

    expect(verseGlossPositions(words), [0, 1, 2]);
  });

  test('recognises Yahweh with or without an attached particle', () {
    expect(isYahweh('יְהוָה'), isTrue);
    expect(isYahweh('יַהְוֶה'), isTrue);
    expect(isYahweh('וַיהוָה'), isTrue);
    expect(isYahweh('לַיהוָה'), isTrue);
    expect(isYahweh('אַבְרָהָם'), isFalse);
    expect(isYahweh('חָכְמָה'), isFalse);
  });

  testWidgets('standalone punctuation cannot shift Yahweh highlighting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: const VerseEntry(
              verse: 1,
              text: 'דָבָר ׀ יְהוָה חָכְמָה',
              glosses: [],
              names: [],
            ),
            isSelected: false,
            hebrewNumerals: true,
            highlightProperNames: true,
            onTap: () {},
            onWordTap: (_, _, _) {},
          ),
        ),
      ),
    );

    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    final wisdom = text.children!.whereType<TextSpan>().firstWhere(
      (span) => span.text == 'חָכְמָה',
    );

    expect(wisdom.style!.color, isNot(const Color(0xFFB8860B)));
  });

  testWidgets('cantillation can be hidden while vowel points remain', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: const VerseEntry(
              verse: 1,
              text: 'בְּרֵאשִׁ֖ית',
              glosses: [],
              names: [],
            ),
            isSelected: false,
            hebrewNumerals: true,
            showCantillation: false,
            onTap: () {},
            onWordTap: (_, _, _) {},
          ),
        ),
      ),
    );

    expect(find.text('בְּרֵאשִׁית'), findsOneWidget);
    expect(find.text('בְּרֵאשִׁ֖ית'), findsNothing);
  });

  testWidgets('word taps carry the lexical occurrence position', (
    tester,
  ) async {
    (String, String?, int?)? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: const VerseEntry(
              verse: 1,
              text: 'דָבָר ׀ יְהוָה',
              glosses: ['word', 'Yahweh'],
              names: [],
            ),
            isSelected: false,
            hebrewNumerals: true,
            glossInterlinear: true,
            onTap: () {},
            onWordTap: (word, gloss, position) {
              tapped = (word, gloss, position);
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('יְהוָה'));
    expect(tapped, ('יְהוָה', 'Yahweh', 1));
  });

  testWidgets('interlinear continuation lines start at the visual right edge', (
    tester,
  ) async {
    const words = [
      'אֶחָד',
      'שְׁנַיִם',
      'שָׁלוֹשׁ',
      'אַרְבַּע',
      'חָמֵשׁ',
      'שֵׁשׁ',
      'שֶׁבַע',
      'שְׁמוֹנֶה',
    ];
    const glosses = [
      'one',
      'two',
      'three',
      'four',
      'five',
      'six',
      'seven',
      'eight',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 310,
            child: VerseRow(
              entry: VerseEntry(
                verse: 1,
                text: words.join(' '),
                glosses: glosses,
                names: const [],
              ),
              isSelected: false,
              hebrewNumerals: true,
              showCantillation: true,
              glossInterlinear: true,
              onTap: () {},
              onWordTap: (_, _, _) {},
            ),
          ),
        ),
      ),
    );

    final bounds = [for (final word in words) tester.getRect(find.text(word))];
    final firstLineTop = bounds.map((rect) => rect.top).reduce(min);
    final lastLineTop = bounds.map((rect) => rect.top).reduce(max);
    final firstLineRight = bounds
        .where((rect) => rect.top == firstLineTop)
        .map((rect) => rect.right)
        .reduce(max);
    final lastLineRight = bounds
        .where((rect) => rect.top == lastLineTop)
        .map((rect) => rect.right)
        .reduce(max);

    expect(lastLineTop, greaterThan(firstLineTop));
    expect(lastLineRight, closeTo(firstLineRight, 0.01));
  });
}
