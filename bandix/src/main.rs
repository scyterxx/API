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
    let options = Options::parse();

    tokio::select! {
        _res = run(options) => { // Gunakan _res agar warning hilang
            log::info!("Program utama berhenti.");
        },
        _ = install_signal_handlers() => {
            log::info!("Sinyal terminasi diterima.");
        }
    }

    // PANGGIL INI SEKARANG (Hapus warning unused import)
    log::info!("Sedang menyimpan data ke disk (Final Flush)...");
    crate::monitor::flush_all().await; 
    log::info!("Penyimpanan selesai. Keluar.");

    Ok(())

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