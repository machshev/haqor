import 'package:flutter/material.dart';

/// The lexicons the word sheet's Lexicon tab draws on, keyed as the hub sends
/// them in `BdbSummary.source`.
enum LexiconSource {
  bdb('B', 'Brown-Driver-Briggs'),
  klein('K', "Klein's Etymological Dictionary"),
  jastrow('J', "Jastrow's Dictionary of the Targumim, Talmud and Midrash"),
  sedra('S', 'SEDRA Syriac lexicon of the Peshitta');

  const LexiconSource(this.letter, this.title);

  /// The badge's monogram.
  final String letter;

  /// The full name, for the badge's tooltip and screen readers.
  final String title;

  /// The source named by [key], BDB when the key is empty or unknown (a hub
  /// older than the dictionaries sends none).
  static LexiconSource of(String key) => switch (key) {
    'klein' => LexiconSource.klein,
    'jastrow' => LexiconSource.jastrow,
    'sedra' => LexiconSource.sedra,
    _ => LexiconSource.bdb,
  };
}

/// A small monogram naming which lexicon an entry comes from, so entries of
/// one lexeme from BDB, Klein, Jastrow and SEDRA can be told apart at a glance.
class LexiconSourceBadge extends StatelessWidget {
  const LexiconSourceBadge({super.key, required this.source});

  /// The hub's source key: `bdb`, `klein`, `jastrow` or `sedra`.
  final String source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lexicon = LexiconSource.of(source);
    final (background, foreground) = switch (lexicon) {
      LexiconSource.bdb => (scheme.primaryContainer, scheme.onPrimaryContainer),
      LexiconSource.klein => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      LexiconSource.jastrow => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      LexiconSource.sedra => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Tooltip(
      message: lexicon.title,
      child: Semantics(
        label: lexicon.title,
        excludeSemantics: true,
        child: Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: Text(
            lexicon.letter,
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The period or language marker Klein or Jastrow puts on an entry, as a
/// compact label: Klein's `NH`, `PBH`, `MH`, `FW` as printed, Jastrow's `ch.`
/// as "Aram." and `b. h.` as "BH". Its tooltip spells the marker out.
class LexiconPeriodLabel extends StatelessWidget {
  const LexiconPeriodLabel._(this.label, this.meaning);

  final String label;
  final String meaning;

  /// The label for [marker], or null when the entry is unmarked.
  static LexiconPeriodLabel? of(String marker) {
    final m = marker.trim();
    if (m.isEmpty) return null;
    final (label, meaning) = describe(m);
    return LexiconPeriodLabel._(label, meaning);
  }

  /// The short label and the spelled-out meaning of a marker.
  static (String, String) describe(String marker) {
    if (marker.contains('ch.')) return ('Aram.', 'Aramaic (Jastrow: ch.)');
    if (marker.contains('b. h')) {
      return ('BH', 'Also biblical Hebrew (Jastrow: b. h.)');
    }
    return switch (marker) {
      'BH' => ('BH', 'Biblical Hebrew'),
      'PBH' => ('PBH', 'Post-biblical Hebrew'),
      'MH' => ('MH', 'Medieval Hebrew'),
      'NH' => ('NH', 'Modern Hebrew'),
      'FW' => ('FW', 'Foreign word'),
      _ => (marker, marker),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: meaning,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
