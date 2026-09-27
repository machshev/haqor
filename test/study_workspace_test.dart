import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
  linkTests();
  sectionTests();

  test(
    'switching bookmark type preserves its place and settings through storage',
    () {
      const word = StudyWord(
        root: 'ברא',
        surface: 'בָּרָא',
        groupId: 'g',
        order: 7,
        note: 'Creation',
        colorValue: 0xff90caf9,
        highlightEnabled: false,
      );
      const other = StudyWord(root: 'אמר', surface: 'אָמַר', order: 8);
      var workspace = const StudyWorkspace(
        id: 's',
        name: 'Study',
        groups: [StudyGroup(id: 'g', name: 'Group')],
        words: [word, other],
      );
      for (final kind in [StudyWordKind.form, StudyWordKind.root]) {
        final previous = workspace.words.first;
        expect(workspace.canSwitchWordKind(previous), isTrue);
        workspace = workspace.switchWordKind(previous);
        expect(workspace.wordForBookmark(previous), isNull);
        workspace = decodeStudyWorkspaces(
          encodeStudyWorkspaces([workspace]),
        ).single;
        expect(workspace.words, hasLength(2));
        expect(
          workspace.words.first.toJson(),
          word.copyWith(kind: kind).toJson(),
        );
        expect(workspace.words.last.toJson(), other.toJson());
      }
    },
  );

  test(
    'switching cannot overwrite an existing root or normalized form bookmark',
    () {
      const root = StudyWord(root: 'ברא', surface: 'בָּרָא', note: 'Root note');
      const form = StudyWord(
        root: 'ברא',
        surface: 'בָּרָ֣א',
        kind: StudyWordKind.form,
        note: 'Form note',
        groupId: 'g',
      );
      const workspace = StudyWorkspace(
        id: 's',
        name: 'Study',
        words: [root, form],
      );
      for (final word in workspace.words) {
        expect(workspace.canSwitchWordKind(word), isFalse);
        expect(workspace.switchWordKind(word), same(workspace));
      }
    },
  );

  test(
    'switching unresolved forms to roots and missing bookmarks is blocked',
    () {
      const form = StudyWord(
        root: '',
        surface: 'בָּרָא',
        kind: StudyWordKind.form,
      );
      const legacy = StudyWord(root: '', surface: 'אָמַר');
      const missing = StudyWord(root: 'ברא', surface: 'בָּרָא');
      const workspace = StudyWorkspace(
        id: 's',
        name: 'Study',
        words: [form, legacy],
      );
      for (final word in [form, missing]) {
        expect(workspace.canSwitchWordKind(word), isFalse);
        expect(workspace.switchWordKind(word), same(workspace));
      }
      expect(workspace.canSwitchWordKind(legacy), isTrue);
      expect(
        workspace.switchWordKind(legacy).words.last.kind,
        StudyWordKind.form,
      );
    },
  );

  test('root and specific forms survive edits, moves, storage and removal', () {
    const root = StudyWord(root: 'ברא', surface: 'בָּרָא');
    const form = StudyWord(
      root: 'ברא',
      surface: 'בָּרָא',
      kind: StudyWordKind.form,
    );
    const other = StudyWord(
      root: 'ברא',
      surface: 'וַיִּבְרָא',
      kind: StudyWordKind.form,
    );
    var workspace = const StudyWorkspace(id: 's', name: 'Study')
        .putGroup(const StudyGroup(id: 'g', name: 'Forms'))
        .putWord(root)
        .putWord(form)
        .putWord(other);
    expect(workspace.words, hasLength(3));
    expect(
      workspace.itemsIn(null).map((item) => item.key).toSet(),
      hasLength(4),
    );
    workspace = workspace.putWord(
      form.copyWith(
        surface: 'בָּרָ֣א',
        note: 'Perfect',
        colorValue: 0xff90caf9,
      ),
    );
    expect(workspace.words, hasLength(3));
    final item = workspace
        .itemsIn(null)
        .firstWhere((item) => item.key == form.key);
    workspace = workspace.moveItem(item, 'g');
    workspace = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single;
    final saved = workspace.wordForBookmark(form)!;
    expect(saved.kind, StudyWordKind.form);
    expect(saved.note, 'Perfect');
    expect(saved.colorValue, 0xff90caf9);
    expect(saved.groupId, 'g');
    expect(workspace.wordForRoot('ברא')?.kind, StudyWordKind.root);
    workspace = workspace.removeWord(root);
    expect(workspace.wordForRoot('ברא'), isNull);
    expect(workspace.words, hasLength(2));
    workspace = workspace.removeWord(form);
    expect(workspace.words.single.key, other.key);
  });

  test(
    'old bookmarks remain roots and form keys retain pointing and roots',
    () {
      final old = StudyWord.fromJson({'root': 'ברא', 'surface': 'בָּרָא'})!;
      expect(old.kind, StudyWordKind.root);
      expect(old.copyWith(note: 'Existing').kind, StudyWordKind.root);
      expect(studyFormKey('שָׁלַ֖ח־'), studyFormKey('שָׁלַח'));
      expect(studyFormKey('שָׁלַח'), isNot(studyFormKey('שִׁלַּח')));
      expect(
        StudyWord.formKey('אלה', 'אֵל'),
        isNot(StudyWord.formKey('אל', 'אֵל')),
      );
      expect(studyFormKey('ܟܬܒܐ'), isNot(studyFormKey('ܡܫܝܚܐ')));
    },
  );

  test('study outline round-trips nested groups and per-item settings', () {
    final workspace = StudyWorkspace(
      id: 'promise-study',
      name: 'Promise study',
      highlightsEnabled: false,
      groups: const [
        StudyGroup(id: 'promise', name: 'Promise'),
        StudyGroup(id: 'fulfilment', name: 'Fulfilment', parentId: 'promise'),
      ],
      passages: const [
        StudyPassage(
          bookIndex: 0,
          chapter: 12,
          verse: 3,
          groupId: 'promise',
          note: 'The call of Abram',
          colorValue: 0xff90caf9,
        ),
        StudyPassage(
          bookIndex: 47,
          chapter: 3,
          verse: 16,
          groupId: 'fulfilment',
          note: 'The seed is singular',
          highlightEnabled: false,
        ),
      ],
      words: const [
        StudyWord(
          root: 'ברך',
          surface: 'וְנִבְרְכוּ',
          groupId: 'promise',
          note: 'Compare the verbal form.',
          colorValue: 0xffffab91,
        ),
      ],
      notes: const [
        StudyNote(
          id: 'intro',
          text: 'Trace the promise and its seed.',
          groupId: 'promise',
          order: 0,
        ),
      ],
    );

    final decoded = decodeStudyWorkspaces(encodeStudyWorkspaces([workspace]));
    final result = decoded.single;

    expect(result.childGroups(null).single.name, 'Promise');
    expect(result.highlightsEnabled, isFalse);
    expect(result.childGroups('promise').single.name, 'Fulfilment');
    expect(result.passages.last.note, 'The seed is singular');
    expect(result.passages.last.highlightEnabled, isFalse);
    expect(result.passages.first.colorValue, 0xff90caf9);
    expect(result.words.single.groupId, 'promise');
    expect(result.words.single.colorValue, 0xffffab91);
    expect(result.notes.single.text, 'Trace the promise and its seed.');
  });

  test('invalid storage is ignored without losing valid workspaces', () {
    final decoded = decodeStudyWorkspaces('''
      [
        {"id":"valid","name":"Valid","groups":[]},
        {"id":"","name":"Broken","groups":[]}
      ]
      ''');

    expect(decoded, hasLength(1));
    expect(decoded.single.groups, isEmpty);
  });

  test(
    'stable item keys update bookmarks and deleting a group promotes them',
    () {
      const parent = StudyGroup(id: 'parent', name: 'Parent');
      const child = StudyGroup(id: 'child', name: 'Child', parentId: 'parent');
      const passage = StudyPassage(
        bookIndex: 0,
        chapter: 1,
        verse: 1,
        groupId: 'parent',
      );
      var workspace = const StudyWorkspace(
        id: 'study',
        name: 'Study',
        groups: [parent, child],
        passages: [passage],
      );

      workspace = workspace
          .putPassage(passage.copyWith(note: 'Opening statement'))
          .putWord(const StudyWord(root: 'ברא', surface: 'בָּרָא'))
          .putWord(
            const StudyWord(
              root: 'ברא',
              surface: 'וַיִּבְרָא',
              note: 'All forms share this bookmark.',
            ),
          );

      expect(workspace.passages, hasLength(1));
      expect(workspace.passages.single.note, 'Opening statement');
      expect(workspace.words, hasLength(1));

      workspace = workspace.removeGroup(parent);
      expect(workspace.groupById('parent'), isNull);
      expect(workspace.groupById('child')?.parentId, isNull);
      expect(workspace.passages.single.groupId, isNull);
    },
  );

  test('theme-based data migrates to groups with per-item colors', () {
    final workspace = decodeStudyWorkspaces('''
      [{
        "id":"theme-version",
        "name":"Promise",
        "highlights":false,
        "wordColor":4294949721,
        "passageColor":4286626756,
        "themes":[{
          "id":"promise",
          "name":"Promise",
          "note":"Header",
          "passages":[{"book":0,"chapter":12,"verse":3,"note":"Abram"}]
        }],
        "words":[{"root":"ברך","surface":"וְנִבְרְכוּ"}]
      }]
      ''').single;

    expect(workspace.groups.single.name, 'Promise');
    expect(workspace.highlightsEnabled, isFalse);
    expect(workspace.notes.single.text, 'Header');
    expect(workspace.passages.single.groupId, 'promise');
    expect(workspace.passages.single.colorValue, 4286626756);
    expect(workspace.passages.single.highlightEnabled, isTrue);
    expect(workspace.words.single.groupId, isNull);
    expect(workspace.words.single.colorValue, 4294949721);
    expect(workspace.words.single.highlightEnabled, isTrue);
  });

  test('old central-passage data migrates without losing legacy words', () {
    var workspace = decodeStudyWorkspaces('''
      [{
        "id":"legacy",
        "name":"Legacy",
        "central":{"book":0,"chapter":1,"verse":1,"note":"start"},
        "passages":[
          {"book":0,"chapter":1,"verse":1,"note":"start"},
          {"book":0,"chapter":1,"verse":2}
        ],
        "words":[
          {"book":0,"chapter":1,"verse":1,"position":0,"surface":"בְּרֵאשִׁית"}
        ]
      }]
      ''').single;

    expect(workspace.groups.single.name, 'Passages');
    expect(workspace.passages, hasLength(2));
    expect(workspace.words.single.root, isEmpty);

    workspace = workspace.putWord(
      const StudyWord(root: 'ראש', surface: 'בְּרֵאשִׁית'),
    );
    expect(workspace.words, hasLength(1));
    expect(workspace.words.single.root, 'ראש');
  });

  test('mixed study items can be reordered within a group', () {
    var workspace = const StudyWorkspace(
      id: 'ordered',
      name: 'Ordered',
      passages: [StudyPassage(bookIndex: 0, chapter: 1, verse: 1, order: 0)],
      words: [StudyWord(root: 'ברא', surface: 'בָּרָא', order: 1)],
      notes: [StudyNote(id: 'note', text: 'Opening paragraph', order: 2)],
    );

    workspace = workspace.reorderItems(null, 2, 0);

    expect(workspace.itemsIn(null).map((item) => item.type), [
      StudyItemType.note,
      StudyItemType.passage,
      StudyItemType.word,
    ]);
    final decoded = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single;
    expect(decoded.itemsIn(null).map((item) => item.type), [
      StudyItemType.note,
      StudyItemType.passage,
      StudyItemType.word,
    ]);
  });
  test('legacy groups follow items at every level and keep their order', () {
    final workspace = StudyWorkspace.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'ordered': true,
      'groups': [
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'},
        {'id': 'child', 'name': 'Child', 'parent': 'a'},
      ],
      'notes': [
        {'id': 'top', 'text': 'Top', 'order': 5},
        {'id': 'nested', 'text': 'Nested', 'group': 'a', 'order': 2},
      ],
    })!;
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'note-top',
      'group-a',
      'group-b',
    ]);
    expect(workspace.itemsIn('a').map((item) => item.key), [
      'note-nested',
      'group-child',
    ]);
    final restored = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single;
    expect(restored.toJson(), workspace.toJson());
  });

  test('groups reorder among items and retain subtrees after moving', () {
    var workspace = const StudyWorkspace(id: 'study', name: 'Study')
        .putNote(const StudyNote(id: 'intro', text: 'Introduction'))
        .putGroup(const StudyGroup(id: 'a', name: 'A'))
        .putGroup(const StudyGroup(id: 'b', name: 'B'))
        .putGroup(const StudyGroup(id: 'child', name: 'Child', parentId: 'a'))
        .putNote(
          const StudyNote(id: 'nested', text: 'Nested', groupId: 'child'),
        );
    workspace = workspace.reorderItems(null, 2, 0);
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'group-b',
      'note-intro',
      'group-a',
    ]);
    workspace = workspace.reorderItems(null, 0, 3);
    expect(workspace.itemsIn(null).map((item) => item.key), [
      'note-intro',
      'group-a',
      'group-b',
    ]);
    workspace = workspace.moveItem(workspace.itemsIn(null)[1], 'b');
    expect(workspace.groupById('a')!.parentId, 'b');
    expect(workspace.groupById('child')!.parentId, 'a');
    expect(workspace.notes.last.groupId, 'child');
    final restored = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single;
    expect(restored.toJson(), workspace.toJson());
  });

  test(
    'moves preserve every item and reject missing targets and group cycles',
    () {
      var workspace = const StudyWorkspace(id: 'study', name: 'Study')
          .putGroup(const StudyGroup(id: 'a', name: 'A'))
          .putGroup(const StudyGroup(id: 'child', name: 'Child', parentId: 'a'))
          .putPassage(
            const StudyPassage(
              bookIndex: 0,
              chapter: 1,
              verse: 1,
              note: 'Opening',
            ),
          )
          .putWord(
            const StudyWord(
              root: 'ברא',
              surface: 'בָּרָא',
              highlightEnabled: false,
            ),
          )
          .putNote(const StudyNote(id: 'note', text: 'A note'));
      final group = workspace.itemsIn(null).first;
      for (final invalid in ['a', 'child', 'missing']) {
        expect(workspace.canMoveItem(group, invalid), isFalse);
        expect(workspace.moveItem(group, invalid), same(workspace));
      }
      for (final item in workspace.itemsIn(null).skip(1).toList()) {
        workspace = workspace.moveItem(item, 'child', index: 0);
      }
      expect(workspace.itemsIn('child').map((item) => item.type), [
        StudyItemType.note,
        StudyItemType.word,
        StudyItemType.passage,
      ]);
      expect(workspace.passages.single.note, 'Opening');
      expect(workspace.words.single.highlightEnabled, isFalse);
      for (final item in workspace.itemsIn('child').toList()) {
        workspace = workspace.moveItem(item, null);
      }
      expect(workspace.itemsIn('child'), isEmpty);
      expect(workspace.itemsIn(null), hasLength(4));
      expect(workspace.passages.single.groupId, isNull);
      expect(workspace.words.single.groupId, isNull);
      expect(workspace.notes.single.groupId, isNull);
    },
  );
}

void linkTests() {
  const isaiah = (bookIndex: 11, chapter: 7, verse: 14);
  const matthew = (bookIndex: 39, chapter: 1, verse: 23);
  const link = StudyLink(
    earlier: isaiah,
    later: matthew,
    earlierPositions: [7, 9],
    laterPositions: [1, 3],
    score: 14.69,
  );

  test('link bookmarks survive notes, moves, storage and group removal', () {
    var workspace = const StudyWorkspace(
      id: 's',
      name: 'Study',
      groups: [StudyGroup(id: 'g', name: 'Emmanuel')],
      words: [StudyWord(root: 'עלמ', surface: 'הָעַלְמָה')],
    ).putLink(link);
    expect(workspace.linkBetween(isaiah, matthew), isNotNull);
    // Added as the outline's last item.
    expect(workspace.itemsIn(null).map((i) => i.type), [
      StudyItemType.word,
      StudyItemType.group,
      StudyItemType.link,
    ]);

    final item = workspace.itemsIn(null).last;
    workspace = workspace.moveItem(item, 'g');
    workspace = workspace.putLink(
      workspace.links.single.copyWith(note: 'Virgin / young woman'),
    );
    workspace = decodeStudyWorkspaces(
      encodeStudyWorkspaces([workspace]),
    ).single;
    final stored = workspace.linkBetween(isaiah, matthew)!;
    expect(stored.groupId, 'g');
    expect(stored.note, 'Virgin / young woman');
    expect(stored.earlierPositions, [7, 9]);
    expect(stored.laterPositions, [1, 3]);
    expect(stored.score, 14.69);
    expect(workspace.itemsIn('g').single.key, link.key);

    // Removing its group keeps the link at the group's level.
    workspace = workspace.removeGroup(workspace.groups.single);
    expect(workspace.linkBetween(isaiah, matthew)!.groupId, isNull);
    workspace = workspace.removeLink(stored);
    expect(workspace.links, isEmpty);
  });

  test('links to a vanished group or with bad verses load safely', () {
    final workspace = decodeStudyWorkspaces('''[{
      "id": "s", "name": "Study", "ordered": true,
      "links": [
        {"ot": [11, 7, 14], "nt": [39, 1, 23], "group": "gone", "order": 2},
        {"ot": [11, 7], "nt": [39, 1, 23]},
        {"ot": [999, 1, 1], "nt": [39, 1, 23]}
      ]
    }]''').single;
    expect(workspace.links, hasLength(1));
    expect(workspace.links.single.groupId, isNull);
  });
}

void sectionTests() {
  // Genesis 1:1–2:3 with two headings, the second holding a subheading and
  // a note, and a note of the summary's own before its headings.
  const summary = StudySection(
    id: 'sum',
    title: 'Creation',
    chapter: 1,
    verse: 1,
    bookIndex: 0,
    endChapter: 2,
    endVerse: 3,
    note: 'Six days and a rest',
  );
  const light = StudySection(
    id: 'light',
    title: 'Light',
    chapter: 1,
    verse: 3,
    parentId: 'sum',
  );
  const land = StudySection(
    id: 'land',
    title: 'Land and seas',
    chapter: 1,
    verse: 9,
    parentId: 'sum',
  );
  const plants = StudySection(
    id: 'plants',
    title: 'Plants',
    chapter: 1,
    verse: 11,
    parentId: 'land',
  );
  StudyWorkspace build() => const StudyWorkspace(id: 's', name: 'Study')
      .putSection(summary)
      .putNote(const StudyNote(id: 'intro', text: 'Intro', groupId: 'sum'))
      // Added out of verse order: headings sort by verse, not insertion.
      .putSection(land)
      .putSection(light)
      .putSection(plants)
      .putNote(const StudyNote(id: 'seas', text: 'Seas', groupId: 'land'));

  test('summaries round-trip and list their items before verse-ordered '
      'headings', () {
    final workspace = decodeStudyWorkspaces(
      encodeStudyWorkspaces([build().copyWith(headingsEnabled: false)]),
    ).single;
    expect(workspace.headingsEnabled, isFalse);
    expect(workspace.sections, hasLength(4));
    final stored = workspace.sectionById('sum')!;
    expect(stored.toJson(), summary.toJson());
    expect(stored.range!.reference, '1:1–2:3');
    expect(workspace.itemsIn(null).single.key, 'section-sum');
    expect(workspace.itemsIn('sum').map((i) => i.key), [
      'note-intro',
      'section-light',
      'section-land',
    ]);
    expect(workspace.itemsIn('land').map((i) => i.key), [
      'note-seas',
      'section-plants',
    ]);
    expect(workspace.summaryOf(workspace.sectionById('plants')!)?.id, 'sum');
  });

  test('a heading runs to the next beside it or its parent\'s end', () {
    final workspace = build();
    expect(workspace.sectionEnd(light), (chapter: 1, verse: 8));
    expect(workspace.sectionEnd(plants), (chapter: 2, verse: 3));
    expect(workspace.sectionEnd(land), (chapter: 2, verse: 3));
    final chapter = workspace.putSection(
      const StudySection(
        id: 'rest',
        title: 'Rest',
        chapter: 2,
        verse: 1,
        parentId: 'sum',
      ),
    );
    // The chapter's length is unknown, so its end has no verse.
    expect(chapter.sectionEnd(land), (chapter: 1, verse: null));
  });

  test('headings stay within their summary and after their parent', () {
    final workspace = build();
    expect(workspace.canPlaceHeading('sum', (chapter: 2, verse: 3)), isTrue);
    expect(workspace.canPlaceHeading('sum', (chapter: 2, verse: 4)), isFalse);
    expect(workspace.canPlaceHeading('land', (chapter: 1, verse: 8)), isFalse);
    expect(workspace.canPlaceHeading(null, (chapter: 1, verse: 5)), isFalse);
    // Headings live only in sections; summaries and other items anywhere.
    final lightItem = workspace.itemsIn('sum')[1];
    final plantsItem = workspace.itemsIn('land').last;
    expect(workspace.canMoveItem(lightItem, null), isFalse);
    expect(workspace.canMoveItem(plantsItem, 'sum'), isTrue);
    expect(workspace.canMoveItem(lightItem, 'land'), isFalse);
    expect(
      workspace.canMoveItem(workspace.itemsIn(null).single, 'plants'),
      isFalse,
    ); // Into its own heading.
    expect(
      workspace.sectionProblem(
        light.withAnchor(
          const StudySection(id: '', title: '', chapter: 3, verse: 1),
        ),
      ),
      isNotNull,
    );
    // Shrinking the summary may not strand its headings.
    expect(
      workspace.sectionProblem(
        summary.withAnchor(
          const StudySection(
            id: '',
            title: '',
            chapter: 1,
            verse: 1,
            bookIndex: 0,
            endChapter: 1,
            endVerse: 10,
          ),
        ),
      ),
      'Its headings must stay within the passage.',
    );
    // Nor move a heading after its own subheadings.
    expect(
      workspace.sectionProblem(
        land.withAnchor(
          const StudySection(id: '', title: '', chapter: 1, verse: 12),
        ),
      ),
      'Its subheadings must not start before it.',
    );
    expect(workspace.sectionProblem(summary.copyWith(title: '')), isNotNull);
    expect(workspace.sectionProblem(summary), isNull);
  });

  test(
    'removing a heading lifts its contents; a summary takes its headings',
    () {
      var workspace = build();
      final lifted = workspace.removeSection(land);
      expect(lifted.sectionById('land'), isNull);
      expect(lifted.sectionById('plants')!.parentId, 'sum');
      expect(lifted.notes.firstWhere((n) => n.id == 'seas').groupId, 'sum');

      workspace = workspace.putGroup(const StudyGroup(id: 'g', name: 'Talk'));
      workspace = workspace.moveItem(workspace.itemsIn(null).first, 'g');
      workspace = workspace.removeSection(workspace.sectionById('sum')!);
      expect(workspace.sections, isEmpty);
      expect(workspace.itemsIn('g').map((i) => i.key), [
        'note-intro',
        'note-seas',
      ]);
    },
  );

  test('the reader shows shown summaries\' headings in each chapter', () {
    final workspace = build().putSection(
      const StudySection(
        id: 'rest',
        title: 'Rest',
        chapter: 2,
        verse: 1,
        parentId: 'sum',
      ),
    );
    List<(String, int)> shown(StudyWorkspace w, int chapter) => [
      for (final h in w.readerHeadings(0, chapter)) (h.section.id, h.depth),
    ];
    expect(shown(workspace, 1), [
      ('sum', 0),
      ('light', 1),
      ('land', 1),
      ('plants', 2),
    ]);
    expect(shown(workspace, 2), [('rest', 1)]);
    expect(shown(workspace, 3), isEmpty);
    expect(workspace.readerHeadings(1, 1), isEmpty);
    expect(shown(workspace.copyWith(headingsEnabled: false), 1), isEmpty);
    expect(
      shown(workspace.putSection(summary.copyWith(showInReader: false)), 1),
      isEmpty,
    );
  });

  test('headings without a summary above them are dropped on load', () {
    final workspace = decodeStudyWorkspaces('''[{
      "id": "s", "name": "Study", "ordered": true,
      "groups": [{"id": "g", "name": "Group", "order": 0}],
      "notes": [{"id": "n", "text": "Kept", "group": "orphan", "order": 1}],
      "sections": [
        {"id": "sum", "title": "Summary", "book": 0, "chapter": 1,
         "verse": 1, "wholeChapter": true, "parent": "g", "order": 0},
        {"id": "h", "title": "Heading", "chapter": 1, "verse": 2,
         "parent": "sum", "order": 0},
        {"id": "orphan", "title": "Orphan", "chapter": 1, "verse": 2,
         "parent": "g", "order": 1},
        {"id": "loose", "title": "Loose", "chapter": 1, "verse": 2},
        {"id": "untitled", "title": "", "book": 0, "chapter": 1, "verse": 1}
      ]
    }]''').single;
    expect(workspace.sections.map((s) => s.id), ['sum', 'h']);
    expect(workspace.sectionById('sum')!.parentId, 'g');
    expect(workspace.notes.single.groupId, isNull);
  });
}
