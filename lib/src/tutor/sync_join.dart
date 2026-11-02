import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../boot_failure.dart';
import 'progress_sync.dart';

/// Lets a deep link open a dialog over whatever page is showing.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Everything a device needs to join sync, as carried by a join link:
///
/// `haqor://join?user=alice&server=https://10.0.0.2:8788&server=https://sync-host.lan:8788&pin=…&token=…`
///
/// `haqor-sync-server join` prints these, and a device already joined can show
/// its own as a QR code for the next device to scan.
@immutable
class SyncJoinLink {
  const SyncJoinLink({
    required this.user,
    required this.servers,
    required this.pin,
    required this.token,
  });

  /// The learner the token belongs to, shown so the right person joins.
  final String user;

  /// Addresses in the order to try them.
  final List<String> servers;

  /// Lowercase hex SHA-256 of the server's certificate; empty when every
  /// address is plain `http://`.
  final String pin;

  final String token;

  /// Parse a pasted or opened link, or return null when it is not a usable
  /// join link.
  static SyncJoinLink? tryParse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'haqor' || uri.host != 'join') {
      return null;
    }
    final query = uri.queryParametersAll;
    String one(String key) => (query[key]?.firstOrNull ?? '').trim();
    final servers = (query['server'] ?? const [])
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final token = one('token');
    if (servers.isEmpty || token.length < 16) return null;
    if (servers.any((s) => syncServerProblem(s) != null)) return null;
    final pin = normaliseSyncPin(one('pin'));
    final needsPin = servers.any((s) => s.startsWith('https://'));
    if (needsPin && pin == null) return null;
    return SyncJoinLink(
      user: one('user'),
      servers: List.unmodifiable(servers),
      pin: pin ?? '',
      token: token,
    );
  }

  /// The link as text, in the same form the server prints. `:` and `/` stay
  /// readable (both are legal in a query), which keeps the QR code small.
  String toLinkString() {
    final parts = [
      if (user.isNotEmpty) 'user=${_encode(user)}',
      for (final server in servers) 'server=${_encode(server)}',
      if (pin.isNotEmpty) 'pin=${_encode(pin)}',
      'token=${_encode(token)}',
    ];
    return 'haqor://join?${parts.join('&')}';
  }

  static String _encode(String value) {
    final out = StringBuffer();
    for (final byte in value.codeUnits) {
      final c = String.fromCharCode(byte);
      if (RegExp(r'[A-Za-z0-9\-._~:/]').hasMatch(c) && byte < 128) {
        out.write(c);
      } else {
        out.write(Uri.encodeQueryComponent(c).replaceAll('+', '%20'));
      }
    }
    return out.toString();
  }
}

/// Null when `server` is a usable sync address, otherwise why it is not.
String? syncServerProblem(String server) {
  final uri = Uri.tryParse(server.trim());
  if (uri == null ||
      !(uri.scheme == 'https' || uri.scheme == 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return 'Addresses start with https:// (or http://), for example '
        'https://192.168.1.10:8788.';
  }
  return null;
}

/// A certificate fingerprint as lowercase hex without separators, or null
/// when `pin` is not a SHA-256 fingerprint.
String? normaliseSyncPin(String pin) {
  final hex = pin.trim().replaceAll(':', '').toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(hex) ? hex : null;
}

StreamSubscription<Uri>? _linkSub;

/// Listen for `haqor://join` links opened from a phone camera, a message or a
/// browser, and offer to join with each one. Native only: the browser build
/// does not sync.
void listenForSyncJoinLinks() {
  if (!progressSyncSupported || _linkSub != null) return;
  try {
    _linkSub = AppLinks().uriLinkStream.listen(
      (uri) => unawaited(offerSyncJoin(uri.toString())),
      onError: (Object error) => debugPrint('join link error: $error'),
    );
  } catch (error) {
    // A platform without a link handler simply never offers joining this
    // way; pasting the link in sync settings still works.
    debugPrint('join links unavailable: $error');
  }
}

/// Ask before replacing this device's sync settings with `text`'s. Returns
/// true when the learner joined.
Future<bool> offerSyncJoin(String text, {BuildContext? context}) async {
  final link = SyncJoinLink.tryParse(text);
  // A deep link can arrive before the first frame; wait for a navigator.
  for (var i = 0; i < 50 && context == null; i++) {
    final current = appNavigatorKey.currentContext;
    if (current != null) {
      context = current;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (context == null || !context.mounted) return false;
  if (link == null) {
    appMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('That is not a Haqor sync join link.')),
    );
    return false;
  }
  final current = await loadProgressSyncConfig();
  if (!context.mounted) return false;
  final joined = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Join study & progress sync?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            link.user.isEmpty
                ? 'This device will sync with:'
                : 'This device will sync as ${link.user} with:',
          ),
          const SizedBox(height: 8),
          for (final server in link.servers)
            Text(server, style: const TextStyle(fontFamily: 'monospace')),
          if (current.isConfigured) ...[
            const SizedBox(height: 12),
            const Text(
              'This replaces the sync settings already on this device. '
              'Progress on this device is kept and merged.',
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Join'),
        ),
      ],
    ),
  );
  if (joined != true) return false;
  await saveProgressSyncConfig(ProgressSyncConfig.fromJoinLink(link));
  final started = progressSyncReady && await syncProgressNow();
  appMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(
        started
            ? 'Joined sync${link.user.isEmpty ? '' : ' as ${link.user}'}. Syncing…'
            : 'Joined sync. This device will sync when Haqor has started.',
      ),
    ),
  );
  return true;
}
