import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

/// A set of settings to suit how much Hebrew the reader brings.
///
/// Applied once and forgotten: a preset is a quick way to set many settings
/// at once, each of which the reader can then refine on its own. Nothing
/// remembers which was chosen, so nothing overrides the refinements later. It
/// leaves the display alone: font, size, theme and layout are about the
/// screen and the eyes, not about Hebrew.
enum ReadingPreset {
  newcomer(
    'New to Hebrew',
    'Read in English, with English book names. Tap an English word to see '
        'the Hebrew it translates.',
    Icons.translate,
  ),
  learner(
    'Learning Hebrew',
    'Read the Hebrew with an English gloss under each word, without the '
        'chanting marks.',
    Icons.school_outlined,
  ),
  reader(
    'Reading Hebrew',
    'The Hebrew text as a printed edition sets it, with Hebrew book names '
        'and numerals.',
    Icons.menu_book_outlined,
  );

  const ReadingPreset(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;

  /// [base] with this preset's settings in place of its own.
  AppReadingSettings applyTo(AppReadingSettings base) => switch (this) {
    newcomer => base.copyWith(
      readerText: ReaderText.english,
      rapidReading: false,
      showInterlinear: true,
      ntSyriac: false,
      englishBookNames: true,
      hebrewNumerals: false,
      showCantillation: false,
      glossInterlinear: true,
      morphologyInterlinear: false,
      highlightProperNames: true,
      syntaxRoles: false,
      syntaxView: SyntaxView.outline,
      rapidReveal: RapidReveal.word,
      ketivDisplay: KetivDisplay.hidden,
    ),
    learner => base.copyWith(
      readerText: ReaderText.source,
      rapidReading: false,
      showInterlinear: true,
      ntSyriac: false,
      englishBookNames: true,
      hebrewNumerals: false,
      showCantillation: false,
      glossInterlinear: true,
      morphologyInterlinear: false,
      highlightProperNames: true,
      syntaxRoles: false,
      syntaxView: SyntaxView.outline,
      rapidReveal: RapidReveal.word,
      ketivDisplay: KetivDisplay.superscript,
    ),
    // The same as [kDefaultReadingSettings].
    reader => base.copyWith(
      readerText: ReaderText.source,
      rapidReading: false,
      showInterlinear: true,
      ntSyriac: false,
      englishBookNames: false,
      hebrewNumerals: true,
      showCantillation: true,
      glossInterlinear: false,
      morphologyInterlinear: false,
      highlightProperNames: false,
      syntaxRoles: false,
      syntaxView: SyntaxView.outline,
      rapidReveal: RapidReveal.verse,
      ketivDisplay: KetivDisplay.superscript,
    ),
  };

  /// Whether a word's occurrences list their verses in English.
  ///
  /// Kept beside [applyTo] rather than in it because the word sheet, not the
  /// reader, owns that choice.
  bool get occurrenceEnglishOnly => this == newcomer;

  /// Saves this preset's settings over the saved ones, keeping the rest.
  Future<void> store(SharedPreferences prefs) async {
    await writeReadingSettings(prefs, applyTo(readReadingSettings(prefs)));
    await setOccurrenceVerseEnglishOnlyEnabled(occurrenceEnglishOnly);
  }
}

/// Whether this is a fresh install that should be asked about its Hebrew.
///
/// Anything at all in the preferences means the app has run here before, and
/// a reader who has used it already has the settings they chose.
bool isFirstRun(SharedPreferences prefs) => prefs.getKeys().isEmpty;

/// Asks a new reader how familiar they are with Hebrew before showing [child],
/// so the reader opens on text they can read.
class WelcomeGate extends StatefulWidget {
  const WelcomeGate({required this.child, super.key});

  final Widget child;

  @override
  State<WelcomeGate> createState() => _WelcomeGateState();
}

class _WelcomeGateState extends State<WelcomeGate> {
  bool? _asking;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _asking = isFirstRun(prefs));
    });
  }

  Future<void> _choose(ReadingPreset preset) async {
    // Saved before the reader is built, so it opens on them.
    await preset.store(await SharedPreferences.getInstance());
    if (mounted) setState(() => _asking = false);
  }

  @override
  Widget build(BuildContext context) => switch (_asking) {
    null => ColoredBox(color: Theme.of(context).colorScheme.surface),
    true => WelcomePage(onChosen: _choose),
    false => widget.child,
  };
}

/// The first screen a new reader sees: one question, three answers.
class WelcomePage extends StatelessWidget {
  const WelcomePage({required this.onChosen, super.key});

  final ValueChanged<ReadingPreset> onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'הָקוֹר',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontFamily: 'Cardo',
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome to Haqor',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'How familiar are you with Hebrew?',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  for (final preset in ReadingPreset.values) ...[
                    ReadingPresetCard(
                      key: ValueKey('welcome-${preset.name}'),
                      preset: preset,
                      onTap: () => onChosen(preset),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'This only sets where to start. Every setting can be '
                    'changed later in Settings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A preset as a tappable card, on the welcome screen and in Settings.
class ReadingPresetCard extends StatelessWidget {
  const ReadingPresetCard({
    required this.preset,
    required this.onTap,
    super.key,
  });

  final ReadingPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(preset.icon, color: scheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      preset.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
