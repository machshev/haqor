import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';

/// The text of one verse, in whichever mode it was asked for.
@immutable
class VerseTextData {
  const VerseTextData({
    required this.text,
    this.glossWords = const [],
    this.sourceWords = const [],
  });

  /// A verse the core could not read. Rows render nothing for it rather than
  /// spinning for a reply that will never come.
  static const missing = VerseTextData(text: '');

  final String text;

  /// English-only mode: the gloss of each word of the verse, in order. Empty in
  /// Hebrew mode, where [text] carries its own words.
  final List<String> glossWords;

  /// The source-language word each entry of [glossWords] renders, so a
  /// gloss-only verse can still be highlighted on the Hebrew behind it.
  final List<String> sourceWords;
}

/// A batching, caching source of verse text for lists that show one verse per
/// row.
///
/// A row asks for its verse and rebuilds on the returned listenable. Every
/// request made before the next microtask is coalesced into a single
/// `GetVerseTexts` round-trip, and the whole cache shares one subscription to
/// the reply stream. Fetching per row instead cost a signal *and* a
/// broadcast-stream listener each, so every reply was handed to every row still
/// waiting — quadratic on a list that can run to thousands of verses.
class VerseTextCache {
  VerseTextCache({this.batchSize = 64, void Function(GetVerseTexts)? send})
    : _send = send ?? ((request) => request.sendSignalToRust());

  /// How many verses one round-trip asks for. Large enough that a fast scroll
  /// is a handful of requests, small enough that the first screen of rows does
  /// not wait on a page of text it cannot show.
  final int batchSize;

  /// How a request reaches Rust. Injectable so a test can observe how many
  /// round-trips a page of rows actually costs.
  final void Function(GetVerseTexts) _send;

  final Map<String, ValueNotifier<VerseTextData?>> _entries = {};
  final List<String> _queue = [];
  final Map<int, List<String>> _inflight = {};
  StreamSubscription<RustSignalPack<VerseTexts>>? _sub;
  bool _flushScheduled = false;
  bool _disposed = false;

  /// Request ids are handed out app-wide, not per cache: the reply stream is a
  /// broadcast, so two caches numbering their own requests from one would each
  /// claim the other's replies and fill their rows with the wrong verses.
  static int _nextRequestId = 1;

  static String _key(int book, int chapter, int verse, bool englishOnly) =>
      '$book:$chapter:$verse:${englishOnly ? 'e' : 'h'}';

  /// The text of one verse, fetched on first ask. Null until it arrives.
  ValueListenable<VerseTextData?> textFor({
    required int book,
    required int chapter,
    required int verse,
    required bool englishOnly,
  }) {
    final key = _key(book, chapter, verse, englishOnly);
    final existing = _entries[key];
    if (existing != null) return existing;
    final notifier = ValueNotifier<VerseTextData?>(null);
    _entries[key] = notifier;
    _queue.add(key);
    _scheduleFlush();
    return notifier;
  }

  void _scheduleFlush() {
    if (_flushScheduled || _disposed) return;
    _flushScheduled = true;
    // A microtask, so all rows the current layout pass builds land in one
    // request rather than one request per row.
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    if (_disposed || _queue.isEmpty) return;
    _sub ??= VerseTexts.rustSignalStream.listen(_receive);
    // A request is single-mode and the key carries the mode, so group before
    // batching: a mode toggle mid-scroll splits into one request per mode.
    final byMode = <bool, List<String>>{};
    for (final key in _queue) {
      (byMode[key.endsWith(':e')] ??= []).add(key);
    }
    _queue.clear();
    for (final MapEntry(key: englishOnly, value: keys) in byMode.entries) {
      for (var i = 0; i < keys.length; i += batchSize) {
        _sendBatch(englishOnly, keys.skip(i).take(batchSize).toList());
      }
    }
  }

  void _sendBatch(bool englishOnly, List<String> keys) {
    final requestId = _nextRequestId++;
    _inflight[requestId] = keys;
    _send(
      GetVerseTexts(
        requestId: requestId,
        englishOnly: englishOnly,
        refs: [
          for (final key in keys)
            if (key.split(':') case [final book, final chapter, final verse, _])
              VerseRef(
                book: int.parse(book),
                chapter: int.parse(chapter),
                verse: int.parse(verse),
              ),
        ],
      ),
    );
  }

  void _receive(RustSignalPack<VerseTexts> pack) {
    final message = pack.message;
    final asked = _inflight.remove(message.requestId);
    // A reply to a request from a different cache instance — the stream is a
    // broadcast, so both see everything.
    if (asked == null) return;
    final filled = <String>{};
    for (final verse in message.verses) {
      final key = _key(
        verse.book,
        verse.chapter,
        verse.verse,
        message.englishOnly,
      );
      filled.add(key);
      _entries[key]?.value = VerseTextData(
        text: verse.text,
        glossWords: verse.glossWords,
        sourceWords: verse.sourceWords,
      );
    }
    // Anything asked for and not returned is unreadable; settle it so the row
    // stops waiting.
    for (final key in asked) {
      if (filled.contains(key)) continue;
      final entry = _entries[key];
      if (entry != null && entry.value == null) {
        entry.value = VerseTextData.missing;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    for (final notifier in _entries.values) {
      notifier.dispose();
    }
    _entries.clear();
    _queue.clear();
    _inflight.clear();
  }
}
