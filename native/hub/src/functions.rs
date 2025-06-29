use crate::signals::{GetVerseText, VerseText};

use rinf::{DartSignal, RustSignal, debug_print};
use haqor_core::bible::Bible;

pub async fn get_verse_text() {
    let bible: Bible = Bible::default();

    let receiver = GetVerseText::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let verse_ref = signal_pack.message;

        debug_print!("{:?}", verse_ref);

        VerseText { text: bible.get(verse_ref.book, verse_ref.chapter, verse_ref.verse).unwrap() }.send_signal_to_dart();
    }
}
