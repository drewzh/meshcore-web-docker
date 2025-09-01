#!/bin/sh

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

log "Starting MeshCore Web Docker container..."

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
log "🌐 MeshCore web server starting on port 80 (container internal)"
log "📡 Access the application via your configured port mapping (e.g., http://localhost:8080)"

# Start nginx in the foreground
exec nginx -g "daemon off;"
