//! This `hub` crate is the
//! entry point of the Rust logic.

mod functions;
mod signals;

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use haqor_core::bible::Bible;
use rinf::{DartSignalBinary, dart_shutdown, debug_print, write_interface};
use tokio::spawn;
use tokio_with_wasm::alias as tokio;

use functions::{
    SharedBible, finish_calibration, get_calibration_probe, get_chapter_text, get_next_study_item,
    get_onboarding_status, get_seen_concepts, get_tutor_gloss_override_stats, get_tutor_settings,
    get_tutor_stats, get_verse_text, get_vocab, get_word_info, get_word_occurrences,
    optimize_tutor_gloss_overrides, reset_tutor, save_issue_report, save_lexicon_entry_override,
    save_tutor_gloss, set_alphabet_known, set_tutor_settings, submit_review, sync_progress,
};
use signals::SetDataDir;

write_interface!();

/// Wait for Dart to send the directory the database assets were copied to,
/// then open them file-backed. Query signals sent in the meantime are buffered
/// by their channels and answered once the handlers start.
async fn open_bible() -> Option<(SharedBible, PathBuf)> {
    let receiver = SetDataDir::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let path = signal_pack.message.path;
        #[cfg(target_arch = "wasm32")]
        if path == "web" {
            match open_web_bible(signal_pack.binary) {
                Ok(bible) => return Some((Arc::new(Mutex::new(bible)), PathBuf::new())),
                Err(e) => debug_print!("failed to open browser databases: {e}"),
            }
            continue;
        }
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

#[cfg(target_arch = "wasm32")]
fn open_web_bible(binary: Vec<u8>) -> Result<Bible, String> {
    const FILES: [&str; 4] = ["bible.db", "sedra.db", "hebrew.db", "lexicon.db"];
    let mut offset = 0usize;
    let mut next = || -> Result<Vec<u8>, String> {
        let length = binary
            .get(offset..offset + 8)
            .ok_or_else(|| "database bundle is truncated".to_string())?
            .try_into()
            .map(u64::from_le_bytes)
            .map_err(|_| "database bundle length is invalid".to_string())?
            as usize;
        offset += 8;
        let bytes = binary
            .get(offset..offset + length)
            .ok_or_else(|| "database bundle is truncated".to_string())?
            .to_vec();
        offset += length;
        Ok(bytes)
    };
    let mut databases = Vec::with_capacity(FILES.len());
    for file in FILES {
        databases.push((file, next()?));
    }
    let progress = next()?;
    if offset != binary.len() {
        return Err("database bundle has trailing bytes".to_string());
    }
    let mut bible = Bible::open_from_bytes(databases).map_err(|e| e.to_string())?;
    bible
        .attach_progress_in_memory()
        .map_err(|e| e.to_string())?;
    if !progress.is_empty() {
        bible
            .restore_progress_snapshot_bytes(progress)
            .map_err(|e| format!("could not restore browser progress: {e}"))?;
    }
    Ok(bible)
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
    spawn(save_issue_report(bible.clone()));
    spawn(save_lexicon_entry_override(bible.clone()));
    spawn(save_tutor_gloss(bible.clone()));
    spawn(get_tutor_gloss_override_stats(bible.clone()));
    spawn(optimize_tutor_gloss_overrides(bible.clone()));
    spawn(sync_progress(bible, data_dir));

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
}
