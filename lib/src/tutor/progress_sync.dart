import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rinf/rinf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bindings/bindings.dart';
import '../prefs_read.dart';
import 'sync_join.dart';

// Every address, one per line. The single-address key is still written with
// the first address so older haqor-admin builds, which read the desktop app's
// preferences, keep finding a server.
const _serverUrlsKey = 'progress_sync_server_urls';
const _serverUrlKey = 'progress_sync_server_url';
const _pinKey = 'progress_sync_cert_pin';
const _tokenKey = 'progress_sync_token';
const _userKey = 'progress_sync_user';
// The address that answered last, tried first next time so a device that is
// usually on one network does not wait out the others on every sync.
const _lastServerKey = 'progress_sync_last_server';

/// LAN sync needs TCP and file access that the browser's WebAssembly build of
/// the core does not have, so on the web it is neither offered nor started.
bool progressSyncSupported = !kIsWeb;

/// Set once the native layer is running and has had its first sync request;
/// a join link opened before then saves its settings and leaves the sync to
/// start-up.
bool progressSyncReady = false;

/// This device's sync settings.
@immutable
class ProgressSyncConfig {
  const ProgressSyncConfig({
    required this.servers,
    required this.pin,
    required this.token,
    this.user = '',
    this.lastServer = '',
  });

  static const empty = ProgressSyncConfig(servers: [], pin: '', token: '');

  factory ProgressSyncConfig.fromJoinLink(SyncJoinLink link) =>
      ProgressSyncConfig(
        servers: link.servers,
        pin: link.pin,
        token: link.token,
        user: link.user,
      );

  final List<String> servers;
  final String pin;
  final String token;
  final String user;
  final String lastServer;

  bool get isConfigured => servers.isNotEmpty && token.isNotEmpty;

  /// Whether any address is plain `http://`. Such settings predate HTTPS
  /// join links, and sharing them would pass plain HTTP on to the next
  /// device.
  bool get usesPlainHttp =>
      servers.any((s) => s.trim().toLowerCase().startsWith('http://'));

  /// Servers in the order to try them: the one that answered last first,
  /// then the rest in their configured order.
  List<String> get tryOrder => [
    if (servers.contains(lastServer)) lastServer,
    ...servers.where((s) => s != lastServer),
  ];

  /// The link another device can join with.
  SyncJoinLink get joinLink =>
      SyncJoinLink(user: user, servers: servers, pin: pin, token: token);
}

List<String> _lines(String? text) => (text ?? '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

Future<ProgressSyncConfig> loadProgressSyncConfig() async {
  final prefs = await SharedPreferences.getInstance();
  var servers = _lines(prefs.readString(_serverUrlsKey));
  if (servers.isEmpty) servers = _lines(prefs.readString(_serverUrlKey));
  return ProgressSyncConfig(
    servers: servers,
    pin: prefs.readString(_pinKey)?.trim() ?? '',
    token: prefs.readString(_tokenKey)?.trim() ?? '',
    user: prefs.readString(_userKey)?.trim() ?? '',
    lastServer: prefs.readString(_lastServerKey)?.trim() ?? '',
  );
}

/// Save `config`, or turn sync off when it has no servers.
Future<void> saveProgressSyncConfig(ProgressSyncConfig config) async {
  final prefs = await SharedPreferences.getInstance();
  if (config.servers.isEmpty) {
    for (final key in [
      _serverUrlsKey,
      _serverUrlKey,
      _pinKey,
      _tokenKey,
      _userKey,
      _lastServerKey,
    ]) {
      await prefs.remove(key);
    }
    return;
  }
  await prefs.setString(_serverUrlsKey, config.servers.join('\n'));
  await prefs.setString(_serverUrlKey, config.servers.first);
  await prefs.setString(_tokenKey, config.token);
  if (config.pin.isEmpty) {
    await prefs.remove(_pinKey);
  } else {
    await prefs.setString(_pinKey, config.pin);
  }
  if (config.user.isEmpty) {
    await prefs.remove(_userKey);
  } else {
    await prefs.setString(_userKey, config.user);
  }
  // A new address list starts without a remembered address.
  await prefs.remove(_lastServerKey);
}

Timer? _scheduledSync;

// Syncs handed to Rust whose status has not come back. Rust runs them one at a
// time and answers each once, in order, so a status belongs to a request only
// after the ones sent before it have been answered.
int _syncsInFlight = 0;
StreamSubscription<RustSignalPack<ProgressSyncStatus>>? _inFlightSub;

/// How many syncs Rust has yet to answer.
int get syncsInFlight => _syncsInFlight;

void _sendSync(ProgressSyncConfig config) {
  _inFlightSub ??= ProgressSyncStatus.rustSignalStream.listen((pack) {
    if (_syncsInFlight > 0) _syncsInFlight--;
    final answered = pack.message.serverUrl;
    if (pack.message.success && answered.isNotEmpty) {
      unawaited(
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString(_lastServerKey, answered),
        ),
      );
    }
  });
  _syncsInFlight++;
  SyncProgress(
    serverUrls: config.tryOrder,
    certPin: config.pin,
    token: config.token,
  ).sendSignalToRust();
}

/// Synchronise after a short quiet period, so quickly flagging several words
/// in a verse creates one LAN request rather than one per tap.
void scheduleProgressSync() {
  if (!progressSyncSupported) return;
  _scheduledSync?.cancel();
  _scheduledSync = Timer(const Duration(seconds: 2), () {
    syncProgressNow();
  });
}

/// Request one merge when a server has been configured. It is harmless offline:
/// the native layer reports the error and the next answer/launch retries.
/// Returns false when sync has not been configured, otherwise true once the
/// request has been handed to Rust.
Future<bool> syncProgressNow({VoidCallback? onRequest}) async {
  if (!progressSyncSupported) return false;
  final config = await loadProgressSyncConfig();
  if (!config.isConfigured) return false;
  onRequest?.call();
  _sendSync(config);
  return true;
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
  final _servers = TextEditingController();
  final _pin = TextEditingController();
  final _token = TextEditingController();
  StreamSubscription<RustSignalPack<ProgressSyncStatus>>? _statusSub;
  String? _status;
  bool? _syncSucceeded;
  bool _saving = false;
  // The settings as saved, which the share section offers; edits in the
  // fields are not shared until they are saved.
  ProgressSyncConfig _saved = ProgressSyncConfig.empty;
  bool _showQr = false;

  @override
  void initState() {
    super.initState();
    _load();
    _statusSub = ProgressSyncStatus.rustSignalStream.listen((pack) {
      if (!mounted) return;
      setState(() {
        _status = pack.message.message;
        _syncSucceeded = pack.message.success;
        _saving = false;
      });
    });
  }

  Future<void> _load() async {
    final config = await loadProgressSyncConfig();
    if (!mounted) return;
    setState(() {
      _saved = config;
      _servers.text = config.servers.join('\n');
      _pin.text = config.pin;
      _token.text = config.token;
    });
  }

  void _fail(String message) => setState(() {
    _status = message;
    _syncSucceeded = false;
  });

  Future<void> _pasteJoinLink() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    if (SyncJoinLink.tryParse(text) == null) {
      _fail(
        'The clipboard does not hold a Haqor join link. Copy one from '
        'haqor-sync-server join, or from a device already syncing.',
      );
      return;
    }
    final joined = await offerSyncJoin(text, context: context);
    if (joined && mounted) {
      await _load();
      setState(() {
        _status = 'Joined. Syncing progress…';
        _syncSucceeded = null;
      });
    }
  }

  Future<void> _save({required bool sync}) async {
    final servers = _lines(_servers.text);
    final token = _token.text.trim();
    final pinText = _pin.text.trim();
    if (servers.isEmpty != token.isEmpty) {
      _fail('Enter both a server address and the token.');
      return;
    }
    for (final server in servers) {
      final problem = syncServerProblem(server);
      if (problem != null) {
        _fail('$server: $problem');
        return;
      }
    }
    final pin = pinText.isEmpty ? '' : normaliseSyncPin(pinText);
    if (pin == null) {
      _fail('The certificate fingerprint is 64 hex characters (SHA-256).');
      return;
    }
    if (pin.isEmpty && servers.any((s) => s.startsWith('https://'))) {
      _fail(
        'https:// addresses need the certificate fingerprint. Paste a join '
        'link to fill it in.',
      );
      return;
    }
    setState(() => _saving = true);
    // The learner name only comes from a join link; keep it while the token
    // it belongs to is unchanged.
    final config = ProgressSyncConfig(
      servers: servers,
      pin: pin,
      token: token,
      user: token == _saved.token ? _saved.user : '',
    );
    await saveProgressSyncConfig(config);
    final saved = await loadProgressSyncConfig();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _showQr = false;
    });
    if (servers.isEmpty) {
      setState(() {
        _status = 'Automatic study and progress sync is off.';
        _syncSucceeded = true;
        _saving = false;
      });
    } else if (sync) {
      setState(() {
        _status = 'Syncing progress…';
        _syncSucceeded = null;
      });
      _sendSync(saved);
    } else {
      setState(() {
        _status = 'Automatic study and progress sync is on.';
        _syncSucceeded = true;
        _saving = false;
      });
    }
  }

  Future<void> _copyJoinLink() async {
    await Clipboard.setData(
      ClipboardData(text: _saved.joinLink.toLinkString()),
    );
    if (!mounted) return;
    setState(() {
      _status =
          'Join link copied. It holds this device\'s token: share it '
          'only with your own devices.';
      _syncSucceeded = true;
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _servers.dispose();
    _pin.dispose();
    _token.dispose();
    super.dispose();
  }

  Widget _shareSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text('Add another device', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'Scan this code with the other device\'s camera, or send it the '
          'link. Anyone with it can read and change your progress.',
        ),
        if (_saved.usesPlainHttp) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This device syncs over plain HTTP, so it can only share '
                  'plain HTTP. Join this device with a link from the server '
                  '(haqor-sync-join) first, then share that.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (_showQr)
          Center(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: _saved.joinLink.toLinkString(),
                size: 240,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _showQr = !_showQr),
              icon: Icon(_showQr ? Icons.visibility_off : Icons.qr_code_2),
              label: Text(_showQr ? 'Hide QR code' : 'Show QR code'),
            ),
            TextButton.icon(
              onPressed: _copyJoinLink,
              icon: const Icon(Icons.link),
              label: const Text('Copy join link'),
            ),
          ],
        ),
      ],
    );
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
              'Study & progress sync',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _saved.user.isEmpty
                  ? 'Your app syncs on launch and after answers whenever your '
                        'sync server can be reached.'
                  : 'Syncing as ${_saved.user}. Your app syncs on launch and '
                        'after answers whenever the server can be reached.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pasteJoinLink,
              icon: const Icon(Icons.content_paste),
              label: const Text('Paste join link'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _servers,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Server addresses',
                hintText: 'https://192.168.1.10:8788',
                helperText: 'One per line, tried in order.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pin,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Certificate fingerprint (SHA-256)',
                helperText: 'Needed for https:// addresses.',
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
              Row(
                children: [
                  if (_syncSucceeded == null) ...[
                    const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _status!,
                      style: TextStyle(
                        color: _syncSucceeded == true
                            ? Theme.of(context).colorScheme.primary
                            : _syncSucceeded == false
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
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
            if (_saved.isConfigured) _shareSection(context),
          ],
        ),
      ),
    ),
  );
}
