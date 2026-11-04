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

/// The passages a note is on, each opening its passage: "Genesis 1:3 ·
/// 2:4", the book named where it changes, and not at all while it is
/// [contextBook].
class CommentaryReferences extends StatelessWidget {
  const CommentaryReferences({
    super.key,
    required this.anchors,
    required this.useEnglishBookNames,
    this.contextBook,
    this.onOpen,
    this.style,
  });

  final List<StudyPassage> anchors;
  final bool useEnglishBookNames;
  final int? contextBook;
  final ValueChanged<StudyPassage>? onOpen;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = onOpen;
    final linkStyle = (style ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.bold,
      color: open == null ? null : theme.colorScheme.primary,
    );
    final labels = <String>[];
    var book = contextBook;
    for (final anchor in anchors) {
      labels.add(
        anchor.bookIndex == book
            ? anchor.reference
            : commentaryReference(
                anchor,
                useEnglishBookNames: useEnglishBookNames,
              ),
      );
      book = anchor.bookIndex;
    }
    return Wrap(
      children: [
        for (final (i, anchor) in anchors.indexed) ...[
          if (i > 0) Text(' · ', style: style),
          InkWell(
            onTap: open == null ? null : () => open(anchor),
            child: Text(labels[i], style: linkStyle),
          ),
        ],
      ],
    );
  }
}

/// One commentary note: its passages (each opening its passage), its text
/// and its menu.
class CommentaryNoteCard extends StatelessWidget {
  const CommentaryNoteCard({
    super.key,
    required this.note,
    required this.useEnglishBookNames,
    required this.onAction,
    this.onOpen,
    this.contextBook,
    this.compact = false,
  });

  final CommentaryNote note;
  final bool useEnglishBookNames;
  final void Function(CommentaryNote note, CommentaryAction action) onAction;
  final ValueChanged<StudyPassage>? onOpen;

  /// The book the list is already in, whose name its passages leave out.
  final int? contextBook;

  /// Smaller, for the reader's margin.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = compact ? theme.textTheme.bodySmall : null;
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
                  child: CommentaryReferences(
                    anchors: note.anchors,
                    useEnglishBookNames: useEnglishBookNames,
                    contextBook: contextBook,
                    onOpen: onOpen,
                    style: compact
                        ? theme.textTheme.labelSmall
                        : theme.textTheme.labelLarge,
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
  final ValueChanged<StudyPassage> onOpen;
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
                          contextBook: bookIndex,
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

  /// Open one of a note's passages in the reader; the page closes first.
  final ValueChanged<StudyPassage> onOpen;

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
    return note.anchors.any(
          (anchor) => commentaryReference(
            anchor,
            useEnglishBookNames: widget.useEnglishBookNames,
          ).toLowerCase().contains(_query),
        ) ||
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
              contextBook: note.bookIndex,
              onAction: widget.onAction,
              onOpen: (anchor) {
                Navigator.of(context).pop();
                widget.onOpen(anchor);
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

/// A commentary note as the dialog leaves it.
typedef CommentaryDraft = ({List<StudyPassage> anchors, String text});

/// The passage editor without a note, to change one of a note's passages or
/// add another; null when cancelled.
typedef CommentaryPassageEditor =
    Future<StudyPassage?> Function(
      StudyPassage initial, {
      required bool adding,
    });

/// Write or edit a commentary note. Its passages are already chosen, so they
/// show as chips above the note (each changing its passage, or unlinking it
/// while others remain), and the note has the focus.
Future<CommentaryDraft?> showCommentaryDialog(
  BuildContext context, {
  required List<StudyPassage> anchors,
  required bool creating,
  required bool useEnglishBookNames,
  required CommentaryPassageEditor editPassage,
  String text = '',
}) => showDialog<CommentaryDraft>(
  context: context,
  builder: (_) => _CommentaryDialog(
    anchors: anchors,
    text: text,
    creating: creating,
    useEnglishBookNames: useEnglishBookNames,
    editPassage: editPassage,
  ),
);

class _CommentaryDialog extends StatefulWidget {
  const _CommentaryDialog({
    required this.anchors,
    required this.text,
    required this.creating,
    required this.useEnglishBookNames,
    required this.editPassage,
  });

  final List<StudyPassage> anchors;
  final String text;
  final bool creating;
  final bool useEnglishBookNames;
  final CommentaryPassageEditor editPassage;

  @override
  State<_CommentaryDialog> createState() => _CommentaryDialogState();
}

class _CommentaryDialogState extends State<_CommentaryDialog> {
  late final List<StudyPassage> _anchors = List.of(widget.anchors);
  late final _text = TextEditingController(text: widget.text);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _change(int index) async {
    final changed = await widget.editPassage(_anchors[index], adding: false);
    if (changed == null || !mounted) return;
    setState(() => _anchors[index] = changed);
  }

  Future<void> _add() async {
    final added = await widget.editPassage(_anchors.last, adding: true);
    if (added == null || !mounted) return;
    if (_anchors.any((a) => a.locationKey == added.locationKey)) return;
    setState(() => _anchors.add(added));
  }

  void _save() {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write the note.');
      return;
    }
    Navigator.pop<CommentaryDraft>(context, (anchors: _anchors, text: text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creating ? 'Add commentary' : 'Edit commentary'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (i, anchor) in _anchors.indexed)
                  InputChip(
                    key: ValueKey('commentary-anchor-$i'),
                    avatar: const Icon(Icons.menu_book_outlined, size: 16),
                    label: Text(
                      commentaryReference(
                        anchor,
                        useEnglishBookNames: widget.useEnglishBookNames,
                      ),
                    ),
                    tooltip: 'Change this passage',
                    onPressed: () => _change(i),
                    onDeleted: _anchors.length > 1
                        ? () => setState(() => _anchors.removeAt(i))
                        : null,
                    deleteButtonTooltipMessage: 'Unlink this passage',
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_link, size: 16),
                  label: const Text('Add passage'),
                  onPressed: _add,
                ),
              ],
            ),
            const SizedBox(height: 12),
            MarkdownNoteField(
              controller: _text,
              label: 'Commentary',
              minLines: 4,
              maxLines: 12,
              autofocus: true,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(widget.creating ? 'Add' : 'Save'),
      ),
    ],
  );
}

/// Choose a note to link a passage to, the most recently written first,
/// with a search.
Future<CommentaryNote?> pickCommentaryNote(
  BuildContext context, {
  required CommentaryStore store,
  required bool useEnglishBookNames,
  required String title,
}) => showDialog<CommentaryNote>(
  context: context,
  builder: (_) => _CommentaryPicker(
    store: store,
    useEnglishBookNames: useEnglishBookNames,
    title: title,
  ),
);

class _CommentaryPicker extends StatefulWidget {
  const _CommentaryPicker({
    required this.store,
    required this.useEnglishBookNames,
    required this.title,
  });

  final CommentaryStore store;
  final bool useEnglishBookNames;
  final String title;

  @override
  State<_CommentaryPicker> createState() => _CommentaryPickerState();
}

class _CommentaryPickerState extends State<_CommentaryPicker> {
  String _query = '';

  bool _matches(CommentaryNote note) =>
      _query.isEmpty ||
      markdownPlainText(note.text).toLowerCase().contains(_query) ||
      note.anchors.any(
        (anchor) => commentaryReference(
          anchor,
          useEnglishBookNames: widget.useEnglishBookNames,
        ).toLowerCase().contains(_query),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notes = widget.store.notes.where(_matches).toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search commentary',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: notes.isEmpty
                  ? const Center(child: Text('No commentary matches.'))
                  : ListView(
                      children: [
                        for (final note in notes)
                          ListTile(
                            key: ValueKey('pick-commentary-${note.id}'),
                            title: CommentaryReferences(
                              anchors: note.anchors,
                              useEnglishBookNames: widget.useEnglishBookNames,
                              style: theme.textTheme.labelLarge,
                            ),
                            subtitle: Text(
                              markdownPlainText(note.text),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, note),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
