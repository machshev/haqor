import 'package:flutter/material.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../study_workspace.dart';
import 'event_parallels_page.dart';

/// The parallel accounts of [events], from the reader at [book] (1-based):
/// each event's title over its accounts, one tap from reading another, and
/// a button setting them side by side.
class GospelParallelsSheet extends StatelessWidget {
  const GospelParallelsSheet({
    super.key,
    required this.heading,
    required this.events,
    required this.book,
    required this.useEnglishBookNames,
    required this.onOpenPassage,
    this.sendVerseTextsRequest,
  });

  final String heading;
  final List<BibleEventEntry> events;
  final int book;
  final bool useEnglishBookNames;
  final ValueChanged<StudyPassage> onOpenPassage;
  final void Function(GetVerseTexts)? sendVerseTextsRequest;

  static Future<void> show(
    BuildContext context, {
    required String heading,
    required List<BibleEventEntry> events,
    required int book,
    required bool useEnglishBookNames,
    required ValueChanged<StudyPassage> onOpenPassage,
    void Function(GetVerseTexts)? sendVerseTextsRequest,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => GospelParallelsSheet(
      heading: heading,
      events: events,
      book: book,
      useEnglishBookNames: useEnglishBookNames,
      onOpenPassage: onOpenPassage,
      sendVerseTextsRequest: sendVerseTextsRequest,
    ),
  );

  String _reference(ThematicTarget p) {
    final name = bookDisplayName(p.book - 1, useEnglish: useEnglishBookNames);
    final start = '$name ${p.chapter}:${p.verse}';
    if (p.lastChapter == p.chapter && p.lastVerse == p.verse) return start;
    if (p.lastChapter == p.chapter) return '$start–${p.lastVerse}';
    return '$start–${p.lastChapter}:${p.lastVerse}';
  }

  /// [event]'s accounts, by book and then by place in it.
  static List<ThematicTarget> _accounts(BibleEventEntry event) =>
      [...event.passages]..sort((a, b) {
        final c = a.book.compareTo(b.book);
        if (c != 0) return c;
        final ch = a.chapter.compareTo(b.chapter);
        return ch != 0 ? ch : a.verse.compareTo(b.verse);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(heading, style: theme.textTheme.titleMedium),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: events.length,
                separatorBuilder: (_, _) => const Divider(height: 20),
                itemBuilder: (context, i) => _event(context, theme, events[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _event(BuildContext context, ThemeData theme, BibleEventEntry event) {
    final accounts = _accounts(event);
    return Column(
      key: ValueKey('gospel-parallels-event-${event.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(event.title, style: theme.textTheme.titleSmall),
            ),
            TextButton.icon(
              key: ValueKey('gospel-parallels-side-by-side-${event.id}'),
              onPressed: () {
                Navigator.pop(context);
                EventParallelsPage.open(
                  context,
                  title: event.title,
                  passages: event.passages,
                  useEnglishBookNames: useEnglishBookNames,
                  onOpenPassage: onOpenPassage,
                  sendVerseTextsRequest: sendVerseTextsRequest,
                );
              },
              icon: const Icon(Icons.view_column_outlined, size: 18),
              label: const Text('Side by side'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in accounts)
              p.book == book
                  // The account being read: still a way back to its start.
                  ? FilterChip(
                      key: ValueKey(
                        'gospel-parallels-account-${event.id}-${p.book}-'
                        '${p.chapter}:${p.verse}',
                      ),
                      selected: true,
                      showCheckmark: false,
                      label: Text(_reference(p)),
                      onSelected: (_) => _open(context, p),
                    )
                  : ActionChip(
                      key: ValueKey(
                        'gospel-parallels-account-${event.id}-${p.book}-'
                        '${p.chapter}:${p.verse}',
                      ),
                      avatar: const Icon(Icons.menu_book_outlined, size: 18),
                      label: Text(_reference(p)),
                      onPressed: () => _open(context, p),
                    ),
          ],
        ),
      ],
    );
  }

  void _open(BuildContext context, ThematicTarget p) {
    Navigator.pop(context);
    onOpenPassage(
      StudyPassage(bookIndex: p.book - 1, chapter: p.chapter, verse: p.verse),
    );
  }
}
