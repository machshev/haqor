import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/place_map.dart';
import 'package:haqor/src/widgets/road_network.dart';

/// Kilometres along [points], longitude, latitude pairs.
double length(List<double> points) {
  var km = 0.0;
  for (var i = 0; i + 3 < points.length; i += 2) {
    final dx =
        (points[i + 2] - points[i]) *
        math.cos((points[i + 1] + points[i + 3]) / 2 * math.pi / 180);
    final dy = points[i + 3] - points[i + 1];
    km += math.sqrt(dx * dx + dy * dy) * 111.2;
  }
  return km;
}

void main() {
  // A road bending north between two towns a degree apart, and a spur.
  //
  //        1 ---- 2
  //       /        \
  //      0          3 ---- 4
  final network = RoadNetwork.parse(
    jsonEncode({
      'nodes': [35.0, 31.0, 35.2, 31.3, 35.8, 31.3, 36.0, 31.0, 37.0, 31.0],
      'fragments': [
        [0, 1, 0, 35.1, 31.2],
        [1, 2, 0],
        [2, 3, 0, 35.9, 31.2],
        [3, 4, 2],
      ],
    }),
  );

  test('a long leg follows the fragments from one end to the other', () {
    final way = network.route(35.0, 31.0, 36.0, 31.0)!;
    expect(way.sublist(0, 2), [35.0, 31.0]);
    expect(way.sublist(way.length - 2), [36.0, 31.0]);
    // Through the bend's corners, in order.
    final points = [
      for (var i = 0; i + 1 < way.length; i += 2) (way[i], way[i + 1]),
    ];
    final corners = [(35.2, 31.3), (35.8, 31.3)];
    expect(points.indexOf(corners[0]), lessThan(points.indexOf(corners[1])));
    expect(points.indexOf(corners[0]), greaterThan(0));
  });

  test('a leg is routed backwards along the fragments too', () {
    final way = network.route(36.0, 31.0, 35.0, 31.0)!;
    final points = [
      for (var i = 0; i + 1 < way.length; i += 2) (way[i], way[i + 1]),
    ];
    expect(
      points.indexOf((35.8, 31.3)),
      lessThan(points.indexOf((35.2, 31.3))),
    );
  });

  test('a place off the road joins it where it passes nearest', () {
    // From a little south of the spur's middle to the far town.
    final way = network.route(36.5, 30.97, 35.0, 31.0)!;
    expect(way.sublist(0, 4), [36.5, 30.97, 36.5, 31.0]);
  });

  test('two places on one fragment keep to it', () {
    final way = network.route(36.2, 31.0, 36.9, 31.0)!;
    expect(way, [36.2, 31.0, 36.2, 31.0, 36.9, 31.0, 36.9, 31.0]);
  });

  test('a short leg, or one far from a road, is left straight', () {
    expect(network.route(35.0, 31.0, 35.05, 31.0), isNull);
    expect(network.route(35.0, 31.0, 35.5, 32.5), isNull);
  });

  test('a road far out of the way is not taken', () {
    // Round the bend from its foot to a point just north of the far town.
    final around = RoadNetwork.parse(
      jsonEncode({
        'nodes': [35.0, 31.0, 35.0, 33.0, 35.3, 33.0, 35.3, 31.0],
        'fragments': [
          [0, 1, 0],
          [1, 2, 0],
          [2, 3, 0],
        ],
      }),
    );
    expect(around.route(35.0, 31.0, 35.3, 31.0), isNull);
  });

  test('a leg by sea is drawn as it is; by land, along the roads', () {
    const voyage = MapLeg([35.0, 31.0, 36.0, 31.0], bySea: true);
    expect(identical(voyage.along(network), voyage), isTrue);
    final walk = const MapLeg([35.0, 31.0, 36.0, 31.0]).along(network);
    expect(walk.points.length, greaterThan(4));
    expect(walk.bySea, isFalse);
  });

  group('the bundled highways', () {
    final roads = RoadNetwork.parse(
      File('assets/map/roads.json').readAsStringSync(),
    );

    test('take the Gospels\' journeys along the roads of the land', () {
      // Nazareth to Bethlehem for the census, and Jerusalem down to Jericho.
      for (final (x1, y1, x2, y2) in [
        (35.2975, 32.7022, 35.2003, 31.7049),
        (35.2345, 31.7767, 35.4444, 31.8711),
      ]) {
        final way = roads.route(x1, y1, x2, y2);
        expect(way, isNotNull);
        expect(way!.length, greaterThan(20));
      }
    });

    test('reach Paul\'s Asia Minor and Abram\'s Mesopotamia', () {
      // Perga up to Antioch in Pisidia; Ur up the Euphrates to Harran.
      for (final (x1, y1, x2, y2) in [
        (30.8537, 36.9604, 31.1892, 38.3061),
        (46.1044, 30.9622, 39.0328, 36.8644),
      ]) {
        final way = roads.route(x1, y1, x2, y2)!;
        final straight = length([x1, y1, x2, y2]);
        expect(length(way), inInclusiveRange(straight, straight * 1.6 + 10));
      }
    });
  });
}
