import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/cross_references_sheet.dart';

/// Answers the sheet's requests the way the Rust side would, through the
/// injected send seams and [assignRustSignal] (see word_occurrences_test).
class _FakeRust {
  final List<GetCrossReferences> requests = [];
  final List<GetVerseTexts> verseRequests = [];

  void deliver(int book, int chapter, int verse, List<CrossReferenceEntry> e) {
    assignRustSignal['CrossReferences']!(
      CrossReferences(
        book: book,
        chapter: chapter,
        verse: verse,
        entries: e,
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  /// Every verse reads `w0 w1 w2 w3 w4`, so a highlight shows by position.
  void deliverVerseTexts() {
    final pending = List<GetVerseTexts>.of(verseRequests);
    verseRequests.clear();
    for (final request in pending) {
      assignRustSignal['VerseTexts']!(
        VerseTexts(
          requestId: request.requestId,
          englishOnly: request.englishOnly,
          verses: [
            for (final ref in request.refs)
              VerseTextEntry(
                book: ref.book,
                chapter: ref.chapter,
                verse: ref.verse,
                text: 'אא בב גג דד הה',
                glossWords: const [],
                sourceWords: const [],
              ),
          ],
        ).bincodeSerialize(),
        Uint8List(0),
      );
    }
  }
}

CrossReferenceEntry _entry({
  required int book,
  required int chapter,
  required int verse,
  double score = 20,
  List<int> positions = const [0, 2],
  List<int> sourcePositions = const [1, 3],
}) => CrossReferenceEntry(
  rank: 1,
  score: score,
  book: book,
  chapter: chapter,
  verse: verse,
  positions: positions,
  sourcePositions: sourcePositions,
);

Future<_FakeRust> _pump(
  WidgetTester tester, {
  void Function(int, int, int)? onNavigate,
}) async {
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CrossReferencesSheet(
            book: 40,
            chapter: 1,
            verse: 23,
            useEnglishBookNames: true,
            onNavigateToPassage: onNavigate,
            sendRequest: rust.requests.add,
            sendVerseTextsRequest: rust.verseRequests.add,
          ),
        ),
      ),
    ),
  );
  return rust;
}

/// The words of every verse row rendered highlighted, keyed by its reference.
Map<String, List<String>> _highlighted(WidgetTester tester) {
  final result = <String, List<String>>{};
  for (final element in find.byType(SelectableText).evaluate()) {
    final spans = (element.widget as SelectableText).textSpan!.children!
        .cast<TextSpan>();
    final ref = spans.first.text!.trim();
    result[ref] = [
      for (final span in spans.skip(1))
        if (span.style?.backgroundColor != null) span.text!,
    ];
  }
  return result;
}

void main() {
  testWidgets('asks for the verse and lists its links with matched words', (
    tester,
  ) async {
    final rust = await _pump(tester);
    expect(rust.requests.single.book, 40);
    expect(rust.requests.single.chapter, 1);
    expect(rust.requests.single.verse, 23);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    rust.deliver(40, 1, 23, [
      _entry(book: 12, chapter: 7, verse: 14),
      _entry(book: 12, chapter: 8, verse: 8, score: 8, positions: [4]),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    expect(find.text('Quotes from the OT'), findsOneWidget);
    expect(find.text('Strong match · 2 words'), findsOneWidget);
    expect(find.text('Possible echo · 1 word'), findsOneWidget);
    final highlighted = _highlighted(tester);
    expect(highlighted['Isaiah 7:14'], ['אא', 'גג']);
    expect(highlighted['Isaiah 8:8'], ['הה']);
    // The source verse shows the first link's matched words.
    expect(highlighted['Matthew 1:23'], ['בב', 'דד']);
  });

  testWidgets('choosing a link shows its words on the source verse', (
    tester,
  ) async {
    final rust = await _pump(tester);
    rust.deliver(40, 1, 23, [
      _entry(book: 12, chapter: 7, verse: 14),
      _entry(book: 12, chapter: 8, verse: 8, sourcePositions: [0]),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Strong match').last);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(_highlighted(tester)['Matthew 1:23'], ['אא']);
  });

  testWidgets('tapping a linked verse opens it', (tester) async {
    final opened = <(int, int, int)>[];
    final rust = await _pump(
      tester,
      onNavigate: (b, c, v) => opened.add((b, c, v)),
    );
    rust.deliver(40, 1, 23, [_entry(book: 12, chapter: 7, verse: 14)]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Isaiah 7:14'));
    expect(opened, [(11, 7, 14)]);
  });

  testWidgets('ignores replies for other verses and says when there are none', (
    tester,
  ) async {
    final rust = await _pump(tester);
    rust.deliver(40, 1, 22, [_entry(book: 12, chapter: 7, verse: 14)]);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    rust.deliver(40, 1, 23, const []);
    await tester.pump();
    expect(find.text('No quotations found for this verse.'), findsOneWidget);
  });
}
