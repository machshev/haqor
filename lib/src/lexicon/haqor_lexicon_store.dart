import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../bindings/bindings.dart';
import '../request_failure.dart' show requestTimeout;

/// A verse an entry cites, with its text, as the hub sends it.
@immutable
class LexiconVerse {
  const LexiconVerse({
    required this.reference,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.original,
    required this.english,
  });

  /// As the entry writes it: `Gen.2.7`.
  final String reference;

  /// Haqor's book number (1-based), chapter and verse.
  final int book;
  final int chapter;
  final int verse;

  /// The Hebrew, or in the New Testament the Greek.
  final String original;
  final String english;
}

/// One Haqor lexicon entry under review: its JSON as an ordered map, which
/// the editor changes in place and saves in the same order, and the verses it
/// cites.
class LexiconEntryDraft {
  LexiconEntryDraft({
    required this.id,
    required this.data,
    required this.verses,
  });

  factory LexiconEntryDraft.fromSignal(HaqorLexiconEntryText entry) {
    final decoded = jsonDecode(entry.json);
    return LexiconEntryDraft(
      id: entry.id,
      data: decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
      verses: {
        for (final v in entry.verses)
          v.reference: LexiconVerse(
            reference: v.reference,
            book: v.book,
            chapter: v.chapter,
            verse: v.verse,
            original: v.original,
            english: v.english,
          ),
      },
    );
  }

  final String id;

  /// The entry, in the schema's shape (haqor-core `data/lexicon/README.md`).
  final Map<String, dynamic> data;

  /// The verses the entry cites, by reference.
  final Map<String, LexiconVerse> verses;

  /// Whether it has unsaved changes.
  bool dirty = false;

  /// The JSON the editor saves: two-space indentation, keys in the order the
  /// file has them, as `jq .` writes it.
  String encode() => const JsonEncoder.withIndent('  ').convert(data);
}

/// What the review page was sent.
@immutable
class LexiconReview {
  const LexiconReview({
    required this.entries,
    required this.editable,
    required this.dir,
    required this.error,
  });

  final List<LexiconEntryDraft> entries;
  final bool editable;
  final String dir;
  final String error;
}

/// Asks the hub for the lexicon under review and saves entries back.
class HaqorLexiconStore {
  HaqorLexiconStore({
    void Function(GetHaqorLexicon)? send,
    void Function(SaveHaqorLexiconEntry)? save,
  }) : _send = send ?? ((r) => r.sendSignalToRust()),
       _save = save ?? ((r) => r.sendSignalToRust());

  final void Function(GetHaqorLexicon) _send;
  final void Function(SaveHaqorLexiconEntry) _save;
  static int _nextRequestId = 1;

  /// The entries, fresh from the review directory.
  Future<LexiconReview> load() async {
    final requestId = _nextRequestId++;
    final reply = HaqorLexicon.rustSignalStream
        .map((pack) => pack.message)
        .firstWhere((m) => m.requestId == requestId)
        .timeout(requestTimeout);
    _send(GetHaqorLexicon(requestId: requestId));
    final message = await reply;
    return LexiconReview(
      entries: message.entries.map(LexiconEntryDraft.fromSignal).toList(),
      editable: message.editable,
      dir: message.dir,
      error: message.error,
    );
  }

  /// Save [entry]; the reply says whether the whole lexicon still checks
  /// clean with it, and if not, why.
  Future<HaqorLexiconSaveStatus> save(LexiconEntryDraft entry) async {
    final reply = HaqorLexiconSaveStatus.rustSignalStream
        .map((pack) => pack.message)
        .firstWhere((m) => m.id == entry.id)
        .timeout(requestTimeout);
    _save(SaveHaqorLexiconEntry(id: entry.id, json: entry.encode()));
    return reply;
  }
}
