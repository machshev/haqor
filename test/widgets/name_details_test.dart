import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/study_workspace.dart';
import 'package:haqor/src/widgets/bible_timeline_page.dart';
import 'package:haqor/src/widgets/name_details.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/place_photos.dart';
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
  List<PlaceImageEntry> images = const [],
  List<ArtifactEntry> artifacts = const [],
  List<ArtifactSourceEntry> artifactSources = const [],
  List<NameVerse> verses = const [],
  List<BibleEventEntry> events = const [],
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
      images: images,
      verses: verses,
      events: events,
      artifacts: artifacts,
      artifactSources: artifactSources,
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  testWidgets('a person page shows who they are and opens their relatives', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    final verseRequests = <GetVerseTexts>[];
    final navigated = <(int, int, int)>[];
    final bookmarked = <int, StudyName>{};
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 7,
          title: 'Zechariah',
          sendRequest: requests.add,
          sendVerseTextsRequest: verseRequests.add,
          onNavigateToPassage: (book, chapter, verse) =>
              navigated.add((book, chapter, verse)),
          basemap: _basemap,
          bookmarks: NameBookmarks(
            isBookmarked: bookmarked.containsKey,
            toggle: (name) async {
              if (bookmarked.remove(name.id) != null) return false;
              bookmarked[name.id] = name;
              return true;
            },
          ),
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
        NameVerse(book: 11, chapter: 14, verse: 29, positions: [8]),
        NameVerse(book: 11, chapter: 15, verse: 8, positions: [3, 9]),
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
    // A person has no map, and no timeline without events.
    expect(find.byType(PlaceMap), findsNothing);
    expect(find.textContaining('Timeline'), findsNothing);
    // The page bookmarks its person in the study, and unbookmarks them.
    await tester.tap(find.byTooltip('Bookmark in the study'));
    await tester.pump();
    expect(bookmarked[7]?.name, 'Zechariah');
    expect(
      bookmarked[7]?.description,
      'King living at the time of Divided Monarchy',
    );
    await tester.tap(find.byTooltip('Remove from the study'));
    await tester.pump();
    expect(bookmarked, isEmpty);
    expect(find.byTooltip('Bookmark in the study'), findsOneWidget);
    // A form of the name links to its word sheet.
    expect(find.byTooltip('Open the word'), findsOneWidget);

    // The verses have a tab of their own.
    expect(find.byType(OccurrenceVerseRow), findsNothing);
    await tester.tap(find.text('Verses (2)'));
    await tester.pumpAndSettle();
    expect(
      find.text('Named 3 times in the Hebrew Bible · 2 verses'),
      findsOneWidget,
    );
    // The verses are listed as the Occurrences tab lists them, the name
    // marked where it stands, and their text asked for in one round-trip.
    final rows = tester
        .widgetList<OccurrenceVerseRow>(find.byType(OccurrenceVerseRow))
        .toList();
    expect(
      [for (final r in rows) r.positions],
      [
        [8],
        [3, 9],
      ],
    );
    expect(verseRequests, hasLength(1));
    // The book filter is the Occurrences tab's, counting each naming word.
    final books = tester.widget<CanonDistribution>(
      find.byType(CanonDistribution),
    );
    expect(books.countsByBook, {11: 3});
    await tester.ensureVisible(find.byType(OccurrenceVerseRow).last);
    await tester.tap(find.byType(OccurrenceVerseRow).last);
    expect(navigated, [(10, 15, 8)]);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Jeroboam'));
    // The relative's page waits on its own reply, so it never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests.last.id, 9);
    expect(requests.last.requestId, isNot(requests.first.requestId));
  });

  testWidgets('the New Testament names by verse, counted apart', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 3,
          title: 'Jerusalem',
          ntSyriac: true,
          sendRequest: requests.add,
          sendVerseTextsRequest: (_) {},
        ),
      ),
    );
    _deliverEntity(
      requests.single,
      _summary(3, 'Jerusalem', kind: 'place', occurrences: 2),
      verses: [
        NameVerse(book: 6, chapter: 10, verse: 1, positions: [4, 12]),
        NameVerse(book: 40, chapter: 2, verse: 1, positions: const []),
        NameVerse(book: 40, chapter: 2, verse: 3, positions: const []),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verses (3)'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Named 2 times in the Hebrew Bible · in 2 New Testament verses',
      ),
      findsOneWidget,
    );
    // Each New Testament verse counts once, and is shown as the reader
    // shows the New Testament.
    final books = tester.widget<CanonDistribution>(
      find.byType(CanonDistribution),
    );
    expect(books.countsByBook, {6: 2, 40: 2});
    final rows = tester
        .widgetList<OccurrenceVerseRow>(find.byType(OccurrenceVerseRow))
        .toList();
    expect([for (final r in rows) r.syriac], [false, true, true]);
  });

  testWidgets('set to the Greek, its NT verses are, and the switch flips them', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    final switched = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 3,
          title: 'Jerusalem',
          ntGreek: true,
          onNtGreekChanged: switched.add,
          sendRequest: requests.add,
          sendVerseTextsRequest: (_) {},
        ),
      ),
    );
    _deliverEntity(
      requests.single,
      _summary(3, 'Jerusalem', kind: 'place', occurrences: 2),
      verses: [
        NameVerse(book: 6, chapter: 10, verse: 1, positions: [4, 12]),
        NameVerse(book: 40, chapter: 2, verse: 1, positions: const []),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verses (2)'));
    await tester.pumpAndSettle();
    List<bool> greek() => [
      for (final r in tester.widgetList<OccurrenceVerseRow>(
        find.byType(OccurrenceVerseRow),
      ))
        r.greek,
    ];
    expect(greek(), [false, true]);

    await tester.tap(find.byKey(const ValueKey('nt-text-toggle')));
    await tester.pump();
    expect(switched, [false]);
    expect(greek(), [false, false]);
  });

  testWidgets('one named only in the New Testament says so', (tester) async {
    final requests = <GetNameEntity>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 4,
          title: 'Peter',
          sendRequest: requests.add,
          sendVerseTextsRequest: (_) {},
        ),
      ),
    );
    _deliverEntity(
      requests.single,
      _summary(4, 'Peter', occurrences: 0),
      verses: [NameVerse(book: 40, chapter: 4, verse: 18, positions: const [])],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verses (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Named in 1 New Testament verse'), findsOneWidget);
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
          area: const [],
          line: const [],
          estimated: false,
        ),
        PlaceLocationEntry(
          latitude: 37.15,
          longitude: 38.78,
          confidence: 53,
          kind: 'settlement',
          label: 'Urfa',
          area: const [],
          line: const [],
          estimated: false,
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

    // Each location opens in Google Maps or Google Earth.
    await tester.tap(
      find.byTooltip('Open in Google Maps or Google Earth').first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Google Maps'), findsOneWidget);
    expect(find.text('Google Earth'), findsOneWidget);
  });

  testWidgets('a place page shows photos of its sites and their Google views', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 4,
          sendRequest: requests.add,
          basemap: _basemap,
        ),
      ),
    );
    PlaceLocationEntry site(String label) => PlaceLocationEntry(
      latitude: 31.56,
      longitude: 34.85,
      confidence: 900,
      kind: 'settlement',
      label: label,
      area: const [],
      line: const [],
      estimated: false,
    );
    PlaceImageEntry image(
      int location,
      String description, {
      bool view = false,
    }) => PlaceImageEntry(
      location: location,
      view: view,
      description: description,
      pageUrl: view
          ? 'https://www.google.com/maps/@31.56,34.85,3a'
          : 'https://commons.wikimedia.org/wiki/File:Lachish.jpg',
      thumbnailUrl: view
          ? ''
          : 'https://upload.wikimedia.org/500px-Lachish.jpg',
      largeUrl: view ? '' : 'https://upload.wikimedia.org/1280px-Lachish.jpg',
      width: view ? 0 : 4000,
      height: view ? 0 : 3000,
      credit: view ? '' : 'Avi1111',
      license: view ? '' : 'CC-BY-SA-4.0',
      placeholder: const ['#80a0bc', '#4c5959'],
    );
    _deliverEntity(
      requests.single,
      _summary(4, 'Lachish', kind: 'place'),
      locations: [site('Tel Lachish'), site('Umm Lakis')],
      images: [
        image(0, 'ruins at Tel Lachish'),
        image(0, 'Google Streetview of Tel Lachish', view: true),
        image(1, 'ruins at Umm Lakis'),
      ],
    );
    await tester.pumpAndSettle();

    // Photos only in the strip: the view is a link.
    expect(find.byType(PlacePhotoStrip), findsOneWidget);
    expect(find.text('ruins at Tel Lachish'), findsOneWidget);
    expect(find.text('ruins at Umm Lakis'), findsOneWidget);
    expect(find.text('Google Streetview of Tel Lachish'), findsNothing);

    // A photo opens large with its credit and licence.
    await tester.tap(find.text('ruins at Tel Lachish'));
    await tester.pumpAndSettle();
    expect(
      find.text('Photo: Avi1111 · CC BY-SA 4.0, via Wikimedia Commons'),
      findsOneWidget,
    );
    expect(find.text('Wikimedia Commons'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // The likeliest site has a Street View; the other does not.
    final menus = find.byTooltip('Open in Google Maps or Google Earth');
    await tester.ensureVisible(menus.first);
    await tester.pumpAndSettle();
    await tester.tap(menus.first);
    await tester.pumpAndSettle();
    expect(find.text('Street View'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.ensureVisible(menus.last);
    await tester.pumpAndSettle();
    await tester.tap(menus.last);
    await tester.pumpAndSettle();
    expect(find.text('Google Earth'), findsOneWidget);
    expect(find.text('Street View'), findsNothing);
  });

  test('licence codes read as people write them', () {
    expect(licenseLabel('CC-BY-SA-4.0'), 'CC BY-SA 4.0');
    expect(licenseLabel('CC-BY-2.5'), 'CC BY 2.5');
    expect(licenseLabel('CC-BY-SA-3.0-IGO'), 'CC BY-SA 3.0-IGO');
    expect(licenseLabel('CC-Zero'), 'CC0');
    expect(licenseLabel('PD'), 'public domain');
    expect(licenseLabel('GFDL'), 'GFDL');
  });

  testWidgets('a person is attested by the finds naming them', (tester) async {
    final requests = <GetNameEntity>[];
    final opened = <(int, int, int)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 5,
          sendRequest: requests.add,
          useEnglishBookNames: true,
          onNavigateToPassage: (b, c, v) => opened.add((b, c, v)),
        ),
      ),
    );
    final hezekiah = _summary(5, 'Hezekiah');
    ArtifactEntry artifact(int id, String name, String how, String strength) =>
        ArtifactEntry(
          id: id,
          key: 'find-$id',
          name: name,
          otherNames: const [],
          kind: 'bulla',
          date: 'c. 710 BC',
          year: -710,
          script: 'Hebrew',
          foundSite: 'Ophel, Jerusalem',
          foundYear: 2009,
          foundPlace: _summary(0, ''),
          museum: '',
          wikipedia: '',
          wikidata: '',
          summary: 'A royal seal impression.',
          attestations: [
            ArtifactAttestationEntry(
              person: _summary(9, 'Ahaz'),
              strength: 'strong',
              how: 'Named as his father.',
              source: 's',
            ),
            ArtifactAttestationEntry(
              person: hezekiah,
              strength: strength,
              how: how,
              source: 's',
            ),
          ],
          passages: [
            ArtifactPassageEntry(
              passage: PassageSpan(
                book: 11,
                chapter: 18,
                verse: 13,
                lastChapter: 18,
                lastVerse: 16,
              ),
              strength: 'strong',
              how: 'His tribute.',
              source: 's',
            ),
          ],
        );
    _deliverEntity(
      requests.single,
      hezekiah,
      artifacts: [
        artifact(1, 'Royal bulla of Hezekiah', 'His own seal.', 'strong'),
        artifact(2, 'A lesser find', 'Perhaps him.', 'possible'),
      ],
      artifactSources: [
        ArtifactSourceEntry(id: 's', citation: 'Mykytiuk 2014', url: ''),
      ],
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Attested by'), 200);
    expect(find.text('Royal bulla of Hezekiah'), findsOneWidget);
    // The row gives how it names him, not his father.
    expect(find.text('c. 710 BC · His own seal.'), findsOneWidget);
    expect(find.text('c. 710 BC · Perhaps him.'), findsOneWidget);
    expect(find.text('Possible'), findsOneWidget);

    await tester.tap(find.text('Royal bulla of Hezekiah'));
    await tester.pumpAndSettle();
    expect(find.text('A royal seal impression.'), findsOneWidget);
    expect(find.text('His own seal.\nSource: Mykytiuk 2014'), findsOneWidget);

    // A passage closes the find and the name page, and opens the reader.
    await tester.tap(find.text('2 Kings 18:13–16'));
    await tester.pumpAndSettle();
    expect(opened, [(10, 18, 13)]);
    expect(find.text('A royal seal impression.'), findsNothing);
  });

  testWidgets('a place lists the finds found there or naming it', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    await tester.pumpWidget(
      MaterialApp(home: NameDetailsPage(id: 6, sendRequest: requests.add)),
    );
    _deliverEntity(
      requests.single,
      _summary(6, 'Dibon', kind: 'place'),
      artifacts: [
        ArtifactEntry(
          id: 1,
          key: 'mesha-stele',
          name: 'Mesha Stele',
          otherNames: const [],
          kind: 'stele',
          date: 'c. 840 BC',
          year: -840,
          script: 'Moabite',
          foundSite: 'Dhiban',
          foundYear: 1868,
          foundPlace: _summary(6, 'Dibon', kind: 'place'),
          museum: 'Louvre, Paris',
          wikipedia: '',
          wikidata: '',
          summary: 'Mesha of Moab.',
          attestations: [
            ArtifactAttestationEntry(
              person: _summary(6, 'Dibon', kind: 'place'),
              strength: 'strong',
              how: "Named as Mesha's city.",
              source: 's',
            ),
          ],
          passages: const [],
        ),
      ],
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Attested by'), 200);
    expect(find.text("c. 840 BC · Named as Mesha's city."), findsOneWidget);
  });

  testWidgets('a timeline tab draws and lists the events they are in', (
    tester,
  ) async {
    final requests = <GetNameEntity>[];
    final timelineRequests = <GetBibleEvents>[];
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: NameDetailsPage(
          id: 5,
          useEnglishBookNames: true,
          sendRequest: requests.add,
          sendTimelineRequest: timelineRequests.add,
        ),
      ),
    );
    BibleEventEntry event(int id, String title, int year, {int years = 0}) =>
        BibleEventEntry(
          id: id,
          title: title,
          year: year,
          duration: years,
          unit: years > 0 ? 'years' : '',
          passages: [
            ThematicTarget(
              book: 2,
              chapter: 2,
              verse: 2,
              lastChapter: 2,
              lastVerse: 10,
            ),
          ],
          people: const [],
          places: const [],
          note: '',
        );
    _deliverEntity(
      requests.single,
      _summary(5, 'Moses'),
      events: [
        event(121, 'Birth of Moses', -1571),
        event(122, 'Lifetime of Moses', -1571, years: 120),
        event(126, 'Exodus from Egypt', -1491),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Verses (2)'), findsNothing);
    await tester.tap(find.text('Timeline (3)'));
    await tester.pumpAndSettle();

    expect(find.text('3 events · 1571 BC – 1451 BC'), findsOneWidget);
    expect(find.byKey(const ValueKey('name-timeline-chart')), findsOneWidget);
    final exodus = find.byKey(const ValueKey('name-event-126'));
    expect(
      find.descendant(
        of: exodus,
        matching: find.text('1491 BC · Exodus 2:2–10'),
      ),
      findsOneWidget,
    );

    // An event opens on the Bible timeline, its details shown.
    await tester.tap(exodus);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final timeline = tester.widget<BibleTimelinePage>(
      find.byType(BibleTimelinePage),
    );
    expect(timeline.initialEventId, '126');
    assignRustSignal['BibleEvents']!(
      BibleEvents(
        requestId: timelineRequests.single.requestId,
        events: [
          event(1, 'Creation of all things', -4004),
          event(126, 'Exodus from Egypt', -1491),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Exodus from Egypt'),
      ),
      findsOneWidget,
    );
  });

  test('the Google links land on the position', () {
    expect(
      googleMapsUri(31.253928, 35.534184).toString(),
      'https://www.google.com/maps/search/?api=1&query=31.253928%2C35.534184',
    );
    expect(
      googleEarthUri(31.253928, 35.534184).toString(),
      'https://earth.google.com/web/@31.253928,35.534184,0a,5000d,35y,0h,45t,0r',
    );
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
              area: const [],
              line: const [],
              estimated: false,
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

  testWidgets("a chapter's people say who each is to the others", (
    tester,
  ) async {
    final requests = <GetChapterPeople>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterPeopleSheet(
            bookIndex: 30,
            chapter: 4,
            useEnglishBookNames: true,
            sendRequest: requests.add,
          ),
        ),
      ),
    );
    expect(requests.single.book, 31);
    assignRustSignal['ChapterPeople']!(
      ChapterPeople(
        requestId: requests.single.requestId,
        book: 31,
        chapter: 4,
        people: [
          ChapterPersonEntry(
            person: _summary(1, 'Boaz', description: 'Husband of Ruth'),
            verses: const [1, 13],
            relations: [
              ChapterRelationEntry(relation: 'partner', flag: '', otherId: 2),
              ChapterRelationEntry(relation: 'child', flag: '', otherId: 3),
            ],
          ),
          ChapterPersonEntry(
            person: _summary(2, 'Ruth', origin: 'Moab'),
            verses: const [13],
            relations: [
              ChapterRelationEntry(relation: 'partner', flag: '', otherId: 1),
            ],
          ),
          ChapterPersonEntry(
            person: _summary(3, 'Obed'),
            verses: const [17, 21, 22],
            relations: [
              ChapterRelationEntry(relation: 'father', flag: '', otherId: 1),
              ChapterRelationEntry(relation: 'mother', flag: '', otherId: 2),
            ],
          ),
        ],
      ).bincodeSerialize(),
      Uint8List(0),
    );
    await tester.pumpAndSettle();

    expect(find.text('People in Ruth 4'), findsOneWidget);
    expect(
      find.text(
        'Husband of Ruth\nMarried to: Ruth · Children: Obed\nverses 1, 13',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Father: Boaz · Mother: Ruth\nverses 17, 21, 22'),
      findsOneWidget,
    );
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
          greekEquivalents: const [],
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
