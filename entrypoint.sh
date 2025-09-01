#!/bin/sh

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

log "Starting MeshCore Web Docker container..."

# Handle Unraid PUID/PGID for appdata compatibility
if [ -n "$PUID" ] && [ -n "$PGID" ]; then
    log "Setting up user permissions for Unraid (PUID: $PUID, PGID: $PGID)"
    
    # Create user/group if they don't exist
    if ! getent group "$PGID" >/dev/null 2>&1; then
        addgroup -g "$PGID" meshcore 2>/dev/null || true
    fi
    
    if ! getent passwd "$PUID" >/dev/null 2>&1; then
        adduser -u "$PUID" -G "$(getent group "$PGID" | cut -d: -f1)" -s /bin/sh -D meshcore 2>/dev/null || true
    fi
    
    # Ensure the user can access the app directories
    chown -R "$PUID:$PGID" /app 2>/dev/null || true
    
    log "User permissions configured"
else
    log "No PUID/PGID specified, running as root"
fi

# Configure HTTPS support
ENABLE_HTTPS="${ENABLE_HTTPS:-false}"
log "HTTPS configuration: $ENABLE_HTTPS"

# Start with the base nginx configuration
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

if [ "$ENABLE_HTTPS" = "true" ]; then
    log "Enabling HTTPS support..."
    
    # Generate SSL certificates if they don't exist
    if [ ! -f "/etc/nginx/ssl/nginx.crt" ] || [ ! -f "/etc/nginx/ssl/nginx.key" ]; then
        log "Generating self-signed SSL certificates..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /etc/nginx/ssl/nginx.key \
            -out /etc/nginx/ssl/nginx.crt \
            -subj "/C=US/ST=State/L=City/O=MeshCore/CN=localhost" \
            -extensions v3_req \
            -config <(echo "[req]"; echo "distinguished_name = req_distinguished_name"; echo "[v3_req]"; echo "subjectAltName = @alt_names"; echo "[alt_names]"; echo "DNS.1 = localhost"; echo "IP.1 = 127.0.0.1")
        
        # Set appropriate permissions
        chmod 600 /etc/nginx/ssl/nginx.key
        chmod 644 /etc/nginx/ssl/nginx.crt
        
        log "SSL certificates generated successfully"
    else
        log "SSL certificates already exist, skipping generation"
    fi
    
    # Add HTTPS server block to nginx configuration
    HTTPS_CONFIG='
    # HTTPS server (required for Bluetooth Web API)
    server {
        listen 443 ssl http2;
        server_name localhost;
        root /app/web/current;
        index index.html index.htm;

        # SSL configuration
        ssl_certificate /etc/nginx/ssl/nginx.crt;
        ssl_certificate_key /etc/nginx/ssl/nginx.key;
        
        # SSL security settings
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384;
        ssl_prefer_server_ciphers off;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # Security headers (enhanced for HTTPS)
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Content-Security-Policy "default-src '\''self'\'' http: https: data: blob: '\''unsafe-inline'\''" always;

        # Handle static files
        location / {
            try_files $uri $uri/ /index.html;
            expires 1h;
            add_header Cache-Control "public, immutable";
        }

        # Handle specific file types with appropriate caching
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Version info endpoint
        location /version {
            access_log off;
            alias /app/web/current/.version;
            add_header Content-Type application/json;
        }

        # Handle favicon
        location = /favicon.ico {
            log_not_found off;
            access_log off;
        }

        # Handle robots.txt
        location = /robots.txt {
            log_not_found off;
            access_log off;
        }

        # Deny access to hidden files and version info
        location ~ /\. {
            deny all;
        }
        
        location ~ /\.version$ {
            deny all;
        }
    }'
    
    # Replace the placeholder with the HTTPS configuration
    sed -i "s|# HTTPS_SERVER_PLACEHOLDER|$HTTPS_CONFIG|" /etc/nginx/nginx.conf
    
    log "HTTPS server block added to nginx configuration"
else
    log "HTTPS disabled - running HTTP only mode"
    # Remove the placeholder line
    sed -i "/# HTTPS_SERVER_PLACEHOLDER/d" /etc/nginx/nginx.conf
fi

# Environment variables for MeshCore download
export MESHCORE_BASE_URL="${MESHCORE_BASE_URL:-https://files.liamcottle.net/MeshCore}"

log "Using MeshCore Base URL: $MESHCORE_BASE_URL"

# Run the new zip-based downloader
log "Running MeshCore zip downloader..."
if /app/scripts/download-zip.sh; then
    log "✅ Download completed successfully"
else
    log "⚠️ Download failed, using fallback content"
fi

# Final verification
if [ -L "/app/web/current" ] && [ -d "/app/web/current" ]; then
    current_target=$(readlink /app/web/current)
    log "Current version: $(basename "$current_target")"
    if [ -f "/app/web/current/.version" ]; then
        log "Version details: $(cat /app/web/current/.version)"
    fi
else
    log "ERROR: No valid web content available"
    exit 1
fi

log "Content verification:"
log "Files in current version: $(ls -A /app/web/current | wc -l)"
log "Index file present: $([ -f /app/web/current/index.html ] && echo "Yes" || echo "No")"

log "Web content is ready, starting nginx..."

if [ "$ENABLE_HTTPS" = "true" ]; then
    log "🌐 MeshCore web server starting with HTTPS enabled"
    log "📡 HTTP:  Access via your configured port mapping (e.g., http://localhost:8080)"
    log "🔒 HTTPS: Access via your configured port mapping (e.g., https://localhost:8443)"
    log "⚠️  IMPORTANT: Use HTTPS for Bluetooth Web API functionality"
else
    log "🌐 MeshCore web server starting (HTTP only)"
    log "📡 HTTP:  Access via your configured port mapping (e.g., http://localhost:8080)"
    log "⚠️  NOTE: HTTPS is required for Bluetooth Web API - use reverse proxy or set ENABLE_HTTPS=true"
fi

# Start nginx in the foreground
exec nginx -g "daemon off;"
