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
