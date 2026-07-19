import 'package:flutter/material.dart';

import 'alphabet_data.dart';

/// Teaching content for the one-time language-intro deck the core serves
/// before anything else (`explain_intro` study items, keys `intro_rtl`,
/// `intro_alphabet` and `intro_vowels`), shared between the study-flow card
/// and the reference page. The core only tracks *that* a card was shown; the
/// content itself is presentation and lives here.

const String _hebrewFont = 'Cardo';
const List<String> _hebrewFallback = ['Noto Serif Hebrew'];

/// Display title for an intro-card key (empty for an unknown key).
String introTitle(String introKey) {
  switch (introKey) {
    case 'intro_rtl':
      return 'Hebrew reads right to left';
    case 'intro_alphabet':
      return 'The alphabet';
    case 'intro_vowels':
      return 'The vowel points';
    default:
      return '';
  }
}

/// The body of one intro card — the illustration plus its explanation —
/// without a title or Continue button, so it can sit inside the study-flow
/// card shell or a reference-page tile alike.
class IntroCardBody extends StatelessWidget {
  final String introKey;
  const IntroCardBody({super.key, required this.introKey});

  @override
  Widget build(BuildContext context) {
    switch (introKey) {
      case 'intro_rtl':
        return const _RtlBody();
      case 'intro_alphabet':
        return const _AlphabetBody();
      case 'intro_vowels':
        return const _VowelsBody();
      default:
        return const SizedBox.shrink();
    }
  }
}

class _RtlBody extends StatelessWidget {
  const _RtlBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The very first words of the Bible, with the reading direction shown.
        const Text(
          'בְּרֵאשִׁית בָּרָא אֱלֹהִים',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 36,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_back, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'read this way',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Hebrew is written and read from right to left — the opposite '
          'direction to English. The first word of a verse is the rightmost '
          'one, and a Hebrew Bible opens from what feels to an English '
          'reader like the back cover.\n\n'
          'Everything in these lessons appears exactly as it does in the '
          'Bible, so your eye gets used to the direction from the very '
          'first letter.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _AlphabetBody extends StatelessWidget {
  const _AlphabetBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Hebrew has 22 letters, and every one of them is a consonant. '
          'There are no capital or small letters — each letter has a single '
          'form. (A few put on a special shape at the end of a word; you will '
          'meet those later.)',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        // The whole alphabet in reading (right-to-left) order — a preview,
        // not something to memorise now.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          textDirection: TextDirection.rtl,
          children: [
            for (final l in kAlphabet)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.letter,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: _hebrewFont,
                      fontFamilyFallback: _hebrewFallback,
                      fontSize: 28,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    l.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'There is no need to memorise this table: the tutor introduces '
          'each letter as a real verse needs it, and keeps quizzing it until '
          'it sticks.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _VowelsBody extends StatelessWidget {
  const _VowelsBody();

  /// The same consonant (mem) under five different vowel points — the vowel
  /// mark, not the letter, is what changes the sound.
  static const List<({String syllable, String sound})> _demo = [
    (syllable: 'מַ', sound: 'ma'),
    (syllable: 'מֵ', sound: 'me'),
    (syllable: 'מִ', sound: 'mi'),
    (syllable: 'מֹ', sound: 'mo'),
    (syllable: 'מוּ', sound: 'mu'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'The letters write only consonants. The vowels are small dots and '
          'dashes (niqqud) placed under, above or inside a letter — the same '
          'letter reads differently depending on its vowel mark:',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 20,
          runSpacing: 8,
          textDirection: TextDirection.rtl,
          children: [
            for (final d in _demo)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.syllable,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontFamily: _hebrewFont,
                      fontFamilyFallback: _hebrewFallback,
                      fontSize: 40,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    d.sound,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'The Bible was first written with no vowel signs at all; the '
          'points were added centuries later to preserve the traditional '
          'pronunciation. Like the letters, each vowel is taught as its own '
          'card — always on a letter you already know, so you learn it as a '
          'spoken syllable.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}

/// The five medial–final letter pairs (finals in red), reading order — the
/// illustration shared by the final-forms study card and the reference page.
class FinalFormsPairs extends StatelessWidget {
  const FinalFormsPairs({super.key});

  @override
  Widget build(BuildContext context) {
    final red = TextStyle(color: Colors.red.shade700);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      runSpacing: 8,
      children: [
        for (final l in kAlphabet)
          if (l.finalForm != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${l.letter} '),
                  TextSpan(text: l.finalForm, style: red),
                ],
              ),
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontFamily: _hebrewFont,
                fontFamilyFallback: _hebrewFallback,
                fontSize: 32,
              ),
            ),
      ],
    );
  }
}

/// The final-forms explanation shared by the study card and reference page.
const String kFinalFormsExplanation =
    'Five letters put on a different shape when they come last in a word. '
    'The sound stays exactly the same — only the shape changes. Each final '
    'form is learnt as its own letter.';
