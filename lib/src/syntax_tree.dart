import 'package:flutter/material.dart';

import 'bindings/bindings.dart';

/// A verse's syntax tree (MACULA Hebrew's), rebuilt from the flat pre-order
/// list a [VerseSyntaxEntry] carries.
///
/// A group is a clause or phrase; a leaf stands for a word of the verse, or
/// for part of one when a prefix or suffix is parsed apart from the word it
/// is written on.
class SyntaxTreeNode {
  SyntaxTreeNode._({
    required this.kind,
    required this.role,
    required this.position,
    required this.partText,
    required this.partGloss,
  });

  /// The kind of group (`cl`, `np`, `pp`, …); empty for a leaf and for an
  /// unlabelled group gathering a conjunction with what it joins.
  final String kind;

  /// The node's function in its clause (`s`, `v`, `o`, …); empty when it has
  /// none of its own.
  final String role;

  /// A leaf's word position in the verse; -1 for a group.
  final int position;

  /// For a leaf that is only part of its word, the part's text and gloss;
  /// empty otherwise.
  final String partText;
  final String partGloss;

  final List<SyntaxTreeNode> children = [];

  bool get isLeaf => position >= 0;

  /// Whether this leaf is only part of its word.
  bool get isPart => partText.isNotEmpty;

  /// The tree of [entry]; null for an empty one.
  static SyntaxTreeNode? fromEntry(VerseSyntaxEntry entry) =>
      fromNodes(entry.nodes);

  static SyntaxTreeNode? fromNodes(List<SyntaxNodeEntry> nodes) {
    final built = <SyntaxTreeNode>[];
    for (final n in nodes) {
      final node = SyntaxTreeNode._(
        kind: n.kind,
        role: n.role,
        position: n.position,
        partText: n.partText,
        partGloss: n.partGloss,
      );
      built.add(node);
      if (n.parent >= 0 && n.parent < built.length - 1) {
        built[n.parent].children.add(node);
      }
    }
    return built.isEmpty ? null : built.first;
  }

  /// The leaves under this node, in tree order.
  List<SyntaxTreeNode> get leaves => [
    if (isLeaf) this,
    for (final c in children) ...c.leaves,
  ];

  /// The word positions under this node, in reading order.
  List<int> get positions {
    final set = {for (final l in leaves) l.position}.toList()..sort();
    return set;
  }

  /// The label a reader sees: the role when the node has one, else what kind
  /// of group it is.
  String get label {
    if (role.isNotEmpty) return syntaxRoleName(role);
    if (kind.isNotEmpty) return syntaxKindName(kind);
    return isLeaf ? '' : 'Joined';
  }
}

/// A clause-level function, spelled out.
String syntaxRoleName(String role) => switch (role) {
  's' => 'Subject',
  'v' => 'Verb',
  'o' => 'Object',
  'o2' => 'Second object',
  'p' => 'Predicate',
  'adv' => 'Adverbial',
  'pp' => 'Prepositional',
  _ => role,
};

/// A kind of group, spelled out.
String syntaxKindName(String kind) => switch (kind) {
  'cl' => 'Clause',
  'np' => 'Noun phrase',
  'pp' => 'Prep. phrase',
  'vp' => 'Verb phrase',
  'adjp' => 'Adjective phrase',
  'advp' => 'Adverb phrase',
  'nump' => 'Number phrase',
  'relp' => 'Relative',
  'cjp' => 'Conjoined',
  'ijp' => 'Interjection',
  _ => kind,
};

/// The roles the reader colours, in legend order. `o2` shares the object's
/// colour and `pp` the adverbial's: each is a variety of the other.
const syntaxColourRoles = ['s', 'v', 'o', 'p', 'adv'];

/// The role a colour stands for: [syntaxColourRoles]' entry for [role], or
/// null for a role the reader does not colour.
String? syntaxColourRole(String role) => switch (role) {
  's' || 'v' || 'p' || 'adv' => role,
  'o' || 'o2' => 'o',
  'pp' => 'adv',
  _ => null,
};

/// The colour of a role, readable as a tint behind Hebrew text and as a
/// label's accent in both themes.
Color syntaxRoleColor(String role, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (syntaxColourRole(role)) {
    's' => dark ? const Color(0xFF7FB2F0) : const Color(0xFF1F5FAF),
    'v' => dark ? const Color(0xFFF08A7F) : const Color(0xFFB3261E),
    'o' => dark ? const Color(0xFF7FD19A) : const Color(0xFF1E7A3C),
    'p' => dark ? const Color(0xFFD9A8F0) : const Color(0xFF7B3FA0),
    'adv' => dark ? const Color(0xFFE8C26B) : const Color(0xFF8A5A00),
    _ => dark ? const Color(0xFFB0B0B0) : const Color(0xFF6B6B6B),
  };
}

/// What the reader shows for one verse: each word's role and where clauses
/// begin.
@immutable
class VerseSyntaxMarks {
  const VerseSyntaxMarks({required this.roles, required this.clauseStarts});

  /// Word position → the role of the clause constituent it belongs to (one
  /// of [syntaxColourRoles]); absent for a word in none, such as a
  /// conjunction joining two clauses.
  final Map<int, String> roles;

  /// Positions of the words a clause begins at, other than the verse's first.
  final Set<int> clauseStarts;

  static const empty = VerseSyntaxMarks(roles: {}, clauseStarts: {});

  /// The marks of [tree].
  ///
  /// A word takes the role of its nearest ancestor that has a coloured one.
  /// When MACULA parses a word in parts (a conjunction or preposition apart
  /// from the word it is prefixed to), the role of the part that is not a
  /// prefix wins: the last part with a role.
  factory VerseSyntaxMarks.of(SyntaxTreeNode tree) {
    final roles = <int, String>{};
    final starts = <int>{};
    void walk(SyntaxTreeNode node, String? inherited) {
      final own = syntaxColourRole(node.role);
      final role = own ?? inherited;
      if (node.isLeaf) {
        if (role != null) roles[node.position] = role;
        return;
      }
      if (node.kind == 'cl') {
        final positions = node.positions;
        if (positions.isNotEmpty && positions.first > 0) {
          starts.add(positions.first);
        }
      }
      // A clause inside a constituent (a relative clause in the object, say)
      // has constituents of its own, which colour its words.
      for (final child in node.children) {
        walk(child, node.kind == 'cl' && own == null ? null : role);
      }
    }

    walk(tree, null);
    return VerseSyntaxMarks(roles: roles, clauseStarts: starts);
  }
}
