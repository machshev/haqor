import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The coastlines, lakes and rivers the place maps draw: Natural Earth's
/// (public domain), clipped to the lands of the Bible and bundled, so the maps
/// need no network. `tool/fetch-basemap.sh` builds the asset.
class Basemap {
  Basemap._(this.land, this.lakes, this.rivers);

  /// Each shape as longitude, latitude pairs.
  final List<Float64List> land;
  final List<Float64List> lakes;
  final List<Float64List> rivers;

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
    return Basemap._(shapes('land'), shapes('lakes'), shapes('rivers'));
  }
}

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
}

/// Longitude is drawn shrunk by the cosine of this latitude, the middle of
/// the lands the maps show, so the Levant keeps its shape.
const _referenceLatitude = 32.0;
final _xScale = math.cos(_referenceLatitude * math.pi / 180);

/// A map of [pins] over the bundled [Basemap], panned by dragging and zoomed
/// by pinching, the mouse wheel or its buttons. It opens fitted to the pins.
class PlaceMap extends StatefulWidget {
  const PlaceMap({
    super.key,
    required this.pins,
    this.onPinTap,
    this.basemap,
    this.minSpan = 1.6,
  });

  final List<MapPin> pins;
  final ValueChanged<MapPin>? onPinTap;

  /// The basemap to draw; the bundled one when null. A test passes its own.
  final Basemap? basemap;

  /// The fewest degrees of latitude the opening view shows, so a single place
  /// is seen with its surroundings.
  final double minSpan;

  @override
  State<PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<PlaceMap> {
  Basemap? _basemap;
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
    if (_basemap == null) {
      Basemap.load().then((map) {
        if (mounted) setState(() => _basemap = map);
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

  /// Centre the pins and zoom to show them all, with a margin.
  void _fit(Size size) {
    _fitted = true;
    final pins = widget.pins;
    if (pins.isEmpty || size.isEmpty) return;
    var west = double.infinity, east = -double.infinity;
    var south = double.infinity, north = -double.infinity;
    for (final p in pins) {
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
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

  MapPin? _pinAt(Offset point, Size size) {
    MapPin? best;
    var bestDistance = 24.0;
    for (final pin in widget.pins) {
      final d = (_toScreen(pin.longitude, pin.latitude, size) - point).distance;
      if (d < bestDistance) {
        best = pin;
        bestDistance = d;
      }
    }
    return best;
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
                right: 6,
                bottom: 4,
                child: Text(
                  'Natural Earth · OpenBible.info',
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
    required this.pinBorder,
    required this.label,
    required this.halo,
  });

  final Color sea, land, river, pin, pinBorder, label, halo;

  @override
  bool operator ==(Object other) =>
      other is _MapColors &&
      other.sea == sea &&
      other.land == land &&
      other.river == river &&
      other.pin == pin &&
      other.label == label;

  @override
  int get hashCode => Object.hash(sea, land, river, pin, label);
}

/// The basemap's shapes as paths in map units (longitude shrunk by
/// [_xScale], latitude flipped), built once per basemap.
class _BasemapPaths {
  _BasemapPaths(Basemap map)
    : land = _path(map.land, close: true),
      lakes = _path(map.lakes, close: true),
      rivers = _path(map.rivers, close: false);

  final Path land, lakes, rivers;

  static Path _path(List<Float64List> shapes, {required bool close}) {
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

  static final _cache = Expando<_BasemapPaths>();
  static _BasemapPaths of(Basemap map) => _cache[map] ??= _BasemapPaths(map);
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.basemap,
    required this.pins,
    required this.center,
    required this.scale,
    required this.colors,
    required this.labelStyle,
  });

  final Basemap? basemap;
  final List<MapPin> pins;
  final Offset center;
  final double scale;
  final _MapColors colors;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.sea);
    final map = basemap;
    if (map != null) {
      final paths = _BasemapPaths.of(map);
      canvas.save();
      canvas.translate(
        size.width / 2 - center.dx * _xScale * scale,
        size.height / 2 + center.dy * scale,
      );
      canvas.scale(scale);
      // Filled, not outlined: the detailed Levant is clipped out of a larger
      // shape, and an outline would draw the clip's edges as coast.
      canvas.drawPath(paths.land, Paint()..color = colors.land);
      canvas.drawPath(paths.lakes, Paint()..color = colors.sea);
      canvas.drawPath(
        paths.rivers,
        Paint()
          ..color = colors.river
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / scale
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.restore();
    }

    Offset screen(MapPin p) => Offset(
      size.width / 2 + (p.longitude - center.dx) * _xScale * scale,
      size.height / 2 - (p.latitude - center.dy) * scale,
    );
    // Candidates under the likeliest locations, so a solid pin is never
    // hidden by a hollow one.
    final ordered = [
      ...pins.where((p) => !p.primary),
      ...pins.where((p) => p.primary),
    ];
    for (final pin in ordered) {
      final at = screen(pin);
      if (!(Offset.zero & size).inflate(20).contains(at)) continue;
      final strength = pin.confidence == null
          ? 1.0
          : (0.35 + 0.65 * pin.confidence!.clamp(0, 1000) / 1000);
      if (pin.primary) {
        canvas.drawCircle(at, 7, Paint()..color = colors.pinBorder);
        canvas.drawCircle(
          at,
          5.5,
          Paint()..color = colors.pin.withValues(alpha: strength),
        );
      } else {
        canvas.drawCircle(
          at,
          5,
          Paint()
            ..color = colors.pin.withValues(alpha: strength * .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    // Labels last, over every pin, the likeliest locations' first; one that
    // would overlap a label already drawn is left for zooming in to show.
    final drawn = <Rect>[];
    for (final pin in [
      ...pins.where((p) => p.primary),
      ...pins.where((p) => !p.primary),
    ]) {
      if (pin.label.isEmpty) continue;
      final at = screen(pin);
      if (!(Offset.zero & size).contains(at)) continue;
      final style = labelStyle.copyWith(
        color: colors.label.withValues(alpha: pin.primary ? 1 : .75),
        fontWeight: pin.primary ? FontWeight.w600 : FontWeight.w400,
        shadows: [
          for (final o in const [
            Offset(1, 0),
            Offset(-1, 0),
            Offset(0, 1),
            Offset(0, -1),
          ])
            Shadow(color: colors.halo, offset: o, blurRadius: 1.5),
        ],
      );
      final text = TextPainter(
        text: TextSpan(text: pin.label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 160);
      final origin = at + Offset(9, -text.height / 2);
      final box = (origin & text.size).inflate(1);
      if (drawn.any(box.overlaps)) continue;
      drawn.add(box);
      text.paint(canvas, origin);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.basemap != basemap ||
      old.pins != pins ||
      old.center != center ||
      old.scale != scale ||
      old.colors != colors ||
      old.labelStyle != labelStyle;
}
