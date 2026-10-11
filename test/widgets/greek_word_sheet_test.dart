import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/issue_reporting.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/greek_word_sheet.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';
import 'package:haqor/src/word_proximity.dart';

GreekOccurrenceEntry _at(int book, int chapter, int verse, int position) =>
    GreekOccurrenceEntry(
      book: book,
      chapter: chapter,
      verse: verse,
      position: position,
      lemma: '',
      grammar: '',
    );

/// Answers [request] with a word of [lemma] standing at [occurrences].
void _deliver(
  GetGreekWord request, {
  required String word,
  required String lemma,
  List<GreekOccurrenceEntry> occurrences = const [],
  List<GreekLexemeEntry> lexemes = const [],
}) {
  assignRustSignal['GreekWordInfo']!(
    GreekWordInfo(
      requestId: request.requestId,
      found: true,
      word: word,
      lemma: lemma,
      gloss: 'gloss',
      english: '',
      grammar: '',
      grammarDescription: '',
      name: null,
      root: lemma,
      roots: [lemma],
      lexemes: lexemes,
      occurrences: [
        for (final o in occurrences)
          GreekOccurrenceEntry(
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            position: o.position,
            lemma: lemma,
            grammar: '',
          ),
      ],
      parses: const [],
      syriacEquivalents: const [],
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a Greek word is bookmarked as Greek, its root its lemma', (
    tester,
  ) async {
    final requests = <GetGreekWord>[];
    final toggled = <StudyWord>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GreekWordSheet(
            word: 'λόγου',
            book: 43,
            chapter: 1,
            verse: 1,
            position: 3,
            sendRequest: requests.add,
            sendVerseTextsRequest: (_) {},
            isStudyBookmarked: (_) => false,
            onToggleStudyBookmark: (word) async {
              toggled.add(word);
              return true;
            },
          ),
        ),
      ),
    );
    _deliver(requests.single, word: 'λόγου', lemma: 'λόγος');
    await tester.pump();

    await tester.tap(find.byTooltip('Study bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text('Bookmark this form'),
        matching: find.byType(CheckedPopupMenuItem<StudyWordKind>),
      ),
    );
    await tester.pumpAndSettle();
    final form = toggled.single;
    expect(
      (form.root, form.surface, form.kind, form.language),
      ('λόγος', 'λόγου', StudyWordKind.form, StudyWordLanguage.greek),
    );
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
  });

  testWidgets('admin mode logs an issue about a Greek word', (tester) async {
    SharedPreferences.setMockInitialValues({'tutor_admin_mode': true});
    final requests = <GetGreekWord>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GreekWordSheet(
            word: 'λόγου',
            book: 43,
            chapter: 1,
            verse: 1,
            position: 3,
            sendRequest: requests.add,
            sendVerseTextsRequest: (_) {},
          ),
        ),
      ),
    );
    _deliver(requests.single, word: 'λόγου', lemma: 'λόγος');
    await tester.pumpAndSettle();
    expect(find.byType(IssueReportButton), findsOneWidget);
  });

  testWidgets('another word of the root opens in the pane', (tester) async {
    final requests = <GetGreekWord>[];
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GreekWordSheet(
            word: 'λόγου',
            book: 43,
            chapter: 1,
            verse: 1,
            position: 3,
            sendRequest: requests.add,
            sendVerseTextsRequest: (_) {},
            onOpenLemma: opened.add,
          ),
        ),
      ),
    );
    _deliver(
      requests.single,
      word: 'λόγου',
      lemma: 'λόγος',
      lexemes: const [
        GreekLexemeEntry(
          lemma: 'λέγω',
          gloss: 'say',
          occurrences: 1,
          isCurrent: false,
          entries: [],
        ),
        GreekLexemeEntry(
          lemma: 'λόγος',
          gloss: 'word',
          occurrences: 2,
          isCurrent: true,
          entries: [],
        ),
      ],
    );
    await tester.pump();
    // The word's own form is not a link to itself.
    expect(find.byKey(const ValueKey('open-lemma-λόγος')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-lemma-λέγω')));
    expect(opened, ['λέγω']);
  });

  testWidgets('a proximity search joins the open Greek words alone', (
    tester,
  ) async {
    final requests = <GetGreekWord>[];
    final proximity = WordProximity();
    addTearDown(proximity.dispose);
    // A Hebrew pane open beside them takes no part: its positions are the
    // Peshitta's.
    proximity.register(
      ProximitySource(
        id: 'hebrew',
        label: () => 'מלתא',
        hits: () => const [ProximityHit(book: 43, chapter: 1, verse: 1)],
      ),
    );
    Widget pane(String id, String word, double top) => Positioned(
      top: top,
      left: 0,
      right: 0,
      height: 400,
      child: GreekWordSheet(
        word: word,
        book: 43,
        chapter: 1,
        verse: 1,
        position: 0,
        sendRequest: requests.add,
        sendVerseTextsRequest: (_) {},
        proximity: proximity,
        proximityId: id,
      ),
    );
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [pane('a', 'λόγος', 0), pane('b', 'θεός', 450)],
          ),
        ),
      ),
    );
    _deliver(
      requests[0],
      word: 'λόγος',
      lemma: 'λόγος',
      occurrences: [_at(43, 1, 1, 3), _at(43, 1, 14, 2), _at(44, 4, 4, 5)],
    );
    _deliver(
      requests[1],
      word: 'θεός',
      lemma: 'θεός',
      occurrences: [_at(43, 1, 1, 10), _at(45, 1, 1, 7)],
    );
    await tester.pump();
    final first = find.byType(GreekWordSheet).first;
    await tester.tap(
      find.descendant(of: first, matching: find.text('Occurrences')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: first,
        matching: find.byTooltip(kProximityToggleTooltip),
      ),
    );
    await tester.pumpAndSettle();
    expect(proximity.enabled, isTrue);
    expect(
      find.descendant(of: first, matching: find.text('θεός')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('מלתא')),
      findsNothing,
    );
    // John 1:1 alone holds both words, each marked where it stands.
    final rows = tester
        .widgetList<OccurrenceVerseRow>(
          find.descendant(of: first, matching: find.byType(OccurrenceVerseRow)),
        )
        .toList();
    expect(
      [for (final r in rows) (r.bookIndex, r.chapter, r.verse)],
      [(42, 1, 1)],
    );
    expect(rows.single.positions, containsAll(<int>[3, 10]));
    expect(rows.single.greek, isTrue);
  });
}
