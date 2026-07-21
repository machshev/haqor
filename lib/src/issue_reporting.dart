import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/bindings.dart';
import 'tutor/progress_sync.dart';

const _legacyFlaggedWordsKey = 'debug_flagged_words';

/// Admin-only flag button for recording a bug report or idea with structured
/// screen context. Visibility remains the caller's responsibility.
class IssueReportButton extends StatelessWidget {
  const IssueReportButton({
    super.key,
    required this.source,
    required this.contextData,
    this.tooltip = 'Report an issue or idea',
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.constraints,
  });

  final String source;
  final Map<String, Object?> contextData;
  final String tooltip;
  final double? iconSize;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const Icon(Icons.flag_outlined),
    tooltip: tooltip,
    iconSize: iconSize,
    visualDensity: visualDensity,
    padding: padding,
    constraints: constraints,
    onPressed: () => showIssueReportDialog(
      context,
      source: source,
      contextData: contextData,
    ),
  );
}

Future<void> showIssueReportDialog(
  BuildContext context, {
  required String source,
  required Map<String, Object?> contextData,
}) async {
  final draft = await showDialog<_IssueDraft>(
    context: context,
    builder: (_) => const _IssueReportDialog(),
  );
  if (draft == null || !context.mounted) return;

  final now = DateTime.now().toUtc();
  final id =
      '${now.microsecondsSinceEpoch.toRadixString(36)}-'
      '${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';
  final media = MediaQuery.maybeOf(context);
  final reportContext = <String, Object?>{
    'source': source,
    'reportedAt': now.toIso8601String(),
    'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
    if (media != null)
      'viewport': {
        'width': media.size.width,
        'height': media.size.height,
        'devicePixelRatio': media.devicePixelRatio,
        'textScaler': media.textScaler.scale(1),
      },
    'details': contextData,
  };

  final statusFuture = IssueReportStatus.rustSignalStream
      .firstWhere((pack) => pack.message.reportId == id)
      .timeout(const Duration(seconds: 8));
  SaveIssueReport(
    id: id,
    reportType: draft.reportType,
    note: draft.note,
    contextJson: jsonEncode(reportContext),
  ).sendSignalToRust();

  try {
    final status = (await statusFuture).message;
    if (status.success) scheduleProgressSync();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(status.message),
        backgroundColor: status.success
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  } on TimeoutException {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'The app did not confirm that the report was saved.',
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

/// Move reports made by the former local-only word flag into the synced issue
/// table. Successfully acknowledged rows are removed from preferences; failed
/// rows remain so a later launch can retry without losing the note.
Future<void> migrateLegacyFlaggedWords() async {
  final prefs = await SharedPreferences.getInstance();
  final rawEntries = prefs.getStringList(_legacyFlaggedWordsKey) ?? const [];
  if (rawEntries.isEmpty) return;

  final remaining = <String>[];
  var migratedAny = false;
  for (final raw in rawEntries) {
    try {
      final legacy = jsonDecode(raw) as Map<String, dynamic>;
      final word = legacy['word'] as String? ?? '';
      final flaggedAt = legacy['flaggedAt'] as String? ?? '';
      final stableKey = base64Url
          .encode(utf8.encode('$flaggedAt|$word'))
          .replaceAll('=', '');
      final id = 'legacy-$stableKey';
      final statusFuture = IssueReportStatus.rustSignalStream
          .firstWhere((pack) => pack.message.reportId == id)
          .timeout(const Duration(seconds: 8));
      SaveIssueReport(
        id: id,
        reportType: 'bug',
        note: (legacy['note'] as String? ?? '').trim().isEmpty
            ? 'Legacy word flag (no note provided).'
            : (legacy['note'] as String).trim(),
        contextJson: jsonEncode({
          'source': 'legacy_word_flag',
          'reportedAt': flaggedAt,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          'locale': PlatformDispatcher.instance.locale.toLanguageTag(),
          'details': legacy,
        }),
      ).sendSignalToRust();
      final status = (await statusFuture).message;
      if (status.success) {
        migratedAny = true;
      } else {
        remaining.add(raw);
      }
    } on Object {
      remaining.add(raw);
    }
  }
  if (remaining.length != rawEntries.length) {
    await prefs.setStringList(_legacyFlaggedWordsKey, remaining);
  }
  if (migratedAny) scheduleProgressSync();
}

class _IssueDraft {
  const _IssueDraft({required this.reportType, required this.note});

  final String reportType;
  final String note;
}

class _IssueReportDialog extends StatefulWidget {
  const _IssueReportDialog();

  @override
  State<_IssueReportDialog> createState() => _IssueReportDialogState();
}

class _IssueReportDialogState extends State<_IssueReportDialog> {
  final _controller = TextEditingController();
  String _reportType = 'bug';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Log an app issue'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'bug',
                icon: Icon(Icons.bug_report_outlined),
                label: Text('Bug'),
              ),
              ButtonSegment(
                value: 'idea',
                icon: Icon(Icons.lightbulb_outline),
                label: Text('Idea'),
              ),
            ],
            selected: {_reportType},
            onSelectionChanged: (selection) =>
                setState(() => _reportType = selection.single),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            // Android's native selection overlay can remain active above this
            // modal after a tap, preventing subsequent taps from reaching the
            // dialog. Issue notes are short, so keep normal editing while
            // disabling text-selection gestures here.
            enableInteractiveSelection: false,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'What happened, or what would you like to improve?',
              helperText:
                  'The current screen/card context is included automatically.',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                _IssueDraft(
                  reportType: _reportType,
                  note: _controller.text.trim(),
                ),
              ),
        child: const Text('Save'),
      ),
    ],
  );
}
