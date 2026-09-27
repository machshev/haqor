import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/verse_row.dart';

void main() {
  Future<void> pumpVerse(WidgetTester tester, Set<int>? positions) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VerseRow(
              entry: const VerseEntry(
                verse: 1,
                text: 'דָבָר יְהוָה',
                glosses: ['word', 'Yahweh'],
                morphologies: ['noun singular', 'noun singular'],
                names: [],
                roots: [],
                ketivs: [],
                crossReferenceScores: [],
              ),
              isSelected: false,
              hebrewNumerals: false,
              glossInterlinear: true,
              morphologyInterlinear: true,
              interlinearPositions: positions,
              onTap: () {},
              onWordTap: (_, _, _, _) {},
            ),
          ),
        ),
      );

  testWidgets('shows the interlinear only beneath the given words', (
    tester,
  ) async {
    await pumpVerse(tester, null);
    expect(find.text('word'), findsOneWidget);
    expect(find.text('Yahweh'), findsOneWidget);

    await pumpVerse(tester, {1});
    expect(find.text('word'), findsNothing);
    expect(find.text('Yahweh'), findsOneWidget);
    expect(find.text('N sg'), findsOneWidget);

    // Nothing revealed sets the verse as running text.
    await pumpVerse(tester, const {});
    expect(find.text('Yahweh'), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
