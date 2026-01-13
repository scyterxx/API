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
use tokio::signal::unix::{signal, SignalKind};

#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    // 1. Parsing argumen
    let options = Options::parse();

    log::info!("Bandix starting up...");

    // 2. Jalankan signal handler dan program utama secara konkuren
    tokio::select! {
        _res = run(options) => {
            log::info!("Program utama berhenti.");
        },
        _ = install_signal_handlers() => {
            log::info!("Sinyal terminasi diterima.");
        }
    }

    // 3. Final Flush: Jaring pengaman terakhir agar data tersimpan ke disk
    log::info!("Executing final data flush...");
    crate::monitor::flush_all().await;
    log::info!("Bandix shutdown complete.");

    Ok(())
} // <--- Pastikan ini adalah penutup fungsi main

async fn install_signal_handlers() {
    let mut sigterm = signal(SignalKind::terminate()).unwrap();
    let mut sigint  = signal(SignalKind::interrupt()).unwrap();

    tokio::select! {
        _ = sigterm.recv() => { log::info!("SIGTERM received"); },
        _ = sigint.recv() => { log::info!("SIGINT received"); },
    }
    // Cukup return agar select! di main berlanjut ke flush_all
}