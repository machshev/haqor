import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Bump whenever the bundled databases change (tool/sync-dbs.sh) so installed
/// copies on devices are replaced on the next app start.
const _dbVersion = 5;

const _dbFiles = [
  'bible.db',
  'sedra.db',
  'hebrew.db',
  'lexicon.db',
];

/// Copy the SQLite databases from the asset bundle into app-local storage,
/// where Rust opens them file-backed, and return the directory holding them.
/// A version marker makes this a no-op on every launch but the first (and the
/// first after a database update).
Future<String> installDatabases() async {
  final support = await getApplicationSupportDirectory();
  final dbDir = Directory('${support.path}${Platform.pathSeparator}db');
  final marker = File('${dbDir.path}${Platform.pathSeparator}.version');

  final installed =
      await marker.exists() ? await marker.readAsString() : null;
  if (installed != '$_dbVersion') {
    await dbDir.create(recursive: true);
    for (final name in _dbFiles) {
      final data = await rootBundle.load('assets/db/$name');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File('${dbDir.path}${Platform.pathSeparator}$name')
          .writeAsBytes(bytes, flush: true);
    }
    // Written last: a copy interrupted part-way is retried next launch.
    await marker.writeAsString('$_dbVersion', flush: true);
  }
  return dbDir.path;
}
