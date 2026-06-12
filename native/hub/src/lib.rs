//! This `hub` crate is the
//! entry point of the Rust logic.

mod functions;
mod signals;

use std::path::Path;
use std::sync::{Arc, Mutex};

use haqor_core::bible::Bible;
use rinf::{DartSignal, dart_shutdown, debug_print, write_interface};
use tokio::spawn;

use functions::{SharedBible, get_chapter_text, get_verse_text, get_word_info};
use signals::SetDataDir;

// Uncomment below to target the web.
// use tokio_with_wasm::alias as tokio;

write_interface!();

/// Wait for Dart to send the directory the database assets were copied to,
/// then open them file-backed. Query signals sent in the meantime are buffered
/// by their channels and answered once the handlers start.
async fn open_bible() -> Option<SharedBible> {
    let receiver = SetDataDir::get_dart_signal_receiver();
    while let Some(signal_pack) = receiver.recv().await {
        let path = signal_pack.message.path;
        match Bible::open(Path::new(&path)) {
            Ok(bible) => return Some(Arc::new(Mutex::new(bible))),
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
    let Some(bible) = open_bible().await else {
        return;
    };
    spawn(get_verse_text(bible.clone()));
    spawn(get_chapter_text(bible.clone()));
    spawn(get_word_info(bible));

    // Keep the main function running until Dart shutdown.
    dart_shutdown().await;
}
