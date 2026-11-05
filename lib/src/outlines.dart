import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bible_data.dart';
import 'bindings/bindings.dart';

/// A verse as one number that orders the Bible: book (counted from one, as
/// Rust counts books), chapter and verse.
int outlineVerseKey(int book, int chapter, int verse) =>
    (book << 16) | (chapter << 8) | verse;

extension OutlineSectionSpan on OutlineSectionEntry {
  int get firstKey => outlineVerseKey(book, chapter, verse);
  int get lastKey => outlineVerseKey(lastBook, lastChapter, lastVerse);

  /// Its values of the facet [key]; empty for none.
  List<String> factsOf(String key) =>
      facts.where((f) => f.facet == key).firstOrNull?.values ?? const [];

  /// Whether it touches chapters [first] to [last] of [book].
  bool touches(int book, int first, int last) =>
      firstKey <= outlineVerseKey(book, last, 255) &&
      lastKey >= outlineVerseKey(book, first, 0);
}

/// A section's verses by name: "Psalms 51", "Genesis 6:9–11:32",
/// "Exodus 20:1–Numbers 10:10". A run of whole chapters is named by its
/// chapters alone when [wholeChapters] says it starts at a chapter's first
/// verse and ends at one's last.
String outlinePassageLabel(
  OutlineSectionEntry s, {
  required bool useEnglish,
  bool wholeChapters = false,
}) {
  String book(int b) => bookDisplayName(b - 1, useEnglish: useEnglish);
  final name = book(s.book);
  if (wholeChapters && s.lastBook == s.book) {
    return s.lastChapter == s.chapter
        ? '$name ${s.chapter}'
        : '$name ${s.chapter}–${s.lastChapter}';
  }
  final start = '$name ${s.chapter}:${s.verse}';
  if (s.lastBook != s.book) {
    return '$start–${book(s.lastBook)} ${s.lastChapter}:${s.lastVerse}';
  }
  if (s.lastChapter == s.chapter && s.lastVerse == s.verse) return start;
  if (s.lastChapter == s.chapter) return '$start–${s.lastVerse}';
  return '$start–${s.lastChapter}:${s.lastVerse}';
}

/// An outline's sections as a tree: each one's children, and the path down
/// to it.
class OutlineTree {
  OutlineTree(this.outline) {
    for (final (i, s) in outline.sections.indexed) {
      final parent = s.parent;
      if (parent == null) {
        top.add(i);
      } else {
        (_children[parent] ??= []).add(i);
      }
    }
  }

  final OutlineEntry outline;

  /// The sections at the top, in order.
  final top = <int>[];
  final _children = <int, List<int>>{};

  OutlineSectionEntry operator [](int section) => outline.sections[section];

  /// The sections inside [section], in order; empty for a leaf.
  List<int> children(int section) => _children[section] ?? const [];

  bool isLeaf(int section) => !_children.containsKey(section);

  /// The sections with none inside them, in order: each psalm, each portion.
  late final List<int> leaves = [
    for (var i = 0; i < outline.sections.length; i++)
      if (isLeaf(i)) i,
  ];

  /// The sections from the top down to [section], [section] last.
  List<int> pathTo(int section) {
    final path = <int>[];
    int? at = section;
    while (at != null && !path.contains(at)) {
      path.insert(0, at);
      at = outline.sections[at].parent;
    }
    return path;
  }

  /// Whether it touches chapters [first] to [last] of [book].
  bool touches(int book, int first, int last) =>
      top.any((i) => this[i].touches(book, first, last));

  /// The deepest sections touching chapters [first] to [last] of [book]
  /// that hold all of what the outline has there: the Psalms' book and
  /// collection for a psalm. Empty when its top sections touch it in more
  /// than one place.
  List<int> pathAround(int book, int first, int last) {
    var level = top;
    final path = <int>[];
    while (true) {
      final touching = [
        for (final i in level)
          if (this[i].touches(book, first, last)) i,
      ];
      if (touching.length != 1) return path;
      path.add(touching.single);
      level = children(touching.single);
    }
  }

  /// The leaves touching chapters [first] to [last] of [book], in order.
  List<int> leavesTouching(int book, int first, int last) => [
    for (final i in leaves)
      if (this[i].touches(book, first, last)) i,
  ];

  /// Each value of the facet [key] with how many leaves have it, most
  /// first, and in first appearance among equals.
  List<(String, int)> valuesOf(String key) {
    final counts = <String, int>{};
    for (final i in leaves) {
      for (final v in this[i].factsOf(key)) {
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    final order = counts.keys.toList();
    final first = {for (final (i, v) in order.indexed) v: i};
    return [for (final v in order) (v, counts[v]!)]..sort((a, b) {
      final byCount = b.$2.compareTo(a.$2);
      return byCount != 0 ? byCount : first[a.$1]!.compareTo(first[b.$1]!);
    });
  }
}

/// Haqor's book outlines, asked of Rust once and kept: there are few enough
/// to hold whole.
class OutlinesStore extends ChangeNotifier {
  OutlinesStore();

  /// The one the app shares.
  static final instance = OutlinesStore();

  static int _nextRequestId = 1;

  StreamSubscription<dynamic>? _sub;
  int _requestId = 0;
  List<OutlineTree>? _trees;

  /// Whether the reply has come.
  bool get loaded => _trees != null;

  /// Every outline, in order.
  List<OutlineTree> get trees => _trees ?? const [];

  OutlineTree? byKey(String key) =>
      trees.where((t) => t.outline.key == key).firstOrNull;

  /// The outlines touching chapters [first] to [last] of [book] (counted
  /// from one).
  List<OutlineTree> touching(int book, int first, int last) => [
    for (final t in trees)
      if (t.touches(book, first, last)) t,
  ];

  /// Asks Rust for them, once; [send] stands in for the signal, for tests.
  void load({void Function(GetOutlines)? send}) {
    if (_sub != null || loaded) return;
    _sub = Outlines.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId) return;
      set(reply.outlines);
    });
    final request = GetOutlines(requestId: _requestId = _nextRequestId++);
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  /// Holds [outlines], as a reply from Rust does.
  void set(List<OutlineEntry> outlines) {
    _trees = [for (final o in outlines) OutlineTree(o)];
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
