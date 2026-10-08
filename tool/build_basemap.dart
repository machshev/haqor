// Build assets/map/basemap.json, the coastlines, lakes and rivers the place
// maps draw, from Natural Earth (public domain, naturalearthdata.com).
//
// The app draws its maps offline, so the base layer is bundled: land, lakes
// and rivers clipped to the lands of the Bible, from Spain to Persia, and
// simplified until they weigh a few hundred kilobytes. Natural Earth's 1:10m
// land is used over the Levant, where the maps zoom in furthest, and its
// 1:50m land elsewhere.
//
//   tool/fetch-basemap.sh    # downloads the pinned layers and runs this
//
// Usage: dart run tool/build_basemap.dart <natural-earth-geojson-dir> <out>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// [west, south, east, north] in degrees.
typedef Box = List<double>;

const Box world = [-12, 4, 64, 48];
const Box levant = [31, 27.5, 40, 37.5];

/// Douglas–Peucker tolerances, in degrees.
const coarse = 0.03;
const fine = 0.004;

typedef Ring = List<math.Point<double>>;

Iterable<Ring> rings(Map<String, dynamic> geometry) sync* {
  Ring ring(List<dynamic> coordinates) => [
    for (final c in coordinates)
      math.Point((c[0] as num).toDouble(), (c[1] as num).toDouble()),
  ];
  final coordinates = geometry['coordinates'] as List<dynamic>;
  switch (geometry['type']) {
    case 'Polygon':
      for (final r in coordinates) {
        yield ring(r as List<dynamic>);
      }
    case 'MultiPolygon':
      for (final polygon in coordinates) {
        for (final r in polygon as List<dynamic>) {
          yield ring(r as List<dynamic>);
        }
      }
    case 'LineString':
      yield ring(coordinates);
    case 'MultiLineString':
      for (final line in coordinates) {
        yield ring(line as List<dynamic>);
      }
  }
}

/// Clip a closed ring to [box] (Sutherland–Hodgman, one edge at a time).
Ring clipPolygon(Ring ring, Box box) {
  var out = ring;
  final edges =
      <
        (
          bool Function(math.Point<double>),
          math.Point<double> Function(math.Point<double>, math.Point<double>),
        )
      >[
        ((p) => p.x >= box[0], (a, b) => _atX(a, b, box[0])),
        ((p) => p.x <= box[2], (a, b) => _atX(a, b, box[2])),
        ((p) => p.y >= box[1], (a, b) => _atY(a, b, box[1])),
        ((p) => p.y <= box[3], (a, b) => _atY(a, b, box[3])),
      ];
  for (final (inside, cross) in edges) {
    if (out.isEmpty) break;
    final input = out;
    out = [];
    for (var i = 0; i < input.length; i++) {
      final current = input[i];
      final previous = input[(i + input.length - 1) % input.length];
      if (inside(current)) {
        if (!inside(previous)) out.add(cross(previous, current));
        out.add(current);
      } else if (inside(previous)) {
        out.add(cross(previous, current));
      }
    }
  }
  return out;
}

math.Point<double> _atX(math.Point<double> a, math.Point<double> b, double x) =>
    math.Point(x, a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x));

math.Point<double> _atY(math.Point<double> a, math.Point<double> b, double y) =>
    math.Point(a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y), y);

bool _inBox(math.Point<double> p, Box box) =>
    p.x >= box[0] && p.x <= box[2] && p.y >= box[1] && p.y <= box[3];

/// The runs of a line inside [box]. Points outside are dropped, which cuts a
/// river at the edge to within a segment of it: enough at map scale.
List<Ring> clipLine(Ring line, Box box) {
  final out = <Ring>[];
  var run = <math.Point<double>>[];
  for (final p in line) {
    if (_inBox(p, box)) {
      run.add(p);
    } else if (run.isNotEmpty) {
      out.add(run);
      run = [];
    }
  }
  if (run.isNotEmpty) out.add(run);
  return out.where((r) => r.length >= 2).toList();
}

Ring simplify(Ring points, double tolerance) {
  if (points.length < 3) return points;
  final keep = List.filled(points.length, false);
  keep[0] = keep[points.length - 1] = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    var furthest = -1;
    var distance = 0.0;
    for (var i = first + 1; i < last; i++) {
      final d = _segmentDistance(points[i], points[first], points[last]);
      if (d > distance) {
        distance = d;
        furthest = i;
      }
    }
    if (furthest >= 0 && distance > tolerance) {
      keep[furthest] = true;
      stack
        ..add((first, furthest))
        ..add((furthest, last));
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ];
}

double _segmentDistance(
  math.Point<double> p,
  math.Point<double> a,
  math.Point<double> b,
) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final length = dx * dx + dy * dy;
  if (length == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / length).clamp(0.0, 1.0);
  return p.distanceTo(math.Point(a.x + t * dx, a.y + t * dy));
}

double _area(Ring r) {
  var sum = 0.0;
  for (var i = 0; i < r.length; i++) {
    final a = r[i], b = r[(i + 1) % r.length];
    sum += a.x * b.y - b.x * a.y;
  }
  return sum.abs() / 2;
}

/// A ring as the asset stores it: longitude, latitude, … to three places
/// (about 100 m), the precision the maps can show.
List<num> flat(Ring ring) => [
  for (final p in ring) ...[
    (p.x * 1000).round() / 1000,
    (p.y * 1000).round() / 1000,
  ],
];

List<Map<String, dynamic>> features(Directory dir, String name) {
  final file = File('${dir.path}/$name.geojson');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return (json['features'] as List<dynamic>).cast<Map<String, dynamic>>();
}

/// Polygons of [layer] within [box], simplified, those smaller than
/// [minArea] square degrees left out.
List<List<num>> polygons(
  Directory dir,
  String layer,
  Box box,
  double tolerance, {
  double minArea = 0.002,
}) {
  final out = <List<num>>[];
  for (final feature in features(dir, layer)) {
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;
    for (final ring in rings(geometry)) {
      var clipped = clipPolygon(ring, box);
      if (clipped.length < 3) continue;
      clipped = simplify(clipped, tolerance);
      if (clipped.length < 3 || _area(clipped) < minArea) continue;
      out.add(flat(clipped));
    }
  }
  return out;
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: build_basemap.dart <natural-earth-geojson-dir> <out>',
    );
    exit(64);
  }
  final dir = Directory(args[0]);
  final land = [
    ...polygons(dir, 'ne_50m_land', world, coarse, minArea: 0.05),
    ...polygons(dir, 'ne_10m_land', levant, fine),
  ];
  final lakes = polygons(dir, 'ne_10m_lakes', world, fine, minArea: 0.01);
  final rivers = <List<num>>[];
  for (final feature in features(dir, 'ne_10m_rivers_lake_centerlines')) {
    final properties = feature['properties'] as Map<String, dynamic>;
    // The major rivers everywhere; every river near the Levant.
    final rank = (properties['scalerank'] as num?) ?? 10;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;
    for (final line in rings(geometry)) {
      for (final run in [
        if (rank <= 5) ...clipLine(line, world),
        if (rank > 5) ...clipLine(line, levant),
      ]) {
        final simple = simplify(run, rank <= 5 ? coarse / 2 : fine);
        if (simple.length >= 2) rivers.add(flat(simple));
      }
    }
  }
  final out = {
    'source': 'Natural Earth (public domain), naturalearthdata.com, v5.1.2',
    'bounds': world,
    'land': land,
    'lakes': lakes,
    'rivers': rivers,
  };
  File(args[1])
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(out));
  stdout.writeln(
    'Wrote ${land.length} land, ${lakes.length} lake and ${rivers.length} '
    'river shapes to ${args[1]}',
  );
}
