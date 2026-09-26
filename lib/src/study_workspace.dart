import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'surface.dart';
import 'bible_data.dart';

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
    this.wholeChapter = false,
    this.endChapter,
    this.endVerse,
    this.startWord,
    this.endWord,
    this.groupId,
    this.note = '',
    this.highlightEnabled = true,
    this.colorValue = defaultStudyPassageColorValue,
    this.order = 0,
  });

  final int bookIndex;
  final int chapter;
  final int verse;
  final bool wholeChapter;
  final int? endChapter;
  final int? endVerse;

  /// Inclusive, zero-based lexical positions, excluding standalone punctuation.
  /// Both endpoints are present for a phrase, and absent for whole verses.
  final int? startWord;
  final int? endWord;
  int get lastChapter => endChapter ?? chapter;
  int get lastVerse => endVerse ?? verse;
  bool get isPhrase => startWord != null;

  bool get isValid =>
      bookIndex >= 0 &&
      bookIndex < kBooks.length &&
      chapter >= 1 &&
      lastChapter <= kBooks[bookIndex].chapters &&
      lastChapter >= chapter &&
      verse >= 1 &&
      lastVerse >= 1 &&
      (lastChapter > chapter || lastVerse >= verse) &&
      ((startWord == null && endWord == null) ||
          (startWord != null &&
              endWord != null &&
              startWord! >= 0 &&
              endWord! >= 0 &&
              (lastChapter > chapter ||
                  lastVerse > verse ||
                  endWord! >= startWord!))) &&
      (!wholeChapter ||
          (verse == 1 && endChapter == null && endVerse == null && !isPhrase));

  bool containsVerse(int book, int ch, int v) =>
      book == bookIndex &&
      (wholeChapter
          ? ch == chapter
          : (ch > chapter || (ch == chapter && v >= verse)) &&
                (ch < lastChapter || (ch == lastChapter && v <= lastVerse)));

  bool containsWord(int book, int ch, int v, int position) =>
      containsVerse(book, ch, v) &&
      (!isPhrase ||
          ((ch != chapter || v != verse || position >= startWord!) &&
              (ch != lastChapter || v != lastVerse || position <= endWord!)));

  String get reference {
    if (wholeChapter) return '$chapter';
    final start = '$chapter:$verse';
    final end = lastChapter == chapter
        ? '$lastVerse'
        : '$lastChapter:$lastVerse';
    if (isPhrase) {
      if (chapter == lastChapter && verse == lastVerse) {
        return '$start · words ${startWord! + 1}–${endWord! + 1}';
      }
      return '$start word ${startWord! + 1}–$end word ${endWord! + 1}';
    }
    return chapter == lastChapter && verse == lastVerse ? start : '$start–$end';
  }

  /// Change only the reference; retain the outline item and its annotations.
  StudyPassage withReference(StudyPassage ref) => StudyPassage(
    bookIndex: ref.bookIndex,
    chapter: ref.chapter,
    verse: ref.verse,
    wholeChapter: ref.wholeChapter,
    endChapter: ref.endChapter,
    endVerse: ref.endVerse,
    startWord: ref.startWord,
    endWord: ref.endWord,
    groupId: groupId,
    note: note,
    highlightEnabled: highlightEnabled,
    colorValue: colorValue,
    order: order,
  );
  final String? groupId;
  final String note;
  final bool highlightEnabled;
  final int colorValue;
  final int order;

  String get locationKey {
    if (wholeChapter) return '$bookIndex:$chapter';
    final start = '$bookIndex:$chapter:$verse';
    final range = lastChapter == chapter && lastVerse == verse
        ? start
        : '$start-$lastChapter:$lastVerse';
    return isPhrase ? '$range@$startWord-$endWord' : range;
  }

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
    wholeChapter: wholeChapter,
    endChapter: endChapter,
    endVerse: endVerse,
    startWord: startWord,
    endWord: endWord,
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
    if (wholeChapter) 'wholeChapter': true,
    if (endChapter != null) 'endChapter': endChapter,
    if (endVerse != null) 'endVerse': endVerse,
    if (startWord != null) 'startWord': startWord,
    if (endWord != null) 'endWord': endWord,
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
    for (final key in ['endChapter', 'endVerse', 'startWord', 'endWord']) {
      if (value[key] != null && value[key] is! int) return null;
    }
    if (value['wholeChapter'] != null && value['wholeChapter'] is! bool) {
      return null;
    }
    final passage = StudyPassage(
      wholeChapter: value['wholeChapter'] == true,
      endChapter: value['endChapter'] as int?,
      endVerse: value['endVerse'] as int?,
      startWord: value['startWord'] as int?,
      endWord: value['endWord'] as int?,
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
    return passage.isValid ? passage : null;
  }
}

enum StudyWordKind { root, form }

/// Pointed Hebrew forms ignore trope and combining-mark order. Syriac forms
/// retain their letters and pointing while dropping punctuation.
String studyFormKey(String surface) =>
    RegExp(r'[\u0710-\u072F\u074D-\u074F]').hasMatch(surface)
    ? surface.replaceAll(RegExp(r'[^\u0710-\u074A\u074D-\u074F]'), '')
    : hebrewSurfaceKey(surface);

@immutable
class StudyWord {
  const StudyWord({
    required this.root,
    required this.surface,
    this.kind = StudyWordKind.root,
    this.groupId,
    this.note = '',
    this.highlightEnabled = true,
    this.colorValue = defaultStudyWordColorValue,
    this.order = 0,
  });

  /// The resolved consonantal root, or empty for an unresolved legacy word or
  /// a form saved without lexicon data.
  final String root;
  final String surface;
  final StudyWordKind kind;

  static String formKey(String root, String surface) =>
      jsonEncode([root, studyFormKey(surface)]);

  String get key => kind == StudyWordKind.form
      ? 'word-form-${formKey(root, surface)}'
      : root.isNotEmpty
      ? 'word-root-$root'
      : 'word-surface-$surface';

  String get title =>
      kind == StudyWordKind.form || root.isEmpty ? surface : root;
  final String? groupId;
  final String note;
  final bool highlightEnabled;
  final int colorValue;
  final int order;

  StudyWord copyWith({
    StudyWordKind? kind,
    String? surface,
    String? Function()? groupId,
    String? note,
    bool? highlightEnabled,
    int? colorValue,
    int? order,
  }) => StudyWord(
    root: root,
    surface: surface ?? this.surface,
    kind: kind ?? this.kind,
    groupId: groupId == null ? this.groupId : groupId(),
    note: note ?? this.note,
    highlightEnabled: highlightEnabled ?? this.highlightEnabled,
    colorValue: colorValue ?? this.colorValue,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    'root': root,
    'surface': surface,
    if (kind != StudyWordKind.root) 'kind': kind.name,
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
      kind: value['kind'] == 'form' ? StudyWordKind.form : StudyWordKind.root,
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

enum StudyItemType { passage, word, note, group }

@immutable
class StudyItem {
  const StudyItem._(this.type, this.value, this.order);

  final StudyItemType type;
  final Object value;
  final int order;

  String get key => switch (type) {
    StudyItemType.passage => 'passage-${(value as StudyPassage).locationKey}',
    StudyItemType.word => (value as StudyWord).key,
    StudyItemType.note => 'note-${(value as StudyNote).id}',
    StudyItemType.group => 'group-${(value as StudyGroup).id}',
  };

  String? get groupId => switch (type) {
    StudyItemType.passage => (value as StudyPassage).groupId,
    StudyItemType.word => (value as StudyWord).groupId,
    StudyItemType.note => (value as StudyNote).groupId,
    StudyItemType.group => (value as StudyGroup).parentId,
  };
}

@immutable
class StudyGroup {
  const StudyGroup({
    required this.id,
    required this.name,
    this.parentId,
    this.order = 0,
  });

  final String id;
  final String name;
  final String? parentId;
  final int order;

  StudyGroup copyWith({
    String? name,
    String? Function()? parentId,
    int? order,
  }) => StudyGroup(
    id: id,
    name: name ?? this.name,
    parentId: parentId == null ? this.parentId : parentId(),
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (parentId != null) 'parent': parentId,
    'order': order,
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
      order: value['order'] is int ? value['order'] as int : 0,
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
      if (word.kind == StudyWordKind.root && word.root == root) return word;
    }
    return null;
  }

  StudyWord? wordForBookmark(StudyWord bookmark) {
    for (final word in words) {
      if (word.key == bookmark.key) return word;
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

  Iterable<StudyPassage> passagesAt(int book, int chapter, int verse) =>
      passages.where((p) => p.containsVerse(book, chapter, verse));

  /// Replace in place, rejecting collisions instead of overwriting another item.
  StudyWorkspace replacePassage(
    StudyPassage original,
    StudyPassage replacement,
  ) {
    if (!replacement.isValid ||
        passages.any(
          (p) =>
              p.locationKey != original.locationKey &&
              p.locationKey == replacement.locationKey,
        )) {
      return this;
    }
    return copyWith(
      passages: [
        for (final p in passages)
          p.locationKey == original.locationKey
              ? p.withReference(replacement).copyWith(note: replacement.note)
              : p,
      ],
    );
  }

  StudyGroup? groupById(String? id) {
    if (id == null) return null;
    for (final group in groups) {
      if (group.id == id) return group;
    }
    return null;
  }

  List<StudyGroup> childGroups(String? parentId) => itemsIn(parentId)
      .where((item) => item.type == StudyItemType.group)
      .map((item) => item.value as StudyGroup)
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
      for (final group in groups)
        if (group.parentId == groupId)
          StudyItem._(StudyItemType.group, group, group.order),
    ];
    // Retain the original list order for legacy items with tied order values.
    final positions = {for (var i = 0; i < items.length; i++) items[i]: i};
    items.sort((a, b) {
      final order = a.order.compareTo(b.order);
      return order != 0 ? order : positions[a]!.compareTo(positions[b]!);
    });
    return items;
  }

  /// One past the highest order among [groupId]'s items — the last of
  /// [itemsIn], found without building and sorting that list.
  int nextOrder(String? groupId) {
    int? highest;
    void consider(int order) {
      if (highest == null || order > highest!) highest = order;
    }

    for (final passage in passages) {
      if (passage.groupId == groupId) consider(passage.order);
    }
    for (final word in words) {
      if (word.groupId == groupId) consider(word.order);
    }
    for (final note in notes) {
      if (note.groupId == groupId) consider(note.order);
    }
    for (final group in groups) {
      if (group.parentId == groupId) consider(group.order);
    }
    return highest == null ? 0 : highest! + 1;
  }

  StudyWorkspace putWord(StudyWord word) {
    final updated = List<StudyWord>.of(words);
    var index = updated.indexWhere((candidate) => candidate.key == word.key);
    if (index < 0 && word.kind == StudyWordKind.root && word.root.isNotEmpty) {
      index = updated.indexWhere(
        (candidate) =>
            candidate.kind == StudyWordKind.root &&
            candidate.root.isEmpty &&
            candidate.surface == word.surface,
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

  bool canSwitchWordKind(StudyWord word) {
    final existing = wordForBookmark(word);
    if (existing == null ||
        (existing.kind == StudyWordKind.form && existing.root.isEmpty)) {
      return false;
    }
    final target = existing.copyWith(
      kind: existing.kind == StudyWordKind.root
          ? StudyWordKind.form
          : StudyWordKind.root,
    );
    return wordForBookmark(target) == null;
  }

  StudyWorkspace switchWordKind(StudyWord word) {
    if (!canSwitchWordKind(word)) return this;
    return copyWith(
      words: [
        for (final existing in words)
          if (existing.key == word.key)
            existing.copyWith(
              kind: existing.kind == StudyWordKind.root
                  ? StudyWordKind.form
                  : StudyWordKind.root,
            )
          else
            existing,
      ],
    );
  }

  StudyWorkspace removeWord(StudyWord word) => copyWith(
    words: words.where((candidate) => candidate.key != word.key).toList(),
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
    return moveItem(items[oldIndex], groupId, index: newIndex);
  }

  bool canMoveItem(StudyItem item, String? groupId) {
    if (groupId != null && groupById(groupId) == null) return false;
    if (!itemsIn(item.groupId).any((candidate) => candidate.key == item.key)) {
      return false;
    }
    if (item.type == StudyItemType.group) {
      final visited = <String>{(item.value as StudyGroup).id};
      var ancestor = groupId;
      while (ancestor != null) {
        if (!visited.add(ancestor)) return false;
        ancestor = groupById(ancestor)?.parentId;
      }
    }
    return true;
  }

  /// Move to a sibling insertion position, or append when no index is given.
  /// Positions refer to the destination outline before removing the source.
  StudyWorkspace moveItem(StudyItem item, String? groupId, {int? index}) {
    if (!canMoveItem(item, groupId)) return this;
    final source = itemsIn(item.groupId);
    final current = source.firstWhere((candidate) => candidate.key == item.key);
    final destination = itemsIn(groupId);
    var position = index ?? destination.length;
    if (position < 0 || position > destination.length) return this;
    if (item.groupId == groupId) {
      final oldIndex = destination.indexWhere((entry) => entry.key == item.key);
      destination.removeAt(oldIndex);
      if (position > oldIndex) position--;
    }
    destination.insert(position, current);
    var updated = this;
    for (var i = 0; i < destination.length; i++) {
      updated = updated._placeItem(destination[i], groupId, i);
    }
    return updated;
  }

  StudyWorkspace _placeItem(StudyItem item, String? groupId, int order) =>
      switch (item.type) {
        StudyItemType.passage => copyWith(
          passages: [
            for (final passage in passages)
              passage.locationKey == (item.value as StudyPassage).locationKey
                  ? passage.copyWith(groupId: () => groupId, order: order)
                  : passage,
          ],
        ),
        StudyItemType.word => copyWith(
          words: [
            for (final word in words)
              StudyItem._(StudyItemType.word, word, word.order).key == item.key
                  ? word.copyWith(groupId: () => groupId, order: order)
                  : word,
          ],
        ),
        StudyItemType.note => copyWith(
          notes: [
            for (final note in notes)
              note.id == (item.value as StudyNote).id
                  ? note.copyWith(groupId: () => groupId, order: order)
                  : note,
          ],
        ),
        StudyItemType.group => copyWith(
          groups: [
            for (final group in groups)
              group.id == (item.value as StudyGroup).id
                  ? group.copyWith(parentId: () => groupId, order: order)
                  : group,
          ],
        ),
      };

  StudyWorkspace putGroup(StudyGroup group) {
    final updated = List<StudyGroup>.of(groups);
    final index = updated.indexWhere((candidate) => candidate.id == group.id);
    if (index < 0) {
      updated.add(group.copyWith(order: nextOrder(group.parentId)));
    } else {
      updated[index] = updated[index].parentId == group.parentId
          ? group
          : group.copyWith(order: nextOrder(group.parentId));
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

    // Before groups were orderable, every level displayed its items first,
    // followed by its groups in storage order. Preserve that layout on load.
    final storedGroupOrders = <String, int>{
      for (final raw in value['groups'] is List ? value['groups'] as List : [])
        if (raw is Map && raw['id'] is String && raw['order'] is int)
          raw['id'] as String: raw['order'] as int,
    };
    final nextOrders = <String?, int>{};
    void accountFor(String? parent, int order) {
      if (order >= (nextOrders[parent] ?? 0)) nextOrders[parent] = order + 1;
    }

    for (final passage in passages) {
      accountFor(passage.groupId, passage.order);
    }
    for (final word in words) {
      accountFor(word.groupId, word.order);
    }
    for (final note in notes) {
      accountFor(note.groupId, note.order);
    }
    for (final group in groups) {
      final order = storedGroupOrders[group.id];
      if (order != null) accountFor(group.parentId, order);
    }
    groups = groups.map((group) {
      if (storedGroupOrders.containsKey(group.id)) return group;
      final order = nextOrders[group.parentId] ?? 0;
      nextOrders[group.parentId] = order + 1;
      return group.copyWith(order: order);
    }).toList();

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

/// Stores [workspaces]; pass [encoded] when the caller has already encoded
/// them (to send them to Rust as well), so the JSON is built only once.
Future<void> saveStudyWorkspaces(
  SharedPreferences prefs,
  List<StudyWorkspace> workspaces,
  String? activeWorkspaceId, {
  String? encoded,
}) async {
  await prefs.setString(
    studyWorkspacesKey,
    encoded ?? encodeStudyWorkspaces(workspaces),
  );
  if (activeWorkspaceId == null) {
    await prefs.remove(activeStudyWorkspaceKey);
  } else {
    await prefs.setString(activeStudyWorkspaceKey, activeWorkspaceId);
  }
}
