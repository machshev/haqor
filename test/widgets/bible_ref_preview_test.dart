import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/request_failure.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

void main() {
  Future<List<GetVerseText>> pump(WidgetTester tester) async {
    final sent = <GetVerseText>[];
    await tester.pumpWidget(
      MaterialApp(
        home: BibleRefPreviewDialog(
          displayRef: 'Gen 1:1',
          bookIndex: 0,
          chapter: 1,
          verse: 1,
          sendVerseText: sent.add,
        ),
      ),
    );
    return sent;
  }

  void fail(String key, String message) => assignRustSignal['RequestFailed']!(
    RequestFailed(
      request: requestVerseText,
      key: key,
      message: message,
    ).bincodeSerialize(),
    Uint8List(0),
  );

  testWidgets('a failed verse request shows the error and can be retried', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    fail('2:1:1', 'another verse');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);

    fail('1:1:1', 'no such verse');
    await tester.pump();
    expect(find.textContaining('no such verse'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    assignRustSignal['VerseText']!(
      const VerseText(
        book: 1,
        chapter: 1,
        verse: 1,
        englishOnly: false,
        text: 'בראשית',
        translit: '',
        glossWords: [],
        sourceWords: [],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    expect(find.text('בראשית'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a verse that never arrives stops spinning', (tester) async {
    await pump(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
