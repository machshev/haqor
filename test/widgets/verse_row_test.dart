import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/verse_row.dart';

void main() {
  test('standalone paseq does not consume an interlinear gloss', () {
    final words = 'וַיִּקְרָא אֱלֹהִים ׀ לָאוֹר יּוֹם'.split(' ');

    expect(verseGlossPositions(words), [0, 1, null, 2, 3]);
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
            ),
            isSelected: false,
            hebrewNumerals: true,
            showCantillation: false,
            onTap: () {},
            onWordTap: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('בְּרֵאשִׁית'), findsOneWidget);
    expect(find.text('בְּרֵאשִׁ֖ית'), findsNothing);
  });
}
