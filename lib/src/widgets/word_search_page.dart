import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';

/// How long the search waits after a keystroke before asking Rust, so a word
/// typed quickly is looked up once rather than letter by letter.
const wordSearchDebounce = Duration(milliseconds: 250);

/// The queries the empty search offers, one in each way of searching.
const _examples = [
  ('שמע', 'a Hebrew root'),
  ('וַיֹּאמֶר', 'a form in the text'),
  ('αγαπη', 'Greek, accents optional'),
  ('ܚܘܒܐ', 'the Peshitta, in Syriac letters'),
  ('shepherd', 'an English meaning'),
];

/// The texts a match can be of, in the order their sections are shown when
/// a query matches in several.
enum WordSearchLanguage {
  hebrew('Hebrew & Aramaic · Old Testament'),
  greek('Greek · New Testament'),
  aramaic('Aramaic · Peshitta');

  const WordSearchLanguage(this.heading);

  final String heading;

  static WordSearchLanguage of(WordSearchEntry entry) =>
      values.firstWhere((l) => l.name == entry.language, orElse: () => hebrew);
}

/// Finds the Bible's words by what the reader types: a Hebrew or Aramaic word
/// or root, pointed or not, a Greek word with or without its accents, a
/// Syriac word, or an English meaning. Each match is a dictionary word with
/// its gloss and how often the text uses it; choosing one closes the page
/// with it, for the reader to open at its occurrences.
class WordSearchPage extends StatefulWidget {
  const WordSearchPage({super.key, this.initialQuery = '', this.sendRequest});

  final String initialQuery;

  /// Stands in for the signal to Rust, for tests.
  final void Function(SearchWords request)? sendRequest;

  /// The query the page last searched, to start from when it is opened
  /// again.
  static String lastQuery = '';

  /// Opens the page over [context]'s navigator; completes with the word
  /// chosen, or null when the page is left without choosing one.
  static Future<WordSearchEntry?> open(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<WordSearchEntry>(
          builder: (_) => WordSearchPage(initialQuery: lastQuery),
        ),
      );

  @override
  State<WordSearchPage> createState() => _WordSearchPageState();
}

class _WordSearchPageState extends State<WordSearchPage> {
  static int _nextRequestId = 1;

  late final TextEditingController _search = TextEditingController(
    text: widget.initialQuery,
  );
  final FocusNode _focus = FocusNode();
  StreamSubscription<RustSignalPack<WordSearchResults>>? _sub;
  Timer? _debounce;
  int? _requestId;

  /// The query [_matches] answer, and whether a newer one is awaited.
  String _answered = '';
  List<WordSearchEntry> _matches = const [];
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _sub = WordSearchResults.rustSignalStream.listen((pack) {
      final results = pack.message;
      if (!mounted || results.requestId != _requestId) return;
      setState(() {
        _matches = results.matches;
        _answered = _search.text.trim();
        _pending = false;
      });
    });
    _search.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _search.text.length,
    );
    if (_search.text.trim().isNotEmpty) _send(_search.text);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed(String text) {
    WordSearchPage.lastQuery = text;
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _requestId = null;
        _matches = const [];
        _answered = '';
        _pending = false;
      });
      return;
    }
    setState(() => _pending = true);
    _debounce = Timer(wordSearchDebounce, () => _send(text));
  }

  void _send(String text) {
    final request = SearchWords(
      requestId: _requestId = _nextRequestId++,
      query: text.trim(),
    );
    _pending = true;
    final send = widget.sendRequest;
    if (send != null) {
      send(request);
    } else {
      request.sendSignalToRust();
    }
  }

  void _fill(String query) {
    _search.text = query;
    _search.selection = TextSelection.collapsed(offset: query.length);
    _changed(query);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const ValueKey('word-search-field'),
          controller: _search,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search Hebrew, Aramaic, Greek or English',
            border: InputBorder.none,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: () => _fill(''),
                  ),
          ),
          onChanged: _changed,
          onSubmitted: (_) {
            final first = _matches.firstOrNull;
            if (first != null && !_pending) Navigator.of(context).pop(first);
          },
        ),
        bottom: _pending
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: query.isEmpty
          ? _buildExamples(context)
          : _matches.isEmpty && !_pending && _answered == query
          ? _buildNothingFound(context, query)
          : _buildMatches(context),
    );
  }

  Widget _buildExamples(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Find a word, then read every place the text uses it. Try',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final (example, what) in _examples)
          ListTile(
            leading: const Icon(Icons.search),
            title: Text(example, style: _wordStyle(context, example)),
            subtitle: Text(what),
            onTap: () => _fill(example),
          ),
      ],
    );
  }

  Widget _buildNothingFound(BuildContext context, String query) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'No word of the text matches “$query”.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildMatches(BuildContext context) {
    final sections = <WordSearchLanguage, List<WordSearchEntry>>{};
    for (final match in _matches) {
      (sections[WordSearchLanguage.of(match)] ??= []).add(match);
    }
    final rows = <Widget>[];
    for (final language in WordSearchLanguage.values) {
      final matches = sections[language];
      if (matches == null) continue;
      rows.add(_SectionHeading(language.heading));
      for (final (index, match) in matches.indexed) {
        rows.add(
          _MatchTile(
            key: ValueKey('word-search-${language.name}-$index'),
            match: match,
            onTap: () => Navigator.of(context).pop(match),
          ),
        );
      }
    }
    return ListView(children: rows);
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// One dictionary word: its headword, its gloss, and below them its root,
/// its part of speech, how it was matched and how often the text uses it.
class _MatchTile extends StatelessWidget {
  const _MatchTile({super.key, required this.match, required this.onTap});

  final WordSearchEntry match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = [
      if (match.root.isNotEmpty && match.root != match.headword)
        'root ${match.root}',
      if (match.partOfSpeech.isNotEmpty) match.partOfSpeech,
      switch (match.matched) {
        'form' => 'by a form of it',
        'root' => 'by its root',
        _ => null,
      },
    ].nonNulls;
    final count = match.occurrences == 1 ? 'once' : '${match.occurrences}×';
    return ListTile(
      onTap: onTap,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(match.headword, style: _wordStyle(context, match.headword)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              match.gloss,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: Text(
        count,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A word set in its own script's face: Hebrew letters right to left.
TextStyle _wordStyle(BuildContext context, String word) {
  final hebrew = word.runes.any((r) => r >= 0x0590 && r <= 0x05FF);
  return TextStyle(
    fontFamily: hebrew ? 'Noto Serif Hebrew' : 'Cardo',
    fontFamilyFallback: const ['Cardo', 'Noto Serif Hebrew'],
    fontSize: 22,
    color: Theme.of(context).colorScheme.onSurface,
  );
}
