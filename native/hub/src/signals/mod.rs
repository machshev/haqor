use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

/// Directory holding the database files (bible.db, sedra.db, hebrew.db,
/// lexicon.db). Sent once from Dart at startup, after the bundled
/// assets have been copied into app-local storage; no queries are answered
/// until it arrives.
#[derive(Debug, Deserialize, DartSignal)]
pub struct SetDataDir {
    pub path: String,
}

#[derive(Debug, Deserialize, DartSignal)]
pub struct GetVerseText {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct VerseText {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
    pub text: String,
}

#[derive(Debug, Deserialize, DartSignal)]
pub struct GetChapter {
    pub book: u8,
    pub chapter: u8,
    pub syriac: bool,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct VerseEntry {
    pub verse: u8,
    pub text: String,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct ChapterText {
    pub book: u8,
    pub chapter: u8,
    pub syriac: bool,
    pub verses: Vec<VerseEntry>,
}

#[derive(Debug, Deserialize, DartSignal)]
pub struct GetWordInfo {
    pub word: String,
    pub syriac: bool,
    /// When set, look the entry up by BDB entry id instead of by `word` —
    /// used to follow a Lexicon cross-reference to its target's root tree.
    /// `word` then carries only the target headword, for the sheet title.
    pub bdb_id: Option<String>,
}

/// Lazy companion to [`GetWordInfo`]: requests only the occurrence lists, which
/// require full-text root scans and so are deferred until the Occurrences tab is
/// first opened rather than computed up-front with the lexicon data.
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetWordOccurrences {
    pub word: String,
    pub syriac: bool,
}

/// Request a page of the frequency-ordered learner vocabulary (tutor mode):
/// distinct OT surface forms in descending occurrence order.
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetVocab {
    pub limit: u32,
    pub offset: u32,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct VocabEntry {
    pub surface: String,
    pub occurrences: u32,
    /// Pre-filter class ("function" or "proper") for surfaces that never
    /// reached the parse engine; `None` for ordinary content words.
    pub lexical_class: Option<String>,
    pub root: String,
    pub gloss: String,
    pub morph: String,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct VocabList {
    pub offset: u32,
    pub entries: Vec<VocabEntry>,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct BdbSummary {
    pub headword: String,
    pub gloss: String,
    pub content_json: String,
    /// Coarse part-of-speech bucket from the BDB `pos` marker — one of
    /// `verb`, `noun`, `adjective`, `adverb`, `proper`, or `other`. The Lexicon
    /// tab groups a root's lexemes under a heading per class (proper names, in
    /// particular, crowd out the root's actual semantic range).
    pub pos_category: String,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct SedraSummary {
    pub lexeme: String,
    pub meaning: String,
    /// True for the lexeme of the word that was looked up (vs. sibling lexemes
    /// of the same root shown for context).
    pub is_current: bool,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct WordOccurrence {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
}

/// An NT occurrence tagged with which lexeme of the root tree it belongs to, so
/// the UI can filter occurrences by lexeme. `lexeme_index` aligns with the order
/// of `sedra_entries`. `words` holds the distinct word forms in that verse.
#[derive(Debug, Serialize, SignalPiece)]
pub struct SedraOccurrence {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
    pub lexeme_index: u32,
    pub words: Vec<String>,
}

/// An OT occurrence tagged with the surface form found in that verse, so the UI
/// can filter a root's occurrences by inflected form (the OT analogue of
/// `SedraOccurrence`'s lexeme filter). The form inventory is derived on the Dart
/// side from the distinct `form` values.
#[derive(Debug, Serialize, SignalPiece)]
pub struct HebrewOccurrence {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
    pub form: String,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct WordInfo {
    pub found: bool,
    pub word: String,
    pub root: String,
    pub gloss: String,
    pub gender: Option<String>,
    pub number: Option<String>,
    pub prefix: Option<String>,
    pub suffix: Option<String>,
    pub prepositions: Option<String>,
    pub article: bool,
    pub vav_con: bool,
    pub bdb_entries: Vec<BdbSummary>,
    pub sedra_entries: Vec<SedraSummary>,
    pub person: Option<String>,
    pub state: Option<String>,
    pub tense: Option<String>,
    pub form: Option<String>,
}

/// Occurrence lists for a looked-up word, fetched lazily via
/// [`GetWordOccurrences`] when the Occurrences tab is opened. The split keeps
/// the initial [`WordInfo`] response (lexicon + morphology) fast, since these
/// lists come from full-text scans of the root across the corpus.
#[derive(Debug, Serialize, RustSignal)]
pub struct WordOccurrences {
    pub found: bool,
    pub occurrences: Vec<WordOccurrence>,
    pub root_occurrences: Vec<WordOccurrence>,
    pub sedra_occurrences: Vec<SedraOccurrence>,
    /// OT (Hebrew Bible) occurrences of the same consonantal root, for the NT
    /// word info "OT" filter. Empty for roots without a Hebrew cognate.
    pub ot_occurrences: Vec<WordOccurrence>,
    /// OT root occurrences tagged with their surface form, for the OT word
    /// info per-form filter. Empty for NT lookups.
    pub hebrew_occurrences: Vec<HebrewOccurrence>,
}

// ---------------------------------------------------------------------------
// Spaced-repetition reading tutor.
//
// The app drives a single never-ending study flow. It asks for the next card
// with `GetNextStudyItem`, then answers each card with `SubmitReview` — whose
// `StudyItem` response is the *next* card (one round-trip per card). A
// `read_verse` or `explain_mark` card carries no grade, so the app advances
// past it with another `GetNextStudyItem`.
// ---------------------------------------------------------------------------

/// Request the next study card (e.g. on launch, or after a gradeless read).
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetNextStudyItem {}

/// Answer the current card; the `StudyItem` response is the next card. The
/// learner's self-assessed `confidence` (set on the grading slider) maps to an
/// SM-2 grade; a fresh-glyph "intro" is just a mid `confidence` with no quiz.
#[derive(Debug, Deserialize, DartSignal)]
pub struct SubmitReview {
    /// `"glyph"` (a consonant, vowel/syllable, or mark) or `"word"` (meaning).
    pub track: String,
    /// The glyph character (folded) or the word surface form.
    pub key: String,
    /// Self-assessed confidence, 0..=100 (slider). <25 Again, <55 Hard,
    /// <85 Good, else Easy.
    pub confidence: u8,
    /// Multiple-choice outcome: 0 = not a quiz (self-graded), 1 = wrong pick
    /// (always lapses), 2 = correct pick (graded on confidence).
    pub correct: u8,
}

/// Wipe all tutor progress (a dev/settings action).
#[derive(Debug, Deserialize, DartSignal)]
pub struct ResetTutor {}

/// Request the richer SRS statistics for the stats view (on demand, not per
/// card). The reply is a single [`TutorStats`].
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetTutorStats {}

/// Richer spaced-repetition statistics for the stats view. A card is *learning*
/// while in the short in-session steps and *mature* once it graduates to
/// day-scale spacing; *seen* is every introduced card.
#[derive(Debug, Serialize, RustSignal)]
pub struct TutorStats {
    pub glyphs_seen: i64,
    pub glyphs_learning: i64,
    pub glyphs_mature: i64,
    pub words_seen: i64,
    pub words_learning: i64,
    pub words_mature: i64,
    pub glyphs_due: i64,
    pub words_due: i64,
    pub reviews_today: i64,
    pub reviews_total: i64,
    pub streak_days: i64,
    /// Share of answers recalled (not "Again"), 0..=100.
    pub accuracy_pct: i64,
    pub verses_readable: i64,
    pub total_verses: i64,
}

/// A teachable glyph (consonant — final forms folded — or niqqud point). The
/// teaching content is held on the Dart side keyed by `glyph`.
#[derive(Debug, Serialize, SignalPiece)]
pub struct GlyphCard {
    pub glyph: String,
    pub is_consonant: bool,
    /// For a vowel, an already-learnt consonant to display it on; else null.
    pub host: Option<String>,
    /// Same-kind glyphs offered as wrong answers in a multiple-choice quiz;
    /// empty when too few peers exist (the app self-grades instead).
    pub distractors: Vec<String>,
}

/// A word to learn or review. Words teach only meaning (vocalisation is learnt
/// from the glyph/syllable drill); `aspect` is retained for the signal shape and
/// is always `"mean"`.
#[derive(Debug, Serialize, SignalPiece)]
pub struct WordCard {
    pub surface_id: i64,
    pub surface: String,
    pub occurrences: i64,
    pub gloss: String,
    pub root: String,
    pub morph: String,
    pub aspect: String,
    /// Plausible wrong glosses for a multiple-choice meaning quiz; filled only
    /// for `"mean"` cards, empty when too few exist (the app self-grades).
    pub distractors: Vec<String>,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct VerseRef {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
}

/// A fully-known verse offered to read, with other now-readable passages.
#[derive(Debug, Serialize, SignalPiece)]
pub struct VerseCard {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
    pub examples: Vec<VerseRef>,
    /// The verse's words in reading order, as `SubmitReview` `"word"` keys —
    /// lets the app offer them for the learner to flag ones they misread.
    pub words: Vec<String>,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct TutorProgress {
    pub glyphs_known: i64,
    pub words_known: i64,
    pub verses_readable: i64,
    pub total_verses: i64,
}

/// The next thing for the learner to do. `kind` tags which payload is set:
/// `"new_glyph"`/`"review_glyph"`/`"explain_mark"` → `glyph`;
/// `"new_word"`/`"review_word"` → `word`; `"read_verse"` → `verse`;
/// `"done"` → none. An `"explain_mark"` card (a reading mark: sof pasuq,
/// maqaf) carries no grade, like `"read_verse"` — the app acknowledges it
/// with another `GetNextStudyItem`, never `SubmitReview`.
#[derive(Debug, Serialize, RustSignal)]
pub struct StudyItem {
    pub kind: String,
    pub glyph: Option<GlyphCard>,
    pub word: Option<WordCard>,
    pub verse: Option<VerseCard>,
    pub progress: TutorProgress,
}

// ---------------------------------------------------------------------------
// One-time onboarding calibration.
//
// Offered only while `progress.db` is still empty, so a learner who already
// knows the alphabet and/or some vocabulary doesn't have to grind through the
// ordinary cold-start curriculum to reach anything actually new to them. The
// app asks `GetOnboardingStatus` once (e.g. on opening the tutor); if
// `needed`, it self-reports the alphabet via `SetAlphabetKnown`, then runs a
// binary search over word-frequency rank using `GetCalibrationProbe` (each
// probe is a real verse to judge readability of) and finishes with
// `FinishCalibration` once converged.
// ---------------------------------------------------------------------------

/// Ask whether onboarding calibration should be offered.
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetOnboardingStatus {}

#[derive(Debug, Serialize, RustSignal)]
pub struct OnboardingStatus {
    pub needed: bool,
    /// Distinct non-Aramaic vocabulary size — the domain for the
    /// calibration binary search over word-frequency rank.
    pub vocab_count: u32,
}

/// The learner's self-report on the "do you already know the alphabet?"
/// onboarding question. When true, every consonant/vowel point the curriculum
/// would ever teach is marked already graduated.
#[derive(Debug, Deserialize, DartSignal)]
pub struct SetAlphabetKnown {
    pub known: bool,
}

/// Ask for a representative verse at a given frequency-rank cutoff, for the
/// vocabulary-calibration binary search: the hardest verse still readable if
/// the learner knows the `rank` most common words (0 = the single most
/// common word).
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetCalibrationProbe {
    pub rank: u32,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct CalibrationProbe {
    pub found: bool,
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
    pub text: String,
    pub rank: u32,
}

/// Finish onboarding calibration: mark the `rank_cutoff` most common words as
/// already known (graduated), so the curriculum starts introducing new
/// vocabulary from that frequency boundary instead of from scratch.
#[derive(Debug, Deserialize, DartSignal)]
pub struct FinishCalibration {
    pub rank_cutoff: u32,
}
