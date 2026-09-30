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

/// A verse of a bookmarked cross reference, with a 0-based book index as the
/// rest of the study document uses.
typedef StudyLinkVerse = ({int bookIndex, int chapter, int verse});

/// A bookmarked cross reference: an NT verse quoting or echoing an OT verse,
/// or two verses of one testament sharing wording, with the matched words
/// (lexical positions) and the score it was found with, so the outline can
/// show and highlight it without asking the core again.
///
/// The two verses are kept in canonical order (OT before NT, then book,
/// chapter and verse), so a link has one key whichever end it was bookmarked
/// from. The JSON keys `ot` / `nt` (`otWords` / `ntWords`) date from when
/// every link crossed the testaments; they still hold the earlier and the
/// later verse, which for those links is the OT and the NT one.
@immutable
class StudyLink {
  const StudyLink({
    required this.earlier,
    required this.later,
    this.earlierPositions = const [],
    this.laterPositions = const [],
    this.score = 0,
    this.groupId,
    this.note = '',
    this.order = 0,
  });

  final StudyLinkVerse earlier;
  final StudyLinkVerse later;
  final List<int> earlierPositions;
  final List<int> laterPositions;
  final double score;
  final String? groupId;
  final String note;
  final int order;

  static String _verseKey(StudyLinkVerse v) =>
      '${v.bookIndex}:${v.chapter}:${v.verse}';

  String get key => 'link-${_verseKey(earlier)}-${_verseKey(later)}';

  StudyLink copyWith({String? Function()? groupId, String? note, int? order}) =>
      StudyLink(
        earlier: earlier,
        later: later,
        earlierPositions: earlierPositions,
        laterPositions: laterPositions,
        score: score,
        groupId: groupId == null ? this.groupId : groupId(),
        note: note ?? this.note,
        order: order ?? this.order,
      );

  Map<String, Object?> toJson() => {
    'ot': [earlier.bookIndex, earlier.chapter, earlier.verse],
    'nt': [later.bookIndex, later.chapter, later.verse],
    if (earlierPositions.isNotEmpty) 'otWords': earlierPositions,
    if (laterPositions.isNotEmpty) 'ntWords': laterPositions,
    if (score > 0) 'score': score,
    if (groupId != null) 'group': groupId,
    if (note.isNotEmpty) 'note': note,
    'order': order,
  };

  static StudyLinkVerse? _verse(Object? value) {
    if (value is! List || value.length != 3 || value.any((v) => v is! int)) {
      return null;
    }
    final [bookIndex, chapter, verse] = value.cast<int>();
    if (bookIndex < 0 || bookIndex >= kBooks.length) return null;
    return (bookIndex: bookIndex, chapter: chapter, verse: verse);
  }

  static List<int> _positions(Object? value) =>
      value is List ? value.whereType<int>().toList() : const [];

  static StudyLink? fromJson(Object? value) {
    if (value is! Map) return null;
    final earlier = _verse(value['ot']);
    final later = _verse(value['nt']);
    if (earlier == null || later == null) return null;
    return StudyLink(
      earlier: earlier,
      later: later,
      earlierPositions: _positions(value['otWords']),
      laterPositions: _positions(value['ntWords']),
      score: value['score'] is num ? (value['score'] as num).toDouble() : 0,
      groupId: value['group'] is String ? value['group'] as String : null,
      note: value['note'] is String ? value['note'] as String : '',
      order: value['order'] is int ? value['order'] as int : 0,
    );
  }
}

/// A verse's place in a chapter, for ordering section headings.
typedef StudySectionStart = ({int chapter, int verse});

int _compareStarts(StudySectionStart a, StudySectionStart b) {
  final chapter = a.chapter.compareTo(b.chapter);
  return chapter != 0 ? chapter : a.verse.compareTo(b.verse);
}

/// A passage summary, or one of the section headings nested beneath it: an
/// outline container like a group, but anchored to the verse its heading
/// stands before in the reader.
///
/// A summary has a book and covers a whole chapter or a verse range. A
/// heading has only the verse it starts at, in its summary's book, and runs
/// to the next heading beside it (or its parent's end). Headings live only in
/// a summary or another heading; any other item can live in either.
@immutable
class StudySection {
  const StudySection({
    required this.id,
    required this.title,
    required this.chapter,
    required this.verse,
    this.bookIndex,
    this.wholeChapter = false,
    this.endChapter,
    this.endVerse,
    this.note = '',
    this.parentId,
    this.showInReader = true,
    this.order = 0,
  });

  final String id;
  final String title;
  final int chapter;
  final int verse;

  /// Present only for a summary, with its range's end.
  final int? bookIndex;
  final bool wholeChapter;
  final int? endChapter;
  final int? endVerse;
  final String note;
  final String? parentId;

  /// A summary's headings show in the reader; headings follow their summary.
  final bool showInReader;
  final int order;

  bool get isSummary => bookIndex != null;
  StudySectionStart get start => (chapter: chapter, verse: verse);

  /// The verses a summary covers; null for a heading.
  StudyPassage? get range => isSummary
      ? StudyPassage(
          bookIndex: bookIndex!,
          chapter: chapter,
          verse: verse,
          wholeChapter: wholeChapter,
          endChapter: endChapter,
          endVerse: endVerse,
        )
      : null;

  bool get isValid =>
      id.isNotEmpty &&
      title.isNotEmpty &&
      (isSummary
          ? range!.isValid
          : chapter >= 1 &&
                verse >= 1 &&
                !wholeChapter &&
                endChapter == null &&
                endVerse == null);

  /// Change only the anchor or range; retain the outline place and notes.
  StudySection withAnchor(StudySection anchor) => StudySection(
    id: id,
    title: title,
    chapter: anchor.chapter,
    verse: anchor.verse,
    bookIndex: anchor.bookIndex,
    wholeChapter: anchor.wholeChapter,
    endChapter: anchor.endChapter,
    endVerse: anchor.endVerse,
    note: note,
    parentId: parentId,
    showInReader: showInReader,
    order: order,
  );

  StudySection copyWith({
    String? title,
    String? note,
    String? Function()? parentId,
    bool? showInReader,
    int? order,
  }) => StudySection(
    id: id,
    title: title ?? this.title,
    chapter: chapter,
    verse: verse,
    bookIndex: bookIndex,
    wholeChapter: wholeChapter,
    endChapter: endChapter,
    endVerse: endVerse,
    note: note ?? this.note,
    parentId: parentId == null ? this.parentId : parentId(),
    showInReader: showInReader ?? this.showInReader,
    order: order ?? this.order,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'chapter': chapter,
    'verse': verse,
    if (bookIndex != null) 'book': bookIndex,
    if (wholeChapter) 'wholeChapter': true,
    if (endChapter != null) 'endChapter': endChapter,
    if (endVerse != null) 'endVerse': endVerse,
    if (note.isNotEmpty) 'note': note,
    if (parentId != null) 'parent': parentId,
    if (!showInReader) 'inReader': false,
    'order': order,
  };

  static StudySection? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final title = value['title'];
    final chapter = value['chapter'];
    final verse = value['verse'];
    if (id is! String || title is! String || chapter is! int || verse is! int) {
      return null;
    }
    for (final key in ['book', 'endChapter', 'endVerse']) {
      if (value[key] != null && value[key] is! int) return null;
    }
    final section = StudySection(
      id: id,
      title: title,
      chapter: chapter,
      verse: verse,
      bookIndex: value['book'] as int?,
      wholeChapter: value['wholeChapter'] == true,
      endChapter: value['endChapter'] as int?,
      endVerse: value['endVerse'] as int?,
      note: value['note'] is String ? value['note'] as String : '',
      parentId: value['parent'] is String ? value['parent'] as String : null,
      showInReader: value['inReader'] is! bool || value['inReader'] as bool,
      order: value['order'] is int ? value['order'] as int : 0,
    );
    return section.isValid ? section : null;
  }
}

/// A section heading to show in the reader before the verse it starts at,
/// [depth] levels below its [summary] (which is itself at depth 0).
typedef StudyReaderHeading = ({
  StudySection section,
  StudySection summary,
  int depth,
});

enum StudyItemType { passage, word, note, link, group, section }

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
    StudyItemType.link => (value as StudyLink).key,
    StudyItemType.group => 'group-${(value as StudyGroup).id}',
    StudyItemType.section => 'section-${(value as StudySection).id}',
  };

  String? get groupId => switch (type) {
    StudyItemType.passage => (value as StudyPassage).groupId,
    StudyItemType.word => (value as StudyWord).groupId,
    StudyItemType.note => (value as StudyNote).groupId,
    StudyItemType.link => (value as StudyLink).groupId,
    StudyItemType.group => (value as StudyGroup).parentId,
    StudyItemType.section => (value as StudySection).parentId,
  };

  /// A section heading, as opposed to a summary or any other item.
  bool get isHeading =>
      type == StudyItemType.section && !(value as StudySection).isSummary;
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
    this.headingsEnabled = true,
    this.groups = const [],
    this.passages = const [],
    this.words = const [],
    this.notes = const [],
    this.links = const [],
    this.sections = const [],
  });

  final String id;
  final String name;
  final bool highlightsEnabled;

  /// Whether summaries' section headings show in the reader.
  final bool headingsEnabled;
  final List<StudyGroup> groups;
  final List<StudyPassage> passages;
  final List<StudyWord> words;
  final List<StudyNote> notes;
  final List<StudyLink> links;
  final List<StudySection> sections;

  StudyWorkspace copyWith({
    String? name,
    bool? highlightsEnabled,
    bool? headingsEnabled,
    List<StudyGroup>? groups,
    List<StudyPassage>? passages,
    List<StudyWord>? words,
    List<StudyNote>? notes,
    List<StudyLink>? links,
    List<StudySection>? sections,
  }) => StudyWorkspace(
    id: id,
    name: name ?? this.name,
    highlightsEnabled: highlightsEnabled ?? this.highlightsEnabled,
    headingsEnabled: headingsEnabled ?? this.headingsEnabled,
    groups: groups ?? this.groups,
    passages: passages ?? this.passages,
    words: words ?? this.words,
    notes: notes ?? this.notes,
    links: links ?? this.links,
    sections: sections ?? this.sections,
  );

  /// The bookmarked link between an OT and an NT verse, if there is one.
  StudyLink? linkBetween(StudyLinkVerse earlier, StudyLinkVerse later) {
    final key = StudyLink(earlier: earlier, later: later).key;
    for (final link in links) {
      if (link.key == key) return link;
    }
    return null;
  }

  StudyWorkspace putLink(StudyLink link) {
    final updated = List<StudyLink>.of(links);
    final index = updated.indexWhere((candidate) => candidate.key == link.key);
    if (index < 0) {
      updated.add(link.copyWith(order: nextOrder(link.groupId)));
    } else {
      updated[index] = updated[index].groupId == link.groupId
          ? link
          : link.copyWith(order: nextOrder(link.groupId));
    }
    return copyWith(links: updated);
  }

  StudyWorkspace removeLink(StudyLink link) => copyWith(
    links: links.where((candidate) => candidate.key != link.key).toList(),
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

  StudySection? sectionById(String? id) {
    if (id == null) return null;
    for (final section in sections) {
      if (section.id == id) return section;
    }
    return null;
  }

  /// Whether [id] names a group or a section, the outline's containers.
  bool hasContainer(String id) =>
      groupById(id) != null || sectionById(id) != null;

  /// The container holding the group or section [id].
  String? containerParent(String id) =>
      groupById(id)?.parentId ?? sectionById(id)?.parentId;

  String? containerName(String id) =>
      groupById(id)?.name ?? sectionById(id)?.title;

  /// The summary a section belongs to: itself, or its nearest summary above.
  StudySection? summaryOf(StudySection section) {
    final visited = <String>{};
    StudySection? current = section;
    while (current != null && visited.add(current.id)) {
      if (current.isSummary) return current;
      current = sectionById(current.parentId);
    }
    return null;
  }

  /// A section's headings, in verse order.
  List<StudySection> childHeadings(String sectionId) =>
      sections.where((s) => s.parentId == sectionId && !s.isSummary).toList()
        ..sort((a, b) {
          final start = _compareStarts(a.start, b.start);
          return start != 0 ? start : a.order.compareTo(b.order);
        });

  /// Whether a heading starting at [start] may sit directly in [parentId]:
  /// a section, within the verses of its summary, not before the parent.
  bool canPlaceHeading(String? parentId, StudySectionStart start) {
    final parent = sectionById(parentId);
    if (parent == null) return false;
    final range = summaryOf(parent)?.range;
    return range != null &&
        range.containsVerse(range.bookIndex, start.chapter, start.verse) &&
        _compareStarts(start, parent.start) >= 0;
  }

  /// Why [candidate] cannot replace (or join as) the section of its id, or
  /// null when it can: a heading must fit its place, and neither may leave
  /// the headings beneath it out of order or outside its verses.
  String? sectionProblem(StudySection candidate) {
    if (!candidate.isValid) {
      return candidate.title.isEmpty
          ? 'Give the section a title.'
          : 'The end must be at or after the start.';
    }
    if (!candidate.isSummary &&
        !canPlaceHeading(candidate.parentId, candidate.start)) {
      return 'A heading must start within its summary, '
          'and not before the heading it is under.';
    }
    for (final child in childHeadings(candidate.id)) {
      if (_compareStarts(child.start, candidate.start) < 0) {
        return 'Its subheadings must not start before it.';
      }
    }
    // A summary's headings, at every depth, must stay within its verses.
    final range = candidate.range;
    if (range != null && !_headingsWithin(candidate.id, range)) {
      return 'Its headings must stay within the passage.';
    }
    return null;
  }

  /// Every heading beneath the section [id], at any depth.
  List<StudySection> headingsBeneath(String id) {
    final found = <StudySection>[];
    final visited = <String>{id};
    final pending = childHeadings(id);
    while (pending.isNotEmpty) {
      final heading = pending.removeLast();
      if (!visited.add(heading.id)) continue;
      found.add(heading);
      pending.addAll(childHeadings(heading.id));
    }
    return found;
  }

  bool _headingsWithin(String id, StudyPassage range) =>
      headingsBeneath(id).every(
        (heading) => range.containsVerse(
          range.bookIndex,
          heading.chapter,
          heading.verse,
        ),
      );

  /// The sections covering a verse, outermost first: a summary containing it
  /// (one shown in the reader, if any is), then each heading down to the
  /// deepest one it falls under. Empty when no summary contains it.
  List<StudySection> sectionsCovering(int book, int chapter, int verse) {
    final containing = sections.where(
      (s) => s.range?.containsVerse(book, chapter, verse) ?? false,
    );
    final summary =
        containing.where((s) => s.showInReader).firstOrNull ??
        containing.firstOrNull;
    if (summary == null) return const [];
    final chain = [summary];
    final here = (chapter: chapter, verse: verse);
    while (true) {
      final next = childHeadings(
        chain.last.id,
      ).where((h) => _compareStarts(h.start, here) <= 0).lastOrNull;
      if (next == null || chain.contains(next)) return chain;
      chain.add(next);
    }
  }

  /// Where a new heading at a verse belongs by default among [covering]
  /// (from [sectionsCovering]): beside the deepest heading over it, dividing
  /// that section there, or beneath it when it starts on that very verse or
  /// only the summary covers it.
  StudySection? headingParentAt(
    List<StudySection> covering,
    StudySectionStart start,
  ) {
    if (covering.isEmpty) return null;
    final deepest = covering.last;
    if (deepest.isSummary || _compareStarts(deepest.start, start) == 0) {
      return deepest;
    }
    return covering[covering.length - 2];
  }

  /// The derived end of a section: the verse before the next heading beside
  /// it, or else its parent's end, up to its summary's range end. The verse
  /// is null where that is the end of a chapter, whose length is unknown.
  ({int chapter, int? verse}) sectionEnd(StudySection section) {
    final visited = <String>{};
    var current = section;
    while (visited.add(current.id)) {
      if (current.isSummary) {
        final range = current.range!;
        return range.wholeChapter
            ? (chapter: range.chapter, verse: null)
            : (chapter: range.lastChapter, verse: range.lastVerse);
      }
      final parent = sectionById(current.parentId);
      if (parent == null) break;
      final siblings = childHeadings(parent.id);
      final index = siblings.indexWhere((s) => s.id == current.id);
      if (index >= 0 && index + 1 < siblings.length) {
        final next = siblings[index + 1].start;
        return next.verse > 1
            ? (chapter: next.chapter, verse: next.verse - 1)
            : (chapter: next.chapter - 1, verse: null);
      }
      current = parent;
    }
    return (chapter: section.chapter, verse: null);
  }

  /// The headings to show in the reader in [chapter] of [book], in reading
  /// order: each shown summary starting there, and each heading beneath one
  /// that starts there, with its depth below its summary.
  List<StudyReaderHeading> readerHeadings(int book, int chapter) {
    if (!headingsEnabled) return const [];
    final headings = <StudyReaderHeading>[];
    for (final summary in sections) {
      final range = summary.range;
      if (range == null ||
          !summary.showInReader ||
          range.bookIndex != book ||
          chapter < range.chapter ||
          chapter > range.lastChapter) {
        continue;
      }
      final visited = <String>{};
      void visit(StudySection section, int depth) {
        if (!visited.add(section.id)) return;
        if (section.chapter == chapter) {
          headings.add((section: section, summary: summary, depth: depth));
        }
        for (final child in childHeadings(section.id)) {
          visit(child, depth + 1);
        }
      }

      visit(summary, 0);
    }
    // A stable sort keeps each tree's parents before children on one verse.
    final positions = {
      for (var i = 0; i < headings.length; i++) headings[i].section.id: i,
    };
    headings.sort((a, b) {
      final verse = a.section.verse.compareTo(b.section.verse);
      return verse != 0
          ? verse
          : positions[a.section.id]!.compareTo(positions[b.section.id]!);
    });
    return headings;
  }

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
      for (final link in links)
        if (link.groupId == groupId)
          StudyItem._(StudyItemType.link, link, link.order),
      for (final group in groups)
        if (group.parentId == groupId)
          StudyItem._(StudyItemType.group, group, group.order),
      for (final section in sections)
        if (section.parentId == groupId)
          StudyItem._(StudyItemType.section, section, section.order),
    ];
    // Retain the original list order for legacy items with tied order values.
    final positions = {for (var i = 0; i < items.length; i++) items[i]: i};
    items.sort((a, b) {
      // A section's own items come before its headings, as the text before
      // its first heading; the headings follow in verse order.
      if (a.isHeading != b.isHeading) return a.isHeading ? 1 : -1;
      if (a.isHeading) {
        final start = _compareStarts(
          (a.value as StudySection).start,
          (b.value as StudySection).start,
        );
        if (start != 0) return start;
      }
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
    for (final link in links) {
      if (link.groupId == groupId) consider(link.order);
    }
    for (final group in groups) {
      if (group.parentId == groupId) consider(group.order);
    }
    for (final section in sections) {
      if (section.parentId == groupId) consider(section.order);
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
    if (groupId != null && !hasContainer(groupId)) return false;
    if (!itemsIn(item.groupId).any((candidate) => candidate.key == item.key)) {
      return false;
    }
    final containerId = switch (item.value) {
      StudyGroup(:final id) || StudySection(:final id) => id,
      _ => null,
    };
    if (containerId != null) {
      final visited = <String>{containerId};
      var ancestor = groupId;
      while (ancestor != null) {
        if (!visited.add(ancestor)) return false;
        ancestor = containerParent(ancestor);
      }
    }
    if (item.isHeading) {
      // A heading keeps its verse, so it may move only where it still fits,
      // with the headings beneath it, which move along.
      final heading = item.value as StudySection;
      if (!canPlaceHeading(groupId, heading.start)) return false;
      final range = summaryOf(sectionById(groupId)!)!.range!;
      return _headingsWithin(heading.id, range);
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
        StudyItemType.link => copyWith(
          links: [
            for (final link in links)
              link.key == (item.value as StudyLink).key
                  ? link.copyWith(groupId: () => groupId, order: order)
                  : link,
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
        StudyItemType.section => copyWith(
          sections: [
            for (final section in sections)
              section.id == (item.value as StudySection).id
                  ? section.copyWith(parentId: () => groupId, order: order)
                  : section,
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
      links: [
        for (final link in links)
          link.groupId == group.id
              ? link.copyWith(groupId: () => parentId)
              : link,
      ],
      sections: [
        for (final section in sections)
          section.parentId == group.id
              ? section.copyWith(parentId: () => parentId)
              : section,
      ],
    );
  }

  StudyWorkspace putSection(StudySection section) {
    final updated = List<StudySection>.of(sections);
    final index = updated.indexWhere((candidate) => candidate.id == section.id);
    if (index < 0) {
      updated.add(section.copyWith(order: nextOrder(section.parentId)));
    } else {
      updated[index] = updated[index].parentId == section.parentId
          ? section
          : section.copyWith(order: nextOrder(section.parentId));
    }
    return copyWith(sections: updated);
  }

  /// Delete a section without deleting its study material. A heading's items
  /// and subheadings move up to its parent. A summary's headings go with it,
  /// and every item they held moves up to the summary's parent.
  StudyWorkspace removeSection(StudySection section) {
    final removed = {
      section.id,
      if (section.isSummary)
        for (final heading in headingsBeneath(section.id)) heading.id,
    };
    final parentId = section.parentId;
    String? reparent(String? id) => removed.contains(id) ? parentId : id;
    return copyWith(
      sections: [
        for (final candidate in sections)
          if (!removed.contains(candidate.id))
            candidate.copyWith(parentId: () => reparent(candidate.parentId)),
      ],
      groups: [
        for (final group in groups)
          group.copyWith(parentId: () => reparent(group.parentId)),
      ],
      passages: [
        for (final passage in passages)
          passage.copyWith(groupId: () => reparent(passage.groupId)),
      ],
      words: [
        for (final word in words)
          word.copyWith(groupId: () => reparent(word.groupId)),
      ],
      notes: [
        for (final note in notes)
          note.copyWith(groupId: () => reparent(note.groupId)),
      ],
      links: [
        for (final link in links)
          link.copyWith(groupId: () => reparent(link.groupId)),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (!highlightsEnabled) 'highlights': false,
    if (!headingsEnabled) 'headings': false,
    'ordered': true,
    'groups': groups.map((group) => group.toJson()).toList(),
    'passages': passages.map((passage) => passage.toJson()).toList(),
    'words': words.map((word) => word.toJson()).toList(),
    'notes': notes.map((note) => note.toJson()).toList(),
    if (links.isNotEmpty) 'links': links.map((link) => link.toJson()).toList(),
    if (sections.isNotEmpty)
      'sections': sections.map((section) => section.toJson()).toList(),
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

    // Sections came after mixed ordering too. Keep a heading only where it
    // still hangs from a summary; the headings dropped leave their items to
    // move to the top level below, like those of any missing container.
    final rawSections = [
      for (final section
          in (value['sections'] is List ? value['sections'] as List : const [])
              .map(StudySection.fromJson)
              .whereType<StudySection>())
        section,
    ];
    final sectionIds = rawSections.map((section) => section.id).toSet();
    var sections = [
      for (final section in rawSections)
        section.parentId == section.id ||
                (section.parentId != null &&
                    !sectionIds.contains(section.parentId) &&
                    !groups.any((group) => group.id == section.parentId))
            ? section.copyWith(parentId: () => null)
            : section,
    ];
    final anchored = StudyWorkspace(id: id, name: name, sections: sections);
    sections = [
      for (final section in sections)
        if (anchored.summaryOf(section) != null) section,
    ];

    final groupIds = {
      ...groups.map((group) => group.id),
      ...sections.map((section) => section.id),
    };
    groups = [
      for (final group in groups)
        group.parentId == null ||
                group.parentId == group.id ||
                !groupIds.contains(group.parentId)
            ? group.copyWith(parentId: () => null)
            : group,
    ];
    sections = [
      for (final section in sections)
        section.parentId == null || groupIds.contains(section.parentId)
            ? section
            : section.copyWith(parentId: () => null),
    ];
    // A cycle among the containers would hang them from nothing, out of reach
    // of the top level. Cut each where a walk up from it first re-enters it.
    final parentOf = <String, String?>{
      for (final group in groups) group.id: group.parentId,
      for (final section in sections) section.id: section.parentId,
    };
    for (final start in parentOf.keys.toList()) {
      final seen = <String>{};
      String? id = start;
      while (id != null && parentOf.containsKey(id)) {
        if (!seen.add(id)) {
          parentOf[id] = null;
          break;
        }
        id = parentOf[id];
      }
    }
    groups = [
      for (final group in groups)
        group.parentId == parentOf[group.id]
            ? group
            : group.copyWith(parentId: () => parentOf[group.id]),
    ];
    sections = [
      for (final section in sections)
        section.parentId == parentOf[section.id]
            ? section
            : section.copyWith(parentId: () => parentOf[section.id]),
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

    // Links came after mixed ordering, so theirs is always stored; one whose
    // group is gone moves to the top level like any other item.
    final links = [
      for (final link
          in (value['links'] is List ? value['links'] as List : const [])
              .map(StudyLink.fromJson)
              .whereType<StudyLink>())
        link.groupId == null || groupIds.contains(link.groupId)
            ? link
            : link.copyWith(groupId: () => null),
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
          if (value['groups'] is List) ...value['groups'] as List,
          if (value['themes'] is List) ...value['themes'] as List,
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
    for (final link in links) {
      accountFor(link.groupId, link.order);
    }
    for (final section in sections) {
      accountFor(section.parentId, section.order);
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
      headingsEnabled: value['headings'] is! bool || value['headings'] as bool,
      groups: groups,
      passages: passages,
      words: words,
      notes: notes,
      links: links,
      sections: sections,
    );
  }
}

int _storedColor(Object? raw, int fallback) =>
    raw is int && raw >= 0 && raw <= 0xffffffff ? raw : fallback;

/// The workspaces in [value], or null when it is missing or not a well-formed
/// list of them, so callers can tell corrupt data from an empty set.
List<StudyWorkspace>? tryDecodeStudyWorkspaces(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return null;
    return decoded
        .map(StudyWorkspace.fromJson)
        .whereType<StudyWorkspace>()
        .toList();
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

List<StudyWorkspace> decodeStudyWorkspaces(String? value) =>
    tryDecodeStudyWorkspaces(value) ?? [];

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
