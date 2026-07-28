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
    this.groupId,
    this.note = '',
    this.highlightEnabled = true,
    this.colorValue = defaultStudyPassageColorValue,
    this.order = 0,
  });

  final int bookIndex;
  final int chapter;
  final int verse;
  final String? groupId;
  final String note;
  final bool highlightEnabled;
  final int colorValue;
  final int order;

  String get locationKey => '$bookIndex:$chapter:$verse';

  StudyPassage copyWith({
    String? Function()? groupId,
    String? note,
    bool? highlightEnabled,
    int? colorValue,
    int? order,
  }) => StudyPassage(
    bookIndex: bookIndex,
    chapter: chapter,
    verse: verse,
    groupId: groupId == null ? this.groupId : groupId(),
    note: note ?? this.note,
    highlightEnabled: highlightEnabled ?? this.highlightEnabled,
    colorValue: colorValue ?? this.colorValue,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    'book': bookIndex,
    'chapter': chapter,
    'verse': verse,
    if (groupId != null) 'group': groupId,
    if (note.isNotEmpty) 'note': note,
    if (!highlightEnabled) 'highlight': false,
    if (colorValue != defaultStudyPassageColorValue) 'color': colorValue,
    'order': order,
  };

  static StudyPassage? fromJson(
    Object? value, {
    String? legacyGroupId,
    bool legacyHighlightsEnabled = true,
    int legacyColorValue = defaultStudyPassageColorValue,
  }) {
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
      groupId: value['group'] is String
          ? value['group'] as String
          : legacyGroupId,
      note: value['note'] is String ? value['note'] as String : '',
      highlightEnabled:
          legacyHighlightsEnabled &&
          (value['highlight'] is bool ? value['highlight'] as bool : true),
      colorValue: _storedColor(value['color'], legacyColorValue),
      order: value['order'] is int ? value['order'] as int : 0,
    );
  }
}

@immutable
class StudyWord {
  const StudyWord({
    required this.root,
    required this.surface,
    this.groupId,
    this.note = '',
    this.highlightEnabled = true,
    this.colorValue = defaultStudyWordColorValue,
    this.order = 0,
  });

  /// The resolved consonantal root. This is the bookmark key: every reader
  /// token carrying the same root is highlighted.
  final String root;
  final String surface;
  final String? groupId;
  final String note;
  final bool highlightEnabled;
  final int colorValue;
  final int order;

  StudyWord copyWith({
    String? surface,
    String? Function()? groupId,
    String? note,
    bool? highlightEnabled,
    int? colorValue,
    int? order,
  }) => StudyWord(
    root: root,
    surface: surface ?? this.surface,
    groupId: groupId == null ? this.groupId : groupId(),
    note: note ?? this.note,
    highlightEnabled: highlightEnabled ?? this.highlightEnabled,
    colorValue: colorValue ?? this.colorValue,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    'root': root,
    'surface': surface,
    if (groupId != null) 'group': groupId,
    if (note.isNotEmpty) 'note': note,
    if (!highlightEnabled) 'highlight': false,
    if (colorValue != defaultStudyWordColorValue) 'color': colorValue,
    'order': order,
  };

  static StudyWord? fromJson(
    Object? value, {
    bool legacyHighlightsEnabled = true,
    int legacyColorValue = defaultStudyWordColorValue,
  }) {
    if (value is! Map) return null;
    final root = value['root'];
    final surface = value['surface'];
    if (surface is! String || surface.isEmpty) return null;
    // The oldest shape stored one verse occurrence instead of a root. Preserve
    // it as a visible bookmark, but do not falsely highlight homographs.
    return StudyWord(
      root: root is String ? root : '',
      surface: surface,
      groupId: value['group'] is String ? value['group'] as String : null,
      note: value['note'] is String ? value['note'] as String : '',
      highlightEnabled:
          legacyHighlightsEnabled &&
          (value['highlight'] is bool ? value['highlight'] as bool : true),
      colorValue: _storedColor(value['color'], legacyColorValue),
      order: value['order'] is int ? value['order'] as int : 0,
    );
  }
}

@immutable
class StudyNote {
  const StudyNote({
    required this.id,
    required this.text,
    this.groupId,
    this.order = 0,
  });

  final String id;
  final String text;
  final String? groupId;
  final int order;

  StudyNote copyWith({String? text, String? Function()? groupId, int? order}) =>
      StudyNote(
        id: id,
        text: text ?? this.text,
        groupId: groupId == null ? this.groupId : groupId(),
        order: order ?? this.order,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    if (groupId != null) 'group': groupId,
    'order': order,
  };

  static StudyNote? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final text = value['text'];
    if (id is! String || id.isEmpty || text is! String || text.isEmpty) {
      return null;
    }
    return StudyNote(
      id: id,
      text: text,
      groupId: value['group'] is String ? value['group'] as String : null,
      order: value['order'] is int ? value['order'] as int : 0,
    );
  }
}

enum StudyItemType { passage, word, note }

@immutable
class StudyItem {
  const StudyItem._(this.type, this.value, this.order);

  final StudyItemType type;
  final Object value;
  final int order;
}

@immutable
class StudyGroup {
  const StudyGroup({required this.id, required this.name, this.parentId});

  final String id;
  final String name;
  final String? parentId;

  StudyGroup copyWith({String? name, String? Function()? parentId}) =>
      StudyGroup(
        id: id,
        name: name ?? this.name,
        parentId: parentId == null ? this.parentId : parentId(),
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (parentId != null) 'parent': parentId,
  };

  static StudyGroup? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    return StudyGroup(
      id: id,
      name: name,
      parentId: value['parent'] is String ? value['parent'] as String : null,
    );
  }
}

@immutable
class StudyWorkspace {
  const StudyWorkspace({
    required this.id,
    required this.name,
    this.highlightsEnabled = true,
    this.groups = const [],
    this.passages = const [],
    this.words = const [],
    this.notes = const [],
  });

  final String id;
  final String name;
  final bool highlightsEnabled;
  final List<StudyGroup> groups;
  final List<StudyPassage> passages;
  final List<StudyWord> words;
  final List<StudyNote> notes;

  StudyWorkspace copyWith({
    String? name,
    bool? highlightsEnabled,
    List<StudyGroup>? groups,
    List<StudyPassage>? passages,
    List<StudyWord>? words,
    List<StudyNote>? notes,
  }) => StudyWorkspace(
    id: id,
    name: name ?? this.name,
    highlightsEnabled: highlightsEnabled ?? this.highlightsEnabled,
    groups: groups ?? this.groups,
    passages: passages ?? this.passages,
    words: words ?? this.words,
    notes: notes ?? this.notes,
  );

  StudyWord? wordForRoot(String root) {
    if (root.isEmpty) return null;
    for (final word in words) {
      if (word.root == root) return word;
    }
    return null;
  }

  StudyPassage? passageAt(int bookIndex, int chapter, int verse) {
    final key = '$bookIndex:$chapter:$verse';
    for (final passage in passages) {
      if (passage.locationKey == key) return passage;
    }
    return null;
  }

  StudyGroup? groupById(String? id) {
    if (id == null) return null;
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  List<StudyGroup> childGroups(String? parentId) => groups
      .where((group) => group.parentId == parentId)
      .toList(growable: false);

  List<StudyItem> itemsIn(String? groupId) {
    final items = <StudyItem>[
      for (final passage in passages)
        if (passage.groupId == groupId)
          StudyItem._(StudyItemType.passage, passage, passage.order),
      for (final word in words)
        if (word.groupId == groupId)
          StudyItem._(StudyItemType.word, word, word.order),
      for (final note in notes)
        if (note.groupId == groupId)
          StudyItem._(StudyItemType.note, note, note.order),
    ];
    items.sort((a, b) => a.order.compareTo(b.order));
    return items;
  }

  int nextOrder(String? groupId) {
    final items = itemsIn(groupId);
    return items.isEmpty ? 0 : items.last.order + 1;
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
      updated.add(word.copyWith(order: nextOrder(word.groupId)));
    } else {
      updated[index] = updated[index].groupId == word.groupId
          ? word
          : word.copyWith(order: nextOrder(word.groupId));
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

  StudyWorkspace putPassage(StudyPassage passage) {
    final updated = List<StudyPassage>.of(passages);
    final index = updated.indexWhere(
      (candidate) => candidate.locationKey == passage.locationKey,
    );
    if (index < 0) {
      updated.add(passage.copyWith(order: nextOrder(passage.groupId)));
    } else {
      updated[index] = updated[index].groupId == passage.groupId
          ? passage
          : passage.copyWith(order: nextOrder(passage.groupId));
    }
    return copyWith(passages: updated);
  }

  StudyWorkspace removePassage(StudyPassage passage) => copyWith(
    passages: passages
        .where((candidate) => candidate.locationKey != passage.locationKey)
        .toList(),
  );

  StudyWorkspace putNote(StudyNote note) {
    final updated = List<StudyNote>.of(notes);
    final index = updated.indexWhere((candidate) => candidate.id == note.id);
    if (index < 0) {
      updated.add(note.copyWith(order: nextOrder(note.groupId)));
    } else {
      updated[index] = updated[index].groupId == note.groupId
          ? note
          : note.copyWith(order: nextOrder(note.groupId));
    }
    return copyWith(notes: updated);
  }

  StudyWorkspace removeNote(StudyNote note) => copyWith(
    notes: notes.where((candidate) => candidate.id != note.id).toList(),
  );

  StudyWorkspace reorderItems(String? groupId, int oldIndex, int newIndex) {
    final items = itemsIn(groupId);
    if (oldIndex < 0 || oldIndex >= items.length) return this;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= items.length) return this;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    var updated = this;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      switch (item.type) {
        case StudyItemType.passage:
          updated = updated.putPassage(
            (item.value as StudyPassage).copyWith(order: index),
          );
        case StudyItemType.word:
          updated = updated.putWord(
            (item.value as StudyWord).copyWith(order: index),
          );
        case StudyItemType.note:
          updated = updated.putNote(
            (item.value as StudyNote).copyWith(order: index),
          );
      }
    }
    return updated;
  }

  StudyWorkspace putGroup(StudyGroup group) {
    final updated = List<StudyGroup>.of(groups);
    final index = updated.indexWhere((candidate) => candidate.id == group.id);
    if (index < 0) {
      updated.add(group);
    } else {
      updated[index] = group;
    }
    return copyWith(groups: updated);
  }

  /// Delete a group without deleting its study material. Direct children and
  /// items are promoted to the deleted group's parent.
  StudyWorkspace removeGroup(StudyGroup group) {
    final parentId = group.parentId;
    return copyWith(
      groups: [
        for (final candidate in groups)
          if (candidate.id != group.id)
            candidate.parentId == group.id
                ? candidate.copyWith(parentId: () => parentId)
                : candidate,
      ],
      passages: [
        for (final passage in passages)
          passage.groupId == group.id
              ? passage.copyWith(groupId: () => parentId)
              : passage,
      ],
      words: [
        for (final word in words)
          word.groupId == group.id
              ? word.copyWith(groupId: () => parentId)
              : word,
      ],
      notes: [
        for (final note in notes)
          note.groupId == group.id
              ? note.copyWith(groupId: () => parentId)
              : note,
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (!highlightsEnabled) 'highlights': false,
    'ordered': true,
    'groups': groups.map((group) => group.toJson()).toList(),
    'passages': passages.map((passage) => passage.toJson()).toList(),
    'words': words.map((word) => word.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
  };

  static StudyWorkspace? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }

    final highlightsEnabled =
        value['highlights'] is! bool || value['highlights'] as bool;
    final legacyWordColor = _storedColor(
      value['wordColor'],
      defaultStudyWordColorValue,
    );
    final legacyPassageColor = _storedColor(
      value['passageColor'],
      defaultStudyPassageColorValue,
    );

    var words = value['words'] is List
        ? (value['words'] as List)
              .map(
                (word) =>
                    StudyWord.fromJson(word, legacyColorValue: legacyWordColor),
              )
              .whereType<StudyWord>()
              .toList()
        : <StudyWord>[];
    var notes = value['notes'] is List
        ? (value['notes'] as List)
              .map(StudyNote.fromJson)
              .whereType<StudyNote>()
              .toList()
        : <StudyNote>[];
    var groups = value['groups'] is List
        ? (value['groups'] as List)
              .map(StudyGroup.fromJson)
              .whereType<StudyGroup>()
              .toList()
        : <StudyGroup>[];
    var passages = value['passages'] is List
        ? (value['passages'] as List)
              .map(
                (passage) => StudyPassage.fromJson(
                  passage,
                  legacyColorValue: legacyPassageColor,
                ),
              )
              .whereType<StudyPassage>()
              .toList()
        : <StudyPassage>[];

    // Migrate the immediately preceding shape: each theme becomes a group and
    // its passages become ordinary items assigned to that group.
    if (groups.isEmpty && value['themes'] is List) {
      for (final rawTheme in value['themes'] as List) {
        if (rawTheme is! Map) continue;
        final group = StudyGroup.fromJson({
          'id': rawTheme['id'],
          'name': rawTheme['name'],
          'note': rawTheme['note'],
        });
        if (group == null) continue;
        groups.add(group);
        if (rawTheme['passages'] is List) {
          for (final rawPassage in rawTheme['passages'] as List) {
            final passage = StudyPassage.fromJson(
              rawPassage,
              legacyGroupId: group.id,
              legacyColorValue: legacyPassageColor,
            );
            if (passage != null &&
                !passages.any(
                  (candidate) => candidate.locationKey == passage.locationKey,
                )) {
              passages.add(passage);
            }
          }
        }
      }
    }

    // Migrate the oldest one-central-passage shape directly when it has never
    // passed through the theme version.
    if (groups.isEmpty && value['central'] != null) {
      final group = StudyGroup(id: '$id-passages', name: 'Passages');
      groups = [group];
      final oldPassages = value['passages'] is List
          ? value['passages'] as List
          : const [];
      passages = [];
      for (final raw in oldPassages) {
        final passage = StudyPassage.fromJson(
          raw,
          legacyGroupId: group.id,
          legacyColorValue: legacyPassageColor,
        );
        if (passage != null) passages.add(passage);
      }
      final central = StudyPassage.fromJson(
        value['central'],
        legacyGroupId: group.id,
        legacyColorValue: legacyPassageColor,
      );
      if (central != null &&
          !passages.any(
            (passage) => passage.locationKey == central.locationKey,
          )) {
        passages.insert(0, central);
      }
    }

    final groupIds = groups.map((group) => group.id).toSet();
    groups = [
      for (final group in groups)
        group.parentId == null ||
                group.parentId == group.id ||
                !groupIds.contains(group.parentId)
            ? group.copyWith(parentId: () => null)
            : group,
    ];
    passages = [
      for (final passage in passages)
        passage.groupId == null || groupIds.contains(passage.groupId)
            ? passage
            : passage.copyWith(groupId: () => null),
    ];
    final validWords = [
      for (final word in words)
        word.groupId == null || groupIds.contains(word.groupId)
            ? word
            : word.copyWith(groupId: () => null),
    ];
    notes = [
      for (final note in notes)
        note.groupId == null || groupIds.contains(note.groupId)
            ? note
            : note.copyWith(groupId: () => null),
    ];

    // Older data had no mixed item ordering. Preserve its visible order
    // (passages followed by words) and turn former group notes into ordinary
    // paragraph items at the start of each group.
    final hasStoredOrder = value['ordered'] == true;
    if (!hasStoredOrder) {
      final counters = <String?, int>{};
      int takeOrder(String? groupId) {
        final order = counters[groupId] ?? 0;
        counters[groupId] = order + 1;
        return order;
      }

      for (final group in groups) {
        Map? rawGroup;
        for (final raw in [
          ...?value['groups'] as List?,
          ...?value['themes'] as List?,
        ]) {
          if (raw is Map && raw['id'] == group.id) {
            rawGroup = raw;
            break;
          }
        }
        final legacyNote = rawGroup?['note'];
        if (legacyNote is String && legacyNote.isNotEmpty) {
          notes.add(
            StudyNote(
              id: '${group.id}-legacy-note',
              text: legacyNote,
              groupId: group.id,
              order: takeOrder(group.id),
            ),
          );
        }
      }
      passages = [
        for (final passage in passages)
          passage.copyWith(order: takeOrder(passage.groupId)),
      ];
      words = [
        for (final word in validWords)
          word.copyWith(order: takeOrder(word.groupId)),
      ];
    } else {
      words = validWords;
    }

    return StudyWorkspace(
      id: id,
      name: name,
      highlightsEnabled: highlightsEnabled,
      groups: groups,
      passages: passages,
      words: words,
      notes: notes,
    );
  }
}

int _storedColor(Object? raw, int fallback) =>
    raw is int && raw >= 0 && raw <= 0xffffffff ? raw : fallback;

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
