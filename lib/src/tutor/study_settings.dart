import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';

/// Open the study-pacing settings as a modal bottom sheet.
Future<void> showStudySettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _SettingsSheet(),
);

/// Configure how fast the tutor progresses: how many new letters and words are
/// introduced at once, and whether grammar rules expand one at a time. Fetches
/// the current [TutorSettings] on open and writes changes back with
/// [SetTutorSettings]; the engine picks them up on the next card.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  StreamSubscription<RustSignalPack<TutorSettings>>? _sub;

  int _lettersPerBatch = 3;
  int _wordsPerBatch = 8;
  bool _grammarGating = true;
  int _vocabRatio = 75;
  bool _loaded = false;

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
  }

  void _adopt(TutorSettings s) {
    _lettersPerBatch = s.lettersPerBatch;
    _wordsPerBatch = s.wordsPerBatch;
    _grammarGating = s.grammarGating;
    _vocabRatio = s.vocabRatio;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _send() {
    SetTutorSettings(
      lettersPerBatch: _lettersPerBatch,
      wordsPerBatch: _wordsPerBatch,
      grammarGating: _grammarGating,
      vocabRatio: _vocabRatio,
    ).sendSignalToRust();
  }

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
            : Column(
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
                    onChanged: (v) => setState(() => _wordsPerBatch = v.round()),
                    onChangeEnd: (_) => _send(),
                  ),
                  Text(
                    'Fewer at once means each is drilled to memory before the '
                    'next arrives — a gentler ramp.',
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
                  Opacity(
                    opacity: _grammarGating ? 1 : 0.4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Balance',
                          style: theme.textTheme.labelLarge,
                        ),
                        Slider(
                          value: _vocabRatio.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: _vocabRatio >= 50
                              ? 'Vocabulary +${_vocabRatio - 50}'
                              : 'Grammar +${50 - _vocabRatio}',
                          onChanged: _grammarGating
                              ? (v) => setState(() => _vocabRatio = v.round())
                              : null,
                          onChangeEnd: _grammarGating ? (_) => _send() : null,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'More grammar',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              'More vocabulary',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'How much vocabulary to learn before each new grammar '
                          'rule unlocks.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
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
