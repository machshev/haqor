import 'package:flutter/material.dart';

import '../bindings/bindings.dart';
import 'name_details.dart' show placePin;
import 'place_map.dart';

/// An event of a sequence to show on a [SequenceMapPage], with its places.
typedef SequenceMapStop = ({
  int event,
  String title,
  List<SequencePlaceEntry> places,
});

/// The places of events of a sequence on the map, numbered in the order
/// they are drawn, each event at its chief place. A line runs from one
/// event's place to the next's only where the next is known to come after
/// it: where the order is unknown, no way is drawn.
class SequenceMapPage extends StatelessWidget {
  const SequenceMapPage({
    super.key,
    required this.title,
    required this.stops,
    required this.knownBefore,
    this.onOpenEvent,
    this.basemap,
  });

  final String title;
  final List<SequenceMapStop> stops;

  /// Whether the first event is known to come before the second.
  final bool Function(int before, int after) knownBefore;

  /// Picks out an event on the sequence, this page closed first.
  final ValueChanged<int>? onOpenEvent;

  /// The basemap to draw; the bundled one when null. A test passes its own.
  final Basemap? basemap;

  static Future<void> open(
    BuildContext context, {
    required String title,
    required List<SequenceMapStop> stops,
    required bool Function(int before, int after) knownBefore,
    ValueChanged<int>? onOpenEvent,
    Basemap? basemap,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SequenceMapPage(
        title: title,
        stops: stops,
        knownBefore: knownBefore,
        onOpenEvent: onOpenEvent,
        basemap: basemap,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The numbers of the events at each place, by place.
    final numbers = <int, List<int>>{};
    final firstAt = <int, SequencePlaceEntry>{};
    for (final (i, stop) in stops.indexed) {
      final place = stop.places.firstOrNull;
      if (place == null) continue;
      (numbers[place.place.id] ??= []).add(i + 1);
      firstAt.putIfAbsent(place.place.id, () => place);
    }
    final pins = [
      for (final MapEntry(key: id, value: place) in firstAt.entries)
        placePin(
          place.location,
          label: '${place.label} (${numbers[id]!.join(', ')})',
          id: id,
        ),
    ];
    final legs = <MapLeg>[];
    SequenceMapStop? last;
    for (final stop in stops) {
      final place = stop.places.firstOrNull;
      if (place == null) continue;
      final from = last?.places.first;
      if (from != null &&
          from.place.id != place.place.id &&
          knownBefore(last!.event, stop.event)) {
        legs.add(
          MapLeg([
            from.location.longitude,
            from.location.latitude,
            place.location.longitude,
            place.location.latitude,
          ]),
        );
      }
      last = stop;
    }
    final located = stops.where((s) => s.places.isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text(
              '$located of ${stops.length} events placed',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: pins.isEmpty
                ? Center(
                    child: Text(
                      'The text places none of these events.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : PlaceMap(
                    key: const ValueKey('sequence-map'),
                    basemap: basemap,
                    pins: pins,
                    legs: legs,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'A line joins two places only where the second event is known '
              'to follow the first.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: stops.length,
              itemBuilder: (context, i) {
                final stop = stops[i];
                final places = stop.places.map((p) => p.label).join(', ');
                return ListTile(
                  key: ValueKey('sequence-map-stop-${stop.event}'),
                  dense: true,
                  leading: CircleAvatar(
                    radius: 13,
                    child: Text('${i + 1}', style: theme.textTheme.labelSmall),
                  ),
                  title: Text(stop.title),
                  subtitle: Text(places.isEmpty ? 'No place told' : places),
                  enabled: stop.places.isNotEmpty || onOpenEvent != null,
                  onTap: onOpenEvent == null
                      ? null
                      : () {
                          Navigator.pop(context);
                          onOpenEvent!(stop.event);
                        },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
