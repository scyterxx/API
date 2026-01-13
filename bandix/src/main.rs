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
        res = run(options) => { /* ... */ },
        _ = install_signal_handlers() => {
            log::info!("Signal received, stopping...");
        }
    }

    // PANGGIL INI agar data benar-benar masuk ke disk sebelum aplikasi mati
    log::info!("Executing final data flush...");
    crate::monitor::flush_all().await; 

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