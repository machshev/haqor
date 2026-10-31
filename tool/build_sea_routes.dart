// dart tool/build_sea_routes.dart <ORBIS base_routes.geojson> <basemap.json> <out>
// ORBIS revision 65881112a6e5246d0bf3a90ac22dad7a2728cc2d, MIT.
// Keep coastal/overseas/ferry geometry only; join coincident water vertices.
// Reject segments crossing the bundled coastline. Nearby visible vertices
// bridge gaps left by ORBIS's coarse coast and connect its separate modes.
import 'dart:convert';
import 'dart:io';
import 'package:haqor/src/widgets/sea_geometry.dart';

void main(List<String> args) {
  final source = jsonDecode(File(args[0]).readAsStringSync());
  final base = jsonDecode(File(args[1]).readAsStringSync());
  final coast = SeaGeometry([
    for (final r in base['land']) [for (final n in r) (n as num).toDouble()],
  ]);
  final gaps = <List<double>>[];
  final nodes = <List<double>>[], ids = <String, int>{}, edges = <(int, int)>{};
  int? node(dynamic p) {
    final x = (p[0] as num).toDouble(), y = (p[1] as num).toDouble();
    if (coast.onLand(x, y)) {
      gaps.add([x, y]);
      return null;
    }
    final key = '${x.toStringAsFixed(5)},${y.toStringAsFixed(5)}';
    return ids.putIfAbsent(key, () {
      nodes.add([x, y]);
      return nodes.length - 1;
    });
  }

  void link(int a, int b) {
    if (a == b) return;
    final p = nodes[a], q = nodes[b];
    if (coast.clear(p[0], p[1], q[0], q[1])) {
      edges.add(a < b ? (a, b) : (b, a));
    } else {
      gaps.add([(p[0] + q[0]) / 2, (p[1] + q[1]) / 2]);
    }
  }

  for (final f in source['features']) {
    if (!['coastal', 'overseas', 'ferry'].contains(f['properties']['t'])) {
      continue;
    }
    final geometry = f['geometry'];
    final lines = geometry['type'] == 'MultiLineString'
        ? geometry['coordinates']
        : [geometry['coordinates']];
    for (final line in lines) {
      int? last;
      for (final p in line) {
        final next = node(p);
        if (last != null && next != null) link(last, next);
        last = next;
      }
    }
  }
  // Add local water vertices where ORBIS's coarse geometry meets land.
  // These short coastline detours repair narrow straits, not new long routes.
  final baseCount = nodes.length;
  final repairs = gaps.toList();
  gaps.clear();
  for (final p in repairs) {
    final x = (p[0] * 40).round(), y = (p[1] * 40).round();
    for (var dx = -6; dx <= 6; dx++) {
      for (var dy = -6; dy <= 6; dy++) {
        final px = (x + dx) / 40, py = (y + dy) / 40;
        if (!coast.onLand(px, py)) node([px, py]);
      }
    }
  }
  final cells = <(int, int), List<int>>{};
  for (var i = 0; i < nodes.length; i++) {
    final p = nodes[i], x = (p[0] * 4).floor(), y = (p[1] * 4).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final j in cells[(x + dx, y + dy)] ?? <int>[]) {
          final q = nodes[j];
          if (SeaGeometry.km(p[0], p[1], q[0], q[1]) <=
              (i < baseCount && j < baseCount ? 20 : 5)) {
            link(i, j);
          }
        }
      }
    }
    (cells[(x, y)] ??= []).add(i);
  }
  File(args[2]).writeAsStringSync(
    jsonEncode({
      'source':
          'ORBIS, Elijah Meeks, MIT; 65881112a6e5246d0bf3a90ac22dad7a2728cc2d. Coastline checked against Haqor basemap. Undirected distance estimates, not seasonal travel times.',
      'nodes': [
        for (final p in nodes)
          ...p.map((v) => double.parse(v.toStringAsFixed(5))),
      ],
      'edges': [
        for (final (a, b) in edges) [a, b],
      ],
    }),
  );
  stdout.writeln('${nodes.length} water vertices, ${edges.length} links');
}
