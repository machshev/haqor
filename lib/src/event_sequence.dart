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

/// A grouping of a sequence's events (see [SequenceGroupingEntry]) as a
/// tree: each group's children, and the group each event is in.
class GroupingTree {
  GroupingTree(this.grouping) {
    for (final (i, g) in grouping.groups.indexed) {
      final parent = g.parent;
      if (parent == null) {
        top.add(i);
      } else {
        (_children[parent] ??= []).add(i);
      }
      for (final e in g.events) {
        leafOf[e] = i;
      }
    }
  }

  final SequenceGroupingEntry grouping;

  /// The groups at the top, in order.
  final top = <int>[];
  final _children = <int, List<int>>{};

  /// The group holding each event, by event id.
  final leafOf = <int, int>{};

  SequenceGroupEntry operator [](int group) => grouping.groups[group];

  /// The groups inside [group], in order; empty for one holding events.
  List<int> children(int group) => _children[group] ?? const [];

  /// The groups from the top down to [group], [group] last.
  List<int> pathTo(int group) {
    final path = <int>[];
    int? at = group;
    while (at != null && !path.contains(at)) {
      path.insert(0, at);
      at = grouping.groups[at].parent;
    }
    return path;
  }

  /// How deep [group] lies: 0 at the top.
  int depth(int group) => pathTo(group).length - 1;

  /// Every event in [group] and the groups inside it, in the sequence's
  /// order as the groups give it.
  List<int> eventsOf(int group) => [
    ...grouping.groups[group].events,
    for (final c in children(group)) ...eventsOf(c),
  ];
}

/// The node of a folded group in a [SequenceGraph]: negative, so that it is
/// told from an event's id.
int groupNode(int group) => -group - 1;

/// The group a node stands for, or null for an event.
int? nodeGroup(int node) => node < 0 ? -node - 1 : null;

/// How the edges of a sequence order its events, and where each is drawn:
/// in rows, every event below all those known to come before it, with the
/// edges no other route implies.
///
/// Drawn by a [grouping], the groups not [expanded] are folded each into one
/// node (see [groupNode]), with the orderings of their events; an unfolded
/// group's events, or its unfolded groups, take rows of their own below
/// those of the groups before it. With [laneOf], each node is drawn in a
/// lane, its lanes side by side across the rows.
class SequenceGraph {
  SequenceGraph(
    this.sequence, {
    this.grouping,
    Set<int> expanded = const {},
    int? Function(int node)? laneOf,
  }) {
    final timeOrder = {for (final (i, e) in sequence.events.indexed) e: i};
    final tree = grouping;

    // The bands of nodes, in order: a folded group alone, or the events of
    // an unfolded one.
    final bands = <List<int>>[];
    void walk(int group) {
      if (!expanded.contains(group)) {
        bands.add([groupNode(group)]);
      } else if (tree!.children(group).isNotEmpty) {
        tree.children(group).forEach(walk);
      } else {
        bands.add(List.of(tree[group].events));
      }
    }

    if (tree == null) {
      bands.add(List.of(sequence.events));
    } else {
      tree.top.forEach(walk);
      // Any event no group holds, at the end.
      final grouped = tree.leafOf.keys.toSet();
      final rest = [
        for (final e in sequence.events)
          if (!grouped.contains(e)) e,
      ];
      if (rest.isNotEmpty) bands.add(rest);
    }
    events = List.unmodifiable([for (final b in bands) ...b]);

    // Each event's node: itself, or the outermost folded group holding it.
    for (final e in sequence.events) {
      var node = e;
      final leaf = tree?.leafOf[e];
      if (leaf != null) {
        for (final g in tree!.pathTo(leaf)) {
          if (!expanded.contains(g)) {
            node = groupNode(g);
            break;
          }
        }
      }
      nodeOf[e] = node;
    }
    for (final n in events) {
      _next[n] = {};
      _prev[n] = {};
      _timeOrder[n] = switch (nodeGroup(n)) {
        final g? =>
          tree!
              .eventsOf(g)
              .map((e) => timeOrder[e] ?? 0)
              .fold(1 << 30, math.min),
        null => timeOrder[n] ?? 0,
      };
    }
    for (final edge in sequence.edges) {
      final (u, v) = (nodeOf[edge.before], nodeOf[edge.after]);
      if (u == null || v == null || u == v) continue;
      _next[u]!.add(v);
      _prev[v]!.add(u);
      final bases = _bases[(u, v)] ??= [];
      for (final b in edge.bases) {
        if (!bases.contains(b)) bases.add(b);
      }
    }
    _after = _closure(_next);
    _before = _closure(_prev);
    _layout(bands, laneOf);
  }

  final EventSequenceEntry sequence;
  final GroupingTree? grouping;

  /// Its nodes, in the order of their bands: its events, and with a
  /// [grouping] its folded groups (see [groupNode]).
  late final List<int> events;

  /// The node each of the sequence's events is drawn as: itself, or the
  /// folded group holding it.
  final nodeOf = <int, int>{};

  final _next = <int, Set<int>>{};
  final _prev = <int, Set<int>>{};
  final _bases = <(int, int), List<String>>{};
  final _timeOrder = <int, int>{};
  late final Map<int, Set<int>> _after;
  late final Map<int, Set<int>> _before;

  /// The nodes known to come before [event], or after it, by any route.
  Set<int> before(int event) => _before[event] ?? const {};
  Set<int> after(int event) => _after[event] ?? const {};

  /// The nodes said directly to come before [event], or after it, with
  /// what says so.
  List<(int, List<String>)> directlyBefore(int event) => [
    for (final e in events)
      if (_prev[event]?.contains(e) ?? false) (e, _bases[(e, event)]!),
  ];
  List<(int, List<String>)> directlyAfter(int event) => [
    for (final e in events)
      if (_next[event]?.contains(e) ?? false) (e, _bases[(event, e)]!),
  ];

  /// The nodes whose order to [event] is unknown.
  int unorderedWith(int event) =>
      events.length - 1 - before(event).length - after(event).length;

  /// The edges drawn: those no longer route between their nodes implies.
  late final List<(int, int)> drawnEdges = [
    for (final u in events)
      for (final v in _next[u]!)
        if (!_next[u]!.any((w) => w != v && after(w).contains(v))) (u, v),
  ];

  /// The drawn edges joining one to one: from a node leading to no other
  /// to one following no other, in the row straight after.
  late final Set<(int, int)> oneToOne = () {
    final outs = <int, int>{};
    final ins = <int, int>{};
    for (final (u, v) in drawnEdges) {
      outs[u] = (outs[u] ?? 0) + 1;
      ins[v] = (ins[v] ?? 0) + 1;
    }
    return {
      for (final (u, v) in drawnEdges)
        if (outs[u] == 1 && ins[v] == 1 && row[v] == row[u]! + 1) (u, v),
    };
  }();

  /// The rows the nodes are drawn in, top to bottom, each left to right.
  late final List<List<int>> rows;

  /// Where each node is drawn: its row, and how far across in slots from
  /// the left (fractional, so a chain stays straight).
  final row = <int, int>{};
  final column = <int, double>{};

  /// How many slots wide the rows are.
  double width = 1;

  /// With lanes, where each lane in use lies across, in slots: from its
  /// start, so wide; in the order of the lanes.
  final lanes = <({int lane, double start, double width})>[];

  /// The rows each unfolded group's nodes lie in, from first to last, by
  /// group; with a [grouping] only.
  final groupRows = <int, (int, int)>{};

  /// Every event of the sequence in the order it is drawn: by row, then
  /// across.
  List<int> get drawnOrder {
    final order = [...events]
      ..sort((a, b) {
        final r = row[a]!.compareTo(row[b]!);
        return r != 0 ? r : column[a]!.compareTo(column[b]!);
      });
    return order;
  }

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

  void _layout(List<List<int>> bands, int? Function(int node)? laneOf) {
    // Rows: band by band, each node one below the lowest of those before it
    // and below every band before its own, taking nodes in time order where
    // none is ordered before another.
    var start = 0;
    for (final band in bands) {
      final members = band.toSet();
      final waiting = {
        for (final e in band) e: _prev[e]!.where(members.contains).length,
      };
      final ready = [
        for (final e in band)
          if (waiting[e] == 0) e,
      ];
      while (ready.isNotEmpty) {
        ready.sort((a, b) => _timeOrder[a]!.compareTo(_timeOrder[b]!));
        final e = ready.removeAt(0);
        row[e] = _prev[e]!
            .where(row.containsKey)
            .map((p) => row[p]! + 1)
            .fold(start, math.max);
        for (final n in _next[e]!) {
          if (!members.contains(n)) continue;
          if ((waiting[n] = waiting[n]! - 1) == 0) ready.add(n);
        }
      }
      // A circle (which the data's build forbids) leaves its nodes at the
      // band's bottom rather than out.
      final deepest = band.map((e) => row[e] ?? start).fold(start, math.max);
      for (final e in band) {
        row.putIfAbsent(e, () => deepest + 1);
      }
      start = band.map((e) => row[e]!).fold(start - 1, math.max) + 1;
    }
    final count = row.values.fold(0, math.max) + 1;
    final built = List.generate(count, (_) => <int>[]);
    for (final e in events) {
      built[row[e]!].add(e);
    }

    // The rows of each unfolded group: those of its events, and of the
    // groups inside it.
    final tree = grouping;
    if (tree != null) {
      for (final e in events) {
        final r = row[e]!;
        final leaf = switch (nodeGroup(e)) {
          final g? => tree[g].parent,
          null => tree.leafOf[e],
        };
        if (leaf == null) continue;
        for (final g in tree.pathTo(leaf)) {
          final (first, last) = groupRows[g] ?? (r, r);
          groupRows[g] = (math.min(first, r), math.max(last, r));
        }
      }
    }

    // Across: each row ordered by where its neighbours on the drawn edges
    // are, sweeping down and up, so that edges cross less.
    final up = <int, List<int>>{};
    final down = <int, List<int>>{};
    for (final (u, v) in drawnEdges) {
      (down[u] ??= []).add(v);
      (up[v] ??= []).add(u);
    }
    for (final r in built) {
      for (final (i, e) in r.indexed) {
        column[e] = i - (r.length - 1) / 2;
      }
    }
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

    if (laneOf != null) {
      _laneLayout(built, laneOf);
      rows = built;
      return;
    }

    // Then each node moved towards its neighbours, keeping a slot apart
    // from the next in its row, so that a chain runs straight down.
    for (var pass = 0; pass < 4; pass++) {
      for (final r in built) {
        if (r.isEmpty) continue;
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
        // row sits where its nodes want on average.
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
    _straighten(built);
    final left = column.values.fold(double.infinity, math.min);
    final right = column.values.fold(double.negativeInfinity, math.max);
    for (final e in events) {
      column[e] = column[e]! - left;
    }
    width = events.isEmpty ? 1 : right - left + 1;
    rows = built;
  }

  /// Each run of nodes joined one to one (see [oneToOne]) moved into one
  /// column, so that it can be drawn stacked. Keep the run between its
  /// neighbours in every row, choosing the clear column nearest its mean.
  void _straighten(List<List<int>> built) {
    final next = {for (final (u, v) in oneToOne) u: v};
    final joined = next.values.toSet();
    for (final head in next.keys) {
      if (joined.contains(head)) continue;
      final run = [head];
      for (var n = next[head]; n != null; n = next[n]) {
        run.add(n);
      }
      var left = double.negativeInfinity;
      var right = double.infinity;
      var total = 0.0;
      for (final e in run) {
        final at = column[e]!;
        total += at;
        for (final other in built[row[e]!]) {
          if (other == e) continue;
          final beside = column[other]!;
          if (beside < at) {
            left = math.max(left, beside + 1);
          } else {
            right = math.min(right, beside - 1);
          }
        }
      }
      if (left > right) continue;
      final at = (total / run.length).clamp(left, right).toDouble();
      for (final e in run) {
        column[e] = at;
      }
    }
  }

  /// Each node in its lane: the lanes side by side, each as wide as the
  /// most of its nodes in one row, a row's nodes in a lane centred in it in
  /// the order the sweeps gave them. A node without a lane goes in a lane
  /// after the others.
  void _laneLayout(List<List<int>> built, int? Function(int node) laneOf) {
    final lane = {for (final e in events) e: laneOf(e) ?? 1 << 20};
    final used = lane.values.toSet().toList()..sort();
    final wide = <int, int>{};
    for (final r in built) {
      final count = <int, int>{};
      for (final e in r) {
        count[lane[e]!] = (count[lane[e]!] ?? 0) + 1;
      }
      count.forEach((l, n) => wide[l] = math.max(wide[l] ?? 1, n));
    }
    var at = 0.0;
    final startOf = <int, double>{};
    for (final l in used) {
      startOf[l] = at;
      lanes.add((lane: l, start: at, width: wide[l]!.toDouble()));
      at += wide[l]!;
    }
    for (final r in built) {
      for (final l in used) {
        final inLane = [
          for (final e in r)
            if (lane[e] == l) e,
        ];
        final offset = (wide[l]! - inLane.length) / 2;
        for (final (i, e) in inLane.indexed) {
          column[e] = startOf[l]! + offset + i;
        }
      }
    }
    width = math.max(at, 1);
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
