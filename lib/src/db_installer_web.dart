import 'package:flutter/services.dart';
import 'package:sqlite3/wasm.dart';

import 'bindings/bindings.dart';

const _dbFiles = ['bible.db', 'sedra.db', 'hebrew.db', 'lexicon.db'];
const _bundleVersion = '0.7.2';
const _fileSystemName = 'haqor-offline-v1';

/// Browser-local Bible data backed by SQLite WASM and IndexedDB.
///
/// The source databases are copied from the installable bundle only when the
/// bundled schema/data version changes. Every subsequent launch reads the
/// persistent IndexedDB copy, so it works without a network connection.
class WebBibleDatabase {
  WebBibleDatabase._(this._bible);

  final CommonDatabase _bible;

  void sendChapter(GetChapter request) {
    final rows = _bible.select(
      'SELECT verse, words FROM bible WHERE book = ? AND chapter = ? '
      'ORDER BY verse',
      [request.book, request.chapter],
    );
    final response = ChapterText(
      book: request.book,
      chapter: request.chapter,
      syriac: request.syriac,
      includeGlosses: request.includeGlosses,
      includeNames: request.includeNames,
      verses: [
        for (final row in rows)
          VerseEntry(
            verse: row['verse'] as int,
            text: row['words'] as String,
            // Reader text is available offline now. Lexicon-derived metadata
            // is populated by the web lexicon backend as it is ported.
            glosses: const [],
            names: const [],
          ),
      ],
    );
    assignRustSignal['ChapterText']!(
      response.bincodeSerialize(),
      Uint8List(0),
    );
  }
}

Future<WebBibleDatabase> initializeWebDatabases() async {
  final sqlite = await WasmSqlite3.loadFromUrlString('sqlite3.wasm');
  final files = await IndexedDbFileSystem.open(dbName: _fileSystemName);
  sqlite.registerVirtualFileSystem(files, makeDefault: true);

  if (_readFile(files, '/.bundle-version') != _bundleVersion) {
    for (final name in _dbFiles) {
      final data = await rootBundle.load('assets/db/$name');
      _writeFile(
        files,
        '/$name',
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }
    _writeFile(files, '/.bundle-version', Uint8List.fromList(_bundleVersion.codeUnits));
    await files.flush();
  }

  return WebBibleDatabase._(sqlite.open('/bible.db', mode: OpenMode.readOnly));
}

String? _readFile(IndexedDbFileSystem files, String path) {
  if (files.xAccess(path, 0) == 0) return null;
  final file = files.xOpen(Sqlite3Filename(path), 0).file;
  try {
    final bytes = Uint8List(file.xFileSize());
    file.xRead(bytes, 0);
    return String.fromCharCodes(bytes);
  } finally {
    file.xClose();
  }
}

void _writeFile(IndexedDbFileSystem files, String path, Uint8List bytes) {
  final file = files
      .xOpen(Sqlite3Filename(path), SqlFlag.SQLITE_OPEN_CREATE)
      .file;
  try {
    file.xTruncate(0);
    file.xWrite(bytes, 0);
    file.xTruncate(bytes.length);
  } finally {
    file.xClose();
  }
}
