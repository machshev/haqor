import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bindings/bindings.dart';
import 'progress_sync.dart';

/// Open the study-pacing settings as a modal bottom sheet.
const _tutorAdminModeKey = 'tutor_admin_mode';

Future<bool> tutorAdminModeEnabled() async =>
    (await SharedPreferences.getInstance()).getBool(_tutorAdminModeKey) ??
    false;

Future<void> setTutorAdminModeEnabled(bool enabled) async =>
    (await SharedPreferences.getInstance()).setBool(
      _tutorAdminModeKey,
      enabled,
    );

Future<void> showStudySettings(
  BuildContext context, {
  ValueChanged<bool>? onAdminModeChanged,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => _SettingsSheet(onAdminModeChanged: onAdminModeChanged),
);

/// Configure how fast the tutor progresses: how many new letters and words are
/// introduced at once, and whether grammar rules expand one at a time. Fetches
/// the current [TutorSettings] on open and writes changes back with
/// [SetTutorSettings]; the engine picks them up on the next card.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({this.onAdminModeChanged});

  final ValueChanged<bool>? onAdminModeChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  StreamSubscription<RustSignalPack<TutorSettings>>? _sub;
  StreamSubscription<RustSignalPack<TutorGlossOverrideStats>>? _overrideSub;

  int _lettersPerBatch = 3;
  int _wordsPerBatch = 8;
  bool _grammarGating = true;
  int _vocabPriority = 75;
  int _grammarPriority = 25;
  int _versePriority = 25;
  int _lettersRatio = 30;
  bool _adminMode = false;
  bool _loaded = false;
  TutorGlossOverrideStats? _overrideStats;
  bool _optimizingOverrides = false;
  String? _overrideStatus;
  bool _overrideStatusIsError = false;

  @override
  void initState() {
    super.initState();
    // Seed from the last value if one was already received, so the controls
    // show instantly on reopen.
    final seed = TutorSettings.latestRustSignal?.message;
    if (seed != null) {
      _adopt(seed);
      _loaded = true;
    }
    // Adopt the authoritative (possibly clamped) values on first arrival only;
    // after that the local controls are the source of truth so an echo of our
    // own write doesn't fight a drag in progress.
    _sub = TutorSettings.rustSignalStream.listen((pack) {
      if (!mounted || _loaded) return;
      setState(() {
        _adopt(pack.message);
        _loaded = true;
      });
    });
    GetTutorSettings().sendSignalToRust();
    _overrideStats = TutorGlossOverrideStats.latestRustSignal?.message;
    _overrideSub = TutorGlossOverrideStats.rustSignalStream.listen((pack) {
      if (!mounted) return;
      final wasOptimizing = _optimizingOverrides;
      final stats = pack.message;
      setState(() {
        _optimizingOverrides = false;
        if (stats.error.isNotEmpty) {
          _overrideStatus = stats.error;
          _overrideStatusIsError = true;
          return;
        }
        _overrideStats = stats;
        _overrideStatusIsError = false;
        if (wasOptimizing) {
          _overrideStatus = stats.removed == 0
              ? 'All local overrides are still required.'
              : 'Removed ${stats.removed} no-op ${stats.removed == 1 ? 'override' : 'overrides'}.';
        }
      });
      if (wasOptimizing && stats.error.isEmpty && stats.removed > 0) {
        scheduleProgressSync();
      }
    });
    GetTutorGlossOverrideStats().sendSignalToRust();
    _loadAdminMode();
  }

  Future<void> _loadAdminMode() async {
    final enabled = await tutorAdminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  Future<void> _setAdminMode(bool enabled) async {
    setState(() => _adminMode = enabled);
    await setTutorAdminModeEnabled(enabled);
    widget.onAdminModeChanged?.call(enabled);
  }

  void _adopt(TutorSettings s) {
    _lettersPerBatch = s.lettersPerBatch;
    _wordsPerBatch = s.wordsPerBatch;
    _grammarGating = s.grammarGating;
    _vocabPriority = s.vocabPriority;
    _grammarPriority = s.grammarPriority;
    _versePriority = s.versePriority;
    _lettersRatio = s.lettersRatio;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _overrideSub?.cancel();
    super.dispose();
  }

  void _optimizeOverrides() {
    setState(() {
      _optimizingOverrides = true;
      _overrideStatus = 'Checking against the current core data…';
      _overrideStatusIsError = false;
    });
    OptimizeTutorGlossOverrides().sendSignalToRust();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset progress?'),
        content: const Text(
          'This clears every learned letter, word and verse. You will start '
          'again from the first verse.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop();
      ResetTutor().sendSignalToRust();
    }
  }

  void _send() {
    SetTutorSettings(
      lettersPerBatch: _lettersPerBatch,
      wordsPerBatch: _wordsPerBatch,
      grammarGating: _grammarGating,
      vocabPriority: _vocabPriority,
      grammarPriority: _grammarPriority,
      versePriority: _versePriority,
      lettersRatio: _lettersRatio,
    ).sendSignalToRust();
  }

  int get _wordsPerGrammarRule => 30 - (_grammarPriority * 27 ~/ 100);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: !_loaded
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Study pace',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    _SectionLabel('New material'),
                    _SliderTile(
                      label: 'New letters at once',
                      value: _lettersPerBatch.toDouble(),
                      min: 1,
                      max: 8,
                      valueLabel: '$_lettersPerBatch',
                      onChanged: (v) =>
                          setState(() => _lettersPerBatch = v.round()),
                      onChangeEnd: (_) => _send(),
                    ),
                    _SliderTile(
                      label: 'New words at once',
                      value: _wordsPerBatch.toDouble(),
                      min: 2,
                      max: 20,
                      valueLabel: '$_wordsPerBatch',
                      onChanged: (v) =>
                          setState(() => _wordsPerBatch = v.round()),
                      onChangeEnd: (_) => _send(),
                    ),
                    Text(
                      'Fewer at once means each is drilled to memory before the '
                      'next arrives — a gentler ramp.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 16),
                    Text('Focus', style: theme.textTheme.labelLarge),
                    Slider(
                      value: _lettersRatio.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: _lettersRatio <= 50
                          ? 'Words +${50 - _lettersRatio}'
                          : 'Letters +${_lettersRatio - 50}',
                      onChanged: (v) =>
                          setState(() => _lettersRatio = v.round()),
                      onChangeEnd: (_) => _send(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Read words sooner',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Learn letters faster',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toward words, the tutor teaches a word as soon as you know '
                      'its letters instead of pressing on with new ones.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 20),
                    _SectionLabel('Grammar'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Introduce grammar gradually'),
                      subtitle: const Text(
                        'Stay on simple Qal verbs, nouns and names until the '
                        'alphabet is known, then add one grammar rule at a time.',
                      ),
                      value: _grammarGating,
                      onChanged: (v) {
                        setState(() => _grammarGating = v);
                        _send();
                      },
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PrioritySlider(
                          label: 'Vocabulary',
                          value: _vocabPriority,
                          enabled: true,
                          onChanged: (v) => setState(() => _vocabPriority = v),
                          onChangeEnd: _send,
                        ),
                        _PrioritySlider(
                          label: 'Grammar',
                          value: _grammarPriority,
                          enabled: _grammarGating,
                          onChanged: (v) =>
                              setState(() => _grammarPriority = v),
                          onChangeEnd: _send,
                        ),
                        _PrioritySlider(
                          label: 'Verses',
                          value: _versePriority,
                          enabled: true,
                          onChanged: (v) => setState(() => _versePriority = v),
                          onChangeEnd: _send,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Vocabulary favours common words; Verses favours passages '
                          'closest to readable. ${_grammarGating ? 'At this Grammar pace, $_wordsPerGrammarRule learnt words separate new rules.' : 'Grammar pacing is off.'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('Progress sync'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sync),
                      title: const Text('Sync over your LAN'),
                      subtitle: const Text(
                        'Keep this progress in sync automatically with your personal server.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showProgressSyncSettings(context),
                    ),
                    const SizedBox(height: 12),
                    _SectionLabel('Admin'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                        Icons.admin_panel_settings_outlined,
                      ),
                      title: const Text('Admin tools'),
                      subtitle: const Text(
                        'Show tutor gloss editing and issue/idea flags. Reports '
                        'stay local until normal LAN sync sends them for review.',
                      ),
                      value: _adminMode,
                      onChanged: _setAdminMode,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_note_outlined),
                      title: const Text('Local gloss overrides'),
                      subtitle: Text(
                        _overrideStats == null
                            ? 'Counting local corrections…'
                            : _overrideStats!.total == 0
                            ? 'No local tutor corrections.'
                            : '${_overrideStats!.total} ${_overrideStats!.total == 1 ? 'override' : 'overrides'} on this device'
                                  '${_overrideStats!.redundant == 0 ? '; all still differ from core.' : '; ${_overrideStats!.redundant} now ${_overrideStats!.redundant == 1 ? 'matches' : 'match'} core.'}',
                      ),
                      trailing: _overrideStats == null
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '${_overrideStats!.total}',
                              style: theme.textTheme.titleMedium,
                            ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed:
                            _overrideStats == null ||
                                _overrideStats!.total == 0 ||
                                _optimizingOverrides
                            ? null
                            : _optimizeOverrides,
                        icon: _optimizingOverrides
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high_outlined),
                        label: Text(
                          _optimizingOverrides
                              ? 'Checking…'
                              : 'Optimise overrides',
                        ),
                      ),
                    ),
                    if (_overrideStatus != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _overrideStatus!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _overrideStatusIsError
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _SectionLabel('Data'),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.restart_alt,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Reset progress',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text(
                        'Erase all tutor learning history and start again.',
                      ),
                      onTap: _confirmReset,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PrioritySlider extends StatelessWidget {
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onChangeEnd;

  const _PrioritySlider({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 88, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          label: '$value',
          onChanged: enabled ? (v) => onChanged(v.round()) : null,
          onChangeEnd: enabled ? (_) => onChangeEnd() : null,
        ),
      ),
      SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.end)),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// A labelled slider with a discrete value chip on the right.
class _SliderTile extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderTile({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 140, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: valueLabel,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(
          width: 28,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: theme.textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}
