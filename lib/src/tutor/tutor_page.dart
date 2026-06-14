import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bindings/bindings.dart';
import 'alphabet_data.dart';
import 'alphabet_quiz.dart';
import 'letters_tab.dart';
import 'word_quiz.dart';
import 'words_tab.dart';

/// How many vocabulary words to request from Rust — far more than anyone
/// masters in one sitting, fetched once per visit.
const int _kVocabLimit = 400;

/// The smallest word pool the quiz draws from, so it is usable before the
/// user has browsed many cards.
const int _kMinQuizPool = 8;

class TutorPage extends StatefulWidget {
  const TutorPage({super.key});

  @override
  State<TutorPage> createState() => _TutorPageState();
}

class _TutorPageState extends State<TutorPage> {
  static const _kLetterMastery = 'tutor_mastery';
  static const _kLettersSeen = 'tutor_letters_seen';
  static const _kWordIndex = 'tutor_word_index';
  static const _kWordMastery = 'tutor_word_mastery';

  List<int> _letterMastery = List.filled(kAlphabet.length, 0);
  final Set<int> _lettersSeen = {};
  List<TutorWord>? _words;
  int _furthestWord = 0;
  Map<String, int> _wordMastery = {};
  bool _prefsLoaded = false;

  StreamSubscription<RustSignalPack<VocabList>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = VocabList.rustSignalStream.listen((pack) {
      if (pack.message.offset != 0) return;
      setState(() => _words = buildTutorWords(pack.message.entries));
    });
    GetVocab(limit: _kVocabLimit, offset: 0).sendSignalToRust();
    _loadPrefs();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final mastery = prefs.getString(_kLetterMastery);
    final seen = prefs.getString(_kLettersSeen);
    final wordMastery = prefs.getString(_kWordMastery);
    final furthest = prefs.getInt(_kWordIndex);
    if (!mounted) return;
    setState(() {
      if (mastery != null) {
        final parts = mastery.split(',').map(int.tryParse).toList();
        if (parts.length == kAlphabet.length && !parts.contains(null)) {
          _letterMastery = parts
              .map((p) => p!.clamp(0, kMasteryTarget))
              .toList();
        }
      }
      if (seen != null && seen.isNotEmpty) {
        _lettersSeen.addAll(
          seen
              .split(',')
              .map(int.tryParse)
              .whereType<int>()
              .where((i) => i >= 0 && i < kAlphabet.length),
        );
      }
      if (wordMastery != null) {
        try {
          _wordMastery = (jsonDecode(wordMastery) as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as int).clamp(0, kMasteryTarget)),
          );
        } catch (_) {}
      }
      if (furthest != null && furthest >= 0) _furthestWord = furthest;
      _prefsLoaded = true;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLetterMastery, _letterMastery.join(','));
    await prefs.setString(_kLettersSeen, _lettersSeen.join(','));
    await prefs.setInt(_kWordIndex, _furthestWord);
    await prefs.setString(_kWordMastery, jsonEncode(_wordMastery));
  }

  void _onLetterAnswered(int letterIndex, bool correct) {
    setState(() {
      final m = _letterMastery[letterIndex];
      _letterMastery[letterIndex] = correct
          ? (m + 1).clamp(0, kMasteryTarget)
          : (m - 1).clamp(0, kMasteryTarget);
    });
    _savePrefs();
  }

  void _onWordAnswered(String surface, bool correct) {
    setState(() {
      final m = _wordMastery[surface] ?? 0;
      _wordMastery[surface] = correct
          ? (m + 1).clamp(0, kMasteryTarget)
          : (m - 1).clamp(0, kMasteryTarget);
    });
    _savePrefs();
  }

  void _onWordViewed(int index, List<int> newLetters) {
    if (index <= _furthestWord && newLetters.isEmpty) return;
    setState(() {
      if (index > _furthestWord) _furthestWord = index;
      _lettersSeen.addAll(newLetters);
    });
    _savePrefs();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = _words;
    final ready = words != null && _prefsLoaded;
    final quizPool = ready
        ? words
              .take((_furthestWord + 1).clamp(_kMinQuizPool, words.length))
              .toList()
        : null;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          title: const Text('Tutor'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Words'),
              Tab(text: 'Letters'),
              Tab(text: 'Quiz'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            !ready
                ? const Center(child: CircularProgressIndicator())
                : words.isEmpty
                ? const Center(child: Text('No vocabulary found'))
                : WordsTab(
                    words: words,
                    initialIndex: _furthestWord.clamp(0, words.length - 1),
                    lettersSeen: _lettersSeen,
                    onWordViewed: _onWordViewed,
                  ),
            LettersTab(mastery: _letterMastery),
            _QuizTab(
              letterMastery: _letterMastery,
              onLetterAnswered: _onLetterAnswered,
              wordPool: quizPool,
              wordMastery: _wordMastery,
              onWordAnswered: _onWordAnswered,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Drill { letters, words }

class _QuizTab extends StatefulWidget {
  final List<int> letterMastery;
  final void Function(int, bool) onLetterAnswered;
  final List<TutorWord>? wordPool; // null while vocabulary loads
  final Map<String, int> wordMastery;
  final void Function(String, bool) onWordAnswered;

  const _QuizTab({
    required this.letterMastery,
    required this.onLetterAnswered,
    required this.wordPool,
    required this.wordMastery,
    required this.onWordAnswered,
  });

  @override
  State<_QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<_QuizTab> {
  _Drill _drill = _Drill.words;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_Drill>(
            segments: const [
              ButtonSegment(value: _Drill.words, label: Text('Words')),
              ButtonSegment(value: _Drill.letters, label: Text('Letters')),
            ],
            selected: {_drill},
            onSelectionChanged: (s) => setState(() => _drill = s.first),
          ),
        ),
        Expanded(
          child: _drill == _Drill.letters
              ? AlphabetQuiz(
                  mastery: widget.letterMastery,
                  onAnswered: widget.onLetterAnswered,
                )
              : widget.wordPool == null
              ? const Center(child: CircularProgressIndicator())
              : WordQuiz(
                  pool: widget.wordPool!,
                  mastery: widget.wordMastery,
                  onAnswered: widget.onWordAnswered,
                ),
        ),
      ],
    );
  }
}
