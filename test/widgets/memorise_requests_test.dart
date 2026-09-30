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
    expect(sent.whereType<GetNextMemoryCard>(), hasLength(1));

    _fail(requestMemoryRecital, 'p', 'database is locked');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('not saved'), findsOneWidget);
    // The next card is asked for once the answer has failed.
    expect(sent.whereType<GetNextMemoryCard>(), hasLength(2));

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<SubmitMemoryRecital>(), hasLength(2));

    // Let the deferred progress sync and the next-card timeout run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the next card is asked for only after the answer is recorded', (
    tester,
  ) async {
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
    expect(sent.whereType<GetNextMemoryCard>(), hasLength(1));

    _deliver(
      'MemoryReviewResult',
      const MemoryReviewResult(
        purpose: 'read',
        targetChapter: 23,
        targetVerse: 1,
        xp: 5,
        firstGraduation: false,
        sectionCompleted: false,
        completedPassages: [],
        relearn: 0,
        intervalDays: 0,
        totalXp: 5,
        levelBefore: 1,
        levelAfter: 1,
        todayXp: 5,
        dailyGoalXp: 50,
        goalReachedNow: false,
        streakDays: 1,
      ).bincodeSerialize(),
    );
    await tester.pump();
    expect(sent.whereType<GetNextMemoryCard>(), hasLength(2));
    expect(sent.last, isA<GetNextMemoryCard>());

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a double tap on the card sends one recital', (tester) async {
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
    final button = find.text('I have read it aloud');
    await tester.tap(button);
    // The card is still on screen, fading out, but no longer takes taps.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(button, warnIfMissed: false);
    await tester.pump();
    expect(sent.whereType<SubmitMemoryRecital>(), hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  MemoryReviewResult result({List<String> completed = const []}) =>
      MemoryReviewResult(
        purpose: 'read',
        targetChapter: 23,
        targetVerse: 1,
        xp: 5,
        firstGraduation: false,
        sectionCompleted: false,
        completedPassages: completed,
        relearn: 0,
        intervalDays: 0,
        totalXp: 5,
        levelBefore: 1,
        levelAfter: 1,
        todayXp: 5,
        dailyGoalXp: 50,
        goalReachedNow: false,
        streakDays: 1,
      );

  const cardItem = MemoryItem(
    kind: 'card',
    card: _card,
    nextDueEpoch: 0,
    canLearnMore: true,
    shapePassageId: '',
  );

  testWidgets('a run whose answer was not saved is not "Nothing learnt yet"', (
    tester,
  ) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryDrillPage(
          passageId: 'p',
          title: 'Psalm 23',
          run: true,
          sendRequest: sent.add,
        ),
      ),
    );
    _deliver('MemoryItem', cardItem.bincodeSerialize());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('I have read it aloud'));
    await tester.pump();

    _fail(requestMemoryRecital, 'p', 'database is locked');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Nothing learnt yet'), findsNothing);
    expect(find.text('Recited!'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('finishing a passage while drilling all names no title', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemoryDrillPage(
          passageId: '',
          title: 'All passages',
          sendRequest: (_) {},
        ),
      ),
    );
    _deliver('MemoryItem', cardItem.bincodeSerialize());
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('I have read it aloud'));
    await tester.pump();
    _deliver('MemoryReviewResult', result(completed: ['p']).bincodeSerialize());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Every verse of a passage'), findsOneWidget);
    expect(find.textContaining('All passages is'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
