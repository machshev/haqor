import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/archaeology_page.dart';

PassageSpan _span(int book, int chapter, int verse, [int? lastVerse]) =>
    PassageSpan(
      book: book,
      chapter: chapter,
      verse: verse,
      lastChapter: chapter,
      lastVerse: lastVerse ?? verse,
    );

NameSummaryEntry _person(int id, String name) => NameSummaryEntry(
  id: id,
  name: name,
  kind: 'person',
  description: 'King',
  origin: '',
  occurrences: 1,
);

ArtifactEntry _artifact({
  required int id,
  required String name,
  required int year,
  String kind = 'stele',
  List<ArtifactAttestationEntry> attestations = const [],
  List<ArtifactPassageEntry> passages = const [],
}) => ArtifactEntry(
  id: id,
  key: name.toLowerCase().replaceAll(' ', '-'),
  name: name,
  otherNames: const [],
  kind: kind,
  date: year < 0 ? 'c. ${-year} BC' : 'AD $year',
  year: year,
  script: 'Akkadian cuneiform',
  foundSite: 'Nineveh, Iraq',
  foundYear: 1830,
  foundPlace: _person(0, ''),
  museum: 'British Museum, London',
  wikipedia: name,
  wikidata: '',
  summary: 'What $name says.',
  attestations: attestations,
  passages: passages,
);

final _sources = [
  ArtifactSourceEntry(id: 'mykytiuk-2014', citation: 'Mykytiuk 2014', url: ''),
];

/// The Mesha Stele (strong); Sennacherib's annals (2 Kings 18:13–16); and
/// the Erastus inscription, possible only.
final _artifacts = [
  _artifact(
    id: 1,
    name: 'Mesha Stele',
    year: -840,
    attestations: [
      ArtifactAttestationEntry(
        person: _person(10, 'Mesha'),
        strength: 'strong',
        how: 'I am Mesha, king of Moab.',
        source: 'mykytiuk-2014',
      ),
    ],
  ),
  _artifact(
    id: 2,
    name: 'Annals of Sennacherib',
    year: -691,
    kind: 'prism',
    attestations: [
      ArtifactAttestationEntry(
        person: _person(11, 'Hezekiah'),
        strength: 'strong',
        how: 'Hezekiah the Judahite.',
        source: 'mykytiuk-2014',
      ),
    ],
    passages: [
      ArtifactPassageEntry(
        passage: _span(11, 18, 13, 16),
        strength: 'strong',
        how: 'The cities of Judah taken.',
        source: 'mykytiuk-2014',
      ),
    ],
  ),
  _artifact(
    id: 3,
    name: 'Erastus inscription',
    year: 50,
    kind: 'inscription',
    attestations: [
      ArtifactAttestationEntry(
        person: _person(12, 'Erastus'),
        strength: 'possible',
        how: 'An aedile of Corinth.',
        source: 'mykytiuk-2014',
      ),
    ],
  ),
];

void _deliver(GetArtifacts request) {
  assignRustSignal['Artifacts']!(
    Artifacts(
      requestId: request.requestId,
      entries: _artifacts,
      sources: _sources,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  testWidgets('the index groups finds by era and filters them', (tester) async {
    final requests = <GetArtifacts>[];
    await tester.pumpWidget(
      MaterialApp(home: ArchaeologyPage(sendRequest: requests.add)),
    );
    _deliver(requests.single);
    await tester.pumpAndSettle();

    expect(find.text('3 finds'), findsOneWidget);
    expect(find.text('The kings of Israel and Judah'), findsOneWidget);
    expect(find.text('Assyria and Judah'), findsOneWidget);
    expect(find.text('The New Testament'), findsOneWidget);
    expect(find.text('c. 840 BC · Mesha'), findsOneWidget);

    // Strong links only leaves out Erastus.
    await tester.tap(find.byKey(const ValueKey('artifact-strong-only')));
    await tester.pumpAndSettle();
    expect(find.text('2 finds'), findsOneWidget);
    expect(find.text('Erastus inscription'), findsNothing);

    // A search finds a find by the person it names.
    await tester.enterText(
      find.byKey(const ValueKey('artifact-search')),
      'hezekiah',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 find'), findsOneWidget);
    expect(find.text('Annals of Sennacherib'), findsOneWidget);
  });

  testWidgets('a find shows its links, and a passage opens the reader', (
    tester,
  ) async {
    final requests = <GetArtifacts>[];
    final opened = <(int, int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ArchaeologyPage(
                  sendRequest: requests.add,
                  useEnglishBookNames: true,
                  onNavigateToPassage: (b, c, v) => opened.add((b, c, v)),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // The page's spinner never settles before its reply.
    await tester.pump(const Duration(milliseconds: 500));
    _deliver(requests.single);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Annals of Sennacherib'));
    await tester.pumpAndSettle();
    expect(find.text('Names'), findsOneWidget);
    expect(find.text('Hezekiah'), findsOneWidget);
    expect(find.text('Bears on'), findsOneWidget);
    expect(
      find.text('The cities of Judah taken.\nSource: Mykytiuk 2014'),
      findsOneWidget,
    );
    expect(find.text('Now: British Museum, London'), findsOneWidget);

    await tester.tap(find.text('2 Kings 18:13–16'));
    await tester.pumpAndSettle();
    // Book indexes are zero-based: 2 Kings is the eleventh book.
    expect(opened, [(10, 18, 13)]);
    expect(find.byType(ArchaeologyPage), findsNothing);
  });

  testWidgets('a chapter puts its passages first, then its people', (
    tester,
  ) async {
    final requests = <GetChapterArtifacts>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterArtifactsSheet(
            bookIndex: 10,
            chapter: 18,
            useEnglishBookNames: true,
            sendRequest: requests.add,
          ),
        ),
      ),
    );
    expect(requests.single.book, 11);
    expect(requests.single.chapter, 18);
    assignRustSignal['ChapterArtifacts']!(
      ChapterArtifacts(
        requestId: requests.single.requestId,
        book: 11,
        chapter: 18,
        entries: [
          ChapterArtifactEntry(
            artifact: _artifacts[1],
            verses: [13, 14, 15, 16],
            people: [_person(11, 'Hezekiah')],
          ),
          ChapterArtifactEntry(
            artifact: _artifacts[0],
            verses: const [],
            people: [_person(10, 'Mesha')],
          ),
        ],
        sources: _sources,
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archaeology in 2 Kings 18'), findsOneWidget);
    expect(find.text('About this passage'), findsOneWidget);
    expect(find.text('Verses 13–16 · c. 691 BC'), findsOneWidget);
    expect(find.text('Naming someone in this chapter'), findsOneWidget);
    expect(find.text('Mesha · c. 840 BC'), findsOneWidget);
    final passage = tester.getTopLeft(find.text('Annals of Sennacherib'));
    final person = tester.getTopLeft(find.text('Mesha Stele'));
    expect(passage.dy, lessThan(person.dy));
  });

  test('a year falls in its era', () {
    expect(archaeologyEra(-1208), 'Before the kings');
    expect(archaeologyEra(-701), 'Assyria and Judah');
    expect(archaeologyEra(31), 'The New Testament');
  });
}
