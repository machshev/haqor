use crate::signals::{
    BdbSummary, CalibrationProbe, ChapterText, FinishCalibration, GetCalibrationProbe, GetChapter,
    GetNextStudyItem, GetOnboardingStatus, GetSeenConcepts, GetTutorSettings, GetTutorStats,
    GetVerseText, GetVocab, GetWordInfo, GetWordOccurrences, GlyphCard, GrammarCard,
    HebrewOccurrence, OnboardingStatus, ResetTutor, SedraOccurrence, SedraSummary, SeenConcept,
    SeenConcepts, SetAlphabetKnown, SetTutorSettings, StudyItem, SubmitReview, SuffixCard,
    TutorProgress,
    TutorSettings, TutorStats, VerseCard, VerseEntry, VerseRef, VerseText, VocabEntry, VocabList,
    WordCard, WordInfo, WordOccurrence, WordOccurrences,
};

use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{SystemTime, UNIX_EPOCH};

use haqor_core::bible::Bible;
use haqor_core::tutor::{self, Grade, Track};
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
                translit: haqor_core::romanize::romanize(&text),
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

pub async fn get_vocab(bible: SharedBible) {
    let receiver = GetVocab::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        match lock(&bible).vocab(req.limit, req.offset) {
            Ok(entries) => VocabList {
                offset: req.offset,
                entries: entries
                    .into_iter()
                    .map(|e| VocabEntry {
                        surface: e.surface,
                        occurrences: e.occurrences,
                        lexical_class: e.lexical_class,
                        root: e.root,
                        gloss: e.gloss,
                        morph: e.morph,
                    })
                    .collect(),
            }
            .send_signal_to_dart(),
            Err(e) => debug_print!("get_vocab error: {:?}", e),
        }
    }
}

pub async fn get_word_info(bible: SharedBible) {
    let receiver = GetWordInfo::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let bible = lock(&bible);
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let lookup = strip_trope(&req.word);

        // A Lexicon cross-reference hands back the target's BDB entry id rather
        // than a surface word (root targets like בטח are never surface forms),
        // so resolve it straight to the target entry's root tree.
        if let Some(id) = req.bdb_id.as_deref().filter(|s| !s.is_empty()) {
            match bible.hebrew_bdb_by_id(id) {
                Ok(Some(entry)) => {
                    let mut bdb_entries: Vec<BdbSummary> = bible
                        .hebrew_bdb_by_root(&entry.root)
                        .unwrap_or_default()
                        .into_iter()
                        .map(|e| BdbSummary {
                            pos_category: e.pos_category().to_string(),
                            headword: e.headword,
                            gloss: e.gloss,
                            content_json: e.content_json,
                        })
                        .collect();
                    // A rootless entry (a particle) isn't reachable by root;
                    // show the target lexeme on its own.
                    if bdb_entries.is_empty() {
                        bdb_entries.push(BdbSummary {
                            pos_category: entry.pos_category().to_string(),
                            headword: entry.headword.clone(),
                            gloss: entry.gloss.clone(),
                            content_json: entry.content_json.clone(),
                        });
                    }
                    WordInfo {
                        found: true,
                        word: entry.headword,
                        root: entry.root,
                        gloss: entry.gloss,
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        prepositions: None,
                        article: false,
                        vav_con: false,
                        bdb_entries,
                        sedra_entries: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                    }
                    .send_signal_to_dart();
                }
                _ => {
                    debug_print!("get_word_info: no BDB entry for id {:?}", id);
                    WordInfo {
                        found: false,
                        word: req.word.clone(),
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
                    }
                    .send_signal_to_dart();
                }
            }
            continue;
        }

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
                    // Function words / particles bridge through the lexicon with
                    // no triliteral root, so their definition can't be fetched by
                    // root; look the lexeme up by its surface form instead.
                    let bdb_entries = if info.root.is_empty() {
                        bible.hebrew_bdb_for_surface(
                            &info.word,
                            info.prefix.as_deref().unwrap_or(""),
                        )
                    } else {
                        bible.hebrew_bdb_by_root(&info.root)
                    }
                    .unwrap_or_default()
                    .into_iter()
                    .map(|e| BdbSummary {
                        pos_category: e.pos_category().to_string(),
                        headword: e.headword,
                        gloss: e.gloss,
                        content_json: e.content_json,
                    })
                    .collect();
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
                    }
                    .send_signal_to_dart();
                }
            }
        }
    }
}

/// Lazy occurrence lookup, split out of [`get_word_info`] so the Occurrences tab
/// can defer the full-text root scans until it is actually opened. Re-derives
/// the lexeme/root keys from the (cheap) lexicon lookup, then runs the scans.
pub async fn get_word_occurrences(bible: SharedBible) {
    let receiver = GetWordOccurrences::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let bible = lock(&bible);
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let lookup = strip_trope(&req.word);

        if req.syriac {
            let words = bible.sedra_word_info(&lookup).unwrap_or_default();
            match words.first() {
                Some(first) => WordOccurrences {
                    found: true,
                    occurrences: to_signal_occurrences(
                        bible
                            .sedra_lexeme_occurrences(first.key_lexeme)
                            .unwrap_or_default(),
                    ),
                    root_occurrences: to_signal_occurrences(
                        bible
                            .sedra_root_occurrences(first.key_root)
                            .unwrap_or_default(),
                    ),
                    sedra_occurrences: to_signal_sedra_occurrences(
                        bible
                            .sedra_root_occurrences_detailed(first.key_root)
                            .unwrap_or_default(),
                    ),
                    ot_occurrences: to_signal_occurrences(
                        bible
                            .ot_root_occurrences(first.key_root)
                            .unwrap_or_default(),
                    ),
                    hebrew_occurrences: Vec::new(),
                }
                .send_signal_to_dart(),
                None => empty_word_occurrences().send_signal_to_dart(),
            }
        } else {
            match bible.hebrew_word_info(&req.word) {
                Some(info) => WordOccurrences {
                    found: true,
                    occurrences: to_signal_occurrences(
                        bible
                            .hebrew_surface_occurrences(&req.word)
                            .unwrap_or_default(),
                    ),
                    root_occurrences: to_signal_occurrences(
                        bible
                            .hebrew_root_occurrences(&info.root)
                            .unwrap_or_default(),
                    ),
                    sedra_occurrences: Vec::new(),
                    ot_occurrences: Vec::new(),
                    hebrew_occurrences: to_signal_hebrew_occurrences(
                        bible
                            .hebrew_root_occurrences_detailed(&info.root)
                            .unwrap_or_default(),
                    ),
                }
                .send_signal_to_dart(),
                None => empty_word_occurrences().send_signal_to_dart(),
            }
        }
    }
}

fn empty_word_occurrences() -> WordOccurrences {
    WordOccurrences {
        found: false,
        occurrences: Vec::new(),
        root_occurrences: Vec::new(),
        sedra_occurrences: Vec::new(),
        ot_occurrences: Vec::new(),
        hebrew_occurrences: Vec::new(),
    }
}

// --- Spaced-repetition reading tutor -------------------------------------

/// Wall-clock now in epoch seconds (the SM-2 scheduler's time base). Tutor
/// state is day-grained, so second precision is ample.
fn now_epoch() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn to_signal_glyph(g: tutor::GlyphCard) -> GlyphCard {
    GlyphCard {
        glyph: g.glyph,
        is_consonant: g.is_consonant,
        host: g.host,
        voiced: g.voiced,
        distractors: g.distractors,
        voiced_distractors: g.voiced_distractors,
    }
}

fn to_signal_word(w: tutor::WordCard) -> WordCard {
    WordCard {
        surface_id: w.surface_id,
        surface: w.surface,
        occurrences: w.occurrences,
        translit: w.translit,
        gloss: w.gloss,
        root_gloss: w.root_gloss,
        note: w.note,
        root: w.root,
        morph: w.morph,
        aspect: "mean".to_string(),
        distractors: w.distractors,
    }
}

/// Map a core form-drill [`tutor::WordCard`] to the signal, tagged `"form"`.
/// The `gloss` field carries the inflected answer and `distractors` the
/// contrasting inflections for the "which form?" quiz.
fn to_signal_form(w: tutor::WordCard) -> WordCard {
    WordCard {
        aspect: "form".to_string(),
        ..to_signal_word(w)
    }
}

fn to_signal_suffix(s: tutor::SuffixCard) -> SuffixCard {
    SuffixCard {
        key: s.key,
        meaning: s.meaning,
        surface: s.surface,
        translit: s.translit,
        stem: s.stem,
        suffix: s.suffix,
        gloss: s.gloss,
        distractors: s.distractors,
    }
}

/// Map a core [`tutor::StudyItem`] to its tagged signal form, attaching the
/// current progress counters so the UI can render a status header on any card.
fn to_signal_study_item(bible: &Bible, item: tutor::StudyItem) -> StudyItem {
    let p = bible.tutor_progress().unwrap_or_default();
    let progress = TutorProgress {
        letters_known: p.letters_known,
        letters_total: p.letters_total,
        vowels_known: p.vowels_known,
        vowels_total: p.vowels_total,
        grammar_known: p.grammar_known,
        grammar_total: p.grammar_total,
        words_known: p.words_known,
        verses_grammar_unlocked: p.verses_grammar_unlocked,
        verses_readable: p.verses_readable,
        total_verses: p.total_verses,
    };
    let mut out = StudyItem {
        kind: String::new(),
        glyph: None,
        word: None,
        suffix: None,
        grammar: None,
        intro: None,
        verse: None,
        progress,
    };
    match item {
        tutor::StudyItem::NewGlyph(g) => {
            out.kind = "new_glyph".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::ReviewGlyph(g) => {
            out.kind = "review_glyph".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::NewWord(w) => {
            out.kind = "new_word".into();
            out.word = Some(to_signal_word(w));
        }
        tutor::StudyItem::ReviewWord(w) => {
            out.kind = "review_word".into();
            out.word = Some(to_signal_word(w));
        }
        tutor::StudyItem::NewFormDrill(w) => {
            out.kind = "new_form".into();
            out.word = Some(to_signal_form(w));
        }
        tutor::StudyItem::ReviewFormDrill(w) => {
            out.kind = "review_form".into();
            out.word = Some(to_signal_form(w));
        }
        tutor::StudyItem::NewSuffixDrill(s) => {
            out.kind = "new_suffix".into();
            out.suffix = Some(to_signal_suffix(s));
        }
        tutor::StudyItem::ReviewSuffixDrill(s) => {
            out.kind = "review_suffix".into();
            out.suffix = Some(to_signal_suffix(s));
        }
        tutor::StudyItem::ExplainMark(g) => {
            out.kind = "explain_mark".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::ExplainFinalForms(g) => {
            out.kind = "explain_final_forms".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::ExplainIntro(key) => {
            out.kind = "explain_intro".into();
            out.intro = Some(key);
        }
        tutor::StudyItem::ExplainGrammar(c) => {
            out.kind = "explain_grammar".into();
            out.grammar = Some(GrammarCard {
                concept: c.concept,
                title: c.title,
                explanation: c.explanation,
                formula: c.formula,
                examples: c.examples,
                example: to_signal_word(c.example),
            });
        }
        tutor::StudyItem::ReadVerse(v) => {
            out.kind = "read_verse".into();
            out.verse = Some(VerseCard {
                book: v.book,
                chapter: v.chapter,
                verse: v.verse,
                examples: v
                    .examples
                    .into_iter()
                    .map(|(book, chapter, verse)| VerseRef {
                        book,
                        chapter,
                        verse,
                    })
                    .collect(),
                words: v.words,
                names: v.names,
            });
        }
        tutor::StudyItem::Done => out.kind = "done".into(),
    }
    out
}

pub async fn get_next_study_item(bible: SharedBible) {
    let receiver = GetNextStudyItem::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.next_study_item(now_epoch()) {
            Ok(item) => to_signal_study_item(&bible, item).send_signal_to_dart(),
            Err(e) => debug_print!("get_next_study_item error: {:?}", e),
        }
    }
}

pub async fn submit_review(bible: SharedBible) {
    let receiver = SubmitReview::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let track = match req.track.as_str() {
            "glyph" => Track::Glyph,
            "form" => Track::Form,
            "suffix" => Track::Suffix,
            _ => Track::Word,
        };
        let correct = match req.correct {
            1 => Some(false),
            2 => Some(true),
            _ => None,
        };
        let grade = Grade::from_confidence(req.confidence, correct);
        let bible = lock(&bible);
        match bible.submit_review(track, &req.key, grade, now_epoch()) {
            Ok(item) => to_signal_study_item(&bible, item).send_signal_to_dart(),
            Err(e) => debug_print!("submit_review error: {:?}", e),
        }
    }
}

pub async fn reset_tutor(bible: SharedBible) {
    let receiver = ResetTutor::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.reset_tutor() {
            // Reset always empties glyph_srs/word_srs, so onboarding is always
            // needed again — push a fresh status so the app routes back through
            // it (TutorEntryPage is already subscribed) instead of resuming the
            // study flow with a new-but-still-post-onboarding card.
            Ok(()) => {
                let tier_count = bible.calibration_tier_count().unwrap_or(0);
                OnboardingStatus {
                    needed: true,
                    tier_count,
                }
                .send_signal_to_dart();
            }
            Err(e) => debug_print!("reset_tutor error: {:?}", e),
        }
    }
}

pub async fn get_seen_concepts(bible: SharedBible) {
    let receiver = GetSeenConcepts::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.seen_concepts() {
            Ok(cards) => SeenConcepts {
                cards: cards
                    .into_iter()
                    .map(|c| SeenConcept {
                        kind: c.kind,
                        key: c.key,
                        title: c.title,
                        explanation: c.explanation,
                        formula: c.formula,
                        examples: c.examples,
                    })
                    .collect(),
            }
            .send_signal_to_dart(),
            Err(e) => debug_print!("get_seen_concepts error: {:?}", e),
        }
    }
}

pub async fn get_tutor_stats(bible: SharedBible) {
    let receiver = GetTutorStats::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.tutor_stats(now_epoch()) {
            Ok(s) => TutorStats {
                letters_seen: s.letters_seen,
                letters_learning: s.letters_learning,
                letters_mature: s.letters_mature,
                vowels_seen: s.vowels_seen,
                vowels_learning: s.vowels_learning,
                vowels_mature: s.vowels_mature,
                words_seen: s.words_seen,
                words_learning: s.words_learning,
                words_mature: s.words_mature,
                grammar_seen: s.grammar_seen,
                grammar_total: s.grammar_total,
                glyphs_due: s.glyphs_due,
                words_due: s.words_due,
                reviews_today: s.reviews_today,
                reviews_total: s.reviews_total,
                streak_days: s.streak_days,
                accuracy_pct: s.accuracy_pct,
                verses_readable: s.verses_readable,
                total_verses: s.total_verses,
            }
            .send_signal_to_dart(),
            Err(e) => debug_print!("get_tutor_stats error: {:?}", e),
        }
    }
}

pub async fn get_tutor_settings(bible: SharedBible) {
    let receiver = GetTutorSettings::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.tutor_settings() {
            Ok(s) => to_signal_settings(s).send_signal_to_dart(),
            Err(e) => debug_print!("get_tutor_settings error: {:?}", e),
        }
    }
}

pub async fn set_tutor_settings(bible: SharedBible) {
    let receiver = SetTutorSettings::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        let bible = lock(&bible);
        let s = tutor::TutorSettings {
            letters_per_batch: req.letters_per_batch,
            words_per_batch: req.words_per_batch,
            grammar_gating: req.grammar_gating,
            vocab_priority: req.vocab_priority,
            grammar_priority: req.grammar_priority,
            verse_priority: req.verse_priority,
            letters_ratio: req.letters_ratio,
        };
        match bible
            .set_tutor_settings(&s)
            .and_then(|()| bible.tutor_settings())
        {
            Ok(stored) => to_signal_settings(stored).send_signal_to_dart(),
            Err(e) => debug_print!("set_tutor_settings error: {:?}", e),
        }
    }
}

fn to_signal_settings(s: tutor::TutorSettings) -> TutorSettings {
    TutorSettings {
        letters_per_batch: s.letters_per_batch,
        words_per_batch: s.words_per_batch,
        grammar_gating: s.grammar_gating,
        vocab_priority: s.vocab_priority,
        grammar_priority: s.grammar_priority,
        verse_priority: s.verse_priority,
        letters_ratio: s.letters_ratio,
    }
}

pub async fn get_onboarding_status(bible: SharedBible) {
    let receiver = GetOnboardingStatus::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        let needed = bible.needs_onboarding().unwrap_or_else(|e| {
            debug_print!("get_onboarding_status error: {:?}", e);
            false
        });
        let tier_count = bible.calibration_tier_count().unwrap_or(0);
        OnboardingStatus { needed, tier_count }.send_signal_to_dart();
    }
}

pub async fn set_alphabet_known(bible: SharedBible) {
    let receiver = SetAlphabetKnown::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        if req.known {
            if let Err(e) = lock(&bible).seed_known_alphabet(now_epoch()) {
                debug_print!("set_alphabet_known error: {:?}", e);
            }
        }
    }
}

pub async fn get_calibration_probe(bible: SharedBible) {
    let receiver = GetCalibrationProbe::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        match lock(&bible).calibration_probe(req.tier) {
            Ok(Some(p)) => CalibrationProbe {
                found: true,
                book: p.book,
                chapter: p.chapter,
                verse: p.verse,
                text: p.text,
                tier: p.tier,
                min_occurrences: p.min_occurrences,
            }
            .send_signal_to_dart(),
            Ok(None) => CalibrationProbe {
                found: false,
                book: 0,
                chapter: 0,
                verse: 0,
                text: String::new(),
                tier: req.tier,
                min_occurrences: 0,
            }
            .send_signal_to_dart(),
            Err(e) => debug_print!("get_calibration_probe error: {:?}", e),
        }
    }
}

pub async fn finish_calibration(bible: SharedBible) {
    let receiver = FinishCalibration::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        if let Err(e) = lock(&bible).seed_known_vocab(req.min_occurrences, now_epoch()) {
            debug_print!("finish_calibration error: {:?}", e);
        }
    }
}
