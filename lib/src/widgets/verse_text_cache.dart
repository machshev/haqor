import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:rinf/rinf.dart';

import '../bindings/bindings.dart';
import '../request_failure.dart' show requestTimeout;

/// The text of one verse, in whichever mode it was asked for.
@immutable
class VerseTextData {
  const VerseTextData({
    required this.text,
    this.glossWords = const [],
    this.sourceWords = const [],
    this.translation = const [],
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

  /// English-only mode: the verse in the English translation, where it has
  /// one, each span naming the Hebrew words it renders. Empty in Hebrew mode
  /// and for a verse without one (the NT), which falls back to [glossWords].
  final List<TranslationSpanEntry> translation;
}

/// One cached verse. A subclass of the notifier only to know whether any row is
/// still listening, which [VerseTextCache] asks before it spends a round-trip
/// on a verse that has been scrolled away from.
class _Entry extends ValueNotifier<VerseTextData?> {
  _Entry() : super(null);

  /// Whether a row has ever listened. A verse nobody has listened to yet is
  /// one a row is about to; only a listener that has gone marks it abandoned.
  bool watched = false;

  bool get listened => hasListeners;

  bool get abandoned => watched && !hasListeners;

  @override
  void addListener(VoidCallback listener) {
    watched = true;
    super.addListener(listener);
  }
}

/// One request on its way to Rust.
class _Batch {
  _Batch(this.mode, this.keys, this.attempt);

  final String mode;
  final List<String> keys;

  /// How many times these verses have now been asked for, this one included.
  final int attempt;
  Timer? timer;

  /// The wait for the reply has run out and the verses have been asked for
  /// again. A reply that comes after all is still used, but it no longer holds
  /// up the next request.
  bool late = false;
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
///
/// Rust answers requests one at a time with no way to cancel one, so a list
/// scrolled quickly would queue every row it passed ahead of whatever the
/// reader asks for next. Each mode therefore has one request out at a time, and
/// a verse whose rows have all gone by the time its turn comes is not asked for.
/// A request that is not answered within [timeout] is asked again, and text
/// that can no longer be trusted is fetched anew: [invalidate] does it, and a
/// saved lexicon correction calls it.
class VerseTextCache {
  VerseTextCache({
    this.batchSize = 64,
    this.timeout = requestTimeout,
    this.maxAttempts = 3,
    this.missingRetryAfter = const Duration(seconds: 30),
    void Function(GetVerseTexts)? send,
    DateTime Function()? now,
  }) : _send = send ?? ((request) => request.sendSignalToRust()),
       _now = now ?? DateTime.now;

  /// How many verses one round-trip asks for. Large enough that a fast scroll
  /// is a handful of requests, small enough that the first screen of rows does
  /// not wait on a page of text it cannot show.
  final int batchSize;

  /// How long a request may go unanswered before its verses are asked for again.
  final Duration timeout;

  /// How many times a verse is asked for before the cache gives up for now and
  /// shows it as unreadable.
  final int maxAttempts;

  /// How long a verse the core could not read, or never answered, stays
  /// unreadable before a row asking for it again triggers another try.
  final Duration missingRetryAfter;

  /// How a request reaches Rust. Injectable so a test can observe how many
  /// round-trips a page of rows actually costs.
  final void Function(GetVerseTexts) _send;
  final DateTime Function() _now;

  final Map<String, _Entry> _entries = {};
  final List<String> _queue = [];
  final Map<int, _Batch> _inflight = {};

  /// Keys queued or in flight, so a row asking again does not ask twice.
  final Set<String> _pending = {};

  /// Keys whose text is on show but may be out of date, and is being fetched
  /// again. The old text stays until the new arrives, so a list does not blank.
  final Set<String> _refresh = {};

  /// When each unreadable verse was given up on.
  final Map<String, DateTime> _missingAt = {};

  /// How many requests each key has been through so far.
  final Map<String, int> _attempts = {};
  StreamSubscription<RustSignalPack<VerseTexts>>? _sub;
  StreamSubscription<RustSignalPack<LexiconEntryOverrideStatus>>?
  _correctionSub;
  bool _flushScheduled = false;
  bool _disposed = false;

  /// Request ids are handed out app-wide, not per cache: the reply stream is a
  /// broadcast, so two caches numbering their own requests from one would each
  /// claim the other's replies and fill their rows with the wrong verses.
  static int _nextRequestId = 1;

  /// The mode letter a key ends in: `e` for glosses, `s` for Syriac script
  /// and `h` for Hebrew. Glosses have no script, so `englishOnly` wins.
  static String _mode(bool englishOnly, bool syriac) =>
      englishOnly ? 'e' : (syriac ? 's' : 'h');

  static String _key(int book, int chapter, int verse, String mode) =>
      '$book:$chapter:$verse:$mode';

  /// Whether [key] still wants a reply: nothing is on show for it, it is being
  /// refreshed, or it was given up on long enough ago to try again.
  bool _wantsFetch(String key) {
    final entry = _entries[key];
    if (entry == null) return false;
    if (entry.value == null || _refresh.contains(key)) return true;
    final missingAt = _missingAt[key];
    return missingAt != null &&
        _now().difference(missingAt) >= missingRetryAfter;
  }

  /// The text of one verse, fetched on first ask. Null until it arrives.
  ValueListenable<VerseTextData?> textFor({
    required int book,
    required int chapter,
    required int verse,
    required bool englishOnly,
    bool syriac = false,
  }) {
    final key = _key(book, chapter, verse, _mode(englishOnly, syriac));
    final existing = _entries[key];
    if (existing != null) {
      // A verse dropped from the queue while its rows were away, or one given
      // up on, is asked for again now a row wants it.
      if (!_pending.contains(key) && _wantsFetch(key)) _enqueue(key);
      return existing;
    }
    _entries[key] = _Entry();
    _enqueue(key);
    return _entries[key]!;
  }

  void _enqueue(String key) {
    _pending.add(key);
    _queue.add(key);
    _scheduleFlush();
  }

  /// Forget every reply and request so far, because the text behind them has
  /// changed (a lexicon correction alters the glosses). Replies still on their
  /// way may carry the old text and are ignored. Rows on show keep what they
  /// have until the new text arrives; the rest are emptied and refetched if a
  /// row asks for them again.
  void invalidate() {
    if (_disposed) return;
    for (final batch in _inflight.values) {
      batch.timer?.cancel();
    }
    _inflight.clear();
    _queue.clear();
    _pending.clear();
    _refresh.clear();
    _missingAt.clear();
    _attempts.clear();
    for (final MapEntry(:key, value: entry) in _entries.entries) {
      if (entry.listened) {
        _refresh.add(key);
        _enqueue(key);
      } else {
        entry.value = null;
      }
    }
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
    // A saved correction changes the glosses of English-only text, from
    // whichever pane made it.
    _correctionSub ??= LexiconEntryOverrideStatus.rustSignalStream
        .where((pack) => pack.message.success)
        .listen((_) => invalidate());
    _dispatch();
  }

  /// Send what is queued, a batch per mode that has no request still out.
  void _dispatch() {
    if (_disposed) return;
    final busy = {
      for (final batch in _inflight.values)
        if (!batch.late) batch.mode,
    };
    // A request is single-mode and the key carries the mode, so group before
    // batching: a mode toggle mid-scroll splits into one request per mode.
    final batches = <String, List<String>>{};
    final waiting = <String>[];
    for (final key in _queue) {
      final entry = _entries[key];
      // Every row that wanted this verse has gone, or it was filled while it
      // waited (a late reply): nothing to ask for.
      if (entry == null || entry.abandoned || !_wantsFetch(key)) {
        _pending.remove(key);
        continue;
      }
      final mode = key.substring(key.length - 1);
      final batch = batches[mode];
      if (busy.contains(mode) || (batch != null && batch.length >= batchSize)) {
        waiting.add(key);
        continue;
      }
      (batches[mode] ??= []).add(key);
    }
    _queue
      ..clear()
      ..addAll(waiting);
    for (final MapEntry(key: mode, value: keys) in batches.entries) {
      _sendBatch(mode, keys);
    }
  }

  void _sendBatch(String mode, List<String> keys) {
    final requestId = _nextRequestId++;
    final attempt = keys.fold(
      1,
      (most, key) => math.max(most, _attempts[key] ?? 1),
    );
    final batch = _Batch(mode, keys, attempt);
    batch.timer = Timer(timeout, () => _onTimeout(requestId));
    _inflight[requestId] = batch;
    _send(
      GetVerseTexts(
        requestId: requestId,
        englishOnly: mode == 'e',
        syriac: mode == 's',
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

  void _onTimeout(int requestId) {
    final batch = _inflight[requestId];
    if (batch == null || _disposed) return;
    batch.late = true;
    final again = <String>[];
    for (final key in batch.keys) {
      if (!_wantsFetch(key)) continue;
      if (batch.attempt < maxAttempts) {
        _attempts[key] = batch.attempt + 1;
        again.add(key);
      } else {
        // Give up for now: show it as unreadable, and let a row that asks
        // again after [missingRetryAfter] try afresh.
        _attempts.remove(key);
        _settleMissing(key);
      }
    }
    _queue.insertAll(0, again);
    // Nothing of it left to wait for once every verse has been given up on.
    if (again.isEmpty) _inflight.remove(requestId);
    _dispatch();
  }

  void _settleMissing(String key) {
    _pending.remove(key);
    _refresh.remove(key);
    _missingAt[key] = _now();
    final entry = _entries[key];
    if (entry != null && entry.value == null) {
      entry.value = VerseTextData.missing;
    }
  }

  void _receive(RustSignalPack<VerseTexts> pack) {
    final message = pack.message;
    final asked = _inflight.remove(message.requestId);
    // A reply to a request from a different cache instance — the stream is a
    // broadcast, so both see everything.
    if (asked == null) return;
    asked.timer?.cancel();
    final filled = <String>{};
    for (final verse in message.verses) {
      final key = _key(verse.book, verse.chapter, verse.verse, asked.mode);
      filled.add(key);
      _pending.remove(key);
      _refresh.remove(key);
      _missingAt.remove(key);
      _attempts.remove(key);
      _entries[key]?.value = VerseTextData(
        text: verse.text,
        glossWords: verse.glossWords,
        sourceWords: verse.sourceWords,
        translation: verse.translation,
      );
    }
    // Anything asked for and not returned is unreadable; settle it so the row
    // stops waiting.
    for (final key in asked.keys) {
      if (!filled.contains(key)) _settleMissing(key);
    }
    // The next batch of the mode that just answered.
    _dispatch();
  }

  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _correctionSub?.cancel();
    for (final batch in _inflight.values) {
      batch.timer?.cancel();
    }
    for (final notifier in _entries.values) {
      notifier.dispose();
    }
    _entries.clear();
    _queue.clear();
    _inflight.clear();
    _pending.clear();
    _refresh.clear();
    _missingAt.clear();
    _attempts.clear();
  }
}
