//! Handler for Haqor's apologetics (see `haqor_core::bible::Apologetic`).

use haqor_core::bible::{Apologetic, VerseSpan};
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    ApologeticAudienceEntry, ApologeticEntry, ApologeticObjectionEntry, ApologeticPointEntry,
    ApologeticSourceEntry, ApologeticSubjectEntry, ApologeticTopicEntry, Apologetics,
    GetApologetics, PassageSpan,
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
        topics: a.topics,
    }
}

pub async fn get_apologetics(bible: SharedBible) {
    let receiver = GetApologetics::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible = lock(&bible);
        let read = || -> Result<_, Box<dyn std::error::Error>> {
            Ok((
                bible.apologetic_subjects()?,
                bible.apologetic_topics()?,
                bible.apologetic_audiences()?,
                bible.apologetics()?,
            ))
        };
        let (subjects, topics, audiences, entries) = read().unwrap_or_else(|e| {
            debug_print!("get_apologetics error: {e:?}");
            Default::default()
        });
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
            topics: topics
                .into_iter()
                .map(|t| ApologeticTopicEntry {
                    key: t.key,
                    title: t.title,
                })
                .collect(),
            audiences: audiences
                .into_iter()
                .map(|a| ApologeticAudienceEntry {
                    key: a.key,
                    title: a.title,
                    note: a.note,
                    agree: a.agree,
                    differ: a.differ,
                })
                .collect(),
            entries: entries.into_iter().map(entry).collect(),
        }
        .send_signal_to_dart();
    }
}
