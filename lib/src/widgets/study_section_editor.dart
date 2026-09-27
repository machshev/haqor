import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'markdown_note.dart';

/// Edits a passage summary (its title, note and the chapter or verses it
/// covers) or a section heading beneath one (its title, note and the verse
/// it starts at, within [summary]'s passage).
class StudySectionEditor extends StatefulWidget {
  const StudySectionEditor({
    super.key,
    required this.initial,
    required this.creating,
    required this.useEnglishBookNames,
    required this.loadChapter,
    required this.validate,
    this.summary,
    this.parents = const [],
  });

  final StudySection initial;
  final bool creating;
  final bool useEnglishBookNames;
  final Future<List<VerseEntry>> Function(int book, int chapter) loadChapter;

  /// Why a section cannot be saved as given, or null when it can.
  final String? Function(StudySection section) validate;

  /// The summary a heading belongs to; null when editing a summary.
  final StudySection? summary;

  /// For a heading, the sections it may go under, outermost (its summary)
  /// first; offered when there is more than one. The initial parent is kept.
  final List<StudySection> parents;

  @override
  State<StudySectionEditor> createState() => _StudySectionEditorState();
}

class _StudySectionEditorState extends State<StudySectionEditor> {
  late int _book, _chapter, _verse, _endChapter, _endVerse;
  late bool _wholeChapter;
  late String? _parentId;
  late final TextEditingController _title, _note;
  List<VerseEntry> _startVerses = [], _endVerses = [];
  final Map<(int, int), Future<List<VerseEntry>>> _chapters = {};
  bool _loading = true;
  String? _loadError, _error;
  int _generation = 0;

  bool get _isSummary => widget.summary == null;
  StudyPassage? get _summaryRange => widget.summary?.range;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    _book = s.bookIndex ?? _summaryRange!.bookIndex;
    _chapter = s.chapter;
    _verse = s.verse;
    _wholeChapter = s.wholeChapter;
    _endChapter = s.endChapter ?? s.chapter;
    _endVerse = s.endVerse ?? s.verse;
    _title = TextEditingController(text: s.title);
    _note = TextEditingController(text: s.note);
    _parentId = s.parentId;
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<List<VerseEntry>> _getChapter(int chapter) => _chapters.putIfAbsent((
    _book,
    chapter,
  ), () => widget.loadChapter(_book, chapter));

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadError = null;
      _error = null;
    });
    try {
      final start = await _getChapter(_chapter);
      if (!mounted || generation != _generation) return;
      final end = !_isSummary || _wholeChapter
          ? start
          : await _getChapter(_endChapter);
      if (!mounted || generation != _generation) return;
      if (start.isEmpty || end.isEmpty) throw StateError('Empty chapter');
      setState(() {
        _startVerses = start;
        _endVerses = end;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _chapters.clear();
      setState(() {
        _loading = false;
        _loadError = 'Could not load the passage. Please retry.';
      });
    }
  }

  StudySection get _anchor => _isSummary
      ? StudySection(
          id: widget.initial.id,
          title: widget.initial.title,
          chapter: _chapter,
          verse: _wholeChapter ? 1 : _verse,
          bookIndex: _book,
          wholeChapter: _wholeChapter,
          endChapter: _wholeChapter ? null : _endChapter,
          endVerse: _wholeChapter ? null : _endVerse,
        )
      : StudySection(
          id: widget.initial.id,
          title: widget.initial.title,
          chapter: _chapter,
          verse: _verse,
        );

  StudySection get _edited => widget.initial
      .withAnchor(_anchor)
      .copyWith(
        title: _title.text.trim(),
        note: _note.text.trim(),
        parentId: () => _parentId,
      );

  void _save() {
    final edited = _edited;
    String? error;
    if (edited.title.isEmpty) {
      error = 'Give the section a title.';
    } else if ((!_wholeChapter || !_isSummary) &&
        (!_startVerses.any((v) => v.verse == _verse) ||
            (_isSummary && !_endVerses.any((v) => v.verse == _endVerse)))) {
      error = 'Choose a verse that exists in each chapter.';
    } else {
      error = widget.validate(edited);
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, edited);
  }

  Widget _numberChoice(
    String label,
    int value,
    List<int> values,
    ValueChanged<int> changed,
  ) => DropdownButtonFormField<int>(
    key: ValueKey('$label-$value-${values.length}'),
    initialValue: values.contains(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final n in values) DropdownMenuItem(value: n, child: Text('$n')),
    ],
    onChanged: (v) {
      if (v != null) changed(v);
    },
  );

  /// The chapters a heading may start in: those of its summary.
  List<int> get _chapterChoices {
    final range = _summaryRange;
    if (range == null) {
      return List.generate(kBooks[_book].chapters, (i) => i + 1);
    }
    return [for (var c = range.chapter; c <= range.lastChapter; c++) c];
  }

  List<int> _verseChoices(List<VerseEntry> verses, int chapter) {
    final range = _summaryRange;
    return [
      for (final v in verses)
        if (range == null || range.containsVerse(_book, chapter, v.verse))
          v.verse,
    ];
  }

  Widget _endpoint({required bool end}) {
    final chapter = end ? _endChapter : _chapter;
    final verse = end ? _endVerse : _verse;
    final verses = end ? _endVerses : _startVerses;
    final label = _isSummary ? (end ? 'End' : 'Start') : 'Heading';
    final verseChoices = _verseChoices(verses, chapter);
    return Row(
      children: [
        Expanded(
          child: _numberChoice('$label chapter', chapter, _chapterChoices, (v) {
            setState(() {
              if (end) {
                _endChapter = v;
                _endVerse = 1;
              } else {
                _chapter = v;
                _verse = 1;
              }
            });
            _load().then((_) {
              // A heading in a summary's first chapter starts at its verse.
              final choices = _verseChoices(_startVerses, _chapter);
              if (!end && mounted && choices.isNotEmpty) {
                setState(() {
                  if (!choices.contains(_verse)) _verse = choices.first;
                });
              }
            });
          }),
        ),
        if (!_isSummary || !_wholeChapter) ...[
          const SizedBox(width: 16),
          Expanded(
            child: _numberChoice(
              '$label verse',
              verse,
              verseChoices,
              (v) => setState(() {
                _error = null;
                if (end) {
                  _endVerse = v;
                } else {
                  _verse = v;
                }
              }),
            ),
          ),
        ],
      ],
    );
  }

  String get _referenceText {
    final anchor = _anchor;
    final book = bookDisplayName(_book, useEnglish: widget.useEnglishBookNames);
    return anchor.isSummary
        ? '$book ${anchor.range!.reference}'
        : 'From $book ${anchor.chapter}:${anchor.verse}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(switch ((_isSummary, widget.creating)) {
      (true, true) => 'New passage summary',
      (true, false) => 'Edit passage summary',
      (false, true) => 'New section heading',
      (false, false) => 'Edit section heading',
    }),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('section-title'),
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _isSummary ? 'Summary title' : 'Heading',
              ),
            ),
            const SizedBox(height: 12),
            if (!_isSummary && widget.parents.length > 1) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('section-parent'),
                initialValue: _parentId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Under'),
                items: [
                  for (var i = 0; i < widget.parents.length; i++)
                    DropdownMenuItem(
                      value: widget.parents[i].id,
                      child: Text(
                        '${'  ' * i}${widget.parents[i].title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _parentId = id;
                  _error = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            if (_isSummary) ...[
              DropdownButtonFormField<int>(
                initialValue: _book,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Book'),
                items: [
                  for (var b = 0; b < kBooks.length; b++)
                    DropdownMenuItem(
                      value: b,
                      child: Text(
                        bookDisplayName(
                          b,
                          useEnglish: widget.useEnglishBookNames,
                        ),
                      ),
                    ),
                ],
                onChanged: (b) {
                  if (b == null) return;
                  setState(() {
                    _book = b;
                    _chapter = _endChapter = _verse = _endVerse = 1;
                  });
                  _load();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<bool>(
                initialValue: _wholeChapter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Covers'),
                items: const [
                  DropdownMenuItem(value: true, child: Text('Whole chapter')),
                  DropdownMenuItem(
                    value: false,
                    child: Text('Verse or verse range'),
                  ),
                ],
                onChanged: (whole) {
                  if (whole == null) return;
                  setState(() => _wholeChapter = whole);
                  _load();
                },
              ),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const LinearProgressIndicator()
            else if (_loadError != null) ...[
              Text(_loadError!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ] else ...[
              _endpoint(end: false),
              if (_isSummary && !_wholeChapter) ...[
                const SizedBox(height: 16),
                _endpoint(end: true),
              ],
              const SizedBox(height: 16),
              Text(_referenceText),
            ],
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
        onPressed: _loading || _loadError != null ? null : _save,
        child: Text(widget.creating ? 'Add' : 'Save'),
      ),
    ],
  );
}
