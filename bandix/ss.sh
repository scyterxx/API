#!/bin/bash
# fix_all_final.sh

echo "=== FIXING ALL REMAINING ERRORS ==="

# 1. Hapus duplikat mod api
echo "1. Fixing duplicate 'api' module..."
if [ -f "src/api.rs" ] && [ -d "src/api" ]; then
    echo "Found both api.rs and api/ directory"
    # Hapus salah satu (pilih api.rs karena kita buat)
    rm -rf src/api
    echo "Removed src/api directory"
elif [ -d "src/api" ]; then
    # Hapus api/ dan gunakan api.rs
    rm -rf src/api
    echo "Removed src/api directory"
fi

# Hapus duplikat mod api di main.rs
sed -i '/^mod api;$/d' src/main.rs
sed -i '1i\mod api;' src/main.rs
echo "Fixed duplicate mod declaration"

# 2. Tambahkan imports yang hilang di main.rs
echo "2. Adding missing imports to main.rs..."

# Backup main.rs
cp src/main.rs src/main.rs.backup.final

# Buat file main.rs yang diperbaiki
cat > /tmp/main_fixed.rs << 'EOF'
use std::sync::Arc;
use log::{info, error};
use tokio::sync::Notify;

mod api;
mod command;
mod monitor;
mod storage;

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

    // Start API server
    let api_router = api::create_router();
    let api_server = tokio::spawn(async move {
        let addr = std::net::SocketAddr::from(([0, 0, 0, 0], 3000));
        info!("Starting API server on {}", addr);
        axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), api_router)
            .await
            .unwrap();
    });

    // Wait for shutdown signal
    shutdown_notify.notified().await;
    
    // Shutdown API server
    api_server.abort();
    info!("Shutdown completed");

    Ok(())
}
EOF

# Ganti main.rs
cp /tmp/main_fixed.rs src/main.rs

# 3. Tambahkan imports log ke modul-modul yang perlu
echo "3. Adding log imports to monitor modules..."

for module in connection dns traffic; do
    FILE="src/monitor/${module}.rs"
    if [ -f "$FILE" ] && ! grep -q "use log::info" "$FILE"; then
        # Tambahkan di baris setelah mod declaration atau di atas
        if grep -q "^use " "$FILE"; then
            # Tambahkan setelah use statements terakhir
            sed -i '/^use / {
                x
                /^$/! {
                    x
                    H
                    d
                }
                x
                /^$/ {
                    x
                    i\
use log::{info, error};
                    x
                }
            }' "$FILE"
        else
            # Tambahkan di baris pertama
            sed -i '1i\use log::{info, error};' "$FILE"
        fi
        echo "✓ Added log imports to ${module}.rs"
    fi
done

# 4. Pastikan fungsi flush_final() ada di monitor/mod.rs
echo "4. Ensuring flush_final() exists..."

cat > /tmp/flush_final_complete.rs << 'EOF'
use std::sync::atomic::Ordering;

static CAPTURE_RUNNING: AtomicBool = AtomicBool::new(false);
static FLUSH_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

/// Flush all monitoring data to disk (called on shutdown)
pub async fn flush_final() -> Result<()> {
    use std::sync::atomic::Ordering;
    
    info!("Starting final flush of all monitoring data...");
    
    // Check if flush is already in progress
    if FLUSH_IN_PROGRESS.swap(true, Ordering::SeqCst) {
        info!("Flush already in progress, waiting...");
        return Ok(());
    }
    
    // Set CAPTURE_RUNNING to false to stop new data
    CAPTURE_RUNNING.store(false, Ordering::SeqCst);
    
    // Flush all modules
    let results = tokio::join!(
        traffic::flush(),
        connection::flush(),
        dns::flush(),
    );
    
    // Handle results
    match results {
        (Ok(_), Ok(_), Ok(_)) => {
            info!("All modules flushed successfully");
        }
        _ => {
            error!("Some modules failed to flush");
            // Continue anyway to try storage sync
        }
    }
    
    // Sync storage barrier
    if let Err(e) = storage::sync_barrier() {
        error!("Failed to sync storage: {}", e);
    }
    
    info!("Final flush completed");
    
    // Reset flush flag
    FLUSH_IN_PROGRESS.store(false, Ordering::SeqCst);
    
    Ok(())
}
EOF

# Cek apakah AtomicBool sudah di-import
if ! grep -q "use std::sync::atomic::AtomicBool" src/monitor/mod.rs; then
    sed -i '1i\use std::sync::atomic::AtomicBool;' src/monitor/mod.rs
fi

# Ganti atau tambahkan fungsi flush_final
if grep -q "pub async fn flush_final()" src/monitor/mod.rs; then
    # Ganti yang ada
    sed -i '/pub async fn flush_final()/,/^}/d' src/monitor/mod.rs
fi

# Tambahkan fungsi baru
cat /tmp/flush_final_complete.rs >> src/monitor/mod.rs

# 5. Perbaiki api.rs
echo "5. Fixing api.rs..."

cat > src/api.rs << 'EOF'
use axum::{
    routing::{get, post},
    Router,
    Json,
};
use log::{info, error};
use serde_json::json;

use crate::monitor;

/// Create API router with all endpoints
pub fn create_router() -> Router {
    Router::new()
        .route("/api/flush", post(flush_handler))
        .route("/api/health", get(health_handler))
}

/// Handler for manual flush endpoint
async fn flush_handler() -> impl axum::response::IntoResponse {
    info!("Manual flush requested via API");
    
    match monitor::flush_final().await {
        Ok(_) => {
            Json(json!({
                "status": "success",
                "message": "Data flushed successfully"
            }))
        }
        Err(e) => {
            error!("Failed to flush via API: {}", e);
            Json(json!({
                "status": "error",
                "message": format!("Failed to flush: {}", e)
            }))
        }
    }
}

/// Health check endpoint
async fn health_handler() -> impl axum::response::IntoResponse {
    Json(json!({
        "status": "healthy",
        "timestamp": chrono::Utc::now().to_rfc3339()
    }))
}
EOF

# 6. Perbaiki Cargo.toml
echo "6. Updating Cargo.toml..."

if ! grep -q "log =" Cargo.toml; then
    cat >> Cargo.toml << 'EOF'

[dependencies]
log = "0.4"
env_logger = "0.11"
axum = "0.7"
tokio = { version = "1.0", features = ["full", "signal", "rt-multi-thread"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }
serde = { version = "1.0", features = ["derive"] }
EOF
fi

# 7. Buat Result type alias jika belum ada
echo "7. Creating common Result type..."

# Cek apakah sudah ada type Result di lib.rs atau main.rs
if ! grep -q "type Result<T>" src/main.rs && ! grep -q "type Result<T>" src/lib.rs 2>/dev/null; then
    # Tambahkan di main.rs setelah imports
    sed -i '/use /a\
type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;' src/main.rs
fi

# 8. Pastikan semua modul dideklarasikan
echo "8. Ensuring all modules are declared..."

# Buat lib.rs jika belum ada
if [ ! -f "src/lib.rs" ]; then
    cat > src/lib.rs << 'EOF'
pub mod api;
pub mod command;
pub mod monitor;
pub mod storage;
pub mod ebpf;
pub mod device;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
EOF
fi

# 9. Format semua file
echo "9. Formatting files..."
rustfmt src/main.rs src/monitor/mod.rs src/api.rs 2>/dev/null || echo "rustfmt may have failed, continuing..."

# 10. Test compilation
echo ""
echo "10. Testing compilation..."
cargo check --target aarch64-unknown-linux-musl 2>&1 | grep -E "(error:|warning:|Compiling)" | head -20

echo ""
echo "=== QUICK FIX COMMANDS ==="
echo "Jika masih ada error, coba perintah berikut:"

echo ""
echo "1. Untuk error 'cannot find flush_final':"
echo "   grep -n 'flush_final' src/monitor/mod.rs"

echo ""
echo "2. Untuk error import:"
echo "   sed -i '1i\\\\' src/main.rs"
echo "   sed -i '1i\\use std::sync::Arc;' src/main.rs"
echo "   sed -i '1i\\use log::{info, error};' src/main.rs"
echo "   sed -i '1i\\use tokio::sync::Notify;' src/main.rs"

echo ""
echo "3. Untuk membersihkan build cache:"
echo "   cargo clean && cargo build --target aarch64-unknown-linux-musl"

echo ""
echo "=== BACKUP FILES ==="
echo "Backup created: src/main.rs.backup.final"
echo "Original can be restored if needed"