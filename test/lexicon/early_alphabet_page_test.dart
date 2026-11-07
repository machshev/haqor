import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/lexicon/early_alphabet_page.dart';

void main() {
  test('has the 22 letters in order, each with an exemplar', () {
    expect(
      petrovichLetters.map((l) => l.letter).join(),
      'אבגדהוזחטיכלמנסעפצקרשת',
    );
    for (final l in petrovichLetters) {
      expect(l.signs, isNotEmpty, reason: l.name);
      expect(l.acrophones, isNotEmpty, reason: l.name);
      // The Iron Age form is the Phoenician letter in the same place.
      expect(
        l.ironAge.runes.single - 0x10900,
        petrovichLetters.indexOf(l),
        reason: l.name,
      );
    }
  });

  for (final width in [380.0, 1200.0]) {
    testWidgets('lays out every letter at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: EarlyAlphabetPage()));
      expect(find.text('Hebrew’s first letters'), findsOneWidget);
      expect(find.text('F1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('M42'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Tav'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
