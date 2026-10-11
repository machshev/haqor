//! Handlers for the archaeological finds that bear on the Bible (see
//! `haqor_core::archaeology`).

use haqor_core::archaeology::{Artifact, ArtifactSource};
use haqor_core::names::NameSummary;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    ArtifactAttestationEntry, ArtifactEntry, ArtifactPassageEntry, ArtifactSourceEntry,
    Artifacts, ChapterArtifactEntry, ChapterArtifacts, GetArtifacts, GetChapterArtifacts,
    NameSummaryEntry, PassageSpan,
};

fn person(s: NameSummary) -> NameSummaryEntry {
    NameSummaryEntry {
        id: s.id,
        name: s.name,
        kind: s.kind.as_str().to_string(),
        description: s.description,
        origin: s.origin,
        occurrences: s.occurrences,
    }
}

fn no_place() -> NameSummaryEntry {
    NameSummaryEntry {
        id: 0,
        name: String::new(),
        kind: String::new(),
        description: String::new(),
        origin: String::new(),
        occurrences: 0,
    }
}

/// A core find as the signals carry it.
pub(crate) fn entry(a: Artifact) -> ArtifactEntry {
    ArtifactEntry {
        id: a.id,
        key: a.key,
        name: a.name,
        other_names: a.other_names,
        kind: a.kind,
        date: a.date,
        year: a.year,
        script: a.script,
        found_site: a.found_site,
        found_year: a.found_year.unwrap_or(0),
        found_place: a.found_place.map_or_else(no_place, person),
        museum: a.museum,
        wikipedia: a.wikipedia,
        wikidata: a.wikidata,
        summary: a.summary,
        attestations: a
            .attestations
            .into_iter()
            .map(|t| ArtifactAttestationEntry {
                person: person(t.person),
                strength: t.strength.as_str().to_string(),
                how: t.how,
                source: t.source,
            })
            .collect(),
        passages: a
            .passages
            .into_iter()
            .map(|p| ArtifactPassageEntry {
                passage: PassageSpan {
                    book: p.passage.first.book,
                    chapter: p.passage.first.chapter,
                    verse: p.passage.first.verse,
                    last_chapter: p.passage.last.chapter,
                    last_verse: p.passage.last.verse,
                },
                strength: p.strength.as_str().to_string(),
                how: p.how,
                source: p.source,
            })
            .collect(),
    }
}

pub(crate) fn source(s: ArtifactSource) -> ArtifactSourceEntry {
    ArtifactSourceEntry {
        id: s.id,
        citation: s.citation,
        url: s.url,
    }
}

pub async fn get_artifacts(bible: SharedBible) {
    let receiver = GetArtifacts::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let archaeology = lock(&bible).artifacts().unwrap_or_else(|e| {
            debug_print!("get_artifacts error: {:?}", e);
            Default::default()
        });
        Artifacts {
            request_id: req.request_id,
            entries: archaeology.artifacts.into_iter().map(entry).collect(),
            sources: archaeology.sources.into_iter().map(source).collect(),
        }
        .send_signal_to_dart();
    }
}

pub async fn get_chapter_artifacts(bible: SharedBible) {
    let receiver = GetChapterArtifacts::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible = lock(&bible);
        let found = bible
            .chapter_artifacts(req.book, req.chapter)
            .unwrap_or_else(|e| {
                debug_print!("get_chapter_artifacts error: {:?}", e);
                Vec::new()
            });
        // The sources the chapter's finds cite, for their footnotes.
        let sources = if found.is_empty() {
            Vec::new()
        } else {
            bible.artifacts().map(|a| a.sources).unwrap_or_default()
        };
        ChapterArtifacts {
            request_id: req.request_id,
            book: req.book,
            chapter: req.chapter,
            entries: found
                .into_iter()
                .map(|f| ChapterArtifactEntry {
                    artifact: entry(f.artifact),
                    verses: f.verses,
                    people: f.people.into_iter().map(person).collect(),
                })
                .collect(),
            sources: sources.into_iter().map(source).collect(),
        }
        .send_signal_to_dart();
    }
}
