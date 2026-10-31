import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// The highways of the ancient world, along which a [PlaceMap] draws a
/// journey's land legs: Itiner-e's Roman roads (CC BY 4.0), laid along the
/// older highways, kept as shared fragments, each running from one junction
/// to the next. A leg is not stored with its way; [route] finds the
/// fragments it follows. `tool/build_roads.dart` builds the asset.
class RoadNetwork {
  RoadNetwork._(this._fragments, this._grades, this._ends) {
    for (var f = 0; f < _fragments.length; f++) {
      final points = _fragments[f];
      var length = 0.0;
      for (var i = 0; i + 3 < points.length; i += 2) {
        length += _km(points[i], points[i + 1], points[i + 2], points[i + 3]);
        // In every cell its bounds cover, so it is found from either end.
        final west = _index(math.min(points[i], points[i + 2]));
        final east = _index(math.max(points[i], points[i + 2]));
        final south = _index(math.min(points[i + 1], points[i + 3]));
        final north = _index(math.max(points[i + 1], points[i + 3]));
        for (var x = west; x <= east; x++) {
          for (var y = south; y <= north; y++) {
            (_grid[_cell(x, y)] ??= []).add(f << 16 | i ~/ 2);
          }
        }
      }
      _lengths.add(length);
      final (from, to) = _ends[f];
      (_links[from] ??= []).add(f);
      (_links[to] ??= []).add(f);
    }
  }

  /// Each fragment's points, longitude, latitude pairs from its first
  /// junction to its last.
  final List<Float64List> _fragments;

  /// How much each fragment's length counts against it: 0 for a main road
  /// whose course is certain, more for one secondary, conjectured or
  /// hypothetical.
  final List<int> _grades;
  final List<(int, int)> _ends;
  final _lengths = <double>[];
  final _links = <int, List<int>>{};

  /// Segments by the cells of [_cellSize] degrees their bounds cover: a
  /// fragment's index, shifted 16 bits, and the segment's.
  final _grid = <int, List<int>>{};
  static const _cellSize = 0.1;

  static const asset = 'assets/map/roads.json';
  static Future<RoadNetwork>? _loading;

  /// The bundled network, read once.
  static Future<RoadNetwork> load() =>
      _loading ??= rootBundle.loadString(asset).then(parse);

  static RoadNetwork parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final nodes = Float64List.fromList([
      for (final v in data['nodes'] as List<dynamic>) (v as num).toDouble(),
    ]);
    final fragments = <Float64List>[];
    final grades = <int>[];
    final ends = <(int, int)>[];
    for (final f in data['fragments'] as List<dynamic>) {
      final list = f as List<dynamic>;
      final from = list[0] as int, to = list[1] as int;
      fragments.add(
        Float64List.fromList([
          nodes[from * 2],
          nodes[from * 2 + 1],
          for (final v in list.skip(3)) (v as num).toDouble(),
          nodes[to * 2],
          nodes[to * 2 + 1],
        ]),
      );
      grades.add(list[2] as int);
      ends.add((from, to));
    }
    return RoadNetwork._(fragments, grades, ends);
  }

  static int _index(double degrees) => (degrees / _cellSize).floor();

  static int _cell(int x, int y) => x * 100000 + y;

  /// Kilometres between two points, near enough over a leg.
  static double _km(double x1, double y1, double x2, double y2) {
    final dx = (x2 - x1) * math.cos((y1 + y2) / 2 * math.pi / 180);
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy) * 111.2;
  }

  /// Legs shorter than this, in kilometres, are drawn straight: there is no
  /// highway to keep to.
  static const minLeg = 12.0;

  /// The longest way on the roads, in kilometres, a leg of [straight]
  /// kilometres may take before the straight line is drawn instead: a road
  /// that far out of the way is not the one taken. A short leg is allowed
  /// more, as roads wind among hills.
  static double longest(double straight) => straight * 1.6 + 10;

  /// The way along the roads from one point to another: the longitude,
  /// latitude pairs of the points, the stretches of fragments between, or
  /// null when the leg is short, or no road runs near both ends, or the way
  /// on them goes too far round.
  Float64List? route(double x1, double y1, double x2, double y2) {
    final straight = _km(x1, y1, x2, y2);
    if (straight < minLeg) return null;
    // A place is joined to a road passing within a few kilometres of it.
    final reach = math.min(10.0, 3 + straight * .15);
    final from = _nearest(x1, y1, reach), to = _nearest(x2, y2, reach);
    if (from == null || to == null) return null;

    // Dijkstra's search over the junctions, from the two ends of the
    // fragment [from] lies on, to those of [to]'s.
    final cost = <int, double>{};
    final length = <int, double>{};
    final via = <int, int>{};
    final heap = _Heap();
    void reach0(int node, double c, double l) {
      if (c < (cost[node] ?? double.infinity)) {
        cost[node] = c;
        length[node] = l;
        via[node] = -1;
        heap.push(c, node);
      }
    }

    final (a0, b0) = _ends[from.fragment];
    final w0 = _weight(from.fragment);
    reach0(a0, from.along * w0, from.along);
    reach0(
      b0,
      (_lengths[from.fragment] - from.along) * w0,
      _lengths[from.fragment] - from.along,
    );
    final (a1, b1) = _ends[to.fragment];
    final targets = {a1, b1};
    var found = 0;
    // A bound on the search: no way is wanted far longer than the leg.
    final limit = longest(straight) * 2;
    while (heap.isNotEmpty && found < targets.length) {
      final (c, node) = heap.pop();
      if (c > cost[node]!) continue;
      if (c > limit) break;
      if (targets.contains(node)) found++;
      for (final f in _links[node] ?? const <int>[]) {
        final (p, q) = _ends[f];
        final next = p == node ? q : p;
        final nc = c + _lengths[f] * _weight(f);
        if (nc < (cost[next] ?? double.infinity)) {
          cost[next] = nc;
          length[next] = length[node]! + _lengths[f];
          via[next] = f;
          heap.push(nc, next);
        }
      }
    }

    // The way through the cheaper end of the destination's fragment, or, on
    // the one fragment, straight along it if that is cheaper.
    final w1 = _weight(to.fragment);
    final toA = to.along, toB = _lengths[to.fragment] - to.along;
    double total(int end) =>
        (cost[end] ?? double.infinity) + (end == a1 ? toA : toB) * w1;
    final end = total(a1) <= total(b1) ? a1 : b1;
    final best = total(end);
    final same = from.fragment == to.fragment;
    if (same && (from.along - to.along).abs() * w0 <= best) {
      final road = (from.along - to.along).abs();
      if (from.distance + road + to.distance > longest(straight)) {
        return null;
      }
      return Float64List.fromList([
        x1,
        y1,
        ..._stretch(from.fragment, from, to),
        x2,
        y2,
      ]);
    }
    if (best == double.infinity) return null;
    final road = length[end]! + (end == a1 ? toA : toB);
    if (from.distance + road + to.distance > longest(straight)) return null;

    // The fragments followed, back from [end].
    final chain = <(int, int)>[];
    var node = end;
    while (via[node]! >= 0) {
      final f = via[node]!;
      chain.add((f, node));
      final (p, q) = _ends[f];
      node = p == node ? q : p;
    }
    final out = <double>[x1, y1];
    // Along [from]'s fragment to the junction the search left by.
    out.addAll(_toEnd(from, node == a0));
    for (final (f, arrive) in chain.reversed) {
      final points = _fragments[f];
      final forwards = _ends[f].$2 == arrive;
      final n = points.length ~/ 2;
      for (var k = 1; k < n; k++) {
        final i = forwards ? k : n - 1 - k;
        out
          ..add(points[i * 2])
          ..add(points[i * 2 + 1]);
      }
    }
    // Along [to]'s fragment from the junction reached.
    final back = _toEnd(to, end == a1);
    for (var i = back.length - 2; i >= 0; i -= 2) {
      out
        ..add(back[i])
        ..add(back[i + 1]);
    }
    out.addAll([x2, y2]);
    return Float64List.fromList(out);
  }

  double _weight(int fragment) => 1 + .15 * _grades[fragment];

  /// The points from where [at] meets its fragment to the fragment's first
  /// junction when [toStart], else its last.
  List<double> _toEnd(_OnRoad at, bool toStart) {
    final points = _fragments[at.fragment];
    final n = points.length ~/ 2;
    final out = <double>[at.x, at.y];
    if (toStart) {
      for (var k = at.segment; k >= 0; k--) {
        out.addAll([points[k * 2], points[k * 2 + 1]]);
      }
    } else {
      for (var k = at.segment + 1; k < n; k++) {
        out.addAll([points[k * 2], points[k * 2 + 1]]);
      }
    }
    return out;
  }

  /// The points along one fragment from [a] to [b].
  List<double> _stretch(int fragment, _OnRoad a, _OnRoad b) {
    final points = _fragments[fragment];
    final out = <double>[a.x, a.y];
    if (a.along <= b.along) {
      for (var k = a.segment + 1; k <= b.segment; k++) {
        out.addAll([points[k * 2], points[k * 2 + 1]]);
      }
    } else {
      for (var k = a.segment; k > b.segment; k--) {
        out.addAll([points[k * 2], points[k * 2 + 1]]);
      }
    }
    return out..addAll([b.x, b.y]);
  }

  /// The nearest point to [x], [y] on any road within [reach] kilometres.
  _OnRoad? _nearest(double x, double y, double reach) {
    final shrink = math.cos(y * math.pi / 180);
    final across = (reach / 111.2 / shrink / _cellSize).ceil();
    final up = (reach / 111.2 / _cellSize).ceil();
    final cx = _index(x), cy = _index(y);
    _OnRoad? best;
    for (var dx = -across; dx <= across; dx++) {
      for (var dy = -up; dy <= up; dy++) {
        for (final key in _grid[_cell(cx + dx, cy + dy)] ?? const <int>[]) {
          final f = key >> 16, s = key & 0xffff;
          final points = _fragments[f];
          final ax = points[s * 2], ay = points[s * 2 + 1];
          final bx = points[s * 2 + 2], by = points[s * 2 + 3];
          // Projected, longitude shrunk to match latitude.
          final ex = (bx - ax) * shrink, ey = by - ay;
          final px = (x - ax) * shrink, py = y - ay;
          final l = ex * ex + ey * ey;
          final t = l == 0 ? 0.0 : ((px * ex + py * ey) / l).clamp(0.0, 1.0);
          final qx = ax + (bx - ax) * t, qy = ay + (by - ay) * t;
          final d = _km(x, y, qx, qy);
          if (d <= reach && (best == null || d < best.distance)) {
            var along = 0.0;
            for (var i = 0; i < s; i++) {
              along += _km(
                points[i * 2],
                points[i * 2 + 1],
                points[i * 2 + 2],
                points[i * 2 + 3],
              );
            }
            along += _km(ax, ay, qx, qy);
            best = _OnRoad(f, s, qx, qy, along, d);
          }
        }
      }
    }
    return best;
  }
}

/// Where a place meets a road: on [segment] of [fragment], at [x], [y],
/// [along] kilometres from its start and [distance] from the place.
class _OnRoad {
  _OnRoad(
    this.fragment,
    this.segment,
    this.x,
    this.y,
    this.along,
    this.distance,
  );
  final int fragment, segment;
  final double x, y, along, distance;
}

/// A binary min-heap of costs and junctions.
class _Heap {
  final _costs = <double>[];
  final _nodes = <int>[];

  bool get isNotEmpty => _costs.isNotEmpty;

  void push(double cost, int node) {
    _costs.add(cost);
    _nodes.add(node);
    var i = _costs.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_costs[parent] <= _costs[i]) break;
      _swap(i, parent);
      i = parent;
    }
  }

  (double, int) pop() {
    final top = (_costs[0], _nodes[0]);
    final lastCost = _costs.removeLast(), lastNode = _nodes.removeLast();
    if (_costs.isNotEmpty) {
      _costs[0] = lastCost;
      _nodes[0] = lastNode;
      var i = 0;
      while (true) {
        final l = i * 2 + 1, r = l + 1;
        var smallest = i;
        if (l < _costs.length && _costs[l] < _costs[smallest]) smallest = l;
        if (r < _costs.length && _costs[r] < _costs[smallest]) smallest = r;
        if (smallest == i) break;
        _swap(i, smallest);
        i = smallest;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final c = _costs[a], n = _nodes[a];
    _costs[a] = _costs[b];
    _nodes[a] = _nodes[b];
    _costs[b] = c;
    _nodes[b] = n;
  }
}
