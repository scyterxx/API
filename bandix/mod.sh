#!/bin/bash
# fix_all_errors.sh

echo "=== FIXING ALL COMPILATION ERRORS ==="

# Backup semua file
cp src/command.rs src/command.rs.backup
cp src/monitor/mod.rs src/monitor/mod.rs.backup2

echo "1. Fixing duplicate definitions in command.rs..."
# Hapus duplikat FLUSH_IN_PROGRESS dan import duplikat
sed -i '9,9d' src/command.rs  # Hapus line 9 (FLUSH_IN_PROGRESS duplikat)
sed -i '6,6d' src/command.rs  # Hapus line 6 (import duplikat)

echo "2. Fixing missing imports in mod.rs..."
# Tambahkan import Ordering jika belum ada
if ! grep -q "use std::sync::atomic::Ordering" src/monitor/mod.rs; then
    # Cari line dengan use statement dan tambahkan di sana
    USE_LINE=$(grep -n "use std::sync::atomic" src/monitor/mod.rs | head -1 | cut -d: -f1)
    if [ -n "$USE_LINE" ]; then
        sed -i "${USE_LINE}a\use std::sync::atomic::Ordering;" src/monitor/mod.rs
    else
        # Tambahkan di bagian atas file setelah mod declarations
        MOD_LINE=$(grep -n "^mod" src/monitor/mod.rs | head -1 | cut -d: -f1)
        if [ -n "$MOD_LINE" ]; then
            sed -i "${MOD_LINE}i\use std::sync::atomic::Ordering;" src/monitor/mod.rs
        else
            # Tambahkan di line 1
            sed -i '1i\use std::sync::atomic::Ordering;' src/monitor/mod.rs
        fi
    fi
fi

echo "3. Fixing module imports in command.rs..."
# Perbaiki use statement untuk traffic, connection, dns
if grep -q "traffic::flush" src/command.rs; then
    # Cek apakah sudah ada import yang benar
    if ! grep -q "use crate::monitor::traffic" src/command.rs; then
        # Tambahkan import di atas fungsi yang menggunakan traffic
        TRAFFIC_LINE=$(grep -n "traffic::flush" src/command.rs | head -1 | cut -d: -f1)
        sed -i "${TRAFFIC_LINE}i\use crate::monitor::traffic;" src/command.rs
    fi
fi

if grep -q "connection::flush" src/command.rs; then
    if ! grep -q "use crate::monitor::connection" src/command.rs; then
        CONN_LINE=$(grep -n "connection::flush" src/command.rs | head -1 | cut -d: -f1)
        sed -i "${CONN_LINE}i\use crate::monitor::connection;" src/command.rs
    fi
fi

if grep -q "dns::flush" src/command.rs; then
    if ! grep -q "use crate::monitor::dns" src/command.rs; then
        DNS_LINE=$(grep -n "dns::flush" src/command.rs | head -1 | cut -d: -f1)
        sed -i "${DNS_LINE}i\use crate::monitor::dns;" src/command.rs
    fi
fi

echo "4. Fixing storage module reference..."
# Perbaiki storage::sync_barrier di mod.rs
if grep -q "storage::sync_barrier" src/monitor/mod.rs; then
    if ! grep -q "use crate::storage" src/monitor/mod.rs && ! grep -q "use super::storage" src/monitor/mod.rs; then
        # Coba tambahkan import storage
        STORAGE_LINE=$(grep -n "storage::sync_barrier" src/monitor/mod.rs | head -1 | cut -d: -f1)
        sed -i "${STORAGE_LINE}i\use crate::storage;" src/monitor/mod.rs
    fi
fi

echo "5. Fixing persist_all function..."
# Cari fungsi persist_all atau ganti dengan implementasi yang benar
if grep -q "persist_all()" src/monitor/mod.rs; then
    # Cek apakah ada mod persist atau fungsi lain
    # Untuk sementara, kita komentar atau implementasi sederhana
    PERSIST_LINE=$(grep -n "persist_all()" src/monitor/mod.rs | head -1 | cut -d: -f1)
    
    # Tampilkan context untuk debugging
    echo "Context around persist_all (line ${PERSIST_LINE}):"
    sed -n "$((PERSIST_LINE-2)),$((PERSIST_LINE+2))p" src/monitor/mod.rs
    
    # Tanya user apa yang harus dilakukan
    echo ""
    read -p "Fungsi persist_all() tidak ditemukan. Apa yang ingin dilakukan? 
    1. Komentar line ini
    2. Ganti dengan implementasi kosong
    3. Lihat dulu konteks lengkap
    Pilihan [3]: " choice
    
    case $choice in
        1)
            sed -i "${PERSIST_LINE}s/^/\/\//" src/monitor/mod.rs
            echo "Line dikomentari"
            ;;
        2)
            sed -i "${PERSIST_LINE}s/persist_all()\.await;/\/\/ TODO: Implement persist_all/" src/monitor/mod.rs
            echo "Diganti dengan TODO"
            ;;
        3)
            sed -n "$((PERSIST_LINE-10)),$((PERSIST_LINE+5))p" src/monitor/mod.rs
            echo "Silakan perbaiki manual"
            exit 1
            ;;
        *)
            sed -i "${PERSIST_LINE}s/^/\/\//" src/monitor/mod.rs
            echo "Default: line dikomentari"
            ;;
    esac
fi

echo "6. Running rustfmt..."
rustfmt src/command.rs src/monitor/mod.rs 2>/dev/null || echo "rustfmt skipped"

echo "7. Testing compilation..."
cargo check --target aarch64-unknown-linux-musl 2>&1 | grep -E "(error|warning|Compiling)" | head -20

echo ""
echo "=== BACKUP INFORMATION ==="
echo "Original command.rs: src/command.rs.backup"
echo "Original mod.rs: src/monitor/mod.rs.backup2"
echo ""
echo "Jika masih error, lihat diff:"
echo "diff -u src/command.rs.backup src/command.rs"
echo "diff -u src/monitor/mod.rs.backup2 src/monitor/mod.rs"