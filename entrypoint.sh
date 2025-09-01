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
log "Current versions available:"
ls -la /app/versions/ 2>/dev/null || log "No versions directory found"

if /app/scripts/update-meshcore.sh; then
    log "✅ Update script completed successfully"
else
    log "⚠️ Update script failed or encountered issues"
fi

log "Post-update versions available:"
ls -la /app/versions/ 2>/dev/null || log "No versions directory found"

# Check if we have web content via the current symlink
log "Checking for current version symlink..."
if [ ! -L "/app/web/current" ] || [ ! -d "/app/web/current" ]; then
    log "ERROR: No current version symlink found or target directory missing"
    log "Available versions:"
    ls -la /app/versions/ 2>/dev/null || echo "No versions directory"
    log "Web directory contents:"
    ls -la /app/web/ 2>/dev/null || echo "No web directory"
    
    # Try to recreate the symlink to loading page
    log "Attempting to recreate symlink to loading page..."
    mkdir -p /app/web
    ln -sf /app/versions/loading /app/web/current
fi

# Debug: Check symlink and version file status
log "Symlink verification:"
log "Current symlink exists: $([ -L /app/web/current ] && echo "Yes" || echo "No")"
log "Current symlink target: $(readlink /app/web/current 2>/dev/null || echo "None")"
log "Target directory exists: $([ -d /app/web/current ] && echo "Yes" || echo "No")"
log "Version file exists: $([ -f /app/web/current/.version ] && echo "Yes" || echo "No")"
if [ -f /app/web/current/.version ]; then
    log "Version file content: $(cat /app/web/current/.version)"
else
    log "Version file location should be: /app/web/current/.version"
    log "Checking if loading version file exists: $([ -f /app/versions/loading/.version ] && echo "Yes" || echo "No")"
    if [ -f /app/versions/loading/.version ]; then
        log "Loading version file content: $(cat /app/versions/loading/.version)"
    fi
fi
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
log "🌐 MeshCore web server starting on port 80 (container internal)"
log "📡 Access the application via your configured port mapping (e.g., http://localhost:8080)"

# Start nginx in the foreground
exec nginx -g "daemon off;"
