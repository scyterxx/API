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
