import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/study_workspace.dart';

void main() {
  test('study workspaces round-trip passages, words, and notes', () {
    final central = const StudyPassage(
      bookIndex: 0,
      chapter: 12,
      verse: 3,
      note: 'The call of Abram',
    );
    final workspace = StudyWorkspace(
      id: 'theme-promise',
      name: 'Promise',
      centralPassage: central,
      passages: [
        central,
        const StudyPassage(
          bookIndex: 47,
          chapter: 3,
          verse: 16,
          note: 'The seed is singular',
        ),
      ],
      words: const [
        StudyWord(
          bookIndex: 0,
          chapter: 12,
          verse: 3,
          position: 5,
          surface: 'וְנִבְרְכוּ',
          note: 'Compare the verbal form in the connected passage.',
        ),
      ],
    );

    final decoded = decodeStudyWorkspaces(encodeStudyWorkspaces([workspace]));

    expect(decoded, hasLength(1));
    expect(decoded.single.name, 'Promise');
    expect(decoded.single.centralPassage.locationKey, '0:12:3');
    expect(decoded.single.passages.last.note, 'The seed is singular');
    expect(decoded.single.words.single.surface, 'וְנִבְרְכוּ');
    expect(decoded.single.words.single.position, 5);
  });

  test('invalid storage is ignored without losing valid workspaces', () {
    final decoded = decodeStudyWorkspaces('''
      [
        {"id":"valid","name":"Valid","central":{"book":0,"chapter":1,"verse":1}},
        {"id":"","name":"Broken","central":null}
      ]
      ''');

    expect(decoded, hasLength(1));
    expect(decoded.single.passages, hasLength(1));
    expect(decoded.single.passages.single.locationKey, '0:1:1');
  });

  test('passage and word updates remain occurrence-specific', () {
    final central = const StudyPassage(bookIndex: 0, chapter: 1, verse: 1);
    var workspace = StudyWorkspace(
      id: 'creation',
      name: 'Creation',
      centralPassage: central,
      passages: [central],
    );

    workspace = workspace
        .putPassage(central.copyWith(note: 'Opening statement'))
        .putWord(
          const StudyWord(
            bookIndex: 0,
            chapter: 1,
            verse: 1,
            position: 0,
            surface: 'בְּרֵאשִׁית',
          ),
        )
        .putWord(
          const StudyWord(
            bookIndex: 0,
            chapter: 1,
            verse: 1,
            position: 1,
            surface: 'בָּרָא',
          ),
        );

    expect(workspace.passages, hasLength(1));
    expect(workspace.passages.single.note, 'Opening statement');
    expect(workspace.words, hasLength(2));
    expect(workspace.wordAt(0, 1, 1, 1)?.surface, 'בָּרָא');
  });
}
