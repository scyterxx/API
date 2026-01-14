
use tokio::signal::unix::{
    tokio::spawn(wait_for_signal());signal, SignalKind};

async fn wait_for_signal() {
    let mut sigint  = signal(SignalKind::interrupt()).unwrap();
    let mut sigterm = signal(SignalKind::terminate()).unwrap();
    let mut sighup  = signal(SignalKind::hangup()).unwrap();

    tokio::select! {
        _ = sigint.recv() => log::info!("SIGINT received"),
        _ = sigterm.recv() => log::info!("SIGTERM received"),
        _ = sighup.recv() => log::info!("SIGHUP received"),
    }

    crate::monitor::flush_final().await;
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    std::process::exit(0);
}

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
