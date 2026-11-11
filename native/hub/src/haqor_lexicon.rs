//! Handlers for the Haqor lexicon's review page (haqor-core ADR 7): its
//! entries, read from haqor-core's `data/lexicon` when `HAQOR_LEXICON_DIR`
//! names it, with the text of the verses they cite, and saves back to it.

use std::path::PathBuf;

use haqor_core::bible::Bible;
use haqor_core::haqor_lexicon;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    GetHaqorLexicon, HaqorLexicon, HaqorLexiconEntryText, HaqorLexiconNameText,
    HaqorLexiconSaveStatus, HaqorLexiconVerse, SaveHaqorLexiconEntry,
};

/// The directory entries are reviewed in, when one is set. Never on the web.
fn review_dir() -> Option<PathBuf> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        std::env::var_os("HAQOR_LEXICON_DIR")
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from)
    }
    #[cfg(target_arch = "wasm32")]
    {
        None
    }
}

/// A verse's text and English: the Greek in the New Testament, the Hebrew in
/// the Old; and in the New Testament the Peshitta, in Hebrew letters.
fn verse(bible: &Bible, book: u8, chapter: u8, verse: u8) -> (String, String, String) {
    let english = |spans: Vec<(u8, Vec<haqor_core::translation::TranslationSpan>)>| {
        spans
            .into_iter()
            .find(|(v, _)| *v == verse)
            .map(|(_, spans)| spans.into_iter().map(|s| s.text).collect::<String>())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    if book >= 40 {
        let greek = bible
            .greek_chapter(book, chapter)
            .unwrap_or_default()
            .into_iter()
            .find(|v| v.verse == verse)
            .map(|v| v.text())
            .unwrap_or_default();
        let english = english(
            bible
                .greek_chapter_translation(book, chapter)
                .unwrap_or_default(),
        );
        let peshitta = bible.get(book, chapter, verse).unwrap_or_default();
        (greek, english, peshitta)
    } else {
        let hebrew = bible.get(book, chapter, verse).unwrap_or_default();
        let english = english(bible.chapter_translation(book, chapter).unwrap_or_default());
        (hebrew, english, String::new())
    }
}

/// The verses an entry's JSON cites, with their text.
fn cited_verses(bible: &Bible, json: &str) -> Vec<HaqorLexiconVerse> {
    haqor_lexicon::references_in(json)
        .into_iter()
        .map(|(reference, (book, chapter, v))| {
            let (original, english, peshitta) = verse(bible, book, chapter, v);
            HaqorLexiconVerse {
                reference,
                book,
                chapter,
                verse: v,
                original,
                english,
                peshitta,
            }
        })
        .collect()
}

/// A name entry as the app shows it: its JSON and the text of the verses it
/// cites.
pub(crate) fn name_text(bible: &Bible, id: String, json: String) -> HaqorLexiconNameText {
    let verses = cited_verses(bible, &json);
    HaqorLexiconNameText { id, json, verses }
}

/// The name entry of the person `entity_id`, where Haqor has one.
pub(crate) fn person_name(bible: &Bible, entity_id: u32) -> Option<HaqorLexiconNameText> {
    match bible.haqor_lexicon_name_for_entity(entity_id.into()) {
        Ok(found) => found.map(|(id, json)| name_text(bible, id, json)),
        Err(error) => {
            debug_print!("haqor_lexicon_name_for_entity({entity_id}) error: {error:?}");
            None
        }
    }
}

/// The name entry for the word `surface`, which names the person
/// `entity_id`: only one that is this word (the Deity's Yahweh entry is not
/// shown on אֱלֹהִים).
pub(crate) fn word_name(
    bible: &Bible,
    entity_id: u32,
    surface: &str,
) -> Option<HaqorLexiconNameText> {
    match bible.haqor_lexicon_name_for_word(entity_id.into(), surface) {
        Ok(found) => found.map(|(id, json)| name_text(bible, id, json)),
        Err(error) => {
            debug_print!("haqor_lexicon_name_for_word({entity_id}) error: {error:?}");
            None
        }
    }
}

/// An entry as the app shows it: its JSON, the text of the verses it cites,
/// its words' evidence counted, and `names`, the name entries formed from it
/// as id and JSON.
pub(crate) fn entry_text(
    bible: &Bible,
    id: String,
    json: String,
    names: Vec<(String, String)>,
) -> HaqorLexiconEntryText {
    let verses = cited_verses(bible, &json);
    // The counted evidence for each word, as JSON (haqor-core's
    // `WordSupport`); empty when the entry does not parse.
    let support = haqor_lexicon::entry_support_json(bible, &json).unwrap_or_default();
    HaqorLexiconEntryText {
        id,
        json,
        verses,
        support,
        names: names
            .into_iter()
            .map(|(id, json)| name_text(bible, id, json))
            .collect(),
    }
}

/// The Haqor lexicon entry for a word of the text, where there is one (see
/// [`Bible::haqor_lexicon_entry`]): the word sheet shows it in place of the
/// other lexicons.
pub(crate) fn word_entry(
    bible: &Bible,
    root: &str,
    word: &str,
    prefix: &str,
) -> Option<HaqorLexiconEntryText> {
    match bible.haqor_lexicon_entry(root, word, prefix) {
        Ok(found) => found.map(|(id, json)| {
            let names = bible.haqor_lexicon_names_of(&id).unwrap_or_default();
            entry_text(bible, id, json, names)
        }),
        Err(error) => {
            debug_print!("haqor_lexicon_entry({root:?}, {word:?}) error: {error:?}");
            None
        }
    }
}

/// The entries and the name entries under review in `dir`, each root entry
/// with the names in `dir` that link back to it.
fn entries(
    bible: &Bible,
    dir: &std::path::Path,
) -> anyhow::Result<(Vec<HaqorLexiconEntryText>, Vec<HaqorLexiconNameText>)> {
    let names = haqor_lexicon::read_name_texts(dir)?;
    let entry_of = |json: &str| haqor_lexicon::name_entry_root(json).unwrap_or_default();
    let entries = haqor_lexicon::read_entry_texts(dir)?
        .into_iter()
        .map(|(id, json)| {
            let own = names
                .iter()
                .filter(|(_, n)| entry_of(n) == id)
                .cloned()
                .collect();
            entry_text(bible, id, json, own)
        })
        .collect();
    let names = names
        .into_iter()
        .map(|(id, json)| name_text(bible, id, json))
        .collect();
    Ok((entries, names))
}

pub async fn get_haqor_lexicon(bible: SharedBible) {
    let receiver = GetHaqorLexicon::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let request_id = signal_pack.message.request_id;
        let Some(dir) = review_dir() else {
            HaqorLexicon {
                request_id,
                editable: false,
                dir: String::new(),
                error: "Set HAQOR_LEXICON_DIR to haqor-core's data/lexicon to review entries."
                    .to_string(),
                entries: Vec::new(),
                names: Vec::new(),
            }
            .send_signal_to_dart();
            continue;
        };
        let read = {
            let bible = lock(&bible);
            entries(&bible, &dir)
        };
        let ((entries, names), error) = match read {
            Ok(read) => (read, String::new()),
            Err(error) => {
                debug_print!("get_haqor_lexicon error: {error:?}");
                ((Vec::new(), Vec::new()), format!("{error:#}"))
            }
        };
        HaqorLexicon {
            request_id,
            editable: true,
            dir: dir.display().to_string(),
            error,
            entries,
            names,
        }
        .send_signal_to_dart();
    }
}

pub async fn save_haqor_lexicon_entry(bible: SharedBible) {
    let receiver = SaveHaqorLexiconEntry::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let save = signal_pack.message;
        let result = match review_dir() {
            None => Err(anyhow::anyhow!("HAQOR_LEXICON_DIR is not set")),
            Some(dir) => {
                let bible = lock(&bible);
                bible
                    .verse_refs()
                    .map_err(anyhow::Error::from)
                    .and_then(|verses| haqor_lexicon::save_entry(&dir, &save.json, &verses))
            }
        };
        let (success, message) = match result {
            Ok(summary) => (
                true,
                format!(
                    "Saved. The lexicon checks clean: {} entries ({} reviewed), {} citations.",
                    summary.entries, summary.reviewed, summary.citations
                ),
            ),
            Err(error) => (false, format!("{error:#}")),
        };
        HaqorLexiconSaveStatus {
            id: save.id,
            success,
            message,
        }
        .send_signal_to_dart();
    }
}
