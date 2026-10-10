import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'name_details.dart';
import 'place_map.dart';

/// The kinds of place the gazetteer narrows to, each gathering OpenBible.info's
/// finer kinds.
enum PlaceKindFilter {
  all('All'),
  settlements('Settlements'),
  regions('Regions'),
  water('Water'),
  mountains('Mountains'),
  valleys('Valleys'),
  other('Other');

  const PlaceKindFilter(this.label);

  final String label;

  static PlaceKindFilter of(String kind) => switch (kind) {
    'settlement' ||
    'district in settlement' ||
    'fortification' ||
    'campsite' ||
    'structure' ||
    'gate' ||
    'hall' ||
    'room' => settlements,
    'region' ||
    'island' ||
    'natural area' ||
    'people group' ||
    'field' ||
    'garden' ||
    'forest' => regions,
    'river' ||
    'body of water' ||
    'spring' ||
    'well' ||
    'wadi' ||
    'pool' ||
    'canal' => water,
    'mountain' ||
    'hill' ||
    'mountain range' ||
    'mountain ridge' ||
    'mountain pass' ||
    'cliff' ||
    'promontory' => mountains,
    'valley' => valleys,
    _ => other,
  };

  bool matches(String kind) => this == all || of(kind) == this;
}

/// How the gazetteer orders its places.
enum PlaceOrder { name, mentions }

/// Text as a search compares it: lower case, without Hebrew points and
/// accents, hyphens, spaces or apostrophes, so "beth lehem" finds Beth-lehem
/// and בית לחם finds בֵּית לֶ֫חֶם.
String placeSearchKey(String text) => text.toLowerCase().replaceAll(
  RegExp('[\u0591-\u05C7\u05F3\u05F4\\-\u2010\u2011 \'\u2019]'),
  '',
);

/// Every place with a known position, to search by name in English or
/// Hebrew and narrow by region and kind, on a map and in a list. Tapping a
/// place opens its page.
class PlacesPage extends StatefulWidget {
  const PlacesPage({
    super.key,
    this.useEnglishBookNames = false,
    this.onNavigateToPassage,
    this.bookmarks,
    this.sendRequest,
    this.sendJourneysRequest,
    this.basemap,
  });

  final bool useEnglishBookNames;
  final void Function(int bookIndex, int chapter, int verse)?
  onNavigateToPassage;
  final NameBookmarks? bookmarks;

  /// Stand in for the signals to Rust, for tests.
  final void Function(GetPlaces)? sendRequest;
  final void Function(GetJourneys)? sendJourneysRequest;
  final Basemap? basemap;

  static Future<void> open(
    BuildContext context, {
    bool useEnglishBookNames = false,
    void Function(int bookIndex, int chapter, int verse)? onNavigateToPassage,
    NameBookmarks? bookmarks,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlacesPage(
        useEnglishBookNames: useEnglishBookNames,
        onNavigateToPassage: onNavigateToPassage,
        bookmarks: bookmarks,
      ),
    ),
  );

  @override
  State<PlacesPage> createState() => _PlacesPageState();
}

class _PlacesPageState extends State<PlacesPage> {
  static int _nextRequestId = 1;
  StreamSubscription<RustSignalPack<Places>>? _sub;
  int? _requestId;
  Places? _places;
  StreamSubscription<RustSignalPack<Journeys>>? _journeysSub;
  int? _journeysRequestId;
  List<JourneyEntry> _journeys = const [];

  /// Each place's search keys, its name's first.
  final _keys = <int, List<String>>{};
  final _regionNames = <int, String>{};

  /// The journeys passing each place, in order.
  final _journeysOf = <int, List<JourneyEntry>>{};

  final _search = TextEditingController();
  String _query = '';
  int? _region;
  PlaceKindFilter _kind = PlaceKindFilter.all;
  PlaceOrder _order = PlaceOrder.name;

  /// The journey shown in place of the list of places, if any.
  JourneyEntry? _journey;

  @override
  void initState() {
    super.initState();
    _journeysSub = Journeys.rustSignalStream.listen((pack) {
      final journeys = pack.message;
      if (!mounted || journeys.requestId != _journeysRequestId) return;
      setState(() {
        _journeys = journeys.journeys;
        _journeysOf.clear();
        for (final journey in _journeys) {
          for (final id in {for (final s in journey.stops) s.place.id}) {
            (_journeysOf[id] ??= []).add(journey);
          }
        }
      });
    });
    final journeysRequest = GetJourneys(
      requestId: _journeysRequestId = _nextRequestId++,
    );
    final sendJourneys = widget.sendJourneysRequest;
    if (sendJourneys != null) {
      sendJourneys(journeysRequest);
    } else {
      journeysRequest.sendSignalToRust();
    }
    _sub = Places.rustSignalStream.listen((pack) {
      final places = pack.message;
      if (!mounted || places.requestId != _requestId) return;
      setState(() {
        _places = places;
        _keys
          ..clear()
          ..addAll({
            for (final p in places.places)
              p.place.id: [
                placeSearchKey(p.place.name),
                for (final name in p.otherNames) placeSearchKey(name),
              ],
          });
        _regionNames
          ..clear()
          ..addAll({for (final r in places.regions) r.id: r.name});
      });
    });
    final request = GetPlaces(requestId: _requestId = _nextRequestId++);
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _journeysSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The places the search and filters leave, in the chosen order; while
  /// searching, those whose name begins with the search first.
  List<PlaceListEntry> _shown(Places places) {
    final query = placeSearchKey(_query);
    final shown = [
      for (final p in places.places)
        if (_kind.matches(p.location.kind) &&
            (_region == null || p.regions.contains(_region)) &&
            (query.isEmpty || _keys[p.place.id]!.any((k) => k.contains(query))))
          p,
    ];
    int rank(PlaceListEntry p) {
      if (query.isEmpty) return 0;
      final keys = _keys[p.place.id]!;
      if (keys.first.startsWith(query)) return 0;
      return keys.any((k) => k.startsWith(query)) ? 1 : 2;
    }

    final ordered = [for (final (i, p) in shown.indexed) (i, rank(p), p)];
    ordered.sort((a, b) {
      final byRank = a.$2.compareTo(b.$2);
      if (byRank != 0) return byRank;
      if (_order == PlaceOrder.mentions) {
        final byMentions = b.$3.place.occurrences.compareTo(
          a.$3.place.occurrences,
        );
        if (byMentions != 0) return byMentions;
      }
      return a.$1.compareTo(b.$1);
    });
    return [for (final (_, _, p) in ordered) p];
  }

  void _open(NameSummaryEntry place) => NameDetailsPage.open(
    context,
    id: place.id,
    title: place.name,
    useEnglishBookNames: widget.useEnglishBookNames,
    bookmarks: widget.bookmarks,
    onNavigateToPassage: widget.onNavigateToPassage == null
        ? null
        : (book, chapter, verse) {
            Navigator.of(context).maybePop();
            widget.onNavigateToPassage!(book, chapter, verse);
          },
  );

  /// The places on the map: regions drawn as ground only when regions are
  /// asked for or one is chosen, or the map would be all tint.
  List<MapPin> _pins(Places places, List<PlaceListEntry> shown) {
    final region = _region;
    return [
      if (region != null && _kind != PlaceKindFilter.regions)
        for (final p in places.places)
          if (p.place.id == region)
            placePin(p.location, label: p.place.name, id: p.place.id),
      for (final p in shown)
        if (_kind == PlaceKindFilter.regions ||
            PlaceKindFilter.of(p.location.kind) != PlaceKindFilter.regions)
          // Among all kinds, the seas' outlines would cover the map: a
          // place's ground is drawn once its kind is chosen.
          _kind == PlaceKindFilter.all
              ? placePin(
                  PlaceLocationEntry(
                    latitude: p.location.latitude,
                    longitude: p.location.longitude,
                    confidence: p.location.confidence,
                    kind: p.location.kind,
                    label: p.location.label,
                    area: const [],
                    line: p.location.line,
                    estimated: p.location.estimated,
                  ),
                  label: p.place.name,
                  id: p.place.id,
                )
              : placePin(p.location, label: p.place.name, id: p.place.id),
    ];
  }

  String _subtitle(PlaceListEntry p) {
    final kind = p.location.kind;
    final label = p.location.label;
    return [
      if (kind.isNotEmpty) kind,
      for (final id in p.regions) ?_regionNames[id],
      if (label.isNotEmpty && label != p.place.name) label,
      if (p.location.estimated) 'low certainty',
      if (p.place.occurrences > 0) mentionsLabel(p.place.occurrences),
      ?_onJourneys(p.place.id),
    ].join(' · ');
  }

  /// The journeys passing a place, by name while there are two at most.
  String? _onJourneys(int id) {
    final journeys = _journeysOf[id] ?? const [];
    return switch (journeys.length) {
      0 => null,
      1 || 2 => 'On ${journeys.map((j) => j.name).join(' and ')}',
      final n => 'On $n journeys',
    };
  }

  /// A stop's verse: "Acts 13:4".
  String _verseLabel(JourneyStopEntry stop) =>
      '${bookDisplayName(stop.book - 1, useEnglish: widget.useEnglishBookNames)} '
      '${stop.chapter}:${stop.verse}';

  void _read(JourneyStopEntry stop) {
    Navigator.of(context).maybePop();
    widget.onNavigateToPassage!(stop.book - 1, stop.chapter, stop.verse);
  }

  /// A journey's places on the map, each once, and its legs between the
  /// stops it draws: a stop with no site is passed over.
  (List<MapPin>, List<MapLeg>) _journeyMap(JourneyEntry journey) {
    final drawn = [
      for (final s in journey.stops)
        if (s.drawn) s,
    ];
    final seen = <int>{};
    final pins = [
      for (final s in drawn)
        if (seen.add(s.place.id))
          placePin(s.location, label: s.label, id: s.place.id),
    ];
    final legs = [
      for (var i = 0; i + 1 < drawn.length; i++)
        MapLeg([
          drawn[i].location.longitude,
          drawn[i].location.latitude,
          ...drawn[i + 1].via,
          drawn[i + 1].location.longitude,
          drawn[i + 1].location.latitude,
        ], bySea: drawn[i + 1].bySea),
    ];
    return (pins, legs);
  }

  /// A journey's stops in order, under what it is.
  Widget _journeyList(JourneyEntry journey) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = placeSearchKey(_query);
    final stops = [
      for (final (i, s) in journey.stops.indexed)
        if (query.isEmpty ||
            placeSearchKey(s.label).contains(query) ||
            (_keys[s.place.id] ?? const []).any((k) => k.contains(query)))
          (i, s),
    ];
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(journey.summary, style: theme.textTheme.bodyMedium),
        ),
        for (final (i, s) in stops)
          ListTile(
            key: ValueKey('stop-$i'),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: s.drawn
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor: s.drawn
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              child: Text('${i + 1}', style: theme.textTheme.labelMedium),
            ),
            title: Text(s.label),
            subtitle: Text(
              [
                [
                  if (s.label != s.place.name) s.place.name,
                  _verseLabel(s),
                  if (s.bySea) 'by sea',
                  if (!s.drawn) 'not on the map',
                  if (s.drawn && s.location.estimated) 'low certainty',
                ].join(' · '),
                if (s.note.isNotEmpty) s.note,
              ].join('\n'),
            ),
            isThreeLine: s.note.isNotEmpty,
            trailing: widget.onNavigateToPassage == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.menu_book_outlined),
                    tooltip: 'Read ${_verseLabel(s)}',
                    onPressed: () => _read(s),
                  ),
            onTap: () => _open(s.place),
          ),
      ],
    );
  }

  /// The journey filter: none, or one journey, the Old Testament's before
  /// the New's.
  Widget _journeyButton() {
    final journey = _journey;
    final theme = Theme.of(context);
    Widget heading(String text) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.primary,
      ),
    );
    final old = [
      for (final j in _journeys)
        if (j.stops.first.book < 40) j,
    ];
    final newer = [
      for (final j in _journeys)
        if (j.stops.first.book >= 40) j,
    ];
    return PopupMenuButton<int>(
      key: const ValueKey('places-journey'),
      tooltip: 'Journeys',
      enabled: _journeys.isNotEmpty,
      onSelected: (id) => setState(() {
        _journey = id < 0 ? null : _journeys.firstWhere((j) => j.id == id);
      }),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: -1,
          checked: journey == null,
          child: const Text('No journey'),
        ),
        for (final (title, journeys) in [
          ('Old Testament', old),
          ('New Testament', newer),
        ])
          if (journeys.isNotEmpty) ...[
            const PopupMenuDivider(),
            PopupMenuItem(enabled: false, height: 32, child: heading(title)),
            for (final j in journeys)
              CheckedPopupMenuItem(
                value: j.id,
                checked: journey?.id == j.id,
                child: Text(j.name),
              ),
          ],
      ],
      child: Chip(
        avatar: const Icon(Icons.route, size: 18),
        label: Text(journey?.name ?? 'Journeys'),
        backgroundColor: journey == null
            ? null
            : theme.colorScheme.secondaryContainer,
        onDeleted: journey == null
            ? null
            : () => setState(() => _journey = null),
        deleteButtonTooltipMessage: 'No journey',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final places = _places;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible places'),
        actions: [
          PopupMenuButton<PlaceOrder>(
            key: const ValueKey('places-order'),
            icon: const Icon(Icons.sort),
            tooltip: 'Order',
            onSelected: (order) => setState(() => _order = order),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: PlaceOrder.name,
                checked: _order == PlaceOrder.name,
                child: const Text('By name'),
              ),
              CheckedPopupMenuItem(
                value: PlaceOrder.mentions,
                checked: _order == PlaceOrder.mentions,
                child: const Text('Most named first'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: places == null
            ? const Center(child: CircularProgressIndicator())
            : places.places.isEmpty
            ? const Center(child: Text('No places are known to this build.'))
            : _body(places),
      ),
    );
  }

  Widget _body(Places places) {
    final theme = Theme.of(context);
    final journey = _journey;
    final shown = _shown(places);
    final (pins, legs) = journey == null
        ? (_pins(places, shown), const <MapLeg>[])
        : _journeyMap(journey);
    final map = PlaceMap(
      basemap: widget.basemap,
      pins: pins,
      legs: legs,
      onPinTap: (pin) => _open(
        journey == null
            ? places.places.firstWhere((p) => p.place.id == pin.id).place
            : journey.stops.firstWhere((s) => s.place.id == pin.id).place,
      ),
    );
    final list = journey != null
        ? _journeyList(journey)
        : shown.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No place matches.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        : ListView.builder(
            itemCount: shown.length,
            itemBuilder: (context, i) {
              final p = shown[i];
              return ListTile(
                key: ValueKey('place-${p.place.id}'),
                leading: Icon(
                  PlaceKindFilter.of(p.location.kind) == PlaceKindFilter.regions
                      ? Icons.terrain_outlined
                      : Icons.place_outlined,
                ),
                title: Text(p.place.name),
                subtitle: Text(_subtitle(p)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(p.place),
              );
            },
          );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const ValueKey('places-search'),
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search places, in English or Hebrew',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear',
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (text) => setState(() => _query = text),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _journeyButton(),
              // A journey's stops are its own; the filters are for places.
              if (journey == null) ...[
                const SizedBox(width: 8),
                _regionButton(places),
                const SizedBox(width: 8),
                for (final kind in PlaceKindFilter.values) ...[
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
          child: Text(
            journey != null
                ? '${journey.stops.length} stops'
                : '${shown.length} place${shown.length == 1 ? '' : 's'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: map),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    controls,
                    Expanded(child: list),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            controls,
            Expanded(flex: 2, child: map),
            const Divider(height: 1),
            Expanded(flex: 3, child: list),
          ],
        );
      },
    );
  }

  /// The region filter: all, or one region of a group, the groups in the
  /// order Rust gives them.
  Widget _regionButton(Places places) {
    final region = _region;
    final groups = <String, List<PlaceRegionEntry>>{};
    for (final r in places.regions) {
      (groups[r.group] ??= []).add(r);
    }
    final theme = Theme.of(context);
    return PopupMenuButton<int>(
      key: const ValueKey('places-region'),
      tooltip: 'Region',
      onSelected: (id) => setState(() => _region = id < 0 ? null : id),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: -1,
          checked: region == null,
          child: const Text('All regions'),
        ),
        for (final MapEntry(key: group, value: regions) in groups.entries) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              group,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final r in regions)
            CheckedPopupMenuItem(
              value: r.id,
              checked: region == r.id,
              child: Text(r.name),
            ),
        ],
      ],
      // The menu opens on a tap; the chip only shows the choice.
      child: Chip(
        avatar: const Icon(Icons.public, size: 18),
        label: Text(
          region == null ? 'All regions' : _regionNames[region] ?? 'Region',
        ),
        backgroundColor: region == null
            ? null
            : theme.colorScheme.secondaryContainer,
        onDeleted: region == null ? null : () => setState(() => _region = null),
        deleteButtonTooltipMessage: 'All regions',
      ),
    );
  }
}
