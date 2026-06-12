use crate::signals::{
    BdbSummary, ChapterText, GetChapter, GetVerseText, GetWordInfo, HebrewOccurrence,
    SedraOccurrence, SedraSummary, VerseEntry, VerseText, WordInfo, WordOccurrence,
};

use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use haqor_core::bible::Bible;
use rinf::{DartSignal, RustSignal, debug_print};

/// One database connection is shared by all query handlers. The databases are
/// read-only, so a poisoned lock (a panic mid-query) leaves nothing
/// inconsistent and the connection can keep being used.
pub type SharedBible = Arc<Mutex<Bible>>;

fn lock(bible: &SharedBible) -> MutexGuard<'_, Bible> {
    bible.lock().unwrap_or_else(PoisonError::into_inner)
}

pub async fn get_verse_text(bible: SharedBible) {
    let receiver = GetVerseText::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let verse_ref = signal_pack.message;
        debug_print!("{:?}", verse_ref);
        match lock(&bible).get(verse_ref.book, verse_ref.chapter, verse_ref.verse) {
            Ok(text) => VerseText {
                book: verse_ref.book,
                chapter: verse_ref.chapter,
                verse: verse_ref.verse,
                text,
            }
            .send_signal_to_dart(),
            Err(e) => debug_print!("get_verse_text error: {:?}", e),
        }
    }
}

pub async fn get_chapter_text(bible: SharedBible) {
    let receiver = GetChapter::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        match lock(&bible).get_chapter(req.book, req.chapter, req.syriac) {
            Ok(raw) => {
                let verses = raw
                    .into_iter()
                    .map(|(verse, text)| VerseEntry { verse, text })
                    .collect();
                ChapterText {
                    book: req.book,
                    chapter: req.chapter,
                    syriac: req.syriac,
                    verses,
                }
                .send_signal_to_dart();
            }
            Err(e) => debug_print!("get_chapter_text error: {:?}", e),
        }
    }
}

/// Strip characters that appear in verse text but not in the words table:
/// cantillation marks (U+0591–U+05AF), meteg (U+05BD), maqaf (U+05BE),
/// paseq (U+05C0), sof pasuq (U+05C3), and upper/lower dots (U+05C4–U+05C6).
fn strip_trope(word: &str) -> String {
    word.chars()
        .filter(|&c| {
            let cp = c as u32;
            !(0x0591..=0x05AF).contains(&cp)
                && cp != 0x05BD
                && cp != 0x05BE
                && cp != 0x05C0
                && cp != 0x05C3
                && cp != 0x05C4
                && cp != 0x05C5
                && cp != 0x05C6
        })
        .collect()
}

fn to_signal_occurrences(
    occurrences: Vec<haqor_core::bible::WordOccurrence>,
) -> Vec<WordOccurrence> {
    occurrences
        .into_iter()
        .map(|o| WordOccurrence {
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
        })
        .collect()
}

fn to_signal_sedra_occurrences(
    occurrences: Vec<haqor_core::bible::SedraOccurrence>,
) -> Vec<SedraOccurrence> {
    occurrences
        .into_iter()
        .map(|o| SedraOccurrence {
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            lexeme_index: o.lexeme_index,
            words: o.words,
        })
        .collect()
}

fn to_signal_hebrew_occurrences(
    occurrences: Vec<haqor_core::bible::HebrewOccurrence>,
) -> Vec<HebrewOccurrence> {
    occurrences
        .into_iter()
        .map(|o| HebrewOccurrence {
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            form: o.form,
        })
        .collect()
}

pub async fn get_word_info(bible: SharedBible) {
    let receiver = GetWordInfo::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let bible = lock(&bible);
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let lookup = strip_trope(&req.word);

        if req.syriac {
            // NT lexicon now comes from the full SEDRA database (roots,
            // lexemes, words, english) keyed directly on the displayed Hebrew
            // word, which is the same bijective transliteration SEDRA stores.
            let words = bible.sedra_word_info(&lookup).unwrap_or_default();
            match words.first() {
                Some(first) => {
                    // Overview of the whole root tree: every lexeme sharing the
                    // root, with the looked-up word's own lexeme flagged.
                    let sedra_entries = bible
                        .sedra_root_tree(first.key_root, first.key_lexeme)
                        .unwrap_or_default()
                        .into_iter()
                        .map(|l| SedraSummary {
                            lexeme: l.lexeme,
                            meaning: l.meanings.join("; "),
                            is_current: l.is_current,
                        })
                        .collect();
                    let gloss = first.meanings.first().cloned().unwrap_or_default();
                    // Occurrences of this lexeme, and of all lexemes of the root.
                    let occurrences = to_signal_occurrences(
                        bible
                            .sedra_lexeme_occurrences(first.key_lexeme)
                            .unwrap_or_default(),
                    );
                    let root_occurrences = to_signal_occurrences(
                        bible
                            .sedra_root_occurrences(first.key_root)
                            .unwrap_or_default(),
                    );
                    let sedra_occurrences = to_signal_sedra_occurrences(
                        bible
                            .sedra_root_occurrences_detailed(first.key_root)
                            .unwrap_or_default(),
                    );
                    // OT occurrences of the same consonantal root (legacy haqor.db).
                    let ot_occurrences = to_signal_occurrences(
                        bible
                            .ot_root_occurrences(first.key_root)
                            .unwrap_or_default(),
                    );
                    WordInfo {
                        found: true,
                        word: first.word.clone(),
                        root: first.root.clone(),
                        gloss,
                        gender: first.gender.clone(),
                        number: first.number.clone(),
                        prefix: None,
                        suffix: first.suffix.clone(),
                        prepositions: None,
                        article: false,
                        vav_con: false,
                        bdb_entries: Vec::new(),
                        sedra_entries,
                        person: first.person.clone(),
                        state: first.state.clone(),
                        tense: first.tense.clone(),
                        form: first.form.clone(),
                        occurrences,
                        root_occurrences,
                        sedra_occurrences,
                        ot_occurrences,
                        hebrew_occurrences: Vec::new(),
                    }
                    .send_signal_to_dart();
                }
                None => {
                    debug_print!("get_word_info: no SEDRA match for {:?}", lookup);
                    WordInfo {
                        found: false,
                        word: req.word,
                        root: String::new(),
                        gloss: String::new(),
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        prepositions: None,
                        article: false,
                        vav_con: false,
                        bdb_entries: Vec::new(),
                        sedra_entries: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        occurrences: Vec::new(),
                        root_occurrences: Vec::new(),
                        sedra_occurrences: Vec::new(),
                        ot_occurrences: Vec::new(),
                        hebrew_occurrences: Vec::new(),
                    }
                    .send_signal_to_dart();
                }
            }
        } else {
            // OT lexicon now comes from the Rust reverse-parse engine
            // (`hebrew.db`) for morphology + occurrences, bridged to the
            // OpenScriptures BDB lexicon (`lexicon.db`) by consonantal root for
            // glossed root trees. `hebrew_word_info` normalises the lookup
            // itself, so the raw word is passed through.
            match bible.hebrew_word_info(&req.word) {
                Some(info) => {
                    let bdb_entries = bible
                        .hebrew_bdb_by_root(&info.root)
                        .unwrap_or_default()
                        .into_iter()
                        .map(|e| BdbSummary {
                            headword: e.headword,
                            gloss: e.gloss,
                            content_json: e.content_json,
                        })
                        .collect();
                    let occurrences = to_signal_occurrences(
                        bible
                            .hebrew_surface_occurrences(&req.word)
                            .unwrap_or_default(),
                    );
                    let root_occurrences = to_signal_occurrences(
                        bible
                            .hebrew_root_occurrences(&info.root)
                            .unwrap_or_default(),
                    );
                    let hebrew_occurrences = to_signal_hebrew_occurrences(
                        bible
                            .hebrew_root_occurrences_detailed(&info.root)
                            .unwrap_or_default(),
                    );
                    WordInfo {
                        found: true,
                        word: info.word,
                        root: info.root,
                        gloss: info.gloss,
                        gender: info.gender,
                        number: info.number,
                        prefix: info.prefix,
                        suffix: None,
                        prepositions: None,
                        article: false,
                        vav_con: info.vav_con,
                        bdb_entries,
                        sedra_entries: Vec::new(),
                        person: info.person,
                        state: info.state,
                        tense: info.tense,
                        form: info.form,
                        occurrences,
                        root_occurrences,
                        sedra_occurrences: Vec::new(),
                        ot_occurrences: Vec::new(),
                        hebrew_occurrences,
                    }
                    .send_signal_to_dart();
                }
                None => {
                    debug_print!("get_word_info: no OT parse for {:?}", lookup);
                    WordInfo {
                        found: false,
                        word: req.word,
                        root: String::new(),
                        gloss: String::new(),
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        prepositions: None,
                        article: false,
                        vav_con: false,
                        bdb_entries: Vec::new(),
                        sedra_entries: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        occurrences: Vec::new(),
                        root_occurrences: Vec::new(),
                        sedra_occurrences: Vec::new(),
                        ot_occurrences: Vec::new(),
                        hebrew_occurrences: Vec::new(),
                    }
                    .send_signal_to_dart();
                }
            }
        }
    }
}
