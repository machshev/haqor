import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';
import 'app_update.dart';
import 'app_update_service.dart';
import 'boot_failure.dart';
import 'external_link.dart';
import 'prefs_read.dart';
import 'tutor/sync_join.dart';

export 'app_update_service.dart' show appUpdateSupported;

const _autoCheckKey = 'update_check_enabled';
const _lastCheckKey = 'update_check_last_ms';

/// How long the startup check stays quiet after it last asked GitHub.
const _checkInterval = Duration(hours: 20);

Future<bool> autoUpdateCheckEnabled() async =>
    (await SharedPreferences.getInstance()).readBool(_autoCheckKey) ?? true;

Future<void> setAutoUpdateCheckEnabled(bool enabled) async =>
    (await SharedPreferences.getInstance()).setBool(_autoCheckKey, enabled);

/// Ask GitHub for a newer release, at most once per [_checkInterval], and
/// offer it with a snack bar. Quiet about every failure: a missed check is
/// retried the next time Haqor starts.
Future<void> checkForUpdatesOnStartup() async {
  if (!appUpdateSupported || !await autoUpdateCheckEnabled()) return;
  final prefs = await SharedPreferences.getInstance();
  final last = prefs.readInt(_lastCheckKey);
  final now = DateTime.now().millisecondsSinceEpoch;
  if (last != null && now - last < _checkInterval.inMilliseconds) return;
  // Let the reader open first; the check is not what they started Haqor for.
  await Future<void>.delayed(const Duration(seconds: 8));
  final AppRelease release;
  try {
    release = await fetchLatestRelease();
  } catch (error) {
    debugPrint('update check failed: $error');
    return;
  }
  await prefs.setInt(_lastCheckKey, now);
  if (!release.isNewerThan(appVersion)) return;
  appMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('Haqor ${release.version} is available.'),
      duration: const Duration(seconds: 15),
      showCloseIcon: true,
      action: SnackBarAction(
        label: 'Update',
        onPressed: () {
          final context = appNavigatorKey.currentContext;
          if (context != null) unawaited(showUpdateDialog(context, release));
        },
      ),
    ),
  );
}

/// Describe [release] and, when the reader agrees, take it.
Future<void> showUpdateDialog(BuildContext context, AppRelease release) async {
  final support = await updateSupport();
  final asset = pickAsset(release, support.targets);
  if (!context.mounted) return;
  final installs = support.method == UpdateMethod.install && asset != null;
  final size = asset == null ? '' : formatDownloadSize(asset.size);
  final how = switch (support.method) {
    _ when asset == null =>
      'This release has no build for this device; see the release page.',
    UpdateMethod.install when defaultTargetPlatform == TargetPlatform.android =>
      'Haqor will download the update ($size) and open Android\'s '
          'installer. Your progress and settings are kept.',
    UpdateMethod.install =>
      'Haqor will download the update ($size), then close and restart to '
          'install it. Your progress and settings are kept.',
    UpdateMethod.download =>
      'Haqor will open the download ($size) in your browser; install it '
          'as you did the first time.',
    UpdateMethod.none => support.reason ?? '',
  };
  final go = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: Text('Haqor ${release.version}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You have $appVersion. $how'),
              if (support.reason != null &&
                  support.method == UpdateMethod.download) ...[
                const SizedBox(height: 8),
                Text(support.reason!, style: theme.textTheme.bodySmall),
              ],
              if (release.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text("What's new", style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: MarkdownBody(
                        data: _notesWithoutInstallTable(release.notes),
                        onTapLink: (_, href, _) {
                          final uri = href == null ? null : Uri.tryParse(href);
                          if (uri != null) unawaited(openExternalLink(uri));
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => unawaited(openExternalLink(release.pageUrl)),
            child: const Text('Release page'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          if (asset != null && support.method != UpdateMethod.none)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(installs ? 'Update' : 'Download'),
            ),
        ],
      );
    },
  );
  if (go != true || asset == null || !context.mounted) return;
  if (installs && !await canInstallUpdates()) {
    if (!context.mounted) return;
    await _askForInstallPermission(context);
    return;
  }
  if (!context.mounted) return;
  if (!installs) {
    await takeUpdate(support, release, asset);
    return;
  }
  await _downloadAndInstall(context, support, release, asset);
}

/// The release body opens with the workflow's per-platform install table,
/// which says nothing to someone updating; the generated notes follow it.
String _notesWithoutInstallTable(String notes) {
  final changes = notes.indexOf("## What's Changed");
  return changes >= 0 ? notes.substring(changes) : notes;
}

Future<void> _askForInstallPermission(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Allow Haqor to install updates'),
      content: const Text(
        'Android asks you to allow Haqor to install apps before it can '
        'install its own update. Turn on "Allow from this source", come back, '
        'and tap Update again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (open == true) await openInstallPermissionSettings();
}

Future<void> _downloadAndInstall(
  BuildContext context,
  UpdateSupport support,
  AppRelease release,
  ReleaseAsset asset,
) async {
  final progress = ValueNotifier<(int, int)>((0, asset.size));
  final navigator = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Downloading Haqor ${release.version}'),
          content: ValueListenableBuilder(
            valueListenable: progress,
            builder: (context, value, _) {
              final (received, total) = value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: total > 0 ? received / total : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    total > 0
                        ? '${formatDownloadSize(received)} of '
                              '${formatDownloadSize(total)}'
                        : formatDownloadSize(received),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  String? failure;
  try {
    await takeUpdate(
      support,
      release,
      asset,
      onProgress: (received, total) => progress.value = (received, total),
    );
  } on UpdateFailure catch (error) {
    failure = error.message;
  } catch (error) {
    failure = 'The update failed: $error';
  } finally {
    navigator.pop();
    progress.dispose();
  }
  if (failure != null) {
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(failure), showCloseIcon: true),
    );
  }
}

/// The Updates section of the App settings: the daily check and a button to
/// check now.
class UpdateSettings extends StatefulWidget {
  const UpdateSettings({super.key});

  @override
  State<UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends State<UpdateSettings> {
  bool _autoCheck = true;
  bool _checking = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    unawaited(
      autoUpdateCheckEnabled().then((enabled) {
        if (mounted) setState(() => _autoCheck = enabled);
      }),
    );
  }

  Future<void> _setAutoCheck(bool enabled) async {
    setState(() => _autoCheck = enabled);
    await setAutoUpdateCheckEnabled(enabled);
  }

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _status = null;
    });
    AppRelease? release;
    String? status;
    try {
      release = await fetchLatestRelease();
      if (!release.isNewerThan(appVersion)) {
        status = 'Haqor $appVersion is the latest release.';
        release = null;
      }
    } catch (error) {
      status = 'Could not check for updates: $error';
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = status ?? 'Haqor ${release!.version} is available.';
    });
    if (release != null) await showUpdateDialog(context, release);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.system_update_outlined),
          title: const Text('Check for updates'),
          subtitle: const Text(
            'Once a day, ask GitHub whether a newer Haqor has been released.',
          ),
          value: _autoCheck,
          onChanged: _setAutoCheck,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _checking ? null : _checkNow,
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_checking ? 'Checking…' : 'Check now'),
          ),
        ),
        if (_status != null) ...[
          const SizedBox(height: 6),
          Text(
            _status!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
