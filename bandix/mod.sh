#!/bin/bash
# PATCH SCRIPT UNTUK bandix API module
# Simpan sebagai: patch_api.sh

echo "Patching bandix API module..."

# 1. Backup file
cp src/api/mod.rs src/api/mod.rs.backup

# 2. Tambah port helper SETELAH use statements
# Cari baris terakhir use statements
USE_END=$(grep -n "use tokio::net::TcpStream;" src/api/mod.rs | cut -d: -f1)
if [ -n "$USE_END" ]; then
    sed -i "${USE_END}a\\
use std::sync::atomic::{AtomicU16, Ordering};\\
\\
static CURRENT_PORT: AtomicU16 = AtomicU16::new(0);\\
\\
/// Get current port for logging\\
pub fn get_port() -> u16 {\\
    CURRENT_PORT.load(Ordering::Relaxed)\\
}" src/api/mod.rs
fi

# 3. Tambah System variant ke ApiHandler enum
sed -i 's/Connection(crate::api::connection::ConnectionApiHandler),/Connection(crate::api::connection::ConnectionApiHandler),\
    System,/' src/api/mod.rs

# 4. Update module_name() method
sed -i '/ApiHandler::Connection(_) => "connection",/a\
            ApiHandler::System => "system",' src/api/mod.rs

# 5. Update supported_routes() method  
sed -i '/ApiHandler::Connection(handler) => handler.supported_routes(),/a\
            ApiHandler::System => vec!["/api/flush", "/api/shutdown"],' src/api/mod.rs

# 6. Update handle_request() method
sed -i '/ApiHandler::Connection(handler) => handler.handle_request(request).await,/a\
            ApiHandler::System => {\
                // System endpoints handled in route_request\
                Ok(HttpResponse::ok("System handler".into()))\
            }' src/api/mod.rs

# 7. GANTI FUNGSI route_request() DENGAN YANG BARU
# Buat file temporary dengan fungsi baru
cat > tmp/new_route_request.rs << 'EOF'
    /// Route a request to the appropriate handler
    pub async fn route_request(&self, request: &HttpRequest) -> Result<HttpResponse, anyhow::Error> {
        // ✅ SINGLE FLUSH PATH - API endpoints
        if request.path == "/api/flush" && request.method == "POST" {
            let port = get_port();
            log::info!("curl 127.0.0.1:{}/api/flush received", port);
            log::info!("Flushing traffic statistics while service keep running");
            
            match crate::command::flush_all(false).await {
                Ok(_) => {
                    return Ok(HttpResponse::ok(
                        r#"{"status":"success","message":"Data flushed, service continues"}"#.to_string()
                    ));
                }
                Err(e) => {
                    log::error!("API flush failed: {}", e);
                    return Ok(HttpResponse::error(500, format!("Flush failed: {}", e)));
                }
            }
        }
        
        // ✅ API SHUTDOWN endpoint
        if request.path == "/api/shutdown" && request.method == "POST" {
            log::info!("API shutdown request received");
            match crate::command::flush_all(true).await {
                Ok(_) => {
                    log::info!("Shutdown flush complete, exiting...");
                    std::process::exit(0);
                }
                Err(e) => {
                    log::error!("Shutdown flush failed: {}", e);
                    std::process::exit(1);
                }
            }
        }

        // Original routing logic
        for handler in self.handlers.values() {
            for route in handler.supported_routes() {
                if request.path.starts_with(route) {
                    return handler.handle_request(request).await;
                }
            }
        }

        Ok(HttpResponse::not_found())
    }
EOF

# Cari dan ganti fungsi route_request yang lama