import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'bible_timeline_page.dart';
import 'markdown_note.dart';
import 'timeline_chart.dart';

/// Edits a timeline: its title, how it counts time (calendar years BC and
/// AD, years of its own, or another unit) and what it calls them, which of
/// [bases] it is built on, the year one year's calendar is set in, and its
/// note. One linked to a standard timeline keeps its scale.
class StudyTimelineEditor extends StatefulWidget {
  const StudyTimelineEditor({
    super.key,
    required this.initial,
    required this.creating,
    this.bases = const [],
  });

  final StudyTimeline initial;
  final bool creating;

  /// The study's timelines it may be built on, those of its scale offered.
  final List<StudyTimeline> bases;

  @override
  State<StudyTimelineEditor> createState() => _StudyTimelineEditorState();
}

class _StudyTimelineEditorState extends State<StudyTimelineEditor> {
  late final TextEditingController _title, _unit, _note, _leapYears, _year;
  late String? _baseId = widget.initial.baseId;
  late TimelineScale _scale;
  late TimelineLeapMonths _leap;
  late TimelineMonthNaming _naming;
  String? _error;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _title = TextEditingController(text: t.title);
    _unit = TextEditingController(text: t.unit);
    _note = TextEditingController(text: t.note);
    _year = TextEditingController(
      text: t.year == null ? '' : formatEraYear(t.year!),
    );
    _scale = t.scale;
    _leap = t.leapMonths;
    _naming = t.monthNaming;
    _leapYears = TextEditingController(
      text: (t.leapYears.toList()..sort())
          .map(
            (y) => t.isCalendar
                ? t.formatValue(y.toDouble())
                : formatTimelineNumber(y.toDouble()),
          )
          .join(', '),
    );
  }

  @override
  void dispose() {
    for (final c in [_title, _unit, _note, _leapYears, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The leap-month choices the scale allows: the cycle only for calendar
  /// years; one year's calendar has its second Adar or not.
  List<TimelineLeapMonths> get _leapChoices => switch (_scale) {
    TimelineScale.calendar => TimelineLeapMonths.values,
    TimelineScale.years => const [
      TimelineLeapMonths.none,
      TimelineLeapMonths.chosen,
    ],
    TimelineScale.units || TimelineScale.annual => const [],
  };

  TimelineLeapMonths get _leapShown =>
      _leapChoices.contains(_leap) ? _leap : TimelineLeapMonths.none;

  /// The chosen leap years as written in the field, or null (with [_error]
  /// set) when one cannot be read. Calendar years need BC or AD.
  Set<int>? _parseLeapYears() {
    final years = <int>{};
    final pattern = RegExp(
      r'^(?:(AD|CE)\s*)?(-?\d+)\s*(BC|BCE|AD|CE)?$',
      caseSensitive: false,
    );
    for (final raw in _leapYears.text.split(RegExp(r'[,;\n]'))) {
      final token = raw.trim();
      if (token.isEmpty) continue;
      final match = pattern.firstMatch(token);
      final number = match == null ? null : int.tryParse(match.group(2)!);
      if (number == null) {
        _error = 'Could not read "$token" as a year.';
        return null;
      }
      if (_scale != TimelineScale.calendar) {
        years.add(number);
        continue;
      }
      final era = (match!.group(3) ?? match.group(1))?.toUpperCase();
      if (number == 0) {
        _error = 'There is no year 0: 1 BC is followed by AD 1.';
        return null;
      }
      if (era == null && number > 0) {
        _error = 'Write each year with BC or AD, as 1446 BC.';
        return null;
      }
      final bc = era == 'BC' || era == 'BCE' || number < 0;
      years.add(bc ? -number.abs() : number.abs());
    }
    return years;
  }

  /// The timelines it may be built on: those of its scale, but itself.
  List<StudyTimeline> get _bases => [
    for (final t in widget.bases)
      if (t.scale == _scale && t.id != widget.initial.id) t,
  ];

  /// The year one year's calendar is set in, as entered: null for none, or
  /// with [_error] set where it cannot be read.
  ({double? year, bool ok}) _readYear() {
    final text = _year.text.trim();
    if (_scale != TimelineScale.annual || text.isEmpty) {
      return (year: null, ok: true);
    }
    final match = RegExp(
      r'^(?:(AD|CE)\s*)?(\d+)\s*(BC|BCE|AD|CE)?$',
      caseSensitive: false,
    ).firstMatch(text);
    final number = match == null ? null : int.tryParse(match.group(2)!);
    final era = (match?.group(3) ?? match?.group(1))?.toUpperCase();
    if (number == null || number == 0 || era == null) {
      _error = 'Write the year with BC or AD, as AD 30.';
      return (year: null, ok: false);
    }
    final bc = era == 'BC' || era == 'BCE';
    return (year: (bc ? -number : number).toDouble(), ok: true);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give the timeline a title.');
      return;
    }
    final year = _readYear();
    if (!year.ok) {
      setState(() {});
      return;
    }
    final baseId = _bases.any((t) => t.id == _baseId) ? _baseId : null;
    final leap = _scale == TimelineScale.annual
        ? (_leap == TimelineLeapMonths.none
              ? TimelineLeapMonths.none
              : TimelineLeapMonths.chosen)
        : _leapShown;
    var leapYears = widget.initial.leapYears;
    if (leap == TimelineLeapMonths.chosen && _scale != TimelineScale.annual) {
      final parsed = _parseLeapYears();
      if (parsed == null) {
        setState(() {});
        return;
      }
      leapYears = parsed;
    }
    final unit = _unit.text.trim();
    Navigator.pop(
      context,
      widget.initial.copyWith(
        title: title,
        scale: _scale,
        unit: switch (_scale) {
          TimelineScale.calendar || TimelineScale.annual => 'Year',
          TimelineScale.years => unit.isEmpty ? 'Year' : unit,
          TimelineScale.units => unit,
        },
        leapMonths: leap,
        monthNaming: _naming,
        leapYears: leapYears,
        note: _note.text.trim(),
        baseId: () => baseId,
        year: () => year.year,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final hasMonths = _scale != TimelineScale.units;
    return AlertDialog(
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
                decoration: InputDecoration(
                  labelText: 'Counts',
                  helperText: widget.initial.isStandard
                      ? 'Linked to a timeline that comes with the app: its '
                            'entries come from there. Build a timeline on it '
                            'to add your own.'
                      : null,
                  helperMaxLines: 3,
                ),
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
                    value: TimelineScale.annual,
                    child: Text("A year's calendar, such as the feasts"),
                  ),
                  DropdownMenuItem(
                    value: TimelineScale.units,
                    child: Text('Another unit, such as days'),
                  ),
                ],
                onChanged: widget.initial.isStandard
                    ? null
                    : (scale) {
                        if (scale != null) {
                          setState(() {
                            _scale = scale;
                            _error = null;
                          });
                        }
                      },
              ),
              if (_bases.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey('timeline-base-${_scale.name}'),
                  initialValue: _bases.any((t) => t.id == _baseId)
                      ? _baseId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Built on',
                    helperText:
                        'Its entries show beneath this one\'s, which may be '
                        'pinned to them.',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Nothing: it stands alone'),
                    ),
                    for (final t in _bases)
                      DropdownMenuItem(
                        value: t.id,
                        child: Text(t.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) => setState(() => _baseId = id),
                ),
              ],
              if (_scale == TimelineScale.annual) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('timeline-year'),
                  controller: _year,
                  decoration: const InputDecoration(
                    labelText: 'Set in the year (optional)',
                    hintText: 'AD 30',
                    helperText:
                        'Which year its weeks are those of; set the day of '
                        'the week its year begins on in its calendar.',
                    helperMaxLines: 2,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
              if (_scale == TimelineScale.years ||
                  _scale == TimelineScale.units) ...[
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
              if (hasMonths)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _scale == TimelineScale.annual
                        ? 'Times are a month and day of the biblical year, '
                              'without a year: lunar months from the first '
                              '(Nisan, Abib), of 30 and 29 days by turns.'
                        : 'Times may name a month and day of the biblical '
                              'year: lunar months from the first (Nisan, '
                              'Abib), of 30 and 29 days by turns.',
                    style: small,
                  ),
                ),
              if (hasMonths) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<TimelineMonthNaming>(
                  key: const ValueKey('timeline-month-names'),
                  initialValue: _naming,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Month names'),
                  items: const [
                    DropdownMenuItem(
                      value: TimelineMonthNaming.postExile,
                      child: Text('After the exile: Nisan, Iyyar, Sivan…'),
                    ),
                    DropdownMenuItem(
                      value: TimelineMonthNaming.preExile,
                      child: Text('Before the exile: Abib, Ziv, 3rd month…'),
                    ),
                    DropdownMenuItem(
                      value: TimelineMonthNaming.numbered,
                      child: Text('Numbered: 1st month, 2nd month…'),
                    ),
                  ],
                  onChanged: (naming) {
                    if (naming != null) setState(() => _naming = naming);
                  },
                ),
                if (_naming == TimelineMonthNaming.preExile)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Scripture names four months before the exile: Abib '
                      '(1st), Ziv (2nd), Ethanim (7th) and Bul (8th). The '
                      'others go by number.',
                      style: small,
                    ),
                  ),
              ],
              if (_scale == TimelineScale.annual)
                SwitchListTile(
                  key: const ValueKey('timeline-leap-annual'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('With a second Adar'),
                  subtitle: const Text(
                    'A 12th month (Adar I) of 30 days, then a 13th (Adar '
                    'II) of 29: a year of 384 '
                    'days.',
                  ),
                  value: _leap != TimelineLeapMonths.none,
                  onChanged: (on) => setState(
                    () => _leap = on
                        ? TimelineLeapMonths.chosen
                        : TimelineLeapMonths.none,
                  ),
                ),
              if (_leapChoices.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<TimelineLeapMonths>(
                  key: ValueKey('timeline-leap-${_scale.name}'),
                  initialValue: _leapShown,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Second Adar'),
                  items: [
                    for (final choice in _leapChoices)
                      DropdownMenuItem(
                        value: choice,
                        child: Text(switch (choice) {
                          TimelineLeapMonths.none => 'Never',
                          TimelineLeapMonths.chosen => 'In chosen years',
                          TimelineLeapMonths.cycle => 'Fixed 19-year cycle',
                        }),
                      ),
                  ],
                  onChanged: (leap) {
                    if (leap != null) {
                      setState(() {
                        _leap = leap;
                        _error = null;
                      });
                    }
                  },
                ),
                if (_leapShown == TimelineLeapMonths.chosen)
                  TextField(
                    key: const ValueKey('timeline-leap-years'),
                    controller: _leapYears,
                    decoration: InputDecoration(
                      labelText: 'Years with a second Adar',
                      hintText: _scale == TimelineScale.calendar
                          ? '1446 BC, 1443 BC'
                          : '3, 6, 8',
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                if (_leapShown == TimelineLeapMonths.cycle)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'The 3rd, 6th, 8th, 11th, 14th, 17th and 19th years of '
                      'each 19 have Adar I and Adar II, as in the fixed '
                      'Hebrew calendar, counted in years of the world '
                      '(anno mundi).',
                      style: small,
                    ),
                  ),
                if (_leapShown != TimelineLeapMonths.none)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "A leap year's 12th month (Adar I) has 30 days, and a "
                      '13th (Adar II) follows with 29.',
                      style: small,
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              MarkdownNoteField(controller: _note, label: 'Note', minLines: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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

/// The parts of a time being entered: the year (or count), whether it is
/// BC, and the month and day within the year where the timeline counts
/// years.
/// The fields for the days leading up to a span or trailing after it, keeping
/// the verses it had.
class _TaperDraft {
  _TaperDraft(TimelineTaper? taper)
    : verses = taper?.verses ?? const [],
      days = TextEditingController(text: taper == null ? '' : '${taper.days}'),
      title = TextEditingController(text: taper?.title ?? ''),
      note = TextEditingController(text: taper?.note ?? '');

  final List<StudyPassage> verses;
  final TextEditingController days, title, note;

  /// What is entered: null where the days are not a whole number,
  /// else none ([taper] null) for no days.
  ({TimelineTaper? taper})? read() {
    final text = days.text.trim();
    if (text.isEmpty || text == '0') return (taper: null);
    final count = int.tryParse(text);
    if (count == null || count < 1) return null;
    return (
      taper: TimelineTaper(
        days: count,
        title: title.text.trim(),
        note: note.text.trim(),
        verses: verses,
      ),
    );
  }

  void dispose() {
    days.dispose();
    title.dispose();
    note.dispose();
  }
}

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
/// It may instead be pinned to another of [entries], a day (or other
/// offset) from it, so that it moves with it.
class StudyTimelineEntryEditor extends StatefulWidget {
  const StudyTimelineEntryEditor({
    super.key,
    required this.initial,
    required this.creating,
    required this.timelines,
    required this.useEnglishBookNames,
    required this.loadChapter,
    this.entries = const [],
    this.loadBibleEntries,
    this.anchorsFor,
  });

  final StudyTimelineEntry initial;

  /// The entries already on the timelines, which it may be pinned to.
  final List<StudyTimelineEntry> entries;

  /// Loads the Bible timeline's events, to link to; without it, only the
  /// study's entries may be linked to.
  final Future<List<StudyTimelineEntry>> Function()? loadBibleEntries;

  /// The entries one on the timeline [timelineId] may be pinned to: its
  /// own and those of the timelines it is built on, as it places them;
  /// without it, those of [entries] on that timeline.
  final List<StudyTimelineEntry> Function(String timelineId)? anchorsFor;
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
  late final TextEditingController _title, _date, _note, _amount, _offset;
  late final TextEditingController _category;
  late final _TimeDraft _start, _end;

  /// The days leading up to the span and trailing after it.
  late final _TaperDraft _lead, _trail;
  late bool _span, _byDuration, _sabbath, _counted;

  /// The part of its day an event falls in; null for the whole day.
  TimelineDayPart? _part;
  late TimelineDurationUnit _durationUnit;
  late String _timelineId;
  late List<StudyPassage> _verses;
  late List<TimelineLink> _links;
  String? _error;

  /// The entry it is pinned to, the unit its offset is in, and the day of
  /// the week it is moved on to, if any.
  String? _anchorId;
  TimelineDurationUnit? _offsetUnit;
  int? _weekday;

  StudyTimeline get _timeline =>
      widget.timelines.firstWhere((t) => t.id == _timelineId);

  /// The entries on the chosen timeline it may be pinned to: any but
  /// itself and those pinned, however far down a chain, to it.
  List<StudyTimelineEntry> get _anchors {
    final candidates =
        widget.anchorsFor?.call(_timelineId) ??
        [
          for (final e in widget.entries)
            if (e.timelineId == _timelineId) e,
        ];
    final byId = {
      for (final e in [...widget.entries, ...candidates]) e.id: e,
    };
    bool pinnedToSelf(StudyTimelineEntry entry) {
      final seen = <String>{};
      for (var e = entry; e.pin != null && seen.add(e.id);) {
        if (e.pin!.anchorId == widget.initial.id) return true;
        final next = byId[e.pin!.anchorId];
        if (next == null) return false;
        e = next;
      }
      return false;
    }

    return [
      for (final e in candidates)
        if (e.id != widget.initial.id && !pinnedToSelf(e)) e,
    ]..sort(compareTimelineEntries);
  }

  /// The entry it is pinned to, where that is on its timeline.
  StudyTimelineEntry? get _anchor =>
      _anchors.where((s) => s.id == _anchorId).firstOrNull;

  /// The units an offset from [anchor] may be in: days where it starts on
  /// a day, else whatever its start allows.
  List<TimelineDurationUnit> _offsetUnits(StudyTimelineEntry anchor) {
    final units = _timeline.durationUnitsFor(anchor.start);
    return units.contains(TimelineDurationUnit.days)
        ? [
            TimelineDurationUnit.days,
            ...units.where((u) => u != TimelineDurationUnit.days),
          ]
        : units;
  }

  TimelineDurationUnit? _offsetUnitFor(StudyTimelineEntry anchor) {
    final units = _offsetUnits(anchor);
    return units.contains(_offsetUnit) ? _offsetUnit : units.firstOrNull;
  }

  /// The pin entered so far.
  TimelinePin? get _pin {
    final anchor = _anchor;
    final amount = double.tryParse(_offset.text.trim());
    if (anchor == null || amount == null) return null;
    final unit = _offsetUnitFor(anchor);
    if (unit == null) return null;
    return TimelinePin(
      anchor.id,
      TimelineDuration(amount, unit),
      weekday: unit == TimelineDurationUnit.days ? _weekday : null,
    );
  }

  /// Pins it to the entry [id], or none, its day counted from the time
  /// entered so far.
  void _pinTo(String? id) => setState(() {
    _anchorId = id;
    _error = null;
    final anchor = _anchor;
    if (anchor == null) return;
    final first = _timeline.firstPinTo(anchor);
    final at = _read(_start);
    final days = at == null ? null : _timeline.daysBetween(anchor.start, at);
    _offsetUnit = first?.offset.unit;
    _offset.text = days != null && first?.isDays == true
        ? '${days + 1}'
        : first == null
        ? ''
        : formatTimelineNumber(first.offset.amount);
  });

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _timelineId = e.timelineId;
    final calendar = _timeline.isCalendar;
    _title = TextEditingController(text: e.title);
    _span = e.isSpan;
    _sabbath = e.sabbath;
    _counted = e.counted;
    _part = e.part;
    // A new entry starts empty, BC by default counting by era.
    // A day already chosen (from the calendar) is kept.
    _start = _TimeDraft(
      widget.creating && e.start.month == null ? null : e.start,
      calendar: calendar,
    );
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
            : _timeline.isAnnual
            ? TimelineDurationUnit.days
            : TimelineDurationUnit.units);
    _date = TextEditingController(text: e.date);
    _category = TextEditingController(text: e.category);
    _note = TextEditingController(text: e.note);
    _verses = List.of(e.verses);
    _links = List.of(e.links);
    _lead = _TaperDraft(e.lead);
    _trail = _TaperDraft(e.trail);
    _anchorId = e.pin?.anchorId;
    _offsetUnit = e.pin?.offset.unit;
    _weekday = e.pin?.weekday;
    _offset = TextEditingController(
      text: e.pin == null ? '' : formatTimelineNumber(e.pin!.offset.amount),
    );
  }

  @override
  void dispose() {
    for (final c in [_title, _date, _note, _amount, _offset, _category]) {
      c.dispose();
    }
    _lead.dispose();
    _trail.dispose();
    _start.dispose();
    for (final c in _dayNotes.values) {
      c.dispose();
    }
    _end.dispose();
    super.dispose();
  }

  /// The year [draft] gives, as written (BC negative); 0 on one year's
  /// calendar, which has none; null when none is entered.
  double? _yearOf(_TimeDraft draft) {
    final timeline = _timeline;
    if (timeline.isAnnual) return 0;
    final typed = double.tryParse(draft.number.text.trim());
    if (typed == null || !typed.isFinite) return null;
    return timeline.isCalendar
        ? (draft.bc ? -typed.abs() : typed.abs())
        : typed;
  }

  /// The time [draft] gives, or null when it gives none; on a calendar
  /// timeline the year is entered without a sign, BC or AD beside it, and
  /// on one year's calendar the month is needed instead of a year.
  TimelineTime? _read(_TimeDraft draft) {
    final timeline = _timeline;
    final value = _yearOf(draft);
    final month = timeline.hasMonths ? draft.month : null;
    if (value == null || (timeline.isAnnual && month == null)) return null;
    return TimelineTime(
      value,
      month: month,
      day: month == null ? null : draft.day,
    );
  }

  /// Why [time] cannot stand on this timeline, or null when it can.
  String? _timeProblem(TimelineTime time) {
    final timeline = _timeline;
    if (timeline.isCalendar && time.value == 0) {
      return 'There is no year 0: 1 BC is followed by AD 1.';
    }
    if (time.month != null && time.value != time.value.roundToDouble()) {
      return 'A year with a month must be a whole year.';
    }
    final month = time.month;
    if (month != null && month > timeline.monthsIn(time.value)) {
      return timeline.isAnnual
          ? 'This calendar has no Adar II.'
          : 'That year has no Adar II.';
    }
    if (!timeline.fits(time)) return 'Choose a day within the month.';
    return null;
  }

  /// The units a duration may be given in from the start entered so far.
  List<TimelineDurationUnit> get _durationUnits {
    final timeline = _timeline;
    final start =
        _read(_start) ??
        TimelineTime(
          1,
          month: timeline.hasMonths ? _start.month : null,
          day: timeline.hasMonths && _start.month != null ? _start.day : null,
        );
    return timeline.durationUnitsFor(start);
  }

  TimelineDuration? get _duration {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null) return null;
    final units = _durationUnits;
    if (units.isEmpty) return null;
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
    final anchor = _anchor;
    final pin = anchor == null ? null : _pin;
    final start = anchor == null
        ? _read(_start)
        : pin == null || !pin.isValid
        ? null
        : timeline.placePin(anchor, pin);
    TimelineTime? end;
    TimelineDuration? duration;
    String? error;
    if (title.isEmpty) {
      error = _span ? 'Give the span a title.' : 'Give the event a title.';
    } else if (anchor != null && start == null) {
      error = _offsetUnitFor(anchor) != TimelineDurationUnit.days
          ? 'Enter how long after ${anchor.title} it falls, in whole '
                'numbers.'
          : timeline.isAnnual
          ? 'Enter a day, counting from ${anchor.title}, within the year.'
          : 'Enter a day, counting from ${anchor.title}.';
    } else if (start == null) {
      error = _span ? 'Enter when it starts.' : 'Enter when it happens.';
    } else {
      error = _timeProblem(start);
    }
    final sabbath = _sabbath && !_span && timeline.hasMonths;
    if (error == null && sabbath && start!.day == null) {
      error = 'A shabbaton needs its month and day.';
    }
    if (error == null && _span) {
      if (_byDuration) {
        duration = _duration;
        if (duration == null || !duration.isValid) {
          error = timeline.countsYears
              ? 'Enter how long it lasts, in whole years, months or days.'
              : timeline.isAnnual
              ? 'Enter how long it lasts, in whole months or days.'
              : 'Enter how long it lasts.';
        } else {
          end = timeline.addDuration(start!, duration);
          if (end == null) {
            error = timeline.isAnnual
                ? "A span on a year's calendar must end within the year."
                : 'Enter how long it lasts.';
          }
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
    final tapers = _span && start?.day != null;
    final lead = tapers ? _lead.read() : null;
    final trail = tapers ? _trail.read() : null;
    if (error == null && tapers) {
      if (lead == null) {
        error = 'Enter the days before it as a whole number.';
      } else if (trail == null) {
        error = 'Enter the days after it as a whole number.';
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
            sabbath: sabbath,
            counted: _span && _counted && timeline.hasMonths,
            part: () => _span || start.day == null ? null : _part,
            category: _category.text.trim(),
            links: _links,
            dayNotes: _span
                ? _dayNotesFor(_spanDays(start, end) ?? 0)
                : const {},
            lead: () => lead?.taper,
            trail: () => trail?.taper,
          )
          .pinnedTo(pin),
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

  /// A link as it reads: the entry's title and its timeline's.
  String _linkLabel(TimelineLink link) {
    final entry = widget.entries.where((e) => link.leadsTo(e)).firstOrNull;
    final timeline = link.timelineId == bibleTimelineId
        ? bibleTimeline
        : widget.timelines.where((t) => t.id == link.timelineId).firstOrNull;
    final title = entry?.title ?? link.title;
    return timeline == null ? title : '$title · ${timeline.title}';
  }

  /// Links it to an entry picked on a study's timeline or the Bible's.
  Future<void> _addLink() async {
    final picked = await showDialog<TimelineLink>(
      context: context,
      builder: (_) => StudyTimelineLinkDialog(
        timelines: widget.timelines,
        entries: widget.entries,
        exceptId: widget.initial.id,
        initialTimelineId: _timelineId,
        loadBibleEntries: widget.loadBibleEntries,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!_links.contains(picked)) _links.add(picked);
    });
  }

  /// The notes for a span's days, by day, as entered so far.
  final _dayNotes = <int, TextEditingController>{};

  TextEditingController _dayNote(int day) => _dayNotes.putIfAbsent(
    day,
    () => TextEditingController(text: widget.initial.dayNotes[day] ?? ''),
  );

  /// The notes entered for the first [days] days.
  Map<int, String> _dayNotesFor(int days) => {
    for (var day = 1; day <= days; day++)
      if (_dayNote(day).text.trim() case final note when note.isNotEmpty)
        day: note,
  };

  /// The days a span from [start] to [end] runs, where both are days and
  /// it runs no more than a season: those its notes may be given for.
  int? _spanDays(TimelineTime? start, TimelineTime? end) {
    if (start == null || end == null) return null;
    final days = _timeline.daysBetween(start, end);
    return days == null || days < 0 || days >= 120 ? null : days + 1;
  }

  /// The span's start and end as entered so far: its start where it is
  /// pinned, and its end from its duration or as entered.
  ({TimelineTime? start, TimelineTime? end}) get _draftSpan {
    final anchor = _anchor;
    final pin = anchor == null ? null : _pin;
    final start = anchor == null
        ? _read(_start)
        : pin == null || !pin.isValid
        ? null
        : _timeline.placePin(anchor, pin);
    final duration = _duration;
    final end = !_byDuration
        ? _read(_end)
        : start == null || duration == null
        ? null
        : _timeline.addDuration(start, duration);
    return (start: start, end: end);
  }

  /// A field for the note on each of the span's days, folded away.
  Widget _dayNoteFields(ThemeData theme) {
    final span = _draftSpan;
    final days = _spanDays(span.start, span.end);
    if (days == null) return const SizedBox.shrink();
    return ExpansionTile(
      key: const ValueKey('timeline-entry-day-notes'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      initiallyExpanded: widget.initial.dayNotes.isNotEmpty,
      leading: const Icon(Icons.view_day_outlined),
      title: const Text('Notes for each day'),
      subtitle: const Text(
        'What each day holds, as the offerings of each day of Chag haSukkot '
        '(Numbers 29); a note starting with a number is drawn to scale.',
      ),
      children: [
        for (var day = 1; day <= days; day++)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextField(
              key: ValueKey('timeline-entry-day-note-$day'),
              controller: _dayNote(day),
              decoration: InputDecoration(
                isDense: true,
                labelText: [
                  'Day $day',
                  if (_timeline.addDays(span.start!, day - 1) case final date?)
                    _timeline.formatTime(date),
                ].join(' · '),
              ),
            ),
          ),
      ],
    );
  }

  /// The days leading up to the span and trailing after it, folded away.
  Widget _taperFields() {
    Widget side(_TaperDraft draft, String which, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                key: ValueKey('timeline-entry-$which-days'),
                controller: draft.days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: '$label (days)',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: ValueKey('timeline-entry-$which-title'),
                controller: draft.title,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'What they are',
                ),
              ),
            ),
          ],
        ),
        TextField(
          key: ValueKey('timeline-entry-$which-note'),
          controller: draft.note,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(isDense: true, labelText: 'Note'),
        ),
        const SizedBox(height: 8),
      ],
    );
    return ExpansionTile(
      key: const ValueKey('timeline-entry-tapers'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      initiallyExpanded:
          widget.initial.lead != null || widget.initial.trail != null,
      leading: const Icon(Icons.compare_arrows),
      title: const Text('Days before and after'),
      subtitle: const Text(
        'Drawn as wedges either side of it, as the way up to a feast and '
        'home again; tapping one opens the span.',
      ),
      children: [side(_lead, 'lead', 'Before'), side(_trail, 'trail', 'After')],
    );
  }

  Widget _time(_TimeDraft draft, {required String label, required String key}) {
    final timeline = _timeline;
    final calendar = timeline.isCalendar;
    // The months and days of the year entered so far; a year not yet
    // entered is taken to have no second Adar, unless every year has one.
    final year = _yearOf(draft) ?? 1;
    final months = timeline.monthsIn(year);
    final month = draft.month != null && draft.month! <= months
        ? draft.month
        : null;
    final days = month == null ? 0 : timeline.daysInMonth(year, month);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!timeline.isAnnual)
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
        if (timeline.hasMonths) ...[
          if (!timeline.isAnnual) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  key: ValueKey('timeline-entry-$key-month-$months'),
                  initialValue: month,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: timeline.isAnnual ? '$label month' : 'Month',
                  ),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (var m = 1; m <= months; m++)
                      DropdownMenuItem(
                        value: m,
                        child: Text(timeline.monthChoice(year, m)),
                      ),
                  ],
                  onChanged: (m) => setState(() {
                    draft.month = m;
                    if (m == null ||
                        (draft.day ?? 0) > timeline.daysInMonth(year, m)) {
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
                  key: ValueKey('timeline-entry-$key-day-$month-$days'),
                  initialValue: draft.day != null && draft.day! <= days
                      ? draft.day
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Day'),
                  items: [
                    const DropdownMenuItem(child: Text('—')),
                    for (var d = 1; d <= days; d++)
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
    final unit = units.contains(_durationUnit)
        ? _durationUnit
        : units.firstOrNull;
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
                  decimal: !timeline.hasMonths,
                ),
                decoration: InputDecoration(
                  labelText: 'Lasting',
                  suffixText: timeline.hasMonths || timeline.unit.isEmpty
                      ? null
                      : timeline.unit,
                ),
                onChanged: (_) => _changed(),
              ),
            ),
            if (timeline.hasMonths && unit != null) ...[
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
        if (timeline.hasMonths && !units.contains(TimelineDurationUnit.days))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              !units.contains(TimelineDurationUnit.months)
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

  /// Its category, typed or picked from those already on its timeline.
  Widget _categoryField(ThemeData theme) {
    final existing = {
      for (final e in widget.entries)
        if (e.timelineId == _timelineId && e.category.isNotEmpty) e.category,
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('timeline-entry-category'),
          controller: _category,
          decoration: const InputDecoration(
            labelText: 'Category (optional)',
            hintText: 'Pilgrim feast, Sabbath, fast…',
          ),
          onChanged: (_) => _changed(),
        ),
        if (existing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final category in existing)
                  ChoiceChip(
                    label: Text(category),
                    selected: _category.text.trim() == category,
                    visualDensity: VisualDensity.compact,
                    onSelected: (on) =>
                        setState(() => _category.text = on ? category : ''),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// How far from [anchor] it falls: which day counting from it, perhaps
  /// moved on to a day of the week, or else how long after it starts; and
  /// where that puts it.
  Widget _pinFields(ThemeData theme, StudyTimelineEntry anchor) {
    final timeline = _timeline;
    final units = _offsetUnits(anchor);
    final unit = _offsetUnitFor(anchor);
    final days = unit == TimelineDurationUnit.days;
    final pin = _pin;
    final at = pin == null || !pin.isValid
        ? null
        : timeline.placePin(anchor, pin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('timeline-entry-offset'),
                controller: _offset,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: !timeline.hasMonths,
                  signed: days,
                ),
                decoration: InputDecoration(
                  labelText: days
                      ? anchor.isSpan
                            ? 'Day of the span'
                            : 'Day, counting from it'
                      : 'After it starts',
                  helperText: days
                      ? anchor.isSpan
                            ? "Day 1 is the span's first; 0 the day before."
                            : 'Day 1 is its own day, 2 the next; 0 the day '
                                  'before.'
                      : null,
                  helperMaxLines: 2,
                  suffixText: days || timeline.hasMonths
                      ? null
                      : timeline.unit.isEmpty
                      ? null
                      : timeline.unit,
                ),
                onChanged: (_) => _changed(),
              ),
            ),
            if (units.length > 1 && unit != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<TimelineDurationUnit>(
                  key: ValueKey('timeline-entry-offset-unit-${anchor.id}'),
                  initialValue: unit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'In'),
                  items: [
                    for (final u in units)
                      DropdownMenuItem(value: u, child: Text(u.name)),
                  ],
                  onChanged: (u) => setState(() {
                    _offsetUnit = u;
                    _error = null;
                  }),
                ),
              ),
            ],
          ],
        ),
        if (days) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            key: const ValueKey('timeline-entry-weekday'),
            initialValue: _weekday,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Then on',
              helperText:
                  'Moves it on to the first such day: the morrow after '
                  'the Sabbath is the first day of the week.',
              helperMaxLines: 2,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('That day')),
              for (var weekday = 1; weekday <= 7; weekday++)
                DropdownMenuItem(
                  value: weekday,
                  child: Text(
                    'The first ${timelineWeekdayLabel(weekday)} from it',
                  ),
                ),
            ],
            onChanged: (weekday) => setState(() {
              _weekday = weekday;
              _error = null;
            }),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            at == null
                ? '${anchor.title} starts ${timeline.formatTime(anchor.start)}'
                : '${_span ? 'Starts' : 'Falls on'} '
                      '${timeline.formatTime(at)}, moving with '
                      '${anchor.title}',
            key: const ValueKey('timeline-entry-offset-time'),
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
      title: Text(
        _sabbath && !_span && _timeline.hasMonths
            ? (widget.creating ? 'New shabbaton' : 'Edit shabbaton')
            : widget.creating
            ? 'New timeline $noun'
            : 'Edit $noun',
      ),
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
              const SizedBox(height: 12),
              _categoryField(theme),
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
              if (_anchors.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  key: ValueKey('timeline-entry-pin-$_timelineId'),
                  initialValue: _anchor?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Pinned to',
                    helperText: 'Pinned, it moves with what it is pinned to.',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Not pinned: a time of its own'),
                    ),
                    for (final s in _anchors)
                      DropdownMenuItem(
                        value: s.id,
                        child: Row(
                          children: [
                            Icon(
                              s.isSpan
                                  ? Icons.linear_scale
                                  : Icons.radio_button_checked,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: _pinTo,
                ),
                const SizedBox(height: 12),
              ],
              if (_anchor case final anchor?)
                _pinFields(theme, anchor)
              else
                _time(_start, label: _span ? 'Start' : 'When', key: 'start'),
              if (!_span && _timeline.hasMonths) ...[
                const SizedBox(height: 12),
                Text(
                  'Part of the day, which runs from sunset',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SegmentedButton<TimelineDayPart?>(
                  key: const ValueKey('timeline-entry-part'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: null, label: Text('Whole')),
                    for (final part in TimelineDayPart.values)
                      ButtonSegment(value: part, label: Text(part.label)),
                  ],
                  selected: {_part},
                  onSelectionChanged: (s) => setState(() => _part = s.single),
                ),
              ],
              if (!_span && _timeline.hasMonths)
                SwitchListTile(
                  key: const ValueKey('timeline-entry-sabbath'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.star_outline),
                  title: const Text('Shabbaton (a ceasing)'),
                  subtitle: const Text(
                    'A day of ceasing besides the Sabbath, as the 1st of the '
                    '7th month (Leviticus 23:24), coloured in the calendar.',
                  ),
                  value: _sabbath,
                  onChanged: (on) => setState(() {
                    _sabbath = on;
                    _error = null;
                  }),
                ),
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
                if (_timeline.hasMonths)
                  SwitchListTile(
                    key: const ValueKey('timeline-entry-counted'),
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.format_list_numbered),
                    title: const Text('Count its days'),
                    subtitle: const Text(
                      'Numbers its days and weeks, as the fifty days to '
                      'Shavuot are counted (Leviticus 23:15-16).',
                    ),
                    value: _counted,
                    onChanged: (on) => setState(() => _counted = on),
                  ),
                if (_timeline.hasMonths) _dayNoteFields(theme),
                if (_timeline.hasMonths) _taperFields(),
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
              const SizedBox(height: 16),
              Text('Linked entries', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final link in _links)
                    InputChip(
                      avatar: const Icon(Icons.link),
                      label: Text(_linkLabel(link)),
                      onDeleted: () => setState(() => _links.remove(link)),
                    ),
                  TextButton.icon(
                    key: const ValueKey('timeline-entry-add-link'),
                    onPressed: _addLink,
                    icon: const Icon(Icons.link),
                    label: const Text('Link to an entry'),
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

/// Chooses an entry to link to (see [TimelineLink]): on one of the study's
/// [timelines], or, given [loadBibleEntries], on the Bible timeline, found
/// by its title. [exceptId] is the entry being linked, not offered.
class StudyTimelineLinkDialog extends StatefulWidget {
  const StudyTimelineLinkDialog({
    super.key,
    required this.timelines,
    required this.entries,
    required this.exceptId,
    this.initialTimelineId,
    this.loadBibleEntries,
  });

  final List<StudyTimeline> timelines;
  final List<StudyTimelineEntry> entries;
  final String exceptId;

  /// The timeline to look on first: another than this, where it has
  /// entries.
  final String? initialTimelineId;
  final Future<List<StudyTimelineEntry>> Function()? loadBibleEntries;

  @override
  State<StudyTimelineLinkDialog> createState() =>
      _StudyTimelineLinkDialogState();
}

class _StudyTimelineLinkDialogState extends State<StudyTimelineLinkDialog> {
  late final List<StudyTimeline> _sources = [
    for (final t in widget.timelines)
      if (widget.entries.any(
        (e) => e.timelineId == t.id && e.id != widget.exceptId,
      ))
        t,
    if (widget.loadBibleEntries != null) bibleTimeline,
  ];
  late String? _sourceId =
      (_sources.where((t) => t.id != widget.initialTimelineId).firstOrNull ??
              _sources.firstOrNull)
          ?.id;
  Future<List<StudyTimelineEntry>>? _bible;
  String _query = '';

  StudyTimeline? get _source =>
      _sources.where((t) => t.id == _sourceId).firstOrNull;

  Widget _list(StudyTimeline source, List<StudyTimelineEntry> entries) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final e in entries)
        if (e.id != widget.exceptId &&
            (query.isEmpty || e.title.toLowerCase().contains(query)))
          e,
    ];
    if (shown.isEmpty) {
      return const Center(child: Text('Nothing found.'));
    }
    return ListView.builder(
      itemCount: shown.length,
      itemBuilder: (context, i) {
        final entry = shown[i];
        return ListTile(
          key: ValueKey('timeline-link-choice-${entry.id}'),
          dense: true,
          leading: Icon(timelineEntryIcon(entry)),
          title: Text(entry.title),
          subtitle: Text(timelineEntryTime(source, entry)),
          onTap: () => Navigator.pop(
            context,
            TimelineLink(source.id, entry.id, title: entry.title),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return AlertDialog(
      title: const Text('Link to an entry'),
      content: SizedBox(
        width: 480,
        height: 440,
        child: source == null
            ? const Center(child: Text('There is nothing else to link to.'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: const ValueKey('timeline-link-source'),
                    initialValue: source.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Timeline'),
                    items: [
                      for (final t in _sources)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text(t.title, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) => setState(() => _sourceId = id),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('timeline-link-search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Find by title',
                    ),
                    onChanged: (text) => setState(() => _query = text),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: source.id == bibleTimelineId
                        ? FutureBuilder<List<StudyTimelineEntry>>(
                            future: _bible ??= widget.loadBibleEntries!(),
                            builder: (context, snapshot) => snapshot.hasError
                                ? const Center(
                                    child: Text(
                                      'The Bible timeline could not be read.',
                                    ),
                                  )
                                : snapshot.data == null
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : _list(source, snapshot.data!),
                          )
                        : _list(
                            source,
                            [
                              for (final e in widget.entries)
                                if (e.timelineId == source.id) e,
                            ]..sort(compareTimelineEntries),
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
