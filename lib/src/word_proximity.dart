import 'package:flutter/widgets.dart';

/// One verse in which a word matched, with what matched there so a result
/// row can highlight it. Books are 1-based, as in the occurrence signals.
class ProximityHit {
  const ProximityHit({
    required this.book,
    required this.chapter,
    required this.verse,
    this.words = const [],
    this.positions = const [],
  });

  final int book;
  final int chapter;
  final int verse;

  /// Matched surface forms, for highlighting by text.
  final List<String> words;

  /// Matched lexical positions, preferred for highlighting when known.
  final List<int> positions;
}

/// A verse of a proximity result: every included word's matches in it merged,
/// tagged with the passage (run of nearby matching verses) it belongs to.
class ProximityVerse {
  ProximityVerse({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.passage,
  });

  final int book;
  final int chapter;
  final int verse;

  /// Index of the passage this verse belongs to, counting from zero in
  /// canonical order. At [ProximityDistance.sameVerse] every verse is its own
  /// passage.
  final int passage;
  final List<String> words = [];
  final List<int> positions = [];
}

/// How close the included words have to stand to one another.
///
/// Measured in verses within one chapter: the occurrence data carries no word
/// positions for the NT, and a verse window across a chapter boundary would
/// need every chapter's length.
class ProximityDistance {
  const ProximityDistance._(this.verses);

  /// All words in one verse.
  static const sameVerse = ProximityDistance._(0);

  /// All words in one chapter.
  static const sameChapter = ProximityDistance._(null);

  /// All words within a span of `n` verses of each other, in one chapter.
  const ProximityDistance.withinVerses(int n) : this._(n);

  /// The choices offered in the occurrences header, narrowest first.
  static const options = [
    sameVerse,
    ProximityDistance.withinVerses(1),
    ProximityDistance.withinVerses(2),
    ProximityDistance.withinVerses(3),
    ProximityDistance.withinVerses(5),
    ProximityDistance.withinVerses(10),
    sameChapter,
  ];

  /// Verse span, or null for a whole chapter.
  final int? verses;

  String get label => switch (verses) {
    null => 'Same chapter',
    0 => 'Same verse',
    1 => 'Within 1 verse',
    final n => 'Within $n verses',
  };

  @override
  bool operator ==(Object other) =>
      other is ProximityDistance && other.verses == verses;

  @override
  int get hashCode => verses.hashCode;
}

/// Verses where every term stands within [distance] of all the others.
///
/// Each term is one word's matching verses. A verse is kept when it holds a
/// match of some term and lies in a window that holds a match of every term;
/// the kept verses of a chapter are then split into passages wherever the gap
/// between them is wider than the window, so overlapping windows read as one
/// passage. With fewer than two terms there is nothing to be near, and the
/// result is empty.
List<ProximityVerse> proximityMatches(
  List<List<ProximityHit>> terms,
  ProximityDistance distance,
) {
  if (terms.length < 2) return const [];

  // term -> chapter key -> verse -> hit
  final byChapter = [
    for (final hits in terms)
      <int, Map<int, ProximityHit>>{
        for (final hit in hits) _chapterKey(hit.book, hit.chapter): {},
      },
  ];
  for (final (term, hits) in terms.indexed) {
    for (final hit in hits) {
      byChapter[term][_chapterKey(hit.book, hit.chapter)]![hit.verse] = hit;
    }
  }

  final shared = byChapter.first.keys.toSet();
  for (final chapters in byChapter.skip(1)) {
    shared.retainAll(chapters.keys);
  }
  final chapterKeys = shared.toList()..sort();

  final out = <ProximityVerse>[];
  var passage = -1;
  for (final key in chapterKeys) {
    final termVerses = [
      for (final chapters in byChapter) chapters[key]!.keys.toList()..sort(),
    ];
    final candidates = {for (final verses in termVerses) ...verses}.toList()
      ..sort();

    final Set<int> kept;
    final span = distance.verses;
    if (span == null) {
      kept = candidates.toSet();
    } else {
      kept = {};
      for (final start in candidates) {
        final end = start + span;
        final covered = termVerses.every(
          (verses) => verses.any((v) => v >= start && v <= end),
        );
        if (!covered) continue;
        kept.addAll(candidates.where((v) => v >= start && v <= end));
      }
    }
    if (kept.isEmpty) continue;

    final book = key >> 8;
    final chapter = key & 0xff;
    int? previous;
    for (final verse in kept.toList()..sort()) {
      if (previous == null || (span != null && verse - previous > span)) {
        passage++;
      }
      previous = verse;
      final row = ProximityVerse(
        book: book,
        chapter: chapter,
        verse: verse,
        passage: passage,
      );
      for (final chapters in byChapter) {
        final hit = chapters[key]![verse];
        if (hit == null) continue;
        for (final word in hit.words) {
          if (!row.words.contains(word)) row.words.add(word);
        }
        row.positions.addAll(hit.positions);
      }
      out.add(row);
    }
  }
  return out;
}

int _chapterKey(int book, int chapter) => (book << 8) | chapter;

/// One open word pane's contribution to a proximity search.
class ProximitySource {
  ProximitySource({required this.id, required this.label, required this.hits});

  /// The pane's id, stable across that pane's word history.
  final String id;

  /// The word as the pane shows it.
  final String Function() label;

  /// The verses the pane's word matches under its own form, parse, or lexeme
  /// filters — not its book filter, which only narrows the pane's own list.
  /// Null while the pane's occurrences are still loading.
  final List<ProximityHit>? Function() hits;
}

/// The open word panes a proximity search can combine, and the search's
/// settings, shared by every pane so switching panes keeps them.
class WordProximity extends ChangeNotifier {
  final Map<String, ProximitySource> _sources = {};
  final Set<String> _excluded = {};
  bool _enabled = false;
  ProximityDistance _distance = ProximityDistance.sameVerse;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Registered panes, in the order they were first opened.
  List<ProximitySource> get sources => List.unmodifiable(_sources.values);

  /// Whether the occurrence lists show proximity results rather than each
  /// word's own occurrences.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  ProximityDistance get distance => _distance;
  set distance(ProximityDistance value) {
    if (_distance == value) return;
    _distance = value;
    notifyListeners();
  }

  /// Every open word is included until it is toggled off.
  bool isIncluded(String id) => !_excluded.contains(id);

  void setIncluded(String id, bool included) {
    final changed = included ? _excluded.remove(id) : _excluded.add(id);
    if (changed) notifyListeners();
  }

  /// Registers a pane's source, replacing an earlier one with the same id in
  /// place so a pane keeps its position while it moves through its history.
  void register(ProximitySource source) {
    _sources[source.id] = source;
    _scheduleNotify();
  }

  /// Removes [source], unless its pane has already registered a successor.
  void unregister(ProximitySource source) {
    if (!identical(_sources[source.id], source)) return;
    _sources.remove(source.id);
    _scheduleNotify();
  }

  /// Forgets a closed pane, including whether it was toggled off.
  void forget(String id) {
    _excluded.remove(id);
    if (_sources.remove(id) != null) _scheduleNotify();
  }

  /// A source's hits have changed. Only a running search reads hits, so with
  /// it off no pane needs rebuilding; turning it on notifies every pane anyway.
  void changed() {
    if (_enabled) _scheduleNotify();
  }

  /// Notified after the current frame, since panes register and load while the
  /// tree is being built.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
