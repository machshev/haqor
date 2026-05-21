use crate::signals::{ChapterText, GetChapter, GetVerseText, VerseEntry, VerseText};

use rinf::{DartSignal, RustSignal, debug_print};
use haqor_core::bible::Bible;

pub async fn get_verse_text() {
    let bible: Bible = Bible::default();

    let receiver = GetVerseText::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let verse_ref = signal_pack.message;
        debug_print!("{:?}", verse_ref);
        match bible.get(verse_ref.book, verse_ref.chapter, verse_ref.verse) {
            Ok(text) => VerseText { text }.send_signal_to_dart(),
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
