import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The coastlines, lakes, rivers and wadis the place maps draw: Natural
/// Earth's (public domain), clipped to the lands of the Bible, and over Israel
/// and Transjordan OpenStreetMap's as OpenBible.info gathers them (ODbL),
/// bundled so the maps need no network. `tool/fetch-basemap.sh` builds the
/// asset.
class Basemap {
  Basemap._(this.land, this.lakes, this.rivers, this.wadis);

  /// Each shape as longitude, latitude pairs.
  final List<Float64List> land;
  final List<Float64List> lakes;
  final List<Float64List> rivers;

  /// Streams that run only after rain, drawn only close in.
  final List<Float64List> wadis;

  static const asset = 'assets/map/basemap.json';
  static Future<Basemap>? _loading;

  /// The bundled basemap, read once.
  static Future<Basemap> load() =>
      _loading ??= rootBundle.loadString(asset).then(parse);

  static Basemap parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    List<Float64List> shapes(String key) => [
      for (final shape in (data[key] as List<dynamic>? ?? const []))
        Float64List.fromList([
          for (final v in shape as List<dynamic>) (v as num).toDouble(),
        ]),
    ];
    return Basemap._(
      shapes('land'),
      shapes('lakes'),
      shapes('rivers'),
      shapes('wadis'),
    );
  }
}

/// One layer of the hills and valleys shaded and tinted by height over the
/// [Basemap]'s land. The layers make a pyramid: a coarse one over all the
/// lands of the Bible, a finer one over the Levant, and finer ones still over
/// the key places, each read only when the map is zoomed in on it.
/// `tool/build_relief.dart` builds them from SRTM elevations: each pixel's
/// red is the light its slope catches from the north-west, 128 on level
/// ground, and its green its height between [lowest] and [highest] metres.
class Relief {
  Relief._({
    required this.file,
    required this.bounds,
    required this.lowest,
    required this.highest,
    required this.fade,
    required this.minScale,
  });

  final String file;

  /// [west, south, east, north] in degrees.
  final List<double> bounds;
  final double lowest, highest;

  /// The degrees over which it fades out at its edges, so it meets the layer
  /// or the plain land below without a seam.
  final double fade;

  /// The map scale, logical pixels to a degree of latitude, from which it is
  /// read and drawn.
  final double minScale;

  static const directory = 'assets/map/relief';
  static const manifestAsset = '$directory/relief.json';
  static Future<List<Relief>>? _loading;

  /// The bundled layers, coarsest first; their pixels are read as needed.
  static Future<List<Relief>> load() =>
      _loading ??= rootBundle.loadString(manifestAsset).then(parse);

  static List<Relief> parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final layer in data['layers'] as List<dynamic>)
        if (layer case final Map<String, dynamic> l)
          Relief._(
            file: l['file'] as String,
            bounds: [
              for (final v in l['bounds'] as List<dynamic>)
                (v as num).toDouble(),
            ],
            lowest: (l['lowest'] as num).toDouble(),
            highest: (l['highest'] as num).toDouble(),
            fade: (l['fade'] as num).toDouble(),
            minScale: (l['minScale'] as num).toDouble(),
          ),
    ];
  }

  bool overlaps(Rect view) =>
      bounds[0] < view.right &&
      bounds[2] > view.left &&
      bounds[1] < view.bottom &&
      bounds[3] > view.top;

  /// Whether [view] lies wholly inside, clear of the faded edges.
  bool covers(Rect view) =>
      bounds[0] + fade <= view.left &&
      bounds[2] - fade >= view.right &&
      bounds[1] + fade <= view.top &&
      bounds[3] - fade >= view.bottom;

  final _images = <(int, bool), Future<ui.Image>>{};

  /// The layer coloured over [land], shadows deeper and lights fainter when
  /// [dark]; made once for each. The pixels are read for it and let go, so
  /// only the coloured images stay in memory.
  Future<ui.Image> image(
    Color land, {
    required bool dark,
  }) => _images[(land.toARGB32(), dark)] ??= () async {
    final bytes = await rootBundle.load('$directory/$file');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final source = (await codec.getNextFrame()).image;
    final data = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
    final width = source.width, height = source.height;
    source.dispose();
    codec.dispose();
    final rgba = await compute(_colour, (
      pixels: data!.buffer.asUint8List(),
      width: width,
      height: height,
      bounds: bounds,
      lowest: lowest,
      highest: highest,
      fade: fade,
      land: land.toARGB32(),
      dark: dark,
    ));
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }();
}

/// Heights in metres and the tints they take, low green to high brown, and
/// the snow of Hermon and higher.
const _hypsometric = <(double, int)>[
  (-450, 0xFF6E9F6A),
  (0, 0xFF93B57E),
  (250, 0xFFC2C08A),
  (700, 0xFFCDA772),
  (1200, 0xFFA8805A),
  (2000, 0xFF8E7462),
  (2800, 0xFFF2EFEA),
];

Uint8List _colour(
  ({
    Uint8List pixels,
    int width,
    int height,
    List<double> bounds,
    double lowest,
    double highest,
    double fade,
    int land,
    bool dark,
  })
  r,
) {
  final land = Color(r.land);
  final tint = r.dark ? .22 : .5;
  final shadow = r.dark ? .6 : .5;
  final light = r.dark ? .15 : .4;
  // The tint for each green value.
  final ramp = List.generate(256, (g) {
    final metres = r.lowest + (r.highest - r.lowest) * g / 255;
    var i = 1;
    while (i < _hypsometric.length - 1 && _hypsometric[i].$1 < metres) {
      i++;
    }
    final (m0, c0) = _hypsometric[i - 1];
    final (m1, c1) = _hypsometric[i];
    final t = ((metres - m0) / (m1 - m0)).clamp(0.0, 1.0);
    return Color.lerp(land, Color.lerp(Color(c0), Color(c1), t), tint)!;
  });
  final [west, south, east, north] = r.bounds;
  final perX = (east - west) / r.width, perY = (north - south) / r.height;
  double fade(double d) => (d / r.fade).clamp(0.0, 1.0);
  final out = Uint8List(r.width * r.height * 4);
  for (var y = 0; y < r.height; y++) {
    final edgeY = fade(math.min(y + .5, r.height - y - .5) * perY);
    for (var x = 0; x < r.width; x++) {
      final i = (y * r.width + x) * 4;
      final alpha = edgeY * fade(math.min(x + .5, r.width - x - .5) * perX);
      final s = (r.pixels[i] - 128) / 128;
      final base = ramp[r.pixels[i + 1]];
      final c = s < 0
          ? Color.lerp(base, const Color(0xFF000000), -s * shadow)!
          : Color.lerp(base, const Color(0xFFFFFFFF), s * light)!;
      // Premultiplied, as raw pixels are drawn.
      out[i] = (c.r * 255 * alpha).round();
      out[i + 1] = (c.g * 255 * alpha).round();
      out[i + 2] = (c.b * 255 * alpha).round();
      out[i + 3] = (alpha * 255).round();
    }
  }
  return out;
}

/// The kinds of place that are ground rather than a spot: drawn as their
/// [MapPin.area], tinted and named across it, without a pin.
const _areaKinds = {
  'region',
  'island',
  'natural area',
  'mountain range',
  'mountain ridge',
  'people group',
  'body of water',
  'valley',
  'garden',
  'forest',
};

/// A place on a [PlaceMap].
@immutable
class MapPin {
  const MapPin({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.id,
    this.primary = true,
    this.confidence,
    this.kind = '',
    this.area = const [],
    this.line = const [],
  });

  final double latitude;
  final double longitude;
  final String label;

  /// What a tap on the pin reports, for a caller with several places.
  final int? id;

  /// The likeliest location, drawn solid; other candidate locations of the
  /// same place are drawn hollow and fainter.
  final bool primary;

  /// 0 to 1000; candidates fade with it. Null draws at full strength.
  final int? confidence;

  /// `settlement`, `river`, `region`, …: a region is drawn as its [area]
  /// rather than as a pin.
  final String kind;

  /// The ground it covers, as rings of longitude, latitude pairs: a region's
  /// bounds, or for a spot, the area it lies somewhere within.
  final List<List<double>> area;

  /// The course it runs, for a river, a wadi or a road, as lines of
  /// longitude, latitude pairs.
  final List<List<double>> line;

  /// Drawn as ground, named across its middle, rather than as a pin.
  bool get isArea => _areaKinds.contains(kind);

  /// The strength it is drawn at, by its [confidence].
  double get strength => confidence == null
      ? 1.0
      : (0.35 + 0.65 * confidence!.clamp(0, 1000) / 1000);
}

/// Longitude is drawn shrunk by the cosine of this latitude, the middle of
/// the lands the maps show, so the Levant keeps its shape.
const _referenceLatitude = 32.0;
final _xScale = math.cos(_referenceLatitude * math.pi / 180);

/// Wadis are drawn from this scale, logical pixels to a degree of latitude,
/// where the land of Israel fills the map.
const _wadiScale = 150.0;

/// A map of [pins] over the bundled [Basemap], panned by dragging and zoomed
/// by pinching, the mouse wheel or its buttons. It opens fitted to the pins.
class PlaceMap extends StatefulWidget {
  const PlaceMap({
    super.key,
    required this.pins,
    this.onPinTap,
    this.basemap,
    this.relief,
    this.minSpan = 1.6,
  });

  final List<MapPin> pins;
  final ValueChanged<MapPin>? onPinTap;

  /// The basemap to draw; the bundled one, with the bundled [relief], when
  /// null. A test passes its own.
  final Basemap? basemap;

  /// The relief layers shaded over the land, coarsest first; none when null
  /// and a [basemap] is given.
  final List<Relief>? relief;

  /// The fewest degrees of latitude the opening view shows, so a single place
  /// is seen with its surroundings.
  final double minSpan;

  @override
  State<PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<PlaceMap> {
  Basemap? _basemap;
  List<Relief>? _relief;
  // The relief layers coloured for the theme, the colours they were made
  // for, and those asked for.
  final _reliefImages = <Relief, ui.Image>{};
  (Color, bool)? _reliefFor;
  final _reliefAsked = <Relief>{};
  // The point at the middle of the view, in degrees, and degrees of latitude
  // to logical pixels.
  Offset _center = const Offset(35.2, 31.8);
  double _scale = 60;
  bool _fitted = false;
  // At the start of a gesture.
  late Offset _startCenter;
  late double _startScale;
  late Offset _startFocal;

  static const _minScale = 6.0;
  static const _maxScale = 6000.0;

  @override
  void initState() {
    super.initState();
    _basemap = widget.basemap;
    _relief = widget.relief;
    if (_basemap == null) {
      Basemap.load().then((map) {
        if (mounted) setState(() => _basemap = map);
      });
      if (_relief == null) {
        Relief.load().then((relief) {
          if (mounted) setState(() => _relief = relief);
        });
      }
    }
  }

  /// The degrees the map shows at [size]: west to east, south to north.
  Rect _view(Size size) {
    final halfWidth = size.width / 2 / (_xScale * _scale);
    final halfHeight = size.height / 2 / _scale;
    return Rect.fromLTRB(
      _center.dx - halfWidth,
      _center.dy - halfHeight,
      _center.dx + halfWidth,
      _center.dy + halfHeight,
    );
  }

  /// Colour the relief layers the view needs over [land], once for each
  /// theme: those it overlaps, zoomed in far enough for.
  void _colourRelief(Size size, Color land, bool dark) {
    final relief = _relief;
    if (relief == null || size.isEmpty) return;
    if (_reliefFor != (land, dark)) {
      _reliefFor = (land, dark);
      _reliefImages.clear();
      _reliefAsked.clear();
    }
    final key = _reliefFor;
    final view = _view(size);
    for (final layer in relief) {
      if (_scale < layer.minScale ||
          !layer.overlaps(view) ||
          !_reliefAsked.add(layer)) {
        continue;
      }
      layer.image(land, dark: dark).then((image) {
        if (mounted && _reliefFor == key) {
          setState(() => _reliefImages[layer] = image);
        }
      });
    }
  }

  @override
  void didUpdateWidget(PlaceMap old) {
    super.didUpdateWidget(old);
    if (!_samePins(old.pins, widget.pins)) _fitted = false;
  }

  static bool _samePins(List<MapPin> a, List<MapPin> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  /// Centre the pins, and the likeliest places' areas and courses, and zoom
  /// to show them all, with a margin.
  void _fit(Size size) {
    _fitted = true;
    final pins = widget.pins;
    if (pins.isEmpty || size.isEmpty) return;
    var west = double.infinity, east = -double.infinity;
    var south = double.infinity, north = -double.infinity;
    void add(double longitude, double latitude) {
      west = math.min(west, longitude);
      east = math.max(east, longitude);
      south = math.min(south, latitude);
      north = math.max(north, latitude);
    }

    for (final p in pins) {
      add(p.longitude, p.latitude);
      if (!p.primary) continue;
      for (final part in [...p.area, ...p.line]) {
        for (var i = 0; i + 1 < part.length; i += 2) {
          add(part[i], part[i + 1]);
        }
      }
    }
    _center = Offset((west + east) / 2, (south + north) / 2);
    final latSpan = math.max(north - south, widget.minSpan);
    final lonSpan = math.max((east - west) * _xScale, widget.minSpan);
    _scale = math
        .min(size.width / (lonSpan * 1.3), size.height / (latSpan * 1.3))
        .clamp(_minScale, _maxScale);
  }

  Offset _toScreen(double longitude, double latitude, Size size) => Offset(
    size.width / 2 + (longitude - _center.dx) * _xScale * _scale,
    size.height / 2 - (latitude - _center.dy) * _scale,
  );

  /// Zoom by [factor], keeping the point under [focal] where it is.
  void _zoom(double factor, Offset focal, Size size) {
    final scale = (_scale * factor).clamp(_minScale, _maxScale);
    final dx = focal.dx - size.width / 2, dy = focal.dy - size.height / 2;
    final longitude = _center.dx + dx / (_xScale * _scale);
    final latitude = _center.dy - dy / _scale;
    setState(() {
      _scale = scale;
      _center = Offset(
        longitude - dx / (_xScale * scale),
        latitude + dy / scale,
      );
    });
  }

  /// The place tapped at [point]: the nearest pin or region label, then the
  /// nearest course, then the smallest area under it.
  MapPin? _pinAt(Offset point, Size size) {
    MapPin? best;
    var bestDistance = 24.0;
    for (final pin in widget.pins) {
      final at = pin.isArea && pin.area.isNotEmpty
          ? _ShapePaths.of(pin.area).labelPoint(pin)
          : (pin.longitude, pin.latitude);
      final d = (_toScreen(at.$1, at.$2, size) - point).distance;
      if (d < bestDistance) {
        best = pin;
        bestDistance = d;
      }
    }
    if (best != null) return best;
    bestDistance = 12;
    for (final pin in widget.pins) {
      for (final part in pin.line) {
        for (var i = 0; i + 3 < part.length; i += 2) {
          final d = _segmentDistance(
            point,
            _toScreen(part[i], part[i + 1], size),
            _toScreen(part[i + 2], part[i + 3], size),
          );
          if (d < bestDistance) {
            best = pin;
            bestDistance = d;
          }
        }
      }
    }
    if (best != null) return best;
    // In map units, as the area paths are.
    final at = Offset(
      (point.dx - size.width / 2) / _scale + _center.dx * _xScale,
      (point.dy - size.height / 2) / _scale - _center.dy,
    );
    var smallest = double.infinity;
    for (final pin in widget.pins) {
      if (pin.area.isEmpty) continue;
      final paths = _ShapePaths.of(pin.area);
      final extent = paths.area.getBounds().size;
      if (extent.width * extent.height < smallest && paths.area.contains(at)) {
        best = pin;
        smallest = extent.width * extent.height;
      }
    }
    return best;
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final length = ab.distanceSquared;
    if (length == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / length).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final colors = _MapColors(
      sea: Color.lerp(
        scheme.surface,
        const Color(0xFF4A90C8),
        dark ? .34 : .18,
      )!,
      land: Color.lerp(
        scheme.surface,
        const Color(0xFFC9B27C),
        dark ? .10 : .22,
      )!,
      river: Color.lerp(
        scheme.surface,
        const Color(0xFF3A80C0),
        dark ? .55 : .45,
      )!,
      pin: scheme.primary,
      region: scheme.tertiary,
      pinBorder: scheme.surface,
      label: scheme.onSurface,
      halo: scheme.surface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        // Fitted once, on first layout or when the pins change; a later
        // resize keeps the reader's view.
        if (!_fitted) _fit(size);
        _colourRelief(size, colors.land, dark);
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is PointerScrollEvent) {
                      final factor = math.pow(0.998, event.scrollDelta.dy);
                      _zoom(factor.toDouble(), event.localPosition, size);
                    }
                  },
                  child: GestureDetector(
                    onScaleStart: (details) {
                      _startCenter = _center;
                      _startScale = _scale;
                      _startFocal = details.localFocalPoint;
                    },
                    onScaleUpdate: (details) {
                      final scale = (_startScale * details.scale).clamp(
                        _minScale,
                        _maxScale,
                      );
                      // The point under the start focus follows the fingers.
                      final dx0 = _startFocal.dx - size.width / 2;
                      final dy0 = _startFocal.dy - size.height / 2;
                      final longitude =
                          _startCenter.dx + dx0 / (_xScale * _startScale);
                      final latitude = _startCenter.dy - dy0 / _startScale;
                      final dx = details.localFocalPoint.dx - size.width / 2;
                      final dy = details.localFocalPoint.dy - size.height / 2;
                      setState(() {
                        _scale = scale;
                        _center = Offset(
                          longitude - dx / (_xScale * scale),
                          latitude + dy / scale,
                        );
                      });
                    },
                    onTapUp: widget.onPinTap == null
                        ? null
                        : (details) {
                            final pin = _pinAt(details.localPosition, size);
                            if (pin != null) widget.onPinTap!(pin);
                          },
                    onDoubleTapDown: (details) =>
                        _zoom(2, details.localPosition, size),
                    onDoubleTap: () {},
                    child: CustomPaint(
                      size: size,
                      painter: _MapPainter(
                        basemap: _basemap,
                        relief: [
                          for (final layer in _relief ?? const <Relief>[])
                            if (_reliefImages[layer] case final image?)
                              (layer, image),
                        ],
                        pins: widget.pins,
                        center: _center,
                        scale: _scale,
                        colors: colors,
                        labelStyle:
                            theme.textTheme.labelSmall ??
                            const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: _ZoomButtons(
                  onZoomIn: () => _zoom(2, size.center(Offset.zero), size),
                  onZoomOut: () => _zoom(.5, size.center(Offset.zero), size),
                  onFit: widget.pins.isEmpty
                      ? null
                      : () => setState(() => _fit(size)),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 4,
                child: Text(
                  'Natural Earth · SRTM · OpenBible.info · '
                  '© OpenStreetMap contributors',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          icon: Icon(icon, size: 18),
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
        );
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: .9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.add, 'Zoom in', onZoomIn),
          button(Icons.remove, 'Zoom out', onZoomOut),
          if (onFit != null)
            button(Icons.center_focus_strong_outlined, 'Show all', onFit),
        ],
      ),
    );
  }
}

@immutable
class _MapColors {
  const _MapColors({
    required this.sea,
    required this.land,
    required this.river,
    required this.pin,
    required this.region,
    required this.pinBorder,
    required this.label,
    required this.halo,
  });

  final Color sea, land, river, pin, region, pinBorder, label, halo;

  @override
  bool operator ==(Object other) =>
      other is _MapColors &&
      other.sea == sea &&
      other.land == land &&
      other.river == river &&
      other.pin == pin &&
      other.region == region &&
      other.label == label;

  @override
  int get hashCode => Object.hash(sea, land, river, pin, region, label);
}

/// Shapes as paths in map units (longitude shrunk by [_xScale], latitude
/// flipped).
Path _path(Iterable<List<double>> shapes, {required bool close}) {
  final path = Path();
  for (final shape in shapes) {
    if (shape.length < 4) continue;
    path.moveTo(shape[0] * _xScale, -shape[1]);
    for (var i = 2; i + 1 < shape.length; i += 2) {
      path.lineTo(shape[i] * _xScale, -shape[i + 1]);
    }
    if (close) path.close();
  }
  return path;
}

/// The basemap's shapes as paths, built once per basemap.
class _BasemapPaths {
  _BasemapPaths(Basemap map)
    : land = _path(map.land, close: true),
      lakes = _path(map.lakes, close: true),
      rivers = _path(map.rivers, close: false),
      wadis = _path(map.wadis, close: false);

  final Path land, lakes, rivers, wadis;

  static final _cache = Expando<_BasemapPaths>();
  static _BasemapPaths of(Basemap map) => _cache[map] ??= _BasemapPaths(map);
}

/// A place's area as a path, and the point its name goes at, built once for
/// each shape a caller passes.
class _ShapePaths {
  _ShapePaths(List<List<double>> rings)
    : area = _path(rings, close: true),
      _middle = _centroid(rings);

  final Path area;
  final (double, double)? _middle;

  /// The middle of its largest ring, where that lies inside; otherwise the
  /// place's own position.
  (double, double) labelPoint(MapPin pin) {
    final middle = _middle;
    if (middle != null &&
        area.contains(Offset(middle.$1 * _xScale, -middle.$2))) {
      return middle;
    }
    return (pin.longitude, pin.latitude);
  }

  /// The centroid of the largest of [rings], by the shoelace formula.
  static (double, double)? _centroid(List<List<double>> rings) {
    (double, double)? best;
    var largest = 0.0;
    for (final ring in rings) {
      var area = 0.0, x = 0.0, y = 0.0;
      final n = ring.length ~/ 2;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final x0 = ring[2 * i], y0 = ring[2 * i + 1];
        final x1 = ring[2 * j], y1 = ring[2 * j + 1];
        final cross = x0 * y1 - x1 * y0;
        area += cross;
        x += (x0 + x1) * cross;
        y += (y0 + y1) * cross;
      }
      if (area.abs() > largest) {
        largest = area.abs();
        best = (x / (3 * area), y / (3 * area));
      }
    }
    return best;
  }

  static final _cache = Expando<_ShapePaths>();
  static _ShapePaths of(List<List<double>> rings) =>
      _cache[rings] ??= _ShapePaths(rings);
}

class _CoursePaths {
  static final _cache = Expando<Path>();
  static Path of(List<List<double>> lines) =>
      _cache[lines] ??= _path(lines, close: false);
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.basemap,
    required this.relief,
    required this.pins,
    required this.center,
    required this.scale,
    required this.colors,
    required this.labelStyle,
  });

  final Basemap? basemap;

  /// The relief layers coloured so far, coarsest first.
  final List<(Relief, ui.Image)> relief;
  final List<MapPin> pins;
  final Offset center;
  final double scale;
  final _MapColors colors;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.sea);
    final halfWidth = size.width / 2 / (_xScale * scale);
    final halfHeight = size.height / 2 / scale;
    final view = Rect.fromLTRB(
      center.dx - halfWidth,
      center.dy - halfHeight,
      center.dx + halfWidth,
      center.dy + halfHeight,
    );
    canvas.save();
    canvas.translate(
      size.width / 2 - center.dx * _xScale * scale,
      size.height / 2 + center.dy * scale,
    );
    canvas.scale(scale);
    final map = basemap;
    if (map != null) {
      final paths = _BasemapPaths.of(map);
      // Filled, not outlined: the detailed Levant is clipped out of a larger
      // shape, and an outline would draw the clip's edges as coast.
      canvas.drawPath(paths.land, Paint()..color = colors.land);
      // The layers in view, zoomed in far enough for, from the finest that
      // covers the whole view: the coarser ones under it would not show.
      final shown = [
        for (final (layer, image) in relief)
          if (scale >= layer.minScale / 2 && layer.overlaps(view))
            (layer, image),
      ];
      var from = 0;
      for (var i = shown.length - 1; i > 0; i--) {
        if (shown[i].$1.covers(view)) {
          from = i;
          break;
        }
      }
      if (shown.length > from) {
        // Over the land only: the elevations run out to sea, and the coast
        // stays crisp.
        canvas
          ..save()
          ..clipPath(paths.land);
        for (final (layer, image) in shown.skip(from)) {
          final [west, south, east, north] = layer.bounds;
          canvas.drawImageRect(
            image,
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
            Rect.fromLTRB(west * _xScale, -north, east * _xScale, -south),
            Paint()..filterQuality = FilterQuality.medium,
          );
        }
        canvas.restore();
      }
      if (scale >= _wadiScale) {
        canvas.drawPath(
          paths.wadis,
          Paint()
            ..color = colors.river.withValues(alpha: .55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8 / scale
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(
        paths.rivers,
        Paint()
          ..color = colors.river
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / scale
          ..strokeJoin = StrokeJoin.round,
      );
      // Over the rivers, which run on through the lakes they feed.
      canvas.drawPath(paths.lakes, Paint()..color = colors.sea);
    }

    // The places' ground and courses under every pin: candidates under the
    // likeliest, larger areas under smaller.
    final shaped = [
      ...pins.where((p) => !p.primary),
      ...pins.where((p) => p.primary),
    ];
    for (final pin in shaped) {
      if (pin.area.isEmpty) continue;
      final path = _ShapePaths.of(pin.area).area;
      if (!path.getBounds().overlaps(
        Rect.fromLTRB(
          view.left * _xScale,
          -view.bottom,
          view.right * _xScale,
          -view.top,
        ),
      )) {
        continue;
      }
      final strength = pin.strength * (pin.primary ? 1 : .6);
      // A region is the place; a spot's area is only where it may lie.
      final color = pin.isArea ? colors.region : colors.pin;
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(
            alpha: (pin.isArea ? .14 : .07) * strength,
          ),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: (pin.isArea ? .6 : .3) * strength)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (pin.isArea ? 1.5 : 1) / scale
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final pin in shaped) {
      if (pin.line.isEmpty) continue;
      canvas.drawPath(
        _CoursePaths.of(pin.line),
        Paint()
          ..color = colors.pin.withValues(
            alpha: .85 * pin.strength * (pin.primary ? 1 : .6),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = (pin.primary ? 3 : 2) / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    Offset screen(double longitude, double latitude) => Offset(
      size.width / 2 + (longitude - center.dx) * _xScale * scale,
      size.height / 2 - (latitude - center.dy) * scale,
    );
    Offset at(MapPin p) => screen(p.longitude, p.latitude);
    // Candidates under the likeliest locations, so a solid pin is never
    // hidden by a hollow one. A region is named across its ground instead.
    for (final pin in shaped) {
      final point = at(pin);
      if (!(Offset.zero & size).inflate(20).contains(point)) continue;
      final strength = pin.strength;
      if (pin.isArea) {
        // A region with no bounds known: a haze about its position.
        if (pin.area.isEmpty) {
          canvas.drawCircle(
            point,
            14,
            Paint()
              ..color = colors.region.withValues(
                alpha: .22 * strength * (pin.primary ? 1 : .6),
              )
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }
        continue;
      }
      if (pin.primary) {
        canvas.drawCircle(point, 7, Paint()..color = colors.pinBorder);
        canvas.drawCircle(
          point,
          5.5,
          Paint()..color = colors.pin.withValues(alpha: strength),
        );
      } else {
        canvas.drawCircle(
          point,
          5,
          Paint()
            ..color = colors.pin.withValues(alpha: strength * .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    // Labels last, over every pin: the likeliest locations' first, then the
    // regions'; one that would overlap a label already drawn is left for
    // zooming in to show.
    final drawn = <Rect>[];
    List<Shadow> halo() => [
      for (final o in const [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
      ])
        Shadow(color: colors.halo, offset: o, blurRadius: 1.5),
    ];
    for (final pin in [
      ...pins.where((p) => p.primary && !p.isArea),
      ...pins.where((p) => !p.primary && !p.isArea),
    ]) {
      if (pin.label.isEmpty) continue;
      final point = at(pin);
      if (!(Offset.zero & size).contains(point)) continue;
      final style = labelStyle.copyWith(
        color: colors.label.withValues(alpha: pin.primary ? 1 : .75),
        fontWeight: pin.primary ? FontWeight.w600 : FontWeight.w400,
        shadows: halo(),
      );
      final text = TextPainter(
        text: TextSpan(text: pin.label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 160);
      final origin = point + Offset(9, -text.height / 2);
      final box = (origin & text.size).inflate(1);
      if (drawn.any(box.overlaps)) continue;
      drawn.add(box);
      text.paint(canvas, origin);
    }
    for (final pin in pins.where((p) => p.isArea)) {
      if (pin.label.isEmpty) continue;
      final (longitude, latitude) = pin.area.isEmpty
          ? (pin.longitude, pin.latitude)
          : _ShapePaths.of(pin.area).labelPoint(pin);
      final point = screen(longitude, latitude);
      if (!(Offset.zero & size).contains(point)) continue;
      final style = labelStyle.copyWith(
        color: Color.lerp(
          colors.region,
          colors.label,
          .35,
        )!.withValues(alpha: pin.primary ? 1 : .75),
        fontWeight: FontWeight.w600,
        fontStyle: FontStyle.italic,
        letterSpacing: 1.6,
        shadows: halo(),
      );
      final text = TextPainter(
        text: TextSpan(text: pin.label.toUpperCase(), style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 200);
      final origin = point - Offset(text.width / 2, text.height / 2);
      final box = (origin & text.size).inflate(1);
      if (drawn.any(box.overlaps)) continue;
      drawn.add(box);
      text.paint(canvas, origin);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.basemap != basemap ||
      !listEquals(old.relief, relief) ||
      old.pins != pins ||
      old.center != center ||
      old.scale != scale ||
      old.colors != colors ||
      old.labelStyle != labelStyle;
}
