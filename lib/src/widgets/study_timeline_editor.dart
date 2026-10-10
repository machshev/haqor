import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// Edits a timeline: its title, the unit its scale counts in, whether it
/// counts years BC and AD, and its note.
class StudyTimelineEditor extends StatefulWidget {
  const StudyTimelineEditor({
    super.key,
    required this.initial,
    required this.creating,
  });

  final StudyTimeline initial;
  final bool creating;

  @override
  State<StudyTimelineEditor> createState() => _StudyTimelineEditorState();
}

class _StudyTimelineEditorState extends State<StudyTimelineEditor> {
  late final TextEditingController _title, _unit, _note;
  late bool _era;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _title = TextEditingController(text: t.title);
    _unit = TextEditingController(text: t.unit);
    _note = TextEditingController(text: t.note);
    _era = t.era;
  }

  @override
  void dispose() {
    _title.dispose();
    _unit.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the timeline a title.');
      return;
    }
    Navigator.pop(
      context,
      widget.initial.copyWith(
        title: title,
        unit: _era ? 'Year' : _unit.text.trim(),
        era: _era,
        note: _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creating ? 'New timeline' : 'Edit timeline'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('timeline-title'),
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Timeline title'),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const ValueKey('timeline-era'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Calendar years (BC / AD)'),
              subtitle: const Text(
                'Otherwise times are numbers counted in a unit of your own, '
                'such as days or years of a reign.',
              ),
              value: _era,
              onChanged: (era) => setState(() => _era = era),
            ),
            if (!_era)
              TextField(
                key: const ValueKey('timeline-unit'),
                controller: _unit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  hintText: 'Day, Year of David, Week…',
                ),
              ),
            const SizedBox(height: 12),
            MarkdownNoteField(controller: _note, label: 'Note', minLines: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
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

/// Edits an event or a span: its title, which timeline it is on, its time
/// (a point, or a start and end) on that timeline's scale, how the date is
/// written, the verses it is linked to and its note.
class StudyTimelineEntryEditor extends StatefulWidget {
  const StudyTimelineEntryEditor({
    super.key,
    required this.initial,
    required this.creating,
    required this.timelines,
    required this.useEnglishBookNames,
    required this.loadChapter,
  });

  final StudyTimelineEntry initial;
  final bool creating;

  /// The timelines it may be on; the initial one must be among them.
  final List<StudyTimeline> timelines;
  final bool useEnglishBookNames;
  final Future<List<VerseEntry>> Function(int book, int chapter) loadChapter;

  @override
  State<StudyTimelineEntryEditor> createState() =>
      _StudyTimelineEntryEditorState();
}

class _StudyTimelineEntryEditorState extends State<StudyTimelineEntryEditor> {
  late final TextEditingController _title, _start, _end, _date, _note;
  late bool _span;
  late String _timelineId;
  late bool _startBc, _endBc;
  late List<StudyPassage> _verses;
  String? _error;

  StudyTimeline get _timeline =>
      widget.timelines.firstWhere((t) => t.id == _timelineId);

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e.title);
    _timelineId = e.timelineId;
    _span = e.isSpan;
    final era = _timeline.era;
    // Counting by era, a time is entered as a year with BC or AD beside it.
    String shown(double? value) =>
        value == null ? '' : formatTimelineNumber(era ? value.abs() : value);
    _start = TextEditingController(
      text: shown(widget.creating ? null : e.start),
    );
    _end = TextEditingController(text: shown(widget.creating ? null : e.end));
    _startBc = e.start < 0 || (widget.creating && era);
    _endBc = (e.end ?? e.start) < 0 || (widget.creating && era);
    _date = TextEditingController(text: e.date);
    _note = TextEditingController(text: e.note);
    _verses = List.of(e.verses);
  }

  @override
  void dispose() {
    for (final c in [_title, _start, _end, _date, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _read(TextEditingController controller, bool bc) {
    final value = double.tryParse(controller.text.trim());
    if (value == null || !value.isFinite) return null;
    if (!_timeline.era) return value;
    return bc ? -value.abs() : value.abs();
  }

  void _save() {
    final title = _title.text.trim();
    final start = _read(_start, _startBc);
    final end = _span ? _read(_end, _endBc) : null;
    final String? error;
    if (title.isEmpty) {
      error = _span ? 'Give the span a title.' : 'Give the event a title.';
    } else if (start == null) {
      error = _span ? 'Enter when it starts.' : 'Enter when it happens.';
    } else if (_span && end == null) {
      error = 'Enter when it ends.';
    } else if (_span && end! < start) {
      error = 'The end must be at or after the start.';
    } else {
      error = null;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      widget.initial
          .withTime(start: start!, end: end)
          .copyWith(
            title: title,
            timelineId: _timelineId,
            date: _date.text.trim(),
            verses: _verses,
            note: _note.text.trim(),
          ),
    );
  }

  Future<void> _addVerses() async {
    final last = _verses.lastOrNull ?? widget.initial.verses.firstOrNull;
    final picked = await showDialog<StudyPassage>(
      context: context,
      builder: (_) => StudyVerseLinkDialog(
        initial: last ?? const StudyPassage(bookIndex: 0, chapter: 1, verse: 1),
        useEnglishBookNames: widget.useEnglishBookNames,
        loadChapter: widget.loadChapter,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!_verses.any((p) => p.locationKey == picked.locationKey)) {
        _verses.add(picked);
      }
    });
  }

  Widget _time({
    required String label,
    required TextEditingController controller,
    required bool bc,
    required ValueChanged<bool> onEra,
    required Key key,
  }) {
    final era = _timeline.era;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: label,
              prefixText: era || _timeline.unit.isEmpty
                  ? null
                  : '${_timeline.unit} ',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        if (era) ...[
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('BC')),
              ButtonSegment(value: false, label: Text('AD')),
            ],
            selected: {bc},
            showSelectedIcon: false,
            onSelectionChanged: (s) => onEra(s.single),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noun = _span ? 'span' : 'event';
    return AlertDialog(
      title: Text(widget.creating ? 'New timeline $noun' : 'Edit $noun'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                key: const ValueKey('timeline-entry-kind'),
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.radio_button_checked),
                    label: Text('Event'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.linear_scale),
                    label: Text('Span'),
                  ),
                ],
                selected: {_span},
                onSelectionChanged: (s) => setState(() {
                  _span = s.single;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('timeline-entry-title'),
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: _span ? 'Span title' : 'Event title',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (widget.timelines.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('timeline-entry-timeline'),
                  initialValue: _timelineId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Timeline'),
                  items: [
                    for (final t in widget.timelines)
                      DropdownMenuItem(
                        value: t.id,
                        child: Text(t.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) setState(() => _timelineId = id);
                  },
                ),
              ],
              const SizedBox(height: 12),
              _time(
                key: const ValueKey('timeline-entry-start'),
                label: _span ? 'Start' : 'When',
                controller: _start,
                bc: _startBc,
                onEra: (bc) => setState(() {
                  // A span starting BC most often ends BC too.
                  if (_end.text.trim().isEmpty) _endBc = bc;
                  _startBc = bc;
                }),
              ),
              if (_span) ...[
                const SizedBox(height: 12),
                _time(
                  key: const ValueKey('timeline-entry-end'),
                  label: 'End',
                  controller: _end,
                  bc: _endBc,
                  onEra: (bc) => setState(() => _endBc = bc),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('timeline-entry-date'),
                controller: _date,
                decoration: const InputDecoration(
                  labelText: 'Date as written (optional)',
                  hintText: 'c., Nisan 14, the seventh month…',
                ),
              ),
              const SizedBox(height: 16),
              Text('Linked verses', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final passage in _verses)
                    InputChip(
                      label: Text(
                        '${bookDisplayName(passage.bookIndex, useEnglish: widget.useEnglishBookNames)} '
                        '${passage.reference}',
                      ),
                      onDeleted: () => setState(() => _verses.remove(passage)),
                    ),
                  TextButton.icon(
                    key: const ValueKey('timeline-entry-add-verses'),
                    onPressed: _addVerses,
                    icon: const Icon(Icons.add_link),
                    label: const Text('Link verses'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MarkdownNoteField(controller: _note, label: 'Note', minLines: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
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
}

/// Chooses a verse, or a run of verses within one chapter, to link to.
class StudyVerseLinkDialog extends StatefulWidget {
  const StudyVerseLinkDialog({
    super.key,
    required this.initial,
    required this.useEnglishBookNames,
    required this.loadChapter,
  });

  final StudyPassage initial;
  final bool useEnglishBookNames;
  final Future<List<VerseEntry>> Function(int book, int chapter) loadChapter;

  @override
  State<StudyVerseLinkDialog> createState() => _StudyVerseLinkDialogState();
}

class _StudyVerseLinkDialogState extends State<StudyVerseLinkDialog> {
  late int _book, _chapter, _verse, _endVerse;
  List<int> _verses = const [];
  bool _loading = true;
  String? _loadError;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _book = p.bookIndex;
    _chapter = p.chapter;
    _verse = p.verse;
    _endVerse = p.lastChapter == p.chapter ? p.lastVerse : p.verse;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final verses = await widget.loadChapter(_book, _chapter);
      if (!mounted || generation != _generation) return;
      if (verses.isEmpty) throw StateError('Empty chapter');
      setState(() {
        _verses = [for (final v in verses) v.verse];
        if (!_verses.contains(_verse)) _verse = _verses.first;
        if (!_verses.contains(_endVerse) || _endVerse < _verse) {
          _endVerse = _verse;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load the chapter. Please retry.';
      });
    }
  }

  Widget _choice(
    String label,
    int value,
    List<int> values,
    ValueChanged<int> changed, {
    String Function(int)? name,
  }) => DropdownButtonFormField<int>(
    key: ValueKey('$label-$value-${values.length}'),
    initialValue: values.contains(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final n in values)
        DropdownMenuItem(
          value: n,
          child: Text(name?.call(n) ?? '$n', overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) {
      if (v != null) changed(v);
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Link verses'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _choice(
            'Book',
            _book,
            [for (var b = 0; b < kBooks.length; b++) b],
            (b) {
              setState(() {
                _book = b;
                _chapter = _verse = _endVerse = 1;
              });
              _load();
            },
            name: (b) =>
                bookDisplayName(b, useEnglish: widget.useEnglishBookNames),
          ),
          const SizedBox(height: 12),
          _choice(
            'Chapter',
            _chapter,
            [for (var c = 1; c <= kBooks[_book].chapters; c++) c],
            (c) {
              setState(() {
                _chapter = c;
                _verse = _endVerse = 1;
              });
              _load();
            },
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LinearProgressIndicator()
          else if (_loadError != null) ...[
            Text(_loadError!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ] else
            Row(
              children: [
                Expanded(
                  child: _choice(
                    'From verse',
                    _verse,
                    _verses,
                    (v) => setState(() {
                      _verse = v;
                      if (_endVerse < v) _endVerse = v;
                    }),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _choice('To verse', _endVerse, [
                    for (final v in _verses)
                      if (v >= _verse) v,
                  ], (v) => setState(() => _endVerse = v)),
                ),
              ],
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading || _loadError != null
            ? null
            : () => Navigator.pop(
                context,
                StudyPassage(
                  bookIndex: _book,
                  chapter: _chapter,
                  verse: _verse,
                  endVerse: _endVerse == _verse ? null : _endVerse,
                ),
              ),
        child: const Text('Link'),
      ),
    ],
  );
}
