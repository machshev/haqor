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
    required this.onBookmarkCurrent,
    required this.onOpenPassage,
    required this.onEditPassage,
    required this.onSetCentral,
    required this.onRemovePassage,
  });

  final List<StudyWorkspace> workspaces;
  final StudyWorkspace? activeWorkspace;
  final StudyPassage currentPassage;
  final bool useEnglishBookNames;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelect;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onBookmarkCurrent;
  final ValueChanged<StudyPassage> onOpenPassage;
  final ValueChanged<StudyPassage> onEditPassage;
  final ValueChanged<StudyPassage> onSetCentral;
  final ValueChanged<StudyPassage> onRemovePassage;

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: useEnglishBookNames)} '
      '${passage.chapter}:${passage.verse}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Study workspace',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add),
                    tooltip: 'New workspace',
                  ),
                ],
              ),
            ),
            if (workspaces.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(activeWorkspace?.id),
                  initialValue: activeWorkspace?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final workspace in workspaces)
                      DropdownMenuItem(
                        value: workspace.id,
                        child: Text(
                          workspace.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) onSelect(id);
                  },
                ),
              ),
            if (activeWorkspace == null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmarks_outlined,
                          size: 42,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Collect a central passage, related references, '
                          'highlights and notes in one place.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed:
                            activeWorkspace!.passageAt(
                                  currentPassage.bookIndex,
                                  currentPassage.chapter,
                                  currentPassage.verse,
                                ) ==
                                null
                            ? onBookmarkCurrent
                            : null,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: Text(
                          activeWorkspace!.passageAt(
                                    currentPassage.bookIndex,
                                    currentPassage.chapter,
                                    currentPassage.verse,
                                  ) ==
                                  null
                              ? 'Bookmark current'
                              : 'Current is saved',
                        ),
                      ),
                    ),
                    PopupMenuButton<_WorkspaceAction>(
                      tooltip: 'Workspace options',
                      onSelected: (action) {
                        switch (action) {
                          case _WorkspaceAction.rename:
                            onRename();
                          case _WorkspaceAction.delete:
                            onDelete();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _WorkspaceAction.rename,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Rename'),
                          ),
                        ),
                        PopupMenuItem(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Connected passages',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  itemCount: activeWorkspace!.passages.length,
                  itemBuilder: (context, index) {
                    final passage = activeWorkspace!.passages[index];
                    final central =
                        passage.locationKey ==
                        activeWorkspace!.centralPassage.locationKey;
                    return Card(
                      elevation: 0,
                      color: central
                          ? theme.colorScheme.primaryContainer.withValues(
                              alpha: 0.55,
                            )
                          : null,
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          central ? Icons.push_pin : Icons.bookmark_outline,
                          color: central ? theme.colorScheme.primary : null,
                        ),
                        title: Text(_reference(passage)),
                        subtitle: passage.note.isEmpty
                            ? (central ? const Text('Central passage') : null)
                            : Text(
                                passage.note,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => onOpenPassage(passage),
                        trailing: PopupMenuButton<_PassageAction>(
                          tooltip: 'Passage options',
                          onSelected: (action) {
                            switch (action) {
                              case _PassageAction.note:
                                onEditPassage(passage);
                              case _PassageAction.central:
                                onSetCentral(passage);
                              case _PassageAction.remove:
                                onRemovePassage(passage);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: _PassageAction.note,
                              child: ListTile(
                                leading: Icon(Icons.note_alt_outlined),
                                title: Text('Edit note'),
                              ),
                            ),
                            if (!central)
                              const PopupMenuItem(
                                value: _PassageAction.central,
                                child: ListTile(
                                  leading: Icon(Icons.push_pin_outlined),
                                  title: Text('Make central'),
                                ),
                              ),
                            if (!central)
                              const PopupMenuItem(
                                value: _PassageAction.remove,
                                child: ListTile(
                                  leading: Icon(Icons.bookmark_remove_outlined),
                                  title: Text('Remove'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (activeWorkspace!.words.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    '${activeWorkspace!.words.length} highlighted '
                    '${activeWorkspace!.words.length == 1 ? 'word' : 'words'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _WorkspaceAction { rename, delete }

enum _PassageAction { note, central, remove }
