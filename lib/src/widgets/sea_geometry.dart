import 'dart:math' as math;

/// Coastline checks shared by the asset builder and maritime routing.
class SeaGeometry {
  SeaGeometry(List<List<double>> land) {
    for (final ring in land) {
      var west = double.infinity, east = -double.infinity;
      var south = double.infinity, north = -double.infinity;
      for (var i = 0; i + 1 < ring.length; i += 2) {
        west = math.min(west, ring[i]);
        east = math.max(east, ring[i]);
        south = math.min(south, ring[i + 1]);
        north = math.max(north, ring[i + 1]);
      }
      for (var x = west.floor(); x <= east.floor(); x++) {
        for (var y = south.floor(); y <= north.floor(); y++) {
          (_cells[(x, y)] ??= []).add(ring);
        }
      }
    }
  }
  final _cells = <(int, int), List<List<double>>>{};
  bool onLand(double x, double y) {
    for (final ring in _cells[(x.floor(), y.floor())] ?? <List<double>>[]) {
      var inside = false;
      for (var i = 0, j = ring.length - 2; i < ring.length; j = i, i += 2) {
        final ax = ring[i], ay = ring[i + 1], bx = ring[j], by = ring[j + 1];
        if ((ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax) {
          inside = !inside;
        }
      }
      if (inside) return true;
    }
    return false;
  }

  /// Sample every 500 m, tolerating only the immediate approach to a port.
  /// This checks the map's coastline resolution, not navigational clearance.
  bool clear(double x1, double y1, double x2, double y2, {double portKm = 0}) {
    final distance = km(x1, y1, x2, y2);
    final steps = math.max(1, (distance / .5).ceil());
    var leftPort = !onLand(x1, y1);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      if (onLand(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)) {
        if (leftPort || distance * t >= portKm) return false;
      } else {
        leftPort = true;
      }
    }
    return true;
  }

  static double km(double x1, double y1, double x2, double y2) {
    final dx = (x2 - x1) * math.cos((y1 + y2) / 2 * math.pi / 180),
        dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy) * 111.2;
  }
}
