// Build assets/map/relief.png, the hills and valleys the place maps shade over
// the land of Israel and its neighbours, from the Terrarium elevation tiles of
// the Terrain Tiles open dataset (SRTM and others; registry.opendata.aws).
//
// The relief is a grid over [box], square on screen at the maps' reference
// latitude. Each pixel holds, in red, the light a slope catches from the
// north-west (128 is level ground's) and, in green, its height on the scale
// [lowest] to [highest] metres. The app colours it for the theme.
//
//   tool/fetch-basemap.sh    # downloads the tiles and runs this
//
// Usage: dart run tool/build_relief.dart --tiles
//        dart run tool/build_relief.dart <tile-dir> <out.png>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// [west, south, east, north] in degrees: Israel, Lebanon, Transjordan, Sinai
/// and Midian, with a margin of desert and sea for the relief to fade out over.
const box = [32.4, 27.2, 38.8, 35.4];

/// Pixels per degree of latitude; longitude has fewer, by the cosine of the
/// maps' reference latitude.
const perDegree = 220.0;
const referenceLatitude = 32.0;

/// The heights the green channel spans, in metres: the Dead Sea to Hermon.
const lowest = -450.0;
const highest = 2850.0;

/// The Terrarium zoom read: about 300 m a pixel here.
const zoom = 9;

/// Slopes are drawn this many times steeper, so hills read at map scale.
const exaggeration = 2.5;

/// Bands of latitude, [south, north], where the tiles' heights are wrong: a
/// seam between survey tiles across the Arabah and Jordan's desert, a few
/// hundred metres off in a line of rows. Heights there are drawn across from
/// the good rows either side.
const seams = [
  [29.018, 29.038],
];

double get _lonPerDegree =>
    perDegree * math.cos(referenceLatitude * math.pi / 180);

double _tileX(double lon) => (lon + 180) / 360 * (1 << zoom);
double _tileY(double lat) {
  final phi = lat * math.pi / 180;
  return (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) /
      2 *
      (1 << zoom);
}

Iterable<(int, int)> tiles() sync* {
  for (var x = _tileX(box[0]).floor(); x <= _tileX(box[2]).floor(); x++) {
    for (var y = _tileY(box[3]).floor(); y <= _tileY(box[1]).floor(); y++) {
      yield (x, y);
    }
  }
}

void main(List<String> args) {
  if (args.length == 1 && args[0] == '--tiles') {
    for (final (x, y) in tiles()) {
      stdout.writeln('$zoom/$x/$y');
    }
    return;
  }
  if (args.length != 2) {
    stderr.writeln('usage: build_relief.dart --tiles | <tile-dir> <out.png>');
    exit(64);
  }
  final decoded = <(int, int), img.Image>{
    for (final (x, y) in tiles())
      (x, y): img.decodePng(
        File('${args[0]}/${zoom}_${x}_$y.png').readAsBytesSync(),
      )!,
  };

  /// Height in metres at [lon], [lat], bilinear between tile pixels.
  double height(double lon, double lat) {
    final px = _tileX(lon) * 256 - .5, py = _tileY(lat) * 256 - .5;
    final x0 = px.floor(), y0 = py.floor();
    double raw(int x, int y) {
      final tile = decoded[(x >> 8, y >> 8)]!;
      final p = tile.getPixel(x & 255, y & 255);
      return p.r * 256 + p.g + p.b / 256 - 32768;
    }

    double at(int x, int y) {
      for (final [south, north] in seams) {
        final top = (_tileY(north) * 256).floor() - 1;
        final bottom = (_tileY(south) * 256).ceil() + 1;
        if (y > top && y < bottom) {
          final t = (y - top) / (bottom - top);
          return raw(x, top) * (1 - t) + raw(x, bottom) * t;
        }
      }
      return raw(x, y);
    }

    final fx = px - x0, fy = py - y0;
    final top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx;
    final bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx;
    return top * (1 - fy) + bottom * fy;
  }

  final width = ((box[2] - box[0]) * _lonPerDegree).round();
  final rows = ((box[3] - box[1]) * perDegree).round();
  // One pixel's margin all round, for the slopes at the edges.
  final grid = List.generate(
    rows + 2,
    (r) => List.generate(
      width + 2,
      (c) => height(
        box[0] + (c - .5) / _lonPerDegree,
        box[3] - (r - .5) / perDegree,
      ),
    ),
  );

  // Lambert shading from the north-west, 45° up (Horn's slope).
  const azimuth = 315 * math.pi / 180, altitude = 45 * math.pi / 180;
  final out = img.Image(width: width, height: rows);
  for (var r = 0; r < rows; r++) {
    final lat = box[3] - (r + .5) / perDegree;
    final dx = 111320 * math.cos(lat * math.pi / 180) / _lonPerDegree;
    const dy = 111320 / perDegree;
    for (var c = 0; c < width; c++) {
      double z(int i, int j) => grid[r + 1 + j][c + 1 + i];
      // Rise per metre east and north (rows run south).
      final east =
          exaggeration *
          ((z(1, -1) + 2 * z(1, 0) + z(1, 1)) -
              (z(-1, -1) + 2 * z(-1, 0) + z(-1, 1))) /
          (8 * dx);
      final north =
          exaggeration *
          ((z(-1, -1) + 2 * z(0, -1) + z(1, -1)) -
              (z(-1, 1) + 2 * z(0, 1) + z(1, 1))) /
          (8 * dy);
      // The cosine between the ground's normal and the light.
      final light =
          (-east * math.cos(altitude) * math.sin(azimuth) -
              north * math.cos(altitude) * math.cos(azimuth) +
              math.sin(altitude)) /
          math.sqrt(east * east + north * north + 1);
      final level = math.sin(altitude);
      // Level ground at 128; full light at 255, none at 0.
      final shade = light >= level
          ? 128 + 127 * (light - level) / (1 - level)
          : 128 * light.clamp(0, 1) / level;
      final e = (z(0, 0) - lowest) / (highest - lowest);
      out.setPixelRgb(
        c,
        r,
        shade.round().clamp(0, 255),
        (e * 255).round().clamp(0, 255),
        0,
      );
    }
  }
  File(args[1])
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(out, level: 9));
  final meta = File(args[1].replaceFirst(RegExp(r'\.png$'), '.json'));
  meta.writeAsStringSync(
    jsonEncode({
      'source':
          'Terrain Tiles (Terrarium, zoom $zoom), registry.opendata.aws: '
          'SRTM and other public elevation data',
      'bounds': box,
      'lowest': lowest,
      'highest': highest,
    }),
  );
  stdout.writeln('Wrote a ${width}x$rows relief to ${args[1]}');
}
