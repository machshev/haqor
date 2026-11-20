//! Handlers for the Haqor lexicon review page (haqor-core ADR 7). A source
//! checkout permits validated editing; a phone uses bundled database entries
//! and records approvals or notes in synced progress.

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use haqor_core::bible::Bible;
use haqor_core::haqor_lexicon;
use haqor_core::lexicon_review::{self, LexiconReviewRecord};
use rinf::{DartSignal, RustSignal, debug_print};
use serde::Deserialize;
use serde_json::{Value, json};

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
    let uses = uses(bible, &json);
    HaqorLexiconNameText {
        id,
        json,
        verses,
        uses,
    }
}

/// How often the entry written as `json` is used in the Hebrew Bible; the
/// review list sorts by it.
fn uses(bible: &Bible, json: &str) -> u32 {
    haqor_lexicon::entry_uses(bible, json)
        .try_into()
        .unwrap_or(u32::MAX)
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
    let uses = uses(bible, &json);
    HaqorLexiconEntryText {
        id,
        json,
        verses,
        support,
        uses,
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

/// The entry for a word at a place in the text, and the word of it the
/// review assigned there (its index in the entry's `words`), where reviewed.
pub(crate) fn word_entry_at(
    bible: &Bible,
    root: &str,
    word: &str,
    prefix: &str,
    context: Option<(u8, u8, u8, u32)>,
) -> Option<(HaqorLexiconEntryText, Option<u32>)> {
    let found = context
        .and_then(|(book, chapter, verse, position)| {
            bible
                .haqor_lexicon_entry_at(book, chapter, verse, position)
                .ok()
                .flatten()
        })
        .or_else(|| {
            bible
                .haqor_lexicon_entry(root, word, prefix)
                .ok()
                .flatten()
                .map(|(id, json)| (id, json, None))
        });
    found.map(|(id, json, lexeme)| {
        let names = bible.haqor_lexicon_names_of(&id).unwrap_or_default();
        (entry_text(bible, id, json, names), lexeme)
    })
}

/// The list can be shown and searched without calculating every entry's
/// evidence or fetching every cited verse; only its uses are counted, so it
/// can be sorted by them.
fn index(
    bible: &Bible,
    dir: &Path,
) -> anyhow::Result<(Vec<HaqorLexiconEntryText>, Vec<HaqorLexiconNameText>)> {
    let entries = haqor_lexicon::read_entry_texts(dir)?
        .into_iter()
        .map(|(id, json)| HaqorLexiconEntryText {
            uses: uses(bible, &json),
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
            uses: uses(bible, &json),
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

/// Add local review state to a database entry without changing its source
/// JSON. The store strips these private fields before displaying the entry.
fn mobile_json(records: &[LexiconReviewRecord], kind: &str, id: &str, source: &str) -> String {
    let Ok(mut value) = serde_json::from_str::<Value>(source) else {
        return source.to_string();
    };
    let Some(object) = value.as_object_mut() else {
        return source.to_string();
    };
    let hash = lexicon_review::source_hash(source);
    object.insert("_mobileSourceHash".into(), json!(hash));
    if let Some(approval) = records.iter().find(|record| {
        record.approved
            && record.entry_kind == kind
            && record.entry_id == id
            && record.source_hash == hash
    }) {
        let day = chrono_day(approval.updated_epoch);
        object.insert("_mobileApprovedOn".into(), json!(day));
    }
    let notes: Vec<Value> = records
        .iter()
        .filter(|record| !record.approved && record.entry_kind == kind && record.entry_id == id)
        .map(|record| {
            json!({
                "targetKind": record.target_kind,
                "targetKey": record.target_key,
                "note": record.note,
                "sourceHash": record.source_hash,
            })
        })
        .collect();
    object.insert("_mobileNotes".into(), json!(notes));
    value.to_string()
}

fn chrono_day(epoch: i64) -> String {
    // SQLite's date format, without pulling a date library into the hub.
    // A review's exact epoch remains in the progress record.
    let days = epoch.div_euclid(86_400);
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 } / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let mut y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    y += i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct MobileReviewRequest {
    entry_id: String,
    is_name: bool,
    source_hash: String,
    target_kind: String,
    target_key: String,
    note: String,
    approved: bool,
}

fn contains_sense(value: &Value, id: &str) -> bool {
    match value {
        Value::Object(map) => {
            map.get("id").and_then(Value::as_str) == Some(id) && map.contains_key("definition")
                || map.values().any(|child| contains_sense(child, id))
        }
        Value::Array(items) => items.iter().any(|child| contains_sense(child, id)),
        _ => false,
    }
}

fn save_mobile_review(bible: &Bible, text: &str) -> anyhow::Result<String> {
    let request: MobileReviewRequest = serde_json::from_str(text)?;
    let source = bible
        .haqor_lexicon_review_entry(&request.entry_id, request.is_name)?
        .ok_or_else(|| anyhow::anyhow!("Entry is not in the bundled lexicon"))?;
    anyhow::ensure!(
        lexicon_review::source_hash(&source) == request.source_hash,
        "This entry changed since it was opened; reload before reviewing"
    );
    let value: Value = serde_json::from_str(&source)?;
    let valid_target = match request.target_kind.as_str() {
        "entry" => request.target_key.is_empty(),
        "word" => {
            value["words"].as_array().is_some_and(|words| {
                words
                    .iter()
                    .any(|word| word["lemma"].as_str() == Some(request.target_key.as_str()))
            }) || value
                .pointer(&request.target_key)
                .is_some_and(|word| word.get("lemma").is_some())
        }
        "sense" => {
            contains_sense(&value, &request.target_key)
                || value
                    .pointer(&request.target_key)
                    .is_some_and(|sense| sense.get("definition").is_some())
        }
        "doctrine" => {
            value["doctrine"].as_array().is_some_and(|items| {
                items
                    .iter()
                    .any(|item| item["topic"].as_str() == Some(request.target_key.as_str()))
            }) || value
                .pointer(&request.target_key)
                .is_some_and(|item| item.get("topic").is_some())
        }
        _ => false,
    };
    anyhow::ensure!(valid_target, "This review target is no longer in the entry");
    let kind = if request.is_name { "name" } else { "root" };
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
    let existing = bible.lexicon_reviews()?;
    if request.approved {
        anyhow::ensure!(
            !existing.iter().any(|record| {
                !record.approved
                    && record.entry_kind == kind
                    && record.entry_id == request.entry_id
                    && record.source_hash == request.source_hash
            }),
            "This version has open review notes; resolve them before approving"
        );
    } else if let Some(mut approval) = existing.into_iter().find(|record| {
        record.approved
            && record.entry_kind == kind
            && record.entry_id == request.entry_id
            && record.source_hash == request.source_hash
    }) {
        approval.deleted = true;
        approval.updated_epoch = (now.as_secs() as i64).max(approval.updated_epoch + 1);
        bible.save_lexicon_review(&approval)?;
    }
    let id = if request.approved {
        format!("approval:{kind}:{}", request.entry_id)
    } else {
        format!("note:{kind}:{}:{}", request.entry_id, now.as_nanos())
    };
    let record = LexiconReviewRecord {
        id,
        entry_id: request.entry_id,
        entry_kind: kind.to_string(),
        source_hash: request.source_hash,
        target_kind: request.target_kind,
        target_key: request.target_key,
        note: request.note,
        approved: request.approved,
        created_epoch: now.as_secs() as i64,
        updated_epoch: now.as_secs() as i64,
        handled: false,
        deleted: false,
    };
    bible.save_lexicon_review(&record)?;
    Ok(if record.approved {
        "Approval saved; it will sync with your progress".to_string()
    } else {
        "Review note saved; it will sync with your progress".to_string()
    })
}

pub async fn get_haqor_lexicon(bible: SharedBible) {
    let receiver = GetHaqorLexicon::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let request_id = signal_pack.message.request_id;
        let entry_id = signal_pack.message.entry_id;
        let is_name = signal_pack.message.is_name;
        let dir = review_dir();
        let read = if let Some(dir) = &dir {
            let bible = lock(&bible);
            if entry_id.is_empty() {
                index(&bible, dir)
            } else {
                detail(&bible, dir, &entry_id, is_name)
            }
        } else {
            let bible = lock(&bible);
            (|| -> anyhow::Result<_> {
                let reviews = bible.lexicon_reviews()?;
                let (roots, names) = if entry_id.is_empty() {
                    bible.haqor_lexicon_review_index()?
                } else {
                    let source = bible.haqor_lexicon_review_entry(&entry_id, is_name)?;
                    let row = source
                        .into_iter()
                        .map(|json| (entry_id.clone(), json))
                        .collect();
                    if is_name {
                        (Vec::new(), row)
                    } else {
                        (row, Vec::new())
                    }
                };
                let entries = roots
                    .into_iter()
                    .map(|(id, json)| {
                        let decorated = mobile_json(&reviews, "root", &id, &json);
                        if entry_id.is_empty() {
                            HaqorLexiconEntryText {
                                uses: uses(&bible, &json),
                                id,
                                json: decorated,
                                verses: Vec::new(),
                                support: String::new(),
                                names: Vec::new(),
                            }
                        } else {
                            let mut entry = entry_text(&bible, id, json, Vec::new());
                            entry.json = decorated;
                            entry
                        }
                    })
                    .collect();
                let names = names
                    .into_iter()
                    .map(|(id, json)| {
                        let decorated = mobile_json(&reviews, "name", &id, &json);
                        if entry_id.is_empty() {
                            HaqorLexiconNameText {
                                uses: uses(&bible, &json),
                                id,
                                json: decorated,
                                verses: Vec::new(),
                            }
                        } else {
                            let mut name = name_text(&bible, id, json);
                            name.json = decorated;
                            name
                        }
                    })
                    .collect();
                Ok((entries, names))
            })()
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
            editable: dir.is_some(),
            dir: dir
                .map(|path| path.display().to_string())
                .unwrap_or_else(|| "bundled database".into()),
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
        let result = if save.id.starts_with("mobile-review:") {
            let bible = lock(&bible);
            save_mobile_review(&bible, &save.json)
        } else {
            match review_dir() {
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
            }
            .map(|summary| {
                format!(
                    "Saved. The lexicon checks clean: {} entries ({} reviewed), {} citations.",
                    summary.entries, summary.reviewed, summary.citations
                )
            })
        };
        let (success, message) = match result {
            Ok(message) => (true, message),
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
