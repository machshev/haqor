//! This `hub` crate is the
//! entry point of the Rust logic.

mod functions;
mod memorise;
mod signals;

use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use haqor_core::bible::Bible;
use rinf::{DartSignalBinary, RustSignal, dart_shutdown, debug_print, write_interface};
use tokio::spawn;
use tokio_with_wasm::alias as tokio;

#[cfg(target_arch = "wasm32")]
use functions::flush_progress;
use functions::{
    SharedBible, finish_calibration, get_bible_events, get_build_info, get_calibration_probe,
    get_chapter_people, get_chapter_places, get_chapter_text, get_chapter_translation,
    get_cross_references, get_dictionary_entry, get_greek_word, get_journeys, get_name_entity,
    get_next_study_item, get_onboarding_status, get_places, get_quotations, get_seen_concepts,
    get_study_state, get_syntax_trees, get_thematic_overview, get_thematic_references,
    get_tutor_gloss_override_stats, get_tutor_settings, get_tutor_stats, get_verse_text,
    get_verse_texts, get_word_info, get_word_occurrences, optimize_tutor_gloss_overrides,
    reset_tutor, save_issue_report, save_lexicon_entry_override, save_study_state,
    save_tutor_gloss, set_alphabet_known, set_corpus_reader, set_tutor_settings, submit_misreads,
    submit_review, sync_progress,
};
use signals::{BootStatus, SetDataDir};

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

/// Tell Dart how opening the databases went, so its boot sequence can move on
/// or show the reason and offer a retry.
fn report_boot(
    failed: bool,
    progress_reset: bool,
    progress_unreadable: bool,
    message: impl Into<String>,
) {
    BootStatus {
        failed,
        progress_reset,
        progress_unreadable,
        message: message.into(),
    }
    .send_signal_to_dart();
}

/// Report a failed attempt. Rust keeps waiting for another [`SetDataDir`], which
/// is how Dart retries.
fn boot_failed(message: String, progress_unreadable: bool) {
    debug_print!("{message}");
    report_boot(true, false, progress_unreadable, message);
}

/// Wait for Dart to send the directory the database assets were copied to,
/// then open them file-backed. Query signals sent in the meantime are buffered
/// by their channels and answered once the handlers start. A failed attempt is
/// reported to Dart and the next [`SetDataDir`] tries again.
async fn open_bible() -> Option<(SharedBible, PathBuf)> {
    let receiver = SetDataDir::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let path = signal_pack.message.path;
        #[cfg(target_arch = "wasm32")]
        if path == "web" {
            match open_web_bible(signal_pack.binary) {
                Ok((bible, reset)) => {
                    report_boot(false, reset.is_some(), false, reset.unwrap_or_default());
                    return Some((Arc::new(Mutex::new(bible)), PathBuf::new()));
                }
                Err(e) => boot_failed(format!("Could not open the browser databases: {e}"), false),
            }
            continue;
        }
        match Bible::open(Path::new(&path)) {
            Ok(bible) => {
                // Attach the writable tutor progress DB (created on first run)
                // alongside the read-only corpus DBs in the same app-data dir.
                let progress = Path::new(&path).join("progress.db");
                if let Err(e) = bible.attach_progress(&progress) {
                    boot_failed(
                        format!(
                            "Could not open the progress database at {}: {e}",
                            progress.display()
                        ),
                        true,
                    );
                    continue;
                }
                // A second, corpus-only handle for the heavy read-only queries.
                // The corpus is immutable, so it costs nothing if it cannot be
                // had: those queries then share the main connection.
                match Bible::open(Path::new(&path)) {
                    Ok(reader) => set_corpus_reader(reader),
                    Err(e) => debug_print!("no separate corpus reader: {e}"),
                }
                report_boot(false, false, false, "");
                return Some((Arc::new(Mutex::new(bible)), PathBuf::from(path)));
            }
            Err(e) => boot_failed(
                format!("Could not open the databases at {path}: {e}"),
                false,
            ),
        }
    }
    None
}

/// Build a value from the databases and restore saved progress into it. If the
/// snapshot cannot be restored, build again with fresh progress instead of
/// failing the whole boot, and return the reason so the learner can be told.
/// (The failed restore may have left the first build half-replaced, so it is
/// not reused.)
#[cfg(any(target_arch = "wasm32", test))]
fn restore_or_reset<B>(
    build: impl Fn() -> Result<B, String>,
    restore: impl Fn(&mut B, Vec<u8>) -> Result<(), String>,
    progress: Vec<u8>,
) -> Result<(B, Option<String>), String> {
    let mut bible = build()?;
    if progress.is_empty() {
        return Ok((bible, None));
    }
    match restore(&mut bible, progress) {
        Ok(()) => Ok((bible, None)),
        Err(reason) => Ok((build()?, Some(reason))),
    }
}

/// Open the browser databases from the bundle Dart sent. The second value is
/// set when the saved progress could not be restored and was replaced by fresh
/// progress.
#[cfg(target_arch = "wasm32")]
fn open_web_bible(binary: Vec<u8>) -> Result<(Bible, Option<String>), String> {
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
    restore_or_reset(
        || {
            let bible = Bible::open_from_bytes(databases.clone()).map_err(|e| e.to_string())?;
            bible
                .attach_progress_in_memory()
                .map_err(|e| e.to_string())?;
            Ok(bible)
        },
        |bible, snapshot| {
            bible
                .restore_progress_snapshot_bytes(snapshot)
                .map_err(|e| format!("could not restore browser progress: {e}"))
        },
        progress,
    )
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
        get_syntax_trees,
        get_name_entity,
        get_chapter_places,
        get_places,
        get_journeys,
        get_bible_events,
        get_chapter_people,
        get_chapter_translation,
        get_greek_word,
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
    // The browser keeps progress in memory; Dart is sent it when it asks rather
    // than after every write.
    #[cfg(target_arch = "wasm32")]
    {
        let flusher = bible.clone();
        supervise("flush_progress", move || flush_progress(flusher.clone()));
    }
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

    #[test]
    fn a_bad_snapshot_is_replaced_by_fresh_progress() {
        let builds = AtomicUsize::new(0);
        let (built, reset) = restore_or_reset(
            || Ok(builds.fetch_add(1, Ordering::SeqCst)),
            |_, _| Err("file is not a database".to_string()),
            vec![1, 2, 3],
        )
        .unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(built, 1, "a fresh build, not the half-restored one");
        assert_eq!(reset.as_deref(), Some("file is not a database"));
    }

    #[test]
    fn a_good_or_absent_snapshot_is_not_reported_as_reset() {
        let (_, reset) =
            restore_or_reset(|| Ok(()), |_, _| Ok(()), vec![1]).unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(reset, None);
        let (_, reset) = restore_or_reset(
            || Ok(()),
            |_, _| Err("never called".to_string()),
            Vec::new(),
        )
        .unwrap_or_else(|e| panic!("{e}"));
        assert_eq!(reset, None);
    }

    #[test]
    fn a_database_that_will_not_open_still_fails_the_boot() {
        let result = restore_or_reset(
            || Err::<(), _>("no database".to_string()),
            |_, _| Ok(()),
            vec![1],
        );
        assert_eq!(result.err().as_deref(), Some("no database"));
    }
}
