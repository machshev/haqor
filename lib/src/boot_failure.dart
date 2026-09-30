import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'bindings/bindings.dart';

/// Rust could not open the databases. [message] is its reason.
class BootFailure implements Exception {
  const BootFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turn Rust's report on opening the databases into what the boot needs: null
/// when all is well, a notice for the learner when the app opened with fresh
/// progress, or a [BootFailure] when it could not open at all.
String? bootNotice(BootStatus status) {
  if (status.failed) throw BootFailure(status.message);
  return status.progressReset ? status.message : null;
}

/// Hand Rust the database location (and, on the web, the bundle) and wait for
/// it to say whether they opened. Returns [bootNotice]'s notice.
Future<String?> openDatabases(String path, Uint8List binary) async {
  // Listen before sending: Rust answers every attempt, failed ones too.
  final status = BootStatus.rustSignalStream.first;
  SetDataDir(path: path).sendSignalToRust(binary);
  return bootNotice((await status).message);
}

/// Shows [child] once the databases are open. Where they could not be, it says
/// why and offers to try again, and to reinstall them where [reinstall] is
/// given (they are copied from the app's assets, so a damaged copy can be
/// replaced).
class BootGate extends StatefulWidget {
  const BootGate({
    super.key,
    required this.start,
    required this.child,
    this.reinstall,
    this.onReady,
    this.initialFailure,
    this.initialNotice,
  });

  /// Open the databases again, as at startup.
  final Future<String?> Function() start;
  final Future<String?> Function()? reinstall;
  final Widget child;

  /// Work that needs the databases, run once they are open.
  final VoidCallback? onReady;
  final String? initialFailure;
  final String? initialNotice;

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  late String? _failure = widget.initialFailure;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (_failure == null) {
      widget.onReady?.call();
      _announce(widget.initialNotice);
    }
  }

  void _announce(String? notice) {
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(notice), duration: const Duration(seconds: 12)),
      );
    });
  }

  Future<void> _attempt(Future<String?> Function() open) async {
    setState(() => _busy = true);
    try {
      final notice = await open();
      if (!mounted) return;
      setState(() {
        _failure = null;
        _busy = false;
      });
      widget.onReady?.call();
      _announce(notice);
    } on BootFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _failure = failure.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure == null) return widget.child;
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final reinstall = widget.reinstall;
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Haqor could not open its databases.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(
                failure,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _attempt(widget.start),
                child: const Text('Try again'),
              ),
              if (reinstall != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _attempt(reinstall),
                  child: const Text('Reinstall the databases'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
