import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/app_settings.dart';
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
              morphologies: [],
              names: [],
              ketivs: [],
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
              morphologies: [],
              names: [],
              ketivs: [],
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
              morphologies: ['noun singular', 'noun singular'],
              names: [],
              ketivs: [],
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

  testWidgets('study highlights stay occurrence-specific and show notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: const VerseEntry(
              verse: 4,
              text: 'מִלָּה מִלָּה',
              glosses: [],
              morphologies: [],
              names: [],
              ketivs: [],
            ),
            isSelected: false,
            hebrewNumerals: false,
            studyHighlighted: true,
            studyNote: true,
            highlightedWordPositions: {1},
            onTap: () {},
            onWordTap: (_, _, _) {},
          ),
        ),
      ),
    );

    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    final words = text.children!
        .whereType<TextSpan>()
        .where((span) => span.text == 'מִלָּה')
        .toList();

    expect(words, hasLength(2));
    expect(words.first.style!.backgroundColor, isNull);
    expect(words.last.style!.backgroundColor, isNotNull);
    expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, isNot(Colors.transparent));
  });

  testWidgets('morphology sits below the gloss with visible spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: const VerseEntry(
              verse: 1,
              text: 'דָבָר',
              glosses: ['word'],
              morphologies: ['noun singular'],
              names: [],
              ketivs: [],
            ),
            isSelected: false,
            hebrewNumerals: true,
            glossInterlinear: true,
            morphologyInterlinear: true,
            onTap: () {},
            onWordTap: (_, _, _) {},
          ),
        ),
      ),
    );

    final glossRect = tester.getRect(find.text('word'));
    final morphologyRect = tester.getRect(find.text('N sg'));

    expect(morphologyRect.top, greaterThan(glossRect.bottom));
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
                morphologies: const [],
                names: const [],
                ketivs: const [],
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

  group('ketiv', () {
    // 2 Sam 12:31 in miniature: the qere בַּמַּלְבֵּן is the third word, and
    // במלכן is what stands written in its place.
    const words = 'וְהֶעֱבִיר אוֹתָם בַּמַּלְבֵּן וְכֵן';
    const ketiv = KetivEntry(position: 2, span: 1, text: 'במלכן');

    VerseEntry entryWith(List<KetivEntry> ketivs) => VerseEntry(
      verse: 31,
      text: words,
      glosses: const [],
      morphologies: const [],
      names: const [],
      ketivs: ketivs,
    );

    Future<void> pump(
      WidgetTester tester,
      KetivDisplay display, {
      VerseEntry? entry,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerseRow(
            entry: entry ?? entryWith(const [ketiv]),
            isSelected: false,
            hebrewNumerals: true,
            ketivDisplay: display,
            onTap: () {},
            onWordTap: (_, _, _) {},
          ),
        ),
      ),
    );

    test('a reading anchors after the last word it stands behind', () {
      final tokens = words.split(' ');
      expect(
        ketivAnchors(tokens, const [ketiv]).keys,
        [2],
        reason: 'a one-word reading anchors on that word',
      );
      expect(
        ketivAnchors(tokens, const [
          KetivEntry(position: 1, span: 2, text: 'א ב'),
        ]).keys,
        [2],
        reason: 'a two-word reading follows the second of them',
      );
    });

    test('a reading that is never read anchors before its word', () {
      final anchors = ketivAnchors(words.split(' '), const [
        KetivEntry(position: 2, span: 0, text: 'אם'),
      ]);
      expect(anchors[2]!.single.before, isTrue);
    });

    test('a standalone paseq does not shift the anchor', () {
      // The paseq is displayed but takes no lexical position, so the reading
      // still lands on the word the core counted.
      final anchors = ketivAnchors(
        'וְהֶעֱבִיר ׀ אוֹתָם בַּמַּלְבֵּן'.split(' '),
        const [ketiv],
      );
      expect(anchors.keys, [3], reason: 'token 3 is the third lexical word');
    });

    testWidgets('off shows nothing of the written form', (tester) async {
      await pump(tester, KetivDisplay.hidden);

      expect(find.textContaining('במלכן'), findsNothing);
      expect(find.text('בַּמַּלְבֵּן'), findsNothing);
    });

    testWidgets('superscript raises the written form off the baseline', (
      tester,
    ) async {
      await pump(tester, KetivDisplay.superscript);

      final ketivRect = tester.getRect(find.text('במלכן'));
      final verseRect = tester.getRect(find.byType(SelectableText));

      expect(
        ketivRect.height,
        lessThan(verseRect.height),
        reason: 'set smaller than the text it annotates',
      );
      // Raised, so it sits in the upper part of the line rather than on the
      // reading baseline near the bottom of it.
      expect(
        ketivRect.center.dy,
        lessThan(verseRect.center.dy),
        reason: 'a superscript rides above the middle of the line',
      );
      // Raised off the *baseline*, though — not pinned to the top of the line
      // box. `PlaceholderAlignment.top` passes every other assertion here while
      // looking wrong, so this is the one that tells them apart: it would put
      // the letters flush with the top of the line.
      expect(
        ketivRect.top,
        greaterThan(verseRect.top + 3),
        reason: 'a superscript is lifted off the baseline, not top-aligned',
      );
    });

    testWidgets('brackets keep the written form in the line of reading', (
      tester,
    ) async {
      await pump(tester, KetivDisplay.brackets);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.textSpan?.toPlainText() ?? '').contains('[במלכן]'),
        ),
        findsOne,
      );
    });

    testWidgets('the marker hides the written form until tapped', (
      tester,
    ) async {
      await pump(tester, KetivDisplay.marker);

      expect(find.text('במלכן'), findsNothing);
      await tester.tap(find.text('⊙'));
      await tester.pump();
      expect(find.text('[במלכן]'), findsOne);

      // Tapping again puts it away, so nothing is left stranded open.
      await tester.tap(find.text('[במלכן]'));
      await tester.pump();
      expect(find.text('[במלכן]'), findsNothing);
      expect(find.text('⊙'), findsOne);
    });

    testWidgets('a verse with no reading is left alone', (tester) async {
      await pump(tester, KetivDisplay.brackets, entry: entryWith(const []));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.textSpan?.toPlainText() ?? '').contains('['),
        ),
        findsNothing,
      );
    });
  });
}
