import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}
