import 'package:flutter/foundation.dart';
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
              translation: const [],
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

  test('Syriac script is its own mode, cached and requested apart', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(send: sent.add);
    addTearDown(cache.dispose);

    final hebrew = cache.textFor(
      book: 40,
      chapter: 1,
      verse: 1,
      englishOnly: false,
    );
    final syriac = cache.textFor(
      book: 40,
      chapter: 1,
      verse: 1,
      englishOnly: false,
      syriac: true,
    );
    // Glosses have no script, so the flag changes nothing for them.
    final gloss = cache.textFor(
      book: 40,
      chapter: 1,
      verse: 1,
      englishOnly: true,
      syriac: true,
    );
    expect(syriac, isNot(same(hebrew)));
    await Future<void>.delayed(Duration.zero);

    expect(sent, hasLength(3));
    expect(sent.map((r) => (r.englishOnly, r.syriac)).toSet(), {
      (false, false),
      (false, true),
      (true, false),
    });

    // A reply fills the row of the mode it was asked in, not its neighbours.
    _reply(sent.firstWhere((r) => r.syriac));
    await Future<void>.delayed(Duration.zero);
    expect(syriac.value?.text, 'verse 40:1:1');
    expect(hebrew.value, isNull);
    expect(gloss.value, isNull);
  });

  test('long lists are split into batches of the requested size', () async {
    final sent = <GetVerseTexts>[];
    final cache = VerseTextCache(batchSize: 10, send: sent.add);
    addTearDown(cache.dispose);

    for (var verse = 1; verse <= 25; verse++) {
      cache.textFor(book: 1, chapter: 1, verse: verse, englishOnly: false);
    }
    await Future<void>.delayed(Duration.zero);

    // One request per mode is out at a time, so the reader's own requests are
    // not stuck behind a queue of rows; each reply releases the next batch.
    expect(sent.map((r) => r.refs.length), [10]);
    _reply(sent.last);
    await Future<void>.delayed(Duration.zero);
    _reply(sent.last);
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

  group('robustness', () {
    // A row is a listener on the entry; these stand in for one.
    void noop() {}

    test('a lexicon correction refetches the rows on show', () async {
      final sent = <GetVerseTexts>[];
      final cache = VerseTextCache(send: sent.add);
      addTearDown(cache.dispose);

      final shown = cache.textFor(
        book: 1,
        chapter: 1,
        verse: 1,
        englishOnly: true,
      )..addListener(noop);
      final scrolledAway = cache.textFor(
        book: 1,
        chapter: 1,
        verse: 2,
        englishOnly: true,
      );
      await Future<void>.delayed(Duration.zero);
      _reply(sent.single);
      await Future<void>.delayed(Duration.zero);
      expect(shown.value?.text, 'verse 1:1:1');

      cache.invalidate();
      await Future<void>.delayed(Duration.zero);

      // The row on show is asked for again, and keeps its text meanwhile.
      expect(sent, hasLength(2));
      expect(sent.last.refs.map((r) => r.verse), [1]);
      expect(shown.value?.text, 'verse 1:1:1');
      // The one nobody is looking at is dropped, and refetched if it is needed.
      expect(scrolledAway.value, isNull);
      _reply(sent.last);
      await Future<void>.delayed(Duration.zero);
      cache.textFor(book: 1, chapter: 1, verse: 2, englishOnly: true);
      await Future<void>.delayed(Duration.zero);
      expect(sent.last.refs.map((r) => r.verse), [2]);
    });

    test('a reply to a request made before a correction is ignored', () async {
      final sent = <GetVerseTexts>[];
      final cache = VerseTextCache(send: sent.add);
      addTearDown(cache.dispose);

      final row = cache.textFor(
        book: 1,
        chapter: 1,
        verse: 1,
        englishOnly: true,
      )..addListener(noop);
      await Future<void>.delayed(Duration.zero);
      final before = sent.single;

      cache.invalidate();
      await Future<void>.delayed(Duration.zero);
      _reply(before);
      await Future<void>.delayed(Duration.zero);

      expect(row.value, isNull, reason: 'the old reply may hold the old gloss');
      _reply(sent.last);
      await Future<void>.delayed(Duration.zero);
      expect(row.value?.text, 'verse 1:1:1');
    });

    test('an unanswered request is asked again, then given up on', () async {
      final sent = <GetVerseTexts>[];
      final cache = VerseTextCache(
        timeout: const Duration(milliseconds: 20),
        maxAttempts: 2,
        send: sent.add,
      );
      addTearDown(cache.dispose);

      final row = cache.textFor(
        book: 1,
        chapter: 1,
        verse: 1,
        englishOnly: false,
      )..addListener(noop);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sent, hasLength(2), reason: 'the first timeout asks again');
      expect(row.value, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sent, hasLength(2), reason: 'two attempts is all it makes');
      expect(row.value?.text, isEmpty);
      expect(
        row.value,
        isNotNull,
        reason: 'settled, so the row stops spinning',
      );
    });

    test('a reply after the timeout is still used', () async {
      final sent = <GetVerseTexts>[];
      final cache = VerseTextCache(
        timeout: const Duration(milliseconds: 20),
        send: sent.add,
      );
      addTearDown(cache.dispose);

      final row = cache.textFor(
        book: 1,
        chapter: 1,
        verse: 1,
        englishOnly: false,
      )..addListener(noop);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sent, hasLength(2));

      _reply(sent.first);
      await Future<void>.delayed(Duration.zero);
      expect(row.value?.text, 'verse 1:1:1');
    });

    test('an unreadable verse is tried again once the wait is over', () async {
      var now = DateTime(2026);
      final sent = <GetVerseTexts>[];
      final cache = VerseTextCache(
        missingRetryAfter: const Duration(seconds: 30),
        now: () => now,
        send: sent.add,
      );
      addTearDown(cache.dispose);

      final row = cache.textFor(
        book: 1,
        chapter: 1,
        verse: 1,
        englishOnly: false,
      )..addListener(noop);
      await Future<void>.delayed(Duration.zero);
      _reply(sent.single, omit: {1});
      await Future<void>.delayed(Duration.zero);
      expect(row.value?.text, isEmpty);

      // Asked again at once (a rebuild), it does not go straight back out.
      cache.textFor(book: 1, chapter: 1, verse: 1, englishOnly: false);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));

      now = now.add(const Duration(seconds: 31));
      cache.textFor(book: 1, chapter: 1, verse: 1, englishOnly: false);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(2));
      // Its row shows nothing in the meantime, not a spinner.
      expect(row.value?.text, isEmpty);
      _reply(sent.last);
      await Future<void>.delayed(Duration.zero);
      expect(row.value?.text, 'verse 1:1:1');
    });

    test(
      'rows scrolled past while a request is out are not asked for',
      () async {
        final sent = <GetVerseTexts>[];
        final cache = VerseTextCache(batchSize: 2, send: sent.add);
        addTearDown(cache.dispose);

        final rows = [
          for (var verse = 1; verse <= 6; verse++)
            cache.textFor(book: 1, chapter: 1, verse: verse, englishOnly: false)
              ..addListener(noop),
        ];
        await Future<void>.delayed(Duration.zero);
        // One request per mode is out at a time, so the rest wait their turn.
        expect(sent, hasLength(1));
        expect(sent.single.refs.map((r) => r.verse), [1, 2]);

        // The reader scrolls on: verses 3 and 4 leave the screen.
        rows[2].removeListener(noop);
        rows[3].removeListener(noop);
        _reply(sent.single);
        await Future<void>.delayed(Duration.zero);

        expect(sent, hasLength(2));
        expect(sent.last.refs.map((r) => r.verse), [5, 6]);

        // And coming back to one of them asks for it after all.
        rows[2].addListener(noop);
        cache.textFor(book: 1, chapter: 1, verse: 3, englishOnly: false);
        _reply(sent.last);
        await Future<void>.delayed(Duration.zero);
        expect(sent.last.refs.map((r) => r.verse), [3]);
      },
    );

    test('a saved lexicon correction invalidates the cache itself', () async {
      final sent = <GetVerseTexts>[];
      final cache = VerseTextCache(send: sent.add);
      addTearDown(cache.dispose);

      cache
          .textFor(book: 1, chapter: 1, verse: 1, englishOnly: true)
          .addListener(noop);
      await Future<void>.delayed(Duration.zero);
      _reply(sent.single);
      await Future<void>.delayed(Duration.zero);

      Future<void> saved({required bool success}) async {
        assignRustSignal['LexiconEntryOverrideStatus']!(
          LexiconEntryOverrideStatus(
            surface: 'מלה',
            success: success,
            message: '',
          ).bincodeSerialize(),
          Uint8List(0),
        );
        await Future<void>.delayed(Duration.zero);
      }

      await saved(success: false);
      expect(sent, hasLength(1), reason: 'a failed save changes nothing');
      await saved(success: true);
      expect(sent, hasLength(2), reason: 'the gloss may have changed');
    });
  });
}
