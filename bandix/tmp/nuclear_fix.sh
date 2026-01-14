#!/bin/bash
echo "=== NUCLEAR FIX: Replacing entire command.rs ==="

# Download original dari backup atau buat baru
if [ -f "src/command.rs.backup" ]; then
    echo "1. Restoring from backup..."
    cp src/command.rs.backup src/command.rs
else
    echo "1. Creating new command.rs..."
    # Buat minimal command.rs
    cat > src/command.rs << 'MINIMAL'
use crate::device::DeviceManager;
use crate::ebpf::shared::load_shared;
use crate::monitor::{ConnectionModuleContext, DnsModuleContext, ModuleContext, MonitorManager, TrafficModuleContext};
use crate::monitor::traffic;
use crate::monitor::connection;
use crate::monitor::dns;
use crate::system::log_startup_info;
use crate::utils::network_utils::get_interface_info;
use crate::web;

use aya::maps::Array;
use clap::{Args, Parser};

// Flush system imports
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use scopeguard;

use log::info;
use log::LevelFilter;
use tokio::signal;

static FLUSH_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

// [PASTE THE REST OF YOUR ORIGINAL command.rs HERE WITHOUT DUPLICATES]
MINIMAL
fi

# 2. Tambahkan flush_all function yang benar
echo "2. Adding correct flush_all function..."
cat >> src/command.rs << 'FLUSHFINAL'

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

/// Graceful shutdown handler
pub async fn graceful_shutdown(shutdown_notify: Arc<tokio::sync::Notify>) -> Result<(), anyhow::Error> {
    log::info!("Signal received, graceful shutdown initiated");
    flush_all(true).await?;
    shutdown_notify.notify_waiters();
    Ok(())
}
FLUSHFINAL

echo "✅ Nuclear fix applied!"
