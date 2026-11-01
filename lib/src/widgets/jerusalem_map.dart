import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../jerusalem_plan.dart';

export '../jerusalem_plan.dart' show PlanFeature;

/// A feature of the plan; see [jerusalemPlan].
typedef JerusalemFeature = PlanFeature;

extension JerusalemFeatureLabel on PlanFeature {
  /// Where the label goes: longitude, latitude.
  Offset get labelAt => Offset(at.$1, at.$2);
}

final jerusalemBounds = Rect.fromLTRB(
  jerusalemBox.$1,
  jerusalemBox.$2,
  jerusalemBox.$3,
  jerusalemBox.$4,
);
const jerusalemFeatures = jerusalemPlan;

/// The city painted from the plan over the ground's relief, by
/// tool/build_jerusalem_image.dart, filling [jerusalemBounds].
const jerusalemImageAsset = 'assets/map/jerusalem_ad30.jpg';

/// The scale, logical pixels to a degree of latitude, from which the city is
/// drawn, and that by which it has faded fully in.
const _cityFrom = 9000.0, _cityFull = 14000.0;

/// Draw the painted city [image] over [rect], in map units, fading in as the
/// map zooms to it and out at its edges into the map around it; dimmed for a
/// dark theme.
void paintJerusalemImage(
  Canvas canvas,
  ui.Image image,
  Rect rect, {
  required double scale,
  required bool dark,
}) {
  if (scale < _cityFrom) return;
  final opacity = ((scale - _cityFrom) / (_cityFull - _cityFrom)).clamp(
    0.0,
    1.0,
  );
  canvas.saveLayer(
    rect,
    Paint()..color = Color.fromRGBO(0, 0, 0, dark ? opacity * .85 : opacity),
  );
  canvas.drawImageRect(
    image,
    Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
    rect,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = dark
          ? const ColorFilter.matrix([
              .55, 0, 0, 0, 0, //
              0, .55, 0, 0, 0,
              0, 0, .58, 0, 0,
              0, 0, 0, 1, 0,
            ])
          : null,
  );
  // Fade the edges out, so the city sits in the map rather than on it.
  final fade = rect.shortestSide * .08;
  final edges = [
    (
      Rect.fromLTWH(rect.left, rect.top, fade, rect.height),
      Alignment.centerLeft,
    ),
    (
      Rect.fromLTWH(rect.right - fade, rect.top, fade, rect.height),
      Alignment.centerRight,
    ),
    (Rect.fromLTWH(rect.left, rect.top, rect.width, fade), Alignment.topCenter),
    (
      Rect.fromLTWH(rect.left, rect.bottom - fade, rect.width, fade),
      Alignment.bottomCenter,
    ),
  ];
  for (final (edge, from) in edges) {
    canvas.drawRect(
      edge,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..shader = LinearGradient(
          begin: from,
          end: -from,
          colors: const [Color(0xFF000000), Color(0x00000000)],
        ).createShader(edge),
    );
  }
  canvas.restore();
}

/// Draw in screen space so line widths and labels remain readable on zoom.
void paintJerusalem(
  Canvas canvas,
  Size size,
  Offset Function(double, double) project,
  Color ink,
  Color paper, {
  required double scale,
  required TextStyle labelStyle,
  List<Rect> reserved = const [],
}) {
  if (scale < 9000) return;
  final extent = Rect.fromPoints(
    project(35.224, 31.784),
    project(35.247, 31.768),
  );
  if (!extent.overlaps(Offset.zero & size)) return;
  final labels = <Rect>[...reserved];
  for (final f in jerusalemFeatures) {
    final color = switch (f.kind) {
      'pool' || 'aqueduct' => const Color(0xFF398AAD),
      'road' => const Color(0xFFB07A3A),
      'valley' => const Color(0xFF9C8D73),
      'precinct' => const Color(0xFFC69C4D),
      _ => ink,
    };
    if (f.points.isNotEmpty) {
      final path = Path();
      for (var i = 0; i < f.points.length; i += 2) {
        final pt = project(f.points[i], f.points[i + 1]);
        if (i == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      final fill = ['precinct', 'building', 'pool'].contains(f.kind);
      if (fill) {
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: .18));
      }
      final paint = Paint()
        ..color = color.withValues(alpha: .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = switch (f.kind) {
          'wall' => 2.5,
          'road' || 'bridge' => 2,
          _ => 1.2,
        };
      // Walls dashed, the aqueduct dotted.
      final (dash, gap) = switch (f.kind) {
        'wall' => (6.0, 4.0),
        'aqueduct' => (2.0, 3.0),
        _ => (0.0, 0.0),
      };
      if (dash > 0) {
        for (final metric in path.computeMetrics()) {
          for (double d = 0; d < metric.length; d += dash + gap) {
            canvas.drawPath(
              metric.extractPath(d, (d + dash).clamp(0, metric.length)),
              paint,
            );
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
    }
    final pt = project(f.labelAt.dx, f.labelAt.dy);
    if (f.kind == 'site') {
      canvas.drawCircle(
        pt,
        3,
        Paint()
          ..color = color.withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    // Court labels become useful only at precinct scale.
    if (scale < 24000 &&
        [
          'Sanctuary',
          'Court of Women / treasury',
          'Royal portico',
          'Solomon’s portico',
        ].contains(f.label)) {
      continue;
    }
    final text = TextPainter(
      text: TextSpan(
        text: f.label,
        style: labelStyle.copyWith(
          fontSize: f.kind == 'district' ? 12 : 10,
          color: ink.withValues(alpha: .8),
          fontStyle: f.kind == 'district' ? FontStyle.italic : FontStyle.normal,
          shadows: [
            Shadow(color: paper, blurRadius: 4),
            Shadow(color: paper, blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: 150);
    final box = Rect.fromLTWH(
      pt.dx - text.width / 2,
      pt.dy + 5,
      text.width,
      text.height,
    );
    if (!(Offset.zero & size).overlaps(box) ||
        labels.any((r) => r.overlaps(box.inflate(2)))) {
      text.dispose();
      continue;
    }
    labels.add(box);
    text.paint(canvas, box.topLeft);
    text.dispose();
  }
  // North and metric scale, using the same latitude projection as PlaceMap.
  final metres = scale > 50000 ? 100 : 500;
  final length = metres / 111320 * scale;
  final p = Paint()
    ..color = ink
    ..strokeWidth = 2;
  canvas.drawLine(
    Offset(16, size.height - 32),
    Offset(16 + length, size.height - 32),
    p,
  );
  final text = TextPainter(
    text: TextSpan(
      text: 'N ↑   $metres m',
      style: labelStyle.copyWith(
        fontSize: 11,
        color: ink,
        backgroundColor: paper,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  text.paint(canvas, Offset(16, size.height - 52));
  text.dispose();
}

Future<void> showJerusalemMapNotes(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Jerusalem around AD 30'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A geographic reconstruction for exploring Gospel events. Zoom in for the Temple courts. Dashed walls and building outlines are approximate; hollow event markers identify estimated sites. Route lines join events, not excavated streets.\n\n'
              'The painting beneath is drawn from this plan over the real relief, with the Tyropoeon cut below its later fill. Walls, the Temple, palace, fortress, pools and ways follow the outlines; houses, trees and tombs are filled in for texture, not placed from excavation.\n\n'
              'The stepped pilgrims’ road from the Siloam pool to the Temple’s south-west corner was excavated from 2004 to 2019 and dated by coins under its paving to Pilate’s time. The Siloam pool shown is the Second Temple pool found in 2004. The lower aqueduct, from Solomon’s Pools, is traced to Wilson’s Arch. The Kidron bridge follows the Mishnah’s causeway of arches (Parah 3:6); no remains of it are known.\n\n'
              'The First and Second Walls are shown. The Second Wall’s course is disputed. The Third Wall, begun under Agrippa I after Jesus’ ministry, and today’s Ottoman walls are omitted.\n\n'
              'The western palace is the working location of Pilate’s headquarters; Antonia is shown as an alternative tradition. The upper room, high-priestly houses, Herod Antipas’ lodging and exact tomb site are uncertain. The Holy Sepulchre vicinity is used for Golgotha and the nearby tomb; the Garden Tomb is shown only as an alternative.\n\n'
              'Siloam is included as a landmark: John 9 records the healed man going there, not Jesus. The Temple precinct is well located; its interior courts are reconstructed.',
            ),
            const SizedBox(height: 12),
            for (final source in const [
              (
                'Jerusalem’s wall phases · University of Michigan',
                'https://image-database.nes.lsa.umich.edu/items/show/299',
              ),
              (
                'Temple layout and ancient sources · Katapi',
                'https://www.katapi.org.uk/Architecture/TempleMount30ce.html',
              ),
              (
                'Second Temple Jerusalem · archaeology',
                'https://jewishvirtuallibrary.org/jsource/Archaeology/Jerusalem.html',
              ),
              (
                'The street from the Siloam pool · Tel Aviv, 2019',
                'https://doi.org/10.1080/03344355.2019.1650491',
              ),
              (
                'The causeway over the Kidron · Mishnah Parah 3:6',
                'https://www.sefaria.org/Mishnah_Parah.3.6',
              ),
            ])
              TextButton(
                onPressed: () => launchUrl(Uri.parse(source.$2)),
                child: Text(source.$1),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
