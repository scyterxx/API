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
    // 解析命令行参数
    let options = Options::parse();

    // 运行主程序
    run(options).await?;

    Ok(())
}

use tokio::signal::unix::{signal, SignalKind};
use crate::command::flush_all;

async fn install_signal_handlers() {
    let mut sigterm = signal(SignalKind::terminate()).unwrap();
    let mut sigint  = signal(SignalKind::interrupt()).unwrap();
    let mut sighup  = signal(SignalKind::hangup()).unwrap();

    tokio::select! {
        _ = sigterm.recv() => {},
        _ = sigint.recv() => {},
        _ = sighup.recv() => {},
    }

    log::info!("SIGTERM/SIGINT/SIGHUP received");
    flush_all().await;
    std::process::exit(0);
}
