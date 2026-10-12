//! Handler for finding the Bible's words by what the reader types (see
//! `haqor_core::word_search`).

use haqor_core::word_search::WordSearchMatch;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, read_corpus};
use crate::signals::{SearchWords, WordSearchEntry, WordSearchResults};

fn entry(m: WordSearchMatch) -> WordSearchEntry {
    WordSearchEntry {
        language: m.language.as_str().to_string(),
        matched: m.matched.as_str().to_string(),
        headword: m.headword,
        root: m.root,
        gloss: m.gloss,
        part_of_speech: m.part_of_speech,
        word: m.word,
        forms: m.forms,
        lexeme: m.lexeme,
        occurrences: m.occurrences,
    }
}

pub async fn search_words(bible: SharedBible) {
    let receiver = SearchWords::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        // A gloss search reads every word of the text's English, so it runs
        // off the runtime as the occurrence scans do.
        let query = req.query;
        let matches = read_corpus(&bible, move |bible| bible.search_words(&query))
            .await
            .unwrap_or_else(|e| {
                debug_print!("search_words panicked: {e}");
                Ok(Vec::new())
            })
            .unwrap_or_else(|e| {
                debug_print!("search_words error: {e:?}");
                Vec::new()
            });
        WordSearchResults {
            request_id: req.request_id,
            matches: matches.into_iter().map(entry).collect(),
        }
        .send_signal_to_dart();
    }
}
