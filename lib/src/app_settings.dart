import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/bindings.dart';
import 'prefs_read.dart';
import 'reading_presets.dart';
import 'tutor/progress_sync.dart';

const _adminModeKey = 'tutor_admin_mode';
const _occurrenceVerseEnglishOnlyKey = 'occurrence_verse_english_only';

Future<bool> adminModeEnabled() async =>
    (await SharedPreferences.getInstance()).readBool(_adminModeKey) ?? false;

Future<void> setAdminModeEnabled(bool enabled) async =>
    (await SharedPreferences.getInstance()).setBool(_adminModeKey, enabled);

Future<bool> occurrenceVerseEnglishOnlyEnabled() async =>
    (await SharedPreferences.getInstance()).readBool(
      _occurrenceVerseEnglishOnlyKey,
    ) ??
    false;

Future<void> setOccurrenceVerseEnglishOnlyEnabled(bool enabled) async =>
    (await SharedPreferences.getInstance()).setBool(
      _occurrenceVerseEnglishOnlyKey,
      enabled,
    );

const _themeModeKey = 'theme_mode';

/// The app's light/dark choice, which [Haqor] listens to.
///
/// Held outside the widget tree because it applies to the whole app, not to
/// any one reader. [loadThemeMode] fills it before the first frame so a saved
/// choice never flashes the other theme.
final themeMode = ValueNotifier(ThemeMode.system);

Future<void> loadThemeMode() async {
  final stored = (await SharedPreferences.getInstance()).readString(
    _themeModeKey,
  );
  themeMode.value = ThemeMode.values.asNameMap()[stored] ?? ThemeMode.system;
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeMode.value = mode;
  await (await SharedPreferences.getInstance()).setString(
    _themeModeKey,
    mode.name,
  );
}

/// How the reader shows a *ketiv* — what the consonantal text writes where the
/// running text gives the *qere* the Masoretes read in its place.
///
/// Three presentations rather than one, because which reads best is a judgement
/// about the page, not about the data. They differ in how much they interrupt: a
/// superscript is quietest but easy to miss, brackets sit in the line of reading
/// and cannot be, and a marker shows nothing at all until asked.
enum KetivDisplay {
  /// The qere alone, as a printed reading edition sets it.
  hidden('Off', 'Show the read text only.'),

  /// Small grey letters, raised, immediately after the word.
  superscript('Superscript', 'Raised grey letters after the word.'),

  /// In the line of reading, bracketed.
  brackets('Brackets', 'In square brackets beside the word.'),

  /// A marker only; tapping it reveals the written form.
  marker('Marker', 'A dot to tap wherever the writing differs.');

  const KetivDisplay(this.label, this.description);

  final String label;
  final String description;
}

enum ReaderLayoutMode {
  automatic(
    'Automatic',
    'Add study and word panels as the window becomes wider.',
  ),
  focus('Focus', 'Keep the reader on its own and open details as sheets.'),
  split('Split', 'Keep one study or word panel beside the reader.'),
  threePanel(
    'Three panels',
    'Show study navigation, the passage, and word details together.',
  );

  const ReaderLayoutMode(this.label, this.description);

  final String label;
  final String description;
}

/// Which text the reader shows: the source text, the English translation,
/// or both side by side.
enum ReaderText {
  /// The Hebrew (or Syriac) alone.
  source('Hebrew', 'The Hebrew text alone.'),

  /// The English translation alone, where there is one.
  english('English', 'The English translation alone.'),

  /// Each verse's Hebrew and English side by side, their verse numbers
  /// shared between them.
  parallel(
    'Side by side',
    'The Hebrew with the English beside it, verse by verse.',
  );

  const ReaderText(this.label, this.description);

  final String label;
  final String description;

  ReaderText get next => values[(index + 1) % values.length];
}

/// How much of the interlinear a tap reveals in [ReaderView.rapid].
enum RapidReveal {
  verse('Verse', 'A tap shows the interlinear for the whole verse.'),
  word('Word', 'A tap shows the interlinear beneath that word.');

  const RapidReveal(this.label, this.description);

  final String label;
  final String description;
}

/// How a verse's Syntax view shows its tree.
enum SyntaxView {
  /// Clauses and phrases as nested, labelled blocks.
  outline('Outline'),

  /// A drawn tree diagram, panned and zoomed.
  tree('Tree');

  const SyntaxView(this.label);

  final String label;
}

class AppReadingSettings {
  const AppReadingSettings({
    required this.ntSyriac,
    required this.englishBookNames,
    required this.hebrewNumerals,
    required this.showCantillation,
    required this.glossInterlinear,
    required this.morphologyInterlinear,
    required this.highlightProperNames,
    required this.rapidReveal,
    required this.ketivDisplay,
    required this.fontSize,
    required this.fontFamily,
    required this.readerLayoutMode,
    this.syntaxRoles = false,
    this.syntaxView = SyntaxView.outline,
    this.readerText = ReaderText.source,
    this.rapidReading = false,
    this.showInterlinear = true,
    this.ntGreek = false,
  });

  /// Whether the Peshitta is set in Syriac script rather than Hebrew.
  final bool ntSyriac;

  /// Whether the reader shows the New Testament in Greek, the Textus
  /// Receptus, in place of the Peshitta. Lists of verses elsewhere keep the
  /// Peshitta, in the script [ntSyriac] says.
  final bool ntGreek;
  final bool englishBookNames;
  final bool hebrewNumerals;
  final bool showCantillation;
  final bool glossInterlinear;
  final bool morphologyInterlinear;
  final bool highlightProperNames;
  final RapidReveal rapidReveal;
  final KetivDisplay ketivDisplay;
  final double fontSize;
  final String fontFamily;
  final ReaderLayoutMode readerLayoutMode;

  /// Whether the reader underlines each word in the colour of its syntax
  /// role (subject, verb, object, …) and marks where clauses begin.
  final bool syntaxRoles;

  /// How a verse's Syntax view first shows its tree.
  final SyntaxView syntaxView;

  /// Whether the reader shows the Hebrew, the English, or both.
  final ReaderText readerText;

  /// Whether the reader shows the Hebrew alone, a tap revealing the
  /// interlinear. Toggled from the top bar, and carried here so a
  /// [ReadingPreset] can set it.
  final bool rapidReading;

  /// Whether the interlinear shows beneath every word when not rapid reading.
  /// Separate from which layers are enabled, so hiding it keeps them.
  final bool showInterlinear;

  AppReadingSettings copyWith({
    bool? ntSyriac,
    bool? englishBookNames,
    bool? hebrewNumerals,
    bool? showCantillation,
    bool? glossInterlinear,
    bool? morphologyInterlinear,
    bool? highlightProperNames,
    RapidReveal? rapidReveal,
    KetivDisplay? ketivDisplay,
    double? fontSize,
    String? fontFamily,
    ReaderLayoutMode? readerLayoutMode,
    bool? syntaxRoles,
    SyntaxView? syntaxView,
    ReaderText? readerText,
    bool? rapidReading,
    bool? showInterlinear,
    bool? ntGreek,
  }) => AppReadingSettings(
    ntSyriac: ntSyriac ?? this.ntSyriac,
    englishBookNames: englishBookNames ?? this.englishBookNames,
    hebrewNumerals: hebrewNumerals ?? this.hebrewNumerals,
    showCantillation: showCantillation ?? this.showCantillation,
    glossInterlinear: glossInterlinear ?? this.glossInterlinear,
    morphologyInterlinear: morphologyInterlinear ?? this.morphologyInterlinear,
    highlightProperNames: highlightProperNames ?? this.highlightProperNames,
    rapidReveal: rapidReveal ?? this.rapidReveal,
    ketivDisplay: ketivDisplay ?? this.ketivDisplay,
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    readerLayoutMode: readerLayoutMode ?? this.readerLayoutMode,
    syntaxRoles: syntaxRoles ?? this.syntaxRoles,
    syntaxView: syntaxView ?? this.syntaxView,
    readerText: readerText ?? this.readerText,
    rapidReading: rapidReading ?? this.rapidReading,
    showInterlinear: showInterlinear ?? this.showInterlinear,
    ntGreek: ntGreek ?? this.ntGreek,
  );
}

/// The settings the app starts from with nothing saved: the
/// [ReadingPreset.reader] preset, at a medium size in Cardo.
const kDefaultReadingSettings = AppReadingSettings(
  ntSyriac: false,
  englishBookNames: false,
  hebrewNumerals: true,
  showCantillation: true,
  glossInterlinear: false,
  morphologyInterlinear: false,
  highlightProperNames: false,
  rapidReveal: RapidReveal.verse,
  ketivDisplay: KetivDisplay.superscript,
  fontSize: 20.0,
  fontFamily: 'Cardo',
  readerLayoutMode: ReaderLayoutMode.automatic,
);

/// The fonts the reader can set its text in.
const kFontFamilies = ['Cardo', 'David Libre', 'Frank Ruhl Libre'];

const _ntSyriacKey = 'nt_syriac';
const _ntGreekKey = 'nt_greek';
const _englishBookNamesKey = 'english_book_names';
const _hebrewNumeralsKey = 'hebrew_numerals';
const _fontSizeKey = 'font_size';
const _fontFamilyKey = 'font_family';
const _showCantillationKey = 'show_cantillation';
const _glossInterlinearKey = 'gloss_interlinear';
const _morphologyInterlinearKey = 'morphology_interlinear';
// Superseded by the two below: one view cycled interlinear, Hebrew only and
// rapid reading. Read once to carry an old choice over.
const _readerViewKey = 'reader_view';
const _rapidReadingKey = 'rapid_reading';
const _showInterlinearKey = 'show_interlinear';
const _rapidRevealKey = 'rapid_reveal';
const _highlightProperNamesKey = 'highlight_proper_names';
const _syntaxRolesKey = 'syntax_roles';
const _syntaxViewKey = 'syntax_view';
const _readerTextKey = 'reader_text';
const _ketivDisplayKey = 'ketiv_display';
const _readerLayoutModeKey = 'reader_layout_mode';

/// The saved reading settings, each one missing or unreadable falling back to
/// [kDefaultReadingSettings].
AppReadingSettings readReadingSettings(SharedPreferences prefs) {
  const defaults = kDefaultReadingSettings;
  T named<T extends Enum>(List<T> values, String key, T fallback) =>
      values.asNameMap()[prefs.readString(key)] ?? fallback;
  final legacyView = prefs.readString(_readerViewKey);
  final family = prefs.readString(_fontFamilyKey);
  return AppReadingSettings(
    ntSyriac: prefs.readBool(_ntSyriacKey) ?? defaults.ntSyriac,
    ntGreek: prefs.readBool(_ntGreekKey) ?? defaults.ntGreek,
    englishBookNames:
        prefs.readBool(_englishBookNamesKey) ?? defaults.englishBookNames,
    hebrewNumerals:
        prefs.readBool(_hebrewNumeralsKey) ?? defaults.hebrewNumerals,
    showCantillation:
        prefs.readBool(_showCantillationKey) ?? defaults.showCantillation,
    glossInterlinear:
        prefs.readBool(_glossInterlinearKey) ?? defaults.glossInterlinear,
    morphologyInterlinear:
        prefs.readBool(_morphologyInterlinearKey) ??
        defaults.morphologyInterlinear,
    highlightProperNames:
        prefs.readBool(_highlightProperNamesKey) ??
        defaults.highlightProperNames,
    rapidReveal: named(
      RapidReveal.values,
      _rapidRevealKey,
      defaults.rapidReveal,
    ),
    ketivDisplay: named(
      KetivDisplay.values,
      _ketivDisplayKey,
      defaults.ketivDisplay,
    ),
    fontSize: snapFontSize(prefs.readDouble(_fontSizeKey)),
    fontFamily: kFontFamilies.contains(family) ? family! : defaults.fontFamily,
    readerLayoutMode: named(
      ReaderLayoutMode.values,
      _readerLayoutModeKey,
      defaults.readerLayoutMode,
    ),
    syntaxRoles: prefs.readBool(_syntaxRolesKey) ?? defaults.syntaxRoles,
    syntaxView: named(SyntaxView.values, _syntaxViewKey, defaults.syntaxView),
    readerText: named(ReaderText.values, _readerTextKey, defaults.readerText),
    rapidReading:
        prefs.readBool(_rapidReadingKey) ??
        (legacyView == null ? defaults.rapidReading : legacyView == 'rapid'),
    showInterlinear:
        prefs.readBool(_showInterlinearKey) ??
        (legacyView == null ? defaults.showInterlinear : legacyView != 'plain'),
  );
}

Future<void> writeReadingSettings(
  SharedPreferences prefs,
  AppReadingSettings settings,
) => Future.wait([
  prefs.setBool(_ntSyriacKey, settings.ntSyriac),
  prefs.setBool(_ntGreekKey, settings.ntGreek),
  prefs.setBool(_englishBookNamesKey, settings.englishBookNames),
  prefs.setBool(_hebrewNumeralsKey, settings.hebrewNumerals),
  prefs.setDouble(_fontSizeKey, settings.fontSize),
  prefs.setString(_fontFamilyKey, settings.fontFamily),
  prefs.setBool(_showCantillationKey, settings.showCantillation),
  prefs.setBool(_glossInterlinearKey, settings.glossInterlinear),
  prefs.setBool(_morphologyInterlinearKey, settings.morphologyInterlinear),
  prefs.setBool(_rapidReadingKey, settings.rapidReading),
  prefs.setBool(_showInterlinearKey, settings.showInterlinear),
  prefs.remove(_readerViewKey),
  prefs.setString(_rapidRevealKey, settings.rapidReveal.name),
  prefs.setBool(_highlightProperNamesKey, settings.highlightProperNames),
  prefs.setBool(_syntaxRolesKey, settings.syntaxRoles),
  prefs.setString(_syntaxViewKey, settings.syntaxView.name),
  prefs.setString(_readerTextKey, settings.readerText.name),
  prefs.setString(_ketivDisplayKey, settings.ketivDisplay.name),
  prefs.setString(_readerLayoutModeKey, settings.readerLayoutMode.name),
]);

Future<void> showAppSettings(
  BuildContext context, {
  required AppReadingSettings readingSettings,
  required ValueChanged<AppReadingSettings> onReadingSettingsChanged,
  @visibleForTesting void Function(Object request)? sendRequest,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.8,
  ),
  builder: (_) => _AppSettingsSheet(
    readingSettings: readingSettings,
    onReadingSettingsChanged: onReadingSettingsChanged,
    sendRequest: sendRequest,
  ),
);

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet({
    required this.readingSettings,
    required this.onReadingSettingsChanged,
    this.sendRequest,
  });

  final AppReadingSettings readingSettings;
  final ValueChanged<AppReadingSettings> onReadingSettingsChanged;
  final void Function(Object request)? sendRequest;

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  StreamSubscription<RustSignalPack<TutorGlossOverrideStats>>? _overrideSub;
  late AppReadingSettings _readingSettings;
  bool _adminMode = false;
  bool _occurrenceVerseEnglishOnly = false;
  TutorGlossOverrideStats? _overrideStats;
  bool _optimizingOverrides = false;
  String? _overrideStatus;
  bool _overrideStatusIsError = false;

  @override
  void initState() {
    super.initState();
    _readingSettings = widget.readingSettings;
    _loadAdminMode();
    _loadOccurrenceVerseMode();
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
    _send(GetTutorGlossOverrideStats());
  }

  void _send(Object request) {
    final hook = widget.sendRequest;
    if (hook != null) return hook(request);
    switch (request) {
      case GetTutorGlossOverrideStats():
        request.sendSignalToRust();
      case OptimizeTutorGlossOverrides():
        request.sendSignalToRust();
    }
  }

  Future<void> _loadAdminMode() async {
    final enabled = await adminModeEnabled();
    if (mounted) setState(() => _adminMode = enabled);
  }

  Future<void> _setAdminMode(bool enabled) async {
    setState(() => _adminMode = enabled);
    await setAdminModeEnabled(enabled);
  }

  Future<void> _loadOccurrenceVerseMode() async {
    final enabled = await occurrenceVerseEnglishOnlyEnabled();
    if (mounted) setState(() => _occurrenceVerseEnglishOnly = enabled);
  }

  Future<void> _setOccurrenceVerseMode(bool enabled) async {
    setState(() => _occurrenceVerseEnglishOnly = enabled);
    await setOccurrenceVerseEnglishOnlyEnabled(enabled);
  }

  void _updateReadingSettings(AppReadingSettings settings) {
    setState(() => _readingSettings = settings);
    widget.onReadingSettingsChanged(settings);
  }

  Future<void> _applyPreset(ReadingPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Apply “${preset.label}”?'),
        content: const Text(
          'Your text and reading-help settings will be set to suit this '
          'level; you can refine any of them afterwards. Font, theme, '
          'layout, sync and admin settings are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _updateReadingSettings(preset.applyTo(_readingSettings));
    await _setOccurrenceVerseMode(preset.occurrenceEnglishOnly);
  }

  void _optimizeOverrides() {
    setState(() {
      _optimizingOverrides = true;
      _overrideStatus = 'Checking against the current core data…';
      _overrideStatusIsError = false;
    });
    _send(OptimizeTutorGlossOverrides());
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
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  const SizedBox(width: 40),
                  Expanded(
                    child: Text(
                      'Settings',
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
            ),
            const TabBar(
              tabs: [
                Tab(key: ValueKey('settings-tab-text'), text: 'Text'),
                Tab(key: ValueKey('settings-tab-helps'), text: 'Helps'),
                Tab(key: ValueKey('settings-tab-app'), text: 'App'),
                Tab(key: ValueKey('settings-tab-presets'), text: 'Presets'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SettingsTab(children: _textSettings(theme)),
                  _SettingsTab(children: _helpSettings(theme)),
                  _SettingsTab(children: _appSettings(theme)),
                  _SettingsTab(children: _presetSettings(theme)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _textSettings(ThemeData theme) => [
    _LabelledSetting(
      label: 'Text',
      footnote:
          '${_readingSettings.readerText.description} The English, for the '
          'Old Testament, is adapted from the unfoldingWord Literal Text; tap '
          'an English word for the Hebrew it translates.',
      child: SegmentedButton<ReaderText>(
        key: const ValueKey('reader-text-setting'),
        showSelectedIcon: false,
        segments: [
          for (final option in ReaderText.values)
            ButtonSegment(value: option, label: Text(option.label)),
        ],
        selected: {_readingSettings.readerText},
        onSelectionChanged: (selection) => _updateReadingSettings(
          _readingSettings.copyWith(readerText: selection.single),
        ),
      ),
    ),
    _LabelledSetting(
      label: 'Book names',
      child: SegmentedButton<bool>(
        key: const ValueKey('book-names-setting'),
        segments: const [
          ButtonSegment(value: false, label: Text('Hebrew')),
          ButtonSegment(value: true, label: Text('English')),
        ],
        selected: {_readingSettings.englishBookNames},
        onSelectionChanged: (selection) => _updateReadingSettings(
          _readingSettings.copyWith(englishBookNames: selection.single),
        ),
      ),
    ),
    _LabelledSetting(
      label: 'Verse numbers',
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('Hebrew (א׳ ב׳ ג׳)')),
          ButtonSegment(value: false, label: Text('English (1 2 3)')),
        ],
        selected: {_readingSettings.hebrewNumerals},
        onSelectionChanged: (selection) => _updateReadingSettings(
          _readingSettings.copyWith(hebrewNumerals: selection.single),
        ),
      ),
    ),
    _LabelledSetting(
      label: 'New Testament text',
      description:
          'The Peshitta in Hebrew or Syriac letters, or the Greek of the '
          'Textus Receptus.',
      child: SegmentedButton<_NtText>(
        segments: const [
          ButtonSegment(value: _NtText.hebrew, label: Text('Hebrew')),
          ButtonSegment(value: _NtText.syriac, label: Text('Syriac')),
          ButtonSegment(value: _NtText.greek, label: Text('Greek')),
        ],
        selected: {
          _readingSettings.ntGreek
              ? _NtText.greek
              : _readingSettings.ntSyriac
              ? _NtText.syriac
              : _NtText.hebrew,
        },
        onSelectionChanged: (selection) =>
            _updateReadingSettings(switch (selection.single) {
              _NtText.greek => _readingSettings.copyWith(ntGreek: true),
              _NtText.syriac => _readingSettings.copyWith(
                ntGreek: false,
                ntSyriac: true,
              ),
              _NtText.hebrew => _readingSettings.copyWith(
                ntGreek: false,
                ntSyriac: false,
              ),
            }),
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Cantillation marks'),
      subtitle: const Text('Show the chanting marks in the main Hebrew text.'),
      value: _readingSettings.showCantillation,
      onChanged: (value) => _updateReadingSettings(
        _readingSettings.copyWith(showCantillation: value),
      ),
    ),
    const SizedBox(height: 8),
    _LabelledSetting(
      label: 'Ketiv (written form)',
      description:
          'Around 1,250 places in the Hebrew Bible are read differently from '
          'how they are written. The reading is always shown; this chooses '
          'how the writing appears beside it.',
      footnote: _readingSettings.ketivDisplay.description,
      child: SegmentedButton<KetivDisplay>(
        showSelectedIcon: false,
        segments: [
          for (final option in KetivDisplay.values)
            ButtonSegment(value: option, label: Text(option.label)),
        ],
        selected: {_readingSettings.ketivDisplay},
        onSelectionChanged: (selection) => _updateReadingSettings(
          _readingSettings.copyWith(ketivDisplay: selection.single),
        ),
      ),
    ),
    _SettingsDropdown<double>(
      key: ValueKey(('font-size', _readingSettings.fontSize)),
      label: 'Font size',
      value: _readingSettings.fontSize,
      options: kFontSizeChoices,
      onChanged: (value) =>
          _updateReadingSettings(_readingSettings.copyWith(fontSize: value)),
    ),
    const SizedBox(height: 12),
    _SettingsDropdown<String>(
      key: ValueKey(('font', _readingSettings.fontFamily)),
      label: 'Font',
      value: _readingSettings.fontFamily,
      options: const {
        'Cardo': 'Cardo',
        'David Libre': 'David Libre',
        'Frank Ruhl Libre': 'Frank Ruhl Libre',
      },
      onChanged: (value) =>
          _updateReadingSettings(_readingSettings.copyWith(fontFamily: value)),
    ),
  ];

  List<Widget> _helpSettings(ThemeData theme) => [
    const _SectionLabel('Interlinear'),
    SwitchListTile(
      key: const ValueKey('gloss-interlinear-setting'),
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
      title: const Text('Morphology interlinear'),
      subtitle: const Text('Show compact morphology beneath each Hebrew word.'),
      value: _readingSettings.morphologyInterlinear,
      onChanged: (value) => _updateReadingSettings(
        _readingSettings.copyWith(morphologyInterlinear: value),
      ),
    ),
    const SizedBox(height: 8),
    _LabelledSetting(
      label: 'Rapid reading reveals',
      description:
          'Rapid reading, chosen from the reader\'s top bar, shows the Hebrew '
          'alone and a tap reveals the interlinear. Long press or right-click '
          'a word for its details.',
      footnote: _readingSettings.rapidReveal.description,
      child: SegmentedButton<RapidReveal>(
        showSelectedIcon: false,
        segments: [
          for (final option in RapidReveal.values)
            ButtonSegment(value: option, label: Text(option.label)),
        ],
        selected: {_readingSettings.rapidReveal},
        onSelectionChanged: (selection) => _updateReadingSettings(
          _readingSettings.copyWith(rapidReveal: selection.single),
        ),
      ),
    ),
    const SizedBox(height: 8),
    const _SectionLabel('Highlighting'),
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
    SwitchListTile(
      key: const ValueKey('syntax-roles-setting'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Colour syntax roles'),
      subtitle: const Text(
        'Underline each Hebrew word in the colour of its role (subject, '
        'verb, object, predicate, adverbial) and mark where clauses begin.',
      ),
      value: _readingSettings.syntaxRoles,
      onChanged: (value) =>
          _updateReadingSettings(_readingSettings.copyWith(syntaxRoles: value)),
    ),
    const SizedBox(height: 8),
    const _SectionLabel('Word and verse details'),
    _LabelledSetting(
      label: 'Syntax view',
      description:
          'How a verse\'s syntax first shows, opened from its verse menu. '
          'Either view can switch to the other.',
      child: SegmentedButton<SyntaxView>(
        key: const ValueKey('syntax-view-setting'),
        showSelectedIcon: false,
        segments: [
          for (final option in SyntaxView.values)
            ButtonSegment(value: option, label: Text(option.label)),
        ],
        selected: {_readingSettings.syntaxView},
        onSelectionChanged: (selection) => _updateReadingSettings(
          _readingSettings.copyWith(syntaxView: selection.single),
        ),
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('English-only occurrences'),
      subtitle: const Text(
        'Show the English reader gloss instead of the Hebrew text in the '
        'word-info occurrences list.',
      ),
      value: _occurrenceVerseEnglishOnly,
      onChanged: _setOccurrenceVerseMode,
    ),
  ];

  List<Widget> _appSettings(ThemeData theme) => [
    _LabelledSetting(
      label: 'Theme',
      child: ValueListenableBuilder(
        valueListenable: themeMode,
        builder: (context, mode, _) => SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dark'),
            ),
          ],
          showSelectedIcon: false,
          selected: {mode},
          onSelectionChanged: (selection) => setThemeMode(selection.single),
        ),
      ),
    ),
    _LabelledSetting(
      label: 'Large-screen layout',
      footnote: _readingSettings.readerLayoutMode.description,
      child: DropdownButtonFormField<ReaderLayoutMode>(
        key: ValueKey(('layout', _readingSettings.readerLayoutMode)),
        initialValue: _readingSettings.readerLayoutMode,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          for (final mode in ReaderLayoutMode.values)
            DropdownMenuItem(value: mode, child: Text(mode.label)),
        ],
        onChanged: (mode) {
          if (mode == null) return;
          _updateReadingSettings(
            _readingSettings.copyWith(readerLayoutMode: mode),
          );
        },
      ),
    ),
    if (progressSyncSupported) ...[
      const _SectionLabel('Sync'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.sync),
        title: const Text('Sync over your LAN'),
        subtitle: const Text(
          'Keep progress, corrections and reports in sync with your personal '
          'server.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => showProgressSyncSettings(context),
      ),
      const SizedBox(height: 12),
    ],
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
        label: Text(_optimizingOverrides ? 'Checking…' : 'Optimise overrides'),
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
  ];

  List<Widget> _presetSettings(ThemeData theme) => [
    const _SectionLabel('How familiar are you with Hebrew?'),
    Text(
      'A preset sets the text and reading helps to suit your level in one '
      'go, as a starting point to refine from. Nothing is locked: change '
      'any setting afterwards. Font, theme, layout, sync and admin settings '
      'are kept.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 16),
    for (final preset in ReadingPreset.values) ...[
      ReadingPresetCard(
        key: ValueKey('settings-preset-${preset.name}'),
        preset: preset,
        onTap: () => _applyPreset(preset),
      ),
      const SizedBox(height: 12),
    ],
  ];
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: children,
  );
}

/// A setting with its label above it, an optional explanation between them,
/// and an optional note below about the current choice.
class _LabelledSetting extends StatelessWidget {
  const _LabelledSetting({
    required this.label,
    required this.child,
    this.description,
    this.footnote,
  });

  final String label;
  final String? description;
  final String? footnote;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noteStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description!, style: noteStyle),
          ],
          const SizedBox(height: 8),
          child,
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(footnote!, style: noteStyle),
          ],
        ],
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
    super.key,
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

/// The font sizes the settings menu offers, with their labels.
final kFontSizeChoices = <double, String>{
  13.0: 'Extra small',
  16.0: 'Small',
  20.0: 'Medium',
  24.0: 'Large',
  28.0: 'Extra large',
};

/// The menu choice nearest a saved size, or Medium when there is none.
///
/// The menu asserts on a value that is not one of its choices, and a saved
/// size can be anything.
double snapFontSize(double? saved) {
  if (saved == null || !saved.isFinite) return 20.0;
  return kFontSizeChoices.keys.reduce(
    (best, size) => (size - saved).abs() < (best - saved).abs() ? size : best,
  );
}

/// The New Testament texts the setting chooses between.
enum _NtText { hebrew, syriac, greek }
