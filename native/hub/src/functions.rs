use crate::signals::{
    BdbSummary, BuildInfo, CalibrationProbe, ChapterText, ChapterTranslation, CrossReferenceEntry,
    CrossReferences, DictionaryEntry, FinishCalibration, GetBuildInfo, GetCalibrationProbe,
    GetChapter, GetChapterTranslation, GetCrossReferences, GetDictionaryEntry, GetNextStudyItem,
    GetOnboardingStatus, GetQuotations, GetSeenConcepts, GetStudyState, GetSyntaxTrees,
    GetThematicOverview, GetThematicReferences, GetTutorGlossOverrideStats, GetTutorSettings,
    GetTutorStats, GetVerseText, GetVerseTexts, GetWordInfo, GetWordOccurrences, GlyphCard,
    GrammarCard, IssueReportStatus, KetivEntry, LexemeSummary, LexiconEntryOverrideStatus,
    Occurrence, OccurrenceParse, OnboardingStatus, OptimizeTutorGlossOverrides, ProgressSyncStatus,
    QuotationEntry, Quotations, RequestFailed, ResetTutor, RootChoice, SaveIssueReport,
    SaveLexiconEntryOverride, SaveStudyState, SaveTutorGloss, SeenConcept, SeenConcepts,
    SetAlphabetKnown, SetTutorSettings, StudyItem, StudyState, SubmitMisreads, SubmitReview,
    SuffixCard, SyncProgress, SyntaxNodeEntry, SyntaxTrees, ThematicOverview,
    ThematicReferenceEntry, ThematicReferences, ThematicTarget, ThematicVerseEntry,
    TranslationSpanEntry, TranslationWordEntry, TutorGlossOverrideStats, TutorProgress,
    TutorSettings, TutorStats, VerseCard, VerseEntry, VerseRef, VerseSyntaxEntry, VerseText,
    VerseTextEntry, VerseTexts, VerseTranslationEntry, WordCard, WordInfo, WordOccurrence,
    WordOccurrences,
};
use crate::signals::{
    ChapterPeople, ChapterPersonEntry, ChapterPlaceEntry, ChapterPlaces, ChapterRelationEntry,
    GetChapterPeople, GetChapterPlaces, GetNameEntity, NameEntityInfo, NameFormEntry,
    NameLinkEntry, NameSummaryEntry, NameVerse, PlaceLocationEntry, SenseChoice, WordSenseEntry,
};
#[cfg(target_arch = "wasm32")]
use crate::signals::{FlushProgress, ProgressSnapshot};

use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
#[cfg(any(target_arch = "wasm32", test))]
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;
#[cfg(not(target_arch = "wasm32"))]
use std::time::{SystemTime, UNIX_EPOCH};

use haqor_core::bible::{
    BdbEntry, Bible, LexiconEntry, LexiconSource, QuotationFilter, QuotationScope, RootRef,
    SedraLexemeSummary, ThematicFilter, inflected_gloss,
};
use haqor_core::tutor::{self, Grade, Track};
use rinf::{DartSignal, RustSignal, debug_print};
use std::fmt::Display;

/// One database connection is shared by all query handlers. The corpus is
/// read-only but the attached progress database is written by the tutor,
/// memorise and sync handlers, so a panic mid-write could in principle leave a
/// half-applied change. A transaction rolls back as the panic unwinds, so
/// the connection is still sound and keeps being used after a handler panic
/// (which [`crate::supervise`] recovers from).
pub type SharedBible = Arc<Mutex<Bible>>;

/// A second connection to the corpus alone, opened by [`crate::open_bible`] on
/// native. The corpus is immutable, so this is a cheap extra handle that shares
/// no lock with the main one, and heavy read-only queries run on it off the
/// runtime thread ([`read_corpus`]) instead of holding the main connection
/// against the reader and the tutor. It has no progress database attached, so
/// it is only for queries that do not depend on learner data.
static CORPUS_READER: OnceLock<SharedBible> = OnceLock::new();

/// Keep the corpus-only connection [`read_corpus`] runs heavy queries on.
pub(crate) fn set_corpus_reader(reader: Bible) {
    let _ = CORPUS_READER.set(Arc::new(Mutex::new(reader)));
}

/// Run a heavy, read-only corpus query without stalling the other handlers.
/// On native it goes to a blocking thread and the corpus-only connection, so
/// the runtime thread and the main connection stay free meanwhile. The browser
/// has no threads to hand it to and only the one connection, so the query runs
/// where it is, as it always did. An `Err` is a query that panicked.
pub(crate) async fn read_corpus<T: Send + 'static>(
    bible: &SharedBible,
    query: impl FnOnce(&Bible) -> T + Send + 'static,
) -> Result<T, String> {
    #[cfg(not(target_arch = "wasm32"))]
    if let Some(reader) = CORPUS_READER.get() {
        return run_blocking(reader.clone(), query).await;
    }
    Ok(query(&lock(bible)))
}

/// Run `query` on a blocking thread against what `handle` guards. A panic in it
/// is returned as an error and leaves the handle usable for the next query.
#[cfg(not(target_arch = "wasm32"))]
async fn run_blocking<H: Send + 'static, T: Send + 'static>(
    handle: Arc<Mutex<H>>,
    query: impl FnOnce(&H) -> T + Send + 'static,
) -> Result<T, String> {
    tokio::task::spawn_blocking(move || {
        query(&handle.lock().unwrap_or_else(PoisonError::into_inner))
    })
    .await
    .map_err(|e| format!("corpus query stopped unexpectedly: {e}"))
}

pub(crate) fn lock(bible: &SharedBible) -> MutexGuard<'_, Bible> {
    bible.lock().unwrap_or_else(PoisonError::into_inner)
}

/// Answer a request that failed with [`RequestFailed`], so the page waiting on
/// its reply can show the error and offer a retry. `key` is empty unless the
/// page can have several instances of `request` in flight.
pub(crate) fn send_failure(request: &str, key: impl Into<String>, error: impl Display) {
    debug_print!("{request} error: {error}");
    RequestFailed {
        request: request.to_string(),
        key: key.into(),
        message: error.to_string(),
    }
    .send_signal_to_dart();
}

/// Every lexicon's entries for a root family, as the Lexicon tab's lexemes:
/// the BDB entries and SEDRA lexemes given, with Klein's and Jastrow's for the
/// same word beside them.
fn lexicon_rows(
    bible: &Bible,
    root: &str,
    bdb: Vec<BdbEntry>,
    sedra: Vec<SedraLexemeSummary>,
) -> Vec<LexemeSummary> {
    bible
        .root_lexemes(root, bdb, sedra)
        .unwrap_or_else(|e| {
            debug_print!("root_lexemes({root:?}) error: {e:?}");
            Vec::new()
        })
        .into_iter()
        .map(|l| LexemeSummary {
            headword: l.headword,
            pos_category: l.pos_category.to_string(),
            is_current: l.is_current,
            entries: l.entries.into_iter().map(lexicon_summary).collect(),
        })
        .collect()
}

fn lexicon_summary(e: LexiconEntry) -> BdbSummary {
    BdbSummary {
        pos_category: e.pos_category.to_string(),
        source: e.source.as_str().to_string(),
        lang: e.lang,
        homograph: e.homograph,
        headword: e.headword,
        gloss: e.gloss,
        content_json: e.content_json,
    }
}

/// Answer the previews of Klein and Jastrow links: one entry by its key.
pub async fn get_dictionary_entry(bible: SharedBible) {
    let receiver = GetDictionaryEntry::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        let entry = LexiconSource::parse(&req.source).and_then(|source| {
            lock(&bible)
                .dictionary_entry(source, &req.key)
                .unwrap_or_else(|e| {
                    debug_print!(
                        "dictionary_entry({:?}, {:?}) error: {e:?}",
                        req.source,
                        req.key
                    );
                    None
                })
        });
        DictionaryEntry {
            request_id: req.request_id,
            found: entry.is_some(),
            entry: entry.map(lexicon_summary),
        }
        .send_signal_to_dart();
    }
}

/// Browser SQLite lives in the WASM heap. Serialising all of it is the cost of
/// one save, so a learner write only marks the progress as changed, and
/// [`flush_progress`] sends Dart a snapshot of it when Dart asks (a timer there
/// and the page being hidden), so the host can persist it between PWA launches.
#[cfg(any(target_arch = "wasm32", test))]
static PROGRESS_DIRTY: AtomicBool = AtomicBool::new(false);

#[cfg(target_arch = "wasm32")]
pub(crate) fn persist_browser_progress(_: &Bible) {
    PROGRESS_DIRTY.store(true, Ordering::Release);
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn persist_browser_progress(_: &Bible) {}

/// Whether progress changed since the last call, clearing the mark.
#[cfg(any(target_arch = "wasm32", test))]
fn take_progress_dirty() -> bool {
    PROGRESS_DIRTY.swap(false, Ordering::AcqRel)
}

/// Send Dart a snapshot of the browser progress if it changed since the last.
#[cfg(target_arch = "wasm32")]
fn flush_browser_progress(bible: &SharedBible) {
    use rinf::RustSignalBinary;

    if !take_progress_dirty() {
        return;
    }
    // The snapshot is taken under the lock and sent after it is let go.
    let snapshot = lock(bible).progress_snapshot_bytes();
    match snapshot {
        Ok(snapshot) => ProgressSnapshot {}.send_signal_to_dart(snapshot),
        Err(error) => {
            // Stay marked, so the next request tries again.
            PROGRESS_DIRTY.store(true, Ordering::Release);
            debug_print!("could not snapshot browser progress: {error}");
        }
    }
}

/// Send Dart any changed browser progress when it asks: on a short timer of its
/// own while the page is open, and as the page is hidden.
#[cfg(target_arch = "wasm32")]
pub async fn flush_progress(bible: SharedBible) {
    let receiver = FlushProgress::get_dart_signal_receiver();
    while receiver.recv().await.is_some() {
        flush_browser_progress(&bible);
    }
}

const MAX_SYNC_SNAPSHOT_BYTES: usize = 64 * 1024 * 1024;

struct SyncEndpoint {
    host: String,
    port: u16,
    path: String,
}

fn parse_sync_endpoint(input: &str) -> Result<SyncEndpoint, String> {
    let rest = input.trim().strip_prefix("http://").ok_or_else(|| {
        "Sync server must start with http:// (LAN sync does not use HTTPS directly).".to_string()
    })?;
    let (authority, path) = match rest.find('/') {
        Some(index) => (&rest[..index], &rest[index..]),
        None => (rest, "/v1/progress"),
    };
    if authority.is_empty() || authority.contains('@') {
        return Err("Sync server address is invalid.".to_string());
    }
    let (host, port) = match authority.rsplit_once(':') {
        Some((host, port)) if !host.is_empty() => (
            host.to_string(),
            port.parse::<u16>()
                .map_err(|_| "Sync server port is invalid.".to_string())?,
        ),
        _ => (authority.to_string(), 80),
    };
    Ok(SyncEndpoint {
        host,
        port,
        path: path.to_string(),
    })
}

/// Read the response headers up to the blank line, returning `Content-Length`.
fn read_content_length(reader: &mut impl BufRead) -> Result<Option<usize>, String> {
    let mut content_length = None;
    loop {
        let mut line = String::new();
        let read = reader
            .read_line(&mut line)
            .map_err(|e| format!("Could not read sync response: {e}"))?;
        if read == 0 {
            return Err("Sync server closed the connection mid-response.".to_string());
        }
        if line == "\r\n" || line == "\n" {
            break;
        }
        if let Some((name, value)) = line.split_once(':')
            && name.eq_ignore_ascii_case("content-length")
        {
            content_length = value.trim().parse::<usize>().ok();
        }
    }
    Ok(content_length)
}

fn post_snapshot(endpoint: &SyncEndpoint, token: &str, body: &[u8]) -> Result<Vec<u8>, String> {
    if body.len() > MAX_SYNC_SNAPSHOT_BYTES {
        return Err("Local progress snapshot is unexpectedly large.".to_string());
    }
    let address = format!("{}:{}", endpoint.host, endpoint.port);
    let socket = address
        .to_socket_addrs()
        .map_err(|e| format!("Could not resolve sync server: {e}"))?
        .next()
        .ok_or_else(|| "Could not resolve sync server.".to_string())?;
    let mut stream = TcpStream::connect_timeout(&socket, Duration::from_secs(10))
        .map_err(|e| format!("Could not reach sync server: {e}"))?;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(30)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(30)));
    write!(
        stream,
        "POST {} HTTP/1.1\r\nHost: {}\r\nAuthorization: Bearer {}\r\nContent-Type: application/vnd.sqlite3\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        endpoint.path,
        endpoint.host,
        token,
        body.len(),
    )
    .map_err(|e| format!("Could not send sync request: {e}"))?;
    stream
        .write_all(body)
        .map_err(|e| format!("Could not send progress snapshot: {e}"))?;

    let mut reader = BufReader::new(stream);
    let mut status = String::new();
    reader
        .read_line(&mut status)
        .map_err(|e| format!("Could not read sync response: {e}"))?;
    if !status.starts_with("HTTP/1.1 200") && !status.starts_with("HTTP/1.0 200") {
        return Err(format!("Sync server returned {}", status.trim()));
    }
    let content_length = read_content_length(&mut reader)?;
    let length =
        content_length.ok_or_else(|| "Sync server omitted its response length.".to_string())?;
    if length > MAX_SYNC_SNAPSHOT_BYTES {
        return Err("Sync server returned an unexpectedly large snapshot.".to_string());
    }
    let mut snapshot = vec![0; length];
    reader
        .read_exact(&mut snapshot)
        .map_err(|e| format!("Could not read progress snapshot: {e}"))?;
    if !haqor_core::progress_sync::is_sqlite_snapshot(&snapshot) {
        return Err("Sync server returned an invalid progress snapshot.".to_string());
    }
    Ok(snapshot)
}

fn sync_progress_blocking(
    bible: &SharedBible,
    data_dir: &Path,
    server_url: &str,
    token: &str,
) -> Result<(), String> {
    let endpoint = parse_sync_endpoint(server_url)?;
    if token.trim().is_empty() {
        return Err("Enter the sync token shown when starting the server.".to_string());
    }
    let upload = data_dir.join(".progress-sync-upload.db");
    let download = data_dir.join(".progress-sync-download.db");
    let _ = fs::remove_file(&upload);
    let _ = fs::remove_file(&download);
    let result = (|| {
        lock(bible)
            .export_progress_snapshot(&upload)
            .map_err(|e| format!("Could not prepare progress for sync: {e}"))?;
        let body =
            fs::read(&upload).map_err(|e| format!("Could not read progress snapshot: {e}"))?;
        debug_print!("progress sync: uploading {} bytes", body.len());
        let merged = post_snapshot(&endpoint, token, &body)?;
        debug_print!("progress sync: received {} merged bytes", merged.len());
        fs::write(&download, merged).map_err(|e| format!("Could not save synced progress: {e}"))?;
        let unmerged_issue_reports =
            haqor_core::progress_sync::unmerged_issue_report_count(&upload, &download)
                .map_err(|e| format!("Could not verify synced issue reports: {e}"))?;
        lock(bible)
            .merge_progress_snapshot(&download)
            .map_err(|e| format!("Could not merge synced progress: {e}"))?;
        if unmerged_issue_reports > 0 {
            return Err(format!(
                "Progress synced, but the server did not store {unmerged_issue_reports} issue \
                 report(s). Update and restart haqor-sync-server; the reports remain saved on \
                 this device."
            ));
        }
        Ok(())
    })();
    let _ = fs::remove_file(&upload);
    let _ = fs::remove_file(&download);
    result
}

fn send_study_state(bible: &Bible) {
    match bible.study_state() {
        Ok(Some((workspaces_json, active_workspace_id, _))) => StudyState {
            found: true,
            workspaces_json,
            active_workspace_id: active_workspace_id.unwrap_or_default(),
        }
        .send_signal_to_dart(),
        Ok(None) => StudyState {
            found: false,
            workspaces_json: "[]".to_string(),
            active_workspace_id: String::new(),
        }
        .send_signal_to_dart(),
        Err(error) => send_failure("study_state", "", error),
    }
}

pub async fn get_study_state(bible: SharedBible) {
    let receiver = GetStudyState::get_dart_signal_receiver();
    while receiver.recv().await.is_some() {
        send_study_state(&lock(&bible));
    }
}

pub async fn save_study_state(bible: SharedBible) {
    let receiver = SaveStudyState::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let state = signal_pack.message;
        let bible_guard = lock(&bible);
        let active =
            (!state.active_workspace_id.is_empty()).then_some(state.active_workspace_id.as_str());
        if let Err(error) = bible_guard.set_study_state(&state.workspaces_json, active, now_epoch())
        {
            debug_print!("save_study_state error: {error:?}");
        } else {
            persist_browser_progress(&bible_guard);
        }
    }
}

/// Synchronise on startup and shortly after each answer. Requests are handled
/// serially so a burst of answers cannot copy a half-updated SQLite file.
pub async fn sync_progress(bible: SharedBible, data_dir: PathBuf) {
    let receiver = SyncProgress::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let request = signal_pack.message;
        debug_print!("progress sync: requested");
        let bible = bible.clone();
        let sync_bible = bible.clone();
        let data_dir = data_dir.clone();
        let result = tokio::task::spawn_blocking(move || {
            sync_progress_blocking(&sync_bible, &data_dir, &request.server_url, &request.token)
        })
        .await
        .unwrap_or_else(|e| Err(format!("Sync task stopped unexpectedly: {e}")));
        match result {
            Ok(()) => {
                debug_print!("progress sync: completed successfully");
                send_study_state(&lock(&bible));
                ProgressSyncStatus {
                    success: true,
                    message: "Study and progress synced.".to_string(),
                }
                .send_signal_to_dart();
            }
            Err(message) => {
                debug_print!("progress sync: failed: {message}");
                ProgressSyncStatus {
                    success: false,
                    message,
                }
                .send_signal_to_dart();
            }
        }
    }
}

/// Persist a mobile tutor correction. Dart schedules the normal snapshot sync
/// immediately afterwards; keeping this separate from the static overlay lets
/// corrections be reviewed before they reach the generated lexicon.
pub async fn save_tutor_gloss(bible: SharedBible) {
    let receiver = SaveTutorGloss::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let correction = signal_pack.message;
        let bible_guard = lock(&bible);
        if let Err(error) = bible_guard.set_tutor_gloss_override(
            &correction.surface,
            &correction.gloss,
            &correction.note,
            now_epoch(),
        ) {
            debug_print!("save_tutor_gloss error: {error:?}");
        } else {
            persist_browser_progress(&bible_guard);
        }
    }
}

/// Persist a mobile root/header correction for the word-info Lexicon panel.
pub async fn save_lexicon_entry_override(bible: SharedBible) {
    let receiver = SaveLexiconEntryOverride::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let correction = signal_pack.message;
        let save_result = {
            let bible_guard = lock(&bible);
            let result = bible_guard.set_lexicon_entry_override(
                &correction.surface,
                &correction.root,
                &correction.gloss,
                &correction.reader_gloss,
                now_epoch(),
            );
            if result.is_ok() {
                persist_browser_progress(&bible_guard);
            }
            result
        };
        match save_result {
            Ok(()) => {
                debug_print!("lexicon entry override saved: {}", correction.surface);
                LexiconEntryOverrideStatus {
                    surface: correction.surface,
                    success: true,
                    message: "Lexicon correction saved and queued for sync.".to_string(),
                }
                .send_signal_to_dart();
            }
            Err(error) => {
                debug_print!("save_lexicon_entry_override error: {error:?}");
                LexiconEntryOverrideStatus {
                    surface: correction.surface,
                    success: false,
                    message: "Could not save lexicon correction.".to_string(),
                }
                .send_signal_to_dart();
            }
        }
    }
}

/// Persist an admin bug report or idea and acknowledge the local write. Dart
/// schedules the ordinary snapshot sync only after this succeeds.
pub async fn save_issue_report(bible: SharedBible) {
    let receiver = SaveIssueReport::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let report = signal_pack.message;
        let now = now_epoch();
        let bible = lock(&bible);
        match bible.save_issue_report(
            &report.id,
            &report.report_type,
            &report.note,
            &report.context_json,
            now,
            now,
        ) {
            Ok(()) => {
                persist_browser_progress(&bible);
                debug_print!("issue report saved: {}", report.id);
                IssueReportStatus {
                    report_id: report.id,
                    success: true,
                    message: "Report saved and queued for sync.".to_string(),
                }
                .send_signal_to_dart();
            }
            Err(error) => {
                debug_print!("save_issue_report error: {error:?}");
                IssueReportStatus {
                    report_id: report.id,
                    success: false,
                    message: "Could not save report.".to_string(),
                }
                .send_signal_to_dart();
            }
        }
    }
}

fn send_tutor_gloss_override_stats(stats: tutor::GlossOverrideStats, removed: i64) {
    TutorGlossOverrideStats {
        total: stats.total,
        redundant: stats.redundant,
        removed,
        error: String::new(),
    }
    .send_signal_to_dart();
}

fn send_tutor_gloss_override_error(message: &str) {
    TutorGlossOverrideStats {
        total: 0,
        redundant: 0,
        removed: 0,
        error: message.to_string(),
    }
    .send_signal_to_dart();
}

pub async fn get_tutor_gloss_override_stats(bible: SharedBible) {
    let receiver = GetTutorGlossOverrideStats::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        match lock(&bible).tutor_gloss_override_stats() {
            Ok(stats) => send_tutor_gloss_override_stats(stats, 0),
            Err(error) => {
                debug_print!("tutor_gloss_override_stats error: {error:?}");
                send_tutor_gloss_override_error("Could not inspect local overrides.");
            }
        }
    }
}

pub async fn optimize_tutor_gloss_overrides(bible: SharedBible) {
    let receiver = OptimizeTutorGlossOverrides::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let result = lock(&bible).optimize_tutor_gloss_overrides(now_epoch());
        match result {
            Ok(optimization) => {
                persist_browser_progress(&lock(&bible));
                send_tutor_gloss_override_stats(optimization.stats, optimization.removed)
            }
            Err(error) => {
                debug_print!("optimize_tutor_gloss_overrides error: {error:?}");
                send_tutor_gloss_override_error("Could not optimise local overrides.");
            }
        }
    }
}

pub async fn get_verse_text(bible: SharedBible) {
    let receiver = GetVerseText::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let verse_ref = signal_pack.message;
        debug_print!("{:?}", verse_ref);
        let bible = lock(&bible);
        // English-only keeps the per-word split alongside the joined text: the
        // caller needs to know which Hebrew word each piece of English came
        // from to highlight it.
        let result = if verse_ref.english_only {
            bible
                .verse_gloss_words(verse_ref.book, verse_ref.chapter, verse_ref.verse)
                .map(|pairs| {
                    let (source_words, gloss_words): (Vec<String>, Vec<String>) =
                        pairs.into_iter().unzip();
                    (gloss_words.join(" "), gloss_words, source_words)
                })
        } else {
            bible
                .get(verse_ref.book, verse_ref.chapter, verse_ref.verse)
                .map(|text| (text, Vec::new(), Vec::new()))
        };
        match result {
            Ok((text, gloss_words, source_words)) => VerseText {
                book: verse_ref.book,
                chapter: verse_ref.chapter,
                verse: verse_ref.verse,
                english_only: verse_ref.english_only,
                translit: if verse_ref.english_only {
                    String::new()
                } else {
                    haqor_core::romanize::romanize(&text)
                },
                text,
                gloss_words,
                source_words,
            }
            .send_signal_to_dart(),
            Err(e) => send_failure(
                "verse_text",
                format!(
                    "{}:{}:{}",
                    verse_ref.book, verse_ref.chapter, verse_ref.verse
                ),
                e,
            ),
        }
    }
}

/// Batched counterpart of [`get_verse_text`], for callers that need a page of
/// verses at once (the Occurrences tab). A verse that cannot be read is simply
/// absent from the reply rather than failing the batch.
pub async fn get_verse_texts(bible: SharedBible) {
    let receiver = GetVerseTexts::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible = lock(&bible);
        let verses = req
            .refs
            .iter()
            .filter_map(|r| {
                let (text, gloss_words, source_words) = if req.english_only {
                    let pairs = bible.verse_gloss_words(r.book, r.chapter, r.verse).ok()?;
                    let (source_words, gloss_words): (Vec<String>, Vec<String>) =
                        pairs.into_iter().unzip();
                    (gloss_words.join(" "), gloss_words, source_words)
                } else if req.syriac {
                    (
                        bible.get_syriac(r.book, r.chapter, r.verse).ok()?,
                        Vec::new(),
                        Vec::new(),
                    )
                } else {
                    (
                        bible.get(r.book, r.chapter, r.verse).ok()?,
                        Vec::new(),
                        Vec::new(),
                    )
                };
                Some(VerseTextEntry {
                    book: r.book,
                    chapter: r.chapter,
                    verse: r.verse,
                    text,
                    gloss_words,
                    source_words,
                })
            })
            .collect();
        VerseTexts {
            request_id: req.request_id,
            english_only: req.english_only,
            verses,
        }
        .send_signal_to_dart();
    }
}

pub async fn get_chapter_text(bible: SharedBible) {
    let receiver = GetChapter::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible_guard = lock(&bible);
        match bible_guard.get_chapter(req.book, req.chapter, req.syriac) {
            Ok(raw) => {
                let metadata = bible_guard
                    .chapter_reader_metadata(
                        req.book,
                        req.chapter,
                        req.include_glosses,
                        req.include_morphology,
                        req.include_names,
                        req.include_roots,
                    )
                    .unwrap_or_default();
                let mut cross_references: std::collections::HashMap<u8, Vec<f32>> = bible_guard
                    .chapter_cross_reference_scores(req.book, req.chapter)
                    .map(|scores| scores.into_iter().collect())
                    .unwrap_or_default();
                let verses = raw
                    .into_iter()
                    .map(|(verse, text)| {
                        let metadata = metadata.get(&verse);
                        VerseEntry {
                            verse,
                            text,
                            glosses: metadata
                                .map(|metadata| metadata.glosses.clone())
                                .unwrap_or_default(),
                            morphologies: metadata
                                .map(|metadata| metadata.morphologies.clone())
                                .unwrap_or_default(),
                            names: metadata
                                .map(|metadata| metadata.names.clone())
                                .unwrap_or_default(),
                            roots: metadata
                                .map(|metadata| metadata.roots.clone())
                                .unwrap_or_default(),
                            ketivs: metadata
                                .map(|metadata| {
                                    metadata
                                        .ketivs
                                        .iter()
                                        .map(|ketiv| KetivEntry {
                                            position: ketiv.position,
                                            span: ketiv.span,
                                            text: ketiv.text.clone(),
                                        })
                                        .collect()
                                })
                                .unwrap_or_default(),
                            cross_reference_scores: cross_references
                                .remove(&verse)
                                .unwrap_or_default(),
                        }
                    })
                    .collect();
                ChapterText {
                    book: req.book,
                    chapter: req.chapter,
                    syriac: req.syriac,
                    include_glosses: req.include_glosses,
                    include_morphology: req.include_morphology,
                    include_names: req.include_names,
                    include_roots: req.include_roots,
                    verses,
                }
                .send_signal_to_dart();
            }
            Err(e) => debug_print!("get_chapter_text error: {:?}", e),
        }
    }
}

/// Strip characters that appear in verse text but not in the words table:
/// cantillation marks (U+0591–U+05AF), meteg (U+05BD), maqaf (U+05BE),
/// paseq (U+05C0), sof pasuq (U+05C3), and upper/lower dots (U+05C4–U+05C6).
fn strip_trope(word: &str) -> String {
    word.chars()
        .filter(|&c| {
            let cp = c as u32;
            !(0x0591..=0x05AF).contains(&cp)
                && cp != 0x05BD
                && cp != 0x05BE
                && cp != 0x05C0
                && cp != 0x05C3
                && cp != 0x05C4
                && cp != 0x05C5
                && cp != 0x05C6
        })
        .collect()
}

fn to_signal_occurrences(
    occurrences: Vec<haqor_core::bible::WordOccurrence>,
) -> Vec<WordOccurrence> {
    occurrences
        .into_iter()
        .map(|o| WordOccurrence {
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
        })
        .collect()
}

fn to_signal_tokens(
    bible: &Bible,
    occurrences: Vec<haqor_core::bible::Occurrence>,
) -> Vec<Occurrence> {
    occurrences
        .into_iter()
        .map(|o| Occurrence {
            // TBESH covers the Hebrew Bible, books 1-39.
            sense: if o.book < 40 {
                let stored = bible
                    .word_sense_gloss(o.book, o.chapter, o.verse, o.position)
                    .unwrap_or_default();
                // Stored as TBESH writes it, `to lie down: be dead`.
                let (gloss, meaning) = stored.split_once(": ").unwrap_or((&stored, ""));
                sense_label(gloss, meaning)
            } else {
                String::new()
            },
            book: o.book,
            chapter: o.chapter,
            verse: o.verse,
            position: o.position,
            surface: o.surface,
            lexeme: o.lexeme,
            parse: OccurrenceParse {
                part_of_speech: o.parse.part_of_speech,
                stem: o.parse.stem,
                stem_family: o.parse.stem_family,
                tense: o.parse.tense,
                person: o.parse.person,
                gender: o.parse.gender,
                number: o.parse.number,
                state: o.parse.state,
            },
        })
        .collect()
}

fn name_summary_entry(s: haqor_core::names::NameSummary) -> NameSummaryEntry {
    NameSummaryEntry {
        id: s.id,
        name: s.name,
        kind: s.kind.as_str().to_string(),
        description: s.description,
        origin: s.origin,
        occurrences: s.occurrences,
    }
}

fn place_location_entry(l: haqor_core::names::PlaceLocation) -> PlaceLocationEntry {
    use haqor_core::names::PlaceShape;
    let flat = |parts: &[Vec<[f64; 2]>]| -> Vec<Vec<f64>> {
        parts.iter().map(|part| part.concat()).collect()
    };
    let (area, line) = match &l.shape {
        Some(PlaceShape::Area(parts)) => (flat(parts), Vec::new()),
        Some(PlaceShape::Line(parts)) => (Vec::new(), flat(parts)),
        None => (Vec::new(), Vec::new()),
    };
    PlaceLocationEntry {
        latitude: l.latitude,
        longitude: l.longitude,
        confidence: l.confidence.map_or(-1, i32::from),
        kind: l.kind,
        label: l.label,
        area,
        line,
    }
}

/// A sense as the occurrence filter names it: the word's gloss, then the
/// sense's after a colon where it has one. [`Occurrence::sense`] and
/// [`WordSenseEntry::full_gloss`] are both written by this, so they match.
fn sense_label(gloss: &str, meaning: &str) -> String {
    let (gloss, meaning) = (gloss.trim(), meaning.trim());
    if meaning.is_empty() {
        gloss.to_string()
    } else {
        format!("{gloss}: {meaning}")
    }
}

fn word_sense_entry(s: haqor_core::names::WordSense) -> WordSenseEntry {
    let full_gloss = sense_label(&s.gloss, &s.sense.meaning);
    WordSenseEntry {
        meaning: s.sense.meaning.clone(),
        full_gloss,
        senses: s
            .senses
            .into_iter()
            .map(|choice| SenseChoice {
                is_current: choice.id == s.sense.id,
                meaning: choice.meaning,
                occurrences: choice.occurrences,
            })
            .collect(),
        gloss: s.gloss,
    }
}

/// The OT word a request is about: resolved at its place in the text when the
/// request names one, so a homograph takes the reading of that token, and by
/// its surface alone otherwise.
fn hebrew_word_in_context(
    bible: &Bible,
    word: &str,
    book: Option<u8>,
    chapter: Option<u8>,
    verse: Option<u8>,
    position: Option<u32>,
) -> Option<haqor_core::bible::HebrewWord> {
    match (book, chapter, verse, position) {
        (Some(book), Some(chapter), Some(verse), Some(position)) => {
            bible.hebrew_word_info_at(word, book, chapter, verse, position as usize)
        }
        _ => bible.hebrew_word_info(word),
    }
}

/// Every root the word can be read under, the resolved one first.
fn root_choices(bible: &Bible, word: &str, resolved: &str) -> Vec<RootChoice> {
    bible
        .hebrew_root_options(word, resolved)
        .unwrap_or_default()
        .into_iter()
        .map(|o| RootChoice {
            root: o.root,
            gloss: o.gloss,
            is_primary: o.is_primary,
        })
        .collect()
}

/// The root a request reads the word under: the one it asked for when the word
/// can be read under it, else the `resolved` one. A stale or foreign root
/// would otherwise send the lexicon or the concordance after the wrong word.
fn selected_root(requested: Option<&str>, options: &[RootChoice], resolved: &str) -> String {
    requested
        .filter(|root| options.iter().any(|o| o.root == *root))
        .unwrap_or(resolved)
        .to_string()
}

pub async fn get_word_info(bible: SharedBible) {
    let receiver = GetWordInfo::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let bible = lock(&bible);
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let lookup = strip_trope(&req.word);

        // A Lexicon cross-reference hands back the target's BDB entry id rather
        // than a surface word (root targets like בטח are never surface forms),
        // so resolve it straight to the target entry's root tree.
        if let Some(id) = req.bdb_id.as_deref().filter(|s| !s.is_empty()) {
            match bible.hebrew_bdb_by_id(id) {
                Ok(Some(entry)) => {
                    let mut tree = bible.hebrew_bdb_by_root(&entry.root).unwrap_or_default();
                    // A rootless entry (a particle) isn't reachable by root;
                    // show the target lexeme on its own.
                    if tree.is_empty() {
                        tree.push(BdbEntry {
                            headword: entry.headword.clone(),
                            root: entry.root.clone(),
                            gloss: entry.gloss.clone(),
                            content_json: entry.content_json.clone(),
                            pos: entry.pos.clone(),
                            is_root: entry.is_root,
                        });
                    }
                    let lexicon = lexicon_rows(&bible, &entry.root, tree, Vec::new());
                    WordInfo {
                        request_id: req.request_id,
                        found: true,
                        word: entry.headword,
                        root: entry.root,
                        gloss: entry.gloss,
                        part_of_speech: None,
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        vav_con: false,
                        lexemes: lexicon,
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        roots: Vec::new(),
                        sense: None,
                        name: None,
                    }
                    .send_signal_to_dart();
                }
                _ => {
                    debug_print!("get_word_info: no BDB entry for id {:?}", id);
                    WordInfo {
                        request_id: req.request_id,
                        found: false,
                        word: req.word.clone(),
                        root: String::new(),
                        gloss: String::new(),
                        part_of_speech: None,
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        vav_con: false,
                        lexemes: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        roots: Vec::new(),
                        sense: None,
                        name: None,
                    }
                    .send_signal_to_dart();
                }
            }
            continue;
        }

        if req.syriac {
            // NT lexicon now comes from the full SEDRA database (roots,
            // lexemes, words, english) keyed directly on the displayed Hebrew
            // word, which is the same bijective transliteration SEDRA stores.
            let words = bible.sedra_word_info(&lookup).unwrap_or_default();
            match words.first() {
                Some(first) => {
                    // The whole SEDRA root tree, the looked-up word's own lexeme
                    // flagged, as one lexicon of the family: it leads, with
                    // BDB's Hebrew cognates and Klein's and Jastrow's articles
                    // spelled like the root or any of its lexemes beside it.
                    // Syriac has the one ש, so a Hebrew shin root and sin root
                    // both answer to it.
                    let sedra = bible
                        .sedra_root_tree(first.key_root, first.key_lexeme)
                        .unwrap_or_default();
                    let lexicon = lexicon_rows(
                        &bible,
                        &first.root,
                        bible
                            .hebrew_bdb_by_syriac_root(&first.root)
                            .unwrap_or_default(),
                        sedra,
                    );
                    let gloss = first.meanings.first().cloned().unwrap_or_default();
                    WordInfo {
                        request_id: req.request_id,
                        found: true,
                        word: first.word.clone(),
                        root: first.root.clone(),
                        gloss,
                        part_of_speech: first.part_of_speech.clone(),
                        gender: first.gender.clone(),
                        number: first.number.clone(),
                        prefix: None,
                        suffix: first.suffix.clone(),
                        vav_con: false,
                        lexemes: lexicon,
                        person: first.person.clone(),
                        state: first.state.clone(),
                        tense: first.tense.clone(),
                        form: first.form.clone(),
                        // NT words reach their root through SEDRA, which files
                        // each lexeme under exactly one.
                        roots: Vec::new(),
                        sense: None,
                        name: None,
                    }
                    .send_signal_to_dart();
                }
                None => {
                    debug_print!("get_word_info: no SEDRA match for {:?}", lookup);
                    WordInfo {
                        request_id: req.request_id,
                        found: false,
                        word: req.word,
                        root: String::new(),
                        gloss: String::new(),
                        part_of_speech: None,
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        vav_con: false,
                        lexemes: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        roots: Vec::new(),
                        sense: None,
                        name: None,
                    }
                    .send_signal_to_dart();
                }
            }
        } else {
            // OT lexicon now comes from the Rust reverse-parse engine
            // (`hebrew.db`) for morphology + occurrences, bridged to the
            // OpenScriptures BDB lexicon (`lexicon.db`) by consonantal root for
            // glossed root trees. `hebrew_word_info` normalises the lookup
            // itself, so the raw word is passed through.
            let contextual = hebrew_word_in_context(
                &bible,
                &req.word,
                req.book,
                req.chapter,
                req.verse,
                req.position,
            );
            match contextual {
                Some(info) => {
                    // Every root the word can be read under, the resolved one
                    // first. A compound name has one per element, and which of
                    // them the reader wants is theirs to say — so the sheet is
                    // sent the list, and may ask for another one's lexicon.
                    let roots = root_choices(&bible, &info.word, &info.root);
                    // The selection only redirects the lexicon; the morphology
                    // below still describes the token that was tapped.
                    let selected = selected_root(req.root.as_deref(), &roots, &info.root);
                    // Match core's lexicon-coverage lookup: rooted words use
                    // the root tree, while rootless function words are looked
                    // up by their surface form and prefix.
                    let tree = (if selected.is_empty() {
                        bible.hebrew_bdb_for_surface(
                            &info.word,
                            info.prefix.as_deref().unwrap_or(""),
                        )
                    } else {
                        bible.hebrew_bdb_by_root(&selected)
                    })
                    .unwrap_or_default();
                    // The Peshitta's root spelled with the same letters, so an
                    // OT word shows its Aramaic cognates as SEDRA files them, and
                    // Jastrow's articles on them join Klein's beside BDB's.
                    let sedra = bible
                        .sedra_root_tree_by_letters(&selected)
                        .unwrap_or_default();
                    let lexicon = lexicon_rows(&bible, &selected, tree, sedra);
                    // The headline describes this occurrence, not merely its
                    // dictionary lemma. Keep the BDB entries below as lexeme
                    // definitions, while rendering proclitics and noun/verb
                    // morphology here (לָמַיִם → "to the water").
                    let gloss = inflected_gloss(&info);
                    // Where the word stands, its sense and the person or place it
                    // names.
                    let (sense, name) = match (req.book, req.chapter, req.verse, req.position) {
                        (Some(book), Some(chapter), Some(verse), Some(position)) => (
                            bible
                                .word_sense(book, chapter, verse, position)
                                .ok()
                                .flatten()
                                .map(word_sense_entry),
                            bible
                                .word_name(book, chapter, verse, position)
                                .ok()
                                .flatten()
                                .map(|n| name_summary_entry(n.summary)),
                        ),
                        _ => (None, None),
                    };
                    WordInfo {
                        request_id: req.request_id,
                        found: true,
                        word: info.word,
                        root: selected,
                        gloss,
                        part_of_speech: info.part_of_speech,
                        gender: info.gender,
                        number: info.number,
                        prefix: info.prefix,
                        suffix: info.obj_suffix,
                        vav_con: info.vav_con,
                        lexemes: lexicon,
                        person: info.person,
                        state: info.state,
                        tense: info.tense,
                        form: info.form,
                        roots,
                        sense,
                        name,
                    }
                    .send_signal_to_dart();
                }
                None => {
                    debug_print!("get_word_info: no OT parse for {:?}", lookup);
                    WordInfo {
                        request_id: req.request_id,
                        found: false,
                        word: req.word,
                        root: String::new(),
                        gloss: String::new(),
                        part_of_speech: None,
                        gender: None,
                        number: None,
                        prefix: None,
                        suffix: None,
                        vav_con: false,
                        lexemes: Vec::new(),
                        person: None,
                        state: None,
                        tense: None,
                        form: None,
                        roots: Vec::new(),
                        sense: None,
                        name: None,
                    }
                    .send_signal_to_dart();
                }
            }
        }
    }
}

/// A root to scan the canon for, owned so the scan can move to another thread.
enum ScanRoot {
    Hebrew(String),
    Sedra(i64),
}

/// Every token of `root` across the canon. This is the heaviest query the
/// sheets make, so it runs off the runtime on [`read_corpus`].
async fn root_tokens(bible: &SharedBible, root: ScanRoot) -> Vec<Occurrence> {
    let tokens = read_corpus(bible, move |bible| {
        let root = match &root {
            ScanRoot::Hebrew(root) => RootRef::Hebrew(root),
            ScanRoot::Sedra(key_root) => RootRef::Sedra(*key_root),
        };
        to_signal_tokens(
            bible,
            bible.root_occurrences(root).unwrap_or_else(|e| {
                debug_print!("root_occurrences({root:?}) error: {e:?}");
                Vec::new()
            }),
        )
    })
    .await;
    tokens.unwrap_or_else(|e| {
        debug_print!("root_occurrences error: {e}");
        Vec::new()
    })
}

/// Lazy occurrence lookup, split out of [`get_word_info`] so the Occurrences tab
/// can defer the full-text root scans until it is actually opened. Re-derives
/// the root from the (cheap) lexicon lookup, then scans the canon for it: the
/// root's own testament and its cognates in the other, whichever the word was
/// read in.
pub async fn get_word_occurrences(bible: SharedBible) {
    let receiver = GetWordOccurrences::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);

        // The word is resolved under the lock, which also has the learner's
        // corrections; the scan that follows needs neither and runs without it.
        let (mut reply, scan) = {
            let bible = lock(&bible);
            if req.syriac {
                let words = bible
                    .sedra_word_info(&strip_trope(&req.word))
                    .unwrap_or_default();
                match words.first() {
                    Some(first) => (
                        WordOccurrences {
                            request_id: req.request_id,
                            found: true,
                            occurrences: Vec::new(),
                            tokens: Vec::new(),
                        },
                        Some(ScanRoot::Sedra(first.key_root)),
                    ),
                    None => (empty_word_occurrences(req.request_id), None),
                }
            } else {
                // Even a word the parse engine can't analyse is still a surface
                // form of the text — its own occurrences keep the sheet useful.
                let occurrences = to_signal_occurrences(
                    bible
                        .hebrew_surface_occurrences(&req.word)
                        .unwrap_or_default(),
                );
                // The token's own reading, as `get_word_info` resolves it: a
                // homograph's root depends on where it stands.
                let contextual = hebrew_word_in_context(
                    &bible,
                    &req.word,
                    req.book,
                    req.chapter,
                    req.verse,
                    req.position,
                );
                match contextual {
                    Some(info) => {
                        // A compound name belongs to each of its roots, and the
                        // sheet says which one the reader is reading it under.
                        let roots = root_choices(&bible, &info.word, &info.root);
                        let root = selected_root(req.root.as_deref(), &roots, &info.root);
                        (
                            WordOccurrences {
                                request_id: req.request_id,
                                found: true,
                                occurrences,
                                tokens: Vec::new(),
                            },
                            Some(ScanRoot::Hebrew(root)),
                        )
                    }
                    None => (
                        WordOccurrences {
                            request_id: req.request_id,
                            found: !occurrences.is_empty(),
                            occurrences,
                            tokens: Vec::new(),
                        },
                        None,
                    ),
                }
            }
        };
        if let Some(root) = scan {
            reply.tokens = root_tokens(&bible, root).await;
        }
        reply.send_signal_to_dart();
    }
}

fn empty_word_occurrences(request_id: u32) -> WordOccurrences {
    WordOccurrences {
        request_id,
        found: false,
        occurrences: Vec::new(),
        tokens: Vec::new(),
    }
}

// --- Spaced-repetition reading tutor -------------------------------------

/// Wall-clock now in epoch seconds (the SM-2 scheduler's time base). Tutor
/// state is day-grained, so second precision is ample.
pub(crate) fn now_epoch() -> i64 {
    // wasm32-unknown-unknown has no OS clock: SystemTime::now panics.
    // Date.now uses the browser wall clock and reports milliseconds.
    #[cfg(target_arch = "wasm32")]
    {
        (js_sys::Date::now() / 1000.0) as i64
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0)
    }
}

fn to_signal_glyph(g: tutor::GlyphCard) -> GlyphCard {
    GlyphCard {
        glyph: g.glyph,
        is_consonant: g.is_consonant,
        host: g.host,
        voiced: g.voiced,
        distractors: g.distractors,
        voiced_distractors: g.voiced_distractors,
    }
}

fn to_signal_word(w: tutor::WordCard) -> WordCard {
    WordCard {
        surface_id: w.surface_id,
        surface: w.surface,
        occurrences: w.occurrences,
        translit: w.translit,
        gloss: w.gloss,
        root_gloss: w.root_gloss,
        note: w.note,
        root: w.root,
        morph: w.morph,
        aspect: "mean".to_string(),
        distractors: w.distractors,
    }
}

/// Map a core form-drill [`tutor::WordCard`] to the signal, tagged `"form"`.
/// The `gloss` field carries the inflected answer and `distractors` the
/// contrasting inflections for the "which form?" quiz.
fn to_signal_form(w: tutor::WordCard) -> WordCard {
    WordCard {
        aspect: "form".to_string(),
        ..to_signal_word(w)
    }
}

fn to_signal_suffix(s: tutor::SuffixCard) -> SuffixCard {
    SuffixCard {
        key: s.key,
        meaning: s.meaning,
        surface: s.surface,
        translit: s.translit,
        stem: s.stem,
        suffix: s.suffix,
        gloss: s.gloss,
        distractors: s.distractors,
    }
}

/// Map a core [`tutor::StudyItem`] to its tagged signal form, attaching the
/// current progress counters so the UI can render a status header on any card.
fn to_signal_study_item(bible: &Bible, item: tutor::StudyItem) -> StudyItem {
    let p = bible.tutor_progress().unwrap_or_default();
    let progress = TutorProgress {
        letters_known: p.letters_known,
        letters_total: p.letters_total,
        vowels_known: p.vowels_known,
        vowels_total: p.vowels_total,
        grammar_known: p.grammar_known,
        grammar_total: p.grammar_total,
        words_known: p.words_known,
        verses_grammar_unlocked: p.verses_grammar_unlocked,
        verses_readable: p.verses_readable,
        total_verses: p.total_verses,
    };
    let mut out = StudyItem {
        kind: String::new(),
        glyph: None,
        word: None,
        suffix: None,
        grammar: None,
        intro: None,
        verse: None,
        progress,
    };
    match item {
        tutor::StudyItem::NewGlyph(g) => {
            out.kind = "new_glyph".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::ReviewGlyph(g) => {
            out.kind = "review_glyph".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::NewWord(w) => {
            out.kind = "new_word".into();
            out.word = Some(to_signal_word(w));
        }
        tutor::StudyItem::ReviewWord(w) => {
            out.kind = "review_word".into();
            out.word = Some(to_signal_word(w));
        }
        tutor::StudyItem::NewFormDrill(w) => {
            out.kind = "new_form".into();
            out.word = Some(to_signal_form(w));
        }
        tutor::StudyItem::ReviewFormDrill(w) => {
            out.kind = "review_form".into();
            out.word = Some(to_signal_form(w));
        }
        tutor::StudyItem::NewSuffixDrill(s) => {
            out.kind = "new_suffix".into();
            out.suffix = Some(to_signal_suffix(s));
        }
        tutor::StudyItem::ReviewSuffixDrill(s) => {
            out.kind = "review_suffix".into();
            out.suffix = Some(to_signal_suffix(s));
        }
        tutor::StudyItem::ExplainMark(g) => {
            out.kind = "explain_mark".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::ExplainFinalForms(g) => {
            out.kind = "explain_final_forms".into();
            out.glyph = Some(to_signal_glyph(g));
        }
        tutor::StudyItem::ExplainIntro(key) => {
            out.kind = "explain_intro".into();
            out.intro = Some(key);
        }
        tutor::StudyItem::ExplainGrammar(c) => {
            out.kind = "explain_grammar".into();
            out.grammar = Some(GrammarCard {
                concept: c.concept,
                title: c.title,
                explanation: c.explanation,
                formula: c.formula,
                examples: c.examples,
                example: to_signal_word(c.example),
            });
        }
        tutor::StudyItem::ReadVerse(v) => {
            out.kind = "read_verse".into();
            // Sent with the card, as `get_verse_text` would answer it, so the
            // verse is on screen with the card rather than a round-trip later.
            let text = bible.get(v.book, v.chapter, v.verse).unwrap_or_default();
            let translit = if text.is_empty() {
                String::new()
            } else {
                haqor_core::romanize::romanize(&text)
            };
            out.verse = Some(VerseCard {
                text,
                translit,
                book: v.book,
                chapter: v.chapter,
                verse: v.verse,
                examples: v
                    .examples
                    .into_iter()
                    .map(|(book, chapter, verse)| VerseRef {
                        book,
                        chapter,
                        verse,
                    })
                    .collect(),
                words: v.words,
                names: v.names,
            });
        }
        tutor::StudyItem::Done => out.kind = "done".into(),
    }
    out
}

pub async fn get_next_study_item(bible: SharedBible) {
    let receiver = GetNextStudyItem::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.next_study_item(now_epoch()) {
            Ok(item) => {
                persist_browser_progress(&bible);
                to_signal_study_item(&bible, item).send_signal_to_dart()
            }
            Err(e) => send_failure("next_study_item", "", e),
        }
    }
}

pub async fn submit_review(bible: SharedBible) {
    let receiver = SubmitReview::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let track = match req.track.as_str() {
            "glyph" => Track::Glyph,
            "form" => Track::Form,
            "suffix" => Track::Suffix,
            _ => Track::Word,
        };
        let correct = match req.correct {
            1 => Some(false),
            2 => Some(true),
            _ => None,
        };
        let grade = Grade::from_confidence(req.confidence, correct);
        let bible = lock(&bible);
        match bible.submit_review(track, &req.key, grade, now_epoch()) {
            Ok(item) => {
                persist_browser_progress(&bible);
                to_signal_study_item(&bible, item).send_signal_to_dart()
            }
            Err(e) => send_failure("submit_review", "", e),
        }
    }
}

/// Lapse every misread word of a verse, then answer with the one card that
/// follows the last of them (see [`SubmitMisreads`]).
pub async fn submit_misreads(bible: SharedBible) {
    let receiver = SubmitMisreads::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible = lock(&bible);
        let grade = Grade::from_confidence(0, None);
        let mut next = None;
        let mut failure = None;
        for word in &req.words {
            match bible.submit_review(Track::Word, word, grade, now_epoch()) {
                Ok(item) => next = Some(item),
                Err(e) => {
                    failure = Some(e);
                    break;
                }
            }
        }
        // A review that failed must not look like a saved one: persist what
        // did land, then tell Dart so it can offer a retry.
        if let Some(e) = failure {
            persist_browser_progress(&bible);
            send_failure("submit_misreads", "", e);
            continue;
        }
        // With nothing flagged the learner still expects to move on.
        let next = match next {
            Some(item) => Ok(item),
            None => bible.next_study_item(now_epoch()),
        };
        match next {
            Ok(item) => {
                persist_browser_progress(&bible);
                to_signal_study_item(&bible, item).send_signal_to_dart()
            }
            Err(e) => send_failure("submit_misreads", "", e),
        }
    }
}

pub async fn reset_tutor(bible: SharedBible) {
    let receiver = ResetTutor::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.reset_tutor(now_epoch()) {
            // Reset always empties glyph_srs/word_srs, so onboarding is always
            // needed again — push a fresh status so the app routes back through
            // it (TutorEntryPage is already subscribed) instead of resuming the
            // study flow with a new-but-still-post-onboarding card.
            Ok(()) => {
                persist_browser_progress(&bible);
                let tier_count = bible.calibration_tier_count().unwrap_or(0);
                OnboardingStatus {
                    needed: true,
                    tier_count,
                }
                .send_signal_to_dart();
            }
            Err(e) => send_failure("reset_tutor", "", e),
        }
    }
}

pub async fn get_seen_concepts(bible: SharedBible) {
    let receiver = GetSeenConcepts::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.seen_concepts() {
            Ok(cards) => SeenConcepts {
                cards: cards
                    .into_iter()
                    .map(|c| SeenConcept {
                        kind: c.kind,
                        key: c.key,
                        title: c.title,
                        explanation: c.explanation,
                        formula: c.formula,
                        examples: c.examples,
                    })
                    .collect(),
            }
            .send_signal_to_dart(),
            Err(e) => send_failure("seen_concepts", "", e),
        }
    }
}

pub async fn get_tutor_stats(bible: SharedBible) {
    let receiver = GetTutorStats::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.tutor_stats(now_epoch()) {
            Ok(s) => TutorStats {
                letters_seen: s.letters_seen,
                letters_learning: s.letters_learning,
                letters_mature: s.letters_mature,
                vowels_seen: s.vowels_seen,
                vowels_learning: s.vowels_learning,
                vowels_mature: s.vowels_mature,
                words_seen: s.words_seen,
                words_learning: s.words_learning,
                words_mature: s.words_mature,
                grammar_seen: s.grammar_seen,
                grammar_total: s.grammar_total,
                glyphs_due: s.glyphs_due,
                words_due: s.words_due,
                reviews_today: s.reviews_today,
                reviews_total: s.reviews_total,
                streak_days: s.streak_days,
                accuracy_pct: s.accuracy_pct,
                verses_readable: s.verses_readable,
                total_verses: s.total_verses,
            }
            .send_signal_to_dart(),
            Err(e) => send_failure("tutor_stats", "", e),
        }
    }
}

pub async fn get_tutor_settings(bible: SharedBible) {
    let receiver = GetTutorSettings::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        match bible.tutor_settings() {
            Ok(s) => to_signal_settings(s).send_signal_to_dart(),
            Err(e) => send_failure("tutor_settings", "", e),
        }
    }
}

pub async fn set_tutor_settings(bible: SharedBible) {
    let receiver = SetTutorSettings::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        let bible = lock(&bible);
        let s = tutor::TutorSettings {
            letters_per_batch: req.letters_per_batch,
            words_per_batch: req.words_per_batch,
            grammar_gating: req.grammar_gating,
            vocab_priority: req.vocab_priority,
            grammar_priority: req.grammar_priority,
            verse_priority: req.verse_priority,
            letters_ratio: req.letters_ratio,
        };
        match bible
            .set_tutor_settings(&s)
            .and_then(|()| bible.tutor_settings())
        {
            Ok(stored) => {
                persist_browser_progress(&bible);
                to_signal_settings(stored).send_signal_to_dart()
            }
            Err(e) => send_failure("set_tutor_settings", "", e),
        }
    }
}

fn to_signal_settings(s: tutor::TutorSettings) -> TutorSettings {
    TutorSettings {
        letters_per_batch: s.letters_per_batch,
        words_per_batch: s.words_per_batch,
        grammar_gating: s.grammar_gating,
        vocab_priority: s.vocab_priority,
        grammar_priority: s.grammar_priority,
        verse_priority: s.verse_priority,
        letters_ratio: s.letters_ratio,
    }
}

pub async fn get_onboarding_status(bible: SharedBible) {
    let receiver = GetOnboardingStatus::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let bible = lock(&bible);
        // A database error must not read as "no onboarding needed", which
        // would skip calibration for a learner who has never done it.
        match bible
            .needs_onboarding()
            .and_then(|needed| Ok((needed, bible.calibration_tier_count()?)))
        {
            Ok((needed, tier_count)) => {
                OnboardingStatus { needed, tier_count }.send_signal_to_dart()
            }
            Err(e) => send_failure("onboarding_status", "", e),
        }
    }
}

/// Report what the app is running. The core version is compiled in; the data
/// version comes from the opened database, so the About view shows the build
/// actually in use rather than whatever was bundled.
pub async fn get_build_info(bible: SharedBible) {
    let receiver = GetBuildInfo::get_dart_signal_receiver();
    while let Some(_pack) = receiver.recv().await {
        let data_version = lock(&bible).data_version().unwrap_or_default();
        BuildInfo {
            core_version: haqor_core::VERSION.to_string(),
            data_version,
        }
        .send_signal_to_dart();
    }
}

pub async fn set_alphabet_known(bible: SharedBible) {
    let receiver = SetAlphabetKnown::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        if req.known {
            let bible_guard = lock(&bible);
            if let Err(e) = bible_guard.seed_known_alphabet(now_epoch()) {
                debug_print!("set_alphabet_known error: {:?}", e);
            } else {
                persist_browser_progress(&bible_guard);
            }
        }
    }
}

pub async fn get_calibration_probe(bible: SharedBible) {
    let receiver = GetCalibrationProbe::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        match lock(&bible).calibration_probe(req.tier) {
            Ok(Some(p)) => CalibrationProbe {
                found: true,
                book: p.book,
                chapter: p.chapter,
                verse: p.verse,
                text: p.text,
                tier: p.tier,
                min_occurrences: p.min_occurrences,
            }
            .send_signal_to_dart(),
            Ok(None) => CalibrationProbe {
                found: false,
                book: 0,
                chapter: 0,
                verse: 0,
                text: String::new(),
                tier: req.tier,
                min_occurrences: 0,
            }
            .send_signal_to_dart(),
            Err(e) => send_failure("calibration_probe", "", e),
        }
    }
}

pub async fn finish_calibration(bible: SharedBible) {
    let receiver = FinishCalibration::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        let bible_guard = lock(&bible);
        if let Err(e) = bible_guard.seed_known_vocab(req.min_occurrences, now_epoch()) {
            debug_print!("finish_calibration error: {:?}", e);
        } else {
            persist_browser_progress(&bible_guard);
        }
    }
}

pub async fn get_cross_references(bible: SharedBible) {
    let receiver = GetCrossReferences::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let quotations = lock(&bible)
            .cross_references(
                req.book,
                req.chapter,
                req.verse,
                (req.min_score > 0.0).then_some(req.min_score),
            )
            .unwrap_or_else(|e| {
                debug_print!("get_cross_references error: {:?}", e);
                Vec::new()
            });
        // Each link comes seen from the requested verse; send the other one.
        let entries = quotations
            .into_iter()
            .map(|q| CrossReferenceEntry {
                score: q.score,
                book: q.other.book,
                chapter: q.other.chapter,
                verse: q.other.verse,
                positions: q.other_positions,
                source_positions: q.positions,
            })
            .collect();
        CrossReferences {
            book: req.book,
            chapter: req.chapter,
            verse: req.verse,
            entries,
        }
        .send_signal_to_dart();
    }
}

pub async fn get_quotations(bible: SharedBible) {
    let receiver = GetQuotations::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let filter = QuotationFilter {
            book: Some(req.book),
            first_chapter: (req.first_chapter > 0).then_some(req.first_chapter),
            last_chapter: (req.last_chapter > 0).then_some(req.last_chapter),
            by_reference: req.by_reference,
            min_score: (req.min_score > 0.0).then_some(req.min_score),
            scope: match req.scope {
                1 => QuotationScope::OtherTestament,
                2 => QuotationScope::SameTestament,
                _ => QuotationScope::All,
            },
        };
        // Counting and paging walk the whole link table, so both run together
        // off the runtime.
        let (limit, offset) = (req.limit, req.offset);
        let found = read_corpus(&bible, move |bible| {
            (
                bible.quotation_count(filter),
                bible.quotations(filter, limit, offset),
            )
        })
        .await;
        let (total, quotations) = match found {
            Ok((Ok(total), Ok(quotations))) => (total, quotations),
            Ok((count, page)) => {
                debug_print!("get_quotations error: {:?} {:?}", count.err(), page.err());
                (0, Vec::new())
            }
            Err(e) => {
                debug_print!("get_quotations error: {e}");
                (0, Vec::new())
            }
        };
        // A book filter has each link seen from its verse in the book.
        let entries = quotations
            .into_iter()
            .map(|q| QuotationEntry {
                score: q.score,
                chapter: q.verse.chapter,
                verse: q.verse.verse,
                positions: q.positions,
                other_book: q.other.book,
                other_chapter: q.other.chapter,
                other_verse: q.other.verse,
                other_positions: q.other_positions,
            })
            .collect();
        Quotations {
            request_id: req.request_id,
            book: req.book,
            total,
            entries,
        }
        .send_signal_to_dart();
    }
}

pub async fn get_thematic_references(bible: SharedBible) {
    let receiver = GetThematicReferences::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let references = lock(&bible)
            .thematic_references(req.book, req.chapter, req.verse)
            .unwrap_or_else(|e| {
                debug_print!("get_thematic_references error: {:?}", e);
                Vec::new()
            });
        let entries = references
            .into_iter()
            .map(|r| ThematicReferenceEntry {
                phrase: r.phrase,
                targets: r
                    .targets
                    .into_iter()
                    .map(|t| ThematicTarget {
                        book: t.first.book,
                        chapter: t.first.chapter,
                        verse: t.first.verse,
                        last_chapter: t.last.chapter,
                        last_verse: t.last.verse,
                    })
                    .collect(),
            })
            .collect();
        ThematicReferences {
            book: req.book,
            chapter: req.chapter,
            verse: req.verse,
            entries,
        }
        .send_signal_to_dart();
    }
}

/// A core thematic reference as the signals carry it.
fn thematic_entry(r: haqor_core::bible::ThematicReference) -> ThematicReferenceEntry {
    ThematicReferenceEntry {
        phrase: r.phrase,
        targets: r
            .targets
            .into_iter()
            .map(|t| ThematicTarget {
                book: t.first.book,
                chapter: t.first.chapter,
                verse: t.first.verse,
                last_chapter: t.last.chapter,
                last_verse: t.last.verse,
            })
            .collect(),
    }
}

pub async fn get_thematic_overview(bible: SharedBible) {
    let receiver = GetThematicOverview::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let filter = ThematicFilter {
            book: req.book,
            first_chapter: (req.first_chapter > 0).then_some(req.first_chapter),
            last_chapter: (req.last_chapter > 0).then_some(req.last_chapter),
        };
        let bible = lock(&bible);
        let (total, verses) = match (
            bible.thematic_reference_verse_count(filter),
            bible.thematic_reference_verses(filter, req.limit, req.offset),
        ) {
            (Ok(total), Ok(verses)) => (total, verses),
            (count, page) => {
                debug_print!(
                    "get_thematic_overview error: {:?} {:?}",
                    count.err(),
                    page.err()
                );
                (0, Vec::new())
            }
        };
        ThematicOverview {
            request_id: req.request_id,
            book: req.book,
            total,
            verses: verses
                .into_iter()
                .map(|v| ThematicVerseEntry {
                    chapter: v.verse.chapter,
                    verse: v.verse.verse,
                    entries: v.references.into_iter().map(thematic_entry).collect(),
                })
                .collect(),
        }
        .send_signal_to_dart();
    }
}

pub async fn get_name_entity(bible: SharedBible) {
    let receiver = GetNameEntity::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let bible = lock(&bible);
        let entity = bible.name_entity(req.id).unwrap_or_else(|e| {
            debug_print!("get_name_entity error: {:?}", e);
            None
        });
        let Some(entity) = entity else {
            NameEntityInfo {
                request_id: req.request_id,
                found: false,
                summary: NameSummaryEntry {
                    id: req.id,
                    name: String::new(),
                    kind: String::new(),
                    description: String::new(),
                    origin: String::new(),
                    occurrences: 0,
                },
                category: String::new(),
                text: String::new(),
                forms: Vec::new(),
                links: Vec::new(),
                locations: Vec::new(),
                verses: Vec::new(),
            }
            .send_signal_to_dart();
            continue;
        };
        let mut verses: Vec<NameVerse> = Vec::new();
        for at in bible.name_occurrences(req.id).unwrap_or_default() {
            match verses.last_mut() {
                Some(v) if (v.book, v.chapter, v.verse) == (at.book, at.chapter, at.verse) => {
                    v.positions.push(at.position);
                }
                _ => verses.push(NameVerse {
                    book: at.book,
                    chapter: at.chapter,
                    verse: at.verse,
                    positions: vec![at.position],
                }),
            }
        }
        NameEntityInfo {
            request_id: req.request_id,
            found: true,
            summary: name_summary_entry(entity.summary),
            category: entity.category,
            text: entity.text,
            forms: entity
                .forms
                .into_iter()
                .map(|f| NameFormEntry {
                    hebrew: f.hebrew,
                    english: f.english,
                    significance: f.significance,
                })
                .collect(),
            links: entity
                .links
                .into_iter()
                .map(|l| NameLinkEntry {
                    relation: l.relation,
                    flag: l.flag,
                    other: name_summary_entry(l.other),
                })
                .collect(),
            locations: entity
                .locations
                .into_iter()
                .map(place_location_entry)
                .collect(),
            verses,
        }
        .send_signal_to_dart();
    }
}

pub async fn get_chapter_people(bible: SharedBible) {
    let receiver = GetChapterPeople::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let people = chapter_people(&lock(&bible), req.book, req.chapter).unwrap_or_else(|e| {
            debug_print!("get_chapter_people error: {:?}", e);
            Vec::new()
        });
        ChapterPeople {
            request_id: req.request_id,
            book: req.book,
            chapter: req.chapter,
            people,
        }
        .send_signal_to_dart();
    }
}

/// The people a chapter names, in the order it first names them, each with
/// the verses naming them and their links to the others.
fn chapter_people(bible: &Bible, book: u8, chapter: u8) -> Result<Vec<ChapterPersonEntry>, String> {
    let mut people: Vec<(haqor_core::names::NameEntity, Vec<u8>)> = Vec::new();
    let names = bible
        .chapter_names(book, chapter)
        .map_err(|e| format!("{e:?}"))?;
    for (verse, _, id) in names {
        if let Some((_, verses)) = people.iter_mut().find(|(p, _)| p.summary.id == id) {
            if verses.last() != Some(&verse) {
                verses.push(verse);
            }
            continue;
        }
        let Some(entity) = bible.name_entity(id).map_err(|e| format!("{e:?}"))? else {
            continue;
        };
        if entity.summary.kind == haqor_core::names::NameKind::Person {
            people.push((entity, vec![verse]));
        }
    }
    let named: std::collections::HashSet<u32> = people.iter().map(|(p, _)| p.summary.id).collect();
    Ok(people
        .into_iter()
        .map(|(entity, verses)| ChapterPersonEntry {
            relations: entity
                .links
                .into_iter()
                .filter(|l| named.contains(&l.other.id))
                .map(|l| ChapterRelationEntry {
                    relation: l.relation,
                    flag: l.flag,
                    other_id: l.other.id,
                })
                .collect(),
            person: name_summary_entry(entity.summary),
            verses,
        })
        .collect())
}

pub async fn get_chapter_places(bible: SharedBible) {
    let receiver = GetChapterPlaces::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let places = lock(&bible)
            .chapter_places(req.book, req.chapter)
            .unwrap_or_else(|e| {
                debug_print!("get_chapter_places error: {:?}", e);
                Vec::new()
            });
        ChapterPlaces {
            request_id: req.request_id,
            book: req.book,
            chapter: req.chapter,
            places: places
                .into_iter()
                .map(|p| ChapterPlaceEntry {
                    place: name_summary_entry(p.place),
                    location: place_location_entry(p.location),
                    verses: p.verses,
                })
                .collect(),
        }
        .send_signal_to_dart();
    }
}

/// A core syntax tree as the signals carry it: its nodes in pre-order, each
/// naming its parent by index.
fn syntax_nodes(tree: haqor_core::syntax::SyntaxNode) -> Vec<SyntaxNodeEntry> {
    fn walk(node: haqor_core::syntax::SyntaxNode, parent: i32, out: &mut Vec<SyntaxNodeEntry>) {
        let index = out.len() as i32;
        let (position, part) = match node.word {
            Some(word) => (i32::from(word.position), word.part),
            None => (-1, None),
        };
        let (part_text, part_gloss) = part.map_or_else(Default::default, |p| (p.text, p.gloss));
        out.push(SyntaxNodeEntry {
            parent,
            kind: node.class,
            role: node.role,
            position,
            part_text,
            part_gloss,
        });
        for child in node.children {
            walk(child, index, out);
        }
    }
    let mut out = Vec::new();
    walk(tree, -1, &mut out);
    out
}

pub async fn get_syntax_trees(bible: SharedBible) {
    let receiver = GetSyntaxTrees::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let trees = lock(&bible)
            .chapter_syntax_trees(req.book, req.chapter)
            .unwrap_or_else(|e| {
                debug_print!("get_syntax_trees error: {:?}", e);
                Vec::new()
            });
        let wanted = |verse: u8| {
            (req.first_verse == 0 || verse >= req.first_verse)
                && (req.last_verse == 0 || verse <= req.last_verse)
        };
        SyntaxTrees {
            request_id: req.request_id,
            book: req.book,
            chapter: req.chapter,
            verses: trees
                .into_iter()
                .filter(|(verse, _)| wanted(*verse))
                .map(|(verse, tree)| VerseSyntaxEntry {
                    verse,
                    nodes: syntax_nodes(tree),
                })
                .collect(),
        }
        .send_signal_to_dart();
    }
}

/// A verse's core translation spans as the signals carry them.
fn translation_spans(
    spans: Vec<haqor_core::translation::TranslationSpan>,
) -> Vec<TranslationSpanEntry> {
    spans
        .into_iter()
        .map(|span| TranslationSpanEntry {
            text: span.text,
            supplied: span.supplied,
            words: span
                .words
                .into_iter()
                .map(|w| TranslationWordEntry {
                    chapter: w.chapter,
                    verse: w.verse,
                    position: w.position,
                })
                .collect(),
        })
        .collect()
}

pub async fn get_chapter_translation(bible: SharedBible) {
    let receiver = GetChapterTranslation::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let req = signal_pack.message;
        debug_print!("{:?}", req);
        let verses = lock(&bible)
            .chapter_translation(req.book, req.chapter)
            .unwrap_or_else(|e| {
                debug_print!("get_chapter_translation error: {:?}", e);
                Vec::new()
            });
        ChapterTranslation {
            request_id: req.request_id,
            book: req.book,
            chapter: req.chapter,
            verses: verses
                .into_iter()
                .map(|(verse, spans)| VerseTranslationEntry {
                    verse,
                    spans: translation_spans(spans),
                })
                .collect(),
        }
        .send_signal_to_dart();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A span keeps its text, its supplied mark and the words it renders,
    /// the main one first.
    #[test]
    fn translation_spans_carry_their_words() {
        let spans = haqor_core::translation::parse("[the heavens|4,3] {[was|5]}", 1, 1)
            .unwrap_or_else(|| panic!("unparsed"));
        let entries = translation_spans(spans);
        assert_eq!(entries[0].text, "the heavens");
        let words: Vec<(u8, u8, u16)> = entries[0]
            .words
            .iter()
            .map(|w| (w.chapter, w.verse, w.position))
            .collect();
        assert_eq!(words, [(1, 1, 4), (1, 1, 3)]);
        assert!(entries[1].words.is_empty());
        assert!(entries[2].supplied);
    }

    /// A tree travels in pre-order, each node naming its parent, with a part
    /// of a word carrying its own text and gloss.
    #[test]
    fn syntax_trees_flatten_in_pre_order() {
        let tree = haqor_core::syntax::parse("[ 0{וַ|and} [cl 0:v{יֹּאמֶר|said} [np:s 1]]]")
            .unwrap_or_else(|| panic!("unparsed"));
        let nodes = syntax_nodes(tree);
        let shape: Vec<(i32, &str, &str, i32)> = nodes
            .iter()
            .map(|n| (n.parent, n.kind.as_str(), n.role.as_str(), n.position))
            .collect();
        assert_eq!(
            shape,
            [
                (-1, "", "", -1),
                (0, "", "", 0),
                (0, "cl", "", -1),
                (2, "", "v", 0),
                (2, "np", "s", -1),
                (4, "", "", 1),
            ]
        );
        assert_eq!(nodes[1].part_text, "וַ");
        assert_eq!(nodes[3].part_gloss, "said");
        assert_eq!(nodes[5].part_text, "");
    }

    #[test]
    fn headers_end_at_blank_line_or_bare_newline() {
        let mut crlf = "Content-Length: 7\r\nX: y\r\n\r\nbody".as_bytes();
        assert_eq!(read_content_length(&mut crlf), Ok(Some(7)));
        let mut lf = "content-length: 3\n\nbody".as_bytes();
        assert_eq!(read_content_length(&mut lf), Ok(Some(3)));
    }

    #[test]
    fn headers_error_at_end_of_stream() {
        let mut truncated = "Content-Length: 7\r\n".as_bytes();
        assert!(read_content_length(&mut truncated).is_err());
    }

    fn choice(root: &str, is_primary: bool) -> RootChoice {
        RootChoice {
            root: root.to_string(),
            gloss: String::new(),
            is_primary,
        }
    }

    #[test]
    fn a_requested_root_is_used_only_when_the_word_reads_under_it() {
        let options = [choice("אלה", true), choice("עזר", false)];
        assert_eq!(selected_root(Some("עזר"), &options, "אלה"), "עזר");
        // A root the word has no reading under, such as a previous word's,
        // falls back to the resolved one rather than scanning for it.
        assert_eq!(selected_root(Some("מלכ"), &options, "אלה"), "אלה");
        assert_eq!(selected_root(Some(""), &options, "אלה"), "אלה");
        assert_eq!(selected_root(None, &options, "אלה"), "אלה");
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod reader_tests {
    use super::*;
    use std::time::Instant;

    #[::tokio::test(flavor = "current_thread")]
    async fn a_slow_query_does_not_stall_the_runtime_thread() {
        let handle = Arc::new(Mutex::new(7u32));
        let started = Instant::now();
        let slow = tokio::spawn(run_blocking(handle.clone(), |n| {
            std::thread::sleep(Duration::from_millis(300));
            *n
        }));
        // Everything else that shares the thread keeps being served meanwhile.
        let mut ticks = 0;
        while started.elapsed() < Duration::from_millis(200) {
            ::tokio::time::sleep(Duration::from_millis(10)).await;
            ticks += 1;
        }
        assert!(ticks >= 10, "runtime thread was blocked: {ticks} ticks");
        assert_eq!(slow.await.ok(), Some(Ok(7)));
    }

    #[::tokio::test(flavor = "current_thread")]
    async fn a_panicking_query_is_an_error_and_the_handle_still_works() {
        let handle = Arc::new(Mutex::new(1u32));
        let failed = run_blocking(handle.clone(), |_| -> u32 { panic!("bad query") }).await;
        assert!(failed.is_err());
        assert_eq!(run_blocking(handle, |n| *n + 1).await, Ok(2));
    }
}

#[cfg(test)]
mod progress_snapshot_tests {
    use super::*;

    #[test]
    fn many_writes_make_one_snapshot() {
        assert!(!take_progress_dirty(), "nothing written yet");
        for _ in 0..20 {
            PROGRESS_DIRTY.store(true, Ordering::Release);
        }
        assert!(take_progress_dirty(), "the writes are sent once");
        assert!(!take_progress_dirty(), "and not again until one more");
    }
}
