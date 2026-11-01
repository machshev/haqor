// Paint Jerusalem around AD 30, seen from above, into
// assets/map/jerusalem_ad30.jpg: the image PlaceMap draws under the outlines
// of the Jerusalem reconstruction.
//
// The ground is the Terrain Tiles' heights (SRTM; registry.opendata.aws),
// shaded from the north-west, with the Tyropoeon cut back below its modern
// fill and the Temple platform levelled. On it are painted the walls,
// buildings, pools and ways of lib/src/jerusalem_plan.dart, at the same
// coordinates, so the outlines lie on what they name, with houses, terraces,
// olive groves and tombs filled in. It is an illustration of the plan, not a
// survey: the houses and trees are placed at random.
//
// The image is a grid over [jerusalemBox], linear in longitude and latitude,
// square on screen at the maps' reference latitude, as PlaceMap projects.
//
//   dart run tool/build_jerusalem_image.dart --tiles   # the tiles to fetch
//   dart run tool/build_jerusalem_image.dart <tile-dir> assets/map/jerusalem_ad30.jpg
//
// <tile-dir> holds each Terrarium tile z/x/y as z_x_y.png, as
// tool/fetch-basemap.sh downloads them.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:haqor/src/jerusalem_plan.dart';
import 'package:image/image.dart' as img;

const referenceLatitude = 32.0;
const zoom = 15;

/// Pixels to a degree of latitude: about 1.2 m a pixel.
const perDegree = 90000.0;
final metresPerPixel = 111320 / perDegree;

typedef P = (double, double);
typedef Rgb = (double, double, double);

final west = jerusalemBox.$1, south = jerusalemBox.$2;
final east = jerusalemBox.$3, north = jerusalemBox.$4;
final xScale = math.cos(referenceLatitude * math.pi / 180);
final width = ((east - west) * xScale * perDegree).round();
final height = ((north - south) * perDegree).round();

P px(double lon, double lat) =>
    ((lon - west) * xScale * perDegree, (north - lat) * perDegree);

List<P> pts(List<double> lonLat) => [
  for (var i = 0; i + 1 < lonLat.length; i += 2) px(lonLat[i], lonLat[i + 1]),
];

PlanFeature feature(String prefix) =>
    jerusalemPlan.firstWhere((f) => f.label.startsWith(prefix));

double _tileX(double lon) => (lon + 180) / 360 * (1 << zoom);
double _tileY(double lat) {
  final phi = lat * math.pi / 180;
  return (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) /
      2 *
      (1 << zoom);
}

Iterable<(int, int, int)> tiles() sync* {
  for (var x = _tileX(west).floor(); x <= _tileX(east).floor(); x++) {
    for (var y = _tileY(north).floor(); y <= _tileY(south).floor(); y++) {
      yield (zoom, x, y);
    }
  }
}

/// The picture, in linear 0-255 floats.
class Picture {
  Picture()
    : r = Float32List(width * height),
      g = Float32List(width * height),
      b = Float32List(width * height);
  final Float32List r, g, b;

  void blend(int x, int y, Rgb c, double a) {
    if (x < 0 || y < 0 || x >= width || y >= height || a <= 0) return;
    final i = y * width + x;
    final t = a > 1 ? 1.0 : a;
    r[i] += (c.$1 - r[i]) * t;
    g[i] += (c.$2 - g[i]) * t;
    b[i] += (c.$3 - b[i]) * t;
  }

  void poly(List<P> p, Rgb c, [double a = 1]) =>
      cover(p, (x, y, k) => blend(x, y, c, a * k));

  void line(List<P> p, double w, Rgb c, [double a = 1]) =>
      stroke(p, w, (x, y, k) => blend(x, y, c, a * k));

  void disc(double cx, double cy, double rad, Rgb c, [double a = 1]) {
    for (var y = (cy - rad - 1).floor(); y <= (cy + rad + 1).ceil(); y++) {
      for (var x = (cx - rad - 1).floor(); x <= (cx + rad + 1).ceil(); x++) {
        final d = math.sqrt(
          math.pow(x + .5 - cx, 2) + math.pow(y + .5 - cy, 2),
        );
        blend(x, y, c, a * (rad + .5 - d).clamp(0, 1));
      }
    }
  }

  /// A shape's shadow, cast to the south-east, under the shape.
  void shadow(List<P> p, double by, [double a = .35]) =>
      poly([for (final q in p) (q.$1 + by, q.$2 + by)], ink, a);
}

const Rgb ink = (40, 32, 22);

/// Calls [f] with each pixel [p] covers and how much of it, 4x4 sampled.
void cover(List<P> p, void Function(int x, int y, double k) f) {
  if (p.length < 3) return;
  var x0 = double.infinity, x1 = -double.infinity;
  var y0 = double.infinity, y1 = -double.infinity;
  for (final q in p) {
    x0 = math.min(x0, q.$1);
    x1 = math.max(x1, q.$1);
    y0 = math.min(y0, q.$2);
    y1 = math.max(y1, q.$2);
  }
  final left = math.max(0, x0.floor()), right = math.min(width - 1, x1.ceil());
  if (right < left) return;
  final row = Float32List(right - left + 1);
  for (
    var y = math.max(0, y0.floor());
    y <= math.min(height - 1, y1.ceil());
    y++
  ) {
    row.fillRange(0, row.length, 0);
    for (var s = 0; s < 4; s++) {
      final sy = y + (s + .5) / 4;
      final xs = <double>[];
      for (var i = 0; i < p.length; i++) {
        final a = p[i], b = p[(i + 1) % p.length];
        if ((a.$2 <= sy) != (b.$2 <= sy)) {
          xs.add(a.$1 + (sy - a.$2) / (b.$2 - a.$2) * (b.$1 - a.$1));
        }
      }
      xs.sort();
      for (var i = 0; i + 1 < xs.length; i += 2) {
        final xa = math.max(xs[i], left.toDouble());
        final xb = math.min(xs[i + 1], right + 1.0);
        for (var x = xa.floor(); x < xb.ceil() && x <= right; x++) {
          final k = math.min(xb, x + 1.0) - math.max(xa, x.toDouble());
          if (k > 0) row[x - left] += k / 4;
        }
      }
    }
    for (var i = 0; i < row.length; i++) {
      if (row[i] > 0) f(left + i, y, math.min(row[i], 1));
    }
  }
}

/// Distance from [q] to the segment [a] [b].
double segmentDistance(P q, P a, P b) {
  final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
  final l = dx * dx + dy * dy;
  final t = l == 0
      ? 0.0
      : (((q.$1 - a.$1) * dx + (q.$2 - a.$2) * dy) / l).clamp(0.0, 1.0);
  return math.sqrt(
    math.pow(q.$1 - a.$1 - t * dx, 2) + math.pow(q.$2 - a.$2 - t * dy, 2),
  );
}

double polylineDistance(P q, List<P> p) {
  var d = double.infinity;
  for (var i = 0; i + 1 < p.length; i++) {
    d = math.min(d, segmentDistance(q, p[i], p[i + 1]));
  }
  return d;
}

/// Calls [f] with each pixel within [w] / 2 of the polyline [p].
void stroke(List<P> p, double w, void Function(int x, int y, double k) f) {
  var x0 = double.infinity, x1 = -double.infinity;
  var y0 = double.infinity, y1 = -double.infinity;
  for (final q in p) {
    x0 = math.min(x0, q.$1);
    x1 = math.max(x1, q.$1);
    y0 = math.min(y0, q.$2);
    y1 = math.max(y1, q.$2);
  }
  final m = w / 2 + 1;
  for (
    var y = math.max(0, (y0 - m).floor());
    y <= math.min(height - 1, (y1 + m).ceil());
    y++
  ) {
    for (
      var x = math.max(0, (x0 - m).floor());
      x <= math.min(width - 1, (x1 + m).ceil());
      x++
    ) {
      final d = polylineDistance((x + .5, y + .5), p);
      final k = (w / 2 + .5 - d).clamp(0.0, 1.0);
      if (k > 0) f(x, y, k);
    }
  }
}

/// A mask of the pixels [p] covers.
Float32List mask(List<P> p) {
  final m = Float32List(width * height);
  cover(p, (x, y, k) => m[y * width + x] = math.max(m[y * width + x], k));
  return m;
}

Float32List strokeMask(List<P> p, double w) {
  final m = Float32List(width * height);
  stroke(p, w, (x, y, k) => m[y * width + x] = math.max(m[y * width + x], k));
  return m;
}

Rgb mix(Rgb a, Rgb b, double t) => (
  a.$1 + (b.$1 - a.$1) * t,
  a.$2 + (b.$2 - a.$2) * t,
  a.$3 + (b.$3 - a.$3) * t,
);

Rgb times(Rgb a, double k) => (a.$1 * k, a.$2 * k, a.$3 * k);

/// The ground's heights, in metres, a pixel each.
Float32List heights(String tileDir) {
  final decoded = <(int, int), img.Image>{
    for (final (z, x, y) in tiles())
      (x, y): img.decodePng(
        File('$tileDir/${z}_${x}_$y.png').readAsBytesSync(),
      )!,
  };
  double raw(int x, int y) {
    final p = decoded[(x >> 8, y >> 8)]!.getPixel(x & 255, y & 255);
    return p.r * 256 + p.g + p.b / 256 - 32768;
  }

  final h = Float32List(width * height);
  for (var y = 0; y < height; y++) {
    final lat = north - (y + .5) / perDegree;
    final ty = _tileY(lat) * 256 - .5;
    for (var x = 0; x < width; x++) {
      final lon = west + (x + .5) / (xScale * perDegree);
      final tx = _tileX(lon) * 256 - .5;
      final x0 = tx.floor(), y0 = ty.floor();
      final fx = tx - x0, fy = ty - y0;
      final top = raw(x0, y0) * (1 - fx) + raw(x0 + 1, y0) * fx;
      final bottom = raw(x0, y0 + 1) * (1 - fx) + raw(x0 + 1, y0 + 1) * fx;
      h[y * width + x] = top * (1 - fy) + bottom * fy;
    }
  }
  return h;
}

/// Box-blurs [h] [times] times with a radius of [r] pixels.
void smooth(Float32List h, int r, int times) {
  final t = Float32List(width * height);
  for (var n = 0; n < times; n++) {
    for (var y = 0; y < height; y++) {
      var sum = 0.0;
      for (var x = -r; x <= r; x++) {
        sum += h[y * width + x.clamp(0, width - 1)];
      }
      for (var x = 0; x < width; x++) {
        t[y * width + x] = sum / (2 * r + 1);
        sum +=
            h[y * width + (x + r + 1).clamp(0, width - 1)] -
            h[y * width + (x - r).clamp(0, width - 1)];
      }
    }
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      for (var y = -r; y <= r; y++) {
        sum += t[y.clamp(0, height - 1) * width + x];
      }
      for (var y = 0; y < height; y++) {
        h[y * width + x] = sum / (2 * r + 1);
        sum +=
            t[(y + r + 1).clamp(0, height - 1) * width + x] -
            t[(y - r).clamp(0, height - 1) * width + x];
      }
    }
  }
}

void main(List<String> args) {
  if (args.length == 1 && args[0] == '--tiles') {
    for (final (z, x, y) in tiles()) {
      stdout.writeln('$z/$x/$y');
    }
    return;
  }
  if (args.length != 2) {
    stderr.writeln(
      'usage: build_jerusalem_image.dart --tiles | <tile-dir> <out.jpg>',
    );
    exit(64);
  }
  final random = math.Random(30);
  double jitter(double by) => (random.nextDouble() * 2 - 1) * by;

  final firstWall = pts(feature('First Wall').points);
  final secondWall = pts(feature('Second Wall').points);
  final precinct = pts(feature('Temple precinct').points);
  final sanctuary = pts(feature('Sanctuary').points);
  final womensCourt = pts(feature('Court of Women').points);
  final royal = pts(feature('Royal portico').points);
  final solomons = pts(feature('Solomon').points);
  final antonia = pts(feature('Antonia').points);
  final palace = pts(feature('Herod').points);
  final bethesda = pts(feature('Bethesda').points);
  final siloam = pts(feature('Pool of Siloam').points);
  final kidron = pts(feature('Kidron valley').points);
  final tyropoeon = pts(feature('Tyropoeon').points);
  final hinnom = pts(feature('Hinnom').points);
  final pilgrims = pts(feature('Pilgrims').points);
  final aqueduct = pts(feature('Lower aqueduct').points);
  final wilson = pts(feature('Wilson').points);
  final kidronBridge = pts(feature('Kidron bridge').points);
  P at(String prefix) {
    final f = feature(prefix);
    return px(f.at.$1, f.at.$2);
  }

  // The Second Wall's quarter: within it, the First Wall's north side and
  // the Temple's west side.
  final secondQuarter = [
    ...secondWall,
    px(35.2343, 31.7790),
    px(35.2337, 31.7767),
    px(35.2300, 31.7766),
  ];

  // The ground.
  final h = heights(args[0]);
  smooth(h, 3, 3);
  final platform = mask(precinct);
  var platformHeight = 0.0, platformCount = 0;
  for (var i = 0; i < h.length; i++) {
    if (platform[i] >= 1) {
      platformHeight += h[i];
      platformCount++;
    }
  }
  platformHeight /= platformCount;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final q = (x + .5, y + .5);
      // The Tyropoeon lies under 10 m and more of later fill.
      final d = polylineDistance(q, tyropoeon) * metresPerPixel;
      if (q.$2 < px(0, 31.7700).$2) h[i] -= 11 * math.exp(-math.pow(d / 32, 2));
      h[i] += (platformHeight - h[i]) * platform[i];
    }
  }
  var lowest = double.infinity, highest = -double.infinity;
  for (final v in h) {
    lowest = math.min(lowest, v);
    highest = math.max(highest, v);
  }
  stdout.writeln('Heights ${lowest.round()} to ${highest.round()} m');

  final picture = Picture();
  final slope = Float32List(width * height);
  final shade = Float32List(width * height);
  const altitude = 40 * math.pi / 180;
  final light = (
    -math.cos(altitude) * math.sqrt1_2,
    math.cos(altitude) * math.sqrt1_2,
    math.sin(altitude),
  );
  const Rgb low = (150, 146, 104), high = (214, 199, 160);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      double hh(int x, int y) =>
          h[y.clamp(0, height - 1) * width + x.clamp(0, width - 1)];
      final dEast = (hh(x + 1, y) - hh(x - 1, y)) / (2 * metresPerPixel) * 1.4;
      final dNorth = (hh(x, y - 1) - hh(x, y + 1)) / (2 * metresPerPixel) * 1.4;
      final n = math.sqrt(dEast * dEast + dNorth * dNorth + 1);
      final lit =
          (-dEast * light.$1 - dNorth * light.$2 + light.$3) / n / light.$3;
      slope[i] = math.sqrt(dEast * dEast + dNorth * dNorth) / 1.4;
      shade[i] = (1 + (lit - 1) * .75).clamp(.6, 1.25);
      final t = ((h[i] - lowest) / (highest - lowest)).clamp(0.0, 1.0);
      var c = mix(low, high, math.pow(t, .8).toDouble());
      // Terraces stepping the slopes outside the walls.
      final step = (h[i] / 2.6).floor();
      if (slope[i] > .06 &&
          slope[i] < .7 &&
          platform[i] == 0 &&
          ((hh(x + 1, y) / 2.6).floor() != step ||
              (hh(x, y + 1) / 2.6).floor() != step)) {
        c = times(c, .86);
      }
      c = times(c, shade[i]);
      picture.r[i] = c.$1;
      picture.g[i] = c.$2;
      picture.b[i] = c.$3;
    }
  }

  // The walled city, and what houses keep clear of.
  final city = mask(firstWall);
  final second = mask(secondQuarter);
  for (var i = 0; i < city.length; i++) {
    city[i] = math.max(city[i], second[i]);
  }
  final blocked = Float32List(width * height);
  void block(Float32List m) {
    for (var i = 0; i < m.length; i++) {
      blocked[i] = math.max(blocked[i], m[i]);
    }
  }

  List<P> grow(List<P> p, double by) {
    var cx = 0.0, cy = 0.0;
    for (final q in p) {
      cx += q.$1;
      cy += q.$2;
    }
    cx /= p.length;
    cy /= p.length;
    return [
      for (final q in p)
        (q.$1 + by * (q.$1 - cx).sign, q.$2 + by * (q.$2 - cy).sign),
    ];
  }

  block(mask(grow(precinct, 6)));
  block(mask(grow(antonia, 4)));
  block(mask(grow(palace, 4)));
  block(mask(grow(bethesda, 4)));
  block(mask(grow(siloam, 5)));
  block(strokeMask(pilgrims, 12));
  block(strokeMask(firstWall, 12));
  block(strokeMask(secondWall, 12));
  block(strokeMask(wilson, 8));
  // The street from the palace along the First Wall's north side to the
  // Temple, and the Upper City's street down to Siloam.
  final northStreet = [px(35.2291, 31.7762), px(35.2337, 31.7763)];
  final cardo = [
    px(35.2300, 31.7764),
    px(35.2310, 31.7730),
    px(35.2335, 31.7708),
  ];
  block(strokeMask(northStreet, 7));
  block(strokeMask(cardo, 6));

  // Ways out of the city, worn into the ground.
  const Rgb dust = (206, 188, 146);
  for (final way in [
    // Over the Kidron bridge and the Mount of Olives to Bethany.
    [
      px(35.2403, 31.7789),
      px(35.2420, 31.7795),
      px(35.2440, 31.7792),
      px(35.2470, 31.7788),
    ],
    // Down the Kidron to Jericho and the wilderness.
    [
      px(35.2362, 31.7700),
      px(35.2372, 31.7720),
      px(35.2386, 31.7750),
      px(35.2395, 31.7778),
      px(35.2412, 31.7780),
      px(35.2470, 31.7770),
    ],
    // South towards Bethlehem and Hebron.
    [
      px(35.2350, 31.7699),
      px(35.2330, 31.7690),
      px(35.2290, 31.7686),
      px(35.2262, 31.7680),
    ],
    // West to Joppa, from the gate by the palace.
    [px(35.2270, 31.7768), px(35.2252, 31.7772), px(35.2240, 31.7778)],
    // North to Samaria and Galilee.
    [px(35.2316, 31.7809), px(35.2312, 31.7822), px(35.2308, 31.7840)],
  ]) {
    picture.line(way, 3.5, dust, .75);
    block(strokeMask(way, 6));
  }

  // Golgotha's quarry and garden, outside the Second Wall.
  final golgotha = at('Golgotha');
  final quarry = [
    for (var k = 0; k < 14; k++)
      (
        golgotha.$1 + math.cos(k / 14 * 2 * math.pi) * (22 + jitter(5)),
        golgotha.$2 + math.sin(k / 14 * 2 * math.pi) * (16 + jitter(4)),
      ),
  ];
  picture.poly(quarry, (222, 214, 196), .8);
  for (var k = 0; k < 9; k++) {
    final a = random.nextDouble() * 2 * math.pi;
    picture.line(
      [
        (golgotha.$1 + math.cos(a) * 4, golgotha.$2 + math.sin(a) * 3),
        (golgotha.$1 + math.cos(a) * 18, golgotha.$2 + math.sin(a) * 13),
      ],
      .8,
      (150, 140, 120),
      .5,
    );
  }

  // Rock-cut tombs on the slopes facing the city.
  void tomb(P q) {
    picture.poly(
      [
        (q.$1 - 1.5, q.$2 - 1),
        (q.$1 + 1.5, q.$2 - 1),
        (q.$1 + 1.5, q.$2 + 1),
        (q.$1 - 1.5, q.$2 + 1),
      ],
      (70, 60, 48),
      .7,
    );
  }

  for (var k = 0; k < 60; k++) {
    final lat = 31.7735 + random.nextDouble() * .0050;
    tomb(px(35.2393 + random.nextDouble() * .0018, lat));
  }
  for (var k = 0; k < 40; k++) {
    final lon = 35.2280 + random.nextDouble() * .0070;
    tomb(px(lon, 31.7683 + random.nextDouble() * .0007));
  }
  for (var k = 0; k < 8; k++) {
    tomb((golgotha.$1 + 24 + jitter(8), golgotha.$2 + jitter(14)));
  }
  // The monumental tombs of the Kidron.
  for (final q in [
    px(35.2385, 31.7764),
    px(35.2386, 31.7758),
    px(35.2387, 31.7753),
  ]) {
    picture.shadow([
      (q.$1 - 4, q.$2 - 4),
      (q.$1 + 4, q.$2 - 4),
      (q.$1 + 4, q.$2 + 4),
      (q.$1 - 4, q.$2 + 4),
    ], 4);
    picture.poly(
      [
        (q.$1 - 4, q.$2 - 4),
        (q.$1 + 4, q.$2 - 4),
        (q.$1 + 4, q.$2 + 4),
        (q.$1 - 4, q.$2 + 4),
      ],
      (214, 200, 170),
    );
    picture.disc(q.$1, q.$2, 2.4, (190, 176, 146));
  }

  // Olive groves and gardens: thick on the Mount of Olives and in the
  // valleys' gardens, thin on the bare western slopes.
  final gethsemane = at('Gethsemane');
  final kingsGarden = px(35.2362, 31.7693);
  final trees = <P>[];
  for (var y = 4.0; y < height; y += 8) {
    for (var x = 4.0; x < width; x += 8) {
      final q = (x + jitter(3), y + jitter(3));
      final i =
          q.$2.clamp(0, height - 1).toInt() * width +
          q.$1.clamp(0, width - 1).toInt();
      if (city[i] > 0 || blocked[i] > 0 || slope[i] > .9) continue;
      final olives = q.$1 > px(35.2392, 0).$1 ? .45 : .09;
      final valley = math.min(
        polylineDistance(q, kidron),
        polylineDistance(q, hinnom),
      );
      var chance = olives + (valley < 20 ? .2 : 0);
      for (final (garden, reach) in [(gethsemane, 45.0), (kingsGarden, 40.0)]) {
        final d = math.sqrt(
          math.pow(q.$1 - garden.$1, 2) + math.pow(q.$2 - garden.$2, 2),
        );
        if (d < reach) chance = .8;
      }
      if (polylineDistance(q, quarry) < 24 && (q.$1 - golgotha.$1).abs() < 40) {
        chance = .35;
      }
      if (random.nextDouble() < chance) trees.add(q);
    }
  }
  for (final (x, y) in trees) {
    picture.disc(x + 1.8, y + 1.8, 2.6, ink, .3);
  }
  for (final (x, y) in trees) {
    final r = 2.2 + random.nextDouble() * .8;
    picture.disc(x, y, r, (98 + jitter(8), 108 + jitter(8), 70 + jitter(6)));
    picture.disc(x - .7, y - .7, r * .45, (138, 146, 102), .6);
  }

  // The city's lanes and yards, then its houses, block by block.
  const Rgb lane = (186, 172, 142);
  for (var i = 0; i < city.length; i++) {
    final c = times(lane, .78 + .22 * shade[i]);
    picture.blend(i % width, i ~/ width, c, city[i] * .9);
  }
  final roofs = <Rgb>[
    (222, 209, 182),
    (210, 196, 166),
    (230, 221, 200),
    (200, 184, 154),
    (238, 233, 220),
    (214, 198, 172),
  ];
  bool clear(List<P> corners) {
    for (final q in corners) {
      final x = q.$1.round(), y = q.$2.round();
      if (x < 0 || y < 0 || x >= width || y >= height) return false;
      final i = y * width + x;
      if (city[i] < .9 || blocked[i] > 0) return false;
    }
    return true;
  }

  final houses = <(List<P>, Rgb, List<P>?)>[];
  void district(
    bool Function(P) within,
    double angle,
    double blockSize,
    int split, {
    double courtyards = .2,
    double gardens = 0,
  }) {
    final ca = math.cos(angle), sa = math.sin(angle);
    P turn(double u, double v) => (u * ca - v * sa, u * sa + v * ca);
    final reach = math.sqrt(width * width + height * height.toDouble());
    for (var v = -reach; v < reach; v += blockSize) {
      for (var u = -reach; u < reach; u += blockSize) {
        final centre = turn(u + blockSize / 2, v + blockSize / 2);
        if (centre.$1 < -blockSize || centre.$2 < -blockSize) continue;
        if (centre.$1 > width + blockSize || centre.$2 > height + blockSize) {
          continue;
        }
        if (!within(centre)) continue;
        // A block, less its lanes, cut into houses.
        final lots = <(double, double, double, double)>[
          (u + 1.6, v + 1.6, u + blockSize - 1.6, v + blockSize - 1.6),
        ];
        for (var n = 0; n < split; n++) {
          final lot = lots.removeAt(random.nextInt(lots.length));
          final (a, b, c, d) = lot;
          final t = .35 + random.nextDouble() * .3;
          if (c - a > d - b) {
            final m = a + (c - a) * t;
            lots.addAll([(a, b, m - .5, d), (m + .5, b, c, d)]);
          } else {
            final m = b + (d - b) * t;
            lots.addAll([(a, b, c, m - .5), (a, m + .5, c, d)]);
          }
        }
        for (final (a, b, c, d) in lots) {
          if (c - a < 3 || d - b < 3 || random.nextDouble() < .06) continue;
          final corners = [turn(a, b), turn(c, b), turn(c, d), turn(a, d)];
          if (!clear([...corners, turn((a + c) / 2, (b + d) / 2)])) continue;
          List<P>? yard;
          if (c - a > 10 && d - b > 10 && random.nextDouble() < courtyards) {
            final w = (c - a) * .38, hgt = (d - b) * .38;
            final mu = (a + c) / 2, mv = (b + d) / 2;
            yard = [
              turn(mu - w / 2, mv - hgt / 2),
              turn(mu + w / 2, mv - hgt / 2),
              turn(mu + w / 2, mv + hgt / 2),
              turn(mu - w / 2, mv + hgt / 2),
            ];
          }
          final roof = roofs[random.nextInt(roofs.length)];
          houses.add((
            corners,
            mix(roof, (255, 250, 240), jitter(.06).abs()),
            yard,
          ));
          if (yard != null && random.nextDouble() < gardens) {
            houses.add((yard, (112, 124, 80), null));
          }
        }
      }
    }
  }

  final tyropoeonX = px(35.2336, 0).$1;
  district(
    (q) => q.$1 < tyropoeonX - 6 && q.$2 > px(0, 31.7766).$2,
    .05,
    30,
    3,
    courtyards: .7,
    gardens: .35,
  );
  district(
    (q) => q.$1 >= tyropoeonX - 6 && q.$2 > px(0, 31.7766).$2,
    -.32,
    22,
    4,
    courtyards: .15,
  );
  district((q) => q.$2 <= px(0, 31.7766).$2, .12, 24, 4, courtyards: .3);
  for (final (corners, _, _) in houses) {
    if (corners.length == 4) picture.shadow(corners, 1.8, .33);
  }
  for (final (corners, roof, yard) in houses) {
    final q = corners.first;
    final i =
        q.$2.round().clamp(0, height - 1) * width +
        q.$1.round().clamp(0, width - 1);
    picture.poly(corners, times(roof, .9 + .1 * shade[i]));
    if (yard != null) {
      picture.poly(yard, (176, 162, 132));
      picture.line([yard[0], yard[1]], .8, ink, .25);
      picture.line([yard[3], yard[0]], .8, ink, .25);
    }
  }

  // Herod's palace: two wings about gardens and pools, and its three towers.
  picture.shadow(palace, 4, .4);
  picture.poly(palace, (226, 216, 196));
  final (pw, pn) = palace[3];
  final (pe, ps) = palace[1];
  final palaceWidth = pe - pw;
  for (final (top, bottom) in [
    (pn + 4, pn + (ps - pn) * .42),
    (pn + (ps - pn) * .58, ps - 4),
  ]) {
    final court = [
      (pw + palaceWidth * .28, top + 4),
      (pe - palaceWidth * .28, top + 4),
      (pe - palaceWidth * .28, bottom - 4),
      (pw + palaceWidth * .28, bottom - 4),
    ];
    picture.poly(court, (118, 132, 84));
    final (cx, cy) = ((pw + pe) / 2, (top + bottom) / 2);
    picture.poly(
      [(cx - 4, cy - 2), (cx + 4, cy - 2), (cx + 4, cy + 2), (cx - 4, cy + 2)],
      (76, 128, 146),
    );
    for (var k = 0; k < 40; k++) {
      picture.disc(
        court[0].$1 + 3 + random.nextDouble() * (court[1].$1 - court[0].$1 - 6),
        court[0].$2 + 3 + random.nextDouble() * (court[2].$2 - court[0].$2 - 6),
        2,
        (84, 104, 62),
      );
    }
  }
  picture.line([...palace, palace.first], 2.2, (178, 164, 134));
  for (var k = 0; k < 3; k++) {
    final x = pw + 6 + k * (palaceWidth - 12) / 2, y = pn + 2;
    final tower = [
      (x - 6, y - 6),
      (x + 6, y - 6),
      (x + 6, y + 6),
      (x - 6, y + 6),
    ];
    picture.shadow(tower, 6, .45);
    picture.poly(tower, (232, 222, 200));
    picture.line([...tower, tower.first], 1, ink, .35);
  }

  // Antonia: a fortress of four towers about a courtyard.
  picture.shadow(antonia, 5, .45);
  picture.poly(antonia, (214, 202, 176));
  final (aw, an) = antonia[3];
  final (ae, aS) = antonia[1];
  picture.poly(
    [(aw + 6, an + 6), (ae - 6, an + 6), (ae - 6, aS - 6), (aw + 6, aS - 6)],
    (182, 168, 138),
  );
  for (final (x, y, s) in [
    (aw, an, 6.0),
    (ae, an, 6.0),
    (aw, aS, 6.0),
    (ae, aS, 9.0),
  ]) {
    final tower = [
      (x - s, y - s),
      (x + s, y - s),
      (x + s, y + s),
      (x - s, y + s),
    ];
    picture.shadow(tower, s, .45);
    picture.poly(tower, (226, 214, 190));
    picture.line([...tower, tower.first], 1, ink, .35);
  }

  // The Temple platform, its walls standing above the valleys.
  picture.shadow(precinct, 9, .5);
  picture.poly(precinct, (228, 219, 196));
  var (tx0, ty0, tx1, ty1) = (
    double.infinity,
    double.infinity,
    -double.infinity,
    -double.infinity,
  );
  for (final q in precinct) {
    tx0 = math.min(tx0, q.$1);
    ty0 = math.min(ty0, q.$2);
    tx1 = math.max(tx1, q.$1);
    ty1 = math.max(ty1, q.$2);
  }
  // Flagstones.
  for (var y = ty0.floor(); y <= ty1; y += 5) {
    for (var x = tx0.floor(); x <= tx1; x++) {
      if (platform[y * width + x] >= 1) picture.blend(x, y, ink, .06);
    }
  }
  for (var x = tx0.floor(); x <= tx1; x += 7) {
    for (var y = ty0.floor(); y <= ty1; y++) {
      if (platform[y * width + x] >= 1) picture.blend(x, y, ink, .05);
    }
  }
  // Porticoes round the court: the Royal Stoa's roof on the south, Solomon's
  // on the east, and single rows west and north.
  const Rgb cedar = (178, 152, 120);
  void portico(List<P> a, double w) {
    picture.line(a, w + 2, ink, .25);
    picture.line(a, w, cedar);
    picture.line(a, 1, (120, 88, 60), .7);
  }

  final (nw, ne, se, sw) = (precinct[3], precinct[2], precinct[1], precinct[0]);
  P inward(P q, double dx, double dy) => (q.$1 + dx, q.$2 + dy);
  portico([inward(nw, 6, 6), inward(sw, 6, -14)], 9);
  portico([inward(nw, 6, 6), inward(ne, -6, 6)], 9);
  picture.shadow(royal, 3, .3);
  picture.poly(royal, cedar);
  picture.line([royal[0], royal[1]], 1, (120, 88, 60), .7);
  picture.line(
    [
      ((royal[0].$1 + royal[3].$1) / 2, (royal[0].$2 + royal[3].$2) / 2),
      ((royal[1].$1 + royal[2].$1) / 2, (royal[1].$2 + royal[2].$2) / 2),
    ],
    1.2,
    (120, 88, 60),
    .8,
  );
  picture.shadow(solomons, 3, .3);
  picture.poly(solomons, cedar);
  picture.line([...precinct], 3, (176, 162, 132));
  // The Huldah gates' stair, up from the Lower City.
  final huldah = px(35.2355, 31.7757);
  for (var k = 0; k < 6; k++) {
    picture.line(
      [
        (huldah.$1 - 26, huldah.$2 + 2 + k * 1.6),
        (huldah.$1 + 26, huldah.$2 + 2 + k * 1.6),
      ],
      .9,
      k.isEven ? (236, 228, 208) : (190, 176, 146),
    );
  }

  // The inner courts, raised within the soreg's low fence.
  var (ix0, iy0, ix1, iy1) = (
    double.infinity,
    double.infinity,
    -double.infinity,
    -double.infinity,
  );
  for (final q in [...sanctuary, ...womensCourt]) {
    ix0 = math.min(ix0, q.$1);
    iy0 = math.min(iy0, q.$2);
    ix1 = math.max(ix1, q.$1);
    iy1 = math.max(iy1, q.$2);
  }
  final soreg = [
    (ix0 - 9, iy0 - 9),
    (ix1 + 9, iy0 - 9),
    (ix1 + 9, iy1 + 9),
    (ix0 - 9, iy1 + 9),
  ];
  picture.line([...soreg, soreg.first], 1, (150, 136, 108), .6);
  picture.shadow(sanctuary, 4, .4);
  picture.shadow(womensCourt, 3, .35);
  picture.poly(sanctuary, (238, 233, 220));
  picture.poly(womensCourt, (232, 225, 208));
  picture.line([...sanctuary], 2.4, (205, 192, 162));
  picture.line([...womensCourt], 2.4, (205, 192, 162));
  // The court of women's four corner chambers.
  final (wx0, wy0, wx1, wy1) = (
    womensCourt[0].$1,
    womensCourt[2].$2,
    womensCourt[1].$1,
    womensCourt[0].$2,
  );
  for (final (x, y) in [
    (wx0 + 4, wy0 + 4),
    (wx1 - 4, wy0 + 4),
    (wx0 + 4, wy1 - 4),
    (wx1 - 4, wy1 - 4),
  ]) {
    picture.poly(
      [(x - 3, y - 3), (x + 3, y - 3), (x + 3, y + 3), (x - 3, y + 3)],
      (210, 196, 166),
    );
  }
  // The sanctuary, facing east, its porch wider than the house; then the
  // altar before it.
  final (sx0, sy0, sx1, sy1) = (
    sanctuary[0].$1,
    sanctuary[2].$2,
    sanctuary[1].$1,
    sanctuary[0].$2,
  );
  final sw2 = sx1 - sx0, sh = sy1 - sy0, scy = (sy0 + sy1) / 2;
  final house = [
    (sx0 + sw2 * .1, scy - sh * .16),
    (sx0 + sw2 * .5, scy - sh * .16),
    (sx0 + sw2 * .5, scy - sh * .26),
    (sx0 + sw2 * .6, scy - sh * .26),
    (sx0 + sw2 * .6, scy + sh * .26),
    (sx0 + sw2 * .5, scy + sh * .26),
    (sx0 + sw2 * .5, scy + sh * .16),
    (sx0 + sw2 * .1, scy + sh * .16),
  ];
  picture.shadow(house, 7, .5);
  picture.poly(house, (250, 247, 238));
  picture.line([...house, house.first], 1, (196, 160, 72), .9);
  picture.line(
    [(sx0 + sw2 * .12, scy), (sx0 + sw2 * .58, scy)],
    1.4,
    (212, 172, 72),
  );
  final altar = (sx0 + sw2 * .8, scy);
  final altarShape = [
    (altar.$1 - 5, altar.$2 - 5),
    (altar.$1 + 5, altar.$2 - 5),
    (altar.$1 + 5, altar.$2 + 5),
    (altar.$1 - 5, altar.$2 + 5),
  ];
  picture.shadow(altarShape, 2.5, .4);
  picture.poly(altarShape, (196, 184, 160));
  picture.disc(altar.$1, altar.$2, 2.2, (120, 80, 50), .8);
  picture.line(
    [(altar.$1 + 5, altar.$2 + 1), (altar.$1 + 12, altar.$2 + 1)],
    2,
    (190, 178, 152),
  );

  // Pools: Bethesda's twin basins with porticoes, and the Siloam pool's
  // flights of steps down to the water.
  picture.shadow(bethesda, 2, .3);
  picture.poly(bethesda, cedar);
  final (bx0, by0, bx1, by1) = (
    bethesda[0].$1,
    bethesda[2].$2,
    bethesda[1].$1,
    bethesda[0].$2,
  );
  final bm = (by0 + by1) / 2;
  picture.poly(
    [
      (bx0 + 3, by0 + 3),
      (bx1 - 3, by0 + 3),
      (bx1 - 3, bm - 1.5),
      (bx0 + 3, bm - 1.5),
    ],
    (72, 124, 140),
  );
  picture.poly(
    [
      (bx0 + 3, bm + 1.5),
      (bx1 - 3, bm + 1.5),
      (bx1 - 3, by1 - 3),
      (bx0 + 3, by1 - 3),
    ],
    (72, 124, 140),
  );
  final (lx0, ly0, lx1, ly1) = (
    siloam[0].$1,
    siloam[2].$2,
    siloam[1].$1,
    siloam[0].$2,
  );
  for (var k = 0; k < 6; k++) {
    final s = k * 1.6;
    picture.poly([
      (lx0 + s, ly0 + s),
      (lx1 - s, ly0 + s),
      (lx1 - s, ly1 - s),
      (lx0 + s, ly1 - s),
    ], k.isEven ? (230, 222, 202) : (186, 172, 144));
  }
  picture.poly(
    [
      (lx0 + 10, ly0 + 10),
      (lx1 - 10, ly0 + 10),
      (lx1 - 10, ly1 - 10),
      (lx0 + 10, ly1 - 10),
    ],
    (64, 122, 140),
  );

  // The pilgrims' road: a paved street stepping up from Siloam to the
  // Temple, between shops.
  picture.line(pilgrims, 9, ink, .25);
  picture.line(pilgrims, 7, (218, 208, 184));
  for (var i = 0; i + 1 < pilgrims.length; i++) {
    final (a, b) = (pilgrims[i], pilgrims[i + 1]);
    final l = math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));
    final (ux, uy) = ((b.$1 - a.$1) / l, (b.$2 - a.$2) / l);
    for (var d = 0.0; d < l; d += 3.2) {
      final (cx, cy) = (a.$1 + ux * d, a.$2 + uy * d);
      picture.line(
        [(cx - uy * 3.4, cy + ux * 3.4), (cx + uy * 3.4, cy - ux * 3.4)],
        .6,
        ink,
        .28,
      );
    }
  }
  // Robinson's Arch: the stair from the street up onto the platform.
  final robinson = pilgrims.last;
  final arch = [
    (robinson.$1 - 3, robinson.$2 - 1),
    (robinson.$1 + 7, robinson.$2 - 1),
    (robinson.$1 + 7, robinson.$2 + 6),
    (robinson.$1 - 3, robinson.$2 + 6),
  ];
  picture.shadow(arch, 4, .45);
  picture.poly(arch, (222, 212, 188));

  // The lower aqueduct, a covered channel, and Wilson's Arch carrying it
  // and a street over the Tyropoeon.
  picture.line(aqueduct, 3.2, (176, 164, 136));
  picture.line(aqueduct, 1.2, (96, 116, 120), .8);
  picture.line([for (final q in wilson) (q.$1 + 5, q.$2 + 5)], 8, ink, .45);
  picture.line(wilson, 8, (214, 202, 176));
  picture.line(wilson, 1, ink, .25);

  // The walls, with towers along them.
  void wall(List<P> p) {
    picture.line([for (final q in p) (q.$1 + 2.5, q.$2 + 2.5)], 6, ink, .4);
    picture.line(p, 5.5, (190, 176, 146));
    picture.line(p, 1, (226, 216, 194), .6);
    var carried = 0.0;
    for (var i = 0; i + 1 < p.length; i++) {
      final (a, b) = (p[i], p[i + 1]);
      final l = math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));
      for (var d = carried; d < l; d += 30) {
        final (x, y) = (
          a.$1 + (b.$1 - a.$1) * d / l,
          a.$2 + (b.$2 - a.$2) * d / l,
        );
        final tower = [
          (x - 4.5, y - 4.5),
          (x + 4.5, y - 4.5),
          (x + 4.5, y + 4.5),
          (x - 4.5, y + 4.5),
        ];
        picture.shadow(tower, 3.5, .4);
        picture.poly(tower, (204, 190, 160));
        picture.line([...tower, tower.first], .8, ink, .3);
        carried = d + 30 - l;
      }
    }
  }

  wall(firstWall);
  wall(secondWall);

  // The causeway on arches from the Temple's east gate over the Kidron.
  final bridge = kidronBridge;
  picture.line([for (final q in bridge) (q.$1 + 7, q.$2 + 7)], 7, ink, .4);
  final (ka, kb) = (bridge.first, bridge.last);
  final kl = math.sqrt(math.pow(kb.$1 - ka.$1, 2) + math.pow(kb.$2 - ka.$2, 2));
  for (var d = 6.0; d < kl - 4; d += 9) {
    final (x, y) = (
      ka.$1 + (kb.$1 - ka.$1) * d / kl + 4,
      ka.$2 + (kb.$2 - ka.$2) * d / kl + 6,
    );
    picture.poly(
      [(x - 1.5, y - 2), (x + 1.5, y - 2), (x + 1.5, y + 2), (x - 1.5, y + 2)],
      (150, 136, 108),
    );
  }
  picture.line(bridge, 6, (212, 200, 172));
  picture.line(bridge, 1, ink, .2);

  final out = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      out.setPixelRgb(
        x,
        y,
        picture.r[i].round().clamp(0, 255),
        picture.g[i].round().clamp(0, 255),
        picture.b[i].round().clamp(0, 255),
      );
    }
  }
  File(args[1]).writeAsBytesSync(img.encodeJpg(out, quality: 84));
  stdout.writeln('Wrote ${args[1]}, ${width}x$height');
}
