use crate::signals::{BdbSummary, ChapterText, GetChapter, GetVerseText, GetWordInfo, SedraSummary, VerseEntry, VerseText, WordInfo, WordOccurrence};

use rinf::{DartSignal, RustSignal, debug_print};
use haqor_core::bible::Bible;

pub async fn get_verse_text() {
    let bible: Bible = Bible::default();

    let receiver = GetVerseText::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let verse_ref = signal_pack.message;
        debug_print!("{:?}", verse_ref);
        match bible.get(verse_ref.book, verse_ref.chapter, verse_ref.verse) {
            Ok(text) => VerseText { book: verse_ref.book, chapter: verse_ref.chapter, verse: verse_ref.verse, text }.send_signal_to_dart(),
            Err(e) => debug_print!("get_verse_text error: {:?}", e),
        }
    }
}

pub async fn get_chapter_text() {
    let bible: Bible = Bible::default();

    let receiver = GetChapter::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        match bible.get_chapter(req.book, req.chapter, req.syriac) {
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

fn to_signal_occurrences(occurrences: Vec<haqor_core::bible::WordOccurrence>) -> Vec<WordOccurrence> {
    occurrences
        .into_iter()
        .map(|o| WordOccurrence { book: o.book, chapter: o.chapter, verse: o.verse })
        .collect()
}

pub async fn get_word_info() {
    let bible: Bible = Bible::default();

    let receiver = GetWordInfo::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
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
                    // One Sedra entry per distinct lexeme, meanings joined.
                    let mut sedra_entries: Vec<SedraSummary> = Vec::new();
                    for w in &words {
                        if sedra_entries.iter().any(|e| e.lexeme == w.lexeme) {
                            continue;
                        }
                        sedra_entries.push(SedraSummary {
                            lexeme: w.lexeme.clone(),
                            meaning: w.meanings.join("; "),
                        });
                    }
                    let gloss = first.meanings.first().cloned().unwrap_or_default();
                    let occurrences = to_signal_occurrences(
                        bible.word_occurrences(&lookup).unwrap_or_default(),
                    );
                    let root_occurrences = to_signal_occurrences(
                        bible.word_occurrences_root(&first.root).unwrap_or_default(),
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
                    }
                    .send_signal_to_dart();
                }
            }
        } else {
            match bible.get_word_morphology(&lookup) {
                Ok(morph) => {
                    let bdb = bible.lex_lookup(&req.word).unwrap_or_default();
                    let gloss = bdb.first().map(|e| e.gloss.clone()).unwrap_or_default();
                    let bdb_entries = bdb
                        .into_iter()
                        .map(|e| BdbSummary {
                            headword: e.headword,
                            gloss: e.gloss,
                            content_json: e.content_json,
                        })
                        .collect();
                    let occurrences = to_signal_occurrences(
                        bible.word_occurrences(&lookup).unwrap_or_default(),
                    );
                    let root_occurrences = to_signal_occurrences(
                        bible.word_occurrences_root(&morph.root).unwrap_or_default(),
                    );
                    WordInfo {
                        found: true,
                        word: morph.word,
                        root: morph.root,
                        gloss,
                        gender: morph.gender,
                        number: morph.number,
                        prefix: morph.prefix,
                        suffix: morph.suffix,
                        prepositions: morph.prepositions,
                        article: morph.article,
                        vav_con: morph.vav_con,
                        bdb_entries,
                        sedra_entries: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        occurrences,
                        root_occurrences,
                    }
                    .send_signal_to_dart();
                }
                Err(e) => {
                    debug_print!("get_word_info error: {:?}", e);
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
                    }
                    .send_signal_to_dart();
                }
            }
        }
    }
}
