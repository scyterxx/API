pub mod dns;
pub mod hostname;
pub mod traffic;

pub const DATA_DIR: &str = "bandix-data";

#[cfg(target_os = "linux")]
pub fn sync_barrier() {
    use std::os::unix::io::AsRawFd;
    
    // Pastikan folder DATA_DIR ada sebelum mencoba membukanya
    if let Ok(dir) = std::fs::File::open(DATA_DIR) {
        unsafe { 
            // syncfs akan mensinkronisasi semua data yang tertunda 
            // pada filesystem tempat DATA_DIR berada.
            libc::syncfs(dir.as_raw_fd()); 
        }
        log::debug!("Storage: Sync barrier executed for {}", DATA_DIR);
    } else {
        // Jika folder belum ada, gunakan sync global sebagai fallback (opsional)
        unsafe { libc::sync(); }
    }
}

#[cfg(not(target_os = "linux"))]
pub fn sync_barrier() {
    // Fallback untuk OS lain (macOS/Windows) jika diperlukan saat dev
}