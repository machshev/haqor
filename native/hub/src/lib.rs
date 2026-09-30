//! This `hub` crate is the
//! entry point of the Rust logic.

mod functions;
mod memorise;
mod signals;

use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use haqor_core::bible::Bible;
use rinf::{DartSignalBinary, dart_shutdown, debug_print, write_interface};
use tokio::spawn;
use tokio_with_wasm::alias as tokio;

use functions::{
    SharedBible, finish_calibration, get_build_info, get_calibration_probe, get_chapter_text,
    get_cross_references, get_dictionary_entry, get_next_study_item, get_onboarding_status,
    get_quotations, get_seen_concepts, get_study_state, get_thematic_overview,
    get_thematic_references, get_tutor_gloss_override_stats, get_tutor_settings, get_tutor_stats,
    get_verse_text, get_verse_texts, get_vocab, get_word_info, get_word_occurrences,
    optimize_tutor_gloss_overrides, reset_tutor, save_issue_report, save_lexicon_entry_override,
    save_study_state, save_tutor_gloss, set_alphabet_known, set_tutor_settings, submit_misreads,
    submit_review, sync_progress,
};
use signals::SetDataDir;

write_interface!();

/// Run each handler under [`supervise`], all sharing one database.
macro_rules! serve {
    ($bible:expr, $($handler:path),+ $(,)?) => {
        $({
            let bible = $bible.clone();
            supervise(stringify!($handler), move || $handler(bible.clone()));
        })+
    };
}

/// Keep a handler answering for the life of the app. Each handler is a loop
/// over one signal's receiver, so a panic in core while serving one request
/// would end that loop and leave the signal unanswered from then on. The
/// panicked request is lost (its page times out and offers a retry), but the
/// loop is started again for the next one.
fn supervise<F, Fut>(name: &'static str, handler: F)
where
    F: Fn() -> Fut + Send + 'static,
    Fut: Future<Output = ()> + Send + 'static,
{
    spawn(async move {
        loop {
            match spawn(handler()).await {
                Err(e) if e.is_panic() => debug_print!("{name} panicked; restarting it"),
                _ => break,
            }
        }
    });
}

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
    const FILES: [&str; 1] = ["haqor.db"];
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
    serve!(
        bible,
        get_verse_text,
        get_verse_texts,
        get_chapter_text,
        get_cross_references,
        get_quotations,
        get_thematic_references,
        get_thematic_overview,
        get_vocab,
        get_word_info,
        get_dictionary_entry,
        get_word_occurrences,
        get_next_study_item,
        submit_review,
        submit_misreads,
        reset_tutor,
        get_tutor_stats,
        get_seen_concepts,
        get_tutor_settings,
        get_study_state,
        save_study_state,
        set_tutor_settings,
        get_onboarding_status,
        get_build_info,
        set_alphabet_known,
        get_calibration_probe,
        finish_calibration,
        save_issue_report,
        save_lexicon_entry_override,
        save_tutor_gloss,
        get_tutor_gloss_override_stats,
        optimize_tutor_gloss_overrides,
        memorise::get_memory_passages,
        memorise::save_memory_passage,
        memorise::delete_memory_passage,
        memorise::get_next_memory_card,
        memorise::get_memory_layout,
        memorise::set_memory_layout,
        memorise::get_memory_run,
        memorise::submit_memory_recital,
        memorise::get_memory_stats,
        memorise::set_memory_settings,
    );
    supervise("sync_progress", move || {
        sync_progress(bible.clone(), data_dir.clone())
    });

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::Duration;

    #[::tokio::test]
    async fn a_panicking_handler_is_started_again() {
        let starts = Arc::new(AtomicUsize::new(0));
        let counted = starts.clone();
        supervise("test", move || {
            let run = counted.fetch_add(1, Ordering::SeqCst);
            async move {
                if run < 2 {
                    panic!("handler panic {run}");
                }
            }
        });
        // The third run returns normally, which ends supervision.
        for _ in 0..100 {
            if starts.load(Ordering::SeqCst) == 3 {
                break;
            }
            ::tokio::time::sleep(Duration::from_millis(10)).await;
        }
        assert_eq!(starts.load(Ordering::SeqCst), 3);
    }
}
