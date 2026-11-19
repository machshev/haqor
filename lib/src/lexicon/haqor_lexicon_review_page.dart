import 'dart:async';

import 'package:flutter/material.dart';

import 'haqor_lexicon_store.dart';
import 'haqor_lexicon_view.dart';
import 'semitic_sounds_page.dart';

/// Review entries in the form the reader sees them. A source checkout allows
/// validated edits and sign-off; the bundled database allows version-bound
/// approval and targeted notes that sync with progress.
class HaqorLexiconReviewPage extends StatefulWidget {
  const HaqorLexiconReviewPage({
    super.key,
    this.store,
    this.onNavigateToPassage,
    this.today,
  });

  final HaqorLexiconStore? store;
  final LexiconNavigate? onNavigateToPassage;

  /// The day a save or sign-off is dated, `YYYY-MM-DD`; today if null.
  final String Function()? today;

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

/// Which entries the review list shows.
enum _ListFilter {
  toReview('To review'),
  signedOff('Signed off'),
  all('All');

  const _ListFilter(this.label);
  final String label;

  bool shows(LexiconEntryDraft entry) => switch (this) {
    toReview => entry.signOff.toReview,
    signedOff => !entry.signOff.toReview,
    all => true,
  };
}

enum _EntryTypeFilter {
  all('All types'),
  root('Roots'),
  name('Names');

  const _EntryTypeFilter(this.label);
  final String label;

  bool shows(LexiconEntryDraft entry) => switch (this) {
    all => true,
    root => !entry.isName,
    name => entry.isName,
  };
}

enum _SortOrder {
  alphabetical('Alphabetical'),
  created('Date created'),
  updated('Last updated');

  const _SortOrder(this.label);
  final String label;
}

class _HaqorLexiconReviewPageState extends State<HaqorLexiconReviewPage> {
  late final HaqorLexiconStore _store = widget.store ?? HaqorLexiconStore();
  LexiconReview? _review;
  Object? _loadError;
  int _selected = 0;
  bool _editing = false;
  bool _saving = false;
  final Set<String> _detailsLoaded = {};
  String? _detailLoading;
  Object? _detailError;
  int _loadVersion = 0;

  String _detailKey(LexiconEntryDraft entry) =>
      '${entry.isName ? 'name' : 'root'}:${entry.id}';

  /// Which entries the list shows: on the first load, those still to review
  /// if there are any.
  _ListFilter? _filter;
  _EntryTypeFilter _entryType = _EntryTypeFilter.all;
  _SortOrder _sortOrder = _SortOrder.alphabetical;
  String _query = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _today() =>
      widget.today?.call() ?? DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _review = null;
      _loadError = null;
      _detailsLoaded.clear();
      _detailLoading = null;
      _detailError = null;
    });
    try {
      final review = await _store.load();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _review = review;
        if (review.entries.isEmpty) return;
        _filter ??= review.entries.any((e) => e.signOff.toReview)
            ? _ListFilter.toReview
            : _ListFilter.all;
        _selected = _selected.clamp(0, review.entries.length - 1);
        if (!_visible(review).any((row) => row.$1 == _selected)) {
          final first = _visible(review).firstOrNull;
          if (first != null) _selected = first.$1;
        }
      });
      unawaited(_loadDetails());
    } catch (error) {
      if (mounted && version == _loadVersion) {
        setState(() => _loadError = error);
      }
    }
  }

  Future<void> _loadDetails() async {
    final entry = _entry;
    if (entry == null) return;
    final key = _detailKey(entry);
    if (_detailsLoaded.contains(key)) return;
    final version = _loadVersion;
    setState(() {
      _detailLoading = key;
      _detailError = null;
    });
    try {
      final detail = await _store.loadEntry(entry);
      if (!mounted || version != _loadVersion) return;
      final entries = _review?.entries;
      if (entries == null) return;
      final index = entries.indexWhere((e) => _detailKey(e) == key);
      if (index < 0 || entries[index].dirty) return;
      setState(() {
        entries[index] = detail;
        _detailsLoaded.add(key);
        if (_detailLoading == key) _detailLoading = null;
      });
    } catch (error) {
      if (mounted && version == _loadVersion && _detailLoading == key) {
        setState(() {
          _detailLoading = null;
          _detailError = error;
        });
      }
    }
  }

  LexiconEntryDraft? get _entry {
    final entries = _review?.entries ?? const [];
    return entries.isEmpty ? null : entries[_selected];
  }

  /// The entries the list shows, with their index among all of them.
  List<(int, LexiconEntryDraft)> _visible(LexiconReview review) {
    final filter = _filter ?? _ListFilter.all;
    final query = _query.trim().toLowerCase();
    final entries = [
      for (final (i, e) in review.entries.indexed)
        if (filter.shows(e) &&
            _entryType.shows(e) &&
            (query.isEmpty || _matches(e, query)))
          (i, e),
    ];
    entries.sort((a, b) {
      if (_sortOrder != _SortOrder.alphabetical) {
        final field = _sortOrder == _SortOrder.created ? 'created' : 'updated';
        final left = a.$2.data[field] as String? ?? '';
        final right = b.$2.data[field] as String? ?? '';
        final dateOrder = right.compareTo(left);
        if (dateOrder != 0) return dateOrder;
      }
      return a.$2.id.toLowerCase().compareTo(b.$2.id.toLowerCase());
    });
    return entries;
  }

  void _keepSelectionVisible() {
    final review = _review;
    if (review == null || _entry?.dirty == true) return;
    final visible = _visible(review);
    if (visible.isEmpty || visible.any((row) => row.$1 == _selected)) return;
    setState(() => _selected = visible.first.$1);
    unawaited(_loadDetails());
  }

  /// How the list names an entry: a name entry by the name, a root's by its
  /// root.
  static String _title(LexiconEntryDraft entry) =>
      (entry.data[entry.isName ? 'name' : 'root'] as String?) ?? entry.id;

  static bool _matches(LexiconEntryDraft entry, String query) {
    final root = (entry.data['root'] as String?) ?? '';
    final gloss = ((entry.data['gloss'] as String?) ?? '').toLowerCase();
    final english = ((entry.data['english'] as String?) ?? '').toLowerCase();
    return entry.id.contains(query) ||
        root.contains(query) ||
        english.contains(query) ||
        gloss.contains(query);
  }

  Future<void> _edit(
    Map<String, dynamic> node,
    String key, {
    required String label,
    bool multiline = false,
  }) async {
    var editedText = node[key] is String ? node[key] as String : '';
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $label'),
        content: SizedBox(
          width: 560,
          child: TextFormField(
            initialValue: editedText,
            onChanged: (value) => editedText = value,
            autofocus: true,
            minLines: multiline ? 4 : 1,
            maxLines: multiline ? 12 : 1,
            style: foreignStyle(editedText, size: 17),
            // Every field edited here is English, even one opening on a
            // Hebrew word.
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onFieldSubmitted: multiline
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
            onPressed: () => Navigator.of(context).pop(editedText),
            child: const Text('Done'),
          ),
        ],
      ),
    );
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

  Future<void> _save() async {
    final entry = _entry;
    if (entry == null) return;
    entry.data['updated'] = _today();
    final message = await _persist(entry);
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Sign the entry off today and save it, with any unsaved edits (which
  /// date it `updated` today too); with [withdraw], put it back to draft.
  /// Nothing changes if the save is refused.
  Future<void> _signOff({bool withdraw = false}) async {
    final entry = _entry;
    if (entry == null) return;
    if (entry.mobileSourceHash.isNotEmpty) {
      if (withdraw) return;
      setState(() => _saving = true);
      try {
        final result = await _store.saveMobileReview(
          entry,
          targetKind: 'entry',
          approved: true,
        );
        if (!mounted) return;
        if (!result.success) throw StateError(result.message);
        setState(() => entry.mobileApprovedOn = _today());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${entry.id}: approval saved for sync')),
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not approve: $error')));
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    final before = Map<String, dynamic>.of(entry.data);
    final wasDirty = entry.dirty;
    final today = _today();
    setState(() {
      if (entry.dirty) entry.data['updated'] = today;
      entry.setSignOff(withdraw ? null : today);
    });
    final saved = await _persist(entry) != null;
    if (!mounted) return;
    if (!saved) {
      setState(() {
        entry.data
          ..clear()
          ..addAll(before);
        entry.dirty = wasDirty;
      });
      return;
    }
    final next = _review!.entries.indexed
        .where((e) => e.$1 != _selected && e.$2.signOff.toReview)
        .firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          withdraw
              ? '${entry.id}: sign-off withdrawn'
              : '${entry.id}: signed off',
        ),
        action: withdraw || next == null
            ? null
            : SnackBarAction(
                label: 'Next: ${next.$2.id}',
                onPressed: () => unawaited(_select(next.$1)),
              ),
      ),
    );
  }

  Future<void> _note(String targetKind, String targetKey) async {
    final entry = _entry;
    if (entry == null || entry.mobileSourceHash.isEmpty) return;
    var noteText = '';
    final label = targetKind == 'entry'
        ? 'whole entry'
        : targetKey.startsWith('/')
        ? 'selected $targetKind'
        : '$targetKind $targetKey';
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review note on $label'),
        content: TextFormField(
          onChanged: (value) => noteText = value,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'What should be checked or changed?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(noteText.trim()),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    if (note == null || note.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await _store.saveMobileReview(
        entry,
        targetKind: targetKind,
        targetKey: targetKey,
        note: note,
      );
      if (!mounted) return;
      if (!result.success) throw StateError(result.message);
      setState(() {
        entry.mobileApprovedOn = null;
        entry.mobileNotes.add({
          'targetKind': targetKind,
          'targetKey': targetKey,
          'note': note,
          'sourceHash': entry.mobileSourceHash,
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review note saved for sync')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save note: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Save [entry]: the core's message if it was saved, or null if not (the
  /// refusal is shown in full).
  Future<String?> _persist(LexiconEntryDraft entry) async {
    setState(() => _saving = true);
    try {
      final status = await _store.save(entry);
      if (!mounted) return status.success ? status.message : null;
      if (status.success) {
        setState(() => entry.dirty = false);
        return status.message;
      }
      setState(() => _saving = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not saved'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(child: SelectableText(status.message)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No reply from the core; not saved.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    return null;
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
    if (mounted) {
      setState(() {
        _selected = index;
        _detailError = null;
      });
      unawaited(_loadDetails());
    }
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
            if ((review?.editable ?? false) &&
                entry != null &&
                _detailsLoaded.contains(_detailKey(entry))) ...[
              _signOffButton(entry),
              const SizedBox(width: 8),
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
                onPressed: entry.dirty && !_saving ? _save : null,
              ),
            ],
            if (entry != null &&
                entry.mobileSourceHash.isNotEmpty &&
                _detailsLoaded.contains(_detailKey(entry))) ...[
              _signOffButton(entry),
              IconButton(
                tooltip: 'Note on whole entry',
                icon: const Icon(Icons.rate_review_outlined),
                onPressed: _saving ? null : () => _note('entry', ''),
              ),
            ],
            IconButton(
              tooltip: 'Semitic sounds',
              icon: const Icon(Icons.record_voice_over_outlined),
              onPressed: () => SemiticSoundsPage.open(
                context,
                onNavigateToPassage: widget.onNavigateToPassage,
              ),
            ),
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

  Widget _signOffButton(LexiconEntryDraft entry) {
    if (entry.mobileSourceHash.isNotEmpty) {
      final hasCurrentNotes = entry.mobileNotes.any(
        (note) => note['sourceHash'] == entry.mobileSourceHash,
      );
      return OutlinedButton.icon(
        key: const ValueKey('lexicon-mobile-approve'),
        icon: Icon(
          entry.mobileApprovedOn == null
              ? Icons.verified_outlined
              : Icons.verified,
        ),
        label: Text(entry.mobileApprovedOn == null ? 'Approve' : 'Approved'),
        onPressed: _saving || entry.mobileApprovedOn != null || hasCurrentNotes
            ? null
            : _signOff,
      );
    }
    if (entry.signOff == LexiconSignOff.signedOff && !entry.dirty) {
      return OutlinedButton.icon(
        key: const ValueKey('lexicon-withdraw-sign-off'),
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Withdraw sign-off'),
        onPressed: _saving ? null : () => _signOff(withdraw: true),
      );
    }
    return FilledButton.icon(
      key: const ValueKey('lexicon-sign-off'),
      icon: const Icon(Icons.verified_outlined, size: 18),
      label: Text(entry.dirty ? 'Save & sign off' : 'Sign off'),
      onPressed: _saving ? null : _signOff,
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
    if (!_detailsLoaded.contains(_detailKey(entry))) {
      if (_detailError != null && _detailLoading == null) {
        return _message(
          'Could not load ${entry.id}: $_detailError',
          retry: true,
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final view = HaqorLexiconEntryView(
      key: ValueKey(_detailKey(entry)),
      entry: entry,
      editing: _editing && review.editable,
      onEdit: _edit,
      onReviewNote: entry.mobileSourceHash.isEmpty ? null : _note,
      showSignOff: true,
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
          child: Column(
            children: [
              if (entry.mobileNotes.isNotEmpty) _mobileNotes(entry),
              Expanded(child: view),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        SizedBox(width: 280, child: _entryList(review)),
        const VerticalDivider(width: 1),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                children: [
                  if (entry.mobileNotes.isNotEmpty) _mobileNotes(entry),
                  Expanded(child: view),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mobileNotes(LexiconEntryDraft entry) => ExpansionTile(
    title: Text('Review notes (${entry.mobileNotes.length})'),
    children: [
      for (final note in entry.mobileNotes)
        ListTile(
          title: Text('${note['targetKind']} ${note['targetKey']}'.trim()),
          subtitle: Text('${note['note']}'),
        ),
    ],
  );

  Widget _entryList(LexiconReview review, {bool closeDrawer = false}) {
    final visible = _visible(review);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            key: const ValueKey('lexicon-review-search'),
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'id, root or gloss',
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('lexicon-review-clear-search'),
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                        _keepSelectionVisible();
                      },
                    ),
            ),
            onChanged: (v) {
              setState(() => _query = v);
              _keepSelectionVisible();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            children: [
              for (final f in _ListFilter.values)
                ChoiceChip(
                  key: ValueKey('lexicon-filter-${f.name}'),
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${f.label} ${review.entries.where(f.shows).length}',
                  ),
                  selected: _filter == f,
                  onSelected: (_) {
                    setState(() => _filter = f);
                    _keepSelectionVisible();
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Column(
            children: [
              DropdownButtonFormField<_EntryTypeFilter>(
                key: const ValueKey('lexicon-entry-type'),
                initialValue: _entryType,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Entry type'),
                items: [
                  for (final type in _EntryTypeFilter.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (type) {
                  if (type != null) {
                    setState(() => _entryType = type);
                    _keepSelectionVisible();
                  }
                },
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<_SortOrder>(
                key: const ValueKey('lexicon-sort-order'),
                initialValue: _sortOrder,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Sort by'),
                items: [
                  for (final order in _SortOrder.values)
                    DropdownMenuItem(value: order, child: Text(order.label)),
                ],
                onChanged: (order) {
                  if (order != null) setState(() => _sortOrder = order);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _filter == _ListFilter.toReview && _query.isEmpty
                          ? 'Every entry is signed off.'
                          : 'No entries match.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final (i, e) in visible)
                      ListTile(
                        key: ValueKey('lexicon-entry-${_detailKey(e)}'),
                        selected: i == _selected,
                        title: Text(
                          _title(e),
                          textDirection: TextDirection.rtl,
                          style: foreignStyle(_title(e), size: 20),
                        ),
                        subtitle: Text(
                          '${e.id}${e.dirty ? ' •' : ''} · '
                          '${(e.data['gloss'] as String?) ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: LexiconSignOffIcon(entry: e),
                        onTap: () async {
                          if (closeDrawer) Navigator.of(context).pop();
                          await _select(i);
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }

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
