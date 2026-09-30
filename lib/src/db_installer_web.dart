import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/bindings.dart';
import 'boot_failure.dart';
import 'boot_status.dart';
import 'db_asset_web.dart';

/// One curated runtime database; the generation databases are not shipped
/// (haqor-core doc/adr/0006-single-runtime-database.md).
const _dbFiles = ['haqor.db'];
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

/// Load the immutable SQLite assets into the WebAssembly runtime. The Rust
/// core uses SQLite's in-memory VFS on web and returns progress snapshots that
/// are kept in the browser's persistent storage.
Future<String?> initializeDatabases({bool reinstall = false}) async {
  final prefs = await SharedPreferences.getInstance();
  // A retry comes back through here; one listener is enough.
  _persistence ??= ProgressSnapshot.rustSignalStream.listen((pack) {
    unawaited(prefs.setString(_progressKey, base64Encode(pack.binary)));
  });

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
  final persisted = prefs.getString(_progressKey);
  var unreadable = false;
  try {
    _append(bundle, persisted == null ? Uint8List(0) : base64Decode(persisted));
  } on FormatException {
    unreadable = true;
    _append(bundle, Uint8List(0));
  }
  final notice = await openDatabases('web', bundle.takeBytes());
  // Either the stored text was not base64 or Rust could not restore it: keep a
  // copy, then start from fresh progress.
  if (persisted != null && (unreadable || notice != null)) {
    await prefs.setString(_progressBackupKey, persisted);
    await prefs.remove(_progressKey);
    return 'Your saved progress could not be read, so Haqor started with fresh '
        'progress. A copy of the old progress was kept in this browser.';
  }
  return notice;
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
