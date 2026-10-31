import '../bindings/bindings.dart';
import 'place_map.dart';

/// The text's stops and offshore waypoints remain authoritative. The storm
/// in Acts 27 and the Exodus crossing are not normal shipping journeys.
List<MapLeg> journeyMapLegs(
  List<JourneyStopEntry> stops, {
  bool highlighted = false,
}) {
  final drawn = stops.where((s) => s.drawn).toList();
  return [
    for (var i = 0; i + 1 < drawn.length; i++)
      MapLeg(
        [
          drawn[i].location.longitude,
          drawn[i].location.latitude,
          ...drawn[i + 1].via,
          drawn[i + 1].location.longitude,
          drawn[i + 1].location.latitude,
        ],
        bySea: drawn[i + 1].bySea,
        highlighted: highlighted,
        estimateSea:
            !(drawn[i + 1].book == 2 ||
                (drawn[i + 1].book == 44 &&
                    ((drawn[i + 1].chapter == 27 && drawn[i + 1].verse >= 14) ||
                        (drawn[i + 1].chapter == 28 &&
                            drawn[i + 1].verse == 1)))),
      ),
  ];
}

/// Expand an event-to-event connection through an attested journey's stops.
/// Only forward sequences containing a voyage are used; unrelated land
/// connections keep their existing road routing.
List<MapLeg>? voyageBetween(
  List<JourneyEntry> journeys,
  int from,
  int to, {
  bool highlighted = false,
  List<ThematicTarget>? fromPassages,
  List<ThematicTarget>? toPassages,
}) {
  List<JourneyStopEntry>? best;
  for (final journey in journeys) {
    final stops = journey.stops;
    bool overlaps(List<ThematicTarget>? passages) =>
        passages == null ||
        passages.any(
          (p) => stops.any(
            (s) =>
                s.book == p.book &&
                s.chapter * 1000 + s.verse >= p.chapter * 1000 + p.verse &&
                s.chapter * 1000 + s.verse <=
                    p.lastChapter * 1000 + p.lastVerse,
          ),
        );
    if (!overlaps(fromPassages) || !overlaps(toPassages)) continue;
    for (var i = 0; i < stops.length; i++) {
      if (stops[i].place.id != from) continue;
      for (var j = i + 1; j < stops.length; j++) {
        if (stops[j].place.id != to) continue;
        final candidate = stops.sublist(i, j + 1);
        if (candidate.skip(1).any((s) => s.bySea) &&
            (best == null || candidate.length < best.length)) {
          best = candidate;
        }
      }
    }
  }
  return best == null ? null : journeyMapLegs(best, highlighted: highlighted);
}
