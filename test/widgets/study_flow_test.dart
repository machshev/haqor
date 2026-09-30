import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/request_failure.dart';
import 'package:haqor/src/tutor/study_flow.dart';

void _fail(String request, String message) {
  assignRustSignal['RequestFailed']!(
    RequestFailed(
      request: request,
      key: '',
      message: message,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<Object>> pump(WidgetTester tester) async {
    final sent = <Object>[];
    await tester.pumpWidget(
      MaterialApp(home: StudyFlowPage(sendRequest: sent.add)),
    );
    await tester.pump();
    return sent;
  }

  testWidgets('a failed first card shows the error and retries the request', (
    tester,
  ) async {
    final sent = await pump(tester);
    expect(sent.single, isA<GetNextStudyItem>());
    expect(find.byType(RequestErrorView), findsNothing);

    _fail(requestNextStudyItem, 'database is locked');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsOneWidget);
    expect(find.textContaining('database is locked'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent, hasLength(2));
    expect(sent.last, isA<GetNextStudyItem>());
    expect(find.byType(RequestErrorView), findsNothing);
  });

  testWidgets('a card that never comes ends in the error state', (
    tester,
  ) async {
    final sent = await pump(tester);

    await tester.pump(requestTimeout + const Duration(seconds: 1));
    expect(find.byType(RequestErrorView), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent, hasLength(2));

    // Leave no timer pending.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failure for another request is ignored', (tester) async {
    await pump(tester);
    _fail(requestMemoryStats, 'not ours');
    await tester.pump();
    expect(find.byType(RequestErrorView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a verse that cannot be fetched offers a retry', (tester) async {
    final sent = await pump(tester);
    assignRustSignal['StudyItem']!(
      _readVerse().bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(sent.whereType<GetVerseText>(), hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    assignRustSignal['RequestFailed']!(
      const RequestFailed(
        request: requestVerseText,
        key: '1:1:1',
        message: 'no such verse',
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump();
    expect(find.textContaining('no such verse'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(sent.whereType<GetVerseText>(), hasLength(2));
    expect(find.textContaining('no such verse'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  Future<List<Object>> pumpWithCard(WidgetTester tester, StudyItem item) async {
    final sent = await pump(tester);
    assignRustSignal['StudyItem']!(item.bincodeSerialize(), Uint8List(0));
    await tester.pump(const Duration(seconds: 1));
    return sent;
  }

  testWidgets('a double tap on Got it sends one review', (tester) async {
    final sent = await pumpWithCard(tester, _newWord());
    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 50));
    // The fading card no longer takes taps; this second tap must be ignored.
    await tester.tap(find.text('Got it'), warnIfMissed: false);
    await tester.pump();
    expect(sent.whereType<SubmitReview>(), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a double tap on Continue asks for one next card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = await pumpWithCard(
      tester,
      _item('explain_intro', intro: 'intro_rtl'),
    );
    expect(sent.whereType<GetNextStudyItem>(), hasLength(1));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 50));
    // The fading card no longer takes taps; this second tap must be ignored.
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    expect(sent.whereType<GetNextStudyItem>(), hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a double tap on the misreads Continue sends one request', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = await pumpWithCard(tester, _readVerse());
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
    await tester.tap(find.text('No'));
    await tester.pump();
    await tester.tap(find.byType(FilterChip));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 50));
    // The fading card no longer takes taps; this second tap must be ignored.
    await tester.tap(find.text('Continue'), warnIfMissed: false);
    await tester.pump();
    expect(sent.whereType<SubmitMisreads>(), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a card fading out takes no taps once the next card is in', (
    tester,
  ) async {
    final sent = await pumpWithCard(tester, _newWord());
    await tester.tap(find.text('Got it'));
    await tester.pump();
    // The next card arrives at once, so the page's own guard is open again.
    assignRustSignal['StudyItem']!(
      _item('done').bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // The old card is still in the tree, part-way through its fade.
    expect(find.text('Got it'), findsOneWidget);
    expect(find.text('Got it').hitTestable(), findsNothing);
    await tester.tap(find.text('Got it'), warnIfMissed: false);
    await tester.pump();
    expect(sent.whereType<SubmitReview>(), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
  });
}

StudyItem _readVerse() => const StudyItem(
  kind: 'read_verse',
  verse: VerseCard(
    book: 1,
    chapter: 1,
    verse: 1,
    examples: [],
    words: ['בְּרֵאשִׁית'],
    names: [false],
    text: '',
    translit: '',
  ),
  progress: TutorProgress(
    lettersKnown: 0,
    lettersTotal: 0,
    vowelsKnown: 0,
    vowelsTotal: 0,
    grammarKnown: 0,
    grammarTotal: 0,
    wordsKnown: 0,
    versesGrammarUnlocked: 0,
    versesReadable: 0,
    totalVerses: 0,
  ),
);

const _noProgress = TutorProgress(
  lettersKnown: 0,
  lettersTotal: 0,
  vowelsKnown: 0,
  vowelsTotal: 0,
  grammarKnown: 0,
  grammarTotal: 0,
  wordsKnown: 0,
  versesGrammarUnlocked: 0,
  versesReadable: 0,
  totalVerses: 0,
);

StudyItem _item(String kind, {String? intro}) =>
    StudyItem(kind: kind, intro: intro, progress: _noProgress);

StudyItem _newWord() => const StudyItem(
  kind: 'new_word',
  word: WordCard(
    surfaceId: 1,
    surface: 'אֱלֹהִים',
    occurrences: 10,
    translit: 'elohim',
    gloss: 'God',
    rootGloss: '',
    note: '',
    root: '',
    morph: '',
    aspect: 'mean',
    distractors: [],
  ),
  progress: _noProgress,
);
