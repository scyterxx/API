pub mod api;
pub mod command;
pub mod monitor;
pub mod storage;
pub mod ebpf;
pub mod device;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;
