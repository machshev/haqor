import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'alphabet_data.dart';
import 'concept_reference.dart';
import 'intro_content.dart';
import 'loading_message.dart';
import 'study_settings.dart';
import 'transliterate.dart';

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
/// sound plus the vowel's *distinguishing* respelling — a friendly digraph for
/// a long vowel (qamats `ah` vs patah `a`, tsere `ey` vs segol `e`, holam `oh`),
/// breve for a hataf (`ă/ĕ/ŏ`), `ə` for sheva. This is [HebrewLetter.vocalisation]
/// where set, falling back to the scholarly [HebrewLetter.translit] (macron
/// notation) otherwise. [transliterateHebrew] collapses all of this to one of
/// a/e/i/o/u, so vocalisation quizzes build their options from here instead.
String _vowelSyllable(String? host, String vowelGlyph) {
  final consonant = (host == null || host.isEmpty) ? '' : consonantOnset(host);
  final info = glyphInfo(vowelGlyph);
  final vowel = info?.vocalisation ?? info?.translit ?? '';
  return '$consonant$vowel';
}

/// A distractor syllable option from a core `"<consonant><vowel>"` string (two
/// code points: a base consonant then a combining vowel point).
_Option _syllableOption(String syllable) {
  final runes = syllable.runes.toList();
  final consonant = runes.isEmpty ? '' : String.fromCharCode(runes.first);
  final vowel = runes.length > 1 ? String.fromCharCode(runes.last) : '';
  return (label: _vowelSyllable(consonant, vowel), sub: glyphInfo(vowel)?.sound);
}

/// The SRS track for a word card. Words teach only meaning; reading is drilled
/// at the glyph/syllable level, and grammatical form on the `_formTrack`.
const String _wordTrack = 'word';

/// The SRS track for a "which form is this?" drill (tracked separately from a
/// word's meaning).
const String _formTrack = 'form';

/// The SRS track for a pronominal-ending drill (the ending highlighted on a
/// known host word); the review key is the ending's person-gender-number key.
const String _suffixTrack = 'suffix';

/// The single, never-ending spaced-repetition reading flow. The Rust curriculum
/// engine decides every card; this page just renders the current [StudyItem]
/// and reports the learner's answer. Each [SubmitReview] response *is* the next
/// card (one round-trip); a `read_verse`, `explain_mark` or
/// `explain_final_forms` card carries no grade, so we advance past it with
/// another [GetNextStudyItem].
class StudyFlowPage extends StatefulWidget {
  const StudyFlowPage({super.key});

  @override
  State<StudyFlowPage> createState() => _StudyFlowPageState();
}

class _StudyFlowPageState extends State<StudyFlowPage> {
  StreamSubscription<RustSignalPack<StudyItem>>? _sub;
  StudyItem? _item;
  // Bumped on every delivered card. The engine legitimately re-serves the same
  // card back-to-back (it pulls an in-learning card forward to keep drilling),
  // so a content-derived key can repeat — and a repeated key makes Flutter reuse
  // the answer-and-grade State, leaving a just-committed quiz frozen. Keying the
  // card subtree by this counter guarantees a fresh grader for every card.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _sub = StudyItem.rustSignalStream.listen((pack) {
      debugPrint('card shown: ${pack.message}');
      if (!mounted) return;
      setState(() {
        _item = pack.message;
        _seq++;
      });
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

  /// Demote each misread word (an "Again" grade lapses it back into review)
  /// instead of gating the whole verse on one blanket grade — flagging a
  /// shared word can re-lock other verses that depend on it too. With
  /// nothing flagged, just move on.
  void _submitMisread(List<String> words) {
    if (words.isEmpty) {
      _next();
      return;
    }
    for (final w in words) {
      _grade(_wordTrack, w, 0, _notQuiz);
    }
  }

  void _showStats() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _StatsSheet(),
  );

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
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Reference',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConceptReferencePage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Statistics',
            onPressed: _showStats,
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Study pace',
            onPressed: () => showStudySettings(context),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Reset progress',
            onPressed: _confirmReset,
          ),
        ],
      ),
      body: item == null
          ? const Center(
              child: LoadingMessage(text: 'Preparing your first lesson…'),
            )
          : Column(
              children: [
                _ProgressStrip(progress: item.progress),
                // Key by the delivery counter so every card — even one whose
                // content matches the previous card — gets a fresh subtree, and
                // the grader never inherits a stale (committed) quiz State.
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(_seq),
                    child: _buildItem(context, item),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildItem(BuildContext context, StudyItem item) {
    switch (item.kind) {
      case 'new_glyph':
      case 'review_glyph':
        final g = item.glyph!;
        // A vowel is drilled as a whole syllable (vowel on a host consonant), so
        // grade the syllable — the core credits every glyph in it, not just the
        // vowel. Consonants and marks grade their single glyph.
        final host = g.host;
        final key = (host != null && host.isNotEmpty) ? '$host${g.glyph}' : g.glyph;
        return _GlyphCard(
          key: ValueKey('glyph:${g.glyph}:${item.kind}'),
          glyph: g,
          isNew: item.kind == 'new_glyph',
          onGrade: (confidence, correct) =>
              _grade('glyph', key, confidence, correct),
        );
      case 'new_word':
      case 'review_word':
        final w = item.word!;
        return _WordCard(
          key: ValueKey('word:${w.surface}:${item.kind}'),
          word: w,
          isNew: item.kind == 'new_word',
          onGrade: (confidence, correct) =>
              _grade(_wordTrack, w.surface, confidence, correct),
        );
      case 'new_form':
      case 'review_form':
        final w = item.word!;
        return _WordCard(
          key: ValueKey('form:${w.surface}:${item.kind}'),
          word: w,
          isNew: item.kind == 'new_form',
          isForm: true,
          onGrade: (confidence, correct) =>
              _grade(_formTrack, w.surface, confidence, correct),
        );
      case 'new_suffix':
      case 'review_suffix':
        final s = item.suffix!;
        return _SuffixCard(
          key: ValueKey('suffix:${s.key}:${s.surface}:${item.kind}'),
          card: s,
          isNew: item.kind == 'new_suffix',
          onGrade: (confidence, correct) =>
              _grade(_suffixTrack, s.key, confidence, correct),
        );
      case 'explain_mark':
        return _ExplainMarkView(glyph: item.glyph!, onContinue: _next);
      case 'explain_intro':
        return _ExplainIntroView(introKey: item.intro!, onContinue: _next);
      case 'explain_final_forms':
        return _ExplainFinalFormsView(glyph: item.glyph!, onContinue: _next);
      case 'explain_grammar':
        return _GrammarInfoView(
          key: ValueKey('grammar:${item.grammar!.concept}'),
          card: item.grammar!,
          onContinue: _next,
        );
      case 'read_verse':
        return _ReadVerseView(
          card: item.verse!,
          onContinue: _next,
          onMisread: _submitMisread,
        );
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
                '${progress.wordsKnown} words · ${progress.lettersKnown} letters · ${progress.vowelsKnown} vowels',
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

/// On-demand spaced-repetition stats. Fetches [TutorStats] once when opened and
/// updates live if a fresh one arrives (e.g. after a review while it's open).
class _StatsSheet extends StatefulWidget {
  const _StatsSheet();

  @override
  State<_StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<_StatsSheet> {
  StreamSubscription<RustSignalPack<TutorStats>>? _sub;
  // Seed with the last value received so the numbers show instantly on reopen.
  TutorStats? _stats = TutorStats.latestRustSignal?.message;

  @override
  void initState() {
    super.initState();
    _sub = TutorStats.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() => _stats = pack.message);
    });
    GetTutorStats().sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _stats;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: s == null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your progress',
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Today at a glance.
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          icon: Icons.local_fire_department,
                          value: '${s.streakDays}',
                          label: 'day streak',
                          highlight: s.streakDays > 0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.today_outlined,
                          value: '${s.reviewsToday}',
                          label: 'reviews today',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.schedule,
                          value: '${s.glyphsDue + s.wordsDue}',
                          label: 'due now',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _StatRow(
                    label: 'Letters',
                    known: s.lettersMature,
                    total: s.lettersSeen,
                    learning: s.lettersLearning,
                  ),
                  const SizedBox(height: 12),
                  _StatRow(
                    label: 'Vowels',
                    known: s.vowelsMature,
                    total: s.vowelsSeen,
                    learning: s.vowelsLearning,
                  ),
                  const SizedBox(height: 12),
                  _StatRow(
                    label: 'Words',
                    known: s.wordsMature,
                    total: s.wordsSeen,
                    learning: s.wordsLearning,
                  ),
                  const SizedBox(height: 12),
                  _StatRow(
                    label: 'Verses readable',
                    known: s.versesReadable,
                    total: s.totalVerses,
                  ),
                  const Divider(height: 32),
                  _StatLine(
                    label: 'Recall accuracy',
                    value: s.reviewsTotal == 0 ? '—' : '${s.accuracyPct}%',
                  ),
                  const SizedBox(height: 8),
                  _StatLine(
                    label: 'Reviews all-time',
                    value: '${s.reviewsTotal}',
                  ),
                ],
              ),
      ),
    );
  }
}

/// A compact icon-over-number tile for the "today" summary row.
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool highlight;
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = highlight ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: highlight ? scheme.primary : null,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled "known / total" progress bar with an optional in-learning count.
class _StatRow extends StatelessWidget {
  final String label;
  final int known;
  final int total;
  final int? learning;
  const _StatRow({
    required this.label,
    required this.known,
    required this.total,
    this.learning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final frac = total == 0 ? 0.0 : known / total;
    final learnNote = (learning != null && learning! > 0)
        ? '  ·  ${learning!} learning'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            Text(
              '$known / $total$learnNote',
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
    );
  }
}

/// A simple label-and-value line for the summary figures.
class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  const _StatLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    // Three or four options make a worthwhile quiz; fewer self-grades. The
    // core prefers already-introduced peers as distractors and tops up from
    // upcoming glyphs/meanings, so this is only a safety net.
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
    // Highlight the mark in red only when *teaching* it (a new card); on a vowel
    // review the whole syllable is being tested, so show it in one colour.
    final highlightMark = combining && !(isVowel && !isNew);
    // A final form is taught with its medial base alongside — the familiar
    // shape first, the new end-of-word shape picked out in red (mirroring how
    // a new vowel is highlighted on its host). Reviews show the glyph alone:
    // the medial form would give the letter's name away.
    final medial = medialForm(glyph.glyph);
    final teachFinal = isNew && medial != null;

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
        // The mark highlighted in colour on its carrier while teaching; on a
        // vowel review the whole syllable stays one colour (it's all being read).
        Text.rich(
          TextSpan(
            children: [
              if (teachFinal) ...[
                TextSpan(text: '$medial '),
                TextSpan(
                  text: glyph.glyph,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ] else ...[
                TextSpan(text: base),
                if (highlightMark)
                  TextSpan(
                    text: glyph.glyph,
                    // Red stands out against the dark consonant far better than
                    // the green theme accent.
                    style: TextStyle(color: Colors.red.shade700),
                  )
                else if (combining)
                  TextSpan(text: glyph.glyph),
              ],
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
          // Vowels are quizzed by syllable sound, consonants/marks by name;
          // either way each option shows its "… as in …" pronunciation.
          correct: isVowel
              ? (label: _vowelSyllable(host, glyph.glyph), sub: info?.sound)
              : (info == null ? null : (label: info.name, sub: info.sound)),
          distractors: isVowel
              ? [for (final d in glyph.distractors) _syllableOption(d)]
              : [
                  for (final d in glyph.distractors)
                    (label: glyphInfo(d)?.name ?? d, sub: glyphInfo(d)?.sound),
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
  /// A "which grammatical form is this?" drill rather than a meaning card. The
  /// answer (`word.gloss`) is the inflected form and the distractors are other
  /// inflections of the same word.
  final bool isForm;
  final void Function(int confidence, int correct) onGrade;

  const _WordCard({
    super.key,
    required this.word,
    required this.isNew,
    this.isForm = false,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Words teach only meaning; by now the word can already be sounded out (all
    // its glyphs are known), so its pronunciation is shown alongside.
    final translit = transliterateHebrew(word.surface);
    // The core already applies curated overrides and inflection; the app just
    // presents word.gloss / word.inflected / word.note.
    final gloss = word.gloss.isEmpty ? '—' : word.gloss;

    final prompt = isForm
        ? (isNew ? 'Now learn this form' : 'Which form is this?')
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
        const SizedBox(height: 4),
        Text(
          translit,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
          revealLabel: isForm ? 'Reveal form' : 'Reveal meaning',
          // The quiz picks the answer from other plausible options, falling back
          // to reveal-and-self-grade when too few options exist.
          correct: (label: gloss, sub: null),
          distractors: [for (final d in word.distractors) (label: d, sub: null)],
          onGrade: onGrade,
          answer: _meanAnswer(context, gloss),
        ),
      ],
    );
  }

  Widget _meanAnswer(BuildContext context, String gloss) {
    final theme = Theme.of(context);
    // The core supplies the inflected form ("and he said") only when it adds
    // something over the base gloss (empty for curated / function words).
    final inflected =
        (word.inflected.isNotEmpty &&
            word.inflected.toLowerCase() != word.gloss.toLowerCase())
        ? word.inflected
        : null;
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
        if (inflected != null) ...[
          const SizedBox(height: 6),
          Text(
            'this form: “$inflected”',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
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
        if (word.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          _TipBox(text: word.note),
        ],
      ],
    );
  }
}

/// Teach or review a pronominal ending, shown in red on a host word the
/// learner already knows — the same highlight a new vowel gets on its host
/// consonant. Reviews rotate the host, so the ending (not one word's shape)
/// is what's being tested; the quiz asks which pronoun it stands for.
class _SuffixCard extends StatelessWidget {
  final SuffixCard card;
  final bool isNew;
  final void Function(int confidence, int correct) onGrade;

  const _SuffixCard({
    super.key,
    required this.card,
    required this.isNew,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final translit = transliterateHebrew(card.surface);

    return _CardShell(
      children: [
        Text(
          isNew ? 'New word ending' : 'Who is the red ending?',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        // The host word with the ending's span picked out in red.
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: card.stem),
              TextSpan(
                text: card.suffix,
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 72,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          translit,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _Grader(
          isNew: isNew,
          revealLabel: 'Reveal pronoun',
          correct: (label: card.meaning, sub: null),
          distractors: [
            for (final d in card.distractors) (label: d, sub: null),
          ],
          onGrade: onGrade,
          answer: _suffixAnswer(context),
        ),
      ],
    );
  }

  Widget _suffixAnswer(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          card.meaning,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (card.gloss.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${card.surface} — “${card.gloss}”',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontStyle: FontStyle.italic,
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

/// Short reference label like "Dev 2:2" from a 1-based Haqor book number.
String refLabel(int book, int chapter, int verse) {
  final name = (book >= 1 && book <= kBooks.length)
      ? kBooks[book - 1].short
      : '$book';
  return '$name $chapter:$verse';
}

/// The reward: a fully-known verse to read for real, plus other now-readable
/// passages sharing its vocabulary. Verse text is fetched on demand.
/// Explain a reading mark (sof pasuq, maqaf) the first time a verse needs it.
/// Unlike a letter or vowel it carries no sound of its own, so it is shown
/// once with an explanation and never drilled — no grading, just a Continue
/// button, like [_ReadVerseView].
class _ExplainMarkView extends StatelessWidget {
  final GlyphCard glyph;
  final VoidCallback onContinue;
  const _ExplainMarkView({required this.glyph, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = glyphInfo(glyph.glyph);
    return _CardShell(
      children: [
        Text(
          'Reading mark',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          glyph.glyph,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 96,
            height: 1.2,
          ),
        ),
        if (info != null) ...[
          const SizedBox(height: 16),
          Text(
            info.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            info.sound,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (info.tip != null) ...[
            const SizedBox(height: 12),
            Text(
              info.tip!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            info.example,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontFamily: _hebrewFont,
              fontFamilyFallback: _hebrewFallback,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${info.exampleTranslit} — ${info.exampleMeaning}',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
        ),
      ],
    );
  }
}

/// One card of the language-intro deck (reading direction, the alphabet, the
/// vowel points), shown once each before anything else is taught. The content
/// lives in [IntroCardBody], shared with the reference page. Gradeless, like
/// [_ExplainMarkView].
class _ExplainIntroView extends StatelessWidget {
  final String introKey;
  final VoidCallback onContinue;
  const _ExplainIntroView({required this.introKey, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      children: [
        Text(
          'Before we start',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          introTitle(introKey),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        IntroCardBody(introKey: introKey),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
        ),
      ],
    );
  }
}

/// A one-time explanation of the final-forms concept, shown before the first
/// final-form letter is introduced: five letters change shape at the end of a
/// word. Leads with the pair about to be met (medial base, then the final
/// form in red), then lists all five pairs. Gradeless, like [_ExplainMarkView].
class _ExplainFinalFormsView extends StatelessWidget {
  final GlyphCard glyph;
  final VoidCallback onContinue;
  const _ExplainFinalFormsView({required this.glyph, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final medial = medialForm(glyph.glyph);
    final red = TextStyle(color: Colors.red.shade700);
    return _CardShell(
      children: [
        Text(
          'Final letters',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        // The pair the learner is about to meet, the new shape in red.
        Text.rich(
          TextSpan(
            children: [
              if (medial != null) TextSpan(text: '$medial '),
              TextSpan(text: glyph.glyph, style: red),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 96,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          kFinalFormsExplanation,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        // All five pairs, medial then final (reading order), finals in red.
        const FinalFormsPairs(),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
        ),
      ],
    );
  }
}

/// A one-time grammar concept card, illustrated by the word about to be learnt.
/// Gradeless: acknowledged with a single Continue button, like [_ExplainMarkView].
class _GrammarInfoView extends StatelessWidget {
  final GrammarCard card;
  final VoidCallback onContinue;
  const _GrammarInfoView({super.key, required this.card, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = card.example;
    final exampleGloss = w.inflected.isNotEmpty ? w.inflected : w.gloss;
    return _CardShell(
      children: [
        Text(
          'Grammar',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          card.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        // The word the learner is about to meet, as the live illustration.
        Text(
          w.surface,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 56,
            height: 1.2,
          ),
        ),
        if (exampleGloss.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            exampleGloss,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          card.explanation,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        if (card.formula.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TipBox(text: card.formula),
        ],
        if (card.examples.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final ex in card.examples)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                ex,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: _hebrewFont,
                  fontFamilyFallback: _hebrewFallback,
                  fontSize: 20,
                ),
              ),
            ),
        ],
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Continue'),
        ),
      ],
    );
  }
}

class _ReadVerseView extends StatefulWidget {
  final VerseCard card;
  final VoidCallback onContinue;
  /// Called with the surfaces (word-track keys) the learner flagged as
  /// misread, so the app can demote just those instead of gating the whole
  /// verse on one blanket grade.
  final void Function(List<String> misread) onMisread;
  const _ReadVerseView({
    required this.card,
    required this.onContinue,
    required this.onMisread,
  });

  @override
  State<_ReadVerseView> createState() => _ReadVerseViewState();
}

class _ReadVerseViewState extends State<_ReadVerseView> {
  StreamSubscription<RustSignalPack<VerseText>>? _sub;
  int _book = 0, _chapter = 0, _verse = 0;
  String? _text;
  // Null while the learner hasn't answered "could you read this?" yet; once
  // set to false, the word picker is shown for flagging misread words.
  bool? _readOk;
  final Set<int> _misread = {};

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
      _readOk = null;
      _misread.clear();
    });
    GetVerseText(book: book, chapter: chapter, verse: verse).sendSignalToRust();
  }

  void _finish() {
    final flagged = [for (final i in _misread) widget.card.words[i]];
    widget.onMisread(flagged);
  }

  bool _isName(int wordIndex) {
    final names = widget.card.names;
    return wordIndex < names.length && names[wordIndex];
  }

  /// Whether the verse being displayed is the card's own verse (an example
  /// chip can swap in another passage, whose words the card doesn't describe).
  bool get _onCardVerse =>
      _book == widget.card.book &&
      _chapter == widget.card.chapter &&
      _verse == widget.card.verse;

  /// The verse text as spans with proper names coloured. A word unit ends at
  /// whitespace or a maqaf, aligning units with [VerseCard.words] (units
  /// without a Hebrew letter — a trailing sof pasuq — belong to no word).
  /// Falls back to one plain span if the alignment doesn't work out.
  List<TextSpan> _verseSpans(String text, TextStyle base, Color nameColor) {
    final words = widget.card.words;
    final names = widget.card.names;
    if (!_onCardVerse || names.length != words.length || !names.contains(true)) {
      return [TextSpan(text: text, style: base)];
    }
    final spans = <TextSpan>[];
    var wordIndex = 0;
    var aligned = true;
    final unit = StringBuffer();
    void flush() {
      if (unit.isEmpty) return;
      final s = unit.toString();
      unit.clear();
      final hasLetter = s.runes.any((r) => r >= 0x05D0 && r <= 0x05EA);
      var name = false;
      if (hasLetter) {
        if (wordIndex < names.length) {
          name = names[wordIndex];
          wordIndex++;
        } else {
          aligned = false;
        }
      }
      spans.add(
        TextSpan(text: s, style: name ? base.copyWith(color: nameColor) : base),
      );
    }

    for (final r in text.runes) {
      unit.write(String.fromCharCode(r));
      if (r == 0x20 || r == 0x05BE) flush(); // space or maqaf ends a word
    }
    flush();
    if (!aligned || wordIndex != words.length) {
      return [TextSpan(text: text, style: base)];
    }
    return spans;
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
                refLabel(_book, _chapter, _verse),
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
                Text.rich(
                  TextSpan(
                    children: _verseSpans(
                      stripCantillation(_text!),
                      const TextStyle(
                        fontFamily: _hebrewFont,
                        fontFamilyFallback: _hebrewFallback,
                        fontSize: 32,
                        height: 1.7,
                      ),
                      theme.colorScheme.tertiary,
                    ),
                  ),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.rtl,
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
                if (_onCardVerse && widget.card.names.contains(true)) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Coloured words are names',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
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
                        label: Text(refLabel(e.book, e.chapter, e.verse)),
                        onPressed: () => _load(e.book, e.chapter, e.verse),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              if (_text != null && _readOk != false) ...[
                Text(
                  'Could you read that?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _readOk = false),
                      icon: const Icon(Icons.close),
                      label: const Text('No'),
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: widget.onContinue,
                      icon: const Icon(Icons.check),
                      label: const Text('Yes'),
                    ),
                  ],
                ),
              ] else if (_readOk == false) ...[
                Text(
                  'Tap any words you misread',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  textDirection: TextDirection.rtl,
                  children: [
                    for (final (i, w) in widget.card.words.indexed)
                      FilterChip(
                        label: Text(
                          stripCantillation(w),
                          style: TextStyle(
                            fontFamily: _hebrewFont,
                            fontFamilyFallback: _hebrewFallback,
                            fontSize: 18,
                            color: _isName(i)
                                ? theme.colorScheme.tertiary
                                : null,
                          ),
                        ),
                        selected: _misread.contains(i),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _misread.add(i);
                          } else {
                            _misread.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continue'),
                ),
              ],
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
