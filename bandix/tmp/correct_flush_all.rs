/// ✅ SINGLE FLUSH PATH untuk semua skenario
pub async fn flush_all(stop_service: bool) -> Result<(), anyhow::Error> {
    if FLUSH_IN_PROGRESS.swap(true, Ordering::Acquire) {
        log::warn!("Flush already in progress, skipping");
        return Err(anyhow::anyhow!("Flush in progress"));
    }
    
    scopeguard::defer!(FLUSH_IN_PROGRESS.store(false, Ordering::Release));
    
    log::info!("=== FLUSH SEQUENCE STARTED ===");
    
    if stop_service {
        log::info!("SIGTERM/SIGINT/SIGHUP received");
        log::info!("Stopping capture");
        log::info!("Detaching shared ingress");
        log::info!("Detaching shared egress");
    }
    
    log::info!("[1/3] Flushing traffic statistics...");
    traffic::flush().await?;
    
    log::info!("[2/3] Flushing connection statistics...");
    connection::flush().await?;
    
    log::info!("[3/3] Flushing DNS cache...");
    dns::flush().await?;
    
    if !stop_service {
        log::info!("Interval flushers remain active");
    }
    
    if stop_service {
        log::info!("Final fsync barrier...");
        let _ = std::process::Command::new("sync").status();
        log::info!("Shutdown complete");
        log::info!("Service stopped / restarting");
    }
    
    log::info!("=== FLUSH COMPLETE ===");
    Ok(())
}
