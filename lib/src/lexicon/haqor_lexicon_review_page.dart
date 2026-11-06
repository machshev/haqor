import 'dart:async';

import 'package:flutter/material.dart';

import 'haqor_lexicon_store.dart';
import 'haqor_lexicon_view.dart';

/// Review and edit the Haqor lexicon's entries in the form the reader will
/// see them. On desktop, with `HAQOR_LEXICON_DIR` set to haqor-core's
/// `data/lexicon`, entries are read from there and saved back, each save
/// checked against the schema and the text first.
class HaqorLexiconReviewPage extends StatefulWidget {
  const HaqorLexiconReviewPage({
    super.key,
    this.store,
    this.onNavigateToPassage,
  });

  final HaqorLexiconStore? store;
  final LexiconNavigate? onNavigateToPassage;

  static Future<void> open(
    BuildContext context, {
    LexiconNavigate? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          HaqorLexiconReviewPage(onNavigateToPassage: onNavigateToPassage),
    ),
  );

  @override
  State<HaqorLexiconReviewPage> createState() => _HaqorLexiconReviewPageState();
}

class _HaqorLexiconReviewPageState extends State<HaqorLexiconReviewPage> {
  late final HaqorLexiconStore _store = widget.store ?? HaqorLexiconStore();
  LexiconReview? _review;
  Object? _loadError;
  int _selected = 0;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _review = null;
      _loadError = null;
    });
    try {
      final review = await _store.load();
      if (!mounted) return;
      setState(() {
        _review = review;
        _selected = _selected.clamp(
          0,
          review.entries.isEmpty ? 0 : review.entries.length - 1,
        );
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  LexiconEntryDraft? get _entry {
    final entries = _review?.entries ?? const [];
    return entries.isEmpty ? null : entries[_selected];
  }

  Future<void> _edit(
    Map<String, dynamic> node,
    String key, {
    required String label,
    bool multiline = false,
  }) async {
    final controller = TextEditingController(
      text: node[key] is String ? node[key] as String : '',
    );
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $label'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: multiline ? 4 : 1,
            maxLines: multiline ? 12 : 1,
            style: foreignStyle(controller.text, size: 17),
            textDirection: directionOf(controller.text),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: multiline
                ? null
                : (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (edited == null || !mounted) return;
    final text = edited.trim();
    final entry = _entry;
    if (entry == null || text == (node[key] ?? '')) return;
    setState(() {
      if (text.isEmpty && key != 'gloss') {
        node.remove(key);
      } else {
        node[key] = text;
      }
      entry.dirty = true;
    });
  }

  void _toggleStatus() {
    final entry = _entry;
    if (entry == null) return;
    setState(() {
      entry.data['status'] = entry.data['status'] == 'reviewed'
          ? 'draft'
          : 'reviewed';
      entry.dirty = true;
    });
  }

  Future<void> _save() async {
    final entry = _entry;
    if (entry == null) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    entry.data['updated'] = today;
    setState(() => _saving = true);
    try {
      final status = await _store.save(entry);
      if (!mounted) return;
      if (status.success) {
        setState(() => entry.dirty = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(status.message)));
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Not saved'),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: SelectableText(status.message),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No reply from the core; not saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final entry = _entry;
    if (entry == null || !entry.dirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text('"${entry.id}" has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _select(int index) async {
    if (index == _selected) return;
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    final entry = _entry;
    if (entry != null && entry.dirty) {
      await _load();
    }
    if (mounted) setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    final entry = _entry;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return PopScope(
      canPop: !(entry?.dirty ?? false),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          entry?.dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            entry == null
                ? 'Lexicon review'
                : 'Lexicon: ${entry.id}${entry.dirty ? ' •' : ''}',
          ),
          actions: [
            if (review?.editable ?? false) ...[
              Row(
                children: [
                  const Text('Edit'),
                  Switch(
                    value: _editing,
                    onChanged: (v) => setState(() => _editing = v),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Save (checked first)',
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                onPressed: (entry?.dirty ?? false) && !_saving ? _save : null,
              ),
            ],
            IconButton(
              tooltip: 'Reload from disk',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                if (await _confirmDiscard()) await _load();
              },
            ),
          ],
        ),
        drawer: wide || review == null || review.entries.length < 2
            ? null
            : Drawer(child: _entryList(review, closeDrawer: true)),
        body: _body(review, entry, wide),
      ),
    );
  }

  Widget _body(LexiconReview? review, LexiconEntryDraft? entry, bool wide) {
    if (_loadError != null) {
      return _message('Could not load the lexicon: $_loadError', retry: true);
    }
    if (review == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (review.error.isNotEmpty && review.entries.isEmpty) {
      return _message(review.error, retry: true);
    }
    if (entry == null) {
      return _message('No entries in ${review.dir}.', retry: true);
    }
    final view = HaqorLexiconEntryView(
      key: ValueKey(entry.id),
      entry: entry,
      editing: _editing && review.editable,
      onEdit: _edit,
      onToggleStatus: _toggleStatus,
      onNavigateToPassage: widget.onNavigateToPassage == null
          ? null
          : (book, chapter, verse) {
              Navigator.of(context).pop();
              widget.onNavigateToPassage!(book, chapter, verse);
            },
    );
    if (!wide || review.entries.length < 2) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: view,
        ),
      );
    }
    return Row(
      children: [
        SizedBox(width: 240, child: _entryList(review)),
        const VerticalDivider(width: 1),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: view,
            ),
          ),
        ),
      ],
    );
  }

  Widget _entryList(LexiconReview review, {bool closeDrawer = false}) =>
      ListView(
        children: [
          for (final (i, e) in review.entries.indexed)
            ListTile(
              selected: i == _selected,
              title: Text(
                (e.data['root'] as String?) ?? e.id,
                textDirection: TextDirection.rtl,
                style: foreignStyle(
                  (e.data['root'] as String?) ?? '',
                  size: 20,
                ),
              ),
              subtitle: Text(
                '${e.id} · ${(e.data['gloss'] as String?) ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: e.data['status'] == 'reviewed'
                  ? const Icon(Icons.check_circle_outline, size: 18)
                  : null,
              onTap: () async {
                if (closeDrawer) Navigator.of(context).pop();
                await _select(i);
              },
            ),
        ],
      );

  Widget _message(String text, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ],
      ),
    ),
  );
}
