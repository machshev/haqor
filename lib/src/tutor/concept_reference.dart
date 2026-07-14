import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import 'alphabet_data.dart';
import 'intro_content.dart';

const String _hebrewFont = 'Cardo';
const List<String> _hebrewFallback = ['Noto Serif Hebrew'];

/// A reference of every explanation card the tutor has already shown —
/// the language-intro deck, the final-forms card, reading marks and grammar
/// concepts — so the learner can look one up again at any time. The list
/// grows as the tutor unlocks new cards; nothing is shown ahead of the
/// curriculum.
class ConceptReferencePage extends StatefulWidget {
  const ConceptReferencePage({super.key});

  @override
  State<ConceptReferencePage> createState() => _ConceptReferencePageState();
}

class _ConceptReferencePageState extends State<ConceptReferencePage> {
  StreamSubscription<RustSignalPack<SeenConcepts>>? _sub;
  List<SeenConcept>? _cards;

  @override
  void initState() {
    super.initState();
    _sub = SeenConcepts.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() => _cards = pack.message.cards);
    });
    GetSeenConcepts().sendSignalToRust();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cards = _cards;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Reference'),
      ),
      body: cards == null
          ? const Center(child: CircularProgressIndicator())
          : cards.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing here yet — explanation cards appear in this '
                  'reference as the lessons introduce them.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : _ConceptList(cards: cards),
    );
  }
}

class _ConceptList extends StatelessWidget {
  final List<SeenConcept> cards;
  const _ConceptList({required this.cards});

  @override
  Widget build(BuildContext context) {
    final intro = cards.where((c) => c.kind == 'intro').toList();
    final script = cards
        .where((c) => c.kind == 'final_forms' || c.kind == 'mark')
        .toList();
    final grammar = cards.where((c) => c.kind == 'grammar').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (intro.isNotEmpty) ...[
          const _SectionHeader('Basics'),
          for (final c in intro) _ConceptTile(card: c),
        ],
        if (script.isNotEmpty) ...[
          const _SectionHeader('Letters & marks'),
          for (final c in script) _ConceptTile(card: c),
        ],
        if (grammar.isNotEmpty) ...[
          const _SectionHeader('Grammar'),
          for (final c in grammar) _ConceptTile(card: c),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// One unlocked explanation card, collapsed to its title; expanding shows the
/// same content the original study card carried.
class _ConceptTile extends StatelessWidget {
  final SeenConcept card;
  const _ConceptTile({required this.card});

  String get _title {
    switch (card.kind) {
      case 'intro':
        return introTitle(card.key);
      case 'final_forms':
        return 'Final letters';
      case 'mark':
        return glyphInfo(card.key)?.name ?? card.key;
      default:
        return card.title;
    }
  }

  /// A short Hebrew specimen shown next to the title, where one exists.
  String? get _leadingGlyph {
    switch (card.kind) {
      case 'mark':
        return card.key;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leading = _leadingGlyph;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        shape: const Border(),
        leading: leading == null
            ? null
            : Text(
                leading,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontFamily: _hebrewFont,
                  fontFamilyFallback: _hebrewFallback,
                  fontSize: 24,
                ),
              ),
        title: Text(_title, style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [_body(context)],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (card.kind) {
      case 'intro':
        return IntroCardBody(introKey: card.key);
      case 'final_forms':
        return const _FinalFormsBody();
      case 'mark':
        return _MarkBody(glyph: card.key);
      default:
        return _GrammarBody(card: card);
    }
  }
}

class _FinalFormsBody extends StatelessWidget {
  const _FinalFormsBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kFinalFormsExplanation,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        const FinalFormsPairs(),
      ],
    );
  }
}

/// A reading mark's explanation, from the same [glyphInfo] data the one-time
/// study card used.
class _MarkBody extends StatelessWidget {
  final String glyph;
  const _MarkBody({required this.glyph});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = glyphInfo(glyph);
    if (info == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          info.sound,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (info.tip != null) ...[
          const SizedBox(height: 8),
          Text(
            info.tip!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          info.example,
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: const TextStyle(
            fontFamily: _hebrewFont,
            fontFamilyFallback: _hebrewFallback,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${info.exampleTranslit} — ${info.exampleMeaning}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// A grammar concept's content, as carried on the card from the core.
class _GrammarBody extends StatelessWidget {
  final SeenConcept card;
  const _GrammarBody({required this.card});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(card.explanation, style: theme.textTheme.bodyMedium),
        if (card.formula.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              card.formula,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
        if (card.examples.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final ex in card.examples)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                ex,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: _hebrewFont,
                  fontFamilyFallback: _hebrewFallback,
                  fontSize: 18,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
