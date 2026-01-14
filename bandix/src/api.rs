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
