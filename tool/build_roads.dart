// Build assets/map/roads.json, the highways the place maps draw a journey's
// land legs along, from Itiner-e, the digital atlas of the roads of the Roman
// Empire (CC BY 4.0, doi:10.5281/zenodo.17122148).
//
// The roads are kept as a network of shared fragments: each runs from one
// junction to the next, stored once, in the detail the maps can show, and a
// journey's leg is the fragments it follows, which the app finds when it
// draws the leg (see `RoadNetwork` in lib/src/widgets/road_network.dart). The
// backbones are the atlas's main roads, from Spain to Mesopotamia, and its
// secondary roads from Italy east, where the journeys of the Bible go; over
// the Levant, where the Gospels' journeys are short, the fragments keep the
// most detail. Beyond the empire, down the Euphrates to Babylon and Ur and up
// the Balikh to Harran, the highways are Haqor's own ([ownHighways]), drawn
// along Natural Earth's rivers (public domain). The Roman roads were laid
// along the older highways, so the network serves the journeys of the Old
// Testament as well as the New.
//
//   tool/fetch-basemap.sh    # downloads the pinned atlas and runs this
//
// Usage: dart run tool/build_roads.dart <itinere_roads.geojson>
//            <ne_10m_rivers_lake_centerlines.geojson> <out>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// [west, south, east, north] in degrees: the basemap's.
const world = [-12.0, 4.0, 64.0, 48.0];

/// Where the secondary roads are kept too: Italy to Mesopotamia.
const secondary = [12.0, 24.0, 50.0, 43.0];

/// Where the fragments keep more of their detail.
const levant = [33.8, 29.0, 37.5, 34.0];

/// Douglas–Peucker tolerances, in degrees.
const coarse = 0.004;
const fine = 0.0008;

/// How far, in degrees, a road's loose end is joined to another road that
/// passes it: the atlas ends a branch on its trunk, not always on a vertex.
const join = 0.003;

typedef Point = math.Point<double>;

/// World Mercator (EPSG:3395, on the WGS 84 ellipsoid), the atlas's
/// projection, back to longitude and latitude.
Point unproject(double x, double y) {
  const a = 6378137.0, e = 0.0818191908426215;
  final t = math.exp(-y / a);
  var phi = math.pi / 2 - 2 * math.atan(t);
  for (var i = 0; i < 8; i++) {
    final s = e * math.sin(phi);
    phi = math.pi / 2 - 2 * math.atan(t * math.pow((1 - s) / (1 + s), e / 2));
  }
  return Point(x / a * 180 / math.pi, phi * 180 / math.pi);
}

bool inBox(Point p, List<double> box) =>
    p.x >= box[0] && p.y >= box[1] && p.x <= box[2] && p.y <= box[3];

List<Point> simplify(List<Point> points, double tolerance) {
  if (points.length < 3) return points;
  final keep = List.filled(points.length, false);
  keep[0] = keep[points.length - 1] = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (first, last) = stack.removeLast();
    var furthest = -1;
    var distance = 0.0;
    for (var i = first + 1; i < last; i++) {
      final d = segmentDistance(points[i], points[first], points[last]);
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

double segmentDistance(Point p, Point a, Point b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final length = dx * dx + dy * dy;
  if (length == 0) return p.distanceTo(a);
  final t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / length).clamp(0.0, 1.0);
  return p.distanceTo(Point(a.x + t * dx, a.y + t * dy));
}

/// How much a road's length counts against it when a leg is routed: a main
/// road whose course is certain least, a secondary or conjectured one more,
/// a hypothetical one most, so that a leg keeps to the highways.
int grade(Map<String, dynamic> properties) {
  var grade = 0;
  if (properties['Type'] != 'Main Road') grade += 1;
  switch (properties['Segment_s']) {
    case 'Certain':
      break;
    case 'Conjectured':
      grade += 1;
    default:
      grade += 2;
  }
  return grade;
}

/// A place Haqor's own highway passes: its longitude and latitude, and the
/// river the highway follows from it to the next, if any: Natural Earth's
/// names for its lines, split by `|`.
typedef Waypoint = ({String name, double x, double y, String? follow});

/// Haqor's own highways, where the atlas has no road: beyond the empire's
/// border on the Euphrates, the way of Abram from Ur and of Judah's exiles to
/// Babylon. Each is cut into fragments where it meets the atlas's roads:
/// at Dura-Europos and Callinicum on the Euphrates, and Edessa beyond Harran.
/// Graded as conjectured secondary roads.
const List<List<Waypoint>> ownHighways = [
  // Up the Euphrates, as the river runs, from Ur past Babylon and the atlas's
  // road at Dura-Europos, which keeps away from the river, to Callinicum.
  [
    (name: 'Ur', x: 46.1036, y: 30.9625, follow: 'Euphrates|Al Furat'),
    (name: 'Babylon', x: 44.4209, y: 32.5364, follow: 'Euphrates|Al Furat'),
    (
      name: 'Dura-Europos',
      x: 40.7147,
      y: 34.7422,
      follow: 'Euphrates|Al Furat',
    ),
    (name: 'Callinicum', x: 39.051, y: 35.884, follow: null),
  ],
  // Up the valley of the Balikh, from its mouth at Callinicum to Harran, and
  // on to Edessa.
  [
    (name: 'Callinicum', x: 39.051, y: 35.884, follow: null),
    (name: 'Harran', x: 39.0328, y: 36.8644, follow: null),
    (name: 'Edessa', x: 38.7842, y: 37.1576, follow: null),
  ],
];

/// Natural Earth's rivers by name, each as its lines.
Map<String, List<List<Point>>> rivers(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  final out = <String, List<List<Point>>>{};
  for (final feature in json['features'] as List<dynamic>) {
    final name = feature['properties']['name'] as String?;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (name == null || geometry == null) continue;
    final lines = geometry['type'] == 'LineString'
        ? [geometry['coordinates']]
        : geometry['coordinates'] as List<dynamic>;
    for (final line in lines) {
      (out[name] ??= []).add([
        for (final c in line as List<dynamic>)
          Point((c[0] as num).toDouble(), (c[1] as num).toDouble()),
      ]);
    }
  }
  return out;
}

/// The course of [lines], a river, from the point on it nearest [from] to
/// that nearest [to]: the shortest way through its vertices, its lines
/// joined where they end within 0.01°.
List<Point> along(List<List<Point>> lines, Point from, Point to) {
  final points = [for (final line in lines) ...line];
  final links = List.generate(points.length, (_) => <int>[]);
  var at = 0;
  final ends = <int>[];
  for (final line in lines) {
    for (var i = 0; i + 1 < line.length; i++) {
      links[at + i].add(at + i + 1);
      links[at + i + 1].add(at + i);
    }
    ends.addAll([at, at + line.length - 1]);
    at += line.length;
  }
  for (final a in ends) {
    for (final b in ends) {
      if (a != b && points[a].distanceTo(points[b]) < 0.01) links[a].add(b);
    }
  }
  int nearest(Point p) {
    var best = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].distanceTo(p) < points[best].distanceTo(p)) best = i;
    }
    return best;
  }

  final start = nearest(from), end = nearest(to);
  final distance = List.filled(points.length, double.infinity);
  final previous = List.filled(points.length, -1);
  final done = List.filled(points.length, false);
  distance[start] = 0;
  // Few enough vertices for the simple search.
  while (true) {
    var u = -1;
    for (var i = 0; i < points.length; i++) {
      if (!done[i] && (u < 0 || distance[i] < distance[u])) u = i;
    }
    if (u < 0 || distance[u] == double.infinity || u == end) break;
    done[u] = true;
    for (final v in links[u]) {
      final d = distance[u] + points[u].distanceTo(points[v]);
      if (d < distance[v]) {
        distance[v] = d;
        previous[v] = u;
      }
    }
  }
  if (distance[end] == double.infinity) {
    throw StateError('no course from $from to $to');
  }
  final out = <Point>[];
  for (var v = end; v >= 0; v = previous[v]) {
    out.add(points[v]);
  }
  return out.reversed.toList();
}

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'usage: build_roads.dart <itinere_roads.geojson> '
      '<ne_10m_rivers_lake_centerlines.geojson> <out>',
    );
    exit(64);
  }
  final json =
      jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;

  // The roads kept, as runs of vertices, each vertex an index into [vertices]
  // shared by every road through it.
  final vertices = <Point>[];
  final index = <(int, int), int>{};
  int vertex(Point p) =>
      index.putIfAbsent(((p.x * 1e5).round(), (p.y * 1e5).round()), () {
        vertices.add(p);
        return vertices.length - 1;
      });
  final roads = <(List<int>, int)>[];
  for (final feature in json['features'] as List<dynamic>) {
    final properties = feature['properties'] as Map<String, dynamic>;
    final kept = properties['Type'] == 'Main Road' ? world : secondary;
    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) continue;
    final lines = geometry['type'] == 'LineString'
        ? [geometry['coordinates']]
        : geometry['coordinates'] as List<dynamic>;
    for (final line in lines) {
      var run = <int>[];
      void close() {
        if (run.length >= 2) roads.add((run, grade(properties)));
        run = [];
      }

      for (final c in line as List<dynamic>) {
        final p = unproject((c[0] as num).toDouble(), (c[1] as num).toDouble());
        if (inBox(p, kept)) {
          final v = vertex(p);
          if (run.isEmpty || run.last != v) run.add(v);
        } else {
          close();
        }
      }
      close();
    }
  }

  // Haqor's own highways, each place moved onto the atlas's nearest vertex
  // within a tenth of a degree, where the atlas's road reaches.
  final courses = rivers(args[1]);
  Point onAtlas(Point p) {
    var best = p;
    var distance = 0.1;
    for (final v in vertices) {
      if (v.distanceTo(p) < distance) {
        distance = v.distanceTo(p);
        best = v;
      }
    }
    return best;
  }

  for (final highway in ownHighways) {
    final run = <int>[];
    for (final (i, w) in highway.indexed) {
      var p = Point(w.x, w.y);
      p = onAtlas(p);
      final points = [p];
      if (w.follow case final river? when i + 1 < highway.length) {
        final lines = [for (final name in river.split('|')) ...?courses[name]];
        if (lines.isEmpty) throw StateError('no river $river');
        final next = highway[i + 1];
        points.addAll(along(lines, p, Point(next.x, next.y)));
      }
      for (final q in points) {
        final v = vertex(q);
        if (run.isEmpty || run.last != v) run.add(v);
      }
    }
    // As a conjectured secondary road.
    roads.add((run, 2));
  }

  // Junctions: where roads end, and where a vertex is on more than one.
  final uses = List.filled(vertices.length, 0);
  final junction = List.filled(vertices.length, false);
  for (final (run, _) in roads) {
    for (final v in run) {
      uses[v]++;
    }
    junction[run.first] = junction[run.last] = true;
  }
  for (var v = 0; v < vertices.length; v++) {
    if (uses[v] > 1) junction[v] = true;
  }

  // A loose end, on no other road, is joined to the nearest vertex of
  // another road that passes within [join], which becomes a junction.
  final grid = <(int, int), List<int>>{};
  (int, int) cell(Point p) => ((p.x / join).floor(), (p.y / join).floor());
  final roadOf = List.filled(vertices.length, -1);
  for (final (i, (run, _)) in roads.indexed) {
    for (final v in run) {
      if (roadOf[v] < 0) {
        roadOf[v] = i;
        grid.putIfAbsent(cell(vertices[v]), () => []).add(v);
      }
    }
  }
  final links = <(List<int>, int)>[];
  for (final (i, (run, g)) in roads.indexed) {
    for (final end in [run.first, run.last]) {
      if (uses[end] > 1) continue;
      final p = vertices[end];
      final (cx, cy) = cell(p);
      var best = -1;
      var distance = join;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final v in grid[(cx + dx, cy + dy)] ?? const <int>[]) {
            if (roadOf[v] == i || v == end) continue;
            final d = vertices[v].distanceTo(p);
            if (d < distance) {
              distance = d;
              best = v;
            }
          }
        }
      }
      if (best >= 0) {
        junction[best] = true;
        links.add(([end, best], g));
      }
    }
  }

  // The fragments: each road cut at its junctions, simplified.
  final nodes = <int, int>{};
  final out = <List<num>>[];
  int node(int v) => nodes.putIfAbsent(v, () => nodes.length);
  for (final (run, g) in [...roads, ...links]) {
    var start = 0;
    for (var i = 1; i < run.length; i++) {
      if (!junction[run[i]] && i < run.length - 1) continue;
      final piece = [for (final v in run.sublist(start, i + 1)) vertices[v]];
      final close = piece.every((p) => inBox(p, levant));
      final simple = simplify(piece, close ? fine : coarse);
      final scale = close ? 1e4 : 1e3;
      out.add([
        node(run[start]),
        node(run[i]),
        g,
        for (final p in simple.sublist(1, simple.length - 1)) ...[
          (p.x * scale).round() / scale,
          (p.y * scale).round() / scale,
        ],
      ]);
      start = i;
    }
  }
  final points = List.filled(nodes.length, const Point(0, 0));
  nodes.forEach((v, n) => points[n] = vertices[v]);
  File(args[2])
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'source':
            'Itiner-e, the digital atlas of ancient roads, static version 2024 '
            '(CC BY 4.0), doi:10.5281/zenodo.17122148',
        'nodes': [
          for (final p in points) ...[
            (p.x * 1e4).round() / 1e4,
            (p.y * 1e4).round() / 1e4,
          ],
        ],
        // Each fragment: its first node, its last, its grade, then the
        // longitude, latitude pairs between.
        'fragments': out,
      }),
    );
  stdout.writeln(
    '${nodes.length} junctions, ${out.length} fragments, '
    '${links.length} loose ends joined',
  );
}
