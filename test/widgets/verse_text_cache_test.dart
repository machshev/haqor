import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:haqor/src/bindings/bindings.dart';
import 'package:haqor/src/widgets/verse_text_cache.dart';

/// Deliver a batch reply through the same entry point rinf uses for real
/// signals, so the cache's own subscription is what routes it.
void _reply(GetVerseTexts request, {Set<int> omit = const {}}) {
  assignRustSignal['VerseTexts']!(
    VerseTexts(
      requestId: request.requestId,
      englishOnly: request.englishOnly,
      verses: [
        for (final ref in request.refs)
          if (!omit.contains(ref.verse))
            VerseTextEntry(
              book: ref.book,
              chapter: ref.chapter,
              verse: ref.verse,
              text: 'verse ${ref.book}:${ref.chapter}:${ref.verse}',
              glossWords: const [],
              sourceWords: const [],
            ),
      ],
    ).bincodeSerialize(),
    Uint8List(0),
  );
}

void main() {
  test('a page of rows costs one round-trip, not one per row', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(send: sent.add);
    addTearDown(cache.dispose);

    final rows = [
      for (var verse = 1; verse <= 30; verse++)
        cache.textFor(book: 1, chapter: 1, verse: verse, englishOnly: false),
    ];
    // Requests are coalesced on the microtask that follows the layout pass, so
    // nothing has gone out yet.
    expect(sent, isEmpty);
    await Future<void>.delayed(Duration.zero);

    expect(sent, hasLength(1));
    expect(sent.single.refs, hasLength(30));
    expect(rows.every((row) => row.value == null), isTrue);

    _reply(sent.single);
    await Future<void>.delayed(Duration.zero);
    expect(rows.first.value?.text, 'verse 1:1:1');
    expect(rows.last.value?.text, 'verse 1:1:30');
  });

  test('asking again for a verse reuses the fetched text', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(send: sent.add);
    addTearDown(cache.dispose);

    final first = cache.textFor(
      book: 1,
      chapter: 1,
      verse: 1,
      englishOnly: false,
    );
    await Future<void>.delayed(Duration.zero);
    _reply(sent.single);
    await Future<void>.delayed(Duration.zero);

    // A row scrolled off and back on must not re-fetch.
    final again = cache.textFor(
      book: 1,
      chapter: 1,
      verse: 1,
      englishOnly: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(sent, hasLength(1));
    expect(again, same(first));
    expect(again.value?.text, 'verse 1:1:1');
  });

  test('the two verse modes are cached apart', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(send: sent.add);
    addTearDown(cache.dispose);

    cache.textFor(book: 1, chapter: 1, verse: 1, englishOnly: false);
    cache.textFor(book: 1, chapter: 1, verse: 1, englishOnly: true);
    await Future<void>.delayed(Duration.zero);

    // One request per mode, since a request carries a single mode.
    expect(sent, hasLength(2));
    expect(sent.map((r) => r.englishOnly).toSet(), {true, false});
  });

  test('long lists are split into batches of the requested size', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(batchSize: 10, send: sent.add);
    addTearDown(cache.dispose);

    for (var verse = 1; verse <= 25; verse++) {
      cache.textFor(book: 1, chapter: 1, verse: verse, englishOnly: false);
    }
    await Future<void>.delayed(Duration.zero);

    expect(sent.map((r) => r.refs.length), [10, 10, 5]);
    // Request ids are distinct, so replies cannot be mistaken for each other.
    expect(sent.map((r) => r.requestId).toSet(), hasLength(3));
  });

  test('a verse the core cannot read stops waiting', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(send: sent.add);
    addTearDown(cache.dispose);

    final ok = cache.textFor(book: 1, chapter: 1, verse: 1, englishOnly: false);
    final missing = cache.textFor(
      book: 1,
      chapter: 1,
      verse: 2,
      englishOnly: false,
    );
    await Future<void>.delayed(Duration.zero);
    _reply(sent.single, omit: {2});
    await Future<void>.delayed(Duration.zero);

    expect(ok.value?.text, 'verse 1:1:1');
    // Settled, not still null: a row rendering a placeholder until a reply that
    // is never coming would spin forever.
    expect(missing.value, isNotNull);
    expect(missing.value?.text, isEmpty);
  });

  test('two caches do not claim each other\'s replies', () async {
    final sentA = <GetVerseTexts>[];
    final sentB = <GetVerseTexts>[];
    final a = VerseTextCache(send: sentA.add);
    final b = VerseTextCache(send: sentB.add);
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    final fromA = a.textFor(book: 1, chapter: 1, verse: 1, englishOnly: false);
    final fromB = b.textFor(book: 2, chapter: 2, verse: 2, englishOnly: false);
    await Future<void>.delayed(Duration.zero);

    // The reply stream is a broadcast, so both caches see both replies; the
    // request id is what keeps each one's rows its own.
    expect(sentA.single.requestId, isNot(sentB.single.requestId));
    _reply(sentB.single);
    await Future<void>.delayed(Duration.zero);

    expect(fromB.value?.text, 'verse 2:2:2');
    expect(fromA.value, isNull, reason: 'A must still be waiting on its own');
  });
}
