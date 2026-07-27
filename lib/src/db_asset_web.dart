/// Fetching the database asset with something to show for the wait.
///
/// `rootBundle.load` returns nothing until all 38 MB have arrived, which is most
/// of a first visit's blank screen. Streaming the same URL through `fetch`
/// reports bytes as they land, so the boot screen can show real progress.
///
/// The URL is the one Flutter itself would request — its asset directory plus
/// the asset key — and the service worker caches it under exactly that key, so
/// this is the same request either way, cached and offline-capable the same. If
/// anything about it fails, [loadDatabaseAsset] falls back to `rootBundle`,
/// which reports nothing but makes no assumptions about URLs at all.
library;

import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@JS('fetch')
external JSPromise<_Response> _fetch(String url);

extension type _Response._(JSObject _) implements JSObject {
  external bool get ok;
  external _Headers get headers;
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _Headers._(JSObject _) implements JSObject {
  @JS('get')
  external String? header(String name);
}

extension type _ReadableStream._(JSObject _) implements JSObject {
  external _Reader getReader();
}

extension type _Reader._(JSObject _) implements JSObject {
  external JSPromise<_Chunk> read();
}

extension type _Chunk._(JSObject _) implements JSObject {
  external bool get done;
  external JSUint8Array? get value;
}

/// Load `assets/db/<name>`, reporting progress to [onProgress] as a 0..1
/// fraction, or as null while the total size is unknown.
Future<Uint8List> loadDatabaseAsset(
  String name, {
  required void Function(double? fraction, int bytes) onProgress,
}) async {
  final key = 'assets/db/$name';
  try {
    return await _streamAsset('assets/$key', onProgress);
  } catch (error) {
    // Not fatal: the bundle path produces the same bytes, only without
    // progress. Worth a line in the console, because losing the progress
    // silently is how it would stay lost.
    debugPrint('streaming $key failed ($error); falling back to the bundle');
    final data = await rootBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

Future<Uint8List> _streamAsset(
  String url,
  void Function(double? fraction, int bytes) onProgress,
) async {
  final response = await _fetch(url).toDart;
  if (!response.ok) {
    throw Exception('$url could not be fetched');
  }
  final declared = int.tryParse(
    response.headers.header('content-length') ?? '',
  );
  // GitHub Pages serves the database gzipped, and `content-length` is then the
  // compressed size — smaller than what arrives. So the total is a hint, and
  // the fraction is clamped rather than trusted.
  final total = declared != null && declared > 0 ? declared : null;

  final stream = response.body;
  if (stream == null) {
    // No streaming body (an older browser, or a synthetic response): take the
    // whole thing and report it as a single step.
    final buffer = await response.arrayBuffer().toDart;
    final bytes = buffer.toDart.asUint8List();
    onProgress(1, bytes.length);
    return bytes;
  }

  final reader = stream.getReader();
  final chunks = <Uint8List>[];
  var received = 0;
  while (true) {
    final chunk = await reader.read().toDart;
    if (chunk.done) break;
    final value = chunk.value;
    if (value == null) continue;
    final bytes = value.toDart;
    chunks.add(bytes);
    received += bytes.length;
    onProgress(
      total == null ? null : (received / total).clamp(0.0, 1.0).toDouble(),
      received,
    );
  }

  final result = Uint8List(received);
  var offset = 0;
  for (final chunk in chunks) {
    result.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return result;
}
