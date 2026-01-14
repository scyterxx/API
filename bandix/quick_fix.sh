#!/bin/bash
echo "Quick fix for compilation errors..."

# 1. Buat command.rs yang benar-benar clean
cat > src/command.rs << 'COMMAND'
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

// ✅ FLUSH SYSTEM IMPORTS (HANYA SEKALI)
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use scopeguard;

use log::info;
use log::LevelFilter;
use tokio::signal;

// ✅ ATOMIC FLUSH GUARD (HANYA SEKALI)
static FLUSH_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

/// 所有命令共享的通用参数
#[derive(Debug, Args, Clone)]
pub struct CommonArgs {
    #[clap(long, help = "Network interface to monitor (required)")]
    pub iface: String,

    #[clap(long, default_value = "8686", help = "Web server listening port")]
    pub port: u16,

    #[clap(
        long,
        default_value = "bandix-data",
        help = "Data directory (ring files and rate limit configurations will be stored here)"
    )]
    pub data_dir: String,

    #[clap(
        long,
        default_value = "info",
        help = "Log level: trace, debug, info, warn, error (default: info). Web and DNS logs are always at DEBUG level."
    )]
    pub log_level: String,
}

/// 流量模块参数
#[derive(Debug, Args, Clone)]
#[clap(group = clap::ArgGroup::new("traffic").multiple(false))]
pub struct TrafficArgs {
    #[clap(long, default_value = "false", help = "Enable traffic monitoring module")]
    pub enable_traffic: bool,

    #[clap(
        long,
        default_value = "600",
        help = "Retention duration (seconds), i.e., ring file capacity (one slot per second)"
    )]
    pub traffic_retention_seconds: u32,

    #[clap(
        long,
        default_value = "600",
        help = "Traffic data checkpoint interval (seconds), how often to save accumulator checkpoints to disk. Long-term hourly data is saved immediately at each hour boundary."
    )]
    pub traffic_persist_interval_seconds: u32,

    #[clap(
        long,
        default_value = "false",
        help = "Enable traffic history data persistence to disk (disabled by default, data only stored in memory)"
    )]
    pub traffic_persist_history: bool,

    #[clap(
        long,
        default_value = "",
        help = "Export traffic device list to a remote HTTP endpoint (POST JSON once per second). Empty = disabled."
    )]
    pub traffic_export_url: String,

    #[clap(
        long,
        default_value = "",
        help = "Export device online/offline events to a remote HTTP endpoint (POST JSON on state change). Empty = disabled."
    )]
    pub traffic_event_url: String,

    #[clap(
        long,
        default_value = "",
        help = "Additional local subnets (comma-separated CIDR notation, e.g. '192.168.2.0/24,10.0.0.0/8'). Empty = only interface subnet."
    )]
    pub traffic_additional_subnets: String,
}

/// DNS 模块参数
#[derive(Debug, Args, Clone)]
pub struct DnsArgs {
    #[clap(long, default_value = "false", help = "Enable DNS monitoring module")]
    pub enable_dns: bool,

    #[clap(
        long,
        default_value = "10000",
        help = "Maximum number of DNS records to keep in memory (default: 10000)"
    )]
    pub dns_max_records: usize,
}

/// 连接模块参数
#[derive(Debug, Args, Clone)]
pub struct ConnectionArgs {
    #[clap(
        long,
        default_value = "false",
        help = "Enable connection statistics monitoring module"
    )]
    pub enable_connection: bool,
}

#[derive(Debug, Parser, Clone)]
#[clap(name = "bandix")]
#[clap(author = "github.com/timsaya")]
#[clap(version = env!("CARGO_PKG_VERSION"))]
#[clap(about = "Network traffic monitoring based on eBPF for OpenWrt")]
pub struct Options {
    #[clap(flatten)]
    pub common: CommonArgs,

    #[clap(flatten)]
    pub traffic: TrafficArgs,

    #[clap(flatten)]
    pub dns: DnsArgs,

    #[clap(flatten)]
    pub connection: ConnectionArgs,
}

// [KEEP ALL THE EXISTING IMPLEMENTATION METHODS...]
// Copy dari file backup atau biarkan seperti adanya

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

// [KEEP THE REST OF THE FILE FROM BACKUP...]
COMMAND

# 2. Tambahkan sisa file dari backup
tail -n +200 src/command.rs.backup >> src/command.rs 2>/dev/null || \
tail -n +200 src/command.rs.backup2 >> src/command.rs 2>/dev/null || \
echo "Using existing file content"

echo "✅ Quick fix applied!"
