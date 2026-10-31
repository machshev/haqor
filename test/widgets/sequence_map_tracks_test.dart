import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/sequence_map_page.dart';

SequenceMapStop stop(int id, {bool located = true}) => (
  event: id,
  title: 'Event $id',
  places: [
    if (located)
      SequencePlaceEntry(
        place: NameSummaryEntry(
          id: id,
          name: 'Place $id',
          kind: 'place',
          description: '',
          origin: '',
          occurrences: 0,
        ),
        label: 'Place $id',
        location: PlaceLocationEntry(
          latitude: 30 + id.toDouble(),
          longitude: 35,
          confidence: 0,
          kind: 'settlement',
          label: '',
          area: [],
          line: [],
          estimated: false,
        ),
      ),
  ],
);

void main() {
  test('track membership survives the generated signal codec', () {
    const entry = SequenceEventDetailsEntry(
      event: 3,
      kinds: [],
      region: '',
      places: [],
      tracks: ['Jesus', 'John the Baptist'],
    );
    expect(
      SequenceEventDetailsEntry.bincodeDeserialize(entry.bincodeSerialize()),
      entry,
    );
  });

  testWidgets(
    'companions share a route and an absent initial track falls back to all',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SequenceMapPage(
            title: 'Companions',
            stops: [stop(1), stop(2)],
            tracks: const {
              1: ['Paul', 'Barnabas'],
              2: ['Paul', 'Barnabas'],
            },
            initialTrack: 'John',
            knownBefore: (a, b) => a < b,
            journeys: const [],
            basemap: Basemap.parse('{"land":[]}'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
      expect(map.pins, hasLength(2));
      expect(map.legs, hasLength(1));
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('map-track-all')))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('parallel tracks share meetings but never join different people', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SequenceMapPage(
          title: 'Parallel journeys',
          stops: [for (var i = 1; i <= 8; i++) stop(i, located: i != 7)],
          tracks: const {
            1: ['Jesus'],
            2: ['John'],
            3: ['Jesus', 'John'],
            4: ['John'],
            5: ['Jesus'],
            7: ['John'],
            8: ['John'],
          },
          knownBefore: (a, b) => a < b && b != 8,
          journeys: const [],
          basemap: Basemap.parse('{"land":[]}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    PlaceMap map() => tester.widget<PlaceMap>(find.byType(PlaceMap));
    List<(int, int)> edges() => [
      for (final l in map().legs)
        (l.points[1].toInt() - 30, l.points.last.toInt() - 30),
    ];
    expect(edges(), [(1, 3), (3, 5), (2, 3), (3, 4)]);
    // The unassigned event and the unordered John event stay pinned, without routes.
    expect(map().pins, hasLength(7));
    await tester.tap(find.byKey(const ValueKey('map-track-Jesus')));
    await tester.pumpAndSettle();
    expect(edges(), [(1, 3), (3, 5)]);
    expect(map().pins, hasLength(3));
    expect(find.byKey(const ValueKey('sequence-map-stop-4')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('map-track-John')));
    await tester.pumpAndSettle();
    expect(edges(), [(2, 3), (3, 4)]);
    await tester.tap(find.byKey(const ValueKey('sequence-map-stop-4')));
    await tester.pumpAndSettle();
    expect(map().legs.where((l) => l.highlighted).single.points, [
      35,
      33,
      35,
      34,
    ]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sequence-map-stop-7')),
      80,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.textContaining('No place told'), findsOneWidget);
  });
}
