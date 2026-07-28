import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const studyWorkspacesKey = 'study_workspaces_v1';
const activeStudyWorkspaceKey = 'active_study_workspace';

const defaultStudyWordColorValue = 0xffffd54f;
const defaultStudyPassageColorValue = 0xff80cbc4;

@immutable
class StudyPassage {
  const StudyPassage({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    this.note = '',
    this.highlightEnabled = true,
  });

  final int bookIndex;
  final int chapter;
  final int verse;
  final String note;
  final bool highlightEnabled;

  String get locationKey => '$bookIndex:$chapter:$verse';

  StudyPassage copyWith({String? note, bool? highlightEnabled}) => StudyPassage(
    bookIndex: bookIndex,
    chapter: chapter,
    verse: verse,
    note: note ?? this.note,
    highlightEnabled: highlightEnabled ?? this.highlightEnabled,
  );

  Map<String, Object?> toJson() => {
    'book': bookIndex,
    'chapter': chapter,
    'verse': verse,
    if (note.isNotEmpty) 'note': note,
    if (!highlightEnabled) 'highlight': false,
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
      highlightEnabled: value['highlight'] is bool
          ? value['highlight'] as bool
          : true,
    );
  }
}

@immutable
class StudyWord {
  const StudyWord({
    required this.root,
    required this.surface,
    this.note = '',
    this.highlightEnabled = true,
  });

  /// The resolved consonantal root. This is the bookmark key: every reader
  /// token carrying the same root is highlighted.
  final String root;
  final String surface;
  final String note;
  final bool highlightEnabled;

  StudyWord copyWith({String? surface, String? note, bool? highlightEnabled}) =>
      StudyWord(
        root: root,
        surface: surface ?? this.surface,
        note: note ?? this.note,
        highlightEnabled: highlightEnabled ?? this.highlightEnabled,
      );

  Map<String, Object?> toJson() => {
    'root': root,
    'surface': surface,
    if (note.isNotEmpty) 'note': note,
    if (!highlightEnabled) 'highlight': false,
  };

  static StudyWord? fromJson(Object? value) {
    if (value is! Map) return null;
    final root = value['root'];
    final surface = value['surface'];
    if (surface is! String || surface.isEmpty) return null;
    // v1 stored one verse occurrence instead of a root. Preserve it as a
    // visible bookmark, but leave its root empty so it cannot falsely
    // highlight unrelated homographs. Saving it after a fresh selection
    // upgrades it to the resolved root.
    return StudyWord(
      root: root is String ? root : '',
      surface: surface,
      note: value['note'] is String ? value['note'] as String : '',
      highlightEnabled: value['highlight'] is bool
          ? value['highlight'] as bool
          : true,
    );
  }
}

@immutable
class StudyTheme {
  const StudyTheme({
    required this.id,
    required this.name,
    this.headerNote = '',
    this.passages = const [],
  });

  final String id;
  final String name;
  final String headerNote;
  final List<StudyPassage> passages;

  StudyTheme copyWith({
    String? name,
    String? headerNote,
    List<StudyPassage>? passages,
  }) => StudyTheme(
    id: id,
    name: name ?? this.name,
    headerNote: headerNote ?? this.headerNote,
    passages: passages ?? this.passages,
  );

  StudyPassage? passageAt(int bookIndex, int chapter, int verse) {
    final key = '$bookIndex:$chapter:$verse';
    for (final passage in passages) {
      if (passage.locationKey == key) return passage;
    }
    return null;
  }

  StudyTheme putPassage(StudyPassage passage) {
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

  StudyTheme removePassage(StudyPassage passage) => copyWith(
    passages: passages
        .where((candidate) => candidate.locationKey != passage.locationKey)
        .toList(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (headerNote.isNotEmpty) 'note': headerNote,
    'passages': passages.map((passage) => passage.toJson()).toList(),
  };

  static StudyTheme? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return StudyTheme(
      id: id,
      name: name,
      headerNote: value['note'] is String ? value['note'] as String : '',
      passages: value['passages'] is List
          ? (value['passages'] as List)
                .map(StudyPassage.fromJson)
                .whereType<StudyPassage>()
                .toList()
          : const [],
    );
  }
}

@immutable
class StudyWorkspace {
  const StudyWorkspace({
    required this.id,
    required this.name,
    this.words = const [],
    this.themes = const [],
    this.highlightsEnabled = true,
    this.wordColorValue = defaultStudyWordColorValue,
    this.passageColorValue = defaultStudyPassageColorValue,
  });

  final String id;
  final String name;
  final List<StudyWord> words;
  final List<StudyTheme> themes;
  final bool highlightsEnabled;
  final int wordColorValue;
  final int passageColorValue;

  StudyWorkspace copyWith({
    String? name,
    List<StudyWord>? words,
    List<StudyTheme>? themes,
    bool? highlightsEnabled,
    int? wordColorValue,
    int? passageColorValue,
  }) => StudyWorkspace(
    id: id,
    name: name ?? this.name,
    words: words ?? this.words,
    themes: themes ?? this.themes,
    highlightsEnabled: highlightsEnabled ?? this.highlightsEnabled,
    wordColorValue: wordColorValue ?? this.wordColorValue,
    passageColorValue: passageColorValue ?? this.passageColorValue,
  );

  StudyWord? wordForRoot(String root) {
    if (root.isEmpty) return null;
    for (final word in words) {
      if (word.root == root) return word;
    }
    return null;
  }

  StudyTheme? themeById(String id) {
    for (final theme in themes) {
      if (theme.id == id) return theme;
    }
    return null;
  }

  StudyPassage? passageAt(int bookIndex, int chapter, int verse) {
    for (final theme in themes) {
      final passage = theme.passageAt(bookIndex, chapter, verse);
      if (passage != null) return passage;
    }
    return null;
  }

  StudyWorkspace putWord(StudyWord word) {
    final updated = List<StudyWord>.of(words);
    var index = updated.indexWhere(
      (candidate) => candidate.root.isNotEmpty && candidate.root == word.root,
    );
    if (index < 0 && word.root.isNotEmpty) {
      index = updated.indexWhere(
        (candidate) =>
            candidate.root.isEmpty && candidate.surface == word.surface,
      );
    }
    if (index < 0) {
      updated.add(word);
    } else {
      updated[index] = word;
    }
    return copyWith(words: updated);
  }

  StudyWorkspace removeWord(StudyWord word) => copyWith(
    words: words
        .where(
          (candidate) => word.root.isNotEmpty
              ? candidate.root != word.root
              : candidate.root.isNotEmpty || candidate.surface != word.surface,
        )
        .toList(),
  );

  StudyWorkspace putTheme(StudyTheme theme) {
    final updated = List<StudyTheme>.of(themes);
    final index = updated.indexWhere((candidate) => candidate.id == theme.id);
    if (index < 0) {
      updated.add(theme);
    } else {
      updated[index] = theme;
    }
    return copyWith(themes: updated);
  }

  StudyWorkspace removeTheme(StudyTheme theme) => copyWith(
    themes: themes.where((candidate) => candidate.id != theme.id).toList(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'words': words.map((word) => word.toJson()).toList(),
    'themes': themes.map((theme) => theme.toJson()).toList(),
    if (!highlightsEnabled) 'highlights': false,
    'wordColor': wordColorValue,
    'passageColor': passageColorValue,
  };

  static StudyWorkspace? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    final words = value['words'] is List
        ? (value['words'] as List)
              .map(StudyWord.fromJson)
              .whereType<StudyWord>()
              .toList()
        : <StudyWord>[];
    var themes = value['themes'] is List
        ? (value['themes'] as List)
              .map(StudyTheme.fromJson)
              .whereType<StudyTheme>()
              .toList()
        : <StudyTheme>[];

    // Migrate the earlier one-central-passage workspace shape into a first
    // passage theme without dropping notes or linked references.
    if (themes.isEmpty && value['central'] != null) {
      final central = StudyPassage.fromJson(value['central']);
      final passages = value['passages'] is List
          ? (value['passages'] as List)
                .map(StudyPassage.fromJson)
                .whereType<StudyPassage>()
                .toList()
          : <StudyPassage>[];
      if (central != null &&
          !passages.any(
            (passage) => passage.locationKey == central.locationKey,
          )) {
        passages.insert(0, central);
      }
      themes = [
        StudyTheme(id: '$id-passages', name: 'Passages', passages: passages),
      ];
    }

    int storedColor(Object? raw, int fallback) =>
        raw is int && raw >= 0 && raw <= 0xffffffff ? raw : fallback;

    return StudyWorkspace(
      id: id,
      name: name,
      words: words,
      themes: themes,
      highlightsEnabled: value['highlights'] is bool
          ? value['highlights'] as bool
          : true,
      wordColorValue: storedColor(
        value['wordColor'],
        defaultStudyWordColorValue,
      ),
      passageColorValue: storedColor(
        value['passageColor'],
        defaultStudyPassageColorValue,
      ),
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
