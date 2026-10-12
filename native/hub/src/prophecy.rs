//! Handlers for the prophecies of the Old Testament and their fulfilments
//! (see `haqor_core::bible::Prophecy`).

use haqor_core::bible::{Prophecy, ProphecyFilter, VerseSpan};
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    GetProphecies, GetVerseProphecies, PassageSpan, Prophecies, ProphecyEntry,
    ProphecyFulfilmentEntry, ProphecyPatternEntry, ProphecyPatternMemberEntry, VerseProphecies,
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

/// A core prophecy as the signals carry it.
fn entry(p: Prophecy) -> ProphecyEntry {
    ProphecyEntry {
        id: p.id,
        passage: passage(p.passage),
        title: p.title,
        theme: p.theme.unwrap_or_default(),
        messianic: p.messianic,
        stages: p.stages,
        note: p.note,
        fulfilments: p
            .fulfilments
            .into_iter()
            .map(|f| ProphecyFulfilmentEntry {
                passage: passage(f.passage),
                prophecy_verses: passage(f.prophecy_verses),
                kind: f.kind,
                stage: f.stage,
                formula: f.formula.unwrap_or_default(),
                reviewed: f.reviewed,
                note: f.note,
            })
            .collect(),
        patterns: p
            .patterns
            .into_iter()
            .map(|pattern| ProphecyPatternEntry {
                id: pattern.id,
                title: pattern.title,
                note: pattern.note,
                members: pattern
                    .members
                    .into_iter()
                    .map(|m| ProphecyPatternMemberEntry {
                        prophecy_id: m.prophecy_id,
                        passage: passage(m.passage),
                        stage: m.stage,
                        label: m.label,
                    })
                    .collect(),
            })
            .collect(),
    }
}

pub async fn get_verse_prophecies(bible: SharedBible) {
    let receiver = GetVerseProphecies::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let prophecies = lock(&bible)
            .verse_prophecies(req.book, req.chapter, req.verse)
            .unwrap_or_else(|e| {
                debug_print!("get_verse_prophecies error: {:?}", e);
                Vec::new()
            });
        VerseProphecies {
            book: req.book,
            chapter: req.chapter,
            verse: req.verse,
            entries: prophecies.into_iter().map(entry).collect(),
        }
        .send_signal_to_dart();
    }
}

pub async fn get_prophecies(bible: SharedBible) {
    let receiver = GetProphecies::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let filter = ProphecyFilter {
            book: (req.book > 0).then_some(req.book),
            first_chapter: (req.first_chapter > 0).then_some(req.first_chapter),
            last_chapter: (req.last_chapter > 0).then_some(req.last_chapter),
            theme: (!req.theme.is_empty()).then_some(req.theme),
            messianic: match req.messianic {
                1 => Some(true),
                2 => Some(false),
                _ => None,
            },
        };
        let bible = lock(&bible);
        let (total, prophecies) = match (
            bible.prophecy_count(&filter),
            bible.prophecies(&filter, req.limit, req.offset),
        ) {
            (Ok(total), Ok(prophecies)) => (total, prophecies),
            (count, page) => {
                debug_print!("get_prophecies error: {:?} {:?}", count.err(), page.err());
                (0, Vec::new())
            }
        };
        Prophecies {
            request_id: req.request_id,
            book: req.book,
            total,
            entries: prophecies.into_iter().map(entry).collect(),
        }
        .send_signal_to_dart();
    }
}
