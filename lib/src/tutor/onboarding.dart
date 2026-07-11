import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import 'loading_message.dart';
import 'study_flow.dart';
import 'transliterate.dart';

const String _hebrewFont = 'Cardo';
const List<String> _hebrewFallback = ['Noto Serif Hebrew'];

enum _OnboardStep { loading, askAlphabet, calibrating, done }

/// Entry point for the tutor. A brand-new learner would otherwise have to
/// grind through every glyph and every common word one SM-2 card at a time
/// before reaching anything actually new to them — this offers a one-time
/// onboarding calibration first: a self-report on the alphabet, then (if
/// known) a binary search over word-frequency rank using real verses as the
/// probe, to seed a sensible vocabulary baseline. Skipped straight to
/// [StudyFlowPage] once any progress already exists (see
/// `Bible::needs_onboarding` on the Rust side).
class TutorEntryPage extends StatefulWidget {
  const TutorEntryPage({super.key});

  @override
  State<TutorEntryPage> createState() => _TutorEntryPageState();
}

class _TutorEntryPageState extends State<TutorEntryPage> {
  StreamSubscription<RustSignalPack<OnboardingStatus>>? _statusSub;
  StreamSubscription<RustSignalPack<CalibrationProbe>>? _probeSub;

  _OnboardStep _step = _OnboardStep.loading;
  int _tierCount = 0;

  // Binary search bounds over difficulty tier (0 = easiest — the most common
  // rarest-word verse in the corpus). Raw word-frequency rank isn't usable as
  // the search domain here: Biblical Hebrew's frequency tail is dominated by
  // hapax legomena, so most of the rank space collapses to one plateau of
  // identical verses. Tiers are the distinct difficulty values, so every step
  // probes a genuinely different verse.
  int _lo = 0;
  int _hi = 0;
  // The last confirmed-readable probe's threshold (0 = nothing confirmed
  // yet), handed to FinishCalibration verbatim.
  int _cutoff = 0;
  int? _pendingTier;
  CalibrationProbe? _probe;

  @override
  void initState() {
    super.initState();
    _statusSub = OnboardingStatus.rustSignalStream.listen(_onStatus);
    _probeSub = CalibrationProbe.rustSignalStream.listen(_onProbe);
    GetOnboardingStatus().sendSignalToRust();
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _probeSub?.cancel();
    super.dispose();
  }

  void _onStatus(RustSignalPack<OnboardingStatus> pack) {
    if (!mounted) return;
    final s = pack.message;
    setState(() {
      if (!s.needed) {
        _step = _OnboardStep.done;
      } else {
        _tierCount = s.tierCount;
        _step = _OnboardStep.askAlphabet;
      }
    });
  }

  void _knowsAlphabet(bool known) {
    if (known) SetAlphabetKnown(known: true).sendSignalToRust();
    if (!known || _tierCount == 0) {
      setState(() => _step = _OnboardStep.done);
      return;
    }
    _lo = 0;
    _hi = _tierCount - 1;
    _cutoff = 0;
    setState(() => _step = _OnboardStep.calibrating);
    _askNext();
  }

  void _askNext() {
    if (_lo > _hi) {
      _finishCalibration();
      return;
    }
    final mid = _lo + (_hi - _lo) ~/ 2;
    _pendingTier = mid;
    setState(() => _probe = null);
    GetCalibrationProbe(tier: mid).sendSignalToRust();
  }

  void _onProbe(RustSignalPack<CalibrationProbe> pack) {
    if (!mounted) return;
    final p = pack.message;
    if (p.tier != _pendingTier) return; // stale reply from an earlier step
    if (!p.found) {
      // No verse anchors this tier (edge of the corpus) — treat as unread
      // and keep narrowing.
      _answer(false);
      return;
    }
    setState(() => _probe = p);
  }

  /// `readable`: whether the learner says they could read the current probe
  /// verse smoothly. Narrows the search toward the hardest tier still
  /// readable, then asks the next probe.
  void _answer(bool readable) {
    final mid = _pendingTier!;
    if (readable) {
      _cutoff = _probe!.minOccurrences;
      _lo = mid + 1;
    } else {
      _hi = mid - 1;
    }
    _askNext();
  }

  void _finishCalibration() {
    FinishCalibration(minOccurrences: _cutoff).sendSignalToRust();
    setState(() => _step = _OnboardStep.done);
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _OnboardStep.loading:
        return const Scaffold(
          body: Center(child: LoadingMessage(text: 'Setting up your tutor…')),
        );
      case _OnboardStep.askAlphabet:
        return _AlphabetQuestion(onAnswer: _knowsAlphabet);
      case _OnboardStep.calibrating:
        return _CalibrationView(probe: _probe, onAnswer: _answer);
      case _OnboardStep.done:
        return const StudyFlowPage();
    }
  }
}

class _AlphabetQuestion extends StatelessWidget {
  const _AlphabetQuestion({required this.onAnswer});

  final void Function(bool known) onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Before you start')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.waving_hand_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Do you already know the Hebrew alphabet?',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                "If so, we'll do a quick check and skip straight to what's "
                "actually new to you.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => onAnswer(false),
                child: const Text("No, I'm starting from scratch"),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => onAnswer(true),
                child: const Text('Yes, I can already read Hebrew'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One step of the vocabulary-calibration binary search: shows the probe
/// verse (or a spinner while it loads) and asks whether the learner could
/// read it smoothly.
class _CalibrationView extends StatelessWidget {
  const _CalibrationView({required this.probe, required this.onAnswer});

  final CalibrationProbe? probe;
  final void Function(bool readable) onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final probe = this.probe;
    return Scaffold(
      appBar: AppBar(title: const Text('Quick vocabulary check')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: probe == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Could you read this verse smoothly?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      refLabel(probe.book, probe.chapter, probe.verse),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      stripCantillation(probe.text),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontFamily: _hebrewFont,
                        fontFamilyFallback: _hebrewFallback,
                        fontSize: 32,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => onAnswer(false),
                          icon: const Icon(Icons.close),
                          label: const Text('Too hard'),
                        ),
                        const SizedBox(width: 16),
                        FilledButton.icon(
                          onPressed: () => onAnswer(true),
                          icon: const Icon(Icons.check),
                          label: const Text('I can read this'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
