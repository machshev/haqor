import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bindings/bindings.dart';

const _serverUrlKey = 'progress_sync_server_url';
const _tokenKey = 'progress_sync_token';

Timer? _scheduledSync;

/// Synchronise after a short quiet period, so quickly flagging several words
/// in a verse creates one LAN request rather than one per tap.
void scheduleProgressSync() {
  _scheduledSync?.cancel();
  _scheduledSync = Timer(const Duration(seconds: 2), syncProgressNow);
}

/// Request one merge when a server has been configured. It is harmless offline:
/// the native layer reports the error and the next answer/launch retries.
Future<void> syncProgressNow() async {
  final prefs = await SharedPreferences.getInstance();
  final serverUrl = prefs.getString(_serverUrlKey)?.trim() ?? '';
  final token = prefs.getString(_tokenKey)?.trim() ?? '';
  if (serverUrl.isEmpty || token.isEmpty) return;
  SyncProgress(serverUrl: serverUrl, token: token).sendSignalToRust();
}

Future<void> showProgressSyncSettings(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _ProgressSyncSheet(),
    );

class _ProgressSyncSheet extends StatefulWidget {
  const _ProgressSyncSheet();

  @override
  State<_ProgressSyncSheet> createState() => _ProgressSyncSheetState();
}

class _ProgressSyncSheetState extends State<_ProgressSyncSheet> {
  final _server = TextEditingController();
  final _token = TextEditingController();
  StreamSubscription<RustSignalPack<ProgressSyncStatus>>? _statusSub;
  String? _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    _statusSub = ProgressSyncStatus.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() => _status = pack.message.message);
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _server.text = prefs.getString(_serverUrlKey) ?? '';
      _token.text = prefs.getString(_tokenKey) ?? '';
    });
  }

  Future<void> _save({required bool sync}) async {
    final serverUrl = _server.text.trim();
    final token = _token.text.trim();
    if ((serverUrl.isEmpty) != (token.isEmpty)) {
      setState(() => _status = 'Enter both the server address and token.');
      return;
    }
    if (serverUrl.isNotEmpty && !serverUrl.startsWith('http://')) {
      setState(() => _status = 'Use a LAN address starting with http://');
      return;
    }
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    if (serverUrl.isEmpty) {
      await prefs.remove(_serverUrlKey);
      await prefs.remove(_tokenKey);
      if (mounted) setState(() => _status = 'Automatic progress sync is off.');
    } else {
      await prefs.setString(_serverUrlKey, serverUrl);
      await prefs.setString(_tokenKey, token);
      if (sync) {
        SyncProgress(serverUrl: serverUrl, token: token).sendSignalToRust();
      } else if (mounted) {
        setState(() => _status = 'Automatic progress sync is on.');
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _server.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Progress sync',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Your app syncs on launch and after answers while this trusted LAN server is available.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _server,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Server address',
                hintText: 'http://192.168.1.10:8788',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              autocorrect: false,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Sync token'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(
                _status!,
                style: TextStyle(
                  color: _status == 'Progress synced.'
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => _save(sync: false),
                  child: const Text('Save'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _save(sync: true),
                  icon: const Icon(Icons.sync),
                  label: const Text('Save & sync now'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
