import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart' hide listEquals;
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
  _stepAndColourTests();
}

void _stepAndColourTests() {
  Future<void> pump(WidgetTester tester, {Map<int, List<String>>? tracks}) =>
      tester.pumpWidget(
        MaterialApp(
          home: SequenceMapPage(
            title: 'Ministry',
            stops: [
              (event: 1, title: 'Baptism', places: [jordan]),
              (event: 2, title: 'Unplaced', places: const []),
              (event: 3, title: 'Wilderness', places: [wilderness]),
              (event: 4, title: 'Temple', places: [temple]),
            ],
            tracks: tracks ?? const {},
            knownBefore: (a, b) => a < b,
            journeys: const [],
            basemap: Basemap.parse('{"land":[]}'),
          ),
        ),
      );
  ValueKey<String> key(String k) => ValueKey(k);
  bool enabled(WidgetTester tester, String k) =>
      tester.widget<IconButton>(find.byKey(key(k))).onPressed != null;
  int? picked(WidgetTester tester) {
    for (final e in [1, 2, 3, 4]) {
      final tile = find.byKey(key('sequence-map-stop-$e'));
      if (tile.evaluate().isNotEmpty &&
          tester.widget<ListTile>(tile).selected) {
        return e;
      }
    }
    return null;
  }

  testWidgets('back and next step through the placed events', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();
    expect(enabled(tester, 'sequence-map-next'), isTrue);
    await tester.tap(find.byKey(key('sequence-map-next')));
    await tester.pumpAndSettle();
    expect(picked(tester), 1);
    expect(enabled(tester, 'sequence-map-back'), isFalse);
    // The unplaced event is passed over.
    await tester.tap(find.byKey(key('sequence-map-next')));
    await tester.pumpAndSettle();
    expect(picked(tester), 3);
    var map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.fitFocus, isTrue);
    expect(map.focus, [35.55, 31.84, 35.52, 32.03]);
    await tester.tap(find.byKey(key('sequence-map-next')));
    await tester.pumpAndSettle();
    expect(picked(tester), 4);
    expect(enabled(tester, 'sequence-map-next'), isFalse);
    await tester.tap(find.byKey(key('sequence-map-back')));
    await tester.pumpAndSettle();
    expect(picked(tester), 3);
    map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.legs.where((l) => l.highlighted), hasLength(1));
  });

  testWidgets('each person\'s track is drawn in a colour of its own', (
    tester,
  ) async {
    await pump(
      tester,
      tracks: const {
        1: ['Jesus', 'John'],
        2: ['John'],
        3: ['Jesus'],
        4: ['Jesus', 'John'],
      },
    );
    await tester.pumpAndSettle();
    final legs = tester.widget<PlaceMap>(find.byType(PlaceMap)).legs;
    expect(legs.every((l) => l.color != null), isTrue);
    // Jesus: Jordan → wilderness → temple; John: Jordan → temple.
    Color? colourTo(List<double> to) => legs
        .firstWhere(
          (l) =>
              listEquals(l.points.sublist(l.points.length - 2), to) &&
              listEquals(l.points.sublist(0, 2), [35.55, 31.84]),
        )
        .color;
    final jesus = colourTo([35.52, 32.03]);
    final john = colourTo([35.23, 31.78]);
    expect(jesus, isNot(john));
    final chip = tester.widget<ChoiceChip>(find.byKey(key('map-track-John')));
    expect((chip.avatar! as CircleAvatar).backgroundColor, john);
  });
}
