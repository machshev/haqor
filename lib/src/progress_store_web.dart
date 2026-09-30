import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const _dbName = 'haqor';
const _storeName = 'kv';

/// Byte blobs kept in the browser's IndexedDB. localStorage holds about 5 MB
/// of text, which the progress database outgrows once base64 has inflated it;
/// IndexedDB takes binary values and a far larger quota.
class ProgressStore {
  ProgressStore._(this._db);

  final web.IDBDatabase _db;

  static Future<ProgressStore> open() {
    final done = Completer<ProgressStore>();
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_storeName);
    }).toJS;
    request.onsuccess = ((web.Event _) {
      done.complete(ProgressStore._(request.result as web.IDBDatabase));
    }).toJS;
    request.onerror = ((web.Event _) {
      done.completeError(_describe(request.error, 'could not open storage'));
    }).toJS;
    request.onblocked = ((web.Event _) {
      done.completeError('storage is blocked by another open copy of Haqor');
    }).toJS;
    return done.future;
  }

  Future<Uint8List?> read(String key) {
    final done = Completer<Uint8List?>();
    final request = _db
        .transaction(_storeName.toJS, 'readonly')
        .objectStore(_storeName)
        .get(key.toJS);
    request.onsuccess = ((web.Event _) {
      final value = request.result;
      done.complete(value == null ? null : (value as JSUint8Array).toDart);
    }).toJS;
    request.onerror = ((web.Event _) {
      done.completeError(_describe(request.error, 'could not read storage'));
    }).toJS;
    return done.future;
  }

  /// Completes once the browser has committed the write, and fails with the
  /// browser's reason (a full quota, say) when it has not.
  Future<void> write(String key, Uint8List value) {
    final done = Completer<void>();
    final transaction = _db.transaction(_storeName.toJS, 'readwrite');
    transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
    transaction.onabort = ((web.Event _) {
      done.completeError(_describe(transaction.error, 'write was aborted'));
    }).toJS;
    transaction.objectStore(_storeName).put(value.toJS, key.toJS);
    return done.future;
  }

  Future<void> delete(String key) {
    final done = Completer<void>();
    final transaction = _db.transaction(_storeName.toJS, 'readwrite');
    transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
    transaction.onabort = ((web.Event _) {
      done.completeError(_describe(transaction.error, 'delete was aborted'));
    }).toJS;
    transaction.objectStore(_storeName).delete(key.toJS);
    return done.future;
  }
}

String _describe(web.DOMException? error, String fallback) =>
    error == null ? fallback : '${error.name}: ${error.message}';
