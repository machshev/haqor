// Build the hills and valleys the place maps shade over the land, from the
// Terrarium elevation tiles of the Terrain Tiles open dataset (SRTM and
// others; registry.opendata.aws), into assets/map/relief/.
//
// The relief is a pyramid of [layers]: a coarse one over all the lands of the
// Bible, a finer one over the Levant, and finer still over the key places,
// the hills of Israel and Midian and then Jerusalem, Shechem, Galilee and
// Jabal al-Lawz. The app draws each over the one below as the map zooms in.
//
// Each layer is a grid over its box, square on screen at the maps' reference
// latitude. Each pixel holds, in red, the light a slope catches from the
// north-west (128 is level ground's) and, in green, its height on the layer's
// scale of lowest to highest metres. The app colours it for the theme.
// relief.json lists the layers.
//
//   tool/fetch-basemap.sh    # downloads the tiles and runs this
//
// Usage: dart run tool/build_relief.dart --tiles
//        dart run tool/build_relief.dart <tile-dir> <out-dir>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class Layer {
  const Layer(
    this.name, {
    required this.box,
    required this.perDegree,
    required this.zoom,
    required this.exaggeration,
    required this.fade,
    this.minScale = 0,
    this.highest = 2850,
    this.seams = const [],
  });

  final String name;

  /// [west, south, east, north] in degrees.
  final List<double> box;

  /// Pixels per degree of latitude; longitude has fewer, by the cosine of the
  /// maps' reference latitude.
  final double perDegree;

  /// The Terrarium zoom read: a tile pixel as fine as the layer's, or a
  /// little finer.
  final int zoom;

  /// Slopes are drawn this many times steeper, so hills read at the layer's
  /// scale; the finer the layer, the less they need it.
  final double exaggeration;

  /// The degrees over which the layer fades out at its edges, into the one
  /// below without a seam.
  final double fade;

  /// The map scale, logical pixels to a degree of latitude, from which the
  /// app draws the layer: about where the layer below runs out of pixels.
  final double minScale;

  /// The heights the green channel spans, in metres: the Dead Sea to Hermon,
  /// or to Ararat for the whole.
  final double highest;
  double get lowest => -450;

  /// Bands of latitude, [south, north], where the tiles read are wrong, their
  /// heights drawn across from the good rows either side.
  final List<List<double>> seams;
}

const layers = [
  // Spain to Persia, Anatolia to Ethiopia, about 5 km a pixel.
  Layer(
    'overview',
    box: [-12, 4, 64, 48],
    perDegree: 24,
    zoom: 6,
    exaggeration: 6,
    fade: 2,
    highest: 5200,
  ),
  // Israel, Lebanon, Transjordan, Sinai and Midian, about 500 m a pixel.
  Layer(
    'levant',
    box: [32.4, 27.2, 38.8, 35.4],
    perDegree: 220,
    zoom: 9,
    exaggeration: 2.5,
    fade: .8,
    seams: arabahSeams,
  ),
  // The hills of Israel from Beersheba to Hermon, the Jordan valley, the
  // Dead Sea and the edge of the Transjordan plateau, about 140 m a pixel.
  Layer(
    'israel',
    box: [34.55, 30.85, 36.05, 33.45],
    perDegree: 800,
    zoom: 11,
    exaggeration: 1.7,
    fade: .15,
    minScale: 110,
  ),
  // The crossing at Nuweiba, Elim, Rephidim and Jabal al-Lawz.
  Layer(
    'midian',
    box: [34.4, 28.3, 35.6, 29.15],
    perDegree: 800,
    zoom: 11,
    exaggeration: 1.7,
    fade: .15,
    minScale: 110,
  ),
  // About 35 m a pixel: Hebron, Bethlehem, Jerusalem, Bethel, Ai and Jericho.
  Layer(
    'judah',
    box: [35.05, 31.5, 35.48, 31.98],
    perDegree: 3200,
    zoom: 12,
    exaggeration: 1.3,
    fade: .04,
    minScale: 400,
  ),
  // Shechem between Ebal and Gerizim, Samaria, Shiloh and Tirzah.
  Layer(
    'shechem',
    box: [35.12, 32.02, 35.42, 32.34],
    perDegree: 3200,
    zoom: 12,
    exaggeration: 1.3,
    fade: .04,
    minScale: 400,
  ),
  // The Sea of Galilee, Capernaum, Nazareth and Tabor.
  Layer(
    'galilee',
    box: [35.25, 32.64, 35.7, 32.95],
    perDegree: 3200,
    zoom: 12,
    exaggeration: 1.3,
    fade: .04,
    minScale: 400,
  ),
  // Jabal al-Lawz and the split rock at Rephidim.
  Layer(
    'lawz',
    box: [35.1, 28.5, 35.45, 28.85],
    perDegree: 3200,
    zoom: 12,
    exaggeration: 1.3,
    fade: .04,
    minScale: 400,
  ),
];

const referenceLatitude = 32.0;

/// A seam between survey tiles across the Arabah and Jordan's desert at zoom 9,
/// a few hundred metres off in a line of rows; the finer zooms have none.
const arabahSeams = [
  [29.018, 29.038],
];

double get _lonPerDegree => math.cos(referenceLatitude * math.pi / 180);

double _tileX(double lon, int zoom) => (lon + 180) / 360 * (1 << zoom);
double _tileY(double lat, int zoom) {
  final phi = lat * math.pi / 180;
  return (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) /
      2 *
      (1 << zoom);
}

Iterable<(int, int, int)> tiles(Layer layer) sync* {
  final z = layer.zoom, box = layer.box;
  for (var x = _tileX(box[0], z).floor(); x <= _tileX(box[2], z).floor(); x++) {
    for (
      var y = _tileY(box[3], z).floor();
      y <= _tileY(box[1], z).floor();
      y++
    ) {
      yield (z, x, y);
    }
  }
}

void main(List<String> args) {
  if (args.length == 1 && args[0] == '--tiles') {
    final all = {for (final layer in layers) ...tiles(layer)};
    for (final (z, x, y) in all) {
      stdout.writeln('$z/$x/$y');
    }
    return;
  }
  if (args.length != 2) {
    stderr.writeln('usage: build_relief.dart --tiles | <tile-dir> <out-dir>');
    exit(64);
  }
  final out = Directory(args[1])..createSync(recursive: true);
  final manifest = <Map<String, dynamic>>[];
  for (final layer in layers) {
    final file = '${layer.name}.png';
    final (width, rows) = build(layer, args[0], '${out.path}/$file');
    manifest.add({
      'file': file,
      'bounds': layer.box,
      'lowest': layer.lowest,
      'highest': layer.highest,
      'fade': layer.fade,
      'minScale': layer.minScale,
    });
    stdout.writeln('Wrote the ${layer.name} relief, ${width}x$rows');
  }
  File('${out.path}/relief.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'source':
          'Terrain Tiles (Terrarium), registry.opendata.aws: SRTM and other '
          'public elevation data',
      'layers': manifest,
    }),
  );
}

(int, int) build(Layer layer, String tileDir, String path) {
  final zoom = layer.zoom, box = layer.box, perDegree = layer.perDegree;
  final lonPerDegree = perDegree * _lonPerDegree;
  final decoded = <(int, int), img.Image>{
    for (final (z, x, y) in tiles(layer))
      (x, y): img.decodePng(
        File('$tileDir/${z}_${x}_$y.png').readAsBytesSync(),
      )!,
  };

  /// Height in metres at [lon], [lat], bilinear between tile pixels.
  double height(double lon, double lat) {
    final px = _tileX(lon, zoom) * 256 - .5, py = _tileY(lat, zoom) * 256 - .5;
    final x0 = px.floor(), y0 = py.floor();
    double raw(int x, int y) {
      final tile = decoded[(x >> 8, y >> 8)]!;
      final p = tile.getPixel(x & 255, y & 255);
      return p.r * 256 + p.g + p.b / 256 - 32768;
    }

    double at(int x, int y) {
      for (final [south, north] in layer.seams) {
        final top = (_tileY(north, zoom) * 256).floor() - 1;
        final bottom = (_tileY(south, zoom) * 256).ceil() + 1;
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

  final width = ((box[2] - box[0]) * lonPerDegree).round();
  final rows = ((box[3] - box[1]) * perDegree).round();
  // One pixel's margin all round, for the slopes at the edges.
  final grid = List.generate(
    rows + 2,
    (r) => List.generate(
      width + 2,
      (c) => height(
        box[0] + (c - .5) / lonPerDegree,
        box[3] - (r - .5) / perDegree,
      ),
    ),
  );

  // Lambert shading from the north-west, 45° up (Horn's slope).
  const azimuth = 315 * math.pi / 180, altitude = 45 * math.pi / 180;
  final image = img.Image(width: width, height: rows);
  for (var r = 0; r < rows; r++) {
    final lat = box[3] - (r + .5) / perDegree;
    final dx = 111320 * math.cos(lat * math.pi / 180) / lonPerDegree;
    final dy = 111320 / perDegree;
    for (var c = 0; c < width; c++) {
      double z(int i, int j) => grid[r + 1 + j][c + 1 + i];
      // Rise per metre east and north (rows run south).
      final east =
          layer.exaggeration *
          ((z(1, -1) + 2 * z(1, 0) + z(1, 1)) -
              (z(-1, -1) + 2 * z(-1, 0) + z(-1, 1))) /
          (8 * dx);
      final north =
          layer.exaggeration *
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
      final e = (z(0, 0) - layer.lowest) / (layer.highest - layer.lowest);
      image.setPixelRgb(
        c,
        r,
        shade.round().clamp(0, 255),
        (e * 255).round().clamp(0, 255),
        0,
      );
    }
  }
  File(path).writeAsBytesSync(img.encodePng(image, level: 9));
  return (width, rows);
}
