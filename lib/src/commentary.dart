import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';

import 'bindings/bindings.dart';
import 'request_failure.dart';
import 'study_workspace.dart';
import 'tutor/progress_sync.dart';

/// A note of the reader's own on a verse, a range of verses, a chapter or a
/// phrase, kept apart from any study. A study can hold a live link to one
/// (a [StudyNote] with its [StudyNote.commentaryId]).
@immutable
class CommentaryNote {
  const CommentaryNote({
    required this.id,
    required this.anchor,
    required this.text,
    required this.created,
    required this.updated,
    this.extra = const {},
  });

  final String id;

  /// What the note is on: only its reference counts, not its note, colour,
  /// group or order.
  final StudyPassage anchor;

  /// Markdown.
  final String text;
  final DateTime created;
  final DateTime updated;

  /// Keys this version does not know, kept so that saving does not erase
  /// fields a newer version wrote.
  final Map<String, Object?> extra;

  int get bookIndex => anchor.bookIndex;

  bool onVerse(int book, int chapter, int verse) =>
      anchor.containsVerse(book, chapter, verse);

  /// Whether the note's passage overlaps the chapter at all.
  bool inChapter(int book, int chapter) =>
      anchor.bookIndex == book &&
      anchor.chapter <= chapter &&
      anchor.lastChapter >= chapter;

  /// The verse of [chapter] where the note shows in the margin: the first
  /// of its own there.
  int marginVerse(int chapter) =>
      anchor.wholeChapter || anchor.chapter < chapter ? 1 : anchor.verse;

  CommentaryNote copyWith({StudyPassage? anchor, String? text}) =>
      CommentaryNote(
        id: id,
        anchor: anchor ?? this.anchor,
        text: text ?? this.text,
        created: created,
        updated: DateTime.now(),
        extra: extra,
      );

  Map<String, Object?> toJson() => {
    ...extra,
    'anchor': commentaryAnchorJson(anchor),
    'text': text,
    'created': created.millisecondsSinceEpoch,
    'updated': updated.millisecondsSinceEpoch,
  };

  static CommentaryNote? fromJson(String id, Object? value) {
    if (id.isEmpty || value is! Map) return null;
    final anchor = StudyPassage.fromJson(value['anchor']);
    final text = value['text'];
    if (anchor == null || text is! String || text.trim().isEmpty) return null;
    DateTime time(Object? ms) => ms is int
        ? DateTime.fromMillisecondsSinceEpoch(ms)
        : DateTime.fromMillisecondsSinceEpoch(0);
    return CommentaryNote(
      id: id,
      anchor: anchor,
      text: text,
      created: time(value['created']),
      updated: time(value['updated'] ?? value['created']),
      extra: {
        for (final entry in value.entries)
          if (entry.key is String &&
              !const {
                'anchor',
                'text',
                'created',
                'updated',
              }.contains(entry.key))
            entry.key as String: entry.value,
      },
    );
  }
}

/// Only the reference of [anchor], without the study's own fields.
Map<String, Object?> commentaryAnchorJson(StudyPassage anchor) => {
  'book': anchor.bookIndex,
  'chapter': anchor.chapter,
  'verse': anchor.verse,
  if (anchor.wholeChapter) 'wholeChapter': true,
  if (anchor.endChapter != null) 'endChapter': anchor.endChapter,
  if (anchor.endVerse != null) 'endVerse': anchor.endVerse,
  if (anchor.startWord != null) 'startWord': anchor.startWord,
  if (anchor.endWord != null) 'endWord': anchor.endWord,
};

/// Bible order, then the first word, then the oldest first.
int compareCommentaryNotes(CommentaryNote a, CommentaryNote b) {
  final x = a.anchor, y = b.anchor;
  for (final (p, q) in [
    (x.bookIndex, y.bookIndex),
    (x.chapter, y.chapter),
    (x.wholeChapter ? 0 : x.verse, y.wholeChapter ? 0 : y.verse),
    (x.startWord ?? -1, y.startWord ?? -1),
  ]) {
    if (p != q) return p.compareTo(q);
  }
  final byCreated = a.created.compareTo(b.created);
  return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
}

/// The commentary notes, shared by every reader tab. Rust keeps them, one
/// row per note, and syncs them; this keeps the copy the app shows, saving
/// each edit at once.
class CommentaryStore extends ChangeNotifier {
  /// [sendRequest], [save] and [delete] let tests replace the native signals.
  CommentaryStore({this.sendRequest, this.save, this.delete});

  final void Function(GetCommentaryNotes request)? sendRequest;
  final void Function(SaveCommentaryNote request)? save;
  final void Function(DeleteCommentaryNote request)? delete;

  final Map<String, CommentaryNote> _notes = {};
  List<CommentaryNote>? _sorted;
  StreamSubscription<RustSignalPack<CommentaryNotes>>? _sub;
  StreamSubscription<RequestFailed>? _failureSub;
  bool _disposed = false;

  // Edits made before Rust's first answer, which that answer predates.
  final Map<String, CommentaryNote?> _early = {};
  bool _answered = false;

  /// Every note, in Bible order.
  List<CommentaryNote> get notes => _sorted ??= List.unmodifiable(
    _notes.values.toList()..sort(compareCommentaryNotes),
  );

  CommentaryNote? byId(String? id) => id == null ? null : _notes[id];

  /// The notes on a verse, in order.
  List<CommentaryNote> notesOn(int book, int chapter, int verse) => [
    for (final note in notes)
      if (note.onVerse(book, chapter, verse)) note,
  ];

  /// The notes anywhere in a chapter, in order.
  List<CommentaryNote> notesInChapter(int book, int chapter) => [
    for (final note in notes)
      if (note.inChapter(book, chapter)) note,
  ];

  void start() {
    _sub = CommentaryNotes.rustSignalStream.listen((pack) {
      receive(pack.message.notes);
    });
    _failureSub = listenForFailure(requestCommentaryNotes, (_) {
      _answered = true;
      _early.clear();
    });
    final request = GetCommentaryNotes();
    final send = sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  /// Take Rust's notes in place of the copy kept here.
  @visibleForTesting
  void receive(List<CommentaryNoteEntry> entries) {
    if (_disposed) return;
    _notes.clear();
    for (final entry in entries) {
      final Object? json;
      try {
        json = jsonDecode(entry.noteJson);
      } on FormatException {
        continue;
      }
      final note = CommentaryNote.fromJson(entry.id, json);
      if (note != null) _notes[note.id] = note;
    }
    if (!_answered) {
      _answered = true;
      // Already saved and sent, and newer than this answer.
      for (final MapEntry(:key, :value) in _early.entries) {
        if (value == null) {
          _notes.remove(key);
        } else {
          _notes[key] = value;
        }
      }
      _early.clear();
    }
    _sorted = null;
    notifyListeners();
  }

  /// Add or replace [note].
  void put(CommentaryNote note) {
    _notes[note.id] = note;
    if (!_answered) _early[note.id] = note;
    _sorted = null;
    notifyListeners();
    final request = SaveCommentaryNote(
      id: note.id,
      noteJson: jsonEncode(note.toJson()),
    );
    final save = this.save;
    if (save != null) {
      save(request);
    } else {
      request.sendSignalToRust();
      scheduleProgressSync();
    }
  }

  void remove(String id) {
    if (_notes.remove(id) == null) return;
    if (!_answered) _early[id] = null;
    _sorted = null;
    notifyListeners();
    final request = DeleteCommentaryNote(id: id);
    final delete = this.delete;
    if (delete != null) {
      delete(request);
    } else {
      request.sendSignalToRust();
      scheduleProgressSync();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _failureSub?.cancel();
    super.dispose();
  }
}

/// A fresh id for a commentary note.
String newCommentaryId() =>
    'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
