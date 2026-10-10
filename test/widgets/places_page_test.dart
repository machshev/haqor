import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/places_page.dart';

/// A square of land round the Levant.
final _basemap = Basemap.parse('{"land":[[30,28,40,28,40,36,30,36]]}');

PlaceListEntry _place(
  int id,
  String name, {
  String kind = 'settlement',
  List<String> otherNames = const [],
  List<int> regions = const [],
  int occurrences = 1,
  List<List<double>> area = const [],
}) => PlaceListEntry(
  place: NameSummaryEntry(
    id: id,
    name: name,
    kind: 'place',
    description: '',
    origin: '',
    occurrences: occurrences,
  ),
  location: PlaceLocationEntry(
    latitude: 31.7,
    longitude: 35.2,
    confidence: 1000,
    kind: kind,
    label: '',
    area: area,
    line: const [],
  ),
  otherNames: otherNames,
  regions: regions,
);

JourneyStopEntry _stop(
  PlaceListEntry place, {
  required int book,
  required int chapter,
  required int verse,
  String? label,
  bool bySea = false,
  bool drawn = true,
  List<double> via = const [],
  String note = '',
}) => JourneyStopEntry(
  place: place.place,
  label: label ?? place.place.name,
  location: place.location,
  book: book,
  chapter: chapter,
  verse: verse,
  bySea: bySea,
  drawn: drawn,
  via: via,
  note: note,
);

/// Where the reader was sent: book (from 0), chapter and verse.
final _readAt = <(int, int, int)>[];

Future<void> _pumpPlaces(WidgetTester tester) async {
  final requests = <GetPlaces>[];
  final journeyRequests = <GetJourneys>[];
  _readAt.clear();
  tester.view.physicalSize = const Size(600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PlacesPage(
        useEnglishBookNames: true,
        sendRequest: requests.add,
        sendJourneysRequest: journeyRequests.add,
        basemap: _basemap,
        onNavigateToPassage: (book, chapter, verse) =>
            _readAt.add((book, chapter, verse)),
      ),
    ),
  );
  final nazareth = _place(4, 'Nazareth', occurrences: 0);
  final bethlehem = _place(1, 'Bethlehem');
  final egypt = _place(5, 'Egypt', kind: 'region');
  assignRustSignal['Journeys']!(
    Journeys(
      requestId: journeyRequests.single.requestId,
      journeys: [
        JourneyEntry(
          id: 1,
          name: 'The flight into Egypt',
          summary: 'Joseph takes the child to Egypt.',
          stops: [
            _stop(bethlehem, book: 40, chapter: 2, verse: 1),
            _stop(
              egypt,
              book: 40,
              chapter: 2,
              verse: 14,
              drawn: false,
              note: 'Until Herod is dead.',
            ),
            _stop(
              nazareth,
              book: 40,
              chapter: 2,
              verse: 23,
              label: 'Nazareth of Galilee',
              bySea: true,
              via: const [34, 31],
            ),
          ],
        ),
      ],
    ).bincodeSerialize(),
    Uint8List(0),
  );
  assignRustSignal['Places']!(
    Places(
      requestId: requests.single.requestId,
      places: [
        _place(
          1,
          'Bethlehem',
          otherNames: const ['Beth-lehem', 'בֵּית לֶ֫חֶם'],
          regions: const [10],
          occurrences: 41,
        ),
        _place(
          2,
          'Capernaum',
          regions: const [11],
          occurrences: 0,
          area: const [
            [35.5, 32.8, 35.6, 32.8, 35.6, 32.9],
          ],
        ),
        _place(
          10,
          'Judea',
          kind: 'region',
          area: const [
            [35, 31, 35.5, 31, 35.5, 32, 35, 32],
          ],
        ),
        _place(11, 'Galilee', kind: 'region'),
        _place(3, 'Jordan', kind: 'river', regions: const [10, 11]),
      ],
      regions: [
        PlaceRegionEntry(id: 10, name: 'Judea', group: 'Land of Israel'),
        PlaceRegionEntry(id: 11, name: 'Galilee', group: 'Land of Israel'),
      ],
    ).bincodeSerialize(),
    Uint8List(0),
  );
  await tester.pumpAndSettle();
}

List<String> _listed(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    (tile.title as Text).data!,
];

void main() {
  test('a search ignores points, hyphens and case', () {
    expect(placeSearchKey('Beth-lehem'), placeSearchKey('bethlehem'));
    expect(placeSearchKey('בֵּית לֶ֫חֶם'), 'ביתלחם');
  });

  testWidgets('places are found by name in English or Hebrew', (tester) async {
    await _pumpPlaces(tester);
    expect(_listed(tester), [
      'Bethlehem',
      'Capernaum',
      'Judea',
      'Galilee',
      'Jordan',
    ]);
    // Regions are not drawn as ground until asked for.
    final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins.map((p) => p.label), ['Bethlehem', 'Capernaum', 'Jordan']);
    // Nor any place's ground among all kinds.
    expect(map.pins.every((p) => p.area.isEmpty), isTrue);

    await tester.enterText(find.byKey(const ValueKey('places-search')), 'לחם');
    await tester.pumpAndSettle();
    expect(_listed(tester), ['Bethlehem']);
    expect(find.textContaining('Judea'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('places-search')),
      'beth lehem',
    );
    await tester.pumpAndSettle();
    expect(_listed(tester), ['Bethlehem']);
  });

  testWidgets('a region narrows the list and is drawn on the map', (
    tester,
  ) async {
    await _pumpPlaces(tester);
    await tester.tap(find.byKey(const ValueKey('places-region')));
    await tester.pumpAndSettle();
    expect(find.text('Land of Israel'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Galilee'));
    await tester.pumpAndSettle();
    expect(_listed(tester), ['Capernaum', 'Jordan']);
    final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins.map((p) => p.label), ['Galilee', 'Capernaum', 'Jordan']);

    await tester.ensureVisible(find.text('Water'));
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(_listed(tester), ['Jordan']);
  });

  testWidgets('the most named come first when asked', (tester) async {
    await _pumpPlaces(tester);
    await tester.ensureVisible(find.text('Settlements'));
    await tester.tap(find.text('Settlements'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('places-order')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<PlaceOrder>, 'Most named first'),
    );
    await tester.pumpAndSettle();
    expect(_listed(tester), ['Bethlehem', 'Capernaum']);
    // A chosen kind's ground is drawn.
    final settlements = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(settlements.pins.last.area, isNotEmpty);
    expect(find.textContaining('Named 41 times'), findsOneWidget);
  });

  _journeyTests();
}

void _journeyTests() {
  testWidgets('a journey lists its stops and draws its legs', (tester) async {
    await _pumpPlaces(tester);
    // A place on a journey says so.
    expect(find.textContaining('On The flight into Egypt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('places-journey')));
    await tester.pumpAndSettle();
    expect(find.text('New Testament'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'The flight into Egypt'),
    );
    await tester.pumpAndSettle();

    expect(_listed(tester), ['Bethlehem', 'Egypt', 'Nazareth of Galilee']);
    expect(find.text('Joseph takes the child to Egypt.'), findsOneWidget);
    expect(find.textContaining('not on the map'), findsOneWidget);
    expect(find.textContaining('Until Herod is dead.'), findsOneWidget);
    // The stop with no site is passed over: one leg, by sea, by its point.
    final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins.map((p) => p.label), ['Bethlehem', 'Nazareth of Galilee']);
    expect(map.legs, hasLength(1));
    expect(map.legs.single.bySea, isTrue);
    expect(map.legs.single.points, [35.2, 31.7, 34, 31, 35.2, 31.7]);

    // Matthew is book 40, the reader's 39.
    await tester.tap(find.byTooltip('Read Matthew 2:23'));
    await tester.pumpAndSettle();
    expect(_readAt, [(39, 2, 23)]);
  });

  testWidgets('leaving a journey brings back the places', (tester) async {
    await _pumpPlaces(tester);
    await tester.tap(find.byKey(const ValueKey('places-journey')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<int>, 'The flight into Egypt'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('No journey'));
    await tester.pumpAndSettle();
    expect(_listed(tester), hasLength(5));
    expect(tester.widget<PlaceMap>(find.byType(PlaceMap)).legs, isEmpty);
  });
}
