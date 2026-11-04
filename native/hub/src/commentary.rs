//! Handlers for the reader's commentary notes, which core stores opaquely
//! one row per note (see `haqor_core::tutor`).

use haqor_core::bible::Bible;
use rinf::{DartSignal, RustSignal, debug_print};

use crate::functions::{SharedBible, lock, now_epoch, persist_browser_progress, send_failure};
use crate::signals::{
    CommentaryNoteEntry, CommentaryNotes, DeleteCommentaryNote, GetCommentaryNotes,
    SaveCommentaryNote,
};

/// The request key Dart listens for when commentary cannot be read.
pub const COMMENTARY_REQUEST: &str = "commentary_notes";

pub fn send_commentary_notes(bible: &Bible) {
    match bible.commentary_notes() {
        Ok(notes) => CommentaryNotes {
            notes: notes
                .into_iter()
                .map(|(id, note_json)| CommentaryNoteEntry { id, note_json })
                .collect(),
        }
        .send_signal_to_dart(),
        Err(error) => send_failure(COMMENTARY_REQUEST, "", error),
    }
}

pub async fn get_commentary_notes(bible: SharedBible) {
    let receiver = GetCommentaryNotes::get_dart_signal_receiver();
    while receiver.recv().await.is_some() {
        send_commentary_notes(&lock(&bible));
    }
}

pub async fn save_commentary_note(bible: SharedBible) {
    let receiver = SaveCommentaryNote::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let note = signal_pack.message;
        let bible = lock(&bible);
        match bible.set_commentary_note(&note.id, &note.note_json, now_epoch()) {
            Ok(()) => persist_browser_progress(&bible),
            Err(error) => debug_print!("save_commentary_note error: {error:?}"),
        }
    }
}

pub async fn delete_commentary_note(bible: SharedBible) {
    let receiver = DeleteCommentaryNote::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.delete_commentary_note(&signal_pack.message.id, now_epoch()) {
            Ok(()) => persist_browser_progress(&bible),
            Err(error) => debug_print!("delete_commentary_note error: {error:?}"),
        }
    }
}
