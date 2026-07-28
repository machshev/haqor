import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

/// A name is often built from two roots, not one.
///
/// אֱלִיעֶזֶר is אל "god" and עזר "help", and BDB prints it under only the first
/// of them — so which root the sheet shows is a choice, and taking it has to
/// move both tabs: the Lexicon to that root's lexemes, the Occurrences to its
/// concordance. These tests drive the sheet through its send seams and watch
/// what it asks Rust for.
class _FakeRust {
  final List<GetWordInfo> infoRequests = [];
  final List<GetWordOccurrences> occurrenceRequests = [];
  final List<GetVerseTexts> verseRequests = [];

  void onInfoRequest(GetWordInfo request) => infoRequests.add(request);
  void onOccurrencesRequest(GetWordOccurrences request) =>
      occurrenceRequests.add(request);
  void onVerseTextsRequest(GetVerseTexts request) => verseRequests.add(request);

  /// Eliezer as the OT branch answers it: the parse resolves אלה, and both of
  /// the name's roots come back so the sheet knows there is a choice.
  void deliverEliezer({required String selected}) {
    assignRustSignal['WordInfo']!(
      WordInfo(
        found: true,
        word: 'אֱלִיעֶזֶר',
        root: selected,
        gloss: 'Eliezer',
        partOfSpeech: 'noun',
        gender: null,
        number: null,
        prefix: null,
        suffix: null,
        prepositions: null,
        article: false,
        vavCon: false,
        bdbEntries: [
          BdbSummary(
            headword: selected == 'אלה' ? 'אֵל' : 'עֵזֶר',
            gloss: selected == 'אלה' ? 'god' : 'help; succour',
            contentJson: '',
            posCategory: 'noun',
          ),
        ],
        sedraEntries: const [],
        person: null,
        state: null,
        tense: null,
        form: null,
        roots: [
          RootChoice(root: 'אלה', gloss: 'god', isPrimary: selected == 'אלה'),
          RootChoice(
            root: 'עזר',
            gloss: 'help; succour',
            isPrimary: selected == 'עזר',
          ),
        ],
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
                text: '${ref.book}:${ref.chapter}:${ref.verse} אֱלִיעֶזֶר',
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
  required int chapter,
  required int verse,
  String surface = 'אֱלִיעֶזֶר',
  String state = 'Absolute',
}) => HebrewOccurrence(
  book: 1,
  chapter: chapter,
  verse: verse,
  position: 1,
  surface: surface,
  parse: OccurrenceParse(
    partOfSpeech: 'Noun',
    stem: '',
    tense: '',
    person: '',
    gender: 'Masculine',
    number: 'Singular',
    state: state,
  ),
  parseLabel: 'noun $state',
);

Future<_FakeRust> _pumpSheet(
  WidgetTester tester, {
  Future<bool> Function(String root, String surface)? onToggleStudyBookmark,
  Future<void> Function(String root, String surface)? onEditStudyNote,
}) async {
  SharedPreferences.setMockInitialValues({
    'occurrence_verse_english_only': false,
  });
  final rust = _FakeRust();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 700,
          child: WordInfoSheet(
            word: 'אֱלִיעֶזֶר',
            syriac: false,
            useEnglishBookNames: true,
            sendInfoRequest: rust.onInfoRequest,
            sendOccurrencesRequest: rust.onOccurrencesRequest,
            sendVerseTextsRequest: rust.onVerseTextsRequest,
            onToggleStudyBookmark: onToggleStudyBookmark,
            onEditStudyNote: onEditStudyNote,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  rust.deliverEliezer(selected: 'אלה');
  await tester.pump();
  rust.deliverOccurrences([_occurrence(chapter: 15, verse: 2)]);
  await tester.pumpAndSettle();
  return rust;
}

void main() {
  testWidgets('a resolved root can be bookmarked and noted from the sheet', (
    tester,
  ) async {
    (String, String)? bookmarked;
    (String, String)? noted;
    await _pumpSheet(
      tester,
      onToggleStudyBookmark: (root, surface) async {
        bookmarked = (root, surface);
        return true;
      },
      onEditStudyNote: (root, surface) async {
        noted = (root, surface);
      },
    );

    await tester.tap(find.byTooltip('Bookmark this root'));
    await tester.pump();
    expect(bookmarked, ('אלה', 'אֱלִיעֶזֶר'));
    expect(find.byTooltip('Remove root bookmark'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit study note'));
    await tester.pump();
    expect(noted, ('אלה', 'אֱלִיעֶזֶר'));
  });

  testWidgets('both of a name’s roots are offered, the resolved one selected', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.text('אלה'), findsOneWidget);
    expect(
      find.text('עזר'),
      findsOneWidget,
      reason: 'Eliezer is God + help, and the sheet should say so',
    );
  });

  testWidgets('picking the other root moves both tabs to it', (tester) async {
    final rust = await _pumpSheet(tester);
    expect(rust.infoRequests.single.root, isNull, reason: 'opens on the parse');
    expect(rust.occurrenceRequests.single.root, isNull);

    await tester.tap(find.text('עזר'));
    await tester.pumpAndSettle();

    expect(
      rust.infoRequests.last.root,
      'עזר',
      reason: 'the Lexicon tab should be re-fetched for the chosen root',
    );
    expect(
      rust.occurrenceRequests.last.root,
      'עזר',
      reason: 'and so should the concordance, where the name now stands',
    );
    // The word itself is unchanged — this is the same token read under another
    // of its roots, not a different lookup.
    expect(rust.infoRequests.last.word, 'אֱלִיעֶזֶר');
  });

  testWidgets('choosing a root a second time asks nothing new', (tester) async {
    final rust = await _pumpSheet(tester);
    await tester.tap(find.text('אלה'));
    await tester.pumpAndSettle();
    expect(
      rust.infoRequests.length,
      1,
      reason: 'tapping the root already shown should not re-fetch',
    );
  });

  testWidgets('the occurrence filters do not survive a change of root', (
    tester,
  ) async {
    final rust = await _pumpSheet(tester);
    await tester.tap(find.text('Occurrences'));
    await tester.pumpAndSettle();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    // Filter down to one parse, then move to the other root: a cut made among
    // אלה's words says nothing about עזר's.
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Absolute').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('All occurrences'), findsNothing);

    await tester.tap(find.text('עזר').first);
    // Not pumpAndSettle: with the lists cleared the tab spins until the new
    // answers arrive, and a spinner never settles.
    await tester.pump();
    rust.deliverEliezer(selected: 'עזר');
    await tester.pump();
    rust.deliverOccurrences([
      _occurrence(chapter: 15, verse: 2),
      _occurrence(chapter: 2, verse: 18, surface: 'עֵזֶר'),
    ]);
    await tester.pumpAndSettle();
    rust.deliverVerseTexts();
    await tester.pumpAndSettle();

    // The new root's list is unfiltered: the cut went with the root it was made
    // under, so both of עזר's verses are listed.
    expect(find.text('All occurrences'), findsOneWidget);
    expect(find.text('2 verses'), findsOneWidget);
  });
}
