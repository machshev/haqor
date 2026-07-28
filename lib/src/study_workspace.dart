import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const studyWorkspacesKey = 'study_workspaces_v1';
const activeStudyWorkspaceKey = 'active_study_workspace';

@immutable
class StudyPassage {
  const StudyPassage({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    this.note = '',
  });

  final int bookIndex;
  final int chapter;
  final int verse;
  final String note;

  String get locationKey => '$bookIndex:$chapter:$verse';

  StudyPassage copyWith({String? note}) => StudyPassage(
    bookIndex: bookIndex,
    chapter: chapter,
    verse: verse,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'book': bookIndex,
    'chapter': chapter,
    'verse': verse,
    if (note.isNotEmpty) 'note': note,
  };

  static StudyPassage? fromJson(Object? value) {
    if (value is! Map) return null;
    final book = value['book'];
    final chapter = value['chapter'];
    final verse = value['verse'];
    if (book is! int || chapter is! int || verse is! int) return null;
    if (book < 0 || chapter < 1 || verse < 1) return null;
    return StudyPassage(
      bookIndex: book,
      chapter: chapter,
      verse: verse,
      note: value['note'] is String ? value['note'] as String : '',
    );
  }
}

@immutable
class StudyWord {
  const StudyWord({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.position,
    required this.surface,
    this.note = '',
  });

  final int bookIndex;
  final int chapter;
  final int verse;
  final int position;
  final String surface;
  final String note;

  String get locationKey => '$bookIndex:$chapter:$verse:$position';

  StudyWord copyWith({String? note}) => StudyWord(
    bookIndex: bookIndex,
    chapter: chapter,
    verse: verse,
    position: position,
    surface: surface,
    note: note ?? this.note,
  );

  Map<String, Object?> toJson() => {
    'book': bookIndex,
    'chapter': chapter,
    'verse': verse,
    'position': position,
    'surface': surface,
    if (note.isNotEmpty) 'note': note,
  };

  static StudyWord? fromJson(Object? value) {
    if (value is! Map) return null;
    final book = value['book'];
    final chapter = value['chapter'];
    final verse = value['verse'];
    final position = value['position'];
    final surface = value['surface'];
    if (book is! int ||
        chapter is! int ||
        verse is! int ||
        position is! int ||
        surface is! String) {
      return null;
    }
    if (book < 0 || chapter < 1 || verse < 1 || position < 0) return null;
    return StudyWord(
      bookIndex: book,
      chapter: chapter,
      verse: verse,
      position: position,
      surface: surface,
      note: value['note'] is String ? value['note'] as String : '',
    );
  }
}

@immutable
class StudyWorkspace {
  const StudyWorkspace({
    required this.id,
    required this.name,
    required this.centralPassage,
    required this.passages,
    this.words = const [],
  });

  final String id;
  final String name;
  final StudyPassage centralPassage;
  final List<StudyPassage> passages;
  final List<StudyWord> words;

  StudyWorkspace copyWith({
    String? name,
    StudyPassage? centralPassage,
    List<StudyPassage>? passages,
    List<StudyWord>? words,
  }) => StudyWorkspace(
    id: id,
    name: name ?? this.name,
    centralPassage: centralPassage ?? this.centralPassage,
    passages: passages ?? this.passages,
    words: words ?? this.words,
  );

  StudyPassage? passageAt(int bookIndex, int chapter, int verse) {
    final key = '$bookIndex:$chapter:$verse';
    for (final passage in passages) {
      if (passage.locationKey == key) return passage;
    }
    return null;
  }

  StudyWord? wordAt(int bookIndex, int chapter, int verse, int position) {
    final key = '$bookIndex:$chapter:$verse:$position';
    for (final word in words) {
      if (word.locationKey == key) return word;
    }
    return null;
  }

  StudyWorkspace putPassage(StudyPassage passage) {
    final updated = List<StudyPassage>.of(passages);
    final index = updated.indexWhere(
      (candidate) => candidate.locationKey == passage.locationKey,
    );
    if (index < 0) {
      updated.add(passage);
    } else {
      updated[index] = passage;
    }
    return copyWith(passages: updated);
  }

  StudyWorkspace removePassage(StudyPassage passage) => copyWith(
    passages: passages
        .where((candidate) => candidate.locationKey != passage.locationKey)
        .toList(),
  );

  StudyWorkspace putWord(StudyWord word) {
    final updated = List<StudyWord>.of(words);
    final index = updated.indexWhere(
      (candidate) => candidate.locationKey == word.locationKey,
    );
    if (index < 0) {
      updated.add(word);
    } else {
      updated[index] = word;
    }
    return copyWith(words: updated);
  }

  StudyWorkspace removeWord(StudyWord word) => copyWith(
    words: words
        .where((candidate) => candidate.locationKey != word.locationKey)
        .toList(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'central': centralPassage.toJson(),
    'passages': passages.map((passage) => passage.toJson()).toList(),
    'words': words.map((word) => word.toJson()).toList(),
  };

  static StudyWorkspace? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final central = StudyPassage.fromJson(value['central']);
    if (id is! String || id.isEmpty || name is! String || central == null) {
      return null;
    }
    final passages = value['passages'] is List
        ? (value['passages'] as List)
              .map(StudyPassage.fromJson)
              .whereType<StudyPassage>()
              .toList()
        : <StudyPassage>[];
    if (!passages.any(
      (passage) => passage.locationKey == central.locationKey,
    )) {
      passages.insert(0, central);
    }
    final words = value['words'] is List
        ? (value['words'] as List)
              .map(StudyWord.fromJson)
              .whereType<StudyWord>()
              .toList()
        : <StudyWord>[];
    return StudyWorkspace(
      id: id,
      name: name,
      centralPassage: central,
      passages: passages,
      words: words,
    );
  }
}

List<StudyWorkspace> decodeStudyWorkspaces(String? value) {
  if (value == null || value.isEmpty) return [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return [];
    return decoded
        .map(StudyWorkspace.fromJson)
        .whereType<StudyWorkspace>()
        .toList();
  } on FormatException {
    return [];
  }
}

String encodeStudyWorkspaces(List<StudyWorkspace> workspaces) =>
    jsonEncode(workspaces.map((workspace) => workspace.toJson()).toList());

Future<void> saveStudyWorkspaces(
  SharedPreferences prefs,
  List<StudyWorkspace> workspaces,
  String? activeWorkspaceId,
) async {
  await prefs.setString(studyWorkspacesKey, encodeStudyWorkspaces(workspaces));
  if (activeWorkspaceId == null) {
    await prefs.remove(activeStudyWorkspaceKey);
  } else {
    await prefs.setString(activeStudyWorkspaceKey, activeWorkspaceId);
  }
}
