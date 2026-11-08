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
    this.peshitta = '',
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

  /// In the New Testament, the Peshitta in Hebrew letters; empty in the Old.
  final String peshitta;
}

/// One Haqor lexicon entry under review: its JSON as an ordered map, which
/// the editor changes in place and saves in the same order, and the verses it
/// cites.
class LexiconEntryDraft {
  LexiconEntryDraft({
    required this.id,
    required this.data,
    required this.verses,
    this.support = const [],
    this.names = const [],
  });

  factory LexiconEntryDraft.fromSignal(HaqorLexiconEntryText entry) =>
      LexiconEntryDraft(
        id: entry.id,
        data: _decode(entry.json),
        verses: _verses(entry.verses),
        support: _support(entry.support),
        names: entry.names.map(LexiconEntryDraft.fromName).toList(),
      );

  /// A name entry (haqor-core `data/lexicon/names`).
  factory LexiconEntryDraft.fromName(HaqorLexiconNameText name) =>
      LexiconEntryDraft(
        id: name.id,
        data: _decode(name.json),
        verses: _verses(name.verses),
      );

  final String id;

  /// The entry, in the schema's shape (haqor-core `data/lexicon/README.md`).
  final Map<String, dynamic> data;

  /// The verses the entry cites, by reference.
  final Map<String, LexiconVerse> verses;

  /// Each word's evidence counted, in the order of its words (haqor-core's
  /// `WordSupport`): uses, verses, cognates for and against, kin. As the
  /// entry was when read; edits do not recount it.
  final List<Map<String, dynamic>> support;

  /// For a root entry, the name entries formed from it, which link back to it.
  final List<LexiconEntryDraft> names;

  /// Whether this is a name entry rather than a root's: it names people and
  /// has no words.
  bool get isName => data.containsKey('people') && !data.containsKey('words');

  /// Whether it has unsaved changes.
  bool dirty = false;

  /// Where the entry stands in review: a draft, signed off, or signed off
  /// and changed since (`updated` later than the `reviewed` date).
  LexiconSignOff get signOff {
    if (data['status'] != 'reviewed') return LexiconSignOff.draft;
    final reviewed = data['reviewed'];
    final updated = data['updated'];
    if (reviewed is String &&
        updated is String &&
        updated.compareTo(reviewed) > 0) {
      return LexiconSignOff.changed;
    }
    return LexiconSignOff.signedOff;
  }

  /// The day it was signed off, `YYYY-MM-DD`, if it has been.
  String? get signedOffOn =>
      data['status'] == 'reviewed' && data['reviewed'] is String
      ? data['reviewed'] as String
      : null;

  /// Sign the entry off on [day] (`YYYY-MM-DD`), or with [day] null put it
  /// back to draft. `reviewed` is kept straight after `status`, where the
  /// files have it.
  void setSignOff(String? day) {
    final entries = data.entries.toList();
    data.clear();
    for (final e in entries) {
      if (e.key == 'reviewed') continue;
      if (e.key == 'status') {
        data['status'] = day == null ? 'draft' : 'reviewed';
        if (day != null) data['reviewed'] = day;
      } else {
        data[e.key] = e.value;
      }
    }
  }

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
      entries: [
        ...message.entries.map(LexiconEntryDraft.fromSignal),
        ...message.names.map(LexiconEntryDraft.fromName),
      ],
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

Map<String, dynamic> _decode(String json) {
  final decoded = jsonDecode(json);
  return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
}

Map<String, LexiconVerse> _verses(List<HaqorLexiconVerse> verses) => {
  for (final v in verses)
    v.reference: LexiconVerse(
      reference: v.reference,
      book: v.book,
      chapter: v.chapter,
      verse: v.verse,
      original: v.original,
      english: v.english,
      peshitta: v.peshitta,
    ),
};

List<Map<String, dynamic>> _support(String json) {
  if (json.isEmpty) return const [];
  final decoded = jsonDecode(json);
  if (decoded is! List) return const [];
  return [
    for (final word in decoded)
      if (word is Map<String, dynamic>) word,
  ];
}

/// Where a lexicon entry stands in review.
enum LexiconSignOff {
  /// Not signed off.
  draft,

  /// Signed off, and unchanged since.
  signedOff,

  /// Signed off, then changed: to be looked at again.
  changed;

  /// Whether the entry still wants a reviewer's sign-off.
  bool get toReview => this != signedOff;
}
