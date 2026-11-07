import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/lexicon/semitic_sounds_page.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('lays out the sounds, diagrams and examples ($brightness)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const SemiticSoundsPage(),
        ),
      );
      expect(find.text('Semitic sound correspondences'), findsOneWidget);
      // Every older consonant has a row; ḏ is one Hebrew and Aramaic split.
      expect(find.text('ḏ (often d)'), findsOneWidget);
      expect(find.text('Old Aram. ש'), findsNWidgets(2));
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('TO VERIFY: ʿarabūn'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TO VERIFY: ʿarabūn'), findsOneWidget);
      // No passage links without somewhere to go.
      expect(find.text('Dan 2:32'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a verse link goes to the passage', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (int, int, int)? went;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => SemiticSoundsPage.open(
              context,
              onNavigateToPassage: (b, c, v) => went = (b, c, v),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final link = find.text('Ezra 6:9');
    await tester.scrollUntilVisible(
      link,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(went, (35, 6, 9));
    expect(find.byType(SemiticSoundsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
