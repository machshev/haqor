import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';
import 'package:haqor/src/word_proximity.dart';

/// The verse text every occurrence row is answered with. Six lexical words; the
/// third one repeats the second so a test can tell position-exact highlighting
/// apart from matching on the text.
const _words = ['אחד', 'בָּרָא', 'בָּרָא', 'ארבע', 'חמש', 'שש'];

/// Answers the sheet's requests the way the Rust side would.
///
/// The sheet's outbound signals are captured through its injected send seams
/// (`sendSignalToRust` needs the native library, which a widget test has not
/// loaded), and replies go back through [assignRustSignal] — the same entry
/// point real signals arrive on.
class _FakeRust {
  final List<GetVerseTexts> verseRequests = [];

  void onVerseTextsRequest(GetVerseTexts request) => verseRequests.add(request);

  final List<GetWordInfo> infoRequests = [];
  final List<GetWordOccurrences> occurrenceRequests = [];

  void onInfoRequest(GetWordInfo request) => infoRequests.add(request);

  void onOccurrencesRequest(GetWordOccurrences request) =>
      occurrenceRequests.add(request);

  void deliverWordInfo({required String word, required String root}) {
    assignRustSignal['WordInfo']!(
      WordInfo(
        requestId: infoRequests.last.requestId,
        found: true,
        word: word,
        root: root,
        gloss: 'create',
        partOfSpeech: 'verb',
        gender: null,
        number: null,
        prefix: null,
        suffix: null,
        prepositions: null,
        article: false,
        vavCon: false,
        bdbEntries: const [],
        sedraEntries: const [],
        person: null,
        state: null,
        tense: 'Perfect',
        form: 'Qal',
        roots: [RootChoice(root: root, gloss: 'create', isPrimary: true)],
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  void deliverOccurrences(List<HebrewOccurrence> occurrences) {
    assignRustSignal['WordOccurrences']!(
      WordOccurrences(
        requestId: occurrenceRequests.last.requestId,
        found: true,
        occurrences: const [],
        rootOccurrences: const [],
        sedraOccurrences: const [],
        otOccurrences: const [],
        hebrewOccurrences: occurrences,
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  /// Answer every verse-text request made so far, each with the same six-word
  /// verse.
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
                text:
                    '${ref.book}:${ref.chapter}:${ref.verse} '
                    '${_words.join(' ')}',
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

HebrewOccurrence _occurrence({
  required int book,
  required int chapter,
  required int verse,
  int position = 1,
  String surface = 'בָּרָא',
  String partOfSpeech = 'Verb',
  String stem = 'Qal',
  String tense = 'Perfect',
  String person = 'Third',
  String gender = 'Masculine',
  String number = 'Singular',
  String state = '',
}) => HebrewOccurrence(
  book: book,
  chapter: chapter,
  verse: verse,
  position: position,
  surface: surface,
  parse: OccurrenceParse(
    partOfSpeech: partOfSpeech,
    stem: stem,
    tense: tense,
    person: person,
    gender: gender,
    number: number,
    state: state,
  ),
  parseLabel: '$stem ${tense.toLowerCase()}',
);

/// Pump the sheet's Occurrences tab with [occurrences], opened from [at].
Future<_FakeRust> _pumpOccurrences(
  WidgetTester tester,
  List<HebrewOccurrence> occurrences, {
  ({int book, int chapter, int verse})? at,
  int? position,
  String word = 'בָּרָא',
  WordProximity? proximity,
}) async {
  SharedPreferences.setMockInitialValues({
    'occurrence_verse_english_only': false,
  });
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: WordInfoSheet(
            word: word,
            syriac: false,
            book: at?.book,
            chapter: at?.chapter,
            verse: at?.verse,
            position: position,
            useEnglishBookNames: true,
            proximity: proximity,
            proximityId: proximity == null ? null : 'self',
            sendInfoRequest: rust.onInfoRequest,
            sendOccurrencesRequest: rust.onOccurrencesRequest,
            sendVerseTextsRequest: rust.onVerseTextsRequest,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  rust.deliverWordInfo(word: word, root: 'ברא');
  await tester.pump(occurrencePrefetchDelay);
  rust.deliverOccurrences(occurrences);
  await tester.pumpAndSettle();
  // Switch to the Occurrences tab.
  await tester.tap(find.text('Occurrences'));
  await tester.pumpAndSettle();
  rust.deliverVerseTexts();
  await tester.pumpAndSettle();
  return rust;
}

/// Widen the list from the tapped word's exact form, where the tab opens, to
/// every form of the root.
Future<void> _showAllForms(WidgetTester tester) async {
  await tester.tap(find.text('All forms'));
  await tester.pumpAndSettle();
}

/// The count shown under the scope segment named [label].
String _scopeCount(WidgetTester tester, String label) {
  final segment = find
      .ancestor(of: find.text(label), matching: find.byType(Column))
      .first;
  final texts = tester.widgetList<Text>(
    find.descendant(of: segment, matching: find.byType(Text)),
  );
  return texts.last.data!;
}

/// The header's scope toggle. Its value type is private to the sheet, so it
/// is found by kind.
final _scopeToggle = find.byWidgetPredicate((w) => w is SegmentedButton);

/// Give the test a tall window, so a filter sheet with seven morphology groups
/// has them all on screen at once. The sheet scrolls on a real phone; these
/// tests are about which groups and values it offers, not about scrolling to
/// them.
void _useTallWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The reference of every occurrence row currently built, in the order they
/// appear on screen.
///
/// Sorted by screen position, not by the order the finder walks the tree: the
/// slivers above the anchor grow upwards, so their children are visited from
/// the bottom up and tree order says nothing about what a reader sees.
List<String> _visibleRefs(WidgetTester tester) {
  final rows = find.byType(SelectableText).evaluate().toList();
  final refs = [
    for (final row in rows)
      (
        y: tester.getTopLeft(find.byWidget(row.widget)).dy,
        ref:
            ((row.widget as SelectableText).textSpan!.children!.first
                    as TextSpan)
                .text!
                .trim(),
      ),
  ]..sort((a, b) => a.y.compareTo(b.y));
  return [for (final entry in refs) entry.ref];
}

void main() {
  testWidgets('the list opens on the verse the reader came from', (
    tester,
  ) async {
    // Forty verses, so the anchor is well past the first screenful.
    final occurrences = [
      for (var verse = 1; verse <= 40; verse++)
        _occurrence(book: 1, chapter: 1, verse: verse),
    ];
    await _pumpOccurrences(
      tester,
      occurrences,
      at: (book: 1, chapter: 1, verse: 30),
    );

    final refs = _visibleRefs(tester);
    expect(refs, isNotEmpty);
    expect(
      refs.first,
      'Genesis 1:30',
      reason: 'the reader\'s own verse should be the first row on screen',
    );
    // And the rows below it still read forwards.
    expect(refs.take(3), ['Genesis 1:30', 'Genesis 1:31', 'Genesis 1:32']);
  });

  testWidgets('verses above the anchor stay in reading order', (tester) async {
    final occurrences = [
      for (var verse = 1; verse <= 40; verse++)
        _occurrence(book: 1, chapter: 1, verse: verse),
    ];
    final rust = await _pumpOccurrences(
      tester,
      occurrences,
      at: (book: 1, chapter: 1, verse: 30),
    );

    // Scroll back above the anchor: the verses before it must ascend towards it,
    // not run backwards.
    // Drag the list itself: the first row in tree order is above the anchor,
    // off screen, and dragging it would land on whatever covers that point.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    // Rows scrolled into view ask for their text; answer them.
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    final refs = _visibleRefs(tester);
    final verses = [for (final ref in refs) int.parse(ref.split(':').last)];
    expect(verses.length, greaterThan(2));
    expect(
      verses,
      orderedEquals(List<int>.of(verses)..sort()),
      reason: 'rows above the anchor must still read downwards: $refs',
    );
  });

  testWidgets('with no reader location the list starts at the beginning', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      for (var verse = 1; verse <= 40; verse++)
        _occurrence(book: 1, chapter: 1, verse: verse),
    ]);
    expect(_visibleRefs(tester).first, 'Genesis 1:1');
  });

  testWidgets('the count line reports verses and tokens apart', (tester) async {
    // Two tokens in one verse, one in another: two verses, three occurrences.
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1, position: 1),
      _occurrence(book: 1, chapter: 1, verse: 1, position: 2),
      _occurrence(book: 1, chapter: 2, verse: 1, position: 1),
    ]);
    expect(find.text('2 verses · 3×'), findsOneWidget);
  });

  testWidgets('a verse with one occurrence reports only its verse count', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 2, verse: 1),
    ]);
    expect(find.text('2 verses'), findsOneWidget);
  });

  testWidgets('book distribution opens a labelled multi-select filter', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 2, chapter: 1, verse: 1),
      _occurrence(book: 6, chapter: 1, verse: 1),
    ]);

    await tester.tap(find.byTooltip('Open book distribution and filters'));
    await tester.pumpAndSettle();

    expect(find.text('Occurrence distribution'), findsOneWidget);
    expect(find.text('Scroll to see all 39 books'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
    final earlierButton = find.ancestor(
      of: find.byTooltip('Earlier books'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(earlierButton).onPressed, isNull);
    await tester.tap(find.byTooltip('Later books'));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(earlierButton).onPressed, isNotNull);
    expect(find.text('Genesis (1)'), findsOneWidget);
    expect(find.text('Exodus (1)'), findsOneWidget);
    expect(find.text('Torah  תּוֹרָה'), findsOneWidget);
    expect(find.text("Nevi'im  נְבִיאִים"), findsOneWidget);

    await tester.tap(find.text('Genesis (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exodus (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('2 books'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);
  });

  testWidgets('book categories can be selected and cleared together', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 5, chapter: 1, verse: 1),
      _occurrence(book: 6, chapter: 1, verse: 1),
    ]);

    await tester.tap(find.byTooltip('Open book distribution and filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Torah  תּוֹרָה'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('5 books'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);

    await tester.tap(find.byTooltip('Open book distribution and filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    // Only the starting exact-form scope is left, which the toggle shows.
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('3 verses'), findsOneWidget);
  });

  testWidgets('highlighting follows the position, not the spelling', (
    tester,
  ) async {
    // The verse holds בָּרָא twice (lexical positions 1 and 2) but only the
    // second is an occurrence of the root. Matching on the text would light up
    // both.
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1, position: 2),
    ]);

    final row = tester.widget<SelectableText>(
      find.byType(SelectableText).first,
    );
    final spans = row.textSpan!.children!.cast<TextSpan>();
    final highlighted = [
      for (final span in spans)
        if (span.style?.backgroundColor != null) span.text,
    ];
    expect(highlighted, ['בָּרָא'], reason: 'exactly one word, not both');
    // Confirm it is the second of the two, by index among the verse's words.
    final texts = [for (final span in spans) span.text];
    final highlightedIndex = spans.toList().indexWhere(
      (s) => s.style?.backgroundColor != null,
    );
    expect(texts[highlightedIndex], 'בָּרָא');
    expect(
      texts.sublist(0, highlightedIndex).where((t) => t == 'בָּרָא').length,
      1,
      reason: 'the earlier identical word must be left unhighlighted',
    );
  });

  testWidgets('the tab opens on the exact form, every form one tap away', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 2, verse: 1, surface: 'וַיִּבְרָא'),
      _occurrence(book: 1, chapter: 3, verse: 1),
    ]);
    // The tapped word's own surface form first.
    expect(_scopeCount(tester, 'Exact'), '2');
    expect(find.text('2 verses'), findsOneWidget);

    await _showAllForms(tester);
    expect(find.text('All occurrences'), findsOneWidget);
    expect(find.text('3 verses'), findsOneWidget);

    await tester.tap(find.text('Exact'));
    await tester.pumpAndSettle();
    expect(find.text('2 verses'), findsOneWidget);
  });

  testWidgets('a form chosen in the sheet lights neither scope', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 2, verse: 1, surface: 'וַיִּבְרָא'),
    ]);
    await _showAllForms(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Form'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('וַיִּבְרָא').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SegmentedButton<Object>>(_scopeToggle);
    expect(toggle.selected, isEmpty);
    expect(find.text('1 verse'), findsOneWidget);
  });

  testWidgets('no exact-match scope when the word is not in the list', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1, surface: 'וַיִּבְרָא'),
    ]);
    expect(_scopeToggle, findsNothing);
    expect(find.text('All occurrences'), findsOneWidget);
  });

  testWidgets('same parse matches the tapped token, across forms', (
    tester,
  ) async {
    _useTallWindow(tester);
    await _pumpOccurrences(
      tester,
      [
        // The tapped token. The same spelling also stands elsewhere under
        // another analysis, which must not be the one taken.
        _occurrence(book: 1, chapter: 1, verse: 1, position: 2),
        _occurrence(book: 1, chapter: 5, verse: 1, stem: 'Niphal'),
        // Another spelling with the tapped token's parse.
        _occurrence(book: 1, chapter: 2, verse: 1, surface: 'וּבָרָא'),
        // Another spelling, plural: out until number is released.
        _occurrence(
          book: 1,
          chapter: 3,
          verse: 1,
          surface: 'בָּרְאוּ',
          number: 'Plural',
        ),
      ],
      at: (book: 1, chapter: 1, verse: 1),
      position: 2,
    );

    expect(_scopeCount(tester, 'Same parse'), '2');
    await tester.tap(find.text('Same parse'));
    await tester.pumpAndSettle();
    expect(find.text('2 verses'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<Object>>(_scopeToggle).selected,
      hasLength(1),
    );

    // Broaden one dimension in the sheet: the rest of the parse still holds.
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    final numberHeading = find
        .ancestor(of: find.text('NUMBER'), matching: find.byType(Row))
        .first;
    await tester.tap(
      find.descendant(of: numberHeading, matching: find.text('Any')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('3 verses'), findsOneWidget);
    // With number released the filter is no longer the tapped token's parse.
    expect(
      tester.widget<SegmentedButton<Object>>(_scopeToggle).selected,
      isEmpty,
    );
  });

  testWidgets('without a location, same parse takes the commonest analysis', (
    tester,
  ) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1, stem: 'Niphal'),
      _occurrence(book: 1, chapter: 2, verse: 1),
      _occurrence(book: 1, chapter: 3, verse: 1),
      _occurrence(book: 1, chapter: 4, verse: 1, surface: 'וּבָרָא'),
    ]);
    // The two Qal tokens outvote the Niphal, and the other spelling joins them.
    expect(_scopeCount(tester, 'Same parse'), '3');
  });

  testWidgets('the scope toggle fits a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pumpOccurrences(tester, [
      for (var i = 0; i < 1200; i++)
        _occurrence(
          book: 1 + i ~/ 100,
          chapter: 1 + i % 100 ~/ 10,
          verse: 1 + i % 10,
          surface: i.isEven ? 'בָּרָא' : 'וּבָרָא',
        ),
    ]);
    expect(_scopeCount(tester, 'Exact'), '600');
    expect(_scopeCount(tester, 'Same parse'), '1200');
    expect(_scopeCount(tester, 'All forms'), '1200');
    expect(tester.takeException(), isNull);
    // The counts grow with the corpus, so they are what must not be cut. The
    // scope names are not measured: the test font's square glyphs are far
    // wider than a real font's.
    for (final count in const ['600', '1200']) {
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: find.text(count), matching: find.byType(RichText)),
      )) {
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$count is cut');
      }
    }
  });

  testWidgets('the filter sheet offers parse before form', (tester) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
    ]);
    await _showAllForms(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    final tabs = tester.widget<TabBar>(find.byType(TabBar).last);
    expect([for (final tab in tabs.tabs) (tab as Tab).text], ['Parse', 'Form']);
    // The parse tab is the one on screen, not the form list.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('All forms'),
      ),
      findsNothing,
    );
  });

  testWidgets('the parse tab groups morphology by dimension', (tester) async {
    _useTallWindow(tester);
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(
        book: 1,
        chapter: 2,
        verse: 1,
        surface: 'הִבְרִיא',
        stem: 'Hiphil',
        tense: 'Imperfect',
        number: 'Plural',
      ),
    ]);
    await _showAllForms(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    // Each component is its own group with its own values, rather than one
    // entry per whole "Qal perfect 3ms" combination.
    for (final heading in const [
      'PART OF SPEECH',
      'STEM',
      'TENSE',
      'PERSON',
      'GENDER',
      'NUMBER',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: 'missing $heading');
    }
    // State is carried by neither token, so its group is left out rather than
    // shown empty.
    expect(find.text('STATE'), findsNothing);

    // Values are per-dimension and counted.
    expect(find.text('Qal  1'), findsOneWidget);
    expect(find.text('Hiphil  1'), findsOneWidget);
    expect(find.text('Singular  1'), findsOneWidget);
    expect(find.text('Plural  1'), findsOneWidget);
  });

  testWidgets('parse dimensions combine, and each narrows the list', (
    tester,
  ) async {
    _useTallWindow(tester);
    final rust = await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1, number: 'Singular'),
      _occurrence(
        book: 1,
        chapter: 2,
        verse: 1,
        stem: 'Hiphil',
        number: 'Singular',
      ),
      _occurrence(
        book: 1,
        chapter: 3,
        verse: 1,
        surface: 'וַיַּבְרִיאוּ',
        stem: 'Hiphil',
        number: 'Plural',
      ),
    ]);
    await _showAllForms(tester);
    expect(find.text('All occurrences'), findsOneWidget);
    expect(find.text('3 verses'), findsOneWidget);

    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    // One dimension: the two Hiphils.
    await tester.tap(find.text('Hiphil  2'));
    await tester.pumpAndSettle();
    // A second dimension ANDs with the first, leaving the plural Hiphil — a
    // combination that never had to exist as its own list entry. Its count is
    // faceted by the Hiphil already chosen, so it reads 1 and not 2.
    await tester.tap(find.text('Plural  1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('hiphil · plural'), findsOneWidget);
    expect(find.text('1 verse'), findsOneWidget);
    // The surviving verse is new to the list, so its text is a fresh request.
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(_visibleRefs(tester), ['Genesis 3:1']);
  });

  testWidgets('a dimension can be released back to Any', (tester) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 2, verse: 1, stem: 'Hiphil'),
    ]);
    await _showAllForms(tester);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hiphil  1'));
    await tester.pumpAndSettle();
    expect(find.text('Any'), findsOneWidget);

    await tester.tap(find.text('Any'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('All occurrences'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);
  });

  testWidgets('copying references puts the filtered list on the clipboard', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 2, verse: 3),
    ]);

    await tester.tap(find.byTooltip('Copy references'));
    await tester.pumpAndSettle();
    expect(copied, ['Genesis 1:1\nGenesis 2:3']);
  });

  testWidgets('proximity finds verses shared with the other open words', (
    tester,
  ) async {
    _useTallWindow(tester);
    final proximity = WordProximity();
    addTearDown(proximity.dispose);
    // Another open pane, whose word stands in Genesis 1:1, 1:3 and 3:1.
    proximity.register(
      ProximitySource(
        id: 'other',
        label: () => 'אֱלֹהִים',
        hits: () => const [
          ProximityHit(book: 1, chapter: 1, verse: 1, positions: [2]),
          ProximityHit(book: 1, chapter: 1, verse: 3, positions: [2]),
          ProximityHit(book: 1, chapter: 3, verse: 1, positions: [2]),
        ],
      ),
    );
    final rust = await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 1, verse: 5),
      _occurrence(book: 1, chapter: 2, verse: 3),
    ], proximity: proximity);
    expect(_visibleRefs(tester), ['Genesis 1:1', 'Genesis 1:5', 'Genesis 2:3']);

    await tester.tap(find.byTooltip('Find passages with the other open words'));
    await tester.pumpAndSettle();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    // Same verse by default, and every open word included.
    expect(find.text('Same verse'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(
            find.byKey(const ValueKey('proximity-word-other')),
          )
          .selected,
      isTrue,
    );
    expect(_visibleRefs(tester), ['Genesis 1:1']);
    expect(find.text('1 verse'), findsOneWidget);

    // Both words highlight in the shared verse.
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    final highlighted = [
      for (final span in text.children!.whereType<TextSpan>())
        if (span.style?.backgroundColor != null) span.text,
    ];
    expect(highlighted, ['בָּרָא', 'בָּרָא']);

    await tester.tap(find.byKey(const ValueKey('proximity-distance')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Within 2 verses').last);
    await tester.pumpAndSettle();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(_visibleRefs(tester), ['Genesis 1:1', 'Genesis 1:3', 'Genesis 1:5']);
    expect(find.text('1 passage · 3 verses'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proximity-word-other')));
    await tester.pumpAndSettle();
    expect(
      find.text('Include another open word to find passages with it'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Show only this word'));
    await tester.pumpAndSettle();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();
    expect(_visibleRefs(tester), ['Genesis 1:1', 'Genesis 1:5', 'Genesis 2:3']);
  });

  testWidgets('proximity is only offered with another word open', (
    tester,
  ) async {
    final proximity = WordProximity();
    addTearDown(proximity.dispose);
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
    ], proximity: proximity);

    expect(
      find.byTooltip('Find passages with the other open words'),
      findsNothing,
    );
    expect(proximity.sources.single.id, 'self');
  });
}
