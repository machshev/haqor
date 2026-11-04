import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../commentary.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// What can be done with a commentary note from its menu.
enum CommentaryAction { edit, addToStudy, delete }

/// A commentary note's reference, as "Genesis 1:3 · words 2–3".
String commentaryReference(
  StudyPassage anchor, {
  required bool useEnglishBookNames,
}) =>
    '${bookDisplayName(anchor.bookIndex, useEnglish: useEnglishBookNames)} '
    '${anchor.reference}';

/// One commentary note: its reference (opening the passage), its text and
/// its menu.
class CommentaryNoteCard extends StatelessWidget {
  const CommentaryNoteCard({
    super.key,
    required this.note,
    required this.useEnglishBookNames,
    required this.onAction,
    this.onOpen,
    this.showBook = true,
    this.compact = false,
  });

  final CommentaryNote note;
  final bool useEnglishBookNames;
  final void Function(CommentaryNote note, CommentaryAction action) onAction;
  final ValueChanged<CommentaryNote>? onOpen;

  /// Without the book's name, where the list already says it.
  final bool showBook;

  /// Smaller, for the reader's margin.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reference = showBook
        ? commentaryReference(
            note.anchor,
            useEnglishBookNames: useEnglishBookNames,
          )
        : note.anchor.reference;
    final textStyle = compact ? theme.textTheme.bodySmall : null;
    final open = onOpen;
    return Card(
      key: ValueKey('commentary-${note.id}'),
      margin: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
      color: theme.colorScheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 8 : 12,
          compact ? 2 : 4,
          0,
          compact ? 6 : 10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.comment_outlined,
                  size: compact ? 14 : 16,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: open == null ? null : () => open(note),
                    child: Text(
                      reference,
                      style:
                          (compact
                                  ? theme.textTheme.labelSmall
                                  : theme.textTheme.labelLarge)
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: open == null
                                    ? null
                                    : theme.colorScheme.primary,
                              ),
                    ),
                  ),
                ),
                CommentaryMenuButton(
                  onSelected: (action) => onAction(note, action),
                  compact: compact,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              // In the margin a long note is cut short; its menu edits it whole.
              child: compact
                  ? Text(
                      markdownPlainText(note.text),
                      style: textStyle,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    )
                  : MarkdownNote(note.text, style: textStyle),
            ),
          ],
        ),
      ),
    );
  }
}

class CommentaryMenuButton extends StatelessWidget {
  const CommentaryMenuButton({
    super.key,
    required this.onSelected,
    this.compact = false,
  });

  final ValueChanged<CommentaryAction> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) => PopupMenuButton<CommentaryAction>(
    tooltip: 'Commentary options',
    iconSize: compact ? 16 : 18,
    padding: const EdgeInsets.all(4),
    style: ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size.square(compact ? 28 : 32)),
      maximumSize: WidgetStatePropertyAll(Size.square(compact ? 28 : 32)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onSelected: onSelected,
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: CommentaryAction.edit,
        child: ListTile(
          leading: Icon(Icons.edit_note),
          title: Text('Edit commentary'),
        ),
      ),
      PopupMenuItem(
        value: CommentaryAction.addToStudy,
        child: ListTile(
          leading: Icon(Icons.playlist_add),
          title: Text('Add to study'),
        ),
      ),
      PopupMenuItem(
        value: CommentaryAction.delete,
        child: ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('Delete'),
        ),
      ),
    ],
  );
}

/// The commentary on one chapter, for the reader's side panel or sheet.
class CommentaryPanel extends StatelessWidget {
  const CommentaryPanel({
    super.key,
    required this.store,
    required this.bookIndex,
    required this.chapter,
    required this.useEnglishBookNames,
    required this.onAdd,
    required this.onAction,
    required this.onOpen,
    required this.onBrowse,
    this.onClose,
    this.scrollController,
  });

  final CommentaryStore store;
  final int bookIndex;
  final int chapter;
  final bool useEnglishBookNames;
  final VoidCallback onAdd;
  final void Function(CommentaryNote note, CommentaryAction action) onAction;
  final ValueChanged<CommentaryNote> onOpen;
  final VoidCallback onBrowse;

  /// Docked, hides the panel.
  final VoidCallback? onClose;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final theme = Theme.of(context);
      final notes = store.notesInChapter(bookIndex, chapter);
      final book = bookDisplayName(bookIndex, useEnglish: useEnglishBookNames);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Commentary · $book $chapter',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'All commentary',
                  icon: const Icon(Icons.list_alt),
                  onPressed: onBrowse,
                ),
                IconButton(
                  key: const ValueKey('commentary-add'),
                  tooltip: 'Add commentary',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: onAdd,
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close commentary',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No commentary on this chapter yet. Add some here, '
                        'or from a verse number’s or a word’s menu.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    children: [
                      for (final note in notes)
                        CommentaryNoteCard(
                          note: note,
                          useEnglishBookNames: useEnglishBookNames,
                          showBook: note.bookIndex != bookIndex,
                          onAction: onAction,
                          onOpen: onOpen,
                        ),
                    ],
                  ),
          ),
        ],
      );
    },
  );
}

/// Every commentary note, in Bible order under its book, with a search.
class CommentaryPage extends StatefulWidget {
  const CommentaryPage({
    super.key,
    required this.store,
    required this.useEnglishBookNames,
    required this.onAction,
    required this.onOpen,
  });

  final CommentaryStore store;
  final bool useEnglishBookNames;
  final void Function(CommentaryNote note, CommentaryAction action) onAction;

  /// Open the note's passage in the reader; the page closes first.
  final ValueChanged<CommentaryNote> onOpen;

  @override
  State<CommentaryPage> createState() => _CommentaryPageState();
}

class _CommentaryPageState extends State<CommentaryPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(CommentaryNote note) {
    if (_query.isEmpty) return true;
    final reference = commentaryReference(
      note.anchor,
      useEnglishBookNames: widget.useEnglishBookNames,
    ).toLowerCase();
    return reference.contains(_query) ||
        markdownPlainText(note.text).toLowerCase().contains(_query);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Commentary')),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final all = widget.store.notes;
        final notes = all.where(_matches).toList();
        final children = <Widget>[];
        int? book;
        for (final note in notes) {
          if (note.bookIndex != book) {
            book = note.bookIndex;
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text(
                  bookDisplayName(book, useEnglish: widget.useEnglishBookNames),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            );
          }
          children.add(
            CommentaryNoteCard(
              note: note,
              useEnglishBookNames: widget.useEnglishBookNames,
              showBook: false,
              onAction: widget.onAction,
              onOpen: (note) {
                Navigator.of(context).pop();
                widget.onOpen(note);
              },
            ),
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search commentary',
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: notes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          all.isEmpty
                              ? 'No commentary yet. Add a note on a verse '
                                    'from its number’s menu, or on a phrase '
                                    'from a word’s menu.'
                              : 'No commentary matches.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          children: children,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}
