import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import 'bindings/bindings.dart';
import 'boot_failure.dart';
import 'boot_status.dart';
import 'db_asset_web.dart';
import 'progress_load.dart';
import 'progress_store_web.dart';
import 'snapshot_writer.dart';

/// One curated runtime database; the generation databases are not shipped
/// (haqor-core doc/adr/0006-single-runtime-database.md).
const _dbFiles = ['haqor.db'];

/// Progress is stored as bytes in IndexedDB under this key. It is also the
/// localStorage key the old base64 copy was kept under.
const _progressKey = 'web_progress_sqlite_v1';

/// Where a saved progress snapshot Rust could not restore is kept, so it is not
/// lost when the app opens with fresh progress.
const _progressBackupKey = 'web_progress_sqlite_v1_unreadable';

/// The databases are built from the network copy on every load, so there is
/// nothing installed to replace; a retry fetches them again.
const canReinstallDatabases = false;

/// Web progress is reset by [initializeDatabases] itself, with no button.
const canResetProgress = false;

Future<String?> startWithFreshProgress() async => null;

StreamSubscription<void>? _persistence;
ProgressStore? _store;
SnapshotWriter? _writer;

void _saveFailed(Object error) {
  debugPrint('could not save progress: $error');
  appMessengerKey.currentState?.showSnackBar(
    const SnackBar(
      content: Text(
        'Haqor could not save your progress in this browser (its storage may '
        'be full or blocked). Progress since the last save will be lost if '
        'you close the page.',
      ),
      duration: Duration(seconds: 12),
    ),
  );
}

/// Write the pending snapshot now. The tab can go at any moment after it is
/// hidden, and on a phone that is the last chance there is.
void _flushOnLeaving() {
  void flush(web.Event _) => unawaited(_writer?.flush());
  web.window.addEventListener('pagehide', flush.toJS);
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event event) {
      if (web.document.visibilityState == 'hidden') flush(event);
    }).toJS,
  );
}

/// Load the immutable SQLite assets into the WebAssembly runtime. The Rust
/// core uses SQLite's in-memory VFS on web and returns progress snapshots that
/// are kept in the browser's persistent storage.
Future<String?> initializeDatabases({bool reinstall = false}) async {
  final prefs = await SharedPreferences.getInstance();
  String? storeNotice;
  try {
    _store ??= await ProgressStore.open();
  } catch (error) {
    debugPrint('progress storage unavailable: $error');
    storeNotice =
        'This browser would not open its storage, so your progress cannot be '
        'saved.';
  }
  final store = _store;

  final bundle = BytesBuilder(copy: false);
  for (final name in _dbFiles) {
    final bytes = await loadDatabaseAsset(
      name,
      onProgress: (fraction, received) => reportBootStatus(
        'Loading the Hebrew Bible…',
        progress: fraction,
        detail: '${(received / (1024 * 1024)).toStringAsFixed(1)} MB',
      ),
    );
    _append(bundle, bytes);
  }
  // The engine deserializes what it is handed below, which takes a few seconds
  // and reports nothing back while it does.
  reportBootStatus('Preparing the text…');
  // Progress used to be one base64 string in localStorage; it is moved across
  // once it has opened.
  var persisted = store == null
      ? null
      : await readStoredProgress(() => store.read(_progressKey));
  // Saving starts only once the stored snapshot has been read, so that nothing
  // can be written over one that could not be. A retry comes back through here;
  // one listener is enough.
  if (store != null && _persistence == null) {
    final writer = _writer = SnapshotWriter(
      write: (snapshot) => store.write(_progressKey, snapshot),
      onFailure: _saveFailed,
    );
    _persistence = ProgressSnapshot.rustSignalStream.listen(
      (pack) => writer.schedule(pack.binary),
    );
    _flushOnLeaving();
  }
  final legacy = persisted == null ? prefs.getString(_progressKey) : null;
  var unreadable = false;
  if (legacy != null) {
    try {
      persisted = base64Decode(legacy);
    } on FormatException {
      unreadable = true;
    }
  }
  _append(bundle, persisted ?? Uint8List(0));
  final notice = await openDatabases('web', bundle.takeBytes());
  // Either the stored text was not base64 or Rust could not restore it: keep a
  // copy, then start from fresh progress.
  final hadProgress = persisted != null || legacy != null;
  if (hadProgress && (unreadable || notice != null)) {
    final keep = persisted ?? utf8.encode(legacy!);
    try {
      await store?.write(_progressBackupKey, Uint8List.fromList(keep));
      await store?.delete(_progressKey);
      await prefs.remove(_progressKey);
    } catch (error) {
      _saveFailed(error);
    }
    return 'Your saved progress could not be read, so Haqor started with fresh '
        'progress. A copy of the old progress was kept in this browser.';
  }
  if (legacy != null && store != null) {
    try {
      await store.write(_progressKey, persisted!);
      await prefs.remove(_progressKey);
    } catch (error) {
      // It stays in localStorage, and the next run tries again.
      _saveFailed(error);
    }
  }
  return notice ?? storeNotice;
}

void _append(BytesBuilder bundle, Uint8List bytes) {
  // dart2js does not implement ByteData's 64-bit accessors. The Rust framing
  // protocol uses a little-endian u64; these bundled assets are well below
  // 4 GiB, so writing its low and high u32 words is equivalent.
  final length = ByteData(8)
    ..setUint32(0, bytes.length, Endian.little)
    ..setUint32(4, 0, Endian.little);
  bundle.add(length.buffer.asUint8List());
  bundle.add(bytes);
}
