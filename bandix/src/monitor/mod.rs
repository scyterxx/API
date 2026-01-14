
use std::sync::atomic::{AtomicBool, Ordering};

static FLUSH_IN_PROGRESS: AtomicBool = AtomicBool::new(false);
static CAPTURE_RUNNING: AtomicBool = AtomicBool::new(true);

pub fn stop_capture() {
    CAPTURE_RUNNING.store(false, Ordering::SeqCst);
}

pub fn capture_enabled() -> bool {
    CAPTURE_RUNNING.load(Ordering::SeqCst)
}

pub async fn flush_interval() {
    if FLUSH_IN_PROGRESS.load(Ordering::SeqCst) {
        return;
    }

    connection::flush().await;
    dns::flush().await;
    traffic::flush().await;

    persist_all().await;
}

pub async fn flush_manual() {
    flush_interval().await;
}

pub async fn flush_final() {
    if FLUSH_IN_PROGRESS.swap(true, Ordering::SeqCst) {
        return;
    }

    stop_capture();

    connection::flush().await;
    dns::flush().await;
    traffic::flush().await;

    persist_all().await;

    if let Err(e) = storage::sync_barrier() {
        log::error!("sync_barrier failed: {:?}", e);
    }
}
