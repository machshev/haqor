import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/sequence_map_page.dart';

SequencePlaceEntry place(int id, String label, double lon, double lat) =>
    SequencePlaceEntry(
      place: NameSummaryEntry(
        id: id,
        name: label,
        kind: 'place',
        description: '',
        origin: '',
        occurrences: 0,
      ),
      label: label,
      location: PlaceLocationEntry(
        latitude: lat,
        longitude: lon,
        confidence: 0,
        kind: 'settlement',
        label: '',
        area: [],
        line: [],
        estimated: false,
      ),
    );

final jordan = place(1, 'Jordan', 35.55, 31.84);
final wilderness = place(2, 'The wilderness', 35.52, 32.03);
final temple = place(3, 'Pinnacle of the temple', 35.23, 31.78);
final pisgah = place(4, 'Pisgah', 35.72, 31.77);

void main() {
  testWidgets('pins every place of an event and joins them in order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SequenceMapPage(
          title: 'Ministry',
          stops: [
            (event: 1, title: 'Baptism', places: [jordan]),
            (
              event: 2,
              title: 'Temptations',
              places: [wilderness, temple, pisgah],
            ),
            (event: 3, title: "John's witness", places: [jordan]),
          ],
          knownBefore: (a, b) => a < b,
          journeys: const [],
          basemap: Basemap.parse('{"land":[]}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins.map((p) => p.label), [
      'Jordan (1, 3)',
      'The wilderness (2)',
      'Pinnacle of the temple (2)',
      'Pisgah (2)',
    ]);
    // Jordan → wilderness, the event's own route, and Pisgah → Jordan.
    final points = [for (final l in map.legs) l.points];
    expect(
      points,
      unorderedEquals([
        [35.55, 31.84, 35.52, 32.03],
        [35.52, 32.03, 35.23, 31.78],
        [35.23, 31.78, 35.72, 31.77],
        [35.72, 31.77, 35.55, 31.84],
      ]),
    );

    // Picking the event picks out all its places, its route and the way to it.
    await tester.tap(find.byKey(const ValueKey('sequence-map-stop-2')));
    await tester.pumpAndSettle();
    map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.pins.where((p) => p.highlighted).map((p) => p.label), [
      'The wilderness (2)',
      'Pinnacle of the temple (2)',
      'Pisgah (2)',
    ]);
    expect(map.legs.where((l) => l.highlighted), hasLength(3));
    expect(map.focus, [
      35.55, 31.84, 35.52, 32.03, //
      35.52, 32.03, 35.23, 31.78, 35.72, 31.77,
    ]);
  });
}
