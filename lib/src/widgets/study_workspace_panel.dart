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
    required this.onMoveItem,
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
  final void Function(StudyItem item, String? groupId, int? index) onMoveItem;

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

  Widget _dropTarget(
    StudyWorkspace workspace,
    String? groupId, {
    int? index,
    required Widget child,
  }) => DragTarget<StudyItem>(
    key: ValueKey('drop-${groupId ?? 'top'}-${index ?? 'inside'}'),
    onWillAcceptWithDetails: (details) =>
        workspace.canMoveItem(details.data, groupId),
    onAcceptWithDetails: (details) => onMoveItem(details.data, groupId, index),
    builder: (context, candidates, rejected) => DecoratedBox(
      decoration: BoxDecoration(
        color: candidates.isEmpty
            ? Colors.transparent
            : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary,
        ),
      ),
      child: child,
    ),
  );

  Widget _rowDropTarget(
    StudyWorkspace workspace,
    StudyItem target,
    int targetIndex, {
    required Widget child,
  }) {
    int insertionIndex(StudyItem dragged) {
      final siblings = workspace.itemsIn(target.groupId);
      final sourceIndex = siblings.indexWhere(
        (item) => item.key == dragged.key,
      );
      // Dropping on a row while moving down places the item after that row;
      // moving up places it before. Explicit gaps still allow exact insertion.
      return sourceIndex >= 0 && sourceIndex < targetIndex
          ? targetIndex + 1
          : targetIndex;
    }

    return DragTarget<StudyItem>(
      key: ValueKey('reorder-${target.key}'),
      onWillAcceptWithDetails: (details) =>
          details.data.key != target.key &&
          workspace.canMoveItem(details.data, target.groupId),
      onAcceptWithDetails: (details) => onMoveItem(
        details.data,
        target.groupId,
        insertionIndex(details.data),
      ),
      builder: (context, candidates, rejected) {
        final below =
            candidates.isNotEmpty &&
            insertionIndex(candidates.first!) > targetIndex;
        final indicator = BorderSide(
          width: 2,
          color: candidates.isEmpty
              ? Colors.transparent
              : Theme.of(context).colorScheme.primary,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: below ? BorderSide.none : indicator,
              bottom: below ? indicator : BorderSide.none,
            ),
          ),
          child: child,
        );
      },
    );
  }

  String _itemLabel(StudyItem item) => switch (item.type) {
    StudyItemType.passage => _reference(item.value as StudyPassage),
    StudyItemType.word => (item.value as StudyWord).surface,
    StudyItemType.note => (item.value as StudyNote).text,
    StudyItemType.group => (item.value as StudyGroup).name,
  };

  List<Widget> _itemsAt(
    BuildContext context,
    StudyWorkspace workspace,
    String? groupId, {
    int depth = 0,
    Set<String> ancestors = const {},
  }) {
    final children = <Widget>[];
    final items = workspace.itemsIn(groupId);
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (item.type == StudyItemType.group &&
          ancestors.contains((item.value as StudyGroup).id)) {
        continue;
      }
      children.add(
        _dropTarget(
          workspace,
          groupId,
          index: index,
          child: const SizedBox(height: 2, width: double.infinity),
        ),
      );
      final handle = _OutlineDragHandle(item: item, label: _itemLabel(item));
      if (item.type == StudyItemType.group) {
        final group = item.value as StudyGroup;
        children.add(
          _groupTile(
            context,
            workspace,
            group,
            depth: depth,
            ancestors: {...ancestors, group.id},
            handle: handle,
            item: item,
            index: index,
          ),
        );
      } else {
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
          StudyItemType.group => throw StateError('Group rendered above'),
        };
        children.add(
          _rowDropTarget(
            workspace,
            item,
            index,
            child: Row(
              key: ValueKey(item.key),
              children: [
                Expanded(child: tile),
                handle,
              ],
            ),
          ),
        );
      }
    }
    children.add(
      _dropTarget(
        workspace,
        groupId,
        index: items.length,
        child: const SizedBox(height: 2, width: double.infinity),
      ),
    );
    return children;
  }

  Widget _groupTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyGroup group, {
    required int depth,
    required Set<String> ancestors,
    required Widget handle,
    required StudyItem item,
    required int index,
  }) => Padding(
    padding: EdgeInsetsDirectional.only(start: depth * 12.0),
    child: ExpansionTile(
      key: PageStorageKey((workspace.id, group.id)),
      initiallyExpanded: true,
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsetsDirectional.only(end: 0),
      childrenPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: _dropTarget(
        workspace,
        group.id,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            group.name,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      trailing: _rowDropTarget(
        workspace,
        item,
        index,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<_GroupAction>(
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
            handle,
          ],
        ),
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
    titleAlignment: passage.note.isEmpty
        ? ListTileTitleAlignment.center
        : ListTileTitleAlignment.top,
    minTileHeight: 32,
    minVerticalPadding: 0,
    contentPadding: EdgeInsetsDirectional.only(
      start: 16 + depth * 12.0,
      end: 0,
    ),
    leading: const Icon(Icons.menu_book_outlined, size: 18),
    title: Text(
      _reference(passage),
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    subtitle: passage.note.isEmpty ? null : Text(passage.note),
    onTap: () => onOpenPassage(passage),
    trailing: PopupMenuButton<_ItemAction>(
      tooltip: 'Passage options',
      iconSize: 18,
      padding: const EdgeInsets.all(6),
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(32, 32)),
        maximumSize: WidgetStatePropertyAll(Size(32, 32)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
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
  }) {
    final subtitle = [
      if (word.kind == StudyWordKind.root && word.root.isEmpty)
        'Open this word again to resolve its root.',
      if (word.note.isNotEmpty) word.note,
    ].join(' · ');
    return ListTile(
      key: ValueKey(word.key),
      dense: true,
      titleAlignment: subtitle.isEmpty
          ? ListTileTitleAlignment.center
          : ListTileTitleAlignment.top,
      minTileHeight: 32,
      minVerticalPadding: 0,
      contentPadding: EdgeInsetsDirectional.only(
        start: 16 + depth * 12.0,
        end: 0,
      ),
      leading: Tooltip(
        message: word.kind == StudyWordKind.root
            ? 'Root bookmark'
            : 'Form bookmark',
        child: Icon(
          word.kind == StudyWordKind.root
              ? Icons.account_tree_outlined
              : Icons.text_fields,
          size: 18,
        ),
      ),
      title: InkWell(
        onTap: () => onOpenWord(word),
        child: Text(
          word.kind == StudyWordKind.form || word.root.isEmpty
              ? word.surface
              : '${word.root} · ${word.surface}',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontFamily: 'Cardo',
            fontFamilyFallback: const ['Noto Serif Hebrew'],
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: PopupMenuButton<_ItemAction>(
        tooltip: 'Word options',
        iconSize: 18,
        padding: const EdgeInsets.all(6),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(32, 32)),
          maximumSize: WidgetStatePropertyAll(Size(32, 32)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
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
  }

  Widget _noteTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyNote note, {
    required int depth,
  }) => ListTile(
    key: ValueKey('note-${note.id}'),
    dense: true,
    minTileHeight: 32,
    minVerticalPadding: 0,
    contentPadding: EdgeInsetsDirectional.only(
      start: 16 + depth * 12.0,
      end: 0,
    ),
    title: Text(note.text),
    trailing: PopupMenuButton<_NoteAction>(
      tooltip: 'Note options',
      iconSize: 18,
      padding: const EdgeInsets.all(6),
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(32, 32)),
        maximumSize: WidgetStatePropertyAll(Size(32, 32)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
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
                      key: PageStorageKey('study-outline-${workspace.id}'),
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                      children: [
                        _dropTarget(
                          workspace,
                          null,
                          child: _OutlineHeader(
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

/// One drag gesture supports ordering and moving between groups. All handles
/// scroll the enclosing outline, including handles inside nested groups.
class _OutlineDragHandle extends StatefulWidget {
  const _OutlineDragHandle({required this.item, required this.label});

  final StudyItem item;
  final String label;

  @override
  State<_OutlineDragHandle> createState() => _OutlineDragHandleState();
}

class _OutlineDragHandleState extends State<_OutlineDragHandle>
    with AutomaticKeepAliveClientMixin {
  bool _dragging = false;

  @override
  bool get wantKeepAlive => _dragging;
  EdgeDraggingAutoScroller? _autoScroller;
  Offset? _dragPosition;

  void _scrollAtPointer() {
    final position = _dragPosition;
    if (position != null) {
      _autoScroller?.startAutoScrollIfNecessary(
        Rect.fromCenter(center: position, width: 40, height: 80),
      );
    }
  }

  @override
  void dispose() {
    _dragPosition = null;
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Draggable<StudyItem>(
      key: ValueKey('drag-${widget.item.key}'),
      data: widget.item,
      maxSimultaneousDrags: 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        _dragging = true;
        updateKeepAlive();
        _autoScroller = EdgeDraggingAutoScroller(
          Scrollable.of(context),
          velocityScalar: 12,
          onScrollViewScrolled: _scrollAtPointer,
        );
      },
      onDragUpdate: (details) {
        _dragPosition = details.globalPosition;
        _scrollAtPointer();
      },
      onDragEnd: (_) {
        _dragPosition = null;
        _autoScroller?.stopAutoScroll();
        _dragging = false;
        updateKeepAlive();
      },
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 220,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              widget.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      childWhenDragging: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.drag_handle, size: 20, color: Colors.grey),
      ),
      child: Tooltip(
        message: 'Drag to reorder or move into a group',
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.drag_handle, size: 20),
          ),
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
                  'passages, roots, specific forms, and notes.',
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
