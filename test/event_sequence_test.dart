import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/event_sequence.dart';

SequenceEdgeEntry _edge(int before, int after, [String basis = 'Mark']) =>
    SequenceEdgeEntry(before: before, after: after, bases: [basis]);

EventSequenceEntry _sequence(
  String key,
  List<int> events,
  List<SequenceEdgeEntry> edges, {
  int? expands,
}) => EventSequenceEntry(
  key: key,
  title: key,
  note: '',
  expands: expands,
  events: events,
  edges: edges,
  groupings: const [],
  milestones: const [],
  details: const [],
);

void main() {
  // 1 → 2 → 3 → 5, 1 → 4 → 5 (John's), 1 → 5 implied, 6 alone.
  final ministry = _sequence(
    'ministry',
    [1, 2, 3, 4, 5, 6],
    [
      _edge(1, 2),
      _edge(2, 3),
      _edge(3, 5),
      _edge(1, 4, 'John'),
      _edge(4, 5, 'John'),
      _edge(1, 5, 'Luke'),
    ],
  );

  test('what comes before and after each event, by any route', () {
    final graph = SequenceGraph(ministry);
    expect(graph.before(5), {1, 2, 3, 4});
    expect(graph.after(2), {3, 5});
    // 2 and 4 are of unknown order to each other, and 6 to all.
    expect(graph.before(4).contains(2) || graph.after(4).contains(2), isFalse);
    expect(graph.unorderedWith(4), 3);
    expect(graph.unorderedWith(6), 5);
    expect(
      [for (final (e, bases) in graph.directlyBefore(5)) (e, bases.join())],
      [(1, 'Luke'), (3, 'Mark'), (4, 'John')],
    );
  });

  test('an ordering a longer route implies is not drawn', () {
    final graph = SequenceGraph(ministry);
    expect(graph.drawnEdges, isNot(contains((1, 5))));
    expect(graph.drawnEdges, containsAll([(1, 2), (2, 3), (3, 5), (1, 4)]));
  });

  test('each event is drawn below those it follows, a chain straight', () {
    final graph = SequenceGraph(ministry);
    for (final e in graph.events) {
      for (final b in graph.before(e)) {
        expect(graph.row[b]!, lessThan(graph.row[e]!), reason: '$b over $e');
      }
    }
    expect(
      [
        for (final e in [1, 2, 3, 5]) graph.row[e],
      ],
      [0, 1, 2, 3],
    );
    expect(graph.row[4], 1);
    // In a row, a slot apart at least.
    for (final row in graph.rows) {
      for (var i = 1; i < row.length; i++) {
        expect(
          graph.column[row[i]]! - graph.column[row[i - 1]]!,
          greaterThanOrEqualTo(1 - 1e-9),
        );
      }
    }
    expect(graph.column.values.reduce((a, b) => a < b ? a : b), 0);
  });

  group('grouped', () {
    // Two parts: 1 alone, then 2–5 in two groups of their own; 6 in none.
    final grouping = SequenceGroupingEntry(
      key: 'parts',
      title: 'Parts',
      note: '',
      groups: [
        SequenceGroupEntry(title: 'One', note: '', parent: null, events: [1]),
        SequenceGroupEntry(title: 'Two', note: '', parent: null, events: []),
        SequenceGroupEntry(title: 'Two a', note: '', parent: 1, events: [2, 4]),
        SequenceGroupEntry(title: 'Two b', note: '', parent: 1, events: [3, 5]),
      ],
    );
    final tree = GroupingTree(grouping);

    test('a grouping is a tree', () {
      expect(tree.top, [0, 1]);
      expect(tree.children(1), [2, 3]);
      expect(tree.leafOf[5], 3);
      expect(tree.pathTo(3), [1, 3]);
      expect(tree.depth(3), 1);
      expect(tree.eventsOf(1), [2, 4, 3, 5]);
    });

    test('a folded group is one node with its events\' orderings', () {
      final graph = SequenceGraph(ministry, grouping: tree);
      final two = groupNode(1);
      expect(nodeGroup(two), 1);
      expect(graph.events, [groupNode(0), two, 6]);
      expect(graph.nodeOf[4], two);
      expect(graph.after(groupNode(0)), {two});
      expect(
        [
          for (final (n, bases) in graph.directlyAfter(groupNode(0)))
            (n, bases.join(', ')),
        ],
        [(two, 'Mark, John, Luke')],
      );
      expect(graph.groupRows, isEmpty);
    });

    test('an unfolded group\'s rows follow those before it', () {
      final graph = SequenceGraph(ministry, grouping: tree, expanded: {1, 2});
      expect(graph.events, [groupNode(0), 2, 4, groupNode(3), 6]);
      // 2 and 4 are of unknown order, so they share a row.
      expect(graph.row[groupNode(0)], 0);
      expect(graph.row[2], 1);
      expect(graph.row[4], 1);
      expect(graph.row[groupNode(3)], 2);
      // 6, ordered with none, is still below every group.
      expect(graph.row[6], 3);
      expect(graph.groupRows, {1: (1, 2), 2: (1, 1)});
    });

    test('in lanes, each node lies in its own', () {
      final lane = {1: 0, 2: 1, 3: 1, 4: 2, 5: 0};
      final graph = SequenceGraph(ministry, laneOf: (n) => lane[n]);
      expect(graph.lanes.map((l) => l.lane), [0, 1, 2, 1 << 20]);
      final start = {for (final l in graph.lanes) l.lane: l.start};
      for (final MapEntry(key: e, value: l) in lane.entries) {
        expect(graph.column[e], start[l], reason: 'event $e');
      }
      expect(graph.column[6], start[1 << 20]);
    });
  });

  test('a sequence inside an event is found through it', () {
    final week = _sequence('week', [7, 8], [_edge(7, 8)], expands: 5);
    final sequences = BibleSequences([ministry, week]);
    expect(sequences.expanding[5]?.key, 'week');
    expect(sequences.homeOf[8]?.key, 'week');
    expect(sequences.pathTo(8).map((s) => s.key), ['ministry', 'week']);
    expect(sequences.pathTo(2).map((s) => s.key), ['ministry']);
    expect(sequences.pathTo(99), isEmpty);
  });
}
