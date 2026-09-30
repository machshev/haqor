import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../study_workspace.dart';
import 'cross_references_sheet.dart' show crossReferenceStrength;
import 'markdown_note.dart';

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
    required this.onSwitchWordKind,
    required this.onRemoveWord,
    required this.onOpenWord,
    required this.onCreateNote,
    required this.onEditNote,
    required this.onUpdateNote,
    required this.onRemoveNote,
    required this.onMoveItem,
    this.onOpenLinkVerse,
    this.onShowLink,
    this.onEditLink,
    this.onUpdateLink,
    this.onRemoveLink,
    this.onToggleHeadings,
    this.onCreateSection,
    this.onEditSection,
    this.onUpdateSection,
    this.onDeleteSection,
    this.onOpenSection,
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
  final ValueChanged<StudyWord> onSwitchWordKind;
  final ValueChanged<StudyWord> onRemoveWord;
  final ValueChanged<StudyWord> onOpenWord;
  final ValueChanged<String?> onCreateNote;
  final ValueChanged<StudyNote> onEditNote;
  final ValueChanged<StudyNote> onUpdateNote;
  final ValueChanged<StudyNote> onRemoveNote;
  final void Function(StudyItem item, String? groupId, int? index) onMoveItem;

  /// Bookmarked cross references: open one of its verses in the reader, show
  /// it in the cross-reference panel, edit its note, move it, or remove it.
  final void Function(StudyLink link, StudyLinkVerse verse)? onOpenLinkVerse;
  final ValueChanged<StudyLink>? onShowLink;
  final ValueChanged<StudyLink>? onEditLink;
  final ValueChanged<StudyLink>? onUpdateLink;
  final ValueChanged<StudyLink>? onRemoveLink;

  /// Passage summaries and their section headings: show them in the reader,
  /// add one (a summary, or a heading when the parent is a section), edit,
  /// update, delete, or open one's first verse in the reader.
  final ValueChanged<bool>? onToggleHeadings;
  final ValueChanged<String?>? onCreateSection;
  final ValueChanged<StudySection>? onEditSection;
  final ValueChanged<StudySection>? onUpdateSection;
  final ValueChanged<StudySection>? onDeleteSection;
  final ValueChanged<StudySection>? onOpenSection;

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: useEnglishBookNames)} '
      '${passage.reference}';

  String _verseReference(StudyLinkVerse verse) =>
      '${bookDisplayName(verse.bookIndex, useEnglish: useEnglishBookNames)} '
      '${verse.chapter}:${verse.verse}';

  String _linkLabel(StudyLink link) =>
      '${_verseReference(link.earlier)} ↔ ${_verseReference(link.later)}';

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
                    ? const Icon(Icons.check, size: 20, color: Colors.black87)
                    : null,
              ),
            ),
        ],
      ),
    ),
  );

  /// Moves [value] through the workspace's own rules, so it lands last in its
  /// new place, and only where it may go, whatever changed while choosing.
  Future<void> _moveTo(
    BuildContext context,
    StudyWorkspace workspace,
    Object value,
  ) async {
    final item = StudyItem.of(value);
    final destination = await _chooseDestination(context, workspace, item);
    if (destination != _cancelledChoice && destination != item.groupId) {
      onMoveItem(item, destination, null);
    }
  }

  Future<String?> _chooseDestination(
    BuildContext context,
    StudyWorkspace workspace,
    StudyItem item,
  ) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move study item'),
        children: [
          if (workspace.canMoveItem(item, null))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, _topLevelChoice),
              child: const ListTile(
                leading: Icon(Icons.notes_outlined),
                title: Text('Top level'),
                subtitle: Text('Not inside a group'),
              ),
            ),
          for (final group in workspace.groups)
            if (workspace.canMoveItem(item, group.id))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, group.id),
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(_containerPath(workspace, group.id)),
                ),
              ),
          for (final section in workspace.sections)
            if (workspace.canMoveItem(item, section.id))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, section.id),
                child: ListTile(
                  leading: Icon(_sectionIcon(section)),
                  title: Text(_containerPath(workspace, section.id)),
                ),
              ),
        ],
      ),
    );
    if (choice == null) return _cancelledChoice;
    return choice == _topLevelChoice ? null : choice;
  }

  String _containerPath(StudyWorkspace workspace, String id) {
    final names = <String>[workspace.containerName(id) ?? ''];
    final visited = <String>{id};
    var parent = workspace.containerParent(id);
    while (parent != null && visited.add(parent)) {
      names.insert(0, workspace.containerName(parent) ?? '');
      parent = workspace.containerParent(parent);
    }
    return names.join(' / ');
  }

  static IconData _sectionIcon(StudySection section) =>
      section.isSummary ? Icons.toc : Icons.subdirectory_arrow_right;

  /// A summary's book and range, or a heading's verses up to the next one.
  String _sectionReference(StudyWorkspace workspace, StudySection section) {
    final summary = workspace.summaryOf(section);
    final book = summary?.bookIndex;
    final name = book == null
        ? ''
        : '${bookDisplayName(book, useEnglish: useEnglishBookNames)} ';
    if (section.isSummary) return '$name${section.range!.reference}';
    final end = workspace.sectionEnd(section);
    final start = '${section.chapter}:${section.verse}';
    final last = end.verse == null
        ? (end.chapter == section.chapter ? 'end' : '${end.chapter}:end')
        : end.chapter == section.chapter
        ? '${end.verse}'
        : '${end.chapter}:${end.verse}';
    return end.chapter == section.chapter && end.verse == section.verse
        ? '$name$start'
        : '$name$start–$last';
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

  /// The gap before an item, or after a container's last one.
  Widget _dropGap(
    StudyWorkspace workspace,
    String? groupId, {
    required int index,
    required int depth,
  }) => _OutlineDropTarget(
    key: ValueKey('drop-${groupId ?? 'top'}-$index'),
    workspace: workspace,
    base: (groupId: groupId, index: index, depth: depth),
    onMoveItem: onMoveItem,
  );

  /// An item's row: others dropped on it reorder around it, and the item
  /// itself, moved across the indent area, changes level.
  Widget _rowDropTarget(
    StudyWorkspace workspace,
    StudyItem target,
    int targetIndex, {
    required int depth,
    required Widget child,
  }) => _OutlineDropTarget(
    key: ValueKey('reorder-${target.key}'),
    workspace: workspace,
    base: (groupId: target.groupId, index: targetIndex, depth: depth),
    row: target,
    onMoveItem: onMoveItem,
    child: child,
  );

  String _itemLabel(StudyItem item) => switch (item.type) {
    StudyItemType.passage => _reference(item.value as StudyPassage),
    StudyItemType.word => (item.value as StudyWord).surface,
    StudyItemType.note => markdownPlainText((item.value as StudyNote).text),
    StudyItemType.link => _linkLabel(item.value as StudyLink),
    StudyItemType.group => (item.value as StudyGroup).name,
    StudyItemType.section => (item.value as StudySection).title,
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
      final containerId = switch (item.value) {
        StudyGroup(:final id) || StudySection(:final id) => id,
        _ => null,
      };
      if (containerId != null && ancestors.contains(containerId)) continue;
      children.add(_dropGap(workspace, groupId, index: index, depth: depth));
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
      } else if (item.type == StudyItemType.section) {
        final section = item.value as StudySection;
        children.add(
          _sectionTile(
            context,
            workspace,
            section,
            depth: depth,
            ancestors: {...ancestors, section.id},
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
          StudyItemType.link => _linkTile(
            context,
            workspace,
            item.value as StudyLink,
            depth: depth,
          ),
          StudyItemType.group ||
          StudyItemType.section => throw StateError('Rendered above'),
        };
        children.add(
          _rowDropTarget(
            workspace,
            item,
            index,
            depth: depth,
            child: Row(
              key: ValueKey(item.key),
              crossAxisAlignment: CrossAxisAlignment.start,
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
      _dropGap(workspace, groupId, index: items.length, depth: depth),
    );
    return children;
  }

  // An expanded group or heading marks only where it starts. Material's
  // default also draws a bar after the children, which stacks up with the
  // next tile's bar and reads as a stray separator.
  ShapeBorder _expandedTileShape(BuildContext context) =>
      Border(top: BorderSide(color: Theme.of(context).dividerColor));

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
    child: _OutlineExpansion.tile(
      (workspace.id, group.id),
      (key, expanded) => ExpansionTile(
        key: key,
        initiallyExpanded: expanded,
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsetsDirectional.only(end: 0),
        childrenPadding: EdgeInsets.zero,
        shape: _expandedTileShape(context),
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
          depth: depth,
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
                    case _GroupAction.addSummary:
                      onCreateSection?.call(group.id);
                    case _GroupAction.edit:
                      onEditGroup(group);
                    case _GroupAction.delete:
                      onDeleteGroup(group);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: _GroupAction.addNote,
                    child: ListTile(
                      leading: Icon(Icons.note_add_outlined),
                      title: Text('Add note'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _GroupAction.addPassage,
                    child: ListTile(
                      leading: Icon(Icons.bookmark_add_outlined),
                      title: Text('Add current passage'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _GroupAction.addGroup,
                    child: ListTile(
                      leading: Icon(Icons.create_new_folder_outlined),
                      title: Text('Add subgroup'),
                    ),
                  ),
                  if (onCreateSection != null)
                    const PopupMenuItem(
                      value: _GroupAction.addSummary,
                      child: ListTile(
                        leading: Icon(Icons.toc),
                        title: Text('Add passage summary'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: _GroupAction.edit,
                    child: ListTile(
                      leading: Icon(Icons.edit_note),
                      title: Text('Edit group'),
                    ),
                  ),
                  const PopupMenuItem(
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
          if (workspace.itemsIn(group.id).isEmpty)
            const _SectionEmpty(text: 'This group is empty.'),
        ],
      ),
    ),
  );

  Widget _sectionTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudySection section, {
    required int depth,
    required Set<String> ancestors,
    required Widget handle,
    required StudyItem item,
    required int index,
  }) {
    final theme = Theme.of(context);
    final open = onOpenSection;
    final create = onCreateSection;
    return Padding(
      key: ValueKey(item.key),
      padding: EdgeInsetsDirectional.only(start: depth * 12.0),
      child: _OutlineExpansion.tile(
        (workspace.id, section.id),
        (key, expanded) => ExpansionTile(
          key: key,
          initiallyExpanded: expanded,
          dense: true,
          visualDensity: VisualDensity.compact,
          tilePadding: const EdgeInsetsDirectional.only(end: 0),
          childrenPadding: EdgeInsets.zero,
          shape: _expandedTileShape(context),
          controlAffinity: ListTileControlAffinity.leading,
          title: _dropTarget(
            workspace,
            section.id,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_sectionIcon(section), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          section.title,
                          style:
                              (section.isSummary
                                      ? theme.textTheme.titleSmall
                                      : theme.textTheme.bodyMedium)
                                  ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  InkWell(
                    onTap: open == null ? null : () => open(section),
                    child: Text(
                      _sectionReference(workspace, section),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (section.note.isNotEmpty)
                    MarkdownNote(
                      section.note,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          trailing: _rowDropTarget(
            workspace,
            item,
            index,
            depth: depth,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (section.isSummary &&
                    (!section.showInReader || !workspace.headingsEnabled))
                  Tooltip(
                    message: 'Not shown in the reader',
                    child: Icon(
                      Icons.visibility_off_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                PopupMenuButton<_SectionAction>(
                  tooltip: section.isSummary
                      ? 'Summary options'
                      : 'Heading options',
                  onSelected: (action) {
                    switch (action) {
                      case _SectionAction.addHeading:
                        create?.call(section.id);
                      case _SectionAction.addPassage:
                        onBookmarkCurrent(section.id);
                      case _SectionAction.addNote:
                        onCreateNote(section.id);
                      case _SectionAction.addGroup:
                        onCreateGroup(section.id);
                      case _SectionAction.showInReader:
                        onUpdateSection?.call(
                          section.copyWith(showInReader: !section.showInReader),
                        );
                      case _SectionAction.edit:
                        onEditSection?.call(section);
                      case _SectionAction.delete:
                        onDeleteSection?.call(section);
                    }
                  },
                  itemBuilder: (_) => [
                    if (section.isSummary)
                      CheckedPopupMenuItem(
                        value: _SectionAction.showInReader,
                        checked: section.showInReader,
                        child: const Text('Show headings in reader'),
                      ),
                    const PopupMenuItem(
                      value: _SectionAction.addHeading,
                      child: ListTile(
                        leading: Icon(Icons.subdirectory_arrow_right),
                        title: Text('Add section heading'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SectionAction.addNote,
                      child: ListTile(
                        leading: Icon(Icons.note_add_outlined),
                        title: Text('Add note'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SectionAction.addPassage,
                      child: ListTile(
                        leading: Icon(Icons.bookmark_add_outlined),
                        title: Text('Add current passage'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _SectionAction.addGroup,
                      child: ListTile(
                        leading: Icon(Icons.create_new_folder_outlined),
                        title: Text('Add subgroup'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _SectionAction.edit,
                      child: ListTile(
                        leading: const Icon(Icons.edit_note),
                        title: Text(
                          section.isSummary ? 'Edit summary' : 'Edit heading',
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: _SectionAction.delete,
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(
                          section.isSummary
                              ? 'Delete summary'
                              : 'Delete heading',
                        ),
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
              section.id,
              depth: depth + 1,
              ancestors: ancestors,
            ),
            if (workspace.itemsIn(section.id).isEmpty)
              const _SectionEmpty(
                text: 'Add section headings, notes or passages here.',
              ),
          ],
        ),
      ),
    );
  }

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
    subtitle: passage.note.isEmpty ? null : MarkdownNote(passage.note),
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
            await _moveTo(context, workspace, passage);
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
            title: Text('Edit reference and note'),
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
    final subtitle = _noteSubtitle(
      word.kind == StudyWordKind.root && word.root.isEmpty
          ? 'Open this word again to resolve its root.'
          : null,
      word.note,
    );
    final isRoot = word.kind == StudyWordKind.root;
    final canSwitchKind = workspace.canSwitchWordKind(word);
    return ListTile(
      key: ValueKey(word.key),
      dense: true,
      titleAlignment: subtitle == null
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
              ? Icons.park_outlined
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
      subtitle: subtitle,
      trailing: PopupMenuButton<_WordAction>(
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
            case _WordAction.highlight:
              onUpdateWord(
                word.copyWith(highlightEnabled: !word.highlightEnabled),
              );
            case _WordAction.switchKind:
              onSwitchWordKind(word);
            case _WordAction.note:
              onEditWord(word);
            case _WordAction.move:
              await _moveTo(context, workspace, word);
            case _WordAction.color:
              final color = await _pickColor(
                context,
                selected: word.colorValue,
                title: 'Word highlight color',
              );
              if (color != null) {
                onUpdateWord(word.copyWith(colorValue: color));
              }
            case _WordAction.remove:
              onRemoveWord(word);
          }
        },
        itemBuilder: (_) => [
          CheckedPopupMenuItem(
            value: _WordAction.highlight,
            checked: word.highlightEnabled,
            child: Text(isRoot ? 'Highlight root' : 'Highlight form'),
          ),
          PopupMenuItem(
            value: _WordAction.switchKind,
            enabled: canSwitchKind,
            child: ListTile(
              enabled: canSwitchKind,
              leading: Icon(isRoot ? Icons.text_fields : Icons.park_outlined),
              title: Text(
                isRoot ? 'Switch to form bookmark' : 'Switch to root bookmark',
              ),
              subtitle: canSwitchKind
                  ? null
                  : Text(
                      !isRoot && word.root.isEmpty
                          ? 'Root not resolved'
                          : 'Already bookmarked',
                    ),
            ),
          ),
          PopupMenuItem(
            value: _WordAction.note,
            child: ListTile(
              leading: Icon(Icons.note_alt_outlined),
              title: Text('Edit note'),
            ),
          ),
          PopupMenuItem(
            value: _WordAction.move,
            child: ListTile(
              leading: Icon(Icons.drive_file_move_outline),
              title: Text('Move to group'),
            ),
          ),
          PopupMenuItem(
            value: _WordAction.color,
            child: ListTile(
              leading: Icon(Icons.palette_outlined),
              title: Text('Highlight color'),
            ),
          ),
          PopupMenuItem(
            value: _WordAction.remove,
            child: ListTile(
              leading: Icon(Icons.bookmark_remove_outlined),
              title: Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkTile(
    BuildContext context,
    StudyWorkspace workspace,
    StudyLink link, {
    required int depth,
  }) {
    final theme = Theme.of(context);
    final open = onOpenLinkVerse;
    Widget verse(StudyLinkVerse v) => InkWell(
      onTap: open == null ? null : () => open(link, v),
      child: Text(
        _verseReference(v),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    final subtitle = _noteSubtitle(
      link.score > 0 ? crossReferenceStrength(link.score) : null,
      link.note,
    );
    return ListTile(
      key: ValueKey(link.key),
      dense: true,
      titleAlignment: subtitle == null
          ? ListTileTitleAlignment.center
          : ListTileTitleAlignment.top,
      minTileHeight: 32,
      minVerticalPadding: 0,
      contentPadding: EdgeInsetsDirectional.only(
        start: 16 + depth * 12.0,
        end: 0,
      ),
      leading: const Tooltip(
        message: 'Cross-reference bookmark',
        child: Icon(Icons.link, size: 18),
      ),
      title: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [verse(link.earlier), const Text('↔'), verse(link.later)],
      ),
      subtitle: subtitle,
      trailing: PopupMenuButton<_LinkAction>(
        tooltip: 'Link options',
        iconSize: 18,
        padding: const EdgeInsets.all(6),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(32, 32)),
          maximumSize: WidgetStatePropertyAll(Size(32, 32)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelected: (action) async {
          switch (action) {
            case _LinkAction.show:
              onShowLink?.call(link);
            case _LinkAction.note:
              onEditLink?.call(link);
            case _LinkAction.move:
              await _moveTo(context, workspace, link);
            case _LinkAction.remove:
              onRemoveLink?.call(link);
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: _LinkAction.show,
            child: ListTile(
              leading: Icon(Icons.link),
              title: Text('Show cross references'),
            ),
          ),
          PopupMenuItem(
            value: _LinkAction.note,
            child: ListTile(
              leading: Icon(Icons.note_alt_outlined),
              title: Text('Edit note'),
            ),
          ),
          PopupMenuItem(
            value: _LinkAction.move,
            child: ListTile(
              leading: Icon(Icons.drive_file_move_outline),
              title: Text('Move to group'),
            ),
          ),
          PopupMenuItem(
            value: _LinkAction.remove,
            child: ListTile(
              leading: Icon(Icons.bookmark_remove_outlined),
              title: Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }

  /// A bookmark's [detail] (if any) with its Markdown [note] beneath, or
  /// null when there is neither.
  Widget? _noteSubtitle(String? detail, String note) {
    if (detail == null && note.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail != null) Text(detail),
        if (note.isNotEmpty) MarkdownNote(note),
      ],
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
    leading: const Icon(Icons.notes_outlined, size: 18),
    title: MarkdownNote(note.text),
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
            await _moveTo(context, workspace, note);
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
                          case _WorkspaceAction.toggleHeadings:
                            if (workspace != null) {
                              onToggleHeadings?.call(
                                !workspace.headingsEnabled,
                              );
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
                        if (workspace != null && onToggleHeadings != null)
                          CheckedPopupMenuItem(
                            value: _WorkspaceAction.toggleHeadings,
                            checked: workspace.headingsEnabled,
                            child: const Text('Show study headings'),
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
                  : _OutlineDragScope(
                      child: _OutlineExpansion(
                        child: ListView(
                          key: PageStorageKey('study-outline-${workspace.id}'),
                          padding: const EdgeInsets.fromLTRB(
                            _outlinePadding,
                            0,
                            _outlinePadding,
                            24,
                          ),
                          children: [
                            _dropTarget(
                              workspace,
                              null,
                              child: _OutlineHeader(
                                onBookmarkCurrent: () =>
                                    onBookmarkCurrent(null),
                                onCreateGroup: () => onCreateGroup(null),
                                onCreateNote: () => onCreateNote(null),
                                onCreateSummary: onCreateSection == null
                                    ? null
                                    : () => onCreateSection!(null),
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
                                workspace.notes.isEmpty &&
                                workspace.links.isEmpty &&
                                workspace.sections.isEmpty)
                              const _SectionEmpty(
                                text:
                                    'Bookmark a passage or word, or create a group '
                                    'to begin a study or talk outline.',
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared state for one drag through the outline: how far in the pointer is,
/// which picks the level; the drop target it was last over; and where the
/// item will land, for the dragged chip to name.
///
/// The drag handles sit at the end of each row, close to the panel's edge, so
/// the pointer soon strays past every target. The last target keeps its
/// place while the pointer stays level with it, and a drop out there lands
/// where it shows.
class _OutlineDragScope extends StatefulWidget {
  const _OutlineDragScope({required this.child});

  final Widget child;

  static _OutlineDragScopeState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OutlineDragNotifier>()?.scope;

  @override
  State<_OutlineDragScope> createState() => _OutlineDragScopeState();
}

class _OutlineDragScopeState extends State<_OutlineDragScope> {
  final destination = ValueNotifier<String?>(null);
  _OutlineDropTargetState? _current;

  void _enter(_OutlineDropTargetState target) {
    if (_current != target) _current?._reset();
    _current = target;
  }

  void _forget(_OutlineDropTargetState target) {
    if (_current == target) _current = null;
  }

  /// Follows the pointer beyond the last target's sides.
  void dragged(StudyItem item, Offset pointer) {
    final current = _current;
    if (current == null || !current.mounted) return;
    if (current._levelWith(pointer)) {
      current._update(item, pointer);
    } else {
      current._reset();
      _current = null;
      destination.value = null;
    }
  }

  /// A drop beside the last target, rather than on one.
  void dropped(StudyItem item) {
    final current = _current;
    _current = null;
    if (current != null && current.mounted) current._drop(item);
  }

  /// How far [pointer] is in from the outline's leading edge, where its
  /// rows start.
  double? indentAt(Offset pointer) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final local = box.globalToLocal(pointer).dx;
    return (Directionality.of(context) == TextDirection.rtl
            ? box.size.width - local
            : local) -
        _outlinePadding;
  }

  void ended() {
    _current?._reset();
    _current = null;
    destination.value = null;
  }

  @override
  void dispose() {
    destination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => destination.value = null,
    child: _OutlineDragNotifier(scope: this, child: widget.child),
  );
}

class _OutlineDragNotifier extends InheritedWidget {
  const _OutlineDragNotifier({required this.scope, required super.child});

  final _OutlineDragScopeState scope;

  @override
  bool updateShouldNotify(_OutlineDragNotifier old) => scope != old.scope;
}

/// A place in the outline: a position among a container's items, and how far
/// it is indented.
typedef _OutlinePlace = ({String? groupId, int index, int depth});

/// The outline's inset from the panel's sides.
const _outlinePadding = 8.0;

/// The width of each level's band in the indent area at the start of the
/// outline. While dragging, the band under the pointer picks the level the
/// item lands at; beyond the deepest band, it stays at the natural level of
/// the place it is over. The bands are wider than the rows' own indents so
/// they are easy to hit with a finger.
const _levelBand = 28.0;

String? _containerIdOf(StudyItem item) => switch (item.value) {
  StudyGroup(:final id) || StudySection(:final id) => id,
  _ => null,
};

/// Where [dragged] lands when dropped at [base] with the pointer [indent]
/// pixels in from the outline's leading edge. Shallower levels place it after
/// each enclosing container in turn; deeper ones at the end of the container
/// just above, then of that container's last, and so on. Levels that can't
/// take the item are passed over on the way back to [base]; null means
/// nowhere fits.
_OutlinePlace? _resolvePlace(
  StudyWorkspace workspace,
  StudyItem dragged,
  _OutlinePlace base,
  double? indent,
) {
  final levels = <_OutlinePlace>[base];
  final visited = <String>{};
  var id = base.groupId;
  var depth = base.depth;
  while (id != null && visited.add(id)) {
    final parent = workspace.containerParent(id);
    final at = workspace
        .itemsIn(parent)
        .indexWhere((item) => _containerIdOf(item) == id);
    if (at < 0) break;
    levels.insert(0, (groupId: parent, index: at + 1, depth: --depth));
    id = parent;
  }
  final baseLevel = levels.length - 1;
  var container = base.groupId;
  var before = base.index;
  depth = base.depth;
  visited.clear();
  while (true) {
    final items = workspace.itemsIn(container);
    var above = before - 1;
    // The gap just below the dragged item is the same place as the one above.
    if (above >= 0 && above < items.length && items[above].key == dragged.key) {
      above--;
    }
    if (above < 0 || above >= items.length) break;
    final inner = _containerIdOf(items[above]);
    if (inner == null || !visited.add(inner)) break;
    container = inner;
    before = workspace.itemsIn(inner).length;
    levels.add((groupId: inner, index: before, depth: ++depth));
  }
  var target = baseLevel;
  final band = indent == null ? null : (indent / _levelBand).floor();
  if (band != null && band <= levels.last.depth) {
    target = (band - levels.first.depth).clamp(0, levels.length - 1);
  }
  while (!workspace.canMoveItem(dragged, levels[target].groupId)) {
    if (target == baseLevel) return null;
    target += target > baseLevel ? -1 : 1;
  }
  return levels[target];
}

/// Accepts drops on the outline. A gap takes the item at its place; a row
/// takes other items before or after it, and its own item when it changes
/// level. Either way the pointer's band in the indent area picks the level,
/// and the target draws an insertion line at the level it will land on.
class _OutlineDropTarget extends StatefulWidget {
  const _OutlineDropTarget({
    super.key,
    required this.workspace,
    required this.base,
    required this.onMoveItem,
    this.row,
    this.child,
  });

  final StudyWorkspace workspace;
  final _OutlinePlace base;
  final StudyItem? row;
  final Widget? child;
  final void Function(StudyItem item, String? groupId, int? index) onMoveItem;

  @override
  State<_OutlineDropTarget> createState() => _OutlineDropTargetState();
}

class _OutlineDropTargetState extends State<_OutlineDropTarget> {
  _OutlinePlace? _place;

  bool _isOwnRow(StudyItem dragged) => widget.row?.key == dragged.key;

  /// The place at the level the pointer started on. Dropping on another row
  /// while moving down places the item after that row; moving up places it
  /// before.
  _OutlinePlace _basePlace(StudyItem dragged) {
    final base = widget.base;
    final row = widget.row;
    if (row == null || _isOwnRow(dragged)) return base;
    final siblings = widget.workspace.itemsIn(row.groupId);
    final source = siblings.indexWhere((item) => item.key == dragged.key);
    return source >= 0 && source < base.index
        ? (groupId: base.groupId, index: base.index + 1, depth: base.depth)
        : base;
  }

  _OutlinePlace? _placeFor(StudyItem dragged, Offset pointer) {
    final place = _resolvePlace(
      widget.workspace,
      dragged,
      _basePlace(dragged),
      _OutlineDragScope.of(context)?.indentAt(pointer),
    );
    // The item's own row only moves it once it changes level.
    if (_isOwnRow(dragged) && place?.depth == widget.base.depth) return null;
    return place;
  }

  /// Whether [pointer] is beside this target, above its bottom and below its
  /// top, however far to either side.
  bool _levelWith(Offset pointer) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final top = box.localToGlobal(Offset.zero).dy;
    return pointer.dy >= top && pointer.dy < top + box.size.height;
  }

  void _update(StudyItem dragged, Offset pointer) {
    final place = _placeFor(dragged, pointer);
    if (place != _place) setState(() => _place = place);
    _OutlineDragScope.of(context)?.destination.value = place == null
        ? null
        : _placeLabel(place);
  }

  void _reset() {
    if (mounted && _place != null) setState(() => _place = null);
  }

  void _drop(StudyItem dragged) {
    final place = _place;
    _reset();
    _OutlineDragScope.of(context)?.destination.value = null;
    if (place != null) widget.onMoveItem(dragged, place.groupId, place.index);
  }

  String _placeLabel(_OutlinePlace place) {
    final id = place.groupId;
    if (id == null) return 'Top level';
    return 'In ${widget.workspace.containerName(id) ?? ''}';
  }

  _OutlineDragScopeState? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = _OutlineDragScope.of(context);
  }

  @override
  void deactivate() {
    _scope?._forget(this);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => DragTarget<StudyItem>(
    onWillAcceptWithDetails: (details) {
      // Whether a drop fits depends on the pointer's level, which keeps
      // changing, so accept and decide on each move.
      _OutlineDragScope.of(context)?._enter(this);
      _update(details.data, details.offset);
      return true;
    },
    onMove: (details) => _update(details.data, details.offset),
    onAcceptWithDetails: (details) {
      _OutlineDragScope.of(context)?._forget(this);
      _drop(details.data);
    },
    builder: (context, candidates, rejected) {
      final place = _place;
      final child = widget.child;
      if (child == null) {
        return place == null
            ? const SizedBox(height: 2, width: double.infinity)
            : _InsertionLine(depth: place.depth, label: _placeLabel(place));
      }
      // Another item marks the edge of the row it will go beside, and the
      // dragged chip names the level; the row's own item only has the chip.
      if (place == null ||
          place.groupId != widget.base.groupId ||
          (widget.row != null &&
              candidates.isNotEmpty &&
              _isOwnRow(candidates.first!))) {
        return child;
      }
      final after = place.index > widget.base.index;
      final line = BorderSide(
        width: 2,
        color: Theme.of(context).colorScheme.primary,
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: after ? BorderSide.none : line,
            bottom: after ? line : BorderSide.none,
          ),
        ),
        child: child,
      );
    },
  );
}

/// Where a dropped item will go: a line starting at its level's band, under
/// the pointer, captioned with the group or heading it will be in.
class _InsertionLine extends StatelessWidget {
  const _InsertionLine({required this.depth, required this.label});

  final int depth;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * _levelBand, end: 4),
      child: SizedBox(
        height: 32,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 14),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                Expanded(child: Container(height: 3, color: color)),
              ],
            ),
            const SizedBox(height: 4),
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
    final destination = _OutlineDragScope.of(context)?.destination;
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
        _OutlineDragScope.of(
          context,
        )?.dragged(widget.item, details.globalPosition);
      },
      onDragEnd: (details) {
        final scope = _OutlineDragScope.of(context);
        if (!details.wasAccepted) scope?.dropped(widget.item);
        scope?.ended();
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (destination != null)
                  ValueListenableBuilder(
                    valueListenable: destination,
                    builder: (context, place, _) => place == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '→ $place',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.drag_handle, size: 20, color: Colors.grey),
      ),
      child: Tooltip(
        message: 'Drag to move; drag toward the left to choose its level',
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

/// Expands or collapses every group and heading in the outline at once.
/// Each tile otherwise keeps its own state, so setting them all starts a new
/// generation of tiles, which open in the chosen state.
class _OutlineExpansion extends StatefulWidget {
  const _OutlineExpansion({required this.child});

  final Widget child;

  static _OutlineExpansionState? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_OutlineExpansionScope>()
      ?.state;

  /// An expandable tile for the container [id], built with the key and
  /// starting state for the current generation.
  static Widget tile(
    Object id,
    Widget Function(Key key, bool expanded) build,
  ) => Builder(
    builder: (context) {
      final scope = context
          .dependOnInheritedWidgetOfExactType<_OutlineExpansionScope>();
      return build(
        PageStorageKey((id, scope?.generation ?? 0)),
        scope?.expanded ?? true,
      );
    },
  );

  @override
  State<_OutlineExpansion> createState() => _OutlineExpansionState();
}

class _OutlineExpansionState extends State<_OutlineExpansion> {
  var _generation = 0;
  var _expanded = true;

  void setAll({required bool expanded}) => setState(() {
    _generation++;
    _expanded = expanded;
  });

  @override
  Widget build(BuildContext context) => _OutlineExpansionScope(
    state: this,
    generation: _generation,
    expanded: _expanded,
    child: widget.child,
  );
}

class _OutlineExpansionScope extends InheritedWidget {
  const _OutlineExpansionScope({
    required this.state,
    required this.generation,
    required this.expanded,
    required super.child,
  });

  final _OutlineExpansionState state;
  final int generation;
  final bool expanded;

  @override
  bool updateShouldNotify(_OutlineExpansionScope old) =>
      generation != old.generation;
}

class _OutlineHeader extends StatelessWidget {
  const _OutlineHeader({
    required this.onBookmarkCurrent,
    required this.onCreateGroup,
    required this.onCreateNote,
    this.onCreateSummary,
  });

  final VoidCallback onBookmarkCurrent;
  final VoidCallback onCreateGroup;
  final VoidCallback onCreateNote;
  final VoidCallback? onCreateSummary;

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
        IconButton(
          tooltip: 'Collapse all',
          icon: const Icon(Icons.unfold_less),
          onPressed: () =>
              _OutlineExpansion.of(context)?.setAll(expanded: false),
        ),
        IconButton(
          tooltip: 'Expand all',
          icon: const Icon(Icons.unfold_more),
          onPressed: () =>
              _OutlineExpansion.of(context)?.setAll(expanded: true),
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
              case _OutlineAction.createSummary:
                onCreateSummary?.call();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _OutlineAction.bookmarkPassage,
              child: ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Bookmark passage'),
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
            if (onCreateSummary != null)
              const PopupMenuItem(
                value: _OutlineAction.createSummary,
                child: ListTile(
                  leading: Icon(Icons.toc),
                  title: Text('New passage summary'),
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

enum _WorkspaceAction {
  create,
  toggleHighlights,
  toggleHeadings,
  rename,
  delete,
}

enum _OutlineAction { bookmarkPassage, createNote, createGroup, createSummary }

enum _GroupAction { addPassage, addNote, addGroup, addSummary, edit, delete }

enum _SectionAction {
  showInReader,
  addHeading,
  addNote,
  addPassage,
  addGroup,
  edit,
  delete,
}

enum _ItemAction { highlight, note, move, color, remove }

enum _WordAction { highlight, switchKind, note, move, color, remove }

enum _NoteAction { edit, move, remove }

enum _LinkAction { show, note, move, remove }
