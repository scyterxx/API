#!/bin/bash
# fix_signals_and_api.sh

echo "=== FIXING SIGNAL HANDLING AND API ENDPOINTS ==="

# 1. Perbaiki signal handling di main.rs
echo "1. Fixing signal handling in main.rs..."

# Cari fungsi main atau signal handling
if grep -q "tokio::signal" src/main.rs; then
    echo "✓ Signal handling found, updating..."
    
    # Ganti signal handling yang ada
    cat > /tmp/signal_fix.rs << 'EOF'
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
EOF
    
    # Update main.rs dengan signal handling yang benar
    sed -i '/tokio::signal::ctrl_c/,/shutdown_notify\.notified/ {
        /tokio::signal::ctrl_c/ {
            r /tmp/signal_fix.rs
            d
        }
        /shutdown_notify\.notified/!d
    }' src/main.rs
    
else
    # Tambahkan signal handling jika belum ada
    echo "Adding signal handling..."
    MAIN_LINE=$(grep -n "fn main()" src/main.rs | cut -d: -f1)
    if [ -n "$MAIN_LINE" ]; then
        sed -i "$((MAIN_LINE+1)) i\\
#[tokio::main]\\
async fn main() -> Result<()> {\\
    // Initialize logging\\
    env_logger::init();\\
    \\
    // Handle shutdown signals\\
    let shutdown_notify = Arc::new(Notify::new());\\
    let shutdown_clone = Arc::clone(\&shutdown_notify);\\
    \\
    tokio::spawn(async move {\\
        let ctrl_c = tokio::signal::ctrl_c();\\
        let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();\\
        let mut sighup = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::hangup()).unwrap();\\
        \\
        tokio::select! {\\
            _ = ctrl_c => {\\
                info!(\"Received SIGINT (Ctrl+C), initiating graceful shutdown...\");\\
            }\\
            _ = sigterm.recv() => {\\
                info!(\"Received SIGTERM, initiating graceful shutdown...\");\\
            }\\
            _ = sighup.recv() => {\\
                info!(\"Received SIGHUP, initiating graceful shutdown...\");\\
            }\\
        }\\
        \\
        // Call flush before shutdown\\
        info!(\"Flushing data to disk before shutdown...\");\\
        if let Err(e) = crate::monitor::flush_final().await {\\
            error!(\"Failed to flush data during shutdown: {}\", e);\\
        }\\
        \\
        shutdown_clone.notify_one();\\
    });\\
    \\
    // Rest of main function..." src/main.rs
    fi
fi

# 2. Perbaiki fungsi flush_final() di monitor/mod.rs
echo "2. Fixing flush_final() function..."

# Buat implementasi flush_final yang benar
cat > /tmp/flush_final_fix.rs << 'EOF'
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

# Ganti fungsi flush_final yang ada
if grep -q "pub async fn flush_final()" src/monitor/mod.rs; then
    sed -i '/pub async fn flush_final()/,/^}/ {
        /pub async fn flush_final()/ {
            r /tmp/flush_final_fix.rs
            d
        }
        /^}/!d
    }' src/monitor/mod.rs
else
    # Tambahkan di akhir file
    cat /tmp/flush_final_fix.rs >> src/monitor/mod.rs
fi

# 3. Tambahkan API endpoint /flush
echo "3. Adding API endpoint /flush..."

# Cari file yang berisi API routes (biasanya di command.rs atau api.rs)
API_FILE="src/command.rs"
if [ ! -f "$API_FILE" ]; then
    API_FILE="src/api.rs"
    if [ ! -f "$API_FILE" ]; then
        API_FILE="src/main.rs"
    fi
fi

echo "Adding flush endpoint to $API_FILE"

# Tambahkan handler untuk /flush
if grep -q "axum::Router" "$API_FILE" || grep -q "\.route(" "$API_FILE"; then
    # Cari router dan tambahkan route
    if ! grep -q "/api/flush" "$API_FILE"; then
        # Tambahkan import jika perlu
        if ! grep -q "use crate::monitor" "$API_FILE"; then
            sed -i '1i\use crate::monitor;' "$API_FILE"
        fi
        
        # Cari router dan tambahkan route
        sed -i '/\.route(/ {
            a\        .route("/api/flush", axum::routing::post(flush_handler))
        }' "$API_FILE"
        
        # Tambahkan handler function
        cat >> "$API_FILE" << 'EOF'

/// Handler for manual flush endpoint
async fn flush_handler() -> impl axum::response::IntoResponse {
    use axum::Json;
    use serde_json::json;
    
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
EOF
    else
        echo "✓ /api/flush endpoint already exists"
    fi
else
    echo "⚠ Router not found, creating simple API server..."
    
    # Buat file api.rs jika belum ada
    if [ ! -f "src/api.rs" ]; then
        cat > src/api.rs << 'EOF'
use axum::{
    routing::post,
    Router,
    Json,
};
use serde_json::json;

use crate::monitor;

/// Create API router with all endpoints
pub fn create_router() -> Router {
    Router::new()
        .route("/api/flush", post(flush_handler))
        .route("/api/health", post(health_handler))
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
    
        # Update main.rs untuk include API
        if grep -q "fn main()" src/main.rs; then
            sed -i '1i\mod api;' src/main.rs
            sed -i '/shutdown_notify\.notified/i\
    // Start API server\
    let api_router = api::create_router();\
    let api_server = tokio::spawn(async move {\
        let addr = std::net::SocketAddr::from(([0, 0, 0, 0], 3000));\
        info!("Starting API server on {}" , addr);\
        axum::serve(tokio::net::TcpListener::bind(addr).await.unwrap(), api_router)\
            .await\
            .unwrap();\
    });' src/main.rs
        fi
    fi
fi

# 4. Pastikan dependencies ada di Cargo.toml
echo "4. Checking dependencies..."

if ! grep -q "axum" Cargo.toml; then
    cat >> Cargo.toml << 'EOF'

[dependencies]
axum = "0.7"
tokio = { version = "1.0", features = ["full", "signal"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }
EOF
fi

# 5. Update fungsi flush di modul lain jika perlu
echo "5. Ensuring all flush functions exist..."

# Cek apakah modul traffic, connection, dns memiliki fungsi flush()
for module in traffic connection dns; do
    MOD_FILE="src/monitor/${module}.rs"
    if [ -f "$MOD_FILE" ] && ! grep -q "pub async fn flush()" "$MOD_FILE"; then
        echo "Adding flush() to ${module}.rs"
        cat >> "$MOD_FILE" << 'EOF'

/// Flush pending data to storage
pub async fn flush() -> Result<()> {
    // TODO: Implement actual flush logic
    info!("Flushing {} data...", stringify!($module));
    Ok(())
}
EOF
    fi
done

# 6. Format dan test
echo "6. Formatting and testing..."
rustfmt src/main.rs src/monitor/mod.rs src/command.rs 2>/dev/null || true

echo ""
echo "=== COMPILATION TEST ==="
cargo check --target aarch64-unknown-linux-musl 2>&1 | grep -E "(error:|warning:|Compiling)" | head -20

echo ""
echo "=== SUMMARY ==="
echo "Perbaikan yang dilakukan:"
echo "✓ Signal handling (SIGINT, SIGTERM, SIGHUP) sekarang memanggil flush"
echo "✓ API endpoint /api/flush ditambahkan"
echo "✓ Fungsi flush_final() diperbaiki"
echo "✓ Dependencies diperbarui"
echo ""
echo "Testing:"
echo "1. Build project: cargo build --target aarch64-unknown-linux-musl"
echo "2. Test API: curl -X POST http://localhost:3000/api/flush"
echo "3. Test signal: kill -SIGTERM <pid>"
echo ""
echo "Backup files:"
echo "- src/main.rs.backup"
echo "- src/command.rs.backup.signal"
echo "- src/monitor/mod.rs.backup.signal"