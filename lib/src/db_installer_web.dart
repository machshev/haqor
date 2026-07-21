import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/bindings.dart';

const _dbFiles = ['bible.db', 'sedra.db', 'hebrew.db', 'lexicon.db'];
const _progressKey = 'web_progress_sqlite_v1';

/// Load the immutable SQLite assets into the WebAssembly runtime. The Rust
/// core uses SQLite's in-memory VFS on web and returns progress snapshots that
/// are kept in the browser's persistent storage.
Future<void> initializeDatabases() async {
  final prefs = await SharedPreferences.getInstance();
  ProgressSnapshot.rustSignalStream.listen((pack) {
    unawaited(prefs.setString(_progressKey, base64Encode(pack.binary)));
  });

  final bundle = BytesBuilder(copy: false);
  for (final name in _dbFiles) {
    final data = await rootBundle.load('assets/db/$name');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    _append(bundle, bytes);
  }
  final persisted = prefs.getString(_progressKey);
  try {
    _append(bundle, persisted == null ? Uint8List(0) : base64Decode(persisted));
  } on FormatException {
    await prefs.remove(_progressKey);
    _append(bundle, Uint8List(0));
  }
  SetDataDir(path: 'web').sendSignalToRust(bundle.takeBytes());
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
