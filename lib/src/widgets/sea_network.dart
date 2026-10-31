import 'dart:convert';
import 'package:flutter/services.dart';
import 'sea_geometry.dart';

/// Estimated maritime courses from ORBIS, checked against the map's coast.
/// Uses distance, not ORBIS's seasonal costs; never estimates sailing times.
class SeaNetwork {
  SeaNetwork._(this.nodes, this.coast, List<dynamic> edges) {
    for (final e in edges) {
      final a = e[0] as int, b = e[1] as int;
      final d = SeaGeometry.km(
        nodes[a * 2],
        nodes[a * 2 + 1],
        nodes[b * 2],
        nodes[b * 2 + 1],
      );
      (_links[a] ??= []).add((b, d));
      (_links[b] ??= []).add((a, d));
    }
  }
  final List<double> nodes;
  final SeaGeometry coast;
  final _links = <int, List<(int, double)>>{};
  static const asset = 'assets/map/sea_routes.json';
  static Future<SeaNetwork>? _loading;
  static Future<SeaNetwork> load() => _loading ??= Future.wait([
    rootBundle.loadString(asset),
    rootBundle.loadString('assets/map/basemap.json'),
  ]).then((data) => parse(data[0], data[1]));
  static SeaNetwork parse(String routes, String basemap) {
    final data = jsonDecode(routes), base = jsonDecode(basemap);
    return SeaNetwork._(
      [for (final n in data['nodes']) (n as num).toDouble()],
      SeaGeometry([
        for (final r in base['land'])
          [for (final n in r) (n as num).toDouble()],
      ]),
      data['edges'],
    );
  }

  final _cache = <String, List<double>?>{};

  /// All supplied waypoints are mandatory. Return no replacement if any
  /// stretch is unsupported, rather than silently dropping a constraint.
  List<double>? route(List<double> points) {
    final key = points.join(',');
    if (_cache.containsKey(key)) return _cache[key];
    final result = _through(points);
    if (_cache.length >= 128) _cache.remove(_cache.keys.first);
    _cache[key] = result;
    return result;
  }

  List<double>? _through(List<double> points) {
    if (points.length < 4 || points.length.isOdd) return null;
    final out = <double>[points[0], points[1]];
    for (var i = 0; i + 3 < points.length; i += 2) {
      final part = _route(
        points[i],
        points[i + 1],
        points[i + 2],
        points[i + 3],
      );
      if (part == null) return null;
      out.addAll(part.skip(2));
    }
    return out;
  }

  List<(int, double)> _near(double x, double y) {
    final found = <(int, double)>[];
    for (final n in _links.keys) {
      final d = SeaGeometry.km(x, y, nodes[n * 2], nodes[n * 2 + 1]);
      if (d <= 30) found.add((n, d));
    }
    found.sort((a, b) => a.$2.compareTo(b.$2));
    // A small harbour approach may straddle the modern coastline. Never
    // allow a connector to cross an island farther along its course.
    return found
        .where(
          (p) => coast.clear(
            x,
            y,
            nodes[p.$1 * 2],
            nodes[p.$1 * 2 + 1],
            portKm: 5,
          ),
        )
        .take(8)
        .toList();
  }

  List<double>? _route(double x1, double y1, double x2, double y2) {
    final direct = SeaGeometry.km(x1, y1, x2, y2);
    if (direct < 1) return [x1, y1, x2, y2];
    final from = _near(x1, y1), to = _near(x2, y2);
    if (from.isEmpty || to.isEmpty) return null;
    final targets = {for (final (n, d) in to) n: d};
    final costs = <int, double>{}, via = <int, int>{}, heap = _Heap();
    for (final (n, d) in from) {
      costs[n] = d;
      via[n] = -1;
      heap.push(d, n);
    }
    var best = double.infinity, end = -1;
    final limit = direct * 2 + 80;
    while (heap.isNotEmpty) {
      final (d, n) = heap.pop();
      if (d != costs[n]) continue;
      if (d > best || d > limit) break;
      if (targets.containsKey(n) && d + targets[n]! < best) {
        best = d + targets[n]!;
        end = n;
      }
      for (final (next, length) in _links[n] ?? <(int, double)>[]) {
        final cost = d + length;
        if (cost < (costs[next] ?? double.infinity)) {
          costs[next] = cost;
          via[next] = n;
          heap.push(cost, next);
        }
      }
    }
    if (end < 0 || best > limit) return null;
    final chain = <int>[];
    for (var n = end; n >= 0; n = via[n]!) {
      chain.add(n);
    }
    return [
      x1,
      y1,
      for (final n in chain.reversed) ...[nodes[n * 2], nodes[n * 2 + 1]],
      x2,
      y2,
    ];
  }
}

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
