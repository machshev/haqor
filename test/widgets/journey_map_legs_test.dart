import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/journey_map_legs.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/sea_network.dart';
import 'package:haqor/src/widgets/sequence_map_page.dart';

// Actual core journey 19 coordinates and reference encoding, captured from
// the bundled database. No production dependency on a local core checkout.
final voyage = JourneyEntry(
  id: 19,
  name: 'Voyage to Rome',
  summary: '',
  stops: [
    for (final s in jsonDecode(
      File('test/fixtures/rome_voyage.json').readAsStringSync(),
    ))
      JourneyStopEntry(
        place: NameSummaryEntry(
          id: s['id'],
          name: 'Stop ${s['id']}',
          kind: 'place',
          description: '',
          origin: '',
          occurrences: 0,
        ),
        label: 'Stop ${s['id']}',
        location: PlaceLocationEntry(
          latitude: (s['point'][1] as num).toDouble(),
          longitude: (s['point'][0] as num).toDouble(),
          confidence: 0,
          kind: 'settlement',
          label: '',
          area: const [],
          line: const [],
          estimated: false,
        ),
        book: (s['ref'] as int) >> 16,
        chapter: ((s['ref'] as int) >> 8) & 255,
        verse: (s['ref'] as int) & 255,
        bySea: s['bySea'],
        drawn: true,
        via: [
          for (final p in (s['via'] as String).split(';'))
            if (p.isNotEmpty) ...p.split(',').map(double.parse),
        ],
        note: '',
      ),
  ],
);
ThematicTarget at(int book, int chapter, int verse, {int? lastVerse}) =>
    ThematicTarget(
      book: book,
      chapter: chapter,
      verse: verse,
      lastChapter: chapter,
      lastVerse: lastVerse ?? verse,
    );
void main() {
  final malta = voyage.stops.indexWhere((s) => s.chapter == 28 && s.verse == 1);
  test(
    'Rome voyage routes every ordinary sailing leg and preserves storm drift',
    () {
      final sea = SeaNetwork.parse(
        File(SeaNetwork.asset).readAsStringSync(),
        File('assets/map/basemap.json').readAsStringSync(),
      );
      final legs = journeyMapLegs(voyage.stops);
      var drift = 0, sailing = 0;
      for (final (i, leg) in legs.indexed) {
        if (!leg.bySea) continue;
        if (!leg.estimateSea) {
          drift++;
          expect(identical(leg.atSea(sea), leg), isTrue);
        } else {
          sailing++;
          expect(sea.route(leg.points), isNotNull, reason: 'leg $i');
        }
      }
      expect(drift, 2);
      expect(sailing, greaterThan(5));
      expect(legs.last.bySea, isFalse);
    },
  );
  test(
    'event connections retain intermediate stops, modes, waypoints and highlights',
    () {
      final legs = voyageBetween(
        [voyage],
        voyage.stops.first.place.id,
        voyage.stops[malta].place.id,
        highlighted: true,
        fromPassages: [at(44, 27, 1, lastVerse: 12)],
        toPassages: [at(44, 27, 13, lastVerse: 44)],
      )!;
      expect(legs.length, malta);
      expect(legs.every((l) => l.highlighted), isTrue);
      expect(legs.last.estimateSea, isFalse);
      expect(
        legs[1].points,
        containsAllInOrder([34.9, 35.85, 33.0, 35.75, 31.0, 36.1]),
      );
      expect(
        voyageBetween(
          [voyage],
          voyage.stops.first.place.id,
          voyage.stops.last.place.id,
          fromPassages: [at(1, 12, 1)],
        ),
        isNull,
      );
      expect(
        voyageBetween(
          [voyage],
          voyage.stops.last.place.id,
          voyage.stops.first.place.id,
        ),
        isNull,
      );
    },
  );
  testWidgets('Rome events map expands the voyage and keeps selection', (
    tester,
  ) async {
    final stops = [voyage.stops.first, voyage.stops[malta], voyage.stops.last];
    await tester.pumpWidget(
      MaterialApp(
        home: SequenceMapPage(
          title: 'Rome',
          stops: [
            for (final (i, s) in stops.indexed)
              (
                event: i,
                title: 'Event $i',
                places: [
                  SequencePlaceEntry(
                    place: s.place,
                    label: s.label,
                    location: s.location,
                  ),
                ],
              ),
          ],
          knownBefore: (a, b) => a < b,
          journeys: [voyage],
          basemap: Basemap.parse('{"land":[]}'),
        ),
      ),
    );
    final map = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(map.legs.length, voyage.stops.length - 1);
    expect(map.legs.last.bySea, isFalse);
    expect(find.textContaining('sea courses estimated'), findsOneWidget);
    await tester.tap(find.text('Event 1'));
    await tester.pump();
    final selected = tester.widget<PlaceMap>(find.byType(PlaceMap));
    expect(selected.legs.take(malta).every((l) => l.highlighted), isTrue);
    expect(selected.legs.skip(malta).any((l) => l.highlighted), isFalse);
  });
}
