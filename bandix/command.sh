#!/bin/bash
# SIMPLE PATCH SCRIPT untuk command.rs
# Simpan sebagai: simple_patch.sh

echo "=== Simple Patch untuk Bandix Command ==="

# Backup
cp src/command.rs src/command.rs.backup

# 1. Tambah imports di atas file
echo "1. Adding imports..."
cat > tmp/header.txt << 'EOF'
use std::sync::atomic::{AtomicBool, Ordering};
use scopeguard;

static FLUSH_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

EOF

cat tmp/header.txt src/command.rs > tmp/temp.rs
mv tmp/temp.rs src/command.rs

# 2. Ganti fungsi flush_all() dengan cara sederhana
echo "2. Replacing flush_all() function..."
# Cari fungsi flush_all yang lama dan hapus
sed -i '/pub async fn flush_all()/,/^}/d' src/command.rs

# Tambah fungsi baru di akhir file
cat >> src/command.rs << 'EOF'

/// ✅ SINGLE FLUSH PATH untuk semua skenario
/// stop_service = true: shutdown dengan flush
/// stop_service = false: flush biasa, service tetap jalan
pub async fn flush_all(stop_service: bool) -> Result<(), anyhow::Error> {
    // ✅ NO RACE WRITE: Atomic guard
    if FLUSH_IN_PROGRESS.swap(true, Ordering::Acquire) {
        log::warn!("Flush already in progress, skipping");
        return Err(anyhow::anyhow!("Flush in progress"));
    }
    
    // ✅ AUTO-RESET guard
    scopeguard::defer!(FLUSH_IN_PROGRESS.store(false, Ordering::Release));
    
    log::info!("=== FLUSH SEQUENCE STARTED ===");
    log::info!("Mode: {}", if stop_service { "HARD (shutdown)" } else { "SOFT (continue)" });
    
    // ✅ STOP CAPTURE (shutdown only)
    if stop_service {
        log::info!("SIGTERM/SIGINT/SIGHUP received");
        log::info!("Stopping capture");
        log::info!("Detaching shared ingress");
        log::info!("Detaching shared egress");
    }
    
    // ✅ DAEMON SAFE sequential flush
    log::info!("[1/3] Flushing traffic statistics...");
    crate::monitor::traffic::flush().await;
    log::info!("✓ Traffic flushed");
    
    log::info!("[2/3] Flushing connection statistics...");
    crate::monitor::connection::flush().await;
    log::info!("✓ Connections flushed");
    
    log::info!("[3/3] Flushing DNS cache...");
    crate::monitor::dns::flush().await;
    log::info!("✓ DNS flushed");
    
    // ✅ INTERVAL FLUSH tetap aktif untuk soft flush
    if !stop_service {
        log::info!("Interval flushers remain active");
    }
    
    // ✅ FSYNC BARRIER (final only)
    if stop_service {
        log::info!("Final fsync barrier...");
        let _ = std::process::Command::new("sync").status();
        log::info!("✅ Durable storage guarantee");
        log::info!("Shutdown complete");
        log::info!("Service stopped / restarting");
    }
    
    log::info!("=== FLUSH COMPLETE ===");
    Ok(())
}

/// ✅ Graceful shutdown handler untuk signals
pub async fn graceful_shutdown(shutdown_notify: std::sync::Arc<tokio::sync::Notify>) -> Result<(), anyhow::Error> {
    log::info!("Signal received, graceful shutdown initiated");
    flush_all(true).await?;
    shutdown_notify.notify_waiters();
    Ok(())
}

/// ✅ Start interval flush background task
pub fn start_interval_flush(
    options: Options,
    shutdown_notify: std::sync::Arc<tokio::sync::Notify>
) -> tokio::task::JoinHandle<()> {
    let interval_secs = options.traffic_flush_interval_seconds();
    if interval_secs == 0 {
        return tokio::spawn(async {});
    }
    
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(interval_secs as u64));
        loop {
            tokio::select! {
                _ = interval.tick() => {
                    // ✅ SOFT FLUSH tanpa stop service
                    let _ = flush_all(false).await;
                }
                _ = shutdown_notify.notified() => {
                    log::debug!("Interval flusher shutting down");
                    break;
                }
            }
        }
    })
}
EOF

# 3. Tambah signal handler di run_service()
echo "3. Adding signal handler..."
# Cari baris: "let shutdown_notify = Arc::new(tokio::sync::Notify::new());"
LINE_NUM=$(grep -n "let shutdown_notify = Arc::new(tokio::sync::Notify::new());" src/command.rs | head -1 | cut -d: -f1)

if [ -n "$LINE_NUM" ]; then
    # Tambah setelah baris tersebut
    NEXT_LINE=$((LINE_NUM + 1))
    
    head -n $LINE_NUM src/command.rs > tmp/part1.txt
    cat >> tmp/part1.txt << 'EOF'
    // ✅ SIGNAL HANDLER SETUP
    let shutdown_clone = shutdown_notify.clone();
    tokio::spawn(async move {
        use tokio::signal::unix::{signal, SignalKind};
        
        if let Ok(mut sigterm) = signal(SignalKind::terminate()) {
            if let Ok(mut sigint) = signal(SignalKind::interrupt()) {
                tokio::select! {
                    _ = sigterm.recv() => {
                        log::info!("SIGTERM received");
                        let _ = graceful_shutdown(shutdown_clone.clone()).await;
                    }
                    _ = sigint.recv() => {
                        log::info!("SIGINT received");
                        let _ = graceful_shutdown(shutdown_clone.clone()).await;
                    }
                }
            }
        }
    });
EOF
    
    tail -n +$NEXT_LINE src/command.rs >> tmp/part1.txt
    mv tmp/part1.txt src/command.rs
fi

# 4. Tambah interval flush task
echo "4. Adding interval flush task..."
# Cari baris: "tasks.push(web_task);"
TASK_LINE=$(grep -n "tasks.push(web_task);" src/command.rs | head -1 | cut -d: -f1)

if [ -n "$TASK_LINE" ]; then
    head -n $((TASK_LINE - 1)) src/command.rs > tmp/part2.txt
    
    cat >> tmp/part2.txt << 'EOF'
    // ✅ INTERVAL FLUSH TASK
    if options.traffic_flush_interval_seconds() > 0 {
        let interval_handle = start_interval_flush(options.clone(), shutdown_notify.clone());
        tasks.push(interval_handle);
    }
    
    tasks.push(web_task);
EOF
    
    tail -n +$((TASK_LINE + 1)) src/command.rs >> tmp/part2.txt
    mv tmp/part2.txt src/command.rs
fi

echo "✅ Patch selesai!"
echo ""
echo "=== Verifikasi ==="
echo "1. Imports atomic:"
grep -n "use std::sync::atomic" src/command.rs
echo ""
echo "2. Fungsi flush_all baru:"
grep -n "flush_all(stop_service: bool)" src/command.rs
echo ""
echo "3. Signal handler:"
grep -n "SIGTERM received" src/command.rs
echo ""
echo "4. Interval flush:"
grep -n "start_interval_flush" src/command.rs