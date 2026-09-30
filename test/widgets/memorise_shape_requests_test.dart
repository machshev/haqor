import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/memorise/memorise_shape.dart';
import 'package:haqor/src/request_failure.dart';

void _fail(String key, String message) => assignRustSignal['RequestFailed']!(
  RequestFailed(
    request: requestMemoryLayout,
    key: key,
    message: message,
  ).bincodeSerialize(),
  Uint8List(0),
);

void main() {
  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryShapePage(
          passageId: 'p',
          title: 'Psalm 23',
          sendRequest: sent.add,
        ),
      ),
    );
    return sent;
  }

  testWidgets('a layout that cannot be loaded shows the error and retries', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.single, isA<GetMemoryLayout>());

    _fail('other', 'not ours');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);

    _fail('p', 'database is locked');
    await tester.pump();
    expect(find.textContaining('database is locked'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetMemoryLayout>(), hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a layout that never arrives stops spinning', (tester) async {
    await pump(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  MemoryLayoutVerse verse(
    int n, {
    List<int> lineStarts = const [],
    bool sectionStart = false,
    bool shaped = false,
    bool ready = false,
  }) => MemoryLayoutVerse(
    chapter: 1,
    verse: n,
    words: [for (var i = 0; i < 4; i++) 'w$n$i'],
    glosses: const [],
    lineStarts: lineStarts,
    sectionStart: sectionStart,
    shaped: shaped,
    ready: ready,
  );

  void layout(List<MemoryLayoutVerse> verses) =>
      assignRustSignal['MemoryLayout']!(
        MemoryLayout(
          passageId: 'p',
          book: 1,
          verses: verses,
        ).bincodeSerialize(),
        Uint8List(0),
      );

  testWidgets('fast taps each build on the edit before them', (tester) async {
    final sent = await pump(tester);
    layout([verse(1, sectionStart: true)]);
    await tester.pump();

    // The first edit's reply has not come back when the second is made.
    await tester.tap(find.text('w10'));
    await tester.pump();
    await tester.tap(find.text('w12'));
    await tester.pump();
    final edits = sent.whereType<SetMemoryLayout>().toList();
    expect(edits, hasLength(2));
    expect(edits[0].lineStarts, [1]);
    expect(edits[1].lineStarts, [1, 3]);

    // The first reply is stale by now and must not undo the second edit.
    layout([
      verse(1, sectionStart: true, shaped: true, lineStarts: [1]),
    ]);
    await tester.pump();
    await tester.tap(find.text('w11'));
    await tester.pump();
    expect(sent.whereType<SetMemoryLayout>().last.lineStarts, [1, 2, 3]);
    // Let the progress sync each edit schedules run out.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}
