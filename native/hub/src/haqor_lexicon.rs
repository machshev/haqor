//! Handlers for the Haqor lexicon's review page (haqor-core ADR 7): its
//! entries, read from a sibling haqor-core checkout (or `HAQOR_LEXICON_DIR`),
//! with the text of the verses they cite, and saved back to it.

use std::path::{Path, PathBuf};

use haqor_core::bible::Bible;
use haqor_core::haqor_lexicon;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock};
use crate::signals::{
    GetHaqorLexicon, HaqorLexicon, HaqorLexiconEntryText, HaqorLexiconNameText,
    HaqorLexiconSaveStatus, HaqorLexiconVerse, SaveHaqorLexiconEntry,
};

/// Find a sibling checkout when running from the Haqor repository or one of
/// its subdirectories.
#[cfg(not(target_arch = "wasm32"))]
fn sibling_review_dir(cwd: &Path) -> Option<PathBuf> {
    cwd.ancestors()
        .find(|ancestor| ancestor.file_name().is_some_and(|name| name == "haqor"))
        .and_then(Path::parent)
        .map(|parent| parent.join("haqor-core/data/lexicon"))
}

/// The directory entries are reviewed in. An explicit path takes precedence
/// over discovery, including when that path cannot be read. Never on the web.
fn review_dir() -> Option<PathBuf> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        std::env::var_os("HAQOR_LEXICON_DIR")
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from)
            .or_else(|| {
                std::env::current_dir()
                    .ok()
                    .and_then(|cwd| sibling_review_dir(&cwd))
                    .filter(|dir| dir.is_dir())
            })
            .or_else(|| {
                std::env::current_exe()
                    .ok()
                    .and_then(|exe| sibling_review_dir(&exe))
                    .filter(|dir| dir.is_dir())
            })
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

/// The list can be shown and searched without calculating every entry's
/// evidence or fetching every cited verse.
fn index(dir: &Path) -> anyhow::Result<(Vec<HaqorLexiconEntryText>, Vec<HaqorLexiconNameText>)> {
    let entries = haqor_lexicon::read_entry_texts(dir)?
        .into_iter()
        .map(|(id, json)| HaqorLexiconEntryText {
            id,
            json,
            verses: Vec::new(),
            support: String::new(),
            names: Vec::new(),
        })
        .collect();
    let names = haqor_lexicon::read_name_texts(dir)?
        .into_iter()
        .map(|(id, json)| HaqorLexiconNameText {
            id,
            json,
            verses: Vec::new(),
        })
        .collect();
    Ok((entries, names))
}

/// Load only the selected JSON file, then add its evidence and cited verses.
fn detail(
    bible: &Bible,
    dir: &Path,
    id: &str,
    is_name: bool,
) -> anyhow::Result<(Vec<HaqorLexiconEntryText>, Vec<HaqorLexiconNameText>)> {
    anyhow::ensure!(
        !id.is_empty()
            && id
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_'),
        "Invalid lexicon entry id"
    );
    let file = if is_name {
        dir.join("names")
    } else {
        dir.to_path_buf()
    }
    .join(format!("{id}.json"));
    let json = std::fs::read_to_string(&file)
        .map_err(|error| anyhow::anyhow!("reading {}: {error}", file.display()))?;
    if is_name {
        Ok((Vec::new(), vec![name_text(bible, id.to_string(), json)]))
    } else {
        let names = haqor_lexicon::read_name_texts(dir)?
            .into_iter()
            .filter(|(_, name)| haqor_lexicon::name_entry_root(name).as_deref() == Some(id))
            .collect();
        Ok((
            vec![entry_text(bible, id.to_string(), json, names)],
            Vec::new(),
        ))
    }
}

pub async fn get_haqor_lexicon(bible: SharedBible) {
    let receiver = GetHaqorLexicon::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let request_id = signal_pack.message.request_id;
        let entry_id = signal_pack.message.entry_id;
        let is_name = signal_pack.message.is_name;
        let Some(dir) = review_dir() else {
            HaqorLexicon {
                request_id,
                editable: false,
                dir: String::new(),
                error: "No sibling haqor-core/data/lexicon found. Set HAQOR_LEXICON_DIR to review entries."
                    .to_string(),
                entries: Vec::new(),
                names: Vec::new(),
            }
            .send_signal_to_dart();
            continue;
        };
        let read = if entry_id.is_empty() {
            index(&dir)
        } else {
            let bible = lock(&bible);
            detail(&bible, &dir, &entry_id, is_name)
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
            None => Err(anyhow::anyhow!(
                "No sibling haqor-core/data/lexicon found; set HAQOR_LEXICON_DIR"
            )),
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
