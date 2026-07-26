import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

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

  void onInfoRequest(GetWordInfo request) {}

  void onOccurrencesRequest(GetWordOccurrences request) {}

  void deliverWordInfo({required String word, required String root}) {
    assignRustSignal['WordInfo']!(
      WordInfo(
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
      ).bincodeSerialize(),
      Uint8List(0),
    );
  }

  void deliverOccurrences(List<HebrewOccurrence> occurrences) {
    assignRustSignal['WordOccurrences']!(
      WordOccurrences(
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
  String word = 'בָּרָא',
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
            useEnglishBookNames: true,
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
  await tester.pump();
  rust.deliverOccurrences(occurrences);
  await tester.pumpAndSettle();
  // Switch to the Occurrences tab.
  await tester.tap(find.text('Occurrences'));
  await tester.pumpAndSettle();
  rust.deliverVerseTexts();
  await tester.pumpAndSettle();
  return rust;
}

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
    await _pumpOccurrences(
      tester,
      occurrences,
      at: (book: 1, chapter: 1, verse: 30),
    );

    // Scroll back above the anchor: the verses before it must ascend towards it,
    // not run backwards.
    await tester.drag(find.byType(SelectableText).first, const Offset(0, 400));
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

  testWidgets('the tab opens unfiltered, on every form of the root', (
    tester,
  ) async {
    // The looked-up word is only one of the root's forms; the others are the
    // reason to open the list at all.
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
      _occurrence(book: 1, chapter: 2, verse: 1, surface: 'וַיִּבְרָא'),
    ]);
    expect(find.text('All occurrences'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);
  });

  testWidgets('the filter sheet offers parse before form', (tester) async {
    await _pumpOccurrences(tester, [
      _occurrence(book: 1, chapter: 1, verse: 1),
    ]);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();

    final tabs = tester.widget<TabBar>(find.byType(TabBar).last);
    expect([for (final tab in tabs.tabs) (tab as Tab).text], ['Parse', 'Form']);
    // The parse tab is the one on screen, not the form list.
    expect(find.text('All forms'), findsNothing);
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
}
