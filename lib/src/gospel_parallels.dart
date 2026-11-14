import 'dart:async';

import 'package:rinf/rinf.dart';

import 'bindings/bindings.dart';

/// The Bible's events told in more than one Gospel, for finding a passage's
/// parallel accounts from the reader: each event's passages, Matthew to
/// John and any other book telling it too.
class GospelParallels {
  GospelParallels(Iterable<BibleEventEntry> events)
    : events = [
        for (final e in events)
          if (_gospelsTelling(e) > 1) e,
      ];

  static final empty = GospelParallels(const []);

  /// The events at least two Gospels tell.
  final List<BibleEventEntry> events;

  /// Whether [book] (1-based) is a Gospel.
  static bool isGospel(int book) => book >= 40 && book <= 43;

  static int _gospelsTelling(BibleEventEntry e) => {
    for (final p in e.passages)
      if (isGospel(p.book)) p.book,
  }.length;

  /// The events with a passage of [book] (1-based) in [chapter], in the
  /// order that book tells them.
  List<BibleEventEntry> inChapter(int book, int chapter) =>
      _ordered(book, (p) => p.chapter <= chapter && chapter <= p.lastChapter);

  /// The events with a passage of [book] (1-based) holding [chapter]:[verse],
  /// in the order that book tells them.
  List<BibleEventEntry> atVerse(int book, int chapter, int verse) =>
      _ordered(book, (p) => _holds(p, chapter, verse));

  List<BibleEventEntry> _ordered(
    int book,
    bool Function(ThematicTarget) matches,
  ) {
    final found = <(ThematicTarget, BibleEventEntry)>[];
    for (final e in events) {
      for (final p in e.passages) {
        if (p.book == book && matches(p)) {
          found.add((p, e));
          break;
        }
      }
    }
    found.sort((a, b) {
      final c = a.$1.chapter.compareTo(b.$1.chapter);
      return c != 0 ? c : a.$1.verse.compareTo(b.$1.verse);
    });
    return [for (final (_, e) in found) e];
  }
}

bool _holds(ThematicTarget p, int chapter, int verse) {
  final at = (chapter, verse);
  return _compare((p.chapter, p.verse), at) <= 0 &&
      _compare(at, (p.lastChapter, p.lastVerse)) <= 0;
}

int _compare((int, int) a, (int, int) b) {
  final c = a.$1.compareTo(b.$1);
  return c != 0 ? c : a.$2.compareTo(b.$2);
}

/// The id of the next request for the Bible's events made here; far from
/// the timeline page's, so neither takes the other's answer.
int _nextRequestId = 1 << 30;

Future<GospelParallels>? _loading;

/// The Gospels' parallels, asked of Rust once and kept. [sendRequest]
/// stands in for the signal to Rust, for tests. With no answer it waits
/// on, holding no timer, and the reader offers no parallels; nor where the
/// signal cannot be sent.
Future<GospelParallels> loadGospelParallels({
  void Function(GetBibleEvents)? sendRequest,
}) => _loading ??= _load(sendRequest);

Future<GospelParallels> _load(void Function(GetBibleEvents)? sendRequest) {
  final id = _nextRequestId++;
  final answer = Completer<GospelParallels>();
  late final StreamSubscription<RustSignalPack<BibleEvents>> sub;
  sub = BibleEvents.rustSignalStream.listen((pack) {
    if (pack.message.requestId != id || answer.isCompleted) return;
    answer.complete(GospelParallels(pack.message.events));
    sub.cancel();
  });
  final request = GetBibleEvents(requestId: id);
  try {
    if (sendRequest != null) {
      sendRequest(request);
    } else {
      request.sendSignalToRust();
    }
  } catch (_) {
    // Without Rust to ask (as under `flutter test`), there are none.
    sub.cancel();
    return Future.value(GospelParallels.empty);
  }
  return answer.future;
}

/// Forgets the parallels loaded, so that a test asks again.
void resetGospelParallelsForTest() => _loading = null;
