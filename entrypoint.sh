#!/bin/sh

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

log "Starting MeshCore Web Docker container..."

# Show initial directory structure for debugging
log "Initial directory structure:"
log "Versions directory:"
ls -la /app/versions/ 2>/dev/null || log "No versions directory found"
log "Web directory:"
ls -la /app/web/ 2>/dev/null || log "No web directory found"

# Run the update script to download/update the web application
log "Running MeshCore updater..."
if ! /app/scripts/update-meshcore.sh; then
    log "WARNING: Update script failed, checking for fallback content..."
fi

# Check if we have web content via the current symlink
log "Checking for current version symlink..."
if [ ! -L "/app/web/current" ] || [ ! -d "/app/web/current" ]; then
    log "ERROR: No current version symlink found or target directory missing"
    log "Available versions:"
    ls -la /app/versions/ 2>/dev/null || echo "No versions directory"
    log "Web directory contents:"
    ls -la /app/web/ 2>/dev/null || echo "No web directory"
    
    # Try to create a symlink to loading version if it exists
    if [ -d "/app/versions/loading" ]; then
        log "Found loading version, creating symlink..."
        mkdir -p /app/web
        ln -sf /app/versions/loading /app/web/current
    else
        log "No loading version found either"
        exit 1
    fi
fi

# Verify the current version has content
if [ -z "$(ls -A /app/web/current 2>/dev/null)" ]; then
    log "ERROR: Current version directory is empty"
    log "Current symlink points to:"
    ls -la /app/web/current 2>/dev/null || echo "Cannot read current symlink"
    exit 1
fi

log "Content verification:"
log "Current version points to: $(readlink /app/web/current)"
log "Files in current version: $(ls -A /app/web/current | wc -l)"
log "Index file present: $([ -f /app/web/current/index.html ] && echo "Yes" || echo "No")"

log "Web content is ready, starting nginx..."

# Start nginx in the foreground
exec nginx -g "daemon off;"
