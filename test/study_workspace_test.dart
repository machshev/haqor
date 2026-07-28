import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
  test('study workspaces round-trip root words, themes, notes, and colors', () {
    const central = StudyPassage(
      bookIndex: 0,
      chapter: 12,
      verse: 3,
      note: 'The call of Abram',
    );
    final workspace = StudyWorkspace(
      id: 'promise-study',
      name: 'Promise study',
      wordColorValue: 0xffffab91,
      passageColorValue: 0xff90caf9,
      themes: const [
        StudyTheme(
          id: 'promise',
          name: 'Promise',
          headerNote: 'Trace the promise and its seed.',
          passages: [
            central,
            StudyPassage(
              bookIndex: 47,
              chapter: 3,
              verse: 16,
              note: 'The seed is singular',
              highlightEnabled: false,
            ),
          ],
        ),
      ],
      words: const [
        StudyWord(
          root: 'ברך',
          surface: 'וְנִבְרְכוּ',
          note: 'Compare the verbal form in the connected passage.',
        ),
      ],
    );

    final decoded = decodeStudyWorkspaces(encodeStudyWorkspaces([workspace]));

    expect(decoded, hasLength(1));
    expect(decoded.single.name, 'Promise study');
    expect(decoded.single.themes.single.headerNote, contains('seed'));
    expect(
      decoded.single.themes.single.passages.last.note,
      'The seed is singular',
    );
    expect(
      decoded.single.themes.single.passages.last.highlightEnabled,
      isFalse,
    );
    expect(decoded.single.words.single.root, 'ברך');
    expect(decoded.single.wordColorValue, 0xffffab91);
    expect(decoded.single.passageColorValue, 0xff90caf9);
  });

  test('invalid storage is ignored without losing valid workspaces', () {
    final decoded = decodeStudyWorkspaces('''
      [
        {"id":"valid","name":"Valid","themes":[]},
        {"id":"","name":"Broken","themes":[]}
      ]
      ''');

    expect(decoded, hasLength(1));
    expect(decoded.single.themes, isEmpty);
  });

  test('theme passage updates and root word updates use stable keys', () {
    const passage = StudyPassage(bookIndex: 0, chapter: 1, verse: 1);
    const theme = StudyTheme(
      id: 'creation',
      name: 'Creation',
      passages: [passage],
    );
    var workspace = const StudyWorkspace(
      id: 'study',
      name: 'Study',
      themes: [theme],
    );

    workspace = workspace
        .putTheme(theme.putPassage(passage.copyWith(note: 'Opening statement')))
        .putWord(const StudyWord(root: 'ברא', surface: 'בָּרָא'))
        .putWord(
          const StudyWord(
            root: 'ברא',
            surface: 'וַיִּבְרָא',
            note: 'All forms share this bookmark.',
          ),
        );

    expect(workspace.themes.single.passages, hasLength(1));
    expect(workspace.themes.single.passages.single.note, 'Opening statement');
    expect(workspace.words, hasLength(1));
    expect(workspace.wordForRoot('ברא')?.surface, 'וַיִּבְרָא');
  });

  test('v1 central-passage data migrates into a passage theme', () {
    final decoded = decodeStudyWorkspaces('''
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
      ''');

    var workspace = decoded.single;
    expect(workspace.themes.single.name, 'Passages');
    expect(workspace.themes.single.passages, hasLength(2));
    expect(workspace.words.single.surface, 'בְּרֵאשִׁית');
    expect(workspace.words.single.root, isEmpty);

    workspace = workspace.putWord(
      const StudyWord(root: 'ראש', surface: 'בְּרֵאשִׁית'),
    );
    expect(workspace.words, hasLength(1));
    expect(workspace.words.single.root, 'ראש');
  });
}
