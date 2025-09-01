#!/bin/bash

set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ENTRYPOINT: $1"
}

log "Starting MeshCore Web Docker container..."

# Run the update script to download/update the web application
log "Running MeshCore updater..."
/app/scripts/update-meshcore.sh

# Check if we have web content
if [ ! -d "/app/web" ] || [ -z "$(ls -A /app/web 2>/dev/null)" ]; then
    log "ERROR: No web content found after update attempt"
    exit 1
fi

log "Web content is ready, starting nginx..."

# Start nginx in the foreground
exec nginx -g "daemon off;"
