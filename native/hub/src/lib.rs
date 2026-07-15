//! This `hub` crate is the
//! entry point of the Rust logic.

mod functions;
mod signals;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use haqor_core::bible::Bible;
use rinf::{DartSignal, dart_shutdown, debug_print, write_interface};
use tokio::spawn;

use functions::{
    SharedBible, finish_calibration, get_calibration_probe, get_chapter_text, get_next_study_item,
    get_onboarding_status, get_seen_concepts, get_tutor_settings, get_tutor_stats, get_verse_text,
    get_vocab, get_word_info, get_word_occurrences, reset_tutor, save_tutor_gloss,
    set_alphabet_known, set_tutor_settings, submit_review, sync_progress,
};
use signals::SetDataDir;

// Uncomment below to target the web.
// use tokio_with_wasm::alias as tokio;

write_interface!();

/// Wait for Dart to send the directory the database assets were copied to,
/// then open them file-backed. Query signals sent in the meantime are buffered
/// by their channels and answered once the handlers start.
async fn open_bible() -> Option<(SharedBible, PathBuf)> {
    let receiver = SetDataDir::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let path = signal_pack.message.path;
        match Bible::open(Path::new(&path)) {
            Ok(bible) => {
                // Attach the writable tutor progress DB (created on first run)
                // alongside the read-only corpus DBs in the same app-data dir.
                let progress = Path::new(&path).join("progress.db");
                if let Err(e) = bible.attach_progress(&progress) {
                    debug_print!("failed to attach progress db at {progress:?}: {e}");
                }
                return Some((Arc::new(Mutex::new(bible)), PathBuf::from(path)));
            }
            Err(e) => debug_print!("failed to open databases at {path}: {e}"),
        }
    }
    None
}

// You can go with any async library, not just `tokio`.
#[tokio::main(flavor = "current_thread")]
async fn main() {
    // Spawn concurrent tasks.
    // Always use non-blocking async functions like `tokio::fs::File::open`.
    // If you must use blocking code, use `tokio::task::spawn_blocking`
    // or the equivalent provided by your async library.
    let Some((bible, data_dir)) = open_bible().await else {
        return;
    };
    spawn(get_verse_text(bible.clone()));
    spawn(get_chapter_text(bible.clone()));
    spawn(get_vocab(bible.clone()));
    spawn(get_word_info(bible.clone()));
    spawn(get_word_occurrences(bible.clone()));
    spawn(get_next_study_item(bible.clone()));
    spawn(submit_review(bible.clone()));
    spawn(reset_tutor(bible.clone()));
    spawn(get_tutor_stats(bible.clone()));
    spawn(get_seen_concepts(bible.clone()));
    spawn(get_tutor_settings(bible.clone()));
    spawn(set_tutor_settings(bible.clone()));
    spawn(get_onboarding_status(bible.clone()));
    spawn(set_alphabet_known(bible.clone()));
    spawn(get_calibration_probe(bible.clone()));
    spawn(finish_calibration(bible.clone()));
    spawn(save_tutor_gloss(bible.clone()));
    spawn(sync_progress(bible, data_dir));

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
}
