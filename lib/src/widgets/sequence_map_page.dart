import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import 'name_details.dart' show placePin;
import 'place_map.dart';
import 'journey_map_legs.dart';

/// An event of a sequence to show on a [SequenceMapPage], with its places.
typedef SequenceMapStop = ({
  int event,
  String title,
  List<SequencePlaceEntry> places,
});

/// The places of events of a sequence on the map, numbered in the order
/// they are drawn, each event at every place it lists. An event's places are
/// joined in their order, its route, and a line runs from one event's last
/// place to the next's first only where the next is known to come after it:
/// where the order is unknown, no way is drawn.
class SequenceMapPage extends StatefulWidget {
  const SequenceMapPage({
    super.key,
    required this.title,
    required this.stops,
    required this.knownBefore,
    this.onOpenEvent,
    this.basemap,
    this.journeys,
    this.passages = const {},
  });

  /// Supplied by tests; otherwise loaded through the existing core signal.
  final List<JourneyEntry>? journeys;
  final Map<int, List<ThematicTarget>> passages;

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
    Map<int, List<ThematicTarget>> passages = const {},
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SequenceMapPage(
        title: title,
        stops: stops,
        knownBefore: knownBefore,
        onOpenEvent: onOpenEvent,
        basemap: basemap,
        passages: passages,
      ),
    ),
  );

  @override
  State<SequenceMapPage> createState() => _SequenceMapPageState();
}

class _SequenceMapPageState extends State<SequenceMapPage> {
  /// The index of the event picked out in the list, if any.
  int? _selected;
  static int _nextJourneyRequest = 0x53000000;
  StreamSubscription<RustSignalPack<Journeys>>? _journeySub;
  List<JourneyEntry> _journeys = const [];

  @override
  void initState() {
    super.initState();
    _journeys = widget.journeys ?? const [];
    if (widget.journeys == null && widget.basemap == null) {
      final id = _nextJourneyRequest++;
      _journeySub = Journeys.rustSignalStream.listen((pack) {
        if (!mounted || pack.message.requestId != id) return;
        setState(() => _journeys = pack.message.journeys);
      });
      GetJourneys(requestId: id).sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _journeySub?.cancel();
    super.dispose();
  }

  List<MapLeg> _connection(
    SequencePlaceEntry from,
    SequencePlaceEntry to,
    bool highlighted,
    int fromEvent,
    int toEvent,
  ) =>
      voyageBetween(
        _journeys,
        from.place.id,
        to.place.id,
        highlighted: highlighted,
        fromPassages: widget.passages[fromEvent],
        toPassages: widget.passages[toEvent],
      ) ??
      [
        MapLeg([
          from.location.longitude,
          from.location.latitude,
          to.location.longitude,
          to.location.latitude,
        ], highlighted: highlighted),
      ];

  /// The event the picked one is known to follow most nearly, of those
  /// before it in the list with a place: where the way to it comes from.
  int? _cameFrom(int i) {
    final stops = widget.stops;
    for (var j = i - 1; j >= 0; j--) {
      if (stops[j].places.isEmpty) continue;
      if (widget.knownBefore(stops[j].event, stops[i].event)) return j;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stops = widget.stops;
    final selected = _selected;
    final picked = selected == null ? null : stops[selected].places.firstOrNull;
    final pickedPlaces = selected == null
        ? const <SequencePlaceEntry>[]
        : stops[selected].places;
    final pickedIds = {for (final p in pickedPlaces) p.place.id};
    // The numbers of the events at each place, by place.
    final numbers = <int, List<int>>{};
    final firstAt = <int, SequencePlaceEntry>{};
    for (final (i, stop) in stops.indexed) {
      for (final place in stop.places) {
        final at = numbers[place.place.id] ??= [];
        if (at.lastOrNull != i + 1) at.add(i + 1);
        firstAt.putIfAbsent(place.place.id, () => place);
      }
    }
    final pins = [
      for (final MapEntry(key: id, value: place) in firstAt.entries)
        placePin(
          place.location,
          label: '${place.label} (${numbers[id]!.join(', ')})',
          id: id,
          highlighted: pickedIds.contains(id),
        ),
    ];
    // The way to the picked event, from the place of the one it follows.
    final from = selected == null || picked == null
        ? null
        : _cameFrom(selected);
    final fromPlace = from == null ? null : stops[from].places.last;
    final way = fromPlace == null || fromPlace.place.id == picked!.place.id
        ? null
        : [
            fromPlace.location.longitude,
            fromPlace.location.latitude,
            picked.location.longitude,
            picked.location.latitude,
          ];
    final legs = <MapLeg>[];
    var wayDrawn = false;
    int? last;
    for (final (i, stop) in stops.indexed) {
      final place = stop.places.firstOrNull;
      if (place == null) continue;
      final previous = last == null ? null : stops[last].places.last;
      if (previous != null &&
          previous.place.id != place.place.id &&
          widget.knownBefore(stops[last!].event, stop.event)) {
        final isWay = way != null && last == from && i == selected;
        wayDrawn |= isWay;
        legs.addAll(
          _connection(previous, place, isWay, stops[last].event, stop.event),
        );
      }
      last = i;
    }
    if (way != null && !wayDrawn) {
      legs.addAll(
        _connection(
          fromPlace!,
          picked!,
          true,
          stops[from!].event,
          stops[selected!].event,
        ),
      );
    }
    // Each event's own route, from place to place in the order it lists them.
    for (final (i, stop) in stops.indexed) {
      for (var k = 1; k < stop.places.length; k++) {
        final a = stop.places[k - 1], b = stop.places[k];
        if (a.place.id == b.place.id) continue;
        legs.addAll(_connection(a, b, i == selected, stop.event, stop.event));
      }
    }
    final route = [
      for (final p in pickedPlaces) ...[
        p.location.longitude,
        p.location.latitude,
      ],
    ];
    final focus = pickedPlaces.length > 1
        ? [...?way, ...route]
        : way ?? (route.isEmpty ? null : route);
    final located = stops.where((s) => s.places.isNotEmpty).length;
    final open = widget.onOpenEvent;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title),
            Text(
              '$located of ${stops.length} events placed${legs.any((l) => l.bySea) ? ' · sea courses estimated' : ''}',
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
                    basemap: widget.basemap,
                    pins: pins,
                    legs: legs,
                    focus: focus,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'A line joins two places only where the second event is known '
              'to follow the first. Tap an event to pick out its place and '
              'the way to it.',
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
                  selected: _selected == i,
                  leading: CircleAvatar(
                    radius: 13,
                    child: Text('${i + 1}', style: theme.textTheme.labelSmall),
                  ),
                  title: Text(stop.title),
                  subtitle: Text(places.isEmpty ? 'No place told' : places),
                  onTap: () =>
                      setState(() => _selected = _selected == i ? null : i),
                  trailing: open == null
                      ? null
                      : IconButton(
                          key: ValueKey('sequence-map-open-${stop.event}'),
                          icon: const Icon(Icons.open_in_new),
                          tooltip: 'Show in the sequence',
                          onPressed: () {
                            Navigator.pop(context);
                            open(stop.event);
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
