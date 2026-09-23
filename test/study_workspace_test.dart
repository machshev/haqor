import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
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
