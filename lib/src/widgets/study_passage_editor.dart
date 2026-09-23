import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'verse_row.dart';

enum _PassageScope { chapter, verses, phrase }

/// Uses the reader's lexical word positions, also in interlinear mode.
class StudyPassageEditor extends StatefulWidget {
  const StudyPassageEditor({
    super.key,
    required this.initial,
    required this.creating,
    required this.useEnglishBookNames,
    required this.loadChapter,
    required this.isDuplicate,
  });

  final StudyPassage initial;
  final bool creating;
  final bool useEnglishBookNames;
  final Future<List<VerseEntry>> Function(int book, int chapter) loadChapter;
  final bool Function(StudyPassage passage) isDuplicate;

  @override
  State<StudyPassageEditor> createState() => _StudyPassageEditorState();
}

class _StudyPassageEditorState extends State<StudyPassageEditor> {
  late int _book, _chapter, _verse, _endChapter, _endVerse;
  late int _startWord, _endWord;
  late _PassageScope _scope;
  late final TextEditingController _note;
  List<VerseEntry> _startVerses = [], _endVerses = [];
  final Map<(int, int), Future<List<VerseEntry>>> _chapters = {};
  bool _loading = true;
  String? _loadError, _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _book = p.bookIndex;
    _chapter = p.chapter;
    _verse = p.verse;
    _endChapter = p.lastChapter;
    _endVerse = p.lastVerse;
    _startWord = p.startWord ?? 0;
    _endWord = p.endWord ?? 0;
    _scope = p.wholeChapter
        ? _PassageScope.chapter
        : p.isPhrase
        ? _PassageScope.phrase
        : _PassageScope.verses;
    _note = TextEditingController(text: p.note);
    _load();
  }

  @override
  void dispose() {
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
      final end = _scope == _PassageScope.chapter
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

  List<String> _words(List<VerseEntry> verses, int verse) {
    final entry = verses.where((v) => v.verse == verse).firstOrNull;
    if (entry == null) return [];
    final tokens = entry.text.split(' ').where((w) => w.isNotEmpty).toList();
    final positions = verseGlossPositions(tokens);
    return [
      for (var i = 0; i < tokens.length; i++)
        if (positions[i] != null) tokens[i],
    ];
  }

  StudyPassage get _reference => StudyPassage(
    bookIndex: _book,
    chapter: _chapter,
    verse: _scope == _PassageScope.chapter ? 1 : _verse,
    wholeChapter: _scope == _PassageScope.chapter,
    endChapter: _scope == _PassageScope.chapter ? null : _endChapter,
    endVerse: _scope == _PassageScope.chapter ? null : _endVerse,
    startWord: _scope == _PassageScope.phrase ? _startWord : null,
    endWord: _scope == _PassageScope.phrase ? _endWord : null,
  );

  void _save() {
    final ref = _reference;
    String? error;
    if (!ref.isValid) {
      error = 'The end of the passage must be at or after the start.';
    } else if (_scope != _PassageScope.chapter &&
        (!_startVerses.any((v) => v.verse == _verse) ||
            !_endVerses.any((v) => v.verse == _endVerse))) {
      error = 'Choose a verse that exists in each chapter.';
    } else if (ref.isPhrase &&
        (_startWord >= _words(_startVerses, _verse).length ||
            _endWord >= _words(_endVerses, _endVerse).length)) {
      error = 'Choose the first and last words of the phrase.';
    } else if (widget.isDuplicate(ref)) {
      error = 'This reference is already bookmarked in this study.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      widget.initial.withReference(ref).copyWith(note: _note.text.trim()),
    );
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

  Widget _endpoint({required bool end}) {
    final chapter = end ? _endChapter : _chapter;
    final verse = end ? _endVerse : _verse;
    final verses = end ? _endVerses : _startVerses;
    final words = _words(verses, verse);
    final label = end ? 'End' : 'Start';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _numberChoice(
                '$label chapter',
                chapter,
                List.generate(kBooks[_book].chapters, (i) => i + 1),
                (v) {
                  setState(() {
                    if (end) {
                      _endChapter = v;
                      _endVerse = 1;
                      _endWord = 0;
                    } else {
                      _chapter = v;
                      _verse = 1;
                      _startWord = 0;
                    }
                  });
                  _load();
                },
              ),
            ),
            if (_scope != _PassageScope.chapter) ...[
              const SizedBox(width: 16),
              Expanded(
                child: _numberChoice(
                  '$label verse',
                  verse,
                  verses.map((v) => v.verse).toList(),
                  (v) => setState(() {
                    _error = null;
                    if (end) {
                      _endVerse = v;
                      _endWord = 0;
                    } else {
                      _verse = v;
                      _startWord = 0;
                    }
                  }),
                ),
              ),
            ],
          ],
        ),
        if (_scope == _PassageScope.phrase) ...[
          const SizedBox(height: 12),
          Text(end ? 'Last word (included)' : 'First word (included)'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            textDirection: TextDirection.rtl,
            children: [
              for (var i = 0; i < words.length; i++)
                ChoiceChip(
                  label: Text(words[i], textDirection: TextDirection.rtl),
                  tooltip: 'Word ${i + 1}',
                  selected: (end ? _endWord : _startWord) == i,
                  onSelected: (_) => setState(() {
                    _error = null;
                    if (end) {
                      _endWord = i;
                    } else {
                      _startWord = i;
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creating ? 'Bookmark passage' : 'Edit passage'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  _startWord = _endWord = 0;
                });
                _load();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_PassageScope>(
              initialValue: _scope,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Bookmark'),
              items: const [
                DropdownMenuItem(
                  value: _PassageScope.chapter,
                  child: Text('Whole chapter'),
                ),
                DropdownMenuItem(
                  value: _PassageScope.verses,
                  child: Text('Verse or verse range'),
                ),
                DropdownMenuItem(
                  value: _PassageScope.phrase,
                  child: Text('Phrase'),
                ),
              ],
              onChanged: (scope) {
                if (scope == null) return;
                setState(() => _scope = scope);
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else if (_loadError != null) ...[
              Text(_loadError!),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ] else ...[
              _endpoint(end: false),
              if (_scope != _PassageScope.chapter) ...[
                const SizedBox(height: 16),
                _endpoint(end: true),
              ],
              const SizedBox(height: 16),
              Text(_reference.reference),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Passage note'),
            ),
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
        child: Text(widget.creating ? 'Bookmark' : 'Save'),
      ),
    ],
  );
}
