import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:haqor/src/widgets/sea_network.dart';
import 'package:haqor/src/widgets/sea_geometry.dart';
import 'package:haqor/src/widgets/place_map.dart';

void main() {
  final sea = SeaNetwork.parse(
    File(SeaNetwork.asset).readAsStringSync(),
    File('assets/map/basemap.json').readAsStringSync(),
  );
  test('real Mediterranean voyages follow water, preserving endpoints', () {
    final cases = <String, List<double>>{
      'Caesarea–Sidon': [34.89, 32.5, 35.37, 33.56],
      'Myra–Cnidus': [29.97, 36.26, 27.37, 36.69],
      'Malta–Syracuse': [14.4, 35.95, 15.29, 37.07],
      'Syracuse–Rhegium': [15.29, 37.07, 15.65, 38.11],
      'Rhegium–Puteoli': [15.65, 38.11, 14.12, 40.82],
      'Patara–Tyre': [29.32, 36.26, 35.2, 33.27],
    };
    for (final entry in cases.entries) {
      final way = sea.route(entry.value);
      expect(way, isNotNull, reason: entry.key);
      expect(way!.take(2), entry.value.take(2));
      expect(way.skip(way.length - 2), entry.value.skip(2));
      for (var i = 2; i + 3 < way.length - 2; i += 2) {
        expect(
          sea.coast.clear(way[i], way[i + 1], way[i + 2], way[i + 3]),
          isTrue,
          reason: '${entry.key}: segment $i',
        );
      }
    }
  });
  test('offshore waypoints remain mandatory', () {
    final points = [
      35.37,
      33.56,
      34.9,
      35.85,
      33.0,
      35.75,
      31.0,
      36.1,
      29.97,
      36.26,
    ];
    final way = sea.route(points);
    expect(way, isNotNull);
    var last = -1;
    for (var i = 0; i < points.length; i += 2) {
      final index = way!.indexOf(points[i], last + 1);
      expect(index, greaterThan(last));
      expect(way[index + 1], points[i + 1]);
      last = index;
    }
  });
  test('uncovered inland routes retain their given course', () {
    const leg = MapLeg([44, 32, 46, 33], bySea: true);
    expect(identical(leg.atSea(sea), leg), isTrue);
  });
  test('drift bypasses the shipping network; sea styling survives routing', () {
    const drift = MapLeg(
      [24.08, 34.83, 14.4, 35.95],
      bySea: true,
      estimateSea: false,
      highlighted: true,
    );
    expect(identical(drift.atSea(sea), drift), isTrue);
    final sailing = const MapLeg(
      [15.65, 38.11, 14.12, 40.82],
      bySea: true,
      highlighted: true,
    ).atSea(sea);
    expect(sailing.bySea, isTrue);
    expect(sailing.highlighted, isTrue);
    expect(sailing.points.length, greaterThan(4));
  });
  test('disconnected network does not invent a crossing', () {
    final isolated = SeaNetwork.parse(
      jsonEncode({
        'nodes': [10, 35, 10.1, 35, 12, 35, 12.1, 35],
        'edges': [
          [0, 1],
          [2, 3],
        ],
      }),
      '{"land":[]}',
    );
    expect(isolated.route([10, 35, 12, 35]), isNull);
  });
  test('coast checks reject crossings through islands', () {
    final coast = SeaGeometry([
      [10, 35, 11, 35, 11, 36, 10, 36],
    ]);
    expect(coast.clear(9, 35.5, 12, 35.5), isFalse);
    expect(coast.clear(9, 34.9, 12, 34.9), isTrue);
  });
}
