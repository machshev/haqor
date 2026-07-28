import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../study_workspace.dart';

class StudyWorkspacePanel extends StatelessWidget {
  const StudyWorkspacePanel({
    super.key,
    required this.workspaces,
    required this.activeWorkspace,
    required this.currentPassage,
    required this.useEnglishBookNames,
    required this.onCreate,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onToggleHighlights,
    required this.onCreateGroup,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onBookmarkCurrent,
    required this.onOpenPassage,
    required this.onEditPassage,
    required this.onUpdatePassage,
    required this.onRemovePassage,
    required this.onEditWord,
    required this.onUpdateWord,
    required this.onRemoveWord,
    required this.onOpenWord,
    required this.onCreateNote,
    required this.onEditNote,
    required this.onUpdateNote,
    required this.onRemoveNote,
    required this.onReorderItems,
  });

  final List<StudyWorkspace> workspaces;
  final StudyWorkspace? activeWorkspace;
  final StudyPassage currentPassage;
  final bool useEnglishBookNames;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelect;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggleHighlights;
  final ValueChanged<String?> onCreateGroup;
  final ValueChanged<StudyGroup> onEditGroup;
  final ValueChanged<StudyGroup> onDeleteGroup;
  final ValueChanged<String?> onBookmarkCurrent;
  final ValueChanged<StudyPassage> onOpenPassage;
  final ValueChanged<StudyPassage> onEditPassage;
  final ValueChanged<StudyPassage> onUpdatePassage;
  final ValueChanged<StudyPassage> onRemovePassage;
  final ValueChanged<StudyWord> onEditWord;
  final ValueChanged<StudyWord> onUpdateWord;
  final ValueChanged<StudyWord> onRemoveWord;
  final ValueChanged<StudyWord> onOpenWord;
  final ValueChanged<String?> onCreateNote;
  final ValueChanged<StudyNote> onEditNote;
  final ValueChanged<StudyNote> onUpdateNote;
  final ValueChanged<StudyNote> onRemoveNote;
  final void Function(String? groupId, int oldIndex, int newIndex)
  onReorderItems;

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: useEnglishBookNames)} '
      '${passage.chapter}:${passage.verse}';

  Future<int?> _pickColor(
    BuildContext context, {
    required int selected,
    required String title,
  }) => showDialog<int>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final value in _highlightColors)
            InkWell(
              onTap: () => Navigator.pop(dialogContext, value),
              customBorder: const CircleBorder(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(value),
                  border: Border.all(
                    color: value == selected
                        ? Theme.of(context).colorScheme.onSurface
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: value == selected
                    ? const Icon(Icons.check, size: 20)
                    : null,
              ),
            ),
        ],
      ),
    ),
  );

  Future<String?> _chooseDestination(
    BuildContext context,
    StudyWorkspace workspace,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move study item'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, _topLevelChoice),
            child: const ListTile(
              leading: Icon(Icons.notes_outlined),
              title: Text('Top level'),
              subtitle: Text('Not inside a group'),
            ),
          ),
          for (final group in workspace.groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, group.id),
              child: ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(_groupPath(workspace, group)),
              ),
            ),
        ],
      ),
    );
    if (choice == null) return _cancelledChoice;
    return choice == _topLevelChoice ? null : choice;
  }

  String _groupPath(StudyWorkspace workspace, StudyGroup group) {
    final names = <String>[group.name];
    final visited = <String>{group.id};
    var parent = workspace.groupById(group.parentId);
    while (parent != null && visited.add(parent.id)) {
      names.insert(0, parent.name);
      parent = workspace.groupById(parent.parentId);
    }
    return names.join(' / ');
  }

  List<Widget> _itemsAt(
    BuildContext context,
    StudyWorkspace workspace,
    String? groupId, {
    int depth = 0,
    Set<String> ancestors = const {},
  }) {
    final children = <Widget>[];
    final items = workspace.itemsIn(groupId);
    if (items.isNotEmpty) {
      children.add(
        ReorderableListView.builder(
          key: ValueKey('items-${groupId ?? 'top'}'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorder: (oldIndex, newIndex) =>
              onReorderItems(groupId, oldIndex, newIndex),
          itemBuilder: (context, index) {
            final item = items[index];
            final tile = switch (item.type) {
              StudyItemType.passage => _passageTile(
                context,
                workspace,
                item.value as StudyPassage,
                depth: depth,
              ),
              StudyItemType.word => _wordTile(
                context,
                workspace,
                item.value as StudyWord,
                depth: depth,
              ),
              StudyItemType.note => _noteTile(
                context,
                workspace,
                item.value as StudyNote,
                depth: depth,
              ),
            };
            return Row(
              key: ValueKey('${item.type.name}-${_itemKey(item)}'),
              children: [
                Expanded(child: tile),
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_handle, size: 20),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    for (final group in workspace.childGroups(groupId)) {
      if (ancestors.contains(group.id)) continue;
      children.add(
        _groupTile(
          context,
          workspace,
          group,
          depth: depth,
          ancestors: {...ancestors, group.id},
        ),
      );
    }
    return children;
  }

  String _itemKey(StudyItem item) => switch (item.type) {
    StudyItemType.passage => (item.value as StudyPassage).locationKey,
    StudyItemType.word =>
      '${(item.value as StudyWord).root}-${(item.value as StudyWord).surface}',
    StudyItemType.note => (item.value as StudyNote).id,
  };

  Widget _groupTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyGroup group, {
    required int depth,
    required Set<String> ancestors,
  }) => Padding(
    padding: EdgeInsetsDirectional.only(start: depth * 12.0),
    child: ExpansionTile(
      key: PageStorageKey(group.id),
      initiallyExpanded: true,
      tilePadding: const EdgeInsetsDirectional.only(end: 0),
      childrenPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(
        group.name,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      trailing: PopupMenuButton<_GroupAction>(
        tooltip: 'Group options',
        onSelected: (action) {
          switch (action) {
            case _GroupAction.addPassage:
              onBookmarkCurrent(group.id);
            case _GroupAction.addNote:
              onCreateNote(group.id);
            case _GroupAction.addGroup:
              onCreateGroup(group.id);
            case _GroupAction.edit:
              onEditGroup(group);
            case _GroupAction.delete:
              onDeleteGroup(group);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _GroupAction.addNote,
            child: ListTile(
              leading: Icon(Icons.note_add_outlined),
              title: Text('Add note'),
            ),
          ),
          PopupMenuItem(
            value: _GroupAction.addPassage,
            child: ListTile(
              leading: Icon(Icons.bookmark_add_outlined),
              title: Text('Add current passage'),
            ),
          ),
          PopupMenuItem(
            value: _GroupAction.addGroup,
            child: ListTile(
              leading: Icon(Icons.create_new_folder_outlined),
              title: Text('Add subgroup'),
            ),
          ),
          PopupMenuItem(
            value: _GroupAction.edit,
            child: ListTile(
              leading: Icon(Icons.edit_note),
              title: Text('Edit group'),
            ),
          ),
          PopupMenuItem(
            value: _GroupAction.delete,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete group'),
            ),
          ),
        ],
      ),
      children: [
        ..._itemsAt(
          context,
          workspace,
          group.id,
          depth: depth + 1,
          ancestors: ancestors,
        ),
        if (workspace.passages.every((item) => item.groupId != group.id) &&
            workspace.words.every((item) => item.groupId != group.id) &&
            workspace.notes.every((item) => item.groupId != group.id) &&
            workspace.childGroups(group.id).isEmpty)
          const _SectionEmpty(text: 'This group is empty.'),
      ],
    ),
  );

  Widget _passageTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyPassage passage, {
    required int depth,
  }) => ListTile(
    key: ValueKey('passage-${passage.locationKey}'),
    dense: true,
    contentPadding: EdgeInsetsDirectional.only(
      start: 16 + depth * 12.0,
      end: 0,
    ),
    leading: const Icon(Icons.menu_book_outlined, size: 18),
    title: Text(_reference(passage)),
    subtitle: passage.note.isEmpty ? null : Text(passage.note),
    onTap: () => onOpenPassage(passage),
    trailing: PopupMenuButton<_ItemAction>(
      tooltip: 'Passage options',
      onSelected: (action) async {
        switch (action) {
          case _ItemAction.highlight:
            onUpdatePassage(
              passage.copyWith(highlightEnabled: !passage.highlightEnabled),
            );
          case _ItemAction.note:
            onEditPassage(passage);
          case _ItemAction.move:
            final destination = await _chooseDestination(context, workspace);
            if (destination != _cancelledChoice) {
              onUpdatePassage(passage.copyWith(groupId: () => destination));
            }
          case _ItemAction.color:
            final color = await _pickColor(
              context,
              selected: passage.colorValue,
              title: 'Passage highlight color',
            );
            if (color != null) {
              onUpdatePassage(passage.copyWith(colorValue: color));
            }
          case _ItemAction.remove:
            onRemovePassage(passage);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: _ItemAction.highlight,
          checked: passage.highlightEnabled,
          child: const Text('Highlight passage'),
        ),
        PopupMenuItem(
          value: _ItemAction.note,
          child: ListTile(
            leading: Icon(Icons.note_alt_outlined),
            title: Text('Edit note'),
          ),
        ),
        PopupMenuItem(
          value: _ItemAction.move,
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('Move to group'),
          ),
        ),
        PopupMenuItem(
          value: _ItemAction.color,
          child: ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Highlight color'),
          ),
        ),
        PopupMenuItem(
          value: _ItemAction.remove,
          child: ListTile(
            leading: Icon(Icons.bookmark_remove_outlined),
            title: Text('Remove'),
          ),
        ),
      ],
    ),
  );

  Widget _wordTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyWord word, {
    required int depth,
  }) => ListTile(
    key: ValueKey('word-${word.root}-${word.surface}'),
    dense: true,
    contentPadding: EdgeInsetsDirectional.only(
      start: 16 + depth * 12.0,
      end: 0,
    ),
    leading: const Icon(Icons.translate_outlined, size: 18),
    title: InkWell(
      onTap: () => onOpenWord(word),
      child: Text(
        word.root.isEmpty ? word.surface : '${word.root} · ${word.surface}',
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
    subtitle: word.note.isEmpty
        ? (word.root.isEmpty
              ? const Text('Open this word again to resolve its root.')
              : null)
        : Text(word.note),
    trailing: PopupMenuButton<_ItemAction>(
      tooltip: 'Word options',
      onSelected: (action) async {
        switch (action) {
          case _ItemAction.highlight:
            onUpdateWord(
              word.copyWith(highlightEnabled: !word.highlightEnabled),
            );
          case _ItemAction.note:
            onEditWord(word);
          case _ItemAction.move:
            final destination = await _chooseDestination(context, workspace);
            if (destination != _cancelledChoice) {
              onUpdateWord(word.copyWith(groupId: () => destination));
            }
          case _ItemAction.color:
            final color = await _pickColor(
              context,
              selected: word.colorValue,
              title: 'Word highlight color',
            );
            if (color != null) {
              onUpdateWord(word.copyWith(colorValue: color));
            }
          case _ItemAction.remove:
            onRemoveWord(word);
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: _ItemAction.highlight,
          checked: word.highlightEnabled,
          child: const Text('Highlight root'),
        ),
        PopupMenuItem(
          value: _ItemAction.note,
          child: ListTile(
            leading: Icon(Icons.note_alt_outlined),
            title: Text('Edit note'),
          ),
        ),
        PopupMenuItem(
          value: _ItemAction.move,
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('Move to group'),
          ),
        ),
        PopupMenuItem(
          value: _ItemAction.color,
          child: ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Highlight color'),
          ),
        ),
        PopupMenuItem(
          value: _ItemAction.remove,
          child: ListTile(
            leading: Icon(Icons.bookmark_remove_outlined),
            title: Text('Remove'),
          ),
        ),
      ],
    ),
  );

  Widget _noteTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyNote note, {
    required int depth,
  }) => ListTile(
    key: ValueKey('note-${note.id}'),
    dense: true,
    contentPadding: EdgeInsetsDirectional.only(
      start: 16 + depth * 12.0,
      end: 0,
    ),
    title: Text(note.text),
    trailing: PopupMenuButton<_NoteAction>(
      tooltip: 'Note options',
      onSelected: (action) async {
        switch (action) {
          case _NoteAction.edit:
            onEditNote(note);
          case _NoteAction.move:
            final destination = await _chooseDestination(context, workspace);
            if (destination != _cancelledChoice) {
              onUpdateNote(note.copyWith(groupId: () => destination));
            }
          case _NoteAction.remove:
            onRemoveNote(note);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: _NoteAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_note),
            title: Text('Edit note'),
          ),
        ),
        PopupMenuItem(
          value: _NoteAction.move,
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outline),
            title: Text('Move to group'),
          ),
        ),
        PopupMenuItem(
          value: _NoteAction.remove,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Remove'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspace = activeWorkspace;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (workspaces.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(workspace?.id),
                        initialValue: workspace?.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final candidate in workspaces)
                            DropdownMenuItem(
                              value: candidate.id,
                              child: Text(
                                candidate.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) {
                          if (id != null) onSelect(id);
                        },
                      ),
                    ),
                    PopupMenuButton<_WorkspaceAction>(
                      tooltip: 'Workspace options',
                      onSelected: (action) {
                        switch (action) {
                          case _WorkspaceAction.create:
                            onCreate();
                          case _WorkspaceAction.toggleHighlights:
                            if (workspace != null) {
                              onToggleHighlights(!workspace.highlightsEnabled);
                            }
                          case _WorkspaceAction.rename:
                            onRename();
                          case _WorkspaceAction.delete:
                            onDelete();
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: _WorkspaceAction.create,
                          child: ListTile(
                            leading: Icon(Icons.add),
                            title: Text('New workspace'),
                          ),
                        ),
                        if (workspace != null)
                          CheckedPopupMenuItem(
                            value: _WorkspaceAction.toggleHighlights,
                            checked: workspace.highlightsEnabled,
                            child: const Text('Show study highlights'),
                          ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: _WorkspaceAction.rename,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Rename'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _WorkspaceAction.delete,
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete workspace'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: workspace == null
                  ? _EmptyWorkspace(onCreate: onCreate)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      children: [
                        _OutlineHeader(
                          currentIsBookmarked:
                              workspace.passageAt(
                                currentPassage.bookIndex,
                                currentPassage.chapter,
                                currentPassage.verse,
                              ) !=
                              null,
                          onBookmarkCurrent: () => onBookmarkCurrent(null),
                          onCreateGroup: () => onCreateGroup(null),
                          onCreateNote: () => onCreateNote(null),
                        ),
                        ..._itemsAt(
                          context,
                          workspace,
                          null,
                          ancestors: const {},
                        ),
                        if (workspace.groups.isEmpty &&
                            workspace.passages.isEmpty &&
                            workspace.words.isEmpty &&
                            workspace.notes.isEmpty)
                          const _SectionEmpty(
                            text:
                                'Bookmark a passage or word, or create a group '
                                'to begin a study or talk outline.',
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineHeader extends StatelessWidget {
  const _OutlineHeader({
    required this.currentIsBookmarked,
    required this.onBookmarkCurrent,
    required this.onCreateGroup,
    required this.onCreateNote,
  });

  final bool currentIsBookmarked;
  final VoidCallback onBookmarkCurrent;
  final VoidCallback onCreateGroup;
  final VoidCallback onCreateNote;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 8, top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            'Outline',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        PopupMenuButton<_OutlineAction>(
          tooltip: 'Add study item',
          icon: const Icon(Icons.add),
          onSelected: (action) {
            switch (action) {
              case _OutlineAction.bookmarkPassage:
                onBookmarkCurrent();
              case _OutlineAction.createGroup:
                onCreateGroup();
              case _OutlineAction.createNote:
                onCreateNote();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _OutlineAction.bookmarkPassage,
              enabled: !currentIsBookmarked,
              child: ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(
                  currentIsBookmarked
                      ? 'Current passage is bookmarked'
                      : 'Bookmark current passage',
                ),
              ),
            ),
            const PopupMenuItem(
              value: _OutlineAction.createNote,
              child: ListTile(
                leading: Icon(Icons.note_add_outlined),
                title: Text('New note'),
              ),
            ),
            const PopupMenuItem(
              value: _OutlineAction.createGroup,
              child: ListTile(
                leading: Icon(Icons.create_new_folder_outlined),
                title: Text('New group'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notes_outlined,
                  size: 42,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Build a study or talk from nested groups, passage '
                  'bookmarks, root words, and notes.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Create workspace'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

const _highlightColors = <int>[
  0xffffd54f,
  0xffffab91,
  0xffce93d8,
  0xff90caf9,
  0xff80cbc4,
  0xffa5d6a7,
  0xffe6ee9c,
  0xffbcaaa4,
];

const _topLevelChoice = '__top_level__';
const _cancelledChoice = '__cancelled__';

enum _WorkspaceAction { create, toggleHighlights, rename, delete }

enum _OutlineAction { bookmarkPassage, createNote, createGroup }

enum _GroupAction { addPassage, addNote, addGroup, edit, delete }

enum _ItemAction { highlight, note, move, color, remove }

enum _NoteAction { edit, move, remove }
