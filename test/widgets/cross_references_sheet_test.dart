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
  final List<GetQuotations> quotationRequests = [];

  void deliverQuotations(int total, List<QuotationEntry> entries) {
    assignRustSignal['Quotations']!(
      Quotations(
        requestId: quotationRequests.last.requestId,
        book: quotationRequests.last.book,
        total: total,
        entries: entries,
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

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
  int? verse = 23,
  void Function(int, int, int)? onNavigate,
}) async {
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CrossReferencesPanel(
            book: 40,
            chapter: 1,
            verse: verse,
            useEnglishBookNames: true,
            onNavigateToPassage: onNavigate,
            sendRequest: rust.requests.add,
            sendQuotationsRequest: rust.quotationRequests.add,
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
  overviewTests();

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

QuotationEntry _quote({
  required int verse,
  required int otherBook,
  required int otherChapter,
  required int otherVerse,
  double score = 20,
}) => QuotationEntry(
  rank: 1,
  score: score,
  chapter: 1,
  verse: verse,
  positions: const [1, 3],
  otherBook: otherBook,
  otherChapter: otherChapter,
  otherVerse: otherVerse,
  otherPositions: const [0, 2],
);

void overviewTests() {
  testWidgets('with no verse it opens the chapter overview grouped by verse', (
    tester,
  ) async {
    final rust = await _pump(tester, verse: null);
    final request = rust.quotationRequests.single;
    expect(request.book, 40);
    expect((request.firstChapter, request.lastChapter), (1, 1));
    expect(request.byReference, isTrue);
    expect(rust.requests, isEmpty, reason: 'no verse view yet');

    rust.deliverQuotations(3, [
      _quote(verse: 22, otherBook: 12, otherChapter: 7, otherVerse: 14),
      _quote(verse: 23, otherBook: 12, otherChapter: 7, otherVerse: 14),
      _quote(verse: 23, otherBook: 12, otherChapter: 8, otherVerse: 8),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    expect(find.text('Cross references'), findsOneWidget);
    expect(find.text('3 quotations'), findsOneWidget);
    // One heading per verse, however many links it has.
    expect(find.text('Matthew 1:22'), findsOneWidget);
    expect(find.text('Matthew 1:23'), findsOneWidget);
    expect(_highlighted(tester)['Isaiah 8:8'], ['אא', 'גג']);
  });

  testWidgets('a row opens its verse on that link, and back returns', (
    tester,
  ) async {
    final rust = await _pump(tester, verse: null);
    rust.deliverQuotations(2, [
      _quote(verse: 23, otherBook: 12, otherChapter: 7, otherVerse: 14),
      _quote(verse: 23, otherBook: 12, otherChapter: 8, otherVerse: 8),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Isaiah 8:8'));
    await tester.pump();
    final request = rust.requests.single;
    expect((request.book, request.chapter, request.verse), (40, 1, 23));
    rust.deliver(40, 1, 23, [
      _entry(book: 12, chapter: 7, verse: 14),
      _entry(book: 12, chapter: 8, verse: 8, sourcePositions: [4]),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(find.text('Quotes from the OT'), findsOneWidget);
    // The link the row was for is the one shown on the verse.
    expect(_highlighted(tester)['Matthew 1:23'], ['הה']);

    await tester.tap(find.byTooltip('All cross references'));
    await tester.pumpAndSettle();
    expect(find.text('2 quotations'), findsOneWidget);
    expect(rust.quotationRequests, hasLength(1), reason: 'kept, not refetched');
  });

  testWidgets('a verse opened directly goes back to its chapter overview', (
    tester,
  ) async {
    final rust = await _pump(tester);
    expect(rust.requests.single.verse, 23);
    await tester.tap(find.byTooltip('All cross references'));
    await tester.pump();
    rust.deliverQuotations(0, const []);
    await tester.pump();
    expect(find.text('No quotations found here.'), findsOneWidget);
  });

  testWidgets('book scope asks for a chapter range and strength order', (
    tester,
  ) async {
    final rust = await _pump(tester, verse: null);
    await tester.tap(find.text('Book'));
    await tester.pump();
    var request = rust.quotationRequests.last;
    expect((request.firstChapter, request.lastChapter), (1, 28));

    await tester.tap(find.text('Strongest'));
    await tester.pump();
    request = rust.quotationRequests.last;
    expect(request.byReference, isFalse);

    await tester.tap(find.byKey(const ValueKey('first-chapter')));
    // The overview is still loading, so its spinner never settles.
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('5').last);
    await tester.pump(const Duration(seconds: 1));
    request = rust.quotationRequests.last;
    expect((request.firstChapter, request.lastChapter), (5, 28));
    expect(request.offset, 0);
  });

  testWidgets('show more asks for the next page', (tester) async {
    final rust = await _pump(tester, verse: null);
    rust.deliverQuotations(150, [
      for (var v = 1; v <= 3; v++)
        _quote(verse: v, otherBook: 12, otherChapter: 7, otherVerse: 14),
    ]);
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Show more'), 200);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(rust.quotationRequests.last.offset, 3);
  });
}
