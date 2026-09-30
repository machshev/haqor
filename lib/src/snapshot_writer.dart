import 'dart:async';
import 'dart:typed_data';

/// Saves the newest of the progress snapshots Rust sends after every write.
///
/// A snapshot is the whole progress database, so writing each one would
/// serialise it again after every card. Snapshots are instead held, newest
/// wins, and written once per [delay]; [flush] writes at once, for when the
/// page is about to go away.
class SnapshotWriter {
  SnapshotWriter({
    required this.write,
    required this.onFailure,
    this.delay = const Duration(seconds: 3),
  });

  final Future<void> Function(Uint8List snapshot) write;

  /// Called when a write fails, once per run of failures: a full disk would
  /// otherwise complain after every card.
  final void Function(Object error) onFailure;
  final Duration delay;

  Uint8List? _pending;
  Timer? _timer;
  Future<void> _writing = Future.value();
  bool _failing = false;

  void schedule(Uint8List snapshot) {
    _pending = snapshot;
    _timer ??= Timer(delay, flush);
  }

  /// Write what is held now. Completes once that write has finished.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _writing = _writing.then((_) => _drain());
  }

  Future<void> _drain() async {
    final snapshot = _pending;
    if (snapshot == null) return;
    _pending = null;
    try {
      await write(snapshot);
      _failing = false;
    } catch (error) {
      // Keep it for the next attempt unless something newer has arrived.
      _pending ??= snapshot;
      if (!_failing) {
        _failing = true;
        onFailure(error);
      }
    }
  }
}
