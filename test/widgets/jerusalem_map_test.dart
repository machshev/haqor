import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/jerusalem_map.dart';

void main() {
  test(
    'AD 30 reconstruction excludes later walls and includes city detail',
    () {
      final labels = jerusalemFeatures.map((f) => f.label).join(' ');
      expect(labels, contains('Second Wall'));
      expect(labels, isNot(contains('Third Wall')));
      expect(labels, isNot(contains('Ottoman')));
      expect(labels, contains('Temple precinct'));
      expect(labels, contains('Siloam'));
      expect(labels, contains('Antonia'));
      for (final f in jerusalemFeatures) {
        expect(f.points.length.isEven, isTrue);
        expect(jerusalemBounds.inflate(.002).contains(f.labelAt), isTrue);
      }
    },
  );

  testWidgets(
    'city detail is opt-in, explains estimates and preserves pin taps',
    (tester) async {
      MapPin? tapped;
      final map = Basemap.parse(
        '{"land":[[35,31,36,31,36,32,35,32]],"lakes":[],"rivers":[]}',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceMap(
              basemap: map,
              pins: const [
                MapPin(
                  longitude: 35.2355,
                  latitude: 31.776,
                  label: 'Temple',
                  id: 1,
                ),
              ],
              onPinTap: (pin) => tapped = pin,
            ),
          ),
        ),
      );
      expect(find.byTooltip('About this reconstruction'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('jerusalem-detail')));
      await tester.pump();
      expect(find.byTooltip('About this reconstruction'), findsOneWidget);
      await tester.tap(find.byTooltip('About this reconstruction'));
      await tester.pumpAndSettle();
      expect(find.text('Jerusalem around AD 30'), findsOneWidget);
      expect(find.textContaining('Third Wall'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // The pin is at the fitted bounds' centre, independent of viewport size.
      await tester.tapAt(tester.getCenter(find.byType(PlaceMap)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tapped?.id, 1);
      await tester.tap(find.byTooltip('Hide Jerusalem reconstruction'));
      await tester.pump();
      expect(find.byTooltip('About this reconstruction'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'selecting nearby events keeps the Jerusalem view at city scale',
    (tester) async {
      const a = MapPin(longitude: 35.230, latitude: 31.776, label: 'A', id: 1);
      const b = MapPin(longitude: 35.234, latitude: 31.776, label: 'B', id: 2);
      MapPin? tapped;
      Widget build(List<double>? focus) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: PlaceMap(
              basemap: Basemap.parse('{"land":[],"lakes":[],"rivers":[]}'),
              pins: const [a, b],
              focus: focus,
              fitFocus: true,
              onPinTap: (pin) => tapped = pin,
            ),
          ),
        ),
      );
      await tester.pumpWidget(build(null));
      await tester.tap(find.byKey(const ValueKey('jerusalem-detail')));
      await tester.pumpWidget(build(const [35.230, 31.776, 35.234, 31.776]));
      await tester.pump();
      final middle = tester.getCenter(find.byType(PlaceMap));
      final half = .002 * math.cos(32 * math.pi / 180) * (400 * .8 / .008);
      await tester.tapAt(middle + Offset(half, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tapped, b);
      expect(tester.takeException(), isNull);
    },
  );
}
