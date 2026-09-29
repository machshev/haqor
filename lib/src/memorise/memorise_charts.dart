import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One point of a single-series chart: its axis label and its value.
class ChartPoint {
  const ChartPoint(this.label, this.value, {this.tooltip});

  final String label;
  final num value;

  /// What a tap or hover on the point says; defaults to "label: value".
  final String? tooltip;
}

/// A compact single-series chart for the memorisation dashboard: bars for
/// counts per day, or a line for a running total. One series in the theme's
/// primary colour, so the title names it and no legend is needed. Tapping or
/// hovering a point shows its value; an optional dashed reference line marks
/// a target such as the daily goal.
class MiniChart extends StatefulWidget {
  const MiniChart({
    super.key,
    required this.points,
    this.line = false,
    this.reference,
    this.referenceLabel,
    this.height = 140,
    this.labelEvery = 7,
  });

  final List<ChartPoint> points;
  final bool line;
  final num? reference;
  final String? referenceLabel;
  final double height;

  /// Show every n-th axis label (the last point is always labelled).
  final int labelEvery;

  @override
  State<MiniChart> createState() => _MiniChartState();
}

class _MiniChartState extends State<MiniChart> {
  int? _active;

  static const _leftGutter = 32.0;
  static const _bottomGutter = 18.0;
  static const _topGutter = 22.0;

  int? _indexAt(Offset local, Size size) {
    final n = widget.points.length;
    if (n == 0) return null;
    final plotWidth = size.width - _leftGutter;
    final x = local.dx - _leftGutter;
    if (x < 0 || x > plotWidth) return null;
    return (x / plotWidth * n).floor().clamp(0, n - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        void update(Offset local) {
          final i = _indexAt(local, size);
          if (i != _active) setState(() => _active = i);
        }

        final active = _active;
        final point = active == null ? null : widget.points[active];
        return MouseRegion(
          onHover: (e) => update(e.localPosition),
          onExit: (_) => setState(() => _active = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => update(d.localPosition),
            onHorizontalDragUpdate: (d) => update(d.localPosition),
            child: Semantics(
              label: widget.points
                  .map((p) => p.tooltip ?? '${p.label}: ${p.value}')
                  .join(', '),
              child: SizedBox(
                height: widget.height,
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ChartPainter(
                          points: widget.points,
                          line: widget.line,
                          reference: widget.reference,
                          referenceLabel: widget.referenceLabel,
                          active: active,
                          labelEvery: widget.labelEvery,
                          series: theme.colorScheme.primary,
                          surface: theme.colorScheme.surfaceContainerLow,
                          grid: theme.colorScheme.outlineVariant,
                          muted: theme.colorScheme.onSurfaceVariant,
                          textStyle:
                              theme.textTheme.labelSmall ?? const TextStyle(),
                        ),
                      ),
                    ),
                    if (point != null)
                      _Tooltip(
                        text: point.tooltip ?? '${point.label}: ${point.value}',
                        fraction:
                            (active! + 0.5) / math.max(widget.points.length, 1),
                        leftGutter: _leftGutter,
                        width: size.width,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({
    required this.text,
    required this.fraction,
    required this.leftGutter,
    required this.width,
  });

  final String text;
  final double fraction;
  final double leftGutter;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const tipWidth = 150.0;
    final centre = leftGutter + fraction * (width - leftGutter);
    final left = (centre - tipWidth / 2)
        .clamp(0.0, math.max(0.0, width - tipWidth))
        .toDouble();
    return Positioned(
      left: left,
      top: -6,
      width: tipWidth,
      child: IgnorePointer(
        child: Material(
          elevation: 2,
          color: theme.colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.line,
    required this.reference,
    required this.referenceLabel,
    required this.active,
    required this.labelEvery,
    required this.series,
    required this.surface,
    required this.grid,
    required this.muted,
    required this.textStyle,
  });

  final List<ChartPoint> points;
  final bool line;
  final num? reference;
  final String? referenceLabel;
  final int? active;
  final int labelEvery;
  final Color series;
  final Color surface;
  final Color grid;
  final Color muted;
  final TextStyle textStyle;

  /// A round axis maximum (1, 2, 5 × 10ⁿ) at or above `value`.
  static double _niceMax(double value) {
    if (value <= 0) return 1;
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor());
    for (final step in [1, 2, 5, 10]) {
      if (step * magnitude >= value) return (step * magnitude).toDouble();
    }
    return (10 * magnitude).toDouble();
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at, {
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: s,
        style: textStyle.copyWith(color: muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const left = _MiniChartState._leftGutter;
    const bottom = _MiniChartState._bottomGutter;
    const top = _MiniChartState._topGutter;
    final plot = Rect.fromLTRB(left, top, size.width, size.height - bottom);
    final maxValue = points
        .map((p) => p.value.toDouble())
        .fold<double>((reference ?? 0).toDouble(), math.max);
    final yMax = _niceMax(maxValue);
    double y(num v) => plot.bottom - v / yMax * plot.height;

    // Recessive grid: baseline, midline and top, labelled on the left.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final v in [0.0, yMax / 2, yMax]) {
      canvas.drawLine(
        Offset(plot.left, y(v)),
        Offset(plot.right, y(v)),
        gridPaint,
      );
      // Counts are whole numbers: a fractional gridline goes unlabelled.
      if (v == v.roundToDouble()) {
        _text(
          canvas,
          v.toInt().toString(),
          Offset(plot.left - 6, y(v)),
          align: TextAlign.right,
        );
      }
    }

    final n = points.length;
    final slot = plot.width / n;
    double cx(int i) => plot.left + slot * (i + 0.5);

    if (line) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final p = Offset(cx(i), y(points[i].value));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      final area = Path.from(path)
        ..lineTo(cx(n - 1), plot.bottom)
        ..lineTo(cx(0), plot.bottom)
        ..close();
      canvas.drawPath(area, Paint()..color = series.withValues(alpha: 0.12));
      canvas.drawPath(
        path,
        Paint()
          ..color = series
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
      final i = active ?? n - 1;
      final marker = Offset(cx(i), y(points[i].value));
      // A surface ring keeps the marker legible over the line.
      canvas.drawCircle(marker, 6, Paint()..color = surface);
      canvas.drawCircle(marker, 4, Paint()..color = series);
    } else {
      // Bars with a 2px gap between neighbours and rounded data-ends
      // anchored to the baseline.
      final barWidth = math.max(1.0, slot - 2);
      for (var i = 0; i < n; i++) {
        final v = points[i].value;
        if (v <= 0) continue;
        final rect = Rect.fromLTRB(
          cx(i) - barWidth / 2,
          y(v),
          cx(i) + barWidth / 2,
          plot.bottom,
        );
        final radius = Radius.circular(math.min(4, barWidth / 2));
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius),
          Paint()
            ..color = active == null || active == i
                ? series
                : series.withValues(alpha: 0.45),
        );
      }
    }

    final ref = reference;
    if (ref != null && ref > 0) {
      final ry = y(ref);
      final dash = Paint()
        ..color = muted
        ..strokeWidth = 1;
      for (var x = plot.left; x < plot.right; x += 6) {
        canvas.drawLine(
          Offset(x, ry),
          Offset(math.min(x + 3, plot.right), ry),
          dash,
        );
      }
      if (referenceLabel != null) {
        _text(canvas, referenceLabel!, Offset(plot.left + 4, ry - 8));
      }
    }

    for (var i = 0; i < n; i++) {
      if (i % labelEvery != 0 && i != n - 1) continue;
      // Leave room before the always-drawn last label.
      final crowdsLast = n - 1 - i < math.max(1, (labelEvery + 1) ~/ 2);
      if (i != n - 1 && crowdsLast) continue;
      _text(
        canvas,
        points[i].label,
        Offset(cx(i), plot.bottom + bottom / 2 + 2),
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points ||
      old.active != active ||
      old.series != series ||
      old.reference != reference;
}

/// Colour for a verse's memorisation strength (0 not started … 5 mature): one
/// hue from faint to full, so the heatmap reads as "how well known".
Color strengthColor(ColorScheme scheme, int strength) {
  if (strength <= 0) return scheme.surfaceContainerHighest;
  const alphas = [0.0, 0.22, 0.38, 0.58, 0.78, 1.0];
  return Color.alphaBlend(
    scheme.primary.withValues(alpha: alphas[strength.clamp(0, 5)]),
    scheme.surfaceContainerHighest,
  );
}

const kStrengthLabels = [
  'Not started',
  'Learning',
  'Nearly there',
  'Learnt',
  'Established',
  'Mature',
];
