use crate::command::{run, Options};
use clap::Parser;
use tokio::signal::unix::{signal, SignalKind};

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let options = Options::parse();
    log::info!("Bandix starting up on OpenWrt...");

    // Jalankan program utama dan signal handler secara bersamaan
    tokio::select! {
        _res = run(options) => {
            log::info!("Program utama berhenti secara normal.");
        },
        _ = install_signal_handlers() => {
            log::info!("Sinyal shutdown diterima (SIGTERM/SIGINT).");
        }
    }

    // FINAL FLUSH: Langkah paling krusial agar data tidak hilang
    log::info!("Sedang menyimpan data terakhir ke disk...");
    crate::monitor::flush_all().await;
    log::info!("Penyimpanan selesai. Bandix berhenti dengan aman.");

    Ok(())
}

async fn install_signal_handlers() {
    // OpenWrt menggunakan SIGTERM untuk perintah 'service stop/restart'
    let mut sigterm = signal(SignalKind::terminate()).unwrap();
    let mut sigint  = signal(SignalKind::interrupt()).unwrap();

    tokio::select! {
        _ = sigterm.recv() => { log::info!("Log: SIGTERM terdeteksi."); },
        _ = sigint.recv() => { log::info!("Log: SIGINT (Ctrl+C) terdeteksi."); },
    }
}