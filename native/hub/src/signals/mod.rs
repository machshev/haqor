use rinf::{DartSignal, RustSignal, SignalPiece};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, DartSignal)]
pub struct GetVerseText {
    pub book: u8,
    pub chapter: u8,
    pub verse: u8,
}

#[derive(Debug, Serialize, RustSignal)]
pub struct VerseText {
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
