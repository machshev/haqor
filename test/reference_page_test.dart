import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/lexicon/early_alphabet_page.dart';
import 'package:haqor/src/lexicon/semitic_sounds_page.dart';
import 'package:haqor/src/reference_page.dart';

void main() {
  testWidgets('lists the reference pages and opens them', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferencePage()));
    expect(find.text('Tutor reference'), findsOneWidget);
    expect(find.text('Semitic sounds'), findsOneWidget);
    expect(find.text('The earliest alphabet'), findsOneWidget);

    await tester.tap(find.text('Semitic sounds'));
    await tester.pumpAndSettle();
    expect(find.byType(SemiticSoundsPage), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('The earliest alphabet'));
    await tester.pumpAndSettle();
    expect(find.byType(EarlyAlphabetPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a verse link closes the shelf and goes to the passage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    (int, int, int)? went;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ReferencePage.open(
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
    await tester.tap(find.text('Semitic sounds'));
    await tester.pumpAndSettle();
    final link = find.text('Dan 2:32');
    await tester.scrollUntilVisible(
      link,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(went, isNotNull);
    expect(find.byType(ReferencePage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
