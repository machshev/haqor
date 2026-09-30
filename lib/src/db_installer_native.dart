import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'boot_failure.dart';
import 'db_version.dart';

/// One curated runtime database; the generation databases are not shipped
/// (haqor-core doc/adr/0006-single-runtime-database.md).
const _dbFiles = ['haqor.db'];

/// The databases are copies of the app's assets, so a damaged one can be
/// replaced. The learner's `progress.db` sits beside them and is never touched.
const canReinstallDatabases = true;

/// Copy the SQLite databases from the asset bundle into app-local storage,
/// where Rust opens them file-backed. Throws a [BootFailure] if they cannot be
/// installed or Rust cannot open them; with [reinstall] the installed copies
/// are replaced even when they look current.
Future<String?> initializeDatabases({bool reinstall = false}) async {
  final String path;
  try {
    path = await _install(reinstall);
  } on FileSystemException catch (error) {
    throw BootFailure('Could not install the databases: $error');
  }
  return openDatabases(path, Uint8List(0));
}

Future<String> _install(bool reinstall) async {
  final support = await getApplicationSupportDirectory();
  final dbDir = Directory('${support.path}${Platform.pathSeparator}db');
  final marker = File('${dbDir.path}${Platform.pathSeparator}.version');

  final bundled = await bundledDbVersion();
  final installed = await marker.exists() ? await marker.readAsString() : null;
  if (reinstall || installed != bundled) {
    await dbDir.create(recursive: true);
    if (await marker.exists()) await marker.delete();
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
  return dbDir.path;
}
