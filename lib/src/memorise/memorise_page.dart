import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bible_data.dart';
import '../bindings/bindings.dart';
import '../tutor/progress_sync.dart';
import '../widgets/book_selector.dart';
import '../widgets/chapter_selector.dart';
import 'memorise_charts.dart';
import 'memorise_drill.dart';
import 'memorise_shape.dart';

/// Seconds east of UTC, so the core counts days (goal, streak) locally.
int memoryUtcOffset() => DateTime.now().timeZoneOffset.inSeconds;

/// The reference a passage covers, e.g. "Psalms 23:1–6".
String passageReference(MemoryPassageEntry p, {required bool useEnglish}) {
  final book = bookDisplayName(p.book - 1, useEnglish: useEnglish);
  if (p.startChapter == p.endChapter) {
    if (p.startVerse == p.endVerse) {
      return '$book ${p.startChapter}:${p.startVerse}';
    }
    return '$book ${p.startChapter}:${p.startVerse}–${p.endVerse}';
  }
  return '$book ${p.startChapter}:${p.startVerse}–${p.endChapter}:${p.endVerse}';
}

String passageTitle(MemoryPassageEntry p, {required bool useEnglish}) =>
    p.title.isNotEmpty ? p.title : passageReference(p, useEnglish: useEnglish);

Future<bool> _useEnglishBookNames() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('english_book_names') ?? false;
}

/// Add a whole chapter as a passage (from the reader), open the memorisation
/// dashboard, and go straight on to shaping it.
Future<void> memoriseChapter(
  BuildContext context,
  int bookIndex,
  int chapter,
) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => MemorisePage(addChapter: (bookIndex + 1, chapter)),
  ),
);

/// The memorisation dashboard: level, daily goal and streak; the passages
/// being learnt with a heatmap of every verse; activity graphs; and
/// achievements.
class MemorisePage extends StatefulWidget {
  const MemorisePage({super.key, this.addChapter});

  /// A (book, chapter) to add as a passage on opening, then shape.
  final (int, int)? addChapter;

  @override
  State<MemorisePage> createState() => _MemorisePageState();
}

class _MemorisePageState extends State<MemorisePage> {
  StreamSubscription<RustSignalPack<MemoryPassages>>? _passagesSub;
  StreamSubscription<RustSignalPack<MemoryStats>>? _statsSub;
  StreamSubscription<RustSignalPack<ProgressSyncStatus>>? _syncSub;
  List<MemoryPassageEntry>? _passages;
  MemoryStats? _stats;
  bool _english = false;

  /// A passage is being added: open its shaping page when it arrives.
  bool _shapeNext = false;

  @override
  void initState() {
    super.initState();
    _passagesSub = MemoryPassages.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() => _passages = pack.message.passages);
      final saved = pack.message.savedId;
      if (_shapeNext && saved.isNotEmpty) {
        _shapeNext = false;
        final passage = pack.message.passages.where((p) => p.id == saved);
        if (passage.isNotEmpty) _shape(passage.first, exit: ShapeExit.start);
      }
      // Any change to the passages moves the counts too.
      GetMemoryStats(utcOffset: memoryUtcOffset()).sendSignalToRust();
    });
    _statsSub = MemoryStats.rustSignalStream.listen((pack) {
      if (mounted) setState(() => _stats = pack.message);
    });
    // Another device's progress may have just arrived.
    _syncSub = ProgressSyncStatus.rustSignalStream.listen((pack) {
      if (pack.message.success) _refresh();
    });
    _useEnglishBookNames().then((english) {
      if (mounted) setState(() => _english = english);
    });
    _refresh();
    final add = widget.addChapter;
    if (add != null) {
      _shapeNext = true;
      SaveMemoryPassage(
        book: add.$1,
        startChapter: add.$2,
        startVerse: 1,
        endChapter: add.$2,
        endVerse: 255,
        title: '',
      ).sendSignalToRust();
      scheduleProgressSync();
    }
  }

  void _refresh() {
    GetMemoryPassages().sendSignalToRust();
    GetMemoryStats(utcOffset: memoryUtcOffset()).sendSignalToRust();
  }

  @override
  void dispose() {
    _passagesSub?.cancel();
    _statsSub?.cancel();
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _practise({MemoryPassageEntry? passage}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryDrillPage(
          passageId: passage?.id ?? '',
          title: passage == null
              ? 'All passages'
              : passageTitle(passage, useEnglish: _english),
        ),
      ),
    );
    _refresh();
  }

  Future<void> _runThrough(MemoryPassageEntry passage) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemoryDrillPage(
          passageId: passage.id,
          title: passageTitle(passage, useEnglish: _english),
          run: true,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _shape(
    MemoryPassageEntry passage, {
    ShapeExit exit = ShapeExit.none,
  }) async {
    final learn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemoryShapePage(
          passageId: passage.id,
          title: passageTitle(passage, useEnglish: _english),
          exit: exit,
        ),
      ),
    );
    _refresh();
    // "Start learning": practise from here, so the list refreshes after.
    if (learn == true && mounted) await _practise(passage: passage);
  }

  Future<void> _addPassage() async {
    // Set before the sheet saves, so its reply cannot beat the flag.
    _shapeNext = true;
    final added = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AddPassageSheet(useEnglish: _english),
    );
    if (added == true) {
      scheduleProgressSync();
    } else {
      _shapeNext = false;
    }
  }

  Future<void> _rename(MemoryPassageEntry passage) async {
    final controller = TextEditingController(text: passage.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this passage'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: passageReference(passage, useEnglish: _english),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    SaveMemoryPassage(
      book: passage.book,
      startChapter: passage.startChapter,
      startVerse: passage.startVerse,
      endChapter: passage.endChapter,
      endVerse: passage.endVerse,
      title: title.trim(),
    ).sendSignalToRust();
    scheduleProgressSync();
  }

  Future<void> _delete(MemoryPassageEntry passage) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop learning this passage?'),
        content: const Text(
          'What you have learnt of its verses is kept, so adding it again '
          'carries on where you left off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    DeleteMemoryPassage(id: passage.id).sendSignalToRust();
    scheduleProgressSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passages = _passages;
    final stats = _stats;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: const Text('Memorise'),
        actions: [
          if (stats != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Daily goal and pace',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (_) => _SettingsSheet(stats: stats),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync progress now',
            onPressed: () async {
              final started = await syncProgressNow();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    started
                        ? 'Syncing progress…'
                        : 'Configure LAN sync in App settings first.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPassage,
        icon: const Icon(Icons.add),
        label: const Text('Add passage'),
      ),
      body: passages == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (stats != null) _HeaderCard(stats: stats),
                const SizedBox(height: 12),
                if (passages.isEmpty)
                  _EmptyState(onAdd: _addPassage)
                else ...[
                  FilledButton.icon(
                    onPressed: () => _practise(),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      stats == null || stats.dueNow == 0
                          ? 'Practise'
                          : 'Practise · ${stats.dueNow} due',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Passages', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final p in passages)
                    _PassageCard(
                      passage: p,
                      useEnglish: _english,
                      onPractise: () => _practise(passage: p),
                      onRunThrough: p.learnt > 0 ? () => _runThrough(p) : null,
                      onShape: () => _shape(p),
                      onRename: () => _rename(p),
                      onDelete: () => _delete(p),
                    ),
                ],
                if (stats != null && stats.reviewsTotal > 0) ...[
                  const SizedBox(height: 16),
                  _ChartsSection(stats: stats),
                  const SizedBox(height: 16),
                  _TotalsSection(stats: stats),
                ],
                if (stats != null) ...[
                  const SizedBox(height: 16),
                  _AchievementsSection(stats: stats),
                ],
              ],
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.stats});

  final MemoryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = stats.dailyGoalXp <= 0 ? 1 : stats.dailyGoalXp;
    final goalFraction = (stats.todayXp / goal).clamp(0.0, 1.0);
    final levelFraction = stats.levelSpan <= 0
        ? 0.0
        : (stats.levelXp / stats.levelSpan).clamp(0.0, 1.0);
    final goalMet = stats.todayXp >= stats.dailyGoalXp;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _LevelBadge(level: stats.level, fraction: levelFraction),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level ${stats.level}',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        '${stats.levelSpan - stats.levelXp} XP to level '
                        '${stats.level + 1} · ${stats.totalXp} XP total',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _StreakChip(days: stats.streakDays),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  goalMet ? Icons.emoji_events : Icons.flag_outlined,
                  size: 18,
                  color: goalMet
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  goalMet ? 'Daily goal met' : 'Daily goal',
                  style: theme.textTheme.labelLarge,
                ),
                const Spacer(),
                Text(
                  '${stats.todayXp} / ${stats.dailyGoalXp} XP',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: goalFraction, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level, required this.fraction});

  final int level;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: fraction,
            strokeWidth: 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Center(
            child: Text(
              '$level',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alive = days > 0;
    return Tooltip(
      message: alive
          ? '$days-day streak — practise today to keep it'
          : 'Practise today to start a streak',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: alive
              ? theme.colorScheme.tertiaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              size: 18,
              color: alive
                  ? theme.colorScheme.onTertiaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              '$days',
              style: theme.textTheme.labelLarge?.copyWith(
                color: alive
                    ? theme.colorScheme.onTertiaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Hide the word in your heart',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a chapter or a run of verses. First work out what it says and '
            'mark where its lines and sections break; then learn it a line and '
            'a verse at a time, reciting from memory, and review it just before '
            'you would forget.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Choose a passage'),
          ),
        ],
      ),
    );
  }
}

enum _PassageAction { shape, runThrough, rename, delete }

class _PassageCard extends StatelessWidget {
  const _PassageCard({
    required this.passage,
    required this.useEnglish,
    required this.onPractise,
    required this.onRunThrough,
    required this.onShape,
    required this.onRename,
    required this.onDelete,
  });

  final MemoryPassageEntry passage;
  final bool useEnglish;
  final VoidCallback onPractise;
  final VoidCallback? onRunThrough;
  final VoidCallback onShape;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = passage.verses.length;
    final complete = total > 0 && passage.learnt == total;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPractise,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (complete) ...[
                    Icon(
                      Icons.verified,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          passageTitle(passage, useEnglish: useEnglish),
                          style: theme.textTheme.titleMedium,
                        ),
                        if (passage.title.isNotEmpty)
                          Text(
                            passageReference(passage, useEnglish: useEnglish),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Learning waits on the learner shaping the next section.
                  if (passage.needsShaping)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.wrap_text, size: 18),
                      label: const Text('Shape next'),
                      onPressed: onShape,
                    ),
                  if (passage.due > 0)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${passage.due} due'),
                    ),
                  PopupMenuButton<_PassageAction>(
                    tooltip: 'Passage options',
                    onSelected: (action) => switch (action) {
                      _PassageAction.shape => onShape(),
                      _PassageAction.runThrough => onRunThrough?.call(),
                      _PassageAction.rename => onRename(),
                      _PassageAction.delete => onDelete(),
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: _PassageAction.shape,
                        child: ListTile(
                          leading: Icon(Icons.wrap_text),
                          title: Text('Shape lines & sections'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _PassageAction.runThrough,
                        enabled: onRunThrough != null,
                        child: const ListTile(
                          leading: Icon(Icons.playlist_play),
                          title: Text('Recite the passage so far'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _PassageAction.rename,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Rename'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _PassageAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _VerseHeatmap(verses: passage.verses),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: passage.masteryPct / 100,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${passage.learnt}/$total learnt · '
                      '${passage.masteryPct}%',
                      style: theme.textTheme.labelMedium,
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

/// One square per verse, shaded by how well it is known; a dot marks a verse
/// due for review. Tap or hover a square for its verse and state.
class _VerseHeatmap extends StatelessWidget {
  const _VerseHeatmap({required this.verses});

  final List<MemoryVerseState> verses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final multiChapter =
        verses.isNotEmpty && verses.first.chapter != verses.last.chapter;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final v in verses) ...[
          // A wider gap marks where a new section begins.
          if (v.sectionStart && v != verses.first) const SizedBox(width: 8),
          Tooltip(
            triggerMode: TooltipTriggerMode.tap,
            message:
                '${multiChapter ? '${v.chapter}:' : 'Verse '}${v.verse} · '
                '${kStrengthLabels[v.strength.clamp(0, 5)]}'
                '${v.due ? ' · due' : ''}',
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: strengthColor(scheme, v.strength),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: v.due
                  ? Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: v.strength >= 3
                            ? scheme.onPrimary
                            : scheme.onSurface,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

String _dayLabel(int day) {
  final date = DateTime.utc(1970).add(Duration(days: day));
  return '${date.day}/${date.month}';
}

class _ChartsSection extends StatelessWidget {
  const _ChartsSection({required this.stats});

  final MemoryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget panel(String title, String subtitle, Widget chart) => Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            chart,
          ],
        ),
      ),
    );
    final today = stats.history.isEmpty ? 0 : stats.history.last.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Progress', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        panel(
          'XP per day',
          'The last 30 days, against your daily goal',
          MiniChart(
            points: [
              for (final d in stats.history)
                ChartPoint(
                  _dayLabel(d.day),
                  d.xp,
                  tooltip:
                      '${_dayLabel(d.day)}: ${d.xp} XP, ${d.reviews} answers',
                ),
            ],
            reference: stats.dailyGoalXp,
            referenceLabel: 'goal',
          ),
        ),
        panel(
          'Verses learnt',
          'Running total of verses learnt by heart',
          MiniChart(
            line: true,
            points: [
              for (final d in stats.history)
                ChartPoint(
                  _dayLabel(d.day),
                  d.learntTotal,
                  tooltip: '${_dayLabel(d.day)}: ${d.learntTotal} verses',
                ),
            ],
          ),
        ),
        panel(
          'Coming up',
          'Verses due for review over the next two weeks',
          MiniChart(
            labelEvery: 3,
            points: [
              for (var i = 0; i < stats.forecast.length; i++)
                ChartPoint(
                  i == 0 ? 'today' : _dayLabel(today + i),
                  stats.forecast[i],
                  tooltip:
                      '${i == 0 ? 'Today' : _dayLabel(today + i)}: '
                      '${stats.forecast[i]} due',
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.stats});

  final MemoryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tile(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: theme.textTheme.headlineSmall),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                tile('${stats.versesLearnt}', 'verses learnt'),
                tile('${stats.versesMature}', 'mature (3 wk+)'),
                tile('${stats.versesLearning}', 'learning'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                tile('${stats.accuracyPct}%', 'recalled'),
                tile('${stats.bestStreakDays}', 'best streak'),
                tile(
                  '${stats.passagesCompleted}/${stats.passagesTotal}',
                  'passages complete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementsSection extends StatelessWidget {
  const _AchievementsSection({required this.stats});

  final MemoryStats stats;

  static const _icons = <String, IconData>{
    'verse': Icons.menu_book,
    'passage': Icons.verified,
    'mature': Icons.park,
    'streak': Icons.local_fire_department,
    'goal': Icons.emoji_events,
    'xp': Icons.bolt,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = stats.achievements.where((a) => a.earned).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Achievements · $earned of ${stats.achievements.length}',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in stats.achievements)
              Tooltip(
                triggerMode: TooltipTriggerMode.tap,
                message: a.earned
                    ? a.description
                    : '${a.description} (${a.progress}/${a.target})',
                child: Container(
                  width: 104,
                  height: 92,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: a.earned
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _icons[a.key.split('_').first] ?? Icons.star,
                        color: a.earned
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        a.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: a.earned
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!a.earned) ...[
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: a.target == 0 ? 0 : a.progress / a.target,
                          minHeight: 3,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.stats});

  final MemoryStats stats;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late double _newPerDay = widget.stats.newPerDay.toDouble();
  late double _goal = widget.stats.dailyGoalXp.toDouble();

  void _save() {
    SetMemorySettings(
      newPerDay: _newPerDay.round(),
      dailyGoalXp: _goal.round(),
      utcOffset: memoryUtcOffset(),
    ).sendSignalToRust();
    scheduleProgressSync();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Daily goal and pace',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text('New verses a day: ${_newPerDay.round()}'),
            Slider(
              value: _newPerDay.clamp(1, 10),
              min: 1,
              max: 10,
              divisions: 9,
              label: '${_newPerDay.round()}',
              onChanged: (v) => setState(() => _newPerDay = v),
              onChangeEnd: (_) => _save(),
            ),
            Text(
              'Fewer new verses leave room to review the ones you know. You '
              'can always learn another when you finish.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Text('Daily goal: ${_goal.round()} XP'),
            Slider(
              value: _goal.clamp(20, 500),
              min: 20,
              max: 500,
              divisions: 48,
              label: '${_goal.round()} XP',
              onChanged: (v) => setState(() => _goal = v),
              onChangeEnd: (_) => _save(),
            ),
            Text(
              'Roughly 10 XP per verse recited; reading a new verse earns 5.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Choose a book, chapter and (optionally) a range of verses to learn.
class _AddPassageSheet extends StatefulWidget {
  const _AddPassageSheet({required this.useEnglish});

  final bool useEnglish;

  @override
  State<_AddPassageSheet> createState() => _AddPassageSheetState();
}

class _AddPassageSheetState extends State<_AddPassageSheet> {
  // Psalm 23: a classic first passage.
  int _book = 26;
  int _chapter = 23;
  bool _wholeChapter = true;
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController();
  final _title = TextEditingController();

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickBook() async {
    final book = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => BookSelectorSheet(
        currentIndex: _book,
        useEnglishBookNames: widget.useEnglish,
      ),
    );
    if (book == null || !mounted) return;
    setState(() {
      _book = book;
      _chapter = 1;
    });
    if (kBooks[book].chapters > 1) await _pickChapter();
  }

  Future<void> _pickChapter() async {
    final chapter = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => ChapterSelectorSheet(
        total: kBooks[_book].chapters,
        current: _chapter,
      ),
    );
    if (chapter != null && mounted) setState(() => _chapter = chapter);
  }

  void _save() {
    var from = 1;
    var to = 255;
    if (!_wholeChapter) {
      from = int.tryParse(_from.text.trim()) ?? 1;
      to = int.tryParse(_to.text.trim()) ?? from;
      from = from.clamp(1, 255);
      to = to.clamp(1, 255);
    }
    SaveMemoryPassage(
      book: _book + 1,
      startChapter: _chapter,
      startVerse: from,
      endChapter: _chapter,
      endVerse: to,
      title: _title.text.trim(),
    ).sendSignalToRust();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add a passage',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickBook,
                      child: Text(
                        bookDisplayName(_book, useEnglish: widget.useEnglish),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: kBooks[_book].chapters > 1 ? _pickChapter : null,
                    child: Text('Chapter $_chapter'),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Whole chapter'),
                value: _wholeChapter,
                onChanged: (v) => setState(() => _wholeChapter = v),
              ),
              if (!_wholeChapter)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _from,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'From verse',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _to,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'To verse',
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Name (optional)',
                  hintText: 'e.g. The shepherd psalm',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.add),
                label: const Text('Start learning'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
