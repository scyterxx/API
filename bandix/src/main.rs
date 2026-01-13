mod api;
mod command;
mod device;
mod ebpf;
mod monitor;
mod storage;
mod system;
mod utils;
mod web;
use clap::Parser;
use command::{run, Options};

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // 1. Parsing argumen command line
    let options = Options::parse();

    // 2. Inisialisasi logging (pastikan ini ada agar log::info terlihat)
    // setup_logging(); 

    log::info!("Bandix starting up...");

    // 3. Jalankan signal handler dan program utama secara konkuren
    // Menggunakan tokio::select memastikan jika salah satu selesai, 
    // kita bisa menangani penutupan dengan rapi.
    tokio::select! {
        res = run(options) => {
            if let Err(e) = res {
                log::error!("Bandix execution error: {}", e);
                return Err(e);
            }
        },
        _ = install_signal_handlers() => {
            log::info!("Termination signal received, shutting down Bandix...");
        }
    }

    // 4. Final Flush sebelum benar-benar keluar (Lapis pengaman terakhir)
    log::info!("Performing final data flush...");
    crate::monitor::flush_all().await;
    log::info!("Bandix shutdown complete.");

    Ok(())
}

use tokio::signal::unix::{signal, SignalKind};
use crate::command::flush_all;

async fn install_signal_handlers() {
    let mut sigterm = signal(SignalKind::terminate()).unwrap();
    let mut sigint  = signal(SignalKind::interrupt()).unwrap();
    let mut sighup  = signal(SignalKind::hangup()).unwrap();

    tokio::select! {
        _ = sigterm.recv() => { log::info!("SIGTERM received"); },
        _ = sigint.recv() => { log::info!("SIGINT received"); },
        _ = sighup.recv() => { log::info!("SIGHUP received"); },
    }
    
    // Jangan exit di sini. 
    // Return dari fungsi ini akan memicu tokio::select! di main untuk lanjut ke tahap flush.
}