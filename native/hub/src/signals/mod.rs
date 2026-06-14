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
