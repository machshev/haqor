import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'alphabet_data.dart';
import 'transliterate.dart';
import 'vocab_overrides.dart';

/// Multiple-choice outcome, matching the Rust `SubmitReview.correct` codes.
const int _notQuiz = 0; // self-graded (no quiz)
const int _quizWrong = 1; // wrong pick — always lapses
const int _quizCorrect = 2; // correct pick — graded on confidence

/// Confidence (0..100) sent for a freshly-taught card's "Got it" — a solid
/// "Good", matching the Rust `Grade::from_confidence` thresholds.
const int _gotItConfidence = 70;

const String _hebrewFont = 'Cardo';
const List<String> _hebrewFallback = ['Noto Serif Hebrew'];

/// The SM-2 grade a confidence value (0..100) lands in, mirroring the Rust
/// `Grade::from_confidence` buckets (<25 Again, <55 Hard, <85 Good, else Easy).
({String label, Color color}) _confidenceBucket(double c, ColorScheme scheme) {
  // Red at the "forgot" end, ramping to green at the "easy" end.
  if (c < 25) return (label: 'Again', color: scheme.error);
  if (c < 55) return (label: 'Hard', color: Colors.orange.shade800);
  if (c < 85) return (label: 'Good', color: Colors.lightGreen.shade700);
  return (label: 'Easy', color: Colors.green.shade700);
}

/// A learner-facing syllable for a vowel taught on [host]: the host consonant's
/// sound plus the vowel's *distinguishing* romanization — macron for a long
/// vowel (qamats `ā` vs patah `a`, tsere `ē` vs segol `e`), breve for a hataf
/// (`ă/ĕ/ŏ`), `ə` for sheva. [transliterateHebrew] collapses these to one of
/// a/e/i/o/u, so vocalisation quizzes build their options from this instead.
String _vowelSyllable(String? host, String vowelGlyph) {
  final consonant = (host == null || host.isEmpty) ? '' : transliterateHebrew(host);
  final vowel = glyphInfo(vowelGlyph)?.translit ?? '';
  return '$consonant$vowel';
}

/// The SRS track for a word card: its reading or its meaning.
String _wordTrack(WordCard w) => w.aspect == 'mean' ? 'word_mean' : 'word_read';

/// The single, never-ending spaced-repetition reading flow. The Rust curriculum
/// engine decides every card; this page just renders the current [StudyItem]
/// and reports the learner's answer. Each [SubmitReview] response *is* the next
/// card (one round-trip); a `read_verse` card carries no grade, so we advance
/// past it with another [GetNextStudyItem].
class StudyFlowPage extends StatefulWidget {
  const StudyFlowPage({super.key});

  @override
  State<StudyFlowPage> createState() => _StudyFlowPageState();
}

class _StudyFlowPageState extends State<StudyFlowPage> {
  StreamSubscription<RustSignalPack<StudyItem>>? _sub;
  StudyItem? _item;

  @override
  void initState() {
    super.initState();
    _sub = StudyItem.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() => _item = pack.message);
    });
    GetNextStudyItem().sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Report an answer: `confidence` (0..100) is the slider self-rating; `correct`
  /// is the multiple-choice outcome (see the `_quiz*` codes). The response is the
  /// next card.
  void _grade(String track, String key, int confidence, int correct) =>
      SubmitReview(
        track: track,
        key: key,
        confidence: confidence,
        correct: correct,
      ).sendSignalToRust();

  void _next() => GetNextStudyItem().sendSignalToRust();

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'This clears every learned letter, word and verse. You will start '
          'again from the first verse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) ResetTutor().sendSignalToRust();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = _item;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Learn to read'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset progress',
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: item == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _ProgressStrip(progress: item.progress),
                Expanded(child: _buildItem(context, item)),
              ],
            ),
    );
  }

  Widget _buildItem(BuildContext context, StudyItem item) {
    switch (item.kind) {
      case 'new_glyph':
      case 'review_glyph':
        final g = item.glyph!;
        return _GlyphCard(
          key: ValueKey('glyph:${g.glyph}:${item.kind}'),
          glyph: g,
          isNew: item.kind == 'new_glyph',
          onGrade: (confidence, correct) =>
              _grade('glyph', g.glyph, confidence, correct),
        );
      case 'new_word':
      case 'review_word':
        final w = item.word!;
        return _WordCard(
          key: ValueKey('word:${w.surface}:${w.aspect}:${item.kind}'),
          word: w,
          isNew: item.kind == 'new_word',
          onGrade: (confidence, correct) =>
              _grade(_wordTrack(w), w.surface, confidence, correct),
        );
      case 'read_verse':
        return _ReadVerseView(card: item.verse!, onContinue: _next);
      case 'done':
        return const _DoneView();
      default:
        return const Center(child: CircularProgressIndicator());
    }
  }
}

/// Headline progress: words/glyphs learned and the share of the OT now readable.
class _ProgressStrip extends StatelessWidget {
  final TutorProgress progress;
  const _ProgressStrip({required this.progress});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = progress.totalVerses == 0 ? 1 : progress.totalVerses;
    final frac = progress.versesReadable / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.wordsKnown} words · ${progress.glyphsKnown} letters',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${progress.versesReadable} / ${progress.totalVerses} verses',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: frac, minHeight: 6),
          ),
        ],
      ),
    );
  }
}

/// Big centred card scaffold shared by the glyph and word views.
class _CardShell extends StatelessWidget {
  final List<Widget> children;
  const _CardShell({required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A button that doubles as a confidence dial. Press and hold, then slide left
/// or right *across the button* to choose how well you knew it — its colour and
/// label track the SM-2 grade (left = Again/Hard, right = Good/Easy) and the
/// grade is committed on release. No separate slider or confirm tap.
class _DragRateButton extends StatefulWidget {
  final String label;
  /// An optional second line under the label (e.g. a vowel's "a as in father").
  final String? subtitle;
  final bool enabled;
  final void Function(int confidence) onCommit;
  /// Fixed colours for a settled, non-interactive state (post-answer feedback).
  final Color? settledColor;
  final Color? settledFg;

  const _DragRateButton({
    required this.label,
    required this.onCommit,
    this.subtitle,
    this.enabled = true,
    this.settledColor,
    this.settledFg,
  });

  @override
  State<_DragRateButton> createState() => _DragRateButtonState();
}

class _DragRateButtonState extends State<_DragRateButton> {
  // A press starts at "Good"; sliding right eases toward Easy, left toward Again.
  static const double _base = 70;
  // How much of the button's width a full-range swing takes (smaller = touchier).
  static const double _span = 120;

  // Non-null while a finger is down: the confidence it currently reads (0..100).
  double? _confidence;
  double _startX = 0;

  void _down(double dx) {
    if (!widget.enabled) return;
    setState(() {
      _startX = dx;
      _confidence = _base;
    });
  }

  void _move(double dx, double width) {
    if (!widget.enabled || _confidence == null) return;
    final c = (_base + (dx - _startX) / width * _span).clamp(0.0, 100.0);
    setState(() => _confidence = c);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pressing = _confidence != null;
    final bucket = pressing ? _confidenceBucket(_confidence!, scheme) : null;
    final bg = bucket?.color ?? widget.settledColor;
    final fg = bucket != null ? Colors.white : widget.settledFg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Listener(
          onPointerDown: (e) => _down(e.localPosition.dx),
          onPointerMove: (e) => _move(e.localPosition.dx, width),
          onPointerUp: (e) {
            final c = _confidence;
            if (c == null) return;
            setState(() => _confidence = null);
            widget.onCommit(c.round());
          },
          onPointerCancel: (_) => setState(() => _confidence = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: bg ?? scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: bg == null
                  ? Border.all(color: scheme.outlineVariant)
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: fg ?? scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: fg ?? scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (pressing) ...[
                  const SizedBox(height: 2),
                  Text(
                    bucket!.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The answer-and-grade machine shared by glyph and word review cards.
///
/// * A freshly-taught card just shows its [answer] and a "Got it" button.
/// * With enough [distractors] (and a [correct] option) it runs a
///   multiple-choice quiz: press and hold the answer you mean, slide across it
///   to set how well you knew it, and release. A correct pick commits at that
///   confidence; a wrong pick reveals the answer and lapses.
/// * Otherwise it self-grades: reveal the [answer], then hold-and-slide a single
///   rate button the same way.
///
/// Each option is a `(label, sub)` record: `label` is the headline (a syllable
/// or word) and `sub` an optional second line (e.g. "a as in father").
typedef _Option = ({String label, String? sub});

class _Grader extends StatefulWidget {
  final bool isNew;
  final String revealLabel;
  final Widget answer;
  /// The right-answer option; null disables the quiz (self-grade only).
  final _Option? correct;
  final List<_Option> distractors;
  final void Function(int confidence, int correct) onGrade;

  const _Grader({
    required this.isNew,
    required this.answer,
    required this.onGrade,
    this.revealLabel = 'Reveal',
    this.correct,
    this.distractors = const [],
  });

  @override
  State<_Grader> createState() => _GraderState();
}

class _GraderState extends State<_Grader> {
  /// Shuffled options for the quiz, or null when self-grading.
  List<_Option>? _options;
  int _correctIndex = 0;
  bool _revealed = false;
  bool _committed = false;
  /// A wrong pick, once released — switches the quiz to its feedback state.
  int? _answeredWrongPick;

  @override
  void initState() {
    super.initState();
    final correct = widget.correct;
    if (widget.isNew || correct == null || correct.label.trim().isEmpty) return;
    final correctLabel = correct.label.trim();
    final seen = <String>{correctLabel.toLowerCase()};
    final options = <_Option>[(label: correctLabel, sub: correct.sub)];
    for (final d in widget.distractors) {
      final t = d.label.trim();
      if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
      options.add((label: t, sub: d.sub));
      if (options.length == 4) break;
    }
    // Three or four options make a worthwhile quiz; fewer self-grades. Glyphs
    // only draw distractors from already-introduced peers, so early on a
    // same-kind pool of two (a three-way choice) is the most we can offer.
    if (options.length < 3) return;
    options.shuffle();
    _options = options;
    _correctIndex = options.indexWhere(
      (o) => o.label.toLowerCase() == correctLabel.toLowerCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isNew) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.answer,
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => widget.onGrade(_gotItConfidence, _notQuiz),
            icon: const Icon(Icons.check),
            label: const Text('Got it'),
          ),
        ],
      );
    }
    final options = _options;
    if (options == null) return _buildSelfGrade(context);
    return _buildQuiz(context, options);
  }

  // Reveal, then hold-and-slide a single rate button to grade.
  Widget _buildSelfGrade(BuildContext context) {
    final theme = Theme.of(context);
    if (!_revealed) {
      return OutlinedButton(
        onPressed: () => setState(() => _revealed = true),
        child: Text(widget.revealLabel),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.answer,
        const SizedBox(height: 24),
        _DragRateButton(
          label: 'Rate it',
          enabled: !_committed,
          onCommit: (c) {
            if (_committed) return;
            _committed = true;
            widget.onGrade(c, _notQuiz);
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Hold and slide to rate how well you knew it',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // Hold an option and slide to set confidence; release commits. A correct pick
  // grades on that confidence; a wrong one reveals the answer and lapses.
  Widget _buildQuiz(BuildContext context, List<_Option> options) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final answeredWrong = _answeredWrongPick != null;

    void release(int i, int confidence) {
      if (_committed || _answeredWrongPick != null) return;
      if (i == _correctIndex) {
        _committed = true;
        widget.onGrade(confidence, _quizCorrect);
      } else {
        setState(() => _answeredWrongPick = i);
      }
    }

    Widget option(int i) {
      // After a wrong answer: the right option turns green, the wrong pick red.
      Color? settled;
      Color? fg;
      if (answeredWrong) {
        if (i == _correctIndex) {
          settled = Colors.green.shade700;
          fg = Colors.white;
        } else if (i == _answeredWrongPick) {
          settled = scheme.error;
          fg = scheme.onError;
        }
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _DragRateButton(
          label: options[i].label,
          subtitle: options[i].sub,
          enabled: !answeredWrong && !_committed,
          settledColor: settled,
          settledFg: fg,
          onCommit: (c) => release(i, c),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) option(i),
        if (!answeredWrong)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Hold your answer, then slide to rate how well you knew it',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (answeredWrong) ...[
          const SizedBox(height: 8),
          Text(
            'Not quite',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          widget.answer,
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => widget.onGrade(0, _quizWrong),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ],
    );
  }
}

/// Teach or review one glyph (consonant or niqqud point).
class _GlyphCard extends StatelessWidget {
  final GlyphCard glyph;
  final bool isNew;
  final void Function(int confidence, int correct) onGrade;

  const _GlyphCard({
    super.key,
    required this.glyph,
    required this.isNew,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = glyphInfo(glyph.glyph);
    final combining = isNiqqud(glyph.glyph);
    // A vowel is taught on an already-learnt host consonant, the mark picked out
    // in colour; other combining points fall back to a dotted-circle carrier.
    final host = glyph.host;
    final onHost = host != null && host.isNotEmpty;
    // What the mark sits on: its host consonant, or a dotted circle. Only used
    // for combining marks; consonants and reading marks show on their own.
    final carrier = onHost ? host : '◌';
    final base = combining ? carrier : glyph.glyph;
    final kind = glyph.isConsonant
        ? 'letter'
        : combining
        ? 'vowel'
        : 'mark';
    // A vowel is taught on a host, so quiz how the syllable *sounds* (not the
    // vowel's name); the distinguishing romanization keeps long/short/sheva
    // apart. Consonants and marks quiz by name (their sounds collide).
    final isVowel = combining && onHost;
    final reviewPrompt = isVowel ? 'How do you say this?' : 'Which $kind is this?';

    return _CardShell(
      children: [
        Text(
          isNew ? 'New $kind' : reviewPrompt,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        // The mark highlighted in colour on its carrier; for a hosted vowel the
        // carrier consonant stays in the normal colour so the new point stands out.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: base),
              if (combining)
                TextSpan(
                  text: glyph.glyph,
                  // Red stands out against the dark consonant far better than the
                  // green theme accent.
                  style: TextStyle(color: Colors.red.shade700),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 120,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        _Grader(
          isNew: isNew,
          // Vowels quiz the syllable sound (with its "as in …" description);
          // consonants/marks quiz the name.
          correct: isVowel
              ? (label: _vowelSyllable(host, glyph.glyph), sub: info?.sound)
              : (info == null ? null : (label: info.name, sub: null)),
          distractors: isVowel
              ? [
                  for (final d in glyph.distractors)
                    (label: _vowelSyllable(host, d), sub: glyphInfo(d)?.sound),
                ]
              : [
                  for (final d in glyph.distractors)
                    (label: glyphInfo(d)?.name ?? d, sub: null),
                ],
          onGrade: onGrade,
          answer: _glyphAnswer(context, info, host, onHost),
        ),
      ],
    );
  }

  Widget _glyphAnswer(
    BuildContext context,
    HebrewLetter? info,
    String? host,
    bool onHost,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onHost) ...[
          // Sound out the (nonsense) syllable, keeping long/short/sheva distinct.
          Text(
            '“${_vowelSyllable(host, glyph.glyph)}”',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (info != null) ...[
          Text(
            '${info.name} · ${info.hebrewName}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            info.sound,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          Text(
            info.example,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontFamily: _hebrewFont,
              fontFamilyFallback: _hebrewFallback,
              fontSize: 30,
            ),
          ),
          Text(
            '${info.exampleTranslit} — ${info.exampleMeaning}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (info.tip != null) ...[
            const SizedBox(height: 12),
            _TipBox(text: info.tip!),
          ],
        ],
      ],
    );
  }
}

/// Teach or review one word (surface form).
class _WordCard extends StatelessWidget {
  final WordCard word;
  final bool isNew;
  final void Function(int confidence, int correct) onGrade;

  const _WordCard({
    super.key,
    required this.word,
    required this.isNew,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The "read" aspect drills pronunciation; the "mean" aspect drills meaning
    // (by which point the word can already be read, so its sound is shown).
    final isRead = word.aspect == 'read';
    final translit = transliterateHebrew(word.surface);
    final gloss =
        kVocabOverrides[vocabKey(word.surface)]?.gloss ??
        (word.gloss.isEmpty ? '—' : word.gloss);

    final prompt = isRead
        ? (isNew ? 'New word — learn to read it' : 'How do you read this?')
        : (isNew ? 'Now learn what it means' : 'What does it mean?');

    return _CardShell(
      children: [
        Text(
          prompt,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          word.surface,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 72,
            height: 1.2,
          ),
        ),
        // Meaning cards keep the pronunciation visible (reading is already
        // known); reading cards hide it (it's the answer) until the grader reveals.
        if (!isRead) ...[
          const SizedBox(height: 4),
          Text(
            translit,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${word.occurrences}× in the Old Testament',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _Grader(
          isNew: isNew,
          revealLabel: isRead ? 'Reveal' : 'Reveal meaning',
          // Reading quizzes on the transliteration (the app transliterates the
          // other surfaces into options); meaning quizzes on the gloss. Either
          // falls back to reveal-and-self-grade when too few options exist.
          correct: (label: isRead ? translit : gloss, sub: null),
          distractors: isRead
              ? [
                  for (final d in word.distractors)
                    (label: transliterateHebrew(d), sub: null),
                ]
              : [for (final d in word.distractors) (label: d, sub: null)],
          onGrade: onGrade,
          answer: isRead
              ? _readAnswer(context, translit)
              : _meanAnswer(context, gloss),
        ),
      ],
    );
  }

  // The answer to a reading card is how to say it.
  Widget _readAnswer(BuildContext context, String translit) => Text(
    translit,
    textAlign: TextAlign.center,
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontStyle: FontStyle.italic),
  );

  Widget _meanAnswer(BuildContext context, String gloss) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          gloss,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (word.morph.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            word.morph,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (word.root.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'root ${word.root}',
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _TipBox extends StatelessWidget {
  final String text;
  const _TipBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Strip cantillation accents (te'amim, U+0591–U+05AF) and meteg (U+05BD) from a
/// verse so the reading view matches the un-accented forms taught on the cards.
/// Vowel points (niqqud) and word separators (space, maqaf) are kept.
String _stripCantillation(String text) {
  final buf = StringBuffer();
  for (final r in text.runes) {
    if (r >= 0x0591 && r <= 0x05AF) continue; // te'amim
    if (r == 0x05BD) continue; // meteg
    buf.writeCharCode(r);
  }
  return buf.toString();
}

/// Short reference label like "Dev 2:2" from a 1-based Haqor book number.
String _refLabel(int book, int chapter, int verse) {
  final name = (book >= 1 && book <= kBooks.length)
      ? kBooks[book - 1].short
      : '$book';
  return '$name $chapter:$verse';
}

/// The reward: a fully-known verse to read for real, plus other now-readable
/// passages sharing its vocabulary. Verse text is fetched on demand.
class _ReadVerseView extends StatefulWidget {
  final VerseCard card;
  final VoidCallback onContinue;
  const _ReadVerseView({required this.card, required this.onContinue});

  @override
  State<_ReadVerseView> createState() => _ReadVerseViewState();
}

class _ReadVerseViewState extends State<_ReadVerseView> {
  StreamSubscription<RustSignalPack<VerseText>>? _sub;
  int _book = 0, _chapter = 0, _verse = 0;
  String? _text;

  @override
  void initState() {
    super.initState();
    _sub = VerseText.rustSignalStream.listen((pack) {
      final m = pack.message;
      if (!mounted) return;
      if (m.book == _book && m.chapter == _chapter && m.verse == _verse) {
        setState(() => _text = m.text);
      }
    });
    _load(widget.card.book, widget.card.chapter, widget.card.verse);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _load(int book, int chapter, int verse) {
    setState(() {
      _book = book;
      _chapter = chapter;
      _verse = verse;
      _text = null;
    });
    GetVerseText(book: book, chapter: chapter, verse: verse).sendSignalToRust();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final examples = widget.card.examples;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.auto_stories, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'You can read this!',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _refLabel(_book, _chapter, _verse),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (_text == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              else ...[
                Text(
                  _stripCantillation(_text!),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontFamily: _hebrewFont,
                    fontFamilyFallback: _hebrewFallback,
                    fontSize: 32,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  transliterateHebrew(_text!),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (examples.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  'Also readable now',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final e in examples)
                      ActionChip(
                        label: Text(_refLabel(e.book, e.chapter, e.verse)),
                        onPressed: () => _load(e.book, e.chapter, e.verse),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: widget.onContinue,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🎉', style: theme.textTheme.displayMedium),
            const SizedBox(height: 16),
            Text(
              'You can read the whole Hebrew Bible!',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Every verse is now made of words you know. Keep reviewing to '
              'keep them fresh.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
