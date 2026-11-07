import 'package:flutter/material.dart';

import 'lexicon/early_alphabet_page.dart';
import 'lexicon/haqor_lexicon_view.dart';
import 'lexicon/semitic_sounds_page.dart';
import 'tutor/concept_reference.dart';

/// The reference shelf behind the reader's top-bar button: the tutor's
/// explanation cards, the Semitic sound correspondences and the early
/// alphabet, gathered in one place.
class ReferencePage extends StatelessWidget {
  const ReferencePage({super.key, this.onNavigateToPassage});

  final LexiconNavigate? onNavigateToPassage;

  static Future<void> open(
    BuildContext context, {
    LexiconNavigate? onNavigateToPassage,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReferencePage(onNavigateToPassage: onNavigateToPassage),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A verse link on a reference page closes the shelf too, so the reader
    // is what shows.
    final navigate = onNavigateToPassage;
    final LexiconNavigate? throughShelf = navigate == null
        ? null
        : (book, chapter, verse) {
            Navigator.of(context).pop();
            navigate(book, chapter, verse);
          };
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    Widget entry({
      required IconData icon,
      required String title,
      required String subtitle,
      required WidgetBuilder page,
    }) => Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute<void>(builder: page)),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Reference')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              section('Learning to read'),
              entry(
                icon: Icons.school_outlined,
                title: 'Tutor reference',
                subtitle:
                    'The letters, marks and grammar the tutor has '
                    'explained so far',
                page: (_) => const ConceptReferencePage(),
              ),
              section('Language and script'),
              entry(
                icon: Icons.record_voice_over_outlined,
                title: 'Semitic sounds',
                subtitle:
                    'The older consonants behind each Hebrew letter, and '
                    'where Aramaic differs',
                page: (_) =>
                    SemiticSoundsPage(onNavigateToPassage: throughShelf),
              ),
              entry(
                icon: Icons.history_edu_outlined,
                title: 'The earliest alphabet',
                subtitle:
                    'Douglas Petrovich’s reconstruction, with the Egyptian '
                    'hieroglyphs behind each letter',
                page: (_) => const EarlyAlphabetPage(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
