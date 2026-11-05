//! Handler for Haqor's book outlines (see `haqor_core::bible::Outline`).

use haqor_core::bible::Outline;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    GetOutlines, OutlineEntry, OutlineFacetEntry, OutlineFactEntry, OutlineSectionEntry, Outlines,
};

fn entry(o: Outline) -> OutlineEntry {
    OutlineEntry {
        key: o.key,
        title: o.title,
        note: o.note,
        facets: o
            .facets
            .into_iter()
            .map(|f| OutlineFacetEntry {
                key: f.key,
                title: f.title,
            })
            .collect(),
        sections: o
            .sections
            .into_iter()
            .map(|s| OutlineSectionEntry {
                parent: s.parent,
                book: s.span.first.book,
                chapter: s.span.first.chapter,
                verse: s.span.first.verse,
                last_book: s.span.last.book,
                last_chapter: s.span.last.chapter,
                last_verse: s.span.last.verse,
                title: s.title,
                subtitle: s.subtitle,
                superscription: s.superscription,
                note: s.note,
                facts: s
                    .facts
                    .into_iter()
                    .map(|f| OutlineFactEntry {
                        facet: f.facet,
                        values: f.values,
                    })
                    .collect(),
            })
            .collect(),
    }
}

pub async fn get_outlines(bible: SharedBible) {
    let receiver = GetOutlines::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let outlines = lock(&bible).outlines().unwrap_or_else(|e| {
            debug_print!("get_outlines error: {e:?}");
            Vec::new()
        });
        Outlines {
            request_id: req.request_id,
            outlines: outlines.into_iter().map(entry).collect(),
        }
        .send_signal_to_dart();
    }
}
