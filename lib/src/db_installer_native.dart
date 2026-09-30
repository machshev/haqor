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

/// A progress database that will not open can be set aside and replaced.
const canResetProgress = true;

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
  await installDatabases(
    dbDir,
    reinstall: reinstall,
    bundled: await bundledDbVersion(),
    loadAsset: (name) async {
      final data = await rootBundle.load('assets/db/$name');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    },
  );
  return dbDir.path;
}

/// What `.version` records: the bundled version, then a `name=size` line per
/// database as written, so a missing or truncated file is noticed without
/// reading the asset. A marker from before sizes were recorded has only the
/// version line.
String _marker(String bundled, Map<String, int> sizes) =>
    [bundled, for (final e in sizes.entries) '${e.key}=${e.value}'].join('\n');

/// Whether the files in [dbDir] are the ones [marker] describes.
bool _installedIntact(Directory dbDir, String? marker, String bundled) {
  if (marker == null) return false;
  final lines = marker.split('\n');
  if (lines.first != bundled) return false;
  final sizes = <String, int?>{
    for (final line in lines.skip(1))
      if (line.contains('='))
        line.split('=').first: int.tryParse(line.split('=').last),
  };
  for (final name in _dbFiles) {
    final file = File('${dbDir.path}${Platform.pathSeparator}$name');
    if (!file.existsSync()) return false;
    final length = file.lengthSync();
    if (length == 0 || (sizes.containsKey(name) && length != sizes[name])) {
      return false;
    }
  }
  return true;
}

Future<File> _rename(File from, String to) => from.rename(to);

/// Install the databases into [dbDir] unless they are already current and
/// intact.
///
/// Each database is written to a temporary file and renamed over the old one,
/// so a crash never leaves a half-written `haqor.db`, and another running
/// instance that has the old file open keeps reading it. On Windows an open
/// file cannot be replaced: the rename fails, and unless [reinstall] was asked
/// for, the current copy is kept and the update waits for the next launch
/// instead of failing the boot over a file another instance is using.
///
/// [rename] is the seam that lets a test stand in for that failure.
Future<void> installDatabases(
  Directory dbDir, {
  required bool reinstall,
  required String bundled,
  required Future<Uint8List> Function(String name) loadAsset,
  Future<File> Function(File from, String to) rename = _rename,
}) async {
  final marker = File('${dbDir.path}${Platform.pathSeparator}.version');
  final installed = await marker.exists() ? await marker.readAsString() : null;
  if (reinstall || !_installedIntact(dbDir, installed, bundled)) {
    await dbDir.create(recursive: true);
    final sizes = <String, int>{};
    var replaced = true;
    for (final name in _dbFiles) {
      final target = File('${dbDir.path}${Platform.pathSeparator}$name');
      final bytes = await loadAsset(name);
      final temp = File('${target.path}.installing');
      await temp.writeAsBytes(bytes, flush: true);
      try {
        await rename(temp, target.path);
        sizes[name] = bytes.length;
      } on FileSystemException {
        try {
          await temp.delete();
        } on FileSystemException {
          // Overwritten by the next install.
        }
        if (reinstall || !await target.exists()) rethrow;
        replaced = false;
      }
    }
    if (replaced) {
      await marker.writeAsString(_marker(bundled, sizes), flush: true);
    }
  }
}

/// Move an unreadable `progress.db` (and any SQLite sidecar files, which belong
/// to it) aside as `progress.db.unreadable-<timestamp>`, and return the new
/// path of the database. The learner's data is kept, not deleted.
Future<String> setAsideProgress(Directory dbDir, DateTime now) async {
  final stamp = now.toUtc().toIso8601String().replaceAll(RegExp(r'[-:.]'), '');
  final base = '${dbDir.path}${Platform.pathSeparator}progress.db';
  final backup = '$base.unreadable-$stamp';
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('$base$suffix');
    if (await file.exists()) await file.rename('$backup$suffix');
  }
  return backup;
}

/// Set the progress database aside and open again with fresh progress. Returns
/// a notice saying where the old file went.
Future<String?> startWithFreshProgress() async {
  final support = await getApplicationSupportDirectory();
  final dbDir = Directory('${support.path}${Platform.pathSeparator}db');
  final backup = await setAsideProgress(dbDir, DateTime.now());
  final notice = await initializeDatabases();
  return notice ??
      'Started with fresh progress. The old progress file was kept as $backup';
}
