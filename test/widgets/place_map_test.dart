import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/place_map.dart';

final _basemap = Basemap.parse(
  '{"land":[[30,28,40,28,40,36,30,36]],"lakes":[],"rivers":[],'
  '"wadis":[[35.3,31.8,35.4,31.7]]}',
);

/// A square of land about [longitude], [latitude], [half] degrees each way.
List<double> _square(double longitude, double latitude, double half) => [
  longitude - half,
  latitude - half,
  longitude + half,
  latitude - half,
  longitude + half,
  latitude + half,
  longitude - half,
  latitude + half,
];

Future<MapPin?> _tapMap(
  WidgetTester tester,
  List<MapPin> pins,
  Offset at,
) async {
  MapPin? tapped;
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 400,
          height: 400,
          child: PlaceMap(
            basemap: _basemap,
            pins: pins,
            onPinTap: (pin) => tapped = pin,
          ),
        ),
      ),
    ),
  );
  final map = tester.getTopLeft(find.byType(PlaceMap));
  await tester.tapAt(map + at);
  // Past the double-tap timeout, which holds a single tap back.
  await tester.pump(const Duration(milliseconds: 500));
  return tapped;
}

void main() {
  test('the basemap reads its wadis', () {
    expect(_basemap.wadis.single, [35.3, 31.8, 35.4, 31.7]);
  });

  test('relief layers say where they are and when they are drawn', () {
    final [overview, detail] = Relief.parse(
      '{"layers":['
      '{"file":"a.png","bounds":[-12,4,64,48],"lowest":-450,"highest":5200,'
      '"fade":2,"minScale":0},'
      '{"file":"b.png","bounds":[35,31.5,35.5,32],"lowest":-450,'
      '"highest":2850,"fade":0.04,"minScale":400}]}',
    );
    expect(overview.file, 'a.png');
    expect(detail.minScale, 400);
    // Jerusalem's surroundings, within the detailed layer and clear of its
    // faded edges.
    const jerusalem = Rect.fromLTRB(35.15, 31.7, 35.3, 31.85);
    expect(detail.overlaps(jerusalem), isTrue);
    expect(detail.covers(jerusalem), isTrue);
    // Galilee is outside it.
    const galilee = Rect.fromLTRB(35.4, 32.7, 35.7, 32.9);
    expect(detail.overlaps(galilee), isFalse);
    // A view running into its faded edge is not covered.
    expect(
      detail.covers(const Rect.fromLTRB(34.9, 31.7, 35.3, 31.85)),
      isFalse,
    );
  });

  test('regions are ground, settlements and rivers are pins', () {
    const egypt = MapPin(
      latitude: 30,
      longitude: 31,
      label: 'Egypt',
      kind: 'region',
    );
    const bethel = MapPin(
      latitude: 31.93,
      longitude: 35.22,
      label: 'Bethel',
      kind: 'settlement',
    );
    const jordan = MapPin(
      latitude: 32,
      longitude: 35.55,
      label: 'Jordan',
      kind: 'river',
    );
    expect(egypt.isArea, isTrue);
    expect(bethel.isArea, isFalse);
    expect(jordan.isArea, isFalse);
  });

  testWidgets('a tap inside a region opens it', (tester) async {
    // A lone region: the map fits its ground, so the map's middle is inside
    // it, and a tap below its name, away from any pin, still finds it.
    final edom = MapPin(
      latitude: 30.5,
      longitude: 35.5,
      label: 'Edom',
      id: 1,
      kind: 'region',
      area: [_square(35.5, 30.5, 0.4)],
    );
    expect(await _tapMap(tester, [edom], const Offset(200, 260)), edom);
    // Outside its ground, nothing.
    expect(await _tapMap(tester, [edom], const Offset(10, 10)), isNull);
  });

  testWidgets('a tap on a river opens it', (tester) async {
    final jordan = MapPin(
      latitude: 32.3,
      longitude: 35.55,
      label: 'Jordan',
      id: 2,
      kind: 'river',
      line: const [
        [35.55, 32.7, 35.55, 31.8],
      ],
    );
    // The map fits the course, so it runs down the middle; a tap beside it,
    // well away from the pin, finds it.
    expect(await _tapMap(tester, [jordan], const Offset(204, 260)), jordan);
  });

  testWidgets('a pin is found before the region around it', (tester) async {
    final judah = MapPin(
      latitude: 31.5,
      longitude: 35.1,
      label: 'Judah',
      id: 1,
      kind: 'region',
      area: [_square(35.1, 31.5, 0.5)],
    );
    const hebron = MapPin(
      latitude: 31.2,
      longitude: 35.1,
      label: 'Hebron',
      id: 2,
      kind: 'settlement',
    );
    MapPin? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: PlaceMap(
              basemap: _basemap,
              pins: [judah, hebron],
              onPinTap: (pin) => tapped = pin,
            ),
          ),
        ),
      ),
    );
    final state = tester.getTopLeft(find.byType(PlaceMap));
    // The map fits Judah's ground, at least 1.6 degrees with a margin of
    // 0.3 times that, to its 400 pixels; Hebron is 0.3 degrees below the
    // middle.
    const perDegree = 400 / (1.6 * 1.3);
    await tester.tapAt(state + const Offset(200, 200 + .3 * perDegree));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tapped, hebron);
  });
}
