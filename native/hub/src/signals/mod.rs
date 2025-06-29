use rinf::{DartSignal, RustSignal};
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
