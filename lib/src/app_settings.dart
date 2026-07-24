import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/bindings.dart';
import 'tutor/progress_sync.dart';

const _adminModeKey = 'tutor_admin_mode';

Future<bool> adminModeEnabled() async =>
    (await SharedPreferences.getInstance()).getBool(_adminModeKey) ?? false;

Future<void> setAdminModeEnabled(bool enabled) async =>
    (await SharedPreferences.getInstance()).setBool(_adminModeKey, enabled);

class AppReadingSettings {
  const AppReadingSettings({
    required this.ntSyriac,
    required this.englishBookNames,
    required this.hebrewNumerals,
    required this.showCantillation,
    required this.glossInterlinear,
    required this.morphologyInterlinear,
    required this.highlightProperNames,
    required this.fontSize,
    required this.fontFamily,
  });

  final bool ntSyriac;
  final bool englishBookNames;
  final bool hebrewNumerals;
  final bool showCantillation;
  final bool glossInterlinear;
  final bool morphologyInterlinear;
  final bool highlightProperNames;
  final double fontSize;
  final String fontFamily;

  AppReadingSettings copyWith({
    bool? ntSyriac,
    bool? englishBookNames,
    bool? hebrewNumerals,
    bool? showCantillation,
    bool? glossInterlinear,
    bool? morphologyInterlinear,
    bool? highlightProperNames,
    double? fontSize,
    String? fontFamily,
  }) => AppReadingSettings(
    ntSyriac: ntSyriac ?? this.ntSyriac,
    englishBookNames: englishBookNames ?? this.englishBookNames,
    hebrewNumerals: hebrewNumerals ?? this.hebrewNumerals,
    showCantillation: showCantillation ?? this.showCantillation,
    glossInterlinear: glossInterlinear ?? this.glossInterlinear,
    morphologyInterlinear: morphologyInterlinear ?? this.morphologyInterlinear,
    highlightProperNames: highlightProperNames ?? this.highlightProperNames,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
  );
}

Future<void> showAppSettings(
  BuildContext context, {
  required AppReadingSettings readingSettings,
  required ValueChanged<AppReadingSettings> onReadingSettingsChanged,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
  ),
  builder: (_) => _AppSettingsSheet(
    readingSettings: readingSettings,
    onReadingSettingsChanged: onReadingSettingsChanged,
  ),
);

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet({
    required this.readingSettings,
    required this.onReadingSettingsChanged,
  });

  final AppReadingSettings readingSettings;
  final ValueChanged<AppReadingSettings> onReadingSettingsChanged;

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  StreamSubscription<RustSignalPack<TutorGlossOverrideStats>>? _overrideSub;
  late AppReadingSettings _readingSettings;
  bool _adminMode = false;
  TutorGlossOverrideStats? _overrideStats;
  bool _optimizingOverrides = false;
  String? _overrideStatus;
  bool _overrideStatusIsError = false;

  @override
  void initState() {
    super.initState();
    _readingSettings = widget.readingSettings;
    _loadAdminMode();
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
              : 'Removed ${stats.removed} no-op '
                    '${stats.removed == 1 ? 'override' : 'overrides'}.';
        }
      });
      if (wasOptimizing && stats.error.isEmpty && stats.removed > 0) {
        scheduleProgressSync();
      }
    });
    GetTutorGlossOverrideStats().sendSignalToRust();
  }

  Future<void> _loadAdminMode() async {
    final enabled = await adminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  Future<void> _setAdminMode(bool enabled) async {
    setState(() => _adminMode = enabled);
    await setAdminModeEnabled(enabled);
  }

  void _updateReadingSettings(AppReadingSettings settings) {
    setState(() => _readingSettings = settings);
    widget.onReadingSettingsChanged(settings);
  }

  void _optimizeOverrides() {
    setState(() {
      _optimizingOverrides = true;
      _overrideStatus = 'Checking against the current core data…';
      _overrideStatusIsError = false;
    });
    OptimizeTutorGlossOverrides().sendSignalToRust();
  }

  @override
  void dispose() {
    _overrideSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'App settings',
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close settings',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Reading'),
              Text('New Testament text', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Hebrew')),
                  ButtonSegment(value: true, label: Text('Syriac')),
                ],
                selected: {_readingSettings.ntSyriac},
                onSelectionChanged: (selection) => _updateReadingSettings(
                  _readingSettings.copyWith(ntSyriac: selection.single),
                ),
              ),
              const SizedBox(height: 16),
              Text('Book names', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Hebrew')),
                  ButtonSegment(value: true, label: Text('English')),
                ],
                selected: {_readingSettings.englishBookNames},
                onSelectionChanged: (selection) => _updateReadingSettings(
                  _readingSettings.copyWith(englishBookNames: selection.single),
                ),
              ),
              const SizedBox(height: 16),
              Text('Verse numbers', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Hebrew (א׳ ב׳ ג׳)')),
                  ButtonSegment(value: false, label: Text('English (1 2 3)')),
                ],
                selected: {_readingSettings.hebrewNumerals},
                onSelectionChanged: (selection) => _updateReadingSettings(
                  _readingSettings.copyWith(hebrewNumerals: selection.single),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Cantillation marks'),
                subtitle: const Text(
                  'Show the chanting marks in the main Hebrew text.',
                ),
                value: _readingSettings.showCantillation,
                onChanged: (value) => _updateReadingSettings(
                  _readingSettings.copyWith(showCantillation: value),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Morphology interlinear'),
                subtitle: const Text('Show compact morphology beneath each Hebrew word.'),
                value: _readingSettings.morphologyInterlinear,
                onChanged: (value) => _updateReadingSettings(
                  _readingSettings.copyWith(morphologyInterlinear: value),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gloss interlinear'),
                subtitle: const Text(
                  'Show an English gloss beneath each source-text word.',
                ),
                value: _readingSettings.glossInterlinear,
                onChanged: (value) => _updateReadingSettings(
                  _readingSettings.copyWith(glossInterlinear: value),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Highlight proper names'),
                subtitle: const Text(
                  'Use colour to distinguish personal and place names.',
                ),
                value: _readingSettings.highlightProperNames,
                onChanged: (value) => _updateReadingSettings(
                  _readingSettings.copyWith(highlightProperNames: value),
                ),
              ),
              const SizedBox(height: 8),
              _SettingsDropdown<double>(
                label: 'Font size',
                value: _readingSettings.fontSize,
                options: {
                  16.0: 'Small',
                  20.0: 'Medium',
                  24.0: 'Large',
                  28.0: 'Extra large',
                },
                onChanged: (value) => _updateReadingSettings(
                  _readingSettings.copyWith(fontSize: value),
                ),
              ),
              const SizedBox(height: 12),
              _SettingsDropdown<String>(
                label: 'Font',
                value: _readingSettings.fontFamily,
                options: const {
                  'Cardo': 'Cardo',
                  'David Libre': 'David Libre',
                  'Frank Ruhl Libre': 'Frank Ruhl Libre',
                },
                onChanged: (value) => _updateReadingSettings(
                  _readingSettings.copyWith(fontFamily: value),
                ),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Sync'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync),
                title: const Text('Sync over your LAN'),
                subtitle: const Text(
                  'Keep progress, corrections and reports in sync with your personal server.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showProgressSyncSettings(context),
              ),
              const SizedBox(height: 12),
              const _SectionLabel('Admin'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.admin_panel_settings_outlined),
                title: const Text('Admin tools'),
                subtitle: const Text(
                  'Show lexicon editing and issue/idea flags in the tutor and reader.',
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
                      : '${_overrideStats!.total} '
                            '${_overrideStats!.total == 1 ? 'override' : 'overrides'} '
                            'on this device${_overrideStats!.redundant == 0 ? '; all still differ from core.' : '; ${_overrideStats!.redundant} now ${_overrideStats!.redundant == 1 ? 'matches' : 'match'} core.'}',
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(
                    _optimizingOverrides ? 'Checking…' : 'Optimise overrides',
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
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SettingsDropdown<T> extends StatelessWidget {
  const _SettingsDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final option in options.entries)
        DropdownMenuItem(value: option.key, child: Text(option.value)),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
