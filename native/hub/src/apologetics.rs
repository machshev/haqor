//! Handler for Haqor's apologetics (see `haqor_core::bible::Apologetic`).

use haqor_core::bible::{Apologetic, VerseSpan};
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    ApologeticEntry, ApologeticObjectionEntry, ApologeticPointEntry, ApologeticSourceEntry,
    ApologeticSubjectEntry, Apologetics, GetApologetics, PassageSpan,
};

fn passage(span: VerseSpan) -> PassageSpan {
    PassageSpan {
        book: span.first.book,
        chapter: span.first.chapter,
        verse: span.first.verse,
        last_chapter: span.last.chapter,
        last_verse: span.last.verse,
    }
}

fn passages(spans: Vec<VerseSpan>) -> Vec<PassageSpan> {
    spans.into_iter().map(passage).collect()
}

fn entry(a: Apologetic) -> ApologeticEntry {
    ApologeticEntry {
        id: a.id,
        key: a.key,
        subject: a.subject,
        kind: a.kind,
        title: a.title,
        summary: a.summary,
        passages: passages(a.passages),
        points: a
            .points
            .into_iter()
            .map(|p| ApologeticPointEntry {
                claim: p.claim,
                passages: passages(p.passages),
                sources: p
                    .sources
                    .into_iter()
                    .map(|s| ApologeticSourceEntry {
                        title: s.title,
                        author: s.author,
                        loc: s.loc,
                        quote: s.quote,
                    })
                    .collect(),
            })
            .collect(),
        objections: a
            .objections
            .into_iter()
            .map(|o| ApologeticObjectionEntry {
                objection: o.objection,
                answer: o.answer,
                passages: passages(o.passages),
            })
            .collect(),
        related: a.related,
    }
}

pub async fn get_apologetics(bible: SharedBible) {
    let receiver = GetApologetics::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible = lock(&bible);
        let (subjects, entries) = match (bible.apologetic_subjects(), bible.apologetics()) {
            (Ok(subjects), Ok(entries)) => (subjects, entries),
            (subjects, entries) => {
                debug_print!(
                    "get_apologetics error: {:?} {:?}",
                    subjects.err(),
                    entries.err()
                );
                (Vec::new(), Vec::new())
            }
        };
        Apologetics {
            request_id: req.request_id,
            subjects: subjects
                .into_iter()
                .map(|s| ApologeticSubjectEntry {
                    key: s.key,
                    title: s.title,
                    note: s.note,
                })
                .collect(),
            entries: entries.into_iter().map(entry).collect(),
        }
        .send_signal_to_dart();
    }
}
