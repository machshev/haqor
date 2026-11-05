import 'dart:async';

import 'package:flutter/foundation.dart';

import 'bindings/bindings.dart';

/// Haqor's apologetics, asked of Rust once and kept: there are few enough to
/// hold whole, and the reader finds a chapter's and a verse's from them.
class ApologeticsStore extends ChangeNotifier {
  ApologeticsStore();

  /// The one the app shares.
  static final instance = ApologeticsStore();

  static int _nextRequestId = 1;

  StreamSubscription<dynamic>? _sub;
  int _requestId = 0;
  List<ApologeticSubjectEntry>? _subjects;
  List<ApologeticTopicEntry> _topics = const [];
  List<ApologeticReligionEntry> _religions = const [];
  List<ApologeticAudienceEntry> _audiences = const [];
  List<ApologeticEntry> _entries = const [];

  /// The entries each verse marks, keyed by [_verseKey].
  Map<int, List<ApologeticEntry>> _marks = const {};

  /// Whether the reply has come.
  bool get loaded => _subjects != null;
  List<ApologeticSubjectEntry> get subjects => _subjects ?? const [];
  List<ApologeticEntry> get entries => _entries;

  /// The topics cutting across subjects, in order.
  List<ApologeticTopicEntry> get topics => _topics;

  /// The religions audiences belong to, in order; empty for a database
  /// built without them.
  List<ApologeticReligionEntry> get religions => _religions;

  /// Whom a conversation may be with, in order.
  List<ApologeticAudienceEntry> get audiences => _audiences;

  /// Asks Rust for them, once; [send] stands in for the signal, for tests.
  void load({void Function(GetApologetics)? send}) {
    if (_sub != null || loaded) return;
    _sub = Apologetics.rustSignalStream.listen((pack) {
      final reply = pack.message;
      if (reply.requestId != _requestId) return;
      set(
        reply.subjects,
        reply.entries,
        topics: reply.topics,
        religions: reply.religions,
        audiences: reply.audiences,
      );
    });
    final request = GetApologetics(requestId: _requestId = _nextRequestId++);
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  /// Holds [subjects], [entries], [topics], [religions] and [audiences], as a
  /// reply from Rust does.
  void set(
    List<ApologeticSubjectEntry> subjects,
    List<ApologeticEntry> entries, {
    List<ApologeticTopicEntry> topics = const [],
    List<ApologeticReligionEntry> religions = const [],
    List<ApologeticAudienceEntry> audiences = const [],
  }) {
    _subjects = subjects;
    _topics = topics;
    _religions = religions;
    _audiences = audiences;
    _entries = entries;
    final marks = <int, List<ApologeticEntry>>{};
    for (final e in entries) {
      for (final p in e.passages) {
        (marks[_verseKey(p.book, p.chapter, p.verse)] ??= []).add(e);
      }
    }
    _marks = marks;
    notifyListeners();
  }

  static int _verseKey(int book, int chapter, int verse) =>
      (book << 16) | (chapter << 8) | verse;

  ApologeticEntry? byKey(String key) =>
      _entries.where((e) => e.key == key).firstOrNull;

  ApologeticSubjectEntry? subject(String key) =>
      subjects.where((s) => s.key == key).firstOrNull;

  ApologeticTopicEntry? topic(String key) =>
      _topics.where((t) => t.key == key).firstOrNull;

  ApologeticReligionEntry? religion(String key) =>
      _religions.where((r) => r.key == key).firstOrNull;

  ApologeticAudienceEntry? audience(String key) =>
      _audiences.where((a) => a.key == key).firstOrNull;

  /// The audiences of the religion [key], in order.
  List<ApologeticAudienceEntry> audiencesOf(String key) => [
    for (final a in _audiences)
      if (a.religion == key) a,
  ];

  /// The entries named by [keys], in their order, skipping any unknown.
  List<ApologeticEntry> byKeys(List<String> keys) => [
    for (final key in keys) ?byKey(key),
  ];

  /// The entries marking chapters [first] to [last] of [book] (counted from
  /// one, as Rust counts books): those with a passage there.
  List<ApologeticEntry> touching(int book, int first, int last) => [
    for (final e in _entries)
      if (e.passages.any((p) => passageTouches(p, book, first, last))) e,
  ];

  /// The entries marked at a verse: those with a passage starting there, or
  /// running into its chapter from before when it is the first verse.
  List<ApologeticEntry> markedAt(int book, int chapter, int verse) {
    final here = _marks[_verseKey(book, chapter, verse)] ?? const [];
    if (verse != 1) return here;
    final carried = [
      for (final e in _entries)
        if (e.passages.any(
          (p) =>
              p.book == book && p.chapter < chapter && p.lastChapter >= chapter,
        ))
          e,
    ];
    return carried.isEmpty ? here : {...here, ...carried}.toList();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Whether [p] lies at least partly in chapters [first] to [last] of [book].
bool passageTouches(PassageSpan p, int book, int first, int last) =>
    p.book == book && p.chapter <= last && p.lastChapter >= first;

/// What an entry is, as the reader sees it.
String apologeticKindLabel(String kind) => switch (kind) {
  'evidence' => 'Evidence',
  'doctrine' => 'Teaching',
  'passage' => 'Disputed passage',
  _ => kind,
};
