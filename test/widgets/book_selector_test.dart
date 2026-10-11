import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bible_data.dart';
import 'package:haqor/src/widgets/book_selector.dart';

void main() {
  testWidgets('English book picker uses compact English abbreviations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BookSelectorSheet(currentIndex: 0, useEnglishBookNames: true),
        ),
      ),
    );

    expect(find.text('Gen'), findsOneWidget);
    expect(find.text('Genesis'), findsNothing);
    expect(find.text('1 Thess'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('1 Thess'),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .width,
      44,
    );
  });

  testWidgets('read in Greek, the New Testament is named from the Greek', (
    tester,
  ) async {
    addTearDown(() => greekBookNames = false);
    Future<void> pump() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookSelectorSheet(
            key: ValueKey(greekBookNames),
            currentIndex: 39,
            useEnglishBookNames: false,
          ),
        ),
      ),
    );

    await pump();
    expect(find.text('Brit Khadasha'), findsOneWidget);
    expect(find.text('Mrq'), findsOneWidget);

    greekBookNames = true;
    await pump();
    expect(find.text('Kainē Diathēkē'), findsOneWidget);
    expect(find.text('Ἡ Καινὴ Διαθήκη'), findsOneWidget);
    expect(find.text('Mar'), findsOneWidget);
    expect(find.text('Mrq'), findsNothing);
    expect(find.byTooltip('Markos  Μάρκος'), findsOneWidget);
    // The Hebrew Bible keeps its names.
    expect(find.text('Torah'), findsOneWidget);
    expect(find.byTooltip('Bereshit  בְּרֵאשִׁית'), findsOneWidget);
  });
}
