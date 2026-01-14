pub mod connection;
pub mod dns;
pub mod traffic;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use tokio::net::TcpStream;
use log::{error, debug};

/// API standar untuk response JSON
#[derive(Serialize, Deserialize)]
pub struct ApiResponse<T> {
    pub status: String,
    pub data: Option<T>,
    pub message: Option<String>,
}

impl<T> ApiResponse<T> {
    pub fn success(data: T) -> Self {
        Self {
            status: "success".to_string(),
            data: Some(data),
            message: None,
        }
    }

    pub fn error(message: String) -> Self {
        Self {
            status: "error".to_string(),
            data: None,
            message: Some(message),
        }
    }
}

/// Struktur HTTP Request sederhana untuk TcpListener manual
#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub method: String,
    pub path: String,
    pub query_params: HashMap<String, String>,
    pub body: Option<String>,
}

/// Struktur HTTP Response
#[derive(Debug)]
pub struct HttpResponse {
    pub status: u16,
    pub content_type: String,
    pub body: String,
}

impl HttpResponse {
    pub fn ok(body: String) -> Self {
        Self {
            status: 200,
            content_type: "application/json".to_string(),
            body,
        }
    }

    pub fn error(status: u16, message: String) -> Self {
        let err = ApiResponse::<()>::error(message);
        Self {
            status,
            content_type: "application/json".to_string(),
            body: serde_json::to_string(&err).unwrap_or_default(),
        }
    }

    pub fn not_found() -> Self {
        Self::error(404, "Not Found".to_string())
    }
}

/// Router untuk menangani permintaan API secara manual
#[derive(Clone)]
pub struct ApiRouter {
    // Di sini Anda bisa menambahkan state jika diperlukan (misal Arc<Context>)
}

impl ApiRouter {
    pub fn new() -> Self {
        Self {}
    }

    /// Fungsi utama untuk routing URL ke Handler
    pub async fn route_request(&self, req: &HttpRequest) -> Result<HttpResponse, anyhow::Error> {
        debug!("Routing request: {} {}", req.method, req.path);

        match (req.method.as_str(), req.path.as_str()) {
            // Route: Flush Data
            ("POST", "/api/flush") | ("GET", "/api/flush") => {
                crate::command::flush_all().await;
                Ok(HttpResponse::ok(r#"{"status":"success","message":"Flush completed"}"#.to_string()))
            },

            // Route: Traffic Monitoring
            ("GET", "/api/traffic/stats") => {
                // Implementasi di traffic.rs
                traffic::handle_get_stats().await
            },

            // Route: Connection Traffic (Perbaikan 404)
            ("GET", "/api/traffic/connections") => {
                connection::handle_get_connections().await
            },

            // Route: DNS Logs
            ("GET", "/api/dns/logs") => {
                dns::handle_get_logs().await
            },

            // Default 404
            _ => Ok(HttpResponse::not_found()),
        }
    }
}

/// Fungsi pembantu untuk parsing HTTP Raw string menjadi struct HttpRequest
pub fn parse_http_request(request_str: &str) -> Result<HttpRequest, anyhow::Error> {
    let lines: Vec<&str> = request_str.lines().collect();
    if lines.is_empty() {
        return Err(anyhow::anyhow!("Empty request"));
    }

    let first_line: Vec<&str> = lines[0].split_whitespace().collect();
    if first_line.len() < 2 {
        return Err(anyhow::anyhow!("Invalid request line"));
    }

    let method = first_line[0].to_string();
    let full_path = first_line[1].to_string();

    // Pisahkan path dan query params
    let parts: Vec<&str> = full_path.splitn(2, '?').collect();
    let path = parts[0].to_string();
    let mut query_params = HashMap::new();

    if parts.len() > 1 {
        for pair in parts[1].split('&') {
            let kv: Vec<&str> = pair.splitn(2, '=').collect();
            if kv.len() == 2 {
                query_params.insert(kv[0].to_string(), kv[1].to_string());
            }
        }
    }

    let body = if let Some(pos) = request_str.find("\r\n\r\n") {
        let b = &request_str[pos + 4..];
        if !b.is_empty() { Some(b.to_string()) } else { None }
    } else {
        None
    };

    Ok(HttpRequest {
        method,
        path,
        query_params,
        body,
    })
}

/// Mengirimkan raw response kembali ke TcpStream
pub async fn send_http_response(stream: &mut TcpStream, response: &HttpResponse) -> Result<(), anyhow::Error> {
    use tokio::io::AsyncWriteExt;

    let status_text = match response.status {
        200 => "OK",
        404 => "Not Found",
        500 => "Internal Server Error",
        _ => "Unknown",
    };

    let raw = format!(
        "HTTP/1.1 {} {}\r\n\
         Content-Type: {}\r\n\
         Content-Length: {}\r\n\
         Access-Control-Allow-Origin: *\r\n\
         Connection: close\r\n\
         \r\n\
         {}",
        response.status,
        status_text,
        response.content_type,
        response.body.len(),
        response.body
    );

    stream.write_all(raw.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

// Fungsi registrasi kosong agar tidak error saat dipanggil dari monitor/mod.rs
use crate::monitor;

pub fn register_flush(router: &mut ApiRouter) {
    router.post("/api/flush", |_| async {
        monitor::flush_all().await;
        ApiResponse::ok("flushed")
    });
}