import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
  test('study outline round-trips nested groups and per-item settings', () {
    final workspace = StudyWorkspace(
      id: 'promise-study',
      name: 'Promise study',
      highlightsEnabled: false,
      groups: const [
        StudyGroup(
          id: 'promise',
          name: 'Promise',
          note: 'Trace the promise and its seed.',
        ),
        StudyGroup(
          id: 'fulfilment',
          name: 'Fulfilment',
          note: 'The promise in the New Testament.',
          parentId: 'promise',
        ),
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
    expect(workspace.groups.single.note, 'Header');
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
}
