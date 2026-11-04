import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../passage_selection.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// A passage's reference, as "Genesis 1:3 · words 2–3".
String passageReference(
  StudyPassage passage, {
  required bool useEnglishBookNames,
}) =>
    '${bookDisplayName(passage.bookIndex, useEnglish: useEnglishBookNames)} '
    '${passage.reference}';

/// The bar over the reader while a passage is being chosen in it: what is
/// chosen, a switch widening it to its verses or chapter (or back to its
/// words), and [actions].
class PassageSelectionBar extends StatelessWidget {
  const PassageSelectionBar({
    super.key,
    required this.selection,
    required this.useEnglishBookNames,
    required this.onScopeChanged,
    required this.actions,
    this.title,
  });

  final PassageSelection selection;
  final bool useEnglishBookNames;
  final ValueChanged<PassageScope> onScopeChanged;
  final List<Widget> actions;

  /// What the passage is being chosen for, when it is for something already
  /// begun (such as a note being written).
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          key: const ValueKey('word-selection-bar'),
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                Text(
                  passageReference(
                    selection.passage,
                    useEnglishBookNames: useEnglishBookNames,
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'Tap or highlight words, or tap verses, in either text. '
                  'Any book or chapter can be opened meanwhile.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    SegmentedButton<PassageScope>(
                      key: const ValueKey('passage-scope'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: [
                        ButtonSegment(
                          value: PassageScope.words,
                          label: const Text('Words'),
                          enabled: selection.hasWords,
                        ),
                        ButtonSegment(
                          value: PassageScope.verses,
                          label: Text(
                            selection.passage.lastVerse ==
                                        selection.passage.verse &&
                                    selection.passage.lastChapter ==
                                        selection.passage.chapter
                                ? 'Verse'
                                : 'Verses',
                          ),
                        ),
                        const ButtonSegment(
                          value: PassageScope.chapter,
                          label: Text('Chapter'),
                        ),
                      ],
                      selected: {selection.scope},
                      onSelectionChanged: (scopes) =>
                          onScopeChanged(scopes.single),
                    ),
                    Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How a [showPassageNoteDialog] ended, but for being cancelled.
sealed class PassageNoteResult {
  const PassageNoteResult(this.passages, this.text);

  /// The passages and note as the dialog left them.
  final List<StudyPassage> passages;
  final String text;
}

/// Saved.
class PassageNoteSaved extends PassageNoteResult {
  const PassageNoteSaved(super.passages, super.text);
}

/// Left to choose a passage in the reader: to replace the one at [index],
/// or with none, to add one. The dialog opens again afterwards.
class PassageNotePick extends PassageNoteResult {
  const PassageNotePick(super.passages, super.text, {this.index});

  final int? index;
}

/// A note on one passage, or with [multiple] on several: its passages show
/// as chips above the note, which has the focus. Tapping a chip (or, with
/// [multiple], "Add passage") leaves the dialog to choose the passage in the
/// reader; with [multiple], a chip can be unlinked while others remain.
/// [validate] can refuse the passages, saying why.
Future<PassageNoteResult?> showPassageNoteDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required List<StudyPassage> passages,
  required bool useEnglishBookNames,
  String text = '',
  String noteLabel = 'Note',
  bool noteRequired = false,
  bool multiple = false,
  String? Function(List<StudyPassage> passages)? validate,
}) => showDialog<PassageNoteResult>(
  context: context,
  builder: (_) => _PassageNoteDialog(
    title: title,
    confirmLabel: confirmLabel,
    passages: passages,
    text: text,
    noteLabel: noteLabel,
    noteRequired: noteRequired,
    multiple: multiple,
    useEnglishBookNames: useEnglishBookNames,
    validate: validate,
  ),
);

class _PassageNoteDialog extends StatefulWidget {
  const _PassageNoteDialog({
    required this.title,
    required this.confirmLabel,
    required this.passages,
    required this.text,
    required this.noteLabel,
    required this.noteRequired,
    required this.multiple,
    required this.useEnglishBookNames,
    required this.validate,
  });

  final String title;
  final String confirmLabel;
  final List<StudyPassage> passages;
  final String text;
  final String noteLabel;
  final bool noteRequired;
  final bool multiple;
  final bool useEnglishBookNames;
  final String? Function(List<StudyPassage> passages)? validate;

  @override
  State<_PassageNoteDialog> createState() => _PassageNoteDialogState();
}

class _PassageNoteDialogState extends State<_PassageNoteDialog> {
  late final List<StudyPassage> _passages = List.of(widget.passages);
  late final _text = TextEditingController(text: widget.text);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _pick({int? index}) => Navigator.pop<PassageNoteResult>(
    context,
    PassageNotePick(_passages, _text.text, index: index),
  );

  void _save() {
    final text = _text.text.trim();
    final error = widget.noteRequired && text.isEmpty
        ? 'Write the note.'
        : widget.validate?.call(_passages);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop<PassageNoteResult>(
      context,
      PassageNoteSaved(_passages, text),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
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
                for (final (i, passage) in _passages.indexed)
                  InputChip(
                    key: ValueKey('passage-chip-$i'),
                    avatar: const Icon(Icons.menu_book_outlined, size: 16),
                    label: Text(
                      passageReference(
                        passage,
                        useEnglishBookNames: widget.useEnglishBookNames,
                      ),
                    ),
                    tooltip: 'Choose this passage in the reader',
                    onPressed: () => _pick(index: i),
                    onDeleted: widget.multiple && _passages.length > 1
                        ? () => setState(() => _passages.removeAt(i))
                        : null,
                    deleteButtonTooltipMessage: 'Unlink this passage',
                  ),
                if (widget.multiple)
                  ActionChip(
                    key: const ValueKey('passage-add'),
                    avatar: const Icon(Icons.add_link, size: 16),
                    label: const Text('Add passage'),
                    tooltip: 'Choose another passage in the reader',
                    onPressed: _pick,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            MarkdownNoteField(
              controller: _text,
              label: widget.noteLabel,
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
      FilledButton(onPressed: _save, child: Text(widget.confirmLabel)),
    ],
  );
}
