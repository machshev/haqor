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
    required this.onWordColorChanged,
    required this.onPassageColorChanged,
    required this.onCreateTheme,
    required this.onEditTheme,
    required this.onDeleteTheme,
    required this.onAddCurrentToTheme,
    required this.onOpenPassage,
    required this.onEditPassage,
    required this.onTogglePassage,
    required this.onRemovePassage,
    required this.onEditWord,
    required this.onToggleWord,
    required this.onRemoveWord,
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
  final ValueChanged<int> onWordColorChanged;
  final ValueChanged<int> onPassageColorChanged;
  final VoidCallback onCreateTheme;
  final ValueChanged<StudyTheme> onEditTheme;
  final ValueChanged<StudyTheme> onDeleteTheme;
  final ValueChanged<StudyTheme> onAddCurrentToTheme;
  final ValueChanged<StudyPassage> onOpenPassage;
  final void Function(StudyTheme theme, StudyPassage passage) onEditPassage;
  final void Function(StudyTheme theme, StudyPassage passage) onTogglePassage;
  final void Function(StudyTheme theme, StudyPassage passage) onRemovePassage;
  final ValueChanged<StudyWord> onEditWord;
  final ValueChanged<StudyWord> onToggleWord;
  final ValueChanged<StudyWord> onRemoveWord;

  String _reference(StudyPassage passage) =>
      '${bookDisplayName(passage.bookIndex, useEnglish: useEnglishBookNames)} '
      '${passage.chapter}:${passage.verse}';

  Future<void> _pickColor(
    BuildContext context, {
    required int selected,
    required String title,
    required ValueChanged<int> onChanged,
  }) async {
    const colors = <int>[
      0xffffd54f,
      0xffffab91,
      0xffce93d8,
      0xff90caf9,
      0xff80cbc4,
      0xffa5d6a7,
      0xffe6ee9c,
      0xffbcaaa4,
    ];
    final picked = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final value in colors)
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
    if (picked != null) onChanged(picked);
  }

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
            Expanded(
              child: workspace == null
                  ? _EmptyWorkspace(onCreate: onCreate)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: const Text('Show study highlights'),
                          subtitle: const Text(
                            'Master switch for bookmarked words and passages',
                          ),
                          value: workspace.highlightsEnabled,
                          onChanged: onToggleHighlights,
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: _ColorButton(
                                  label: 'Words',
                                  value: workspace.wordColorValue,
                                  onPressed: () => _pickColor(
                                    context,
                                    selected: workspace.wordColorValue,
                                    title: 'Word highlight color',
                                    onChanged: onWordColorChanged,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ColorButton(
                                  label: 'Passages',
                                  value: workspace.passageColorValue,
                                  onPressed: () => _pickColor(
                                    context,
                                    selected: workspace.passageColorValue,
                                    title: 'Passage highlight color',
                                    onChanged: onPassageColorChanged,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _SectionHeader(
                          title: 'Bookmarked words',
                          count: workspace.words.length,
                        ),
                        if (workspace.words.isEmpty)
                          const _SectionEmpty(
                            text:
                                'Select a word in the reader, then bookmark its '
                                'root from Word study.',
                          )
                        else
                          for (final word in workspace.words)
                            Card(
                              elevation: 0,
                              child: ListTile(
                                dense: true,
                                leading: IconButton(
                                  onPressed: () => onToggleWord(word),
                                  icon: Icon(
                                    word.highlightEnabled
                                        ? Icons.highlight
                                        : Icons.highlight_outlined,
                                  ),
                                  tooltip: word.highlightEnabled
                                      ? 'Turn off this root highlight'
                                      : 'Turn on this root highlight',
                                ),
                                title: Text(
                                  word.root.isEmpty
                                      ? word.surface
                                      : '${word.root} · ${word.surface}',
                                  textDirection: TextDirection.rtl,
                                ),
                                subtitle: word.note.isEmpty
                                    ? (word.root.isEmpty
                                          ? const Text(
                                              'Open this word again to resolve '
                                              'its root.',
                                            )
                                          : null)
                                    : Text(word.note),
                                onTap: () => onEditWord(word),
                                trailing: IconButton(
                                  onPressed: () => onRemoveWord(word),
                                  icon: const Icon(
                                    Icons.bookmark_remove_outlined,
                                  ),
                                  tooltip: 'Remove word bookmark',
                                ),
                              ),
                            ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(
                              child: _SectionHeader(title: 'Passage themes'),
                            ),
                            TextButton.icon(
                              onPressed: onCreateTheme,
                              icon: const Icon(Icons.add),
                              label: const Text('New theme'),
                            ),
                          ],
                        ),
                        if (workspace.themes.isEmpty)
                          const _SectionEmpty(
                            text:
                                'Create a theme for an idea, add a header note, '
                                'then collect related passages.',
                          )
                        else
                          for (final studyTheme in workspace.themes)
                            Card(
                              elevation: 0,
                              clipBehavior: Clip.antiAlias,
                              child: ExpansionTile(
                                key: PageStorageKey(studyTheme.id),
                                initiallyExpanded: true,
                                leading: const Icon(Icons.topic_outlined),
                                title: Text(studyTheme.name),
                                subtitle: studyTheme.headerNote.isEmpty
                                    ? Text(
                                        '${studyTheme.passages.length} '
                                        '${studyTheme.passages.length == 1 ? 'passage' : 'passages'}',
                                      )
                                    : Text(
                                        studyTheme.headerNote,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: PopupMenuButton<_ThemeAction>(
                                  tooltip: 'Theme options',
                                  onSelected: (action) {
                                    switch (action) {
                                      case _ThemeAction.edit:
                                        onEditTheme(studyTheme);
                                      case _ThemeAction.delete:
                                        onDeleteTheme(studyTheme);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: _ThemeAction.edit,
                                      child: ListTile(
                                        leading: Icon(Icons.edit_note),
                                        title: Text('Edit header'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _ThemeAction.delete,
                                      child: ListTile(
                                        leading: Icon(Icons.delete_outline),
                                        title: Text('Delete theme'),
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      0,
                                      12,
                                      8,
                                    ),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.tonalIcon(
                                        onPressed:
                                            studyTheme.passageAt(
                                                  currentPassage.bookIndex,
                                                  currentPassage.chapter,
                                                  currentPassage.verse,
                                                ) ==
                                                null
                                            ? () => onAddCurrentToTheme(
                                                studyTheme,
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.bookmark_add_outlined,
                                        ),
                                        label: Text(
                                          studyTheme.passageAt(
                                                    currentPassage.bookIndex,
                                                    currentPassage.chapter,
                                                    currentPassage.verse,
                                                  ) ==
                                                  null
                                              ? 'Add current passage'
                                              : 'Current passage is in theme',
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (studyTheme.passages.isEmpty)
                                    const _SectionEmpty(
                                      text: 'No passages in this theme yet.',
                                    )
                                  else
                                    for (final passage in studyTheme.passages)
                                      ListTile(
                                        dense: true,
                                        leading: IconButton(
                                          onPressed: () => onTogglePassage(
                                            studyTheme,
                                            passage,
                                          ),
                                          icon: Icon(
                                            passage.highlightEnabled
                                                ? Icons.highlight
                                                : Icons.highlight_outlined,
                                          ),
                                          tooltip: passage.highlightEnabled
                                              ? 'Turn off this passage highlight'
                                              : 'Turn on this passage highlight',
                                        ),
                                        title: Text(_reference(passage)),
                                        subtitle: passage.note.isEmpty
                                            ? null
                                            : Text(
                                                passage.note,
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                        onTap: () => onOpenPassage(passage),
                                        trailing: PopupMenuButton<_PassageAction>(
                                          tooltip: 'Passage options',
                                          onSelected: (action) {
                                            switch (action) {
                                              case _PassageAction.note:
                                                onEditPassage(
                                                  studyTheme,
                                                  passage,
                                                );
                                              case _PassageAction.remove:
                                                onRemovePassage(
                                                  studyTheme,
                                                  passage,
                                                );
                                            }
                                          },
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: _PassageAction.note,
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons.note_alt_outlined,
                                                ),
                                                title: Text('Edit note'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: _PassageAction.remove,
                                              child: ListTile(
                                                leading: Icon(
                                                  Icons
                                                      .bookmark_remove_outlined,
                                                ),
                                                title: Text('Remove'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                ],
                              ),
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
                  Icons.bookmarks_outlined,
                  size: 42,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Keep root bookmarks, notes, and themed passage lists '
                  'together while you study.',
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Text(
      count == null ? title : '$title ($count)',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });

  final String label;
  final int value;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(value),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    ),
    label: Text('$label color'),
  );
}

enum _WorkspaceAction { rename, delete }

enum _ThemeAction { edit, delete }

enum _PassageAction { note, remove }
