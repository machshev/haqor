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

/// Ask the native layer to merge this device's progress with the trusted LAN
/// sync server. The token is deliberately never persisted by Rust; Dart keeps
/// it in the platform preference store and sends it only for this request.
#[derive(Debug, Deserialize, DartSignal)]
pub struct SyncProgress {
    pub server_url: String,
    pub token: String,
}

/// Save a learner-facing gloss correction from tutor admin mode. It is stored
/// in the writable progress database and therefore travels with LAN sync.
#[derive(Debug, Deserialize, DartSignal)]
pub struct SaveTutorGloss {
    pub surface: String,
    pub gloss: String,
    pub note: String,
}

/// Result of a requested background sync. The app normally keeps this quiet
/// after automatic runs, but settings can surface the message on demand.
#[derive(Debug, Serialize, RustSignal)]
pub struct ProgressSyncStatus {
    pub success: bool,
    pub message: String,
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
    /// The verse's voiced reading (learner romanization, cantillation ignored).
    pub translit: String,
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
    pub glosses: Vec<String>,
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
// `read_verse`, `explain_mark` or `explain_final_forms` card carries no
// grade, so the app advances past it with another `GetNextStudyItem`.
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
    pub letters_seen: i64,
    pub letters_learning: i64,
    pub letters_mature: i64,
    pub vowels_seen: i64,
    pub vowels_learning: i64,
    pub vowels_mature: i64,
    pub words_seen: i64,
    pub words_learning: i64,
    pub words_mature: i64,
    pub grammar_seen: i64,
    pub grammar_total: i64,
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

/// Request the current curriculum-pacing settings (on demand, e.g. when the
/// settings sheet opens). The reply is a single [`TutorSettings`].
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetTutorSettings {}

/// Update the curriculum-pacing settings; the reply is the stored
/// [`TutorSettings`] (so the UI reflects any clamping).
#[derive(Debug, Deserialize, DartSignal)]
pub struct SetTutorSettings {
    pub letters_per_batch: u8,
    pub words_per_batch: u8,
    pub grammar_gating: bool,
    pub vocab_priority: u8,
    pub grammar_priority: u8,
    pub verse_priority: u8,
    /// Letters↔words balance (0..=100): the share of new-material introductions
    /// spent on new letters vs. reading a word already spelt with known letters.
    /// Lower is more word-forward.
    pub letters_ratio: u8,
}

/// How fast the curriculum progresses in each dimension, configured by the
/// learner: `letters_per_batch`/`words_per_batch` cap how many new letters /
/// word meanings are in flight at once (gentler = smaller), `grammar_gating`
/// introduces grammar rules one at a time, while the three priorities control
/// useful vocabulary, grammar expansion, and completing readable verses.
#[derive(Debug, Serialize, RustSignal)]
pub struct TutorSettings {
    pub letters_per_batch: u8,
    pub words_per_batch: u8,
    pub grammar_gating: bool,
    pub vocab_priority: u8,
    pub grammar_priority: u8,
    pub verse_priority: u8,
    /// Letters↔words balance (0..=100): the share of new-material introductions
    /// spent on new letters vs. reading a word already spelt with known letters.
    /// Lower is more word-forward.
    pub letters_ratio: u8,
}

/// A teachable glyph (consonant — final forms folded — or niqqud point). The
/// teaching content is held on the Dart side keyed by `glyph`.
#[derive(Debug, Serialize, SignalPiece)]
pub struct GlyphCard {
    pub glyph: String,
    pub is_consonant: bool,
    /// For a vowel, an already-learnt consonant to display it on; else null.
    pub host: Option<String>,
    /// The voiced reading of the taught syllable (`host` + `glyph`, e.g.
    /// "bah") when the card has a host; empty for consonants and reading
    /// marks, which quiz by name.
    pub voiced: String,
    /// Same-kind glyphs offered as wrong answers in a multiple-choice quiz;
    /// empty when too few peers exist (the app self-grades instead).
    pub distractors: Vec<String>,
    /// Aligned with `distractors` on a vowel card: each syllable's voiced
    /// reading ("re", "bᵉ"); empty for consonants and reading marks.
    pub voiced_distractors: Vec<String>,
}

/// A word to learn or review. Words teach only meaning (vocalisation is learnt
/// from the glyph/syllable drill); `aspect` is retained for the signal shape and
/// is always `"mean"`.
#[derive(Debug, Serialize, SignalPiece)]
pub struct WordCard {
    pub surface_id: i64,
    pub surface: String,
    pub occurrences: i64,
    /// The surface's voiced reading ("bereshit"), shown under the Hebrew.
    pub translit: String,
    /// The learner meaning of this surface — the quiz answer. Form-specific
    /// where the parse supports it ("and to the house"), the lexeme's base
    /// sense otherwise.
    pub gloss: String,
    /// The lexeme's base sense ("house") when it differs from the
    /// form-specific `gloss` — shown as a secondary "root meaning" line;
    /// empty when `gloss` is already the base sense or for a curated word /
    /// function word / proper noun.
    pub root_gloss: String,
    /// Composition/teaching note for a curated word ("לְ (to) + ־וֹ (him)"),
    /// empty otherwise.
    pub note: String,
    pub root: String,
    pub morph: String,
    pub aspect: String,
    /// Plausible wrong glosses for a multiple-choice meaning quiz; filled only
    /// for `"mean"` cards, empty when too few exist (the app self-grades).
    pub distractors: Vec<String>,
}

/// A pronominal-ending drill: the ending shown on a known host word with its
/// span highlighted in red (`surface == stem + suffix`; render `stem` plain
/// and `suffix` red, as a new vowel is shown on its host consonant). The quiz
/// asks which pronoun the ending stands for; `meaning` is the answer and
/// `distractors` the other endings' meanings. Graded with track `"suffix"`
/// and `key` as the `SubmitReview` key.
#[derive(Debug, Serialize, SignalPiece)]
pub struct SuffixCard {
    /// Person-gender-number key ("1cs", "3ms") — the `"suffix"` grading key.
    pub key: String,
    /// The pronoun the ending stands for ("me", "him") — the quiz answer.
    pub meaning: String,
    pub surface: String,
    /// The host word's voiced reading.
    pub translit: String,
    pub stem: String,
    pub suffix: String,
    /// The host's learner gloss ("to me") for the answer side; may be empty.
    pub gloss: String,
    /// Empty when too few exist for a quiz (the app self-grades instead).
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
    /// Aligned with `words`: true where the word is a proper name, so the
    /// verse view can render names distinctly (sounded out, not translated).
    pub names: Vec<bool>,
}

#[derive(Debug, Serialize, SignalPiece)]
pub struct TutorProgress {
    pub letters_known: i64,
    pub letters_total: i64,
    pub vowels_known: i64,
    pub vowels_total: i64,
    pub grammar_known: i64,
    pub grammar_total: i64,
    pub words_known: i64,
    pub verses_grammar_unlocked: i64,
    pub verses_readable: i64,
    pub total_verses: i64,
}

/// A grammar concept shown once before the word that uses it, illustrated by
/// that word. Carries no grade — acknowledged with another `GetNextStudyItem`.
#[derive(Debug, Serialize, SignalPiece)]
pub struct GrammarCard {
    pub concept: String,
    pub title: String,
    pub explanation: String,
    /// A compact formula, empty when none.
    pub formula: String,
    pub examples: Vec<String>,
    /// A familiar word illustrating this concept (not necessarily the word
    /// about to be learnt).
    pub example: WordCard,
}

/// The next thing for the learner to do. `kind` tags which payload is set:
/// `"new_glyph"`/`"review_glyph"`/`"explain_mark"`/`"explain_final_forms"` → `glyph`;
/// `"new_word"`/`"review_word"` → `word`; `"new_suffix"`/`"review_suffix"` →
/// `suffix`; `"explain_grammar"` → `grammar`;
/// `"explain_intro"` → `intro` (a language-intro card key —
/// `"intro_rtl"`/`"intro_alphabet"`/`"intro_vowels"` — whose teaching content
/// is held on the Dart side); `"read_verse"` → `verse`; `"done"` → none. The
/// `"explain_mark"`, `"explain_final_forms"`, `"explain_grammar"` and
/// `"explain_intro"` cards carry no grade, like `"read_verse"` — the app
/// acknowledges them with another `GetNextStudyItem`, never `SubmitReview`.
#[derive(Debug, Serialize, RustSignal)]
pub struct StudyItem {
    pub kind: String,
    pub glyph: Option<GlyphCard>,
    pub word: Option<WordCard>,
    pub suffix: Option<SuffixCard>,
    pub grammar: Option<GrammarCard>,
    pub intro: Option<String>,
    pub verse: Option<VerseCard>,
    pub progress: TutorProgress,
}

/// Ask for every explanation card the learner has already been shown, for the
/// tutor's reference page.
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetSeenConcepts {}

/// One already-shown explanation card. `kind` says how to render it:
/// `"intro"` and `"final_forms"` keep their teaching content on the Dart side
/// (keyed by `key`), a `"mark"` card's `key` is the reading-mark glyph itself,
/// and a `"grammar"` card carries its content in the remaining fields (empty
/// for the other kinds).
#[derive(Debug, Serialize, SignalPiece)]
pub struct SeenConcept {
    pub kind: String,
    pub key: String,
    pub title: String,
    pub explanation: String,
    pub formula: String,
    pub examples: Vec<String>,
}

/// Every explanation card already unlocked, in reference order: the intro
/// deck, final forms, reading marks (order met), then grammar concepts in
/// teaching order.
#[derive(Debug, Serialize, RustSignal)]
pub struct SeenConcepts {
    pub cards: Vec<SeenConcept>,
}

// ---------------------------------------------------------------------------
// One-time onboarding calibration.
//
// Offered only while `progress.db` is still empty, so a learner who already
// knows the alphabet and/or some vocabulary doesn't have to grind through the
// ordinary cold-start curriculum to reach anything actually new to them. The
// app asks `GetOnboardingStatus` once (e.g. on opening the tutor); if
// `needed`, it self-reports the alphabet via `SetAlphabetKnown`, then runs a
// binary search over `GetCalibrationProbe`'s distinct verse-difficulty tiers
// (each probe is a real verse to judge readability of — searching raw
// vocabulary rank instead would plateau across Biblical Hebrew's huge hapax-
// legomenon tail) and finishes with `FinishCalibration` once converged.
// ---------------------------------------------------------------------------

/// Ask whether onboarding calibration should be offered.
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetOnboardingStatus {}

#[derive(Debug, Serialize, RustSignal)]
pub struct OnboardingStatus {
    pub needed: bool,
    /// Number of distinct verse-difficulty tiers — the domain for the
    /// calibration binary search (see `GetCalibrationProbe`).
    pub tier_count: u32,
}

/// The learner's self-report on the "do you already know the alphabet?"
/// onboarding question. When true, every consonant/vowel point the curriculum
/// would ever teach is marked already graduated.
#[derive(Debug, Deserialize, DartSignal)]
pub struct SetAlphabetKnown {
    pub known: bool,
}

/// Ask for a representative verse at a given difficulty tier, for the
/// vocabulary-calibration binary search: `tier` 0 is the easiest (most common
/// rarest-word) verse in the corpus, counting up toward the rarest.
#[derive(Debug, Deserialize, DartSignal)]
pub struct GetCalibrationProbe {
    pub tier: u32,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct CalibrationProbe {
    pub found: bool,
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
    pub text: String,
    pub tier: u32,
    /// This verse's difficulty: its rarest word's OT occurrence count. The
    /// app tracks the threshold from the last confirmed-readable probe and
    /// hands it back verbatim as `FinishCalibration.min_occurrences`.
    pub min_occurrences: i64,
}

/// Finish onboarding calibration: mark every word occurring at least
/// `min_occurrences` times as already known (graduated), so the curriculum
/// starts introducing new vocabulary from that frequency boundary instead of
/// from scratch. A no-op for `min_occurrences <= 0` (nothing confirmed known).
#[derive(Debug, Deserialize, DartSignal)]
pub struct FinishCalibration {
    pub min_occurrences: i64,
}
