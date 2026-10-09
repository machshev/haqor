import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../external_link.dart';

/// A study note written in Markdown, rendered in [style] (the ambient text
/// style by default). Web and email links open outside the app.
class MarkdownNote extends StatelessWidget {
  const MarkdownNote(this.data, {super.key, this.style});

  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = DefaultTextStyle.of(context).style.merge(style);
    final size = base.fontSize ?? 14;
    TextStyle heading(double scale) =>
        base.copyWith(fontSize: size * scale, fontWeight: FontWeight.bold);
    return MarkdownBody(
      data: data,
      softLineBreak: true,
      onTapLink: (_, href, _) => _openLink(context, href),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        listBullet: base,
        tableBody: base,
        tableHead: base.copyWith(fontWeight: FontWeight.bold),
        h1: heading(1.4),
        h2: heading(1.25),
        h3: heading(1.1),
        h4: heading(1),
        h5: heading(1),
        h6: heading(1),
        a: base.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: base.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        blockquote: base.copyWith(color: theme.colorScheme.onSurfaceVariant),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 8),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        pPadding: EdgeInsets.zero,
        blockSpacing: size * 0.5,
      ),
    );
  }
}

/// The link schemes a note may open; anything else is ignored.
const _openableSchemes = {'http', 'https', 'mailto'};

Future<void> _openLink(BuildContext context, String? href) async {
  final uri = href == null ? null : Uri.tryParse(href);
  if (uri == null || !_openableSchemes.contains(uri.scheme.toLowerCase())) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await openExternalLink(uri);
  } catch (_) {}
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text('Could not open $href')));
  }
}

/// [markdown] as plain text on one line, for labels too small to render it.
String markdownPlainText(String markdown) {
  final text = StringBuffer();
  void visit(md.Node node) {
    if (node is md.Element) {
      node.children?.forEach(visit);
      if (_blockTags.contains(node.tag)) text.write(' ');
    } else {
      text.write(node.textContent);
    }
  }

  md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parse(markdown).forEach(visit);
  return text.toString().replaceAll(RegExp(r"\s+"), ' ').trim();
}

const _blockTags = {
  'p',
  'li',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'blockquote',
  'pre',
  'br',
  'tr',
  'td',
  'th',
};

/// A Markdown text field with a formatting toolbar, keyboard shortcuts
/// (Ctrl/Cmd+B, Ctrl/Cmd+I) and a preview of the rendered note.
class MarkdownNoteField extends StatefulWidget {
  const MarkdownNoteField({
    super.key,
    required this.controller,
    required this.label,
    this.minLines = 3,
    this.maxLines = 8,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final int minLines, maxLines;
  final bool autofocus;

  @override
  State<MarkdownNoteField> createState() => _MarkdownNoteFieldState();
}

class _MarkdownNoteFieldState extends State<MarkdownNoteField> {
  final _focus = FocusNode();
  bool _preview = false;

  TextEditingController get _controller => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Wraps the selection in [marker] (or unwraps it when already wrapped);
  /// with nothing selected, inserts a pair of markers around the cursor.
  void _wrap(String marker) {
    final value = _controller.value;
    final text = value.text;
    var selection = value.selection;
    if (!selection.isValid) {
      selection = TextSelection.collapsed(offset: text.length);
    }
    final start = selection.start, end = selection.end;
    final n = marker.length;
    final wrapped =
        start >= n &&
        end + n <= text.length &&
        text.substring(start - n, start) == marker &&
        text.substring(end, end + n) == marker;
    if (wrapped) {
      _controller.value = TextEditingValue(
        text:
            text.substring(0, start - n) +
            text.substring(start, end) +
            text.substring(end + n),
        selection: TextSelection(baseOffset: start - n, extentOffset: end - n),
      );
    } else {
      _controller.value = TextEditingValue(
        text:
            text.substring(0, start) +
            marker +
            text.substring(start, end) +
            marker +
            text.substring(end),
        selection: TextSelection(baseOffset: start + n, extentOffset: end + n),
      );
    }
    _focus.requestFocus();
  }

  /// Turns the selection into a link's text, leaving the cursor where the
  /// address goes; with nothing selected, selects placeholder link text.
  void _link() {
    final value = _controller.value;
    final text = value.text;
    var selection = value.selection;
    if (!selection.isValid) {
      selection = TextSelection.collapsed(offset: text.length);
    }
    final start = selection.start, end = selection.end;
    final label = start == end ? 'link text' : text.substring(start, end);
    const address = 'https://';
    _controller.value = TextEditingValue(
      text:
          '${text.substring(0, start)}[$label]($address)${text.substring(end)}',
      selection: start == end
          ? TextSelection(
              baseOffset: start + 1,
              extentOffset: start + 1 + label.length,
            )
          : TextSelection.collapsed(
              offset: start + label.length + 3 + address.length,
            ),
    );
    _focus.requestFocus();
  }

  /// Toggles [prefix] at the start of each line the selection touches;
  /// [numbered] numbers the lines instead ("1. ", "2. ", …).
  void _prefixLines(String prefix, {bool numbered = false}) {
    final value = _controller.value;
    final text = value.text;
    var selection = value.selection;
    if (!selection.isValid) {
      selection = TextSelection.collapsed(offset: text.length);
    }
    final lineStart = selection.start == 0
        ? 0
        : text.lastIndexOf('\n', selection.start - 1) + 1;
    var lineEnd = text.indexOf('\n', selection.end);
    if (lineEnd < 0) lineEnd = text.length;
    final lines = text.substring(lineStart, lineEnd).split('\n');
    final numberPattern = RegExp(r'^\d+\. ');
    bool has(String line) =>
        numbered ? numberPattern.hasMatch(line) : line.startsWith(prefix);
    final remove = lines.every(has);
    final edited = [
      for (var i = 0; i < lines.length; i++)
        remove
            ? lines[i].replaceFirst(
                numbered ? numberPattern : RegExp(RegExp.escape(prefix)),
                '',
              )
            : '${numbered ? '${i + 1}. ' : prefix}${lines[i]}',
    ].join('\n');
    _controller.value = TextEditingValue(
      text: text.substring(0, lineStart) + edited + text.substring(lineEnd),
      selection: TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + edited.length,
      ),
    );
    _focus.requestFocus();
  }

  Widget _button(String tooltip, IconData icon, VoidCallback onPressed) =>
      IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        visualDensity: VisualDensity.compact,
        onPressed: _preview ? null : onPressed,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _button('Bold', Icons.format_bold, () => _wrap('**')),
                    _button('Italic', Icons.format_italic, () => _wrap('*')),
                    _button('Heading', Icons.title, () => _prefixLines('### ')),
                    _button(
                      'Bulleted list',
                      Icons.format_list_bulleted,
                      () => _prefixLines('- '),
                    ),
                    _button(
                      'Numbered list',
                      Icons.format_list_numbered,
                      () => _prefixLines('', numbered: true),
                    ),
                    _button(
                      'Quote',
                      Icons.format_quote,
                      () => _prefixLines('> '),
                    ),
                    _button('Code', Icons.code, () => _wrap('`')),
                    _button('Link', Icons.link, _link),
                  ],
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('markdown-preview-toggle'),
              tooltip: _preview ? 'Edit' : 'Preview',
              isSelected: _preview,
              icon: const Icon(Icons.visibility_outlined, size: 20),
              selectedIcon: const Icon(Icons.edit_outlined, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _preview = !_preview),
            ),
          ],
        ),
        if (_preview)
          InputDecorator(
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: widget.minLines * 20.0,
                maxHeight: widget.maxLines * 24.0,
              ),
              child: SingleChildScrollView(
                child: _controller.text.trim().isEmpty
                    ? Text(
                        'Nothing to preview',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : MarkdownNote(_controller.text),
              ),
            ),
          )
        else
          CallbackShortcuts(
            bindings: {
              const SingleActivator(
                LogicalKeyboardKey.keyB,
                control: true,
              ): () =>
                  _wrap('**'),
              const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
                  _wrap('**'),
              const SingleActivator(
                LogicalKeyboardKey.keyI,
                control: true,
              ): () =>
                  _wrap('*'),
              const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
                  _wrap('*'),
            },
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: 'Markdown: **bold**, *italic*, - list, > quote',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }
}

/// Asks for a Markdown note in a dialog, returning it trimmed, or null
/// when cancelled.
Future<String?> showMarkdownNoteDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String label,
  String confirmLabel = 'Save',
}) => showDialog<String>(
  context: context,
  builder: (_) => _MarkdownNoteDialog(
    title: title,
    initialValue: initialValue,
    label: label,
    confirmLabel: confirmLabel,
  ),
);

class _MarkdownNoteDialog extends StatefulWidget {
  const _MarkdownNoteDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.confirmLabel,
  });

  final String title, initialValue, label, confirmLabel;

  @override
  State<_MarkdownNoteDialog> createState() => _MarkdownNoteDialogState();
}

class _MarkdownNoteDialogState extends State<_MarkdownNoteDialog> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 540,
      child: MarkdownNoteField(
        controller: _controller,
        label: widget.label,
        autofocus: true,
        maxLines: 12,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
