import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/syntax_tree.dart';

/// A node of the flat pre-order list the hub sends.
SyntaxNodeEntry node(
  int parent, {
  String kind = '',
  String role = '',
  int position = -1,
  String partText = '',
  String partGloss = '',
}) => SyntaxNodeEntry(
  parent: parent,
  kind: kind,
  role: role,
  position: position,
  partText: partText,
  partGloss: partGloss,
);

void main() {
  /// Genesis 1:1 as `[cl [pp:pp 0] 1:v 2:s [np:o 3 [np 4]]]`.
  final genesis = SyntaxTreeNode.fromNodes([
    node(-1, kind: 'cl'),
    node(0, kind: 'pp', role: 'pp'),
    node(1, position: 0),
    node(0, role: 'v', position: 1),
    node(0, role: 's', position: 2),
    node(0, kind: 'np', role: 'o'),
    node(5, position: 3),
    node(5, kind: 'np'),
    node(7, position: 4),
  ])!;

  test('rebuilds the tree from its pre-order list', () {
    expect(genesis.kind, 'cl');
    expect(genesis.children.map((c) => c.label), [
      'Prepositional',
      'Verb',
      'Subject',
      'Object',
    ]);
    expect(genesis.positions, [0, 1, 2, 3, 4]);
    expect(genesis.children[3].children[1].label, 'Noun phrase');
  });

  test('each word takes its constituent\'s role', () {
    final marks = VerseSyntaxMarks.of(genesis);
    expect(marks.roles, {0: 'adv', 1: 'v', 2: 's', 3: 'o', 4: 'o'});
    expect(marks.clauseStarts, isEmpty);
  });

  /// `[ 0{וַ|and} [cl 0:v{יֹּאמֶר|said} 1:s] [cl 2:v [np:o 3]]]`: a
  /// conjunction parsed apart from its verb, then a second clause.
  test('a prefix leaves the word its part\'s role; clauses mark starts', () {
    final tree = SyntaxTreeNode.fromNodes([
      node(-1),
      node(0, position: 0, partText: 'וַ', partGloss: 'and'),
      node(0, kind: 'cl'),
      node(2, role: 'v', position: 0, partText: 'יֹּאמֶר', partGloss: 'said'),
      node(2, role: 's', position: 1),
      node(0, kind: 'cl'),
      node(5, role: 'v', position: 2),
      node(5, kind: 'np', role: 'o'),
      node(7, position: 3),
    ])!;
    expect(tree.label, 'Joined');
    expect(tree.leaves.first.isPart, isTrue);
    final marks = VerseSyntaxMarks.of(tree);
    expect(marks.roles, {0: 'v', 1: 's', 2: 'v', 3: 'o'});
    // The first clause starts the verse, which needs no mark.
    expect(marks.clauseStarts, {2});
  });

  /// A relative clause inside the object colours its own constituents.
  test('a clause inside a constituent has its own roles', () {
    final tree = SyntaxTreeNode.fromNodes([
      node(-1, kind: 'cl'),
      node(0, role: 'v', position: 0),
      node(0, kind: 'np', role: 'o'),
      node(2, position: 1),
      node(2, kind: 'cl'),
      node(4, position: 2),
      node(4, role: 'v', position: 3),
    ])!;
    final marks = VerseSyntaxMarks.of(tree);
    expect(marks.roles, {0: 'v', 1: 'o', 3: 'v'});
    expect(marks.clauseStarts, {2});
  });

  test('second objects and prepositional phrases share colours', () {
    expect(syntaxColourRole('o2'), 'o');
    expect(syntaxColourRole('pp'), 'adv');
    expect(syntaxColourRole(''), isNull);
    expect(syntaxRoleName('o2'), 'Second object');
  });
}
