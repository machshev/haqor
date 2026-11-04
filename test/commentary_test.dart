import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/commentary.dart';
import 'package:haqor/src/study_workspace.dart';

CommentaryNote _note(
  String id,
  StudyPassage anchor, {
  String text = 'Note',
  int created = 1,
}) => CommentaryNote(
  id: id,
  anchors: [anchor],
  text: text,
  created: DateTime.fromMillisecondsSinceEpoch(created),
  updated: DateTime.fromMillisecondsSinceEpoch(created),
);

void main() {
  test('a commentary note keeps its anchor, text and unknown keys', () {
    final note = CommentaryNote.fromJson('c1', {
      'anchor': {
        'book': 0,
        'chapter': 1,
        'verse': 3,
        'startWord': 1,
        'endWord': 2,
        // A study's own fields mean nothing on an anchor.
        'note': 'ignored',
      },
      'text': '*Light* first',
      'created': 10,
      'updated': 20,
      'future': [1, 2],
    })!;
    expect(note.anchor.locationKey, '0:1:3@1-2');
    expect(note.text, '*Light* first');
    expect(note.updated.millisecondsSinceEpoch, 20);
    final json = note.toJson();
    expect(json['future'], [1, 2]);
    // Read from the single anchor of earlier drafts, saved as a list.
    expect(json.containsKey('anchor'), isFalse);
    expect(json['anchors'], [
      {'book': 0, 'chapter': 1, 'verse': 3, 'startWord': 1, 'endWord': 2},
    ]);
    final again = CommentaryNote.fromJson('c1', jsonDecode(jsonEncode(json)))!;
    expect(again.toJson(), json);
  });

  test('a note links to more passages, each marked where it is', () {
    final time = DateTime.fromMillisecondsSinceEpoch(1);
    final note = CommentaryNote(
      id: 'n',
      anchors: const [StudyPassage(bookIndex: 0, chapter: 2, verse: 5)],
      text: 'Rest',
      created: time,
      updated: time,
    );
    const phrase = StudyPassage(
      bookIndex: 1,
      chapter: 20,
      verse: 8,
      startWord: 1,
      endWord: 3,
    );
    final linked = note.linkedTo(phrase);
    expect(linked.anchors, [note.anchor, phrase]);
    // The same passage again changes nothing.
    expect(identical(linked.linkedTo(phrase), linked), isTrue);
    expect(linked.inChapter(1, 20), isTrue);
    expect(linked.marginVerse(1, 20), 8);
    expect(linked.marginVerse(0, 2), 5);
    expect(linked.onVerse(1, 20, 8), isTrue);
    expect(linked.onWord(1, 20, 8, 2), isTrue);
    expect(linked.onWord(1, 20, 8, 4), isFalse);
    // A whole verse marks no words.
    expect(linked.onWord(0, 2, 5, 0), isFalse);
    final read = CommentaryNote.fromJson(
      'n',
      jsonDecode(jsonEncode(linked.toJson())),
    )!;
    expect(read.anchors.map((a) => a.locationKey), ['0:2:5', '1:20:8@1-3']);
  });

  test('a note without text or a valid anchor is not read', () {
    expect(
      CommentaryNote.fromJson('c', {
        'anchor': {'book': 0, 'chapter': 1, 'verse': 1},
        'text': '  ',
      }),
      isNull,
    );
    expect(
      CommentaryNote.fromJson('c', {
        'anchor': {'book': 0, 'chapter': 0, 'verse': 1},
        'text': 'x',
      }),
      isNull,
    );
    expect(CommentaryNote.fromJson('', {'text': 'x'}), isNull);
  });

  test('notes find their verses and chapters, in Bible order', () {
    final store = CommentaryStore(
      sendRequest: (_) {},
      save: (_) {},
      delete: (_) {},
    );
    final range = _note(
      'range',
      const StudyPassage(
        bookIndex: 0,
        chapter: 1,
        verse: 30,
        endChapter: 2,
        endVerse: 3,
      ),
    );
    final chapter = _note(
      'chapter',
      const StudyPassage(
        bookIndex: 0,
        chapter: 2,
        verse: 1,
        wholeChapter: true,
      ),
      created: 5,
    );
    final verse = _note(
      'verse',
      const StudyPassage(bookIndex: 0, chapter: 2, verse: 2),
    );
    store
      ..put(verse)
      ..put(chapter)
      ..put(range);
    expect(store.notes.map((n) => n.id), ['range', 'chapter', 'verse']);
    expect(store.notesOn(0, 2, 2).map((n) => n.id), [
      'range',
      'chapter',
      'verse',
    ]);
    expect(store.notesOn(0, 2, 4).map((n) => n.id), ['chapter']);
    expect(store.notesInChapter(0, 1).map((n) => n.id), ['range']);
    expect(range.marginVerse(0, 1), 30);
    expect(range.marginVerse(0, 2), 1);
    expect(verse.marginVerse(0, 2), 2);
    store.dispose();
  });

  test('edits made before Rust answers outlive its older answer', () {
    final saved = <SaveCommentaryNote>[];
    final deleted = <DeleteCommentaryNote>[];
    final store = CommentaryStore(
      sendRequest: (_) {},
      save: saved.add,
      delete: deleted.add,
    );
    const anchor = StudyPassage(bookIndex: 0, chapter: 1, verse: 1);
    String json(String text) =>
        jsonEncode(_note('x', anchor, text: text).toJson());
    store.receive([]);
    store.put(_note('early', anchor, text: 'mine'));
    expect(saved.single.id, 'early');
    expect(jsonDecode(saved.single.noteJson)['text'], 'mine');

    final fresh = CommentaryStore(
      sendRequest: (_) {},
      save: (_) {},
      delete: deleted.add,
    );
    fresh
      ..put(_note('a', anchor, text: 'edited here'))
      ..remove('a')
      ..put(_note('b', anchor, text: 'edited here'));
    fresh.receive([
      CommentaryNoteEntry(id: 'b', noteJson: json('stale')),
      CommentaryNoteEntry(id: 'c', noteJson: json('from rust')),
      CommentaryNoteEntry(id: 'bad', noteJson: '{not json'),
    ]);
    expect(fresh.notes.map((n) => (n.id, n.text)), [
      ('b', 'edited here'),
      ('c', 'from rust'),
    ]);
    // Later answers (after a sync) are taken whole.
    fresh.receive([CommentaryNoteEntry(id: 'c', noteJson: json('synced'))]);
    expect(fresh.notes.map((n) => (n.id, n.text)), [('c', 'synced')]);
    fresh.remove('c');
    expect(deleted.map((d) => d.id), ['a', 'c']);
    store.dispose();
    fresh.dispose();
  });

  test('a study links to commentary and keeps a copy of its text', () {
    const linked = StudyNote(
      id: 'n',
      text: 'old copy',
      commentaryId: 'c1',
      groupId: 'g',
    );
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
      notes: [
        linked,
        StudyNote(id: 'own', text: 'own note'),
      ],
    );
    expect(workspace.linksCommentary('c1'), isTrue);
    expect(workspace.linksCommentary('c2'), isFalse);
    workspace = workspace.withCommentaryText('c1', 'new copy');
    expect(workspace.notes.map((n) => n.text), ['new copy', 'own note']);
    expect(
      identical(workspace.withCommentaryText('c1', 'new copy'), workspace),
      isTrue,
    );

    final json = workspace.notes.first.toJson();
    expect(json['commentary'], 'c1');
    final read = StudyNote.fromJson(json)!;
    expect(read.commentaryId, 'c1');
    expect(read.copyWith(order: 3).commentaryId, 'c1');
    expect(read.extra, isEmpty);
    expect(StudyNote.fromJson({'id': 'x', 'text': 't'})!.commentaryId, isNull);
  });
}
