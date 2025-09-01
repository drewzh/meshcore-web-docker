#!/bin/sh

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

log "Starting MeshCore Web Docker container..."

# Run the update script to download/update the web application
log "Running MeshCore updater..."
if /app/scripts/update-meshcore.sh; then
    log "✅ Update script completed successfully"
    # Check what version we have after update
    current_target=$(readlink /app/web/current 2>/dev/null || echo "none")
    log "After update, current symlink points to: $current_target"
    if [ -f "/app/web/current/.version" ]; then
        log "Version file content: $(cat /app/web/current/.version)"
    else
        log "No version file found after update"
    fi
    
    # Check if we have any downloaded versions
    downloaded_versions=$(ls -1 /app/versions/ 2>/dev/null | grep -v "loading" | wc -l)
    log "Downloaded versions available: $downloaded_versions"
    if [ "$downloaded_versions" -gt 0 ]; then
        log "Available versions: $(ls -1 /app/versions/ | grep -v loading | tr '\n' ' ')"
    fi
else
    log "⚠️ Update script failed, using fallback content"
fi

# Ensure we have a working symlink and version file
if [ ! -L "/app/web/current" ] || [ ! -d "/app/web/current" ]; then
    log "Creating symlink to loading page..."
    mkdir -p /app/web
    ln -sf /app/versions/loading /app/web/current
fi

# Ensure version file exists for the /version endpoint (only if pointing to loading page)
current_target=$(readlink /app/web/current 2>/dev/null || echo "")
if [[ "$current_target" == */loading ]] && [ ! -f "/app/web/current/.version" ]; then
    log "Creating temporary version file for loading page..."
    cat > /app/web/current/.version << 'EOF'
{"status":"loading","version":"loading-page","description":"MeshCore is downloading..."}
EOF
fi

log "Content verification:"
log "Current version points to: $(readlink /app/web/current)"
log "Files in current version: $(ls -A /app/web/current | wc -l)"
log "Index file present: $([ -f /app/web/current/index.html ] && echo "Yes" || echo "No")"

log "Web content is ready, starting nginx..."
log "🌐 MeshCore web server starting on port 80 (container internal)"
log "📡 Access the application via your configured port mapping (e.g., http://localhost:8080)"

# Start nginx in the foreground
exec nginx -g "daemon off;"
