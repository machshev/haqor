import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// Edits a timeline: its title, how it counts time (calendar years BC and
/// AD, years of its own, or another unit) and what it calls them, and its
/// note.
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
  late TimelineScale _scale;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _title = TextEditingController(text: t.title);
    _unit = TextEditingController(text: t.unit);
    _note = TextEditingController(text: t.note);
    _scale = t.scale;
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
    final unit = _unit.text.trim();
    Navigator.pop(
      context,
      widget.initial.copyWith(
        title: title,
        scale: _scale,
        unit: switch (_scale) {
          TimelineScale.calendar => 'Year',
          TimelineScale.years => unit.isEmpty ? 'Year' : unit,
          TimelineScale.units => unit,
        },
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
            DropdownButtonFormField<TimelineScale>(
              key: const ValueKey('timeline-scale'),
              initialValue: _scale,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Counts'),
              items: const [
                DropdownMenuItem(
                  value: TimelineScale.calendar,
                  child: Text('Calendar years (BC / AD)'),
                ),
                DropdownMenuItem(
                  value: TimelineScale.years,
                  child: Text('Years of its own, such as a reign'),
                ),
                DropdownMenuItem(
                  value: TimelineScale.units,
                  child: Text('Another unit, such as days'),
                ),
              ],
              onChanged: (scale) {
                if (scale != null) setState(() => _scale = scale);
              },
            ),
            if (_scale != TimelineScale.calendar) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('timeline-unit'),
                controller: _unit,
                decoration: InputDecoration(
                  labelText: _scale == TimelineScale.years
                      ? 'Years called'
                      : 'Unit',
                  hintText: _scale == TimelineScale.years
                      ? 'Year of David, Year of the exile…'
                      : 'Day, Week, Generation…',
                ),
              ),
            ],
            if (_scale != TimelineScale.units)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Times may name a month and day of the biblical year: '
                  'lunar months from Nisan, of 30 and 29 days by turns.',
                  style: Theme.of(context).textTheme.bodySmall,
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

/// The parts of a time being entered: the year (or count), whether it is
/// BC, and the month and day within the year where the timeline counts
/// years.
class _TimeDraft {
  _TimeDraft(TimelineTime? time, {required bool calendar})
    : number = TextEditingController(
        text: time == null
            ? ''
            : formatTimelineNumber(calendar ? time.value.abs() : time.value),
      ),
      bc = time == null ? calendar : time.value < 0,
      month = time?.month,
      day = time?.day;

  final TextEditingController number;

  /// Counting by era, whether the year is BC; its number is entered
  /// without a sign.
  bool bc;
  int? month, day;

  void dispose() => number.dispose();
}

/// Edits an event or a span: its title, which timeline it is on, its time
/// (a point, or a start and either an end or a duration) on that timeline's
/// scale, how the date is written, the verses it is linked to and its note.
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
  late final TextEditingController _title, _date, _note, _amount;
  late final _TimeDraft _start, _end;
  late bool _span, _byDuration;
  late TimelineDurationUnit _durationUnit;
  late String _timelineId;
  late List<StudyPassage> _verses;
  String? _error;

  StudyTimeline get _timeline =>
      widget.timelines.firstWhere((t) => t.id == _timelineId);

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _timelineId = e.timelineId;
    final calendar = _timeline.isCalendar;
    _title = TextEditingController(text: e.title);
    _span = e.isSpan;
    // A new entry starts empty, BC by default counting by era.
    _start = _TimeDraft(widget.creating ? null : e.start, calendar: calendar);
    _end = _TimeDraft(widget.creating ? null : e.end, calendar: calendar);
    final duration = e.duration;
    _byDuration = duration != null;
    _amount = TextEditingController(
      text: duration == null ? '' : formatTimelineNumber(duration.amount),
    );
    _durationUnit =
        duration?.unit ??
        (_timeline.countsYears
            ? TimelineDurationUnit.years
            : TimelineDurationUnit.units);
    _date = TextEditingController(text: e.date);
    _note = TextEditingController(text: e.note);
    _verses = List.of(e.verses);
  }

  @override
  void dispose() {
    for (final c in [_title, _date, _note, _amount]) {
      c.dispose();
    }
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  /// The time [draft] gives, or null when it gives none; on a calendar
  /// timeline the year is entered without a sign, BC or AD beside it.
  TimelineTime? _read(_TimeDraft draft) {
    final timeline = _timeline;
    final typed = double.tryParse(draft.number.text.trim());
    if (typed == null || !typed.isFinite) return null;
    final value = timeline.isCalendar
        ? (draft.bc ? -typed.abs() : typed.abs())
        : typed;
    final month = timeline.countsYears ? draft.month : null;
    return TimelineTime(
      value,
      month: month,
      day: month == null ? null : draft.day,
    );
  }

  /// Why [time] cannot stand on this timeline, or null when it can.
  String? _timeProblem(TimelineTime time) {
    if (_timeline.isCalendar && time.value == 0) {
      return 'There is no year 0: 1 BC is followed by AD 1.';
    }
    if (time.month != null && time.value != time.value.roundToDouble()) {
      return 'A year with a month must be a whole year.';
    }
    if (!time.isValid) return 'Choose a day within the month.';
    return null;
  }

  /// The units a duration may be given in from the start entered so far.
  List<TimelineDurationUnit> get _durationUnits {
    final start = _read(_start) ?? const TimelineTime(1);
    return _timeline.durationUnitsFor(start);
  }

  TimelineDuration? get _duration {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null) return null;
    final units = _durationUnits;
    return TimelineDuration(
      amount,
      units.contains(_durationUnit) ? _durationUnit : units.first,
    );
  }

  /// The end the duration gives from the start, as entered so far.
  TimelineTime? get _durationEnd {
    final start = _read(_start);
    final duration = _duration;
    if (start == null || duration == null) return null;
    return _timeline.addDuration(start, duration);
  }

  void _save() {
    final title = _title.text.trim();
    final timeline = _timeline;
    final start = _read(_start);
    TimelineTime? end;
    TimelineDuration? duration;
    String? error;
    if (title.isEmpty) {
      error = _span ? 'Give the span a title.' : 'Give the event a title.';
    } else if (start == null) {
      error = _span ? 'Enter when it starts.' : 'Enter when it happens.';
    } else {
      error = _timeProblem(start);
    }
    if (error == null && _span) {
      if (_byDuration) {
        duration = _duration;
        if (duration == null || !duration.isValid) {
          error = timeline.countsYears
              ? 'Enter how long it lasts, in whole years, months or days.'
              : 'Enter how long it lasts.';
        } else {
          end = timeline.addDuration(start!, duration);
          if (end == null) error = 'Enter how long it lasts.';
        }
      } else {
        end = _read(_end);
        if (end == null) {
          error = 'Enter when it ends.';
        } else {
          error = _timeProblem(end);
          if (error == null &&
              timeline.positionOf(end) < timeline.positionOf(start!)) {
            error = 'The end must be at or after the start.';
          }
        }
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      widget.initial
          .withTime(start: start!, end: end, duration: duration)
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

  void _changed() => setState(() => _error = null);

  Widget _time(_TimeDraft draft, {required String label, required String key}) {
    final timeline = _timeline;
    final calendar = timeline.isCalendar;
    final month = draft.month;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('timeline-entry-$key'),
                controller: draft.number,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: calendar ? '$label year' : label,
                  prefixText: calendar || timeline.unit.isEmpty
                      ? null
                      : '${timeline.unit} ',
                ),
                onChanged: (_) => _changed(),
              ),
            ),
            if (calendar) ...[
              const SizedBox(width: 12),
              SegmentedButton<bool>(
                key: ValueKey('timeline-entry-$key-era'),
                segments: const [
                  ButtonSegment(value: true, label: Text('BC')),
                  ButtonSegment(value: false, label: Text('AD')),
                ],
                selected: {draft.bc},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  // A span starting BC most often ends BC too.
                  if (identical(draft, _start) &&
                      _end.number.text.trim().isEmpty) {
                    _end.bc = s.single;
                  }
                  draft.bc = s.single;
                  _error = null;
                }),
              ),
            ],
          ],
        ),
        if (timeline.countsYears) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('timeline-entry-$key-month'),
                  initialValue: month,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Month'),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(
                        value: m,
                        child: Text('$m · ${hebrewMonthNames[m - 1]}'),
                      ),
                  ],
                  onChanged: (m) => setState(() {
                    draft.month = m;
                    if (m == null || (draft.day ?? 0) > lunarMonthDays(m)) {
                      draft.day = null;
                    }
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('timeline-entry-$key-day-$month'),
                  initialValue: draft.day,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    if (month != null)
                      for (var d = 1; d <= lunarMonthDays(month); d++)
                        DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: month == null
                      ? null
                      : (d) => setState(() {
                          draft.day = d;
                          _error = null;
                        }),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _durationFields(ThemeData theme) {
    final timeline = _timeline;
    final units = _durationUnits;
    final unit = units.contains(_durationUnit) ? _durationUnit : units.first;
    final end = _durationEnd;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('timeline-entry-duration'),
                controller: _amount,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: !timeline.countsYears,
                ),
                decoration: InputDecoration(
                  labelText: 'Lasting',
                  suffixText: timeline.countsYears || timeline.unit.isEmpty
                      ? null
                      : timeline.unit,
                ),
                onChanged: (_) => _changed(),
              ),
            ),
            if (timeline.countsYears) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<TimelineDurationUnit>(
                  key: ValueKey('timeline-entry-duration-unit-${units.length}'),
                  initialValue: unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'In'),
                  items: [
                    for (final u in units)
                      DropdownMenuItem(value: u, child: Text(u.name)),
                  ],
                  onChanged: (u) {
                    if (u != null) {
                      setState(() {
                        _durationUnit = u;
                        _error = null;
                      });
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        if (timeline.countsYears && units.length < 3)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              units.length == 1
                  ? 'Give the start a month to count months, and a day to '
                        'count days.'
                  : 'Give the start a day to count days.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (end != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Ends ${timeline.formatTime(end)}',
              key: const ValueKey('timeline-entry-duration-end'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
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
                onChanged: (_) => _changed(),
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
              _time(_start, label: _span ? 'Start' : 'When', key: 'start'),
              if (_span) ...[
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  key: const ValueKey('timeline-entry-span-by'),
                  segments: const [
                    ButtonSegment(value: false, label: Text('End')),
                    ButtonSegment(value: true, label: Text('Duration')),
                  ],
                  selected: {_byDuration},
                  onSelectionChanged: (s) => setState(() {
                    _byDuration = s.single;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 8),
                if (_byDuration)
                  _durationFields(theme)
                else
                  _time(_end, label: 'End', key: 'end'),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('timeline-entry-date'),
                controller: _date,
                decoration: const InputDecoration(
                  labelText: 'Date as written (optional)',
                  hintText: 'c., in the days of…',
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
