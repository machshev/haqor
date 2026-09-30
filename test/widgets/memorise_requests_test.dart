import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/memorise/memorise_drill.dart';
import 'package:haqor/src/request_failure.dart';

void _deliver(String name, Uint8List bytes) =>
    assignRustSignal[name]!(bytes, Uint8List(0));

void _fail(String request, String key, String message) => _deliver(
  'RequestFailed',
  RequestFailed(
    request: request,
    key: key,
    message: message,
  ).bincodeSerialize(),
);

const _card = MemoryCard(
  passageId: 'p',
  book: 19,
  purpose: 'read',
  title: 'Title',
  prompt: 'Read it aloud.',
  segments: [
    MemorySegment(
      chapter: 23,
      verse: 1,
      line: 0,
      lineCount: 1,
      words: [MemoryWord(text: 'יְהוָה', gloss: 'the LORD', translit: 'YHWH')],
    ),
  ],
  cue: '',
  targetChapter: 23,
  targetVerse: 1,
  step: 0,
  stepCount: 1,
  isNew: true,
  position: 1,
  total: 1,
  section: 1,
  sectionCount: 1,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryDrillPage(
          passageId: 'p',
          title: 'Psalm 23',
          sendRequest: sent.add,
        ),
      ),
    );
    return sent;
  }

  testWidgets('a card that cannot be fetched shows the error and retries', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.single, isA<GetNextMemoryCard>());

    // Another passage's failure is not ours.
    _fail(requestMemoryItem, 'other', 'not ours');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);

    _fail(requestMemoryItem, 'p', 'database is locked');
    await tester.pump();
    expect(find.textContaining('database is locked'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetNextMemoryCard>(), hasLength(2));
    expect(find.byType(RequestErrorView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a card that never comes ends in the error state', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an answer that was not saved can be sent again', (tester) async {
    final sent = await pump(tester);
    _deliver(
      'MemoryItem',
      const MemoryItem(
        kind: 'card',
        card: _card,
        nextDueEpoch: 0,
        canLearnMore: true,
        shapePassageId: '',
      ).bincodeSerialize(),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('I have read it aloud'));
    await tester.pump();
    expect(sent.whereType<SubmitMemoryRecital>(), hasLength(1));

    _fail(requestMemoryRecital, 'p', 'database is locked');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('not saved'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<SubmitMemoryRecital>(), hasLength(2));

    // Let the deferred progress sync and the next-card timeout run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
