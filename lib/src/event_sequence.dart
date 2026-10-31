import 'dart:math' as math;

import 'bindings/bindings.dart';

/// The Bible's event sequences together: which sequence holds each event,
/// and which opens where an event is drawn (see [EventSequenceEntry]).
class BibleSequences {
  BibleSequences(this.all)
    : homeOf = {
        for (final s in all)
          for (final e in s.events) e: s,
      },
      expanding = {for (final s in all) ?s.expands: s};

  static final empty = BibleSequences(const []);

  final List<EventSequenceEntry> all;

  /// The sequence each event is in, by event id.
  final Map<int, EventSequenceEntry> homeOf;

  /// The sequence telling the inside of each event that has one.
  final Map<int, EventSequenceEntry> expanding;

  /// The sequences from the outermost to the one holding [event], each
  /// opened from an event of the one before; empty for an event in none.
  List<EventSequenceEntry> pathTo(int event) {
    final path = <EventSequenceEntry>[];
    var at = homeOf[event];
    while (at != null && !path.contains(at)) {
      path.insert(0, at);
      at = switch (at.expands) {
        final e? => homeOf[e],
        null => null,
      };
    }
    return path;
  }
}

/// How the edges of a sequence order its events, and where each is drawn:
/// in rows, every event below all those known to come before it, with the
/// edges no other route implies.
class SequenceGraph {
  SequenceGraph(this.sequence) : events = List.unmodifiable(sequence.events) {
    final members = events.toSet();
    for (final e in events) {
      _next[e] = {};
      _prev[e] = {};
    }
    for (final edge in sequence.edges) {
      if (!members.contains(edge.before) || !members.contains(edge.after)) {
        continue;
      }
      _next[edge.before]!.add(edge.after);
      _prev[edge.after]!.add(edge.before);
      (_bases[(edge.before, edge.after)] ??= []).addAll(edge.bases);
    }
    _after = _closure(_next);
    _before = _closure(_prev);
    _layout();
  }

  final EventSequenceEntry sequence;

  /// Its events, by id, in time order.
  final List<int> events;

  final _next = <int, Set<int>>{};
  final _prev = <int, Set<int>>{};
  final _bases = <(int, int), List<String>>{};
  late final Map<int, Set<int>> _after;
  late final Map<int, Set<int>> _before;

  /// The events known to come before [event], or after it, by any route.
  Set<int> before(int event) => _before[event] ?? const {};
  Set<int> after(int event) => _after[event] ?? const {};

  /// The events said directly to come before [event], or after it, with
  /// what says so.
  List<(int, List<String>)> directlyBefore(int event) => [
    for (final e in events)
      if (_prev[event]?.contains(e) ?? false) (e, _bases[(e, event)]!),
  ];
  List<(int, List<String>)> directlyAfter(int event) => [
    for (final e in events)
      if (_next[event]?.contains(e) ?? false) (e, _bases[(event, e)]!),
  ];

  /// The events whose order to [event] is unknown.
  int unorderedWith(int event) =>
      events.length - 1 - before(event).length - after(event).length;

  /// The edges drawn: those no longer route between their events implies.
  late final List<(int, int)> drawnEdges = [
    for (final u in events)
      for (final v in _next[u]!)
        if (!_next[u]!.any((w) => w != v && after(w).contains(v))) (u, v),
  ];

  /// The rows the events are drawn in, top to bottom, each left to right.
  late final List<List<int>> rows;

  /// Where each event is drawn: its row, and how far across in slots from
  /// the left (fractional, so a chain stays straight).
  final row = <int, int>{};
  final column = <int, double>{};

  /// How many slots wide the rows are.
  double width = 1;

  static Map<int, Set<int>> _closure(Map<int, Set<int>> step) {
    final reach = <int, Set<int>>{};
    Set<int> from(int e, Set<int> visiting) {
      if (reach[e] case final r?) return r;
      final out = <int>{};
      visiting.add(e);
      for (final n in step[e]!) {
        if (visiting.contains(n)) continue;
        out
          ..add(n)
          ..addAll(from(n, visiting));
      }
      visiting.remove(e);
      return reach[e] = out;
    }

    for (final e in step.keys) {
      from(e, {});
    }
    return reach;
  }

  void _layout() {
    // Rows: each event one below the lowest of those before it, taking
    // events in time order where none is ordered before another.
    final waiting = {for (final e in events) e: _prev[e]!.length};
    final ready = [
      for (final e in events)
        if (waiting[e] == 0) e,
    ];
    final timeOrder = {for (final (i, e) in events.indexed) e: i};
    while (ready.isNotEmpty) {
      ready.sort((a, b) => timeOrder[a]!.compareTo(timeOrder[b]!));
      final e = ready.removeAt(0);
      row[e] = _prev[e]!.map((p) => row[p]! + 1).fold(0, math.max);
      for (final n in _next[e]!) {
        if ((waiting[n] = waiting[n]! - 1) == 0) ready.add(n);
      }
    }
    // A circle (which the data's build forbids) leaves its events at the
    // bottom rather than out.
    final deepest = row.values.fold(0, math.max);
    for (final e in events) {
      row.putIfAbsent(e, () => deepest + 1);
    }
    final count = row.values.fold(0, math.max) + 1;
    final built = List.generate(count, (_) => <int>[]);
    for (final e in events) {
      built[row[e]!].add(e);
    }

    // Across: each row ordered by where its neighbours on the drawn edges
    // are, sweeping down and up, so that edges cross less.
    final up = <int, List<int>>{};
    final down = <int, List<int>>{};
    for (final (u, v) in drawnEdges) {
      (down[u] ??= []).add(v);
      (up[v] ??= []).add(u);
    }
    void place() {
      for (final r in built) {
        for (final (i, e) in r.indexed) {
          column[e] = i - (r.length - 1) / 2;
        }
      }
    }

    place();
    double? centre(int e, Map<int, List<int>> by) {
      final near = by[e];
      if (near == null || near.isEmpty) return null;
      return near.map((n) => column[n]!).reduce((a, b) => a + b) / near.length;
    }

    for (var sweep = 0; sweep < 6; sweep++) {
      final downward = sweep.isEven;
      final order = downward ? built : built.reversed;
      for (final r in order) {
        final key = {
          for (final e in r) e: centre(e, downward ? up : down) ?? column[e]!,
        };
        _stableSort(r, (a, b) => key[a]!.compareTo(key[b]!));
        for (final (i, e) in r.indexed) {
          column[e] = i - (r.length - 1) / 2;
        }
      }
    }

    // Then each event moved towards its neighbours, keeping a slot apart
    // from the next in its row, so that a chain runs straight down.
    for (var pass = 0; pass < 4; pass++) {
      for (final r in built) {
        final want = [
          for (final e in r)
            switch ((centre(e, up), centre(e, down))) {
              (final a?, final b?) => (a + b) / 2,
              (final a?, null) => a,
              (null, final b?) => b,
              (null, null) => column[e]!,
            },
        ];
        // Left to right at least a slot apart, then shifted so that the
        // row sits where its events want on average.
        final placed = <double>[];
        for (final w in want) {
          placed.add(placed.isEmpty ? w : math.max(w, placed.last + 1));
        }
        final shift =
            (want.reduce((a, b) => a + b) - placed.reduce((a, b) => a + b)) /
            want.length;
        for (final (i, e) in r.indexed) {
          column[e] = placed[i] + shift;
        }
      }
    }
    final left = column.values.fold(double.infinity, math.min);
    final right = column.values.fold(double.negativeInfinity, math.max);
    for (final e in events) {
      column[e] = column[e]! - left;
    }
    width = events.isEmpty ? 1 : right - left + 1;
    rows = built;
  }
}

/// A stable sort, so that events of equal weight keep their order.
void _stableSort<T>(List<T> list, int Function(T, T) compare) {
  final indexed = list.indexed.toList()
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  list
    ..clear()
    ..addAll(indexed.map((p) => p.$2));
}
