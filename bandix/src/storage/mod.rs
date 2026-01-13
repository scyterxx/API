pub mod dns;
pub mod hostname;
pub mod traffic;

#[cfg(target_os = "linux")]
pub fn sync_barrier() {
    use std::os::unix::io::AsRawFd;
    if let Ok(dir) = std::fs::File::open(DATA_DIR) {
        unsafe { libc::syncfs(dir.as_raw_fd()); }
    }
}
