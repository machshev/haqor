import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Original, schematic reconstruction in geographic coordinates. These are
/// approximate footprints, not digitized excavation plans. See
/// doc/jerusalem-map.md for dating, evidence and uncertainties.
class JerusalemFeature {
  const JerusalemFeature(this.label, this.kind, this.points, this.labelAt);
  final String label;
  final String kind;
  final List<double> points;
  final Offset labelAt; // longitude, latitude
}

const jerusalemBounds = Rect.fromLTRB(35.224, 31.768, 35.247, 31.784);
const jerusalemFeatures = <JerusalemFeature>[
  JerusalemFeature('First Wall · approximate', 'wall', [
    35.2280,
    31.7770,
    35.2300,
    31.7766,
    35.2337,
    31.7767,
    35.2355,
    31.7754,
    35.2361,
    31.7730,
    35.2355,
    31.7710,
    35.2340,
    31.7700,
    35.2310,
    31.7698,
    35.2275,
    31.7705,
    35.2268,
    31.7730,
    35.2270,
    31.7752,
    35.2280,
    31.7770,
  ], Offset(35.2281, 31.7701)),
  JerusalemFeature('Second Wall · conjectural', 'wall', [
    35.2280,
    31.7770,
    35.2308,
    31.7775,
    35.2316,
    31.7794,
    35.2324,
    31.7810,
    35.2348,
    31.7808,
  ], Offset(35.2312, 31.7800)),
  JerusalemFeature('Temple precinct', 'precinct', [
    35.2342,
    31.7757,
    35.2371,
    31.7760,
    35.2379,
    31.7807,
    35.2347,
    31.7810,
    35.2342,
    31.7757,
  ], Offset(35.2360, 31.7796)),
  JerusalemFeature('Sanctuary', 'building', [
    35.2348,
    31.7777,
    35.2355,
    31.7777,
    35.2355,
    31.7784,
    35.2348,
    31.7784,
    35.2348,
    31.7777,
  ], Offset(35.2351, 31.7787)),
  JerusalemFeature('Court of Women / treasury', 'building', [
    35.2356,
    31.7777,
    35.2362,
    31.7777,
    35.2362,
    31.7784,
    35.2356,
    31.7784,
    35.2356,
    31.7777,
  ], Offset(35.2360, 31.7774)),
  JerusalemFeature('Royal portico', 'building', [
    35.2344,
    31.7760,
    35.2370,
    31.7763,
    35.2370,
    31.7766,
    35.2344,
    31.7763,
    35.2344,
    31.7760,
  ], Offset(35.2357, 31.7756)),
  JerusalemFeature('Solomon’s portico', 'building', [
    35.2370,
    31.7764,
    35.2376,
    31.7805,
    35.2378,
    31.7805,
    35.2372,
    31.7764,
    35.2370,
    31.7764,
  ], Offset(35.2388, 31.7793)),
  JerusalemFeature('Antonia · alternative trial tradition', 'building', [
    35.2338,
    31.7807,
    35.2353,
    31.7807,
    35.2353,
    31.7815,
    35.2338,
    31.7815,
    35.2338,
    31.7807,
  ], Offset(35.2339, 31.7820)),
  JerusalemFeature('Herod’s palace · likely praetorium', 'building', [
    35.2270,
    31.7738,
    35.2290,
    31.7738,
    35.2290,
    31.7768,
    35.2270,
    31.7768,
    35.2270,
    31.7738,
  ], Offset(35.2272, 31.7733)),
  JerusalemFeature('Upper City', 'district', [], Offset(35.2302, 31.7748)),
  JerusalemFeature(
    'Lower City / City of David',
    'district',
    [],
    Offset(35.2353, 31.7728),
  ),
  JerusalemFeature('Bethesda pools', 'pool', [
    35.2353,
    31.7817,
    35.2360,
    31.7817,
    35.2360,
    31.7824,
    35.2353,
    31.7824,
    35.2353,
    31.7817,
  ], Offset(35.2365, 31.7827)),
  JerusalemFeature('Pool of Siloam · sent man’s destination', 'pool', [
    35.2345,
    31.7701,
    35.2354,
    31.7701,
    35.2354,
    31.7706,
    35.2345,
    31.7706,
    35.2345,
    31.7701,
  ], Offset(35.2362, 31.7695)),
  JerusalemFeature('Kidron valley', 'valley', [
    35.2390,
    31.7840,
    35.2390,
    31.7810,
    35.2390,
    31.7780,
    35.2376,
    31.7745,
    35.2368,
    31.7715,
    35.2360,
    31.7690,
  ], Offset(35.2393, 31.7745)),
  JerusalemFeature('Tyropoeon valley', 'valley', [
    35.2315,
    31.7820,
    35.2327,
    31.7790,
    35.2336,
    31.7760,
    35.2338,
    31.7730,
    35.2349,
    31.7702,
  ], Offset(35.2332, 31.7740)),
  JerusalemFeature('Hinnom valley', 'valley', [
    35.2250,
    31.7780,
    35.2250,
    31.7740,
    35.2257,
    31.7710,
    35.2280,
    31.7688,
    35.2320,
    31.7682,
    35.2360,
    31.7690,
  ], Offset(35.2291, 31.7687)),
  JerusalemFeature(
    'Golgotha / tomb · traditional vicinity',
    'site',
    [],
    Offset(35.2297, 31.7785),
  ),
  JerusalemFeature(
    'Garden Tomb · alternative tradition',
    'site',
    [],
    Offset(35.2298, 31.7838),
  ),
  JerusalemFeature(
    'Upper room · estimated',
    'site',
    [],
    Offset(35.2285, 31.7718),
  ),
  JerusalemFeature(
    'High-priestly quarter · estimated',
    'site',
    [],
    Offset(35.2325, 31.7715),
  ),
  JerusalemFeature(
    'Gethsemane · traditional vicinity',
    'site',
    [],
    Offset(35.2397, 31.7793),
  ),
  JerusalemFeature('Mount of Olives', 'district', [], Offset(35.2450, 31.7790)),
  JerusalemFeature(
    'Southern steps / Huldah gates',
    'site',
    [],
    Offset(35.2355, 31.7752),
  ),
];

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
      'pool' => const Color(0xFF398AAD),
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
        ..strokeWidth = (f.kind == 'wall' ? 2.5 : 1.2);
      if (f.kind == 'wall') {
        for (final metric in path.computeMetrics()) {
          for (double d = 0; d < metric.length; d += 10) {
            canvas.drawPath(
              metric.extractPath(d, (d + 6).clamp(0, metric.length)),
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
