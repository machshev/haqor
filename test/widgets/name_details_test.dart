import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/name_details.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/word_info_sheet.dart';

/// A square of land round the Levant, and a lake in it.
final _basemap = Basemap.parse(
  '{"land":[[30,28,40,28,40,36,30,36]],"lakes":[[35.4,31.2,35.6,31.2,35.6,31.6,35.4,31.6]],'
  '"rivers":[[35.6,32.7,35.5,31.8]]}',
);

NameSummaryEntry _summary(
  int id,
  String name, {
  String kind = 'person',
  String description = '',
  String origin = '',
  int occurrences = 1,
}) => NameSummaryEntry(
  id: id,
  name: name,
  kind: kind,
  description: description,
  origin: origin,
  occurrences: occurrences,
);

void _deliverEntity(
  GetNameEntity request,
  NameSummaryEntry summary, {
  List<NameLinkEntry> links = const [],
  List<PlaceLocationEntry> locations = const [],
  List<WordOccurrence> verses = const [],
}) {
  assignRustSignal['NameEntityInfo']!(
    NameEntityInfo(
      requestId: request.requestId,
      found: true,
      summary: summary,
      category: summary.kind == 'place' ? 'Place' : 'Male',
      text: 'A king of Northern Israel\na son of Jeroboam.',
      forms: [
        NameFormEntry(
          hebrew: 'זְכַרְיָהוּ',
          english: const ['Zechariah', 'Zachariah'],
          significance: 'Named',
        ),
      ],
      links: links,
      locations: locations,
      verses: verses,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  testWidgets('a person page shows who they are and opens their relatives', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 7,
          title: 'Zechariah',
          sendRequest: requests.add,
          basemap: _basemap,
        ),
      ),
    );
    expect(requests.single.id, 7);
    _deliverEntity(
      requests.single,
      _summary(
        7,
        'Zechariah',
        description: 'King living at the time of Divided Monarchy',
        origin: 'Israel',
        occurrences: 3,
      ),
      links: [
        NameLinkEntry(
          relation: 'father',
          flag: '',
          other: _summary(9, 'Jeroboam', description: 'King'),
        ),
      ],
      verses: [
        WordOccurrence(book: 11, chapter: 14, verse: 29),
        WordOccurrence(book: 11, chapter: 15, verse: 8),
      ],
    );
    await tester.pumpAndSettle();

    expect(
      find.text('King living at the time of Divided Monarchy'),
      findsOneWidget,
    );
    expect(find.text('a son of Jeroboam.'), findsOneWidget);
    expect(find.text('Father'), findsOneWidget);
    expect(find.text('Zechariah, Zachariah'), findsOneWidget);
    expect(find.text('Named 3 times in the Hebrew Bible'), findsOneWidget);
    // A person has no map.
    expect(find.byType(PlaceMap), findsNothing);

    await tester.tap(find.widgetWithText(ActionChip, 'Jeroboam'));
    // The relative's page waits on its own reply, so it never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests.last.id, 9);
    expect(requests.last.requestId, isNot(requests.first.requestId));
  });

  testWidgets('a place page maps its likeliest location and the others', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 3,
          sendRequest: requests.add,
          basemap: _basemap,
        ),
      ),
    );
    _deliverEntity(
      requests.single,
      _summary(3, 'Ur', kind: 'place'),
      locations: [
        PlaceLocationEntry(
          latitude: 30.96,
          longitude: 46.10,
          confidence: 703,
          kind: 'settlement',
          label: 'Tell el-Muqayyar',
        ),
        PlaceLocationEntry(
          latitude: 37.15,
          longitude: 38.78,
          confidence: 53,
          kind: 'settlement',
          label: 'Urfa',
        ),
      ],
    );
    await tester.pumpAndSettle();

    final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins, hasLength(2));
    expect(map.pins.first.primary, isTrue);
    expect(map.pins.last.primary, isFalse);
    expect(find.text('Tell el-Muqayyar'), findsOneWidget);
    expect(find.text('settlement · 70% confident'), findsOneWidget);
    expect(find.text('Urfa'), findsOneWidget);
  });

  testWidgets('a chapter map lists its places and opens them', (tester) async {
    final requests = <GetChapterPlaces>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterPlacesSheet(
            bookIndex: 30,
            chapter: 1,
            useEnglishBookNames: true,
            sendRequest: requests.add,
            basemap: _basemap,
          ),
        ),
      ),
    );
    // The reader counts books from 0, the signals from 1.
    expect(requests.single.book, 31);
    assignRustSignal['ChapterPlaces']!(
      ChapterPlaces(
        requestId: requests.single.requestId,
        book: 31,
        chapter: 1,
        places: [
          ChapterPlaceEntry(
            place: _summary(
              5,
              'Bethlehem',
              kind: 'place',
              origin: 'Tribe of Judah',
            ),
            location: PlaceLocationEntry(
              latitude: 31.70,
              longitude: 35.21,
              confidence: 1000,
              kind: 'settlement',
              label: 'Bethlehem',
            ),
            verses: const [1, 2, 19],
          ),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tribe of Judah · verses 1, 2, 19'), findsOneWidget);
    final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins.single.label, 'Bethlehem');
    expect(map.pins.single.id, 5);
  });

  testWidgets('tapping a pin reports it', (tester) async {
    MapPin? tapped;
    const pin = MapPin(latitude: 31.7, longitude: 35.2, label: 'Bethlehem');
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: PlaceMap(
            basemap: _basemap,
            pins: const [pin],
            onPinTap: (p) => tapped = p,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A lone pin opens in the middle of the map.
    await tester.tapAt(tester.getCenter(find.byType(PlaceMap)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, pin);
  });

  group('the word sheet', () {
    Future<List<GetWordOccurrences>> pumpSheet(
      WidgetTester tester, {
      WordSenseEntry? sense,
      NameSummaryEntry? name,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final infoRequests = <GetWordInfo>[];
      final occurrenceRequests = <GetWordOccurrences>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 700,
              child: WordInfoSheet(
                word: 'שָׁכַב',
                syriac: false,
                book: 11,
                chapter: 14,
                verse: 29,
                position: 0,
                sendInfoRequest: infoRequests.add,
                sendOccurrencesRequest: occurrenceRequests.add,
                sendVerseTextsRequest: (_) {},
              ),
            ),
          ),
        ),
      );
      assignRustSignal['WordInfo']!(
        WordInfo(
          requestId: infoRequests.single.requestId,
          found: true,
          word: 'שָׁכַב',
          root: 'שכב',
          gloss: 'he lay down',
          partOfSpeech: 'verb',
          vavCon: true,
          lexemes: const [],
          roots: const [],
          sense: sense,
          name: name,
        ).bincodeSerialize(),
        Uint8List(0),
      );
      await tester.pumpAndSettle();
      return occurrenceRequests;
    }

    testWidgets('marks the sense a word has and filters by it', (tester) async {
      final requests = await pumpSheet(
        tester,
        sense: WordSenseEntry(
          gloss: 'to lie down',
          meaning: 'be dead',
          fullGloss: 'to lie down: be dead',
          senses: [
            SenseChoice(
              meaning: 'lay down',
              occurrences: 102,
              isCurrent: false,
            ),
            SenseChoice(meaning: 'be dead', occurrences: 45, isCurrent: true),
          ],
        ),
      );
      expect(find.text('Here “to lie down” means “be dead”'), findsOneWidget);
      final chip = find.widgetWithText(FilterChip, 'be dead · 45');
      expect(tester.widget<FilterChip>(chip).selected, isTrue);

      await tester.tap(find.widgetWithText(FilterChip, 'lay down · 102'));
      // The tab waits on its occurrences, so it never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(requests, isNotEmpty);
      assignRustSignal['WordOccurrences']!(
        WordOccurrences(
          requestId: requests.last.requestId,
          found: true,
          occurrences: const [],
          tokens: [
            for (final (verse, sense) in [
              (29, 'to lie down: be dead'),
              (30, 'to lie down: lay down'),
            ])
              Occurrence(
                book: 11,
                chapter: 14,
                verse: verse,
                position: 0,
                surface: 'שָׁכַב',
                lexeme: '',
                sense: sense,
                parse: OccurrenceParse(
                  partOfSpeech: 'Verb',
                  stem: 'Qal',
                  stemFamily: '',
                  tense: 'Perfect',
                  person: 'Third',
                  gender: 'Masculine',
                  number: 'Singular',
                  state: '',
                ),
              ),
          ],
        ).bincodeSerialize(),
        Uint8List(0),
      );
      await tester.pumpAndSettle();
      // The Occurrences tab, narrowed to the one verse with that sense.
      expect(find.textContaining('1 verse'), findsWidgets);
    });

    testWidgets('names the person a word means', (tester) async {
      await pumpSheet(
        tester,
        name: _summary(
          7,
          'Zechariah',
          description: 'King living at the time of Divided Monarchy',
          occurrences: 3,
        ),
      );
      expect(find.byType(NameCard), findsOneWidget);
      expect(find.text('Zechariah'), findsOneWidget);
      expect(find.textContaining('Named 3 times'), findsOneWidget);
      expect(
        find.textContaining('King living at the time of Divided Monarchy'),
        findsOneWidget,
      );
    });
  });
}
