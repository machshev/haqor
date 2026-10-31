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
    this.tracks = const {},
    this.initialTrack,
  });

  /// Supplied by tests; otherwise loaded through the existing core signal.
  final List<JourneyEntry>? journeys;
  final Map<int, List<ThematicTarget>> passages;

  /// Explicit journey membership, not people merely mentioned in a passage.
  /// With no assignments the existing chronological map is retained.
  final Map<int, List<String>> tracks;
  final String? initialTrack;

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
    Map<int, List<String>> tracks = const {},
    String? initialTrack,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SequenceMapPage(
        title: title,
        stops: stops,
        knownBefore: knownBefore,
        onOpenEvent: onOpenEvent,
        basemap: basemap,
        passages: passages,
        tracks: tracks,
        initialTrack: initialTrack,
      ),
    ),
  );

  @override
  State<SequenceMapPage> createState() => _SequenceMapPageState();
}

/// The colours people's tracks are drawn in, in the order the tracks are
/// first met: strong enough for the light map and the dark.
const trackColors = <Color>[
  Color(0xFFC0392B), // red
  Color(0xFF1F6FB2), // blue
  Color(0xFF2E8B3E), // green
  Color(0xFF8E44AD), // purple
  Color(0xFFD68910), // amber
  Color(0xFF00897B), // teal
  Color(0xFFC2185B), // magenta
  Color(0xFF6D4C41), // brown
];

class _SequenceMapPageState extends State<SequenceMapPage> {
  final _list = ScrollController();
  final _tileKeys = <int, GlobalKey>{};

  /// The colour [track]'s legs are drawn in; none without tracks.
  Color? _colorOf(String? track) {
    final i = track == null ? -1 : _tracks.indexOf(track);
    return i < 0 ? null : trackColors[i % trackColors.length];
  }

  /// The colour of an event's legs: its first track that is shown.
  Color? _eventColor(int event) => _colorOf(
    (widget.tracks[event] ?? const <String>[])
        .where((t) => _track == null || t == _track)
        .firstOrNull,
  );

  /// The event to pick [forward] or back of the one picked: the next with a
  /// place, or the next of all where none has one; null at an end.
  int? _step(bool forward) {
    final stops = _stops;
    final placed = [
      for (final (i, s) in stops.indexed)
        if (s.places.isNotEmpty) i,
    ];
    final order = placed.isEmpty
        ? [for (var i = 0; i < stops.length; i++) i]
        : placed;
    final at = _selected;
    if (at == null) return forward ? order.firstOrNull : order.lastOrNull;
    return forward
        ? order.where((i) => i > at).firstOrNull
        : order.where((i) => i < at).lastOrNull;
  }

  void _pick(int? i) {
    setState(() => _selected = i);
    if (i == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(i));
  }

  /// Scroll the list so the [i]th event's tile is seen.
  void _reveal(int i, {bool again = true}) {
    if (!mounted) return;
    final tile = _tileKeys[i]?.currentContext;
    if (tile != null) {
      Scrollable.ensureVisible(
        tile,
        alignment: .5,
        duration: const Duration(milliseconds: 200),
      );
    } else if (again && _list.hasClients) {
      // Not built yet: jump near it, then bring it in.
      _list.jumpTo((i * 56.0).clamp(0, _list.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(i, again: false),
      );
    }
  }

  /// The index of the event picked out in the list, if any.
  int? _selected;
  String? _track;
  List<String> get _tracks =>
      widget.tracks.values.expand((t) => t).toSet().toList();
  List<SequenceMapStop> get _stops => [
    for (final s in widget.stops)
      if (_track == null || (widget.tracks[s.event]?.contains(_track) ?? false))
        s,
  ];
  static int _nextJourneyRequest = 0x53000000;
  StreamSubscription<RustSignalPack<Journeys>>? _journeySub;
  List<JourneyEntry> _journeys = const [];

  @override
  void initState() {
    super.initState();
    _track = _tracks.contains(widget.initialTrack) ? widget.initialTrack : null;
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
    _list.dispose();
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
    final stops = _stops;
    for (var j = i - 1; j >= 0; j--) {
      if (stops[j].places.isEmpty) continue;
      final tracks = widget.tracks[stops[i].event] ?? const <String>[];
      if (_tracks.isNotEmpty &&
          !tracks.any(
            (t) =>
                (_track == null || t == _track) &&
                (widget.tracks[stops[j].event]?.contains(t) ?? false),
          )) {
        continue;
      }
      if (widget.knownBefore(stops[j].event, stops[i].event)) return j;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stops = _stops;
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
    // A chronological edge can synchronise two people without being travel.
    // Build each person's path independently, including shared events in both.
    final seen = <(int, int)>{};
    for (final track in (_tracks.isEmpty ? [''] : _tracks).where(
      (t) => _track == null || t == _track,
    )) {
      final color = _colorOf(track);
      int? last;
      for (final (i, stop) in stops.indexed) {
        if (_tracks.isNotEmpty &&
            !(widget.tracks[stop.event]?.contains(track) ?? false)) {
          continue;
        }
        final place = stop.places.firstOrNull;
        if (place == null) continue;
        final previous = last == null ? null : stops[last].places.last;
        if (previous != null &&
            previous.place.id != place.place.id &&
            widget.knownBefore(stops[last!].event, stop.event)) {
          final isWay = way != null && last == from && i == selected;
          wayDrawn |= isWay;
          if (seen.add((last, i))) {
            legs.addAll(
              _connection(
                previous,
                place,
                isWay,
                stops[last].event,
                stop.event,
              ).map((l) => l.withColor(color)),
            );
          }
        }
        last = i;
      }
    }
    if (way != null && !wayDrawn) {
      legs.addAll(
        _connection(
          fromPlace!,
          picked!,
          true,
          stops[from!].event,
          stops[selected!].event,
        ).map((l) => l.withColor(_eventColor(stops[selected].event))),
      );
    }
    // Each event's own route, from place to place in the order it lists them.
    for (final (i, stop) in stops.indexed) {
      for (var k = 1; k < stop.places.length; k++) {
        final a = stop.places[k - 1], b = stop.places[k];
        if (a.place.id == b.place.id) continue;
        final color = _eventColor(stop.event);
        legs.addAll(
          _connection(
            a,
            b,
            i == selected,
            stop.event,
            stop.event,
          ).map((l) => l.withColor(color)),
        );
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
    final back = _step(false), next = _step(true);
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const ValueKey('sequence-map-back'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous event',
            onPressed: back == null ? null : () => _pick(back),
          ),
          IconButton(
            key: const ValueKey('sequence-map-next'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next event',
            onPressed: next == null ? null : () => _pick(next),
          ),
        ],
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
          if (_tracks.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (final track in [null, ..._tracks])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('map-track-${track ?? "all"}'),
                        avatar: track == null
                            ? null
                            : CircleAvatar(backgroundColor: _colorOf(track)),
                        label: Text(track ?? 'All tracks'),
                        selected: _track == track,
                        onSelected: (_) => setState(() {
                          _track = track;
                          _selected = null;
                          _tileKeys.clear();
                        }),
                      ),
                    ),
                ],
              ),
            ),
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
                    fitFocus: true,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _tracks.isEmpty
                  ? 'Lines connect known, ordered event locations. Tap an event to see its place.'
                  : 'Lines follow the same person between known, ordered locations. '
                        'Timing links between people are kept in the sequence. '
                        'Tap an event to see its place and route.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.builder(
              controller: _list,
              itemCount: stops.length,
              itemBuilder: (context, i) {
                final stop = stops[i];
                final places = stop.places.map((p) => p.label).join(', ');
                return KeyedSubtree(
                  key: _tileKeys.putIfAbsent(i, GlobalKey.new),
                  child: ListTile(
                    key: ValueKey('sequence-map-stop-${stop.event}'),
                    dense: true,
                    selected: _selected == i,
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    title: Text(stop.title),
                    subtitle: Text(
                      [
                        ...(widget.tracks[stop.event] ?? const <String>[]),
                        places.isEmpty ? 'No place told' : places,
                      ].join(' · '),
                    ),
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
