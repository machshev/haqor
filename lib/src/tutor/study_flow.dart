import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import 'alphabet_data.dart';
import 'transliterate.dart';
import 'vocab_overrides.dart';

/// SM-2 grades, matching the Rust `Grade` enum order (0..3).
const int _again = 0;
const int _hard = 1;
const int _good = 2;
const int _easy = 3;

const String _hebrewFont = 'Cardo';
const List<String> _hebrewFallback = ['Noto Serif Hebrew'];

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
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _sub = StudyItem.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() {
        _item = pack.message;
        _revealed = false;
      });
    });
    GetNextStudyItem().sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _grade(String track, String key, int grade) =>
      SubmitReview(track: track, key: key, grade: grade).sendSignalToRust();

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
        return _GlyphCard(
          glyph: item.glyph!,
          isNew: true,
          revealed: true,
          onReveal: () {},
          onGrade: (g) => _grade('glyph', item.glyph!.glyph, g),
        );
      case 'review_glyph':
        return _GlyphCard(
          glyph: item.glyph!,
          isNew: false,
          revealed: _revealed,
          onReveal: () => setState(() => _revealed = true),
          onGrade: (g) => _grade('glyph', item.glyph!.glyph, g),
        );
      case 'new_word':
        return _WordCard(
          word: item.word!,
          isNew: true,
          revealed: true,
          onReveal: () {},
          onGrade: (g) => _grade('word', item.word!.surface, g),
        );
      case 'review_word':
        return _WordCard(
          word: item.word!,
          isNew: false,
          revealed: _revealed,
          onReveal: () => setState(() => _revealed = true),
          onGrade: (g) => _grade('word', item.word!.surface, g),
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

/// Four SM-2 grade buttons (or a single "Got it" for a freshly-taught card).
class _GradeButtons extends StatelessWidget {
  final void Function(int grade) onGrade;
  final bool firstExposure;
  const _GradeButtons({required this.onGrade, this.firstExposure = false});

  @override
  Widget build(BuildContext context) {
    if (firstExposure) {
      return FilledButton.icon(
        onPressed: () => onGrade(_good),
        icon: const Icon(Icons.check),
        label: const Text('Got it'),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    Widget btn(String label, int grade, Color color) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => onGrade(grade),
          child: Text(label),
        ),
      ),
    );
    return Row(
      children: [
        btn('Again', _again, scheme.error),
        btn('Hard', _hard, Colors.orange.shade700),
        btn('Good', _good, Colors.green.shade700),
        btn('Easy', _easy, Colors.blue.shade700),
      ],
    );
  }
}

/// Teach or review one glyph (consonant or niqqud point).
class _GlyphCard extends StatelessWidget {
  final GlyphCard glyph;
  final bool isNew;
  final bool revealed;
  final VoidCallback onReveal;
  final void Function(int grade) onGrade;

  const _GlyphCard({
    required this.glyph,
    required this.isNew,
    required this.revealed,
    required this.onReveal,
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
        if (onHost) ...[
          const SizedBox(height: 8),
          // Sound out the (nonsense) syllable so the vowel's sound is clear.
          Text(
            '“${transliterateHebrew('$host${glyph.glyph}')}”',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (isNew || revealed) ...[
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
          const SizedBox(height: 24),
          _GradeButtons(onGrade: onGrade, firstExposure: isNew),
        ] else
          OutlinedButton(
            onPressed: onReveal,
            child: const Text('Reveal'),
          ),
      ],
    );
  }
}

/// Teach or review one word (surface form).
class _WordCard extends StatelessWidget {
  final WordCard word;
  final bool isNew;
  final bool revealed;
  final VoidCallback onReveal;
  final void Function(int grade) onGrade;

  const _WordCard({
    required this.word,
    required this.isNew,
    required this.revealed,
    required this.onReveal,
    required this.onGrade,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Prefer a curated learner gloss for the head of the frequency list.
    final gloss =
        kVocabOverrides[vocabKey(word.surface)]?.gloss ??
        (word.gloss.isEmpty ? '—' : word.gloss);

    return _CardShell(
      children: [
        Text(
          isNew ? 'New word' : 'What does this mean?',
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
        // Always shown (even before the meaning is revealed) so the learner can
        // sound the word out — that's the reading skill being practised.
        Text(
          transliterateHebrew(word.surface),
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
        if (isNew || revealed) ...[
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
          // On the rare new word that still carries unintroduced glyphs, show
          // them so nothing is unfamiliar before the drill.
          if (word.newGlyphs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final g in word.newGlyphs)
                  Chip(
                    label: Text(
                      isNiqqud(g.glyph) ? '◌${g.glyph}' : g.glyph,
                      style: const TextStyle(
                        fontFamily: _hebrewFont,
                        fontFamilyFallback: _hebrewFallback,
                        fontSize: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          _GradeButtons(onGrade: onGrade, firstExposure: isNew),
        ] else
          OutlinedButton(
            onPressed: onReveal,
            child: const Text('Reveal meaning'),
          ),
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
