import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'bindings/bindings.dart';
import 'db_version.dart';

const _dbFiles = ['bible.db', 'sedra.db', 'hebrew.db', 'lexicon.db'];

/// Copy the SQLite databases from the asset bundle into app-local storage,
/// where Rust opens them file-backed.
Future<void> initializeDatabases() async {
  final support = await getApplicationSupportDirectory();
  final dbDir = Directory('${support.path}${Platform.pathSeparator}db');
  final marker = File('${dbDir.path}${Platform.pathSeparator}.version');

  final bundled = await bundledDbVersion();
  final installed = await marker.exists() ? await marker.readAsString() : null;
  if (installed != bundled) {
    await dbDir.create(recursive: true);
    for (final name in _dbFiles) {
      final data = await rootBundle.load('assets/db/$name');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await File(
        '${dbDir.path}${Platform.pathSeparator}$name',
      ).writeAsBytes(bytes, flush: true);
    }
    await marker.writeAsString(bundled, flush: true);
  }
  SetDataDir(path: dbDir.path).sendSignalToRust(Uint8List(0));
}
