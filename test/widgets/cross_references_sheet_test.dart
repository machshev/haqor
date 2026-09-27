import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/cross_references_sheet.dart';

/// Answers the sheet's requests the way the Rust side would, through the
/// injected send seams and [assignRustSignal] (see word_occurrences_test).
class _FakeRust {
  final List<GetCrossReferences> requests = [];
  final List<GetVerseTexts> verseRequests = [];
  final List<GetQuotations> quotationRequests = [];

  final List<GetThematicReferences> thematicRequests = [];
  final List<GetThematicOverview> thematicOverviewRequests = [];

  void deliverThematicOverview(int total, List<ThematicVerseEntry> verses) {
    assignRustSignal['ThematicOverview']!(
      ThematicOverview(
        requestId: thematicOverviewRequests.last.requestId,
        book: thematicOverviewRequests.last.book,
        total: total,
        verses: verses,
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  void deliverThematic(
    int book,
    int chapter,
    int verse,
    List<ThematicReferenceEntry> entries,
  ) {
    assignRustSignal['ThematicReferences']!(
      ThematicReferences(
        book: book,
        chapter: chapter,
        verse: verse,
        entries: entries,
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

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
  double minScore = 0,
  ValueChanged<double>? onMinScoreChanged,
  void Function(int, int, int)? onNavigate,
}) async {
  SharedPreferences.setMockInitialValues({});
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CrossReferencesPanel(
            book: 40,
            chapter: 1,
            target: verse == null ? null : (book: 40, chapter: 1, verse: verse),
            useEnglishBookNames: true,
            minScore: minScore,
            onMinScoreChanged: onMinScoreChanged,
            onNavigateToPassage: onNavigate,
            sendRequest: rust.requests.add,
            sendQuotationsRequest: rust.quotationRequests.add,
            sendThematicReferencesRequest: rust.thematicRequests.add,
            sendThematicOverviewRequest: rust.thematicOverviewRequests.add,
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
  strengthTests();
  dockedTests();
  bookmarkTests();

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

    expect(find.text('Cross references'), findsOneWidget);
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
    rust.deliverThematic(40, 1, 23, const []);
    await tester.pump();
    expect(
      find.text('No cross references found for this verse.'),
      findsOneWidget,
    );
  });

  testWidgets('a verse without quotations opens on its thematic references', (
    tester,
  ) async {
    final opened = <(int, int, int)>[];
    final rust = await _pump(
      tester,
      onNavigate: (b, c, v) => opened.add((b, c, v)),
    );
    expect(rust.thematicRequests.single.verse, 23);
    rust.deliver(40, 1, 23, const []);
    await tester.pump();
    // Whether there is anything to show waits for the thematic reply.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    rust.deliverThematic(40, 1, 23, [
      ThematicReferenceEntry(
        phrase: 'a virgin',
        targets: [
          _target(book: 12, chapter: 7, verse: 14),
          _target(book: 1, chapter: 3, verse: 15),
        ],
      ),
      ThematicReferenceEntry(
        phrase: 'Emmanuel',
        targets: [
          _target(book: 12, chapter: 8, verse: 8, lastVerse: 10),
          _target(book: 12, chapter: 9, verse: 5, lastChapter: 10),
        ],
      ),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    expect(find.text('Quotations (0)'), findsOneWidget);
    expect(find.text('Thematic (4)'), findsOneWidget);
    expect(find.text('“a virgin”'), findsOneWidget);
    expect(find.text('“Emmanuel”'), findsOneWidget);
    expect(find.textContaining('Isaiah 7:14'), findsOneWidget);
    expect(find.text('Isaiah 8:8–10'), findsOneWidget);
    expect(find.text('Isaiah 9:5–10:5'), findsOneWidget);

    await tester.tap(find.textContaining('Genesis 3:15'));
    expect(opened, [(0, 3, 15)]);
  });

  testWidgets('the thematic references are a second list beside the links', (
    tester,
  ) async {
    final rust = await _pump(tester);
    rust.deliver(40, 1, 23, [_entry(book: 12, chapter: 7, verse: 14)]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    // The links show before the thematic reply arrives.
    expect(find.text('Strong match · 2 words'), findsOneWidget);

    rust.deliverThematic(40, 1, 23, [
      ThematicReferenceEntry(
        phrase: 'a virgin',
        targets: [_target(book: 1, chapter: 3, verse: 15)],
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('“a virgin”'), findsNothing);

    await tester.tap(find.text('Thematic (1)'));
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(find.text('“a virgin”'), findsOneWidget);
    expect(find.text('Strong match · 2 words'), findsNothing);
    // The thematic list shows no source verse: the header names it.
    expect(_highlighted(tester).containsKey('Matthew 1:23'), isFalse);

    await tester.tap(find.text('Quotations (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Strong match · 2 words'), findsOneWidget);
  });
}

ThematicTarget _target({
  required int book,
  required int chapter,
  required int verse,
  int? lastChapter,
  int? lastVerse,
}) => ThematicTarget(
  book: book,
  chapter: chapter,
  verse: verse,
  lastChapter: lastChapter ?? chapter,
  lastVerse: lastVerse ?? (lastChapter == null ? verse : 5),
);

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
  testWidgets('the overview switches to the chapter\'s thematic references', (
    tester,
  ) async {
    final opened = <(int, int, int)>[];
    final rust = await _pump(
      tester,
      verse: null,
      onNavigate: (b, c, v) => opened.add((b, c, v)),
    );
    rust.deliverQuotations(0, const []);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('strength')), findsOneWidget);

    await tester.tap(find.text('Thematic'));
    await tester.pump();
    final request = rust.thematicOverviewRequests.single;
    expect(request.book, 40);
    expect((request.firstChapter, request.lastChapter), (1, 1));
    expect(request.offset, 0);
    // Strength, order and link kind belong to quotations alone.
    expect(find.byKey(const ValueKey('strength')), findsNothing);
    expect(find.byKey(const ValueKey('links')), findsNothing);

    rust.deliverThematicOverview(2, [
      ThematicVerseEntry(
        chapter: 1,
        verse: 21,
        entries: [
          ThematicReferenceEntry(
            phrase: 'Jesus',
            targets: [
              _target(book: 40, chapter: 1, verse: 25),
              _target(book: 44, chapter: 5, verse: 31),
            ],
          ),
        ],
      ),
      ThematicVerseEntry(
        chapter: 1,
        verse: 23,
        entries: [
          ThematicReferenceEntry(
            phrase: 'a virgin',
            targets: [_target(book: 12, chapter: 7, verse: 14, lastVerse: 16)],
          ),
        ],
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Thematic references in Matthew'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);
    expect(find.text('Matthew 1:21'), findsOneWidget);
    expect(find.text('Jesus'), findsOneWidget);
    // Within the book a reference drops the book's name.
    expect(find.text('1:25;'), findsOneWidget);
    expect(find.text('Acts 5:31'), findsOneWidget);
    expect(find.text('Isaiah 7:14–16'), findsOneWidget);

    await tester.tap(find.text('Acts 5:31'));
    expect(opened, [(43, 5, 31)]);

    // A verse's heading opens its view on the thematic list, with no source
    // verse above it.
    await tester.tap(find.text('Matthew 1:23'));
    await tester.pump();
    expect(rust.thematicRequests.single.verse, 23);
    rust.deliver(40, 1, 23, [_entry(book: 12, chapter: 7, verse: 14)]);
    rust.deliverThematic(40, 1, 23, [
      ThematicReferenceEntry(
        phrase: 'a virgin',
        targets: [_target(book: 12, chapter: 7, verse: 14)],
      ),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(find.text('“a virgin”'), findsOneWidget);
    expect(_highlighted(tester).containsKey('Matthew 1:23'), isFalse);

    // Back on quotations, the overview follows.
    await tester.tap(find.text('Quotations (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All cross references'));
    await tester.pump();
    expect(rust.quotationRequests, hasLength(2));
  });

  testWidgets('the thematic overview pages by verse', (tester) async {
    final rust = await _pump(tester, verse: null);
    rust.deliverQuotations(0, const []);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thematic'));
    await tester.pump();
    rust.deliverThematicOverview(41, [
      for (var v = 1; v <= 3; v++)
        ThematicVerseEntry(
          chapter: 1,
          verse: v,
          entries: [
            ThematicReferenceEntry(
              phrase: 'p$v',
              targets: [_target(book: 1, chapter: 1, verse: 1)],
            ),
          ],
        ),
    ]);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Show more'), 100);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    expect(rust.thematicOverviewRequests.last.offset, 3);
  });
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
    expect(find.text('3 links'), findsOneWidget);
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
    expect(find.text('Cross references'), findsOneWidget);
    // The link the row was for is the one shown on the verse.
    expect(_highlighted(tester)['Matthew 1:23'], ['הה']);

    await tester.tap(find.byTooltip('All cross references'));
    await tester.pumpAndSettle();
    expect(find.text('2 links'), findsOneWidget);
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
    expect(find.text('No cross references found here.'), findsOneWidget);
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

  testWidgets('the links filter asks for one kind of link at a time', (
    tester,
  ) async {
    final rust = await _pump(tester, verse: null);
    expect(rust.quotationRequests.single.scope, 0);
    expect(find.text('Quotations and parallels in Matthew'), findsOneWidget);

    await tester.tap(find.text('OT ↔ NT'));
    await tester.pump();
    expect(rust.quotationRequests.last.scope, 1);
    expect(find.text('Matthew quoting the OT'), findsOneWidget);

    await tester.tap(find.text('Within NT'));
    await tester.pump();
    expect(rust.quotationRequests.last.scope, 2);
    expect(rust.quotationRequests.last.offset, 0);
    expect(find.text('Matthew and the rest of the NT'), findsOneWidget);
  });

  testWidgets('links within the testament are labelled as parallels', (
    tester,
  ) async {
    final rust = await _pump(tester, verse: null);
    rust.deliverQuotations(2, [
      _quote(verse: 23, otherBook: 12, otherChapter: 7, otherVerse: 14),
      _quote(verse: 23, otherBook: 42, otherChapter: 1, otherVerse: 31),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(find.text('Strong match · 2 words'), findsOneWidget);
    expect(find.text('Parallel · Strong match · 2 words'), findsOneWidget);
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

void strengthTests() {
  testWidgets('the strength filter narrows the overview and is reported', (
    tester,
  ) async {
    final chosen = <double>[];
    final rust = await _pump(
      tester,
      verse: null,
      onMinScoreChanged: chosen.add,
    );
    expect(rust.quotationRequests.single.minScore, 0);

    await tester.tap(find.text('Strong'));
    await tester.pump();
    expect(rust.quotationRequests.last.minScore, kStrongCrossReference);
    expect(chosen, [kStrongCrossReference]);
  });

  testWidgets('a verse folds its links weaker than the filter', (tester) async {
    final rust = await _pump(tester, minScore: kLikelyCrossReference);
    expect(rust.requests.single.minScore, 0, reason: 'fetches every link');
    rust.deliver(40, 1, 23, [
      _entry(book: 12, chapter: 7, verse: 14, score: 20),
      _entry(book: 12, chapter: 8, verse: 8, score: 8, positions: [4]),
    ]);
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    expect(find.textContaining('Isaiah 7:14'), findsOneWidget);
    expect(find.textContaining('Isaiah 8:8'), findsNothing);
    await tester.tap(find.text('Show 1 weaker link'));
    await tester.pump();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(find.textContaining('Isaiah 8:8'), findsOneWidget);
  });
}

void dockedTests() {
  testWidgets('the verse text switch asks for English and remembers it', (
    tester,
  ) async {
    final rust = await _pump(tester, verse: null);
    rust.deliverQuotations(1, [
      _quote(verse: 23, otherBook: 12, otherChapter: 7, otherVerse: 14),
    ]);
    await tester.pump();
    expect(rust.verseRequests.last.englishOnly, isFalse);

    await tester.tap(find.byTooltip('Show English-only verse text'));
    await tester.pump();
    expect(rust.verseRequests.last.englishOnly, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('occurrence_verse_english_only'), isTrue);
  });

  testWidgets('docked, it follows the reader and reopens asked-for verses', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final rust = _FakeRust();
    var closed = 0;
    Widget panel(int chapter, int request) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CrossReferencesPanel(
            book: 40,
            chapter: chapter,
            target: request == 0 ? null : (book: 40, chapter: 2, verse: 15),
            targetRequest: request,
            useEnglishBookNames: true,
            onClose: () => closed++,
            sendRequest: rust.requests.add,
            sendQuotationsRequest: rust.quotationRequests.add,
            sendThematicReferencesRequest: rust.thematicRequests.add,
            sendThematicOverviewRequest: rust.thematicOverviewRequests.add,
            sendVerseTextsRequest: rust.verseRequests.add,
          ),
        ),
      ),
    );
    await tester.pumpWidget(panel(1, 0));
    expect(rust.quotationRequests.single.firstChapter, 1);

    // The reader scrolls on: the chapter overview follows it.
    await tester.pumpWidget(panel(2, 0));
    expect(rust.quotationRequests.last.firstChapter, 2);

    // A marker is tapped: that verse opens, and after going back, the same
    // verse asked for again opens again.
    await tester.pumpWidget(panel(2, 1));
    expect(rust.requests.single.verse, 15);
    await tester.tap(find.byTooltip('All cross references'));
    await tester.pump();
    await tester.pumpWidget(panel(2, 2));
    expect(rust.requests, hasLength(2));

    await tester.tap(find.byTooltip('Close cross references'));
    expect(closed, 1);
  });
}

void bookmarkTests() {
  testWidgets('a link can be bookmarked the right way round from either side', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final rust = _FakeRust();
    final bookmarked = <String>{};
    final toggled = <StudyLink>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CrossReferencesPanel(
              book: 40,
              chapter: 1,
              target: (book: 40, chapter: 1, verse: 23),
              useEnglishBookNames: true,
              isLinkBookmarked: (earlier, later) => bookmarked.contains(
                StudyLink(earlier: earlier, later: later).key,
              ),
              onToggleLinkBookmark: (link) async {
                toggled.add(link);
                return bookmarked.add(link.key) || !bookmarked.remove(link.key);
              },
              sendRequest: rust.requests.add,
              sendQuotationsRequest: rust.quotationRequests.add,
              sendThematicReferencesRequest: rust.thematicRequests.add,
              sendThematicOverviewRequest: rust.thematicOverviewRequests.add,
              sendVerseTextsRequest: rust.verseRequests.add,
            ),
          ),
        ),
      ),
    );
    rust.deliver(40, 1, 23, [_entry(book: 12, chapter: 7, verse: 14)]);
    await tester.pump();

    await tester.tap(find.byTooltip('Bookmark this link'));
    await tester.pump();
    final link = toggled.single;
    // Opened from Matthew, the link still files Isaiah as its earlier verse.
    expect(link.earlier, (bookIndex: 11, chapter: 7, verse: 14));
    expect(link.later, (bookIndex: 39, chapter: 1, verse: 23));
    expect(link.earlierPositions, [0, 2]);
    expect(link.laterPositions, [1, 3]);
    expect(find.byTooltip('Remove link bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove link bookmark'));
    await tester.pump();
    expect(bookmarked, isEmpty);
    expect(find.byTooltip('Bookmark this link'), findsOneWidget);
  });

  testWidgets('a link within the NT is filed earlier verse first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final rust = _FakeRust();
    final toggled = <StudyLink>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CrossReferencesPanel(
              book: 41,
              chapter: 1,
              target: (book: 41, chapter: 1, verse: 3),
              useEnglishBookNames: true,
              isLinkBookmarked: (_, _) => false,
              onToggleLinkBookmark: (link) async {
                toggled.add(link);
                return true;
              },
              sendRequest: rust.requests.add,
              sendQuotationsRequest: rust.quotationRequests.add,
              sendThematicReferencesRequest: rust.thematicRequests.add,
              sendThematicOverviewRequest: rust.thematicOverviewRequests.add,
              sendVerseTextsRequest: rust.verseRequests.add,
            ),
          ),
        ),
      ),
    );
    // Opened from Mark 1:3, its parallel Matthew 3:3 comes first.
    rust.deliver(41, 1, 3, [_entry(book: 40, chapter: 3, verse: 3)]);
    await tester.pump();
    await tester.tap(find.byTooltip('Bookmark this link'));
    await tester.pump();
    final link = toggled.single;
    expect(link.earlier, (bookIndex: 39, chapter: 3, verse: 3));
    expect(link.later, (bookIndex: 40, chapter: 1, verse: 3));
    expect(link.earlierPositions, [0, 2]);
    expect(link.laterPositions, [1, 3]);
  });
}
