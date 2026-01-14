mod api;
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
#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    env_logger::init();
    
    // Handle shutdown signals
    let shutdown_notify = Arc::new(Notify::new());
    let shutdown_clone = Arc::clone(&shutdown_notify);
    
    tokio::spawn(async move {
        let ctrl_c = tokio::signal::ctrl_c();
        let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();
        let mut sighup = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::hangup()).unwrap();
        
        tokio::select! {
            _ = ctrl_c => {
                info!("Received SIGINT (Ctrl+C), initiating graceful shutdown...");
            }
            _ = sigterm.recv() => {
                info!("Received SIGTERM, initiating graceful shutdown...");
            }
            _ = sighup.recv() => {
                info!("Received SIGHUP, initiating graceful shutdown...");
            }
        }
        
        // Call flush before shutdown
        info!("Flushing data to disk before shutdown...");
        if let Err(e) = crate::monitor::flush_final().await {
            error!("Failed to flush data during shutdown: {}", e);
        }
        
        shutdown_clone.notify_one();
    });
    
    // Rest of main function...
    // 解析命令行参数
    let options = Options::parse();

    // 运行主程序
    run(options).await?;

    Ok(())
}
