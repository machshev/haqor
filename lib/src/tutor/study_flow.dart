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
  if (c < 25) return (label: 'Again', color: scheme.error);
  if (c < 55) return (label: 'Hard', color: Colors.orange.shade700);
  if (c < 85) return (label: 'Good', color: Colors.green.shade700);
  return (label: 'Easy', color: Colors.blue.shade700);
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

/// A confidence slider that maps to an SM-2 grade on submit. Used to self-grade
/// a revealed card, and to rate a correct multiple-choice answer. The live label
/// shows which grade the current position lands in.
class _ConfidenceSlider extends StatefulWidget {
  /// `_notQuiz` (self-grade) or `_quizCorrect` (rating a correct pick).
  final int correct;
  final void Function(int confidence, int correct) onGrade;
  const _ConfidenceSlider({required this.correct, required this.onGrade});

  @override
  State<_ConfidenceSlider> createState() => _ConfidenceSliderState();
}

class _ConfidenceSliderState extends State<_ConfidenceSlider> {
  // Start in the middle of "Good": the honest default for a card you recalled.
  double _value = 70;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bucket = _confidenceBucket(_value, theme.colorScheme);
    Widget edge(String t) => Text(
      t,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How well did you know it?',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          bucket.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: bucket.color,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            edge('Forgot'),
            Expanded(
              child: Slider(
                value: _value,
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: bucket.color,
                label: bucket.label,
                onChanged: (v) => setState(() => _value = v),
              ),
            ),
            edge('Easy'),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: bucket.color,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => widget.onGrade(_value.round(), widget.correct),
          child: Text('Submit · ${bucket.label}'),
        ),
      ],
    );
  }
}

/// The answer-and-grade machine shared by glyph and word review cards.
///
/// * A freshly-taught card just shows its [answer] and a "Got it" button.
/// * With enough [distractorLabels] (and a [correctLabel]) it runs a
///   multiple-choice quiz: pick an option, see the answer, then a correct pick
///   is rated on the confidence slider while a wrong pick always lapses.
/// * Otherwise it self-grades: reveal the [answer], then rate it on the slider.
class _Grader extends StatefulWidget {
  final bool isNew;
  final String revealLabel;
  final Widget answer;
  /// The right-answer option label; null disables the quiz (self-grade only).
  final String? correctLabel;
  final List<String> distractorLabels;
  final void Function(int confidence, int correct) onGrade;

  const _Grader({
    required this.isNew,
    required this.answer,
    required this.onGrade,
    this.revealLabel = 'Reveal',
    this.correctLabel,
    this.distractorLabels = const [],
  });

  @override
  State<_Grader> createState() => _GraderState();
}

class _GraderState extends State<_Grader> {
  /// Shuffled options for the quiz, or null when self-grading.
  List<String>? _options;
  int _correctIndex = 0;
  bool _revealed = false;
  int? _picked;

  @override
  void initState() {
    super.initState();
    final correct = widget.correctLabel?.trim();
    if (widget.isNew || correct == null || correct.isEmpty) return;
    final seen = <String>{correct.toLowerCase()};
    final options = <String>[correct];
    for (final d in widget.distractorLabels) {
      final t = d.trim();
      if (t.isEmpty || !seen.add(t.toLowerCase())) continue;
      options.add(t);
      if (options.length == 4) break;
    }
    // Need a full four-way choice for the quiz to be worthwhile.
    if (options.length < 4) return;
    options.shuffle();
    _options = options;
    _correctIndex = options.indexOf(correct);
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

  // Reveal, then rate on the confidence slider.
  Widget _buildSelfGrade(BuildContext context) {
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
        _ConfidenceSlider(correct: _notQuiz, onGrade: widget.onGrade),
      ],
    );
  }

  // Pick an option, then see the answer and grade.
  Widget _buildQuiz(BuildContext context, List<String> options) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final picked = _picked;
    final answered = picked != null;
    final gotItRight = picked == _correctIndex;

    Widget option(int i) {
      // Before answering: plain tappable choices. After: the right answer turns
      // green and a wrong pick turns red, so the mistake is clear.
      Color? bg;
      Color? fg;
      if (answered) {
        if (i == _correctIndex) {
          bg = Colors.green.shade700;
          fg = Colors.white;
        } else if (i == picked) {
          bg = scheme.error;
          fg = scheme.onError;
        }
      }
      final style = answered
          ? FilledButton.styleFrom(
              backgroundColor: bg ?? scheme.surfaceContainerHighest,
              foregroundColor: fg ?? scheme.onSurfaceVariant,
              disabledBackgroundColor: bg ?? scheme.surfaceContainerHighest,
              disabledForegroundColor: fg ?? scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(vertical: 14),
            )
          : null;
      final child = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SizedBox(
          width: double.infinity,
          child: answered
              ? FilledButton(
                  onPressed: null,
                  style: style,
                  child: Text(options[i], textAlign: TextAlign.center),
                )
              : OutlinedButton(
                  onPressed: () => setState(() {
                    _picked = i;
                    _revealed = true;
                  }),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(options[i], textAlign: TextAlign.center),
                ),
        ),
      );
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) option(i),
        if (answered) ...[
          const SizedBox(height: 8),
          Text(
            gotItRight ? 'Correct' : 'Not quite',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: gotItRight ? Colors.green.shade700 : scheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          widget.answer,
          const SizedBox(height: 24),
          if (gotItRight)
            _ConfidenceSlider(correct: _quizCorrect, onGrade: widget.onGrade)
          else
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

    return _CardShell(
      children: [
        Text(
          isNew ? 'New $kind' : 'Which $kind is this?',
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
          // Quiz on the glyph's name; only when we have a name to show.
          correctLabel: info?.name,
          distractorLabels: [
            for (final d in glyph.distractors) glyphInfo(d)?.name ?? d,
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
          // Sound out the (nonsense) syllable so the vowel's sound is clear.
          Text(
            '“${transliterateHebrew('$host${glyph.glyph}')}”',
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
          // Quiz only meaning cards (multiple-choice on the gloss); reading is
          // a spoken skill, so it stays a reveal-and-self-grade card.
          correctLabel: isRead ? null : gloss,
          distractorLabels: word.distractors,
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
