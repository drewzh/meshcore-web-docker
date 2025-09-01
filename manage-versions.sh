#!/bin/bash

# MeshCore Version Management Utility
# This script helps manage versions of the MeshCore web application

set -e

CONTAINER_NAME="meshcore-web-docker_meshcore-web_1"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $1" >&2
}

# Function to check if container is running
check_container() {
    if ! docker ps --format "table {{.Names}}" | grep -q "$CONTAINER_NAME"; then
        # Try alternative container name format
        CONTAINER_NAME=$(docker ps --format "table {{.Names}}" | grep "meshcore-web" | head -1 || echo "")
        if [ -z "$CONTAINER_NAME" ]; then
            error "MeshCore container is not running. Start it with: ./test.sh start"
            exit 1
        fi
    fi
}

# Function to list available versions
list_versions() {
    check_container
    log "Available versions:"
    docker exec "$CONTAINER_NAME" find /app/versions -maxdepth 1 -type d -name "*" ! -name "." ! -name ".." -exec basename {} \; | sort
}

# Function to show current version
show_current() {
    check_container
    log "Current version information:"
    docker exec "$CONTAINER_NAME" cat /app/web/current/.version 2>/dev/null || echo "No version info available"
}

# Function to switch to a specific version
switch_version() {
    local version="$1"
    if [ -z "$version" ]; then
        error "Please specify a version to switch to"
        echo "Available versions:"
        list_versions
        exit 1
    fi
    
    check_container
    log "Switching to version: $version"
    
    if docker exec "$CONTAINER_NAME" /app/scripts/update-meshcore.sh switch "$version"; then
        log "Successfully switched to version: $version"
        log "Reloading nginx..."
        docker exec "$CONTAINER_NAME" nginx -s reload
    else
        error "Failed to switch to version: $version"
        exit 1
    fi
}

# Function to force update
force_update() {
    check_container
    log "Forcing update of MeshCore web application..."
    
    if docker exec "$CONTAINER_NAME" /app/scripts/update-meshcore.sh update; then
        log "Update completed successfully"
        log "Reloading nginx..."
        docker exec "$CONTAINER_NAME" nginx -s reload
    else
        error "Update failed"
        exit 1
    fi
}

# Function to validate current version
validate_current() {
    check_container
    log "Validating current version..."
    
    if docker exec "$CONTAINER_NAME" /app/scripts/download-meshcore.sh validate /app/web/current; then
        log "Current version is valid"
    else
        error "Current version is invalid"
        exit 1
    fi
}

# Function to show detailed status
show_status() {
    check_container
    log "=== MeshCore Web Application Status ==="
    
    # Current version
    echo ""
    log "Current version:"
    docker exec "$CONTAINER_NAME" cat /app/web/current/.version 2>/dev/null || echo "No version info available"
    
    # Available versions
    echo ""
    log "Available versions:"
    docker exec "$CONTAINER_NAME" find /app/versions -maxdepth 1 -type d -name "*" ! -name "." ! -name ".." -exec basename {} \; | sort | while read -r ver; do
        local current_marker=""
        if docker exec "$CONTAINER_NAME" readlink /app/web/current | grep -q "$ver"; then
            current_marker=" (current)"
        fi
        echo "  - $ver$current_marker"
    done
    
    # Disk usage
    echo ""
    log "Disk usage:"
    docker exec "$CONTAINER_NAME" du -sh /app/versions/* 2>/dev/null || echo "No versions found"
    
    # Container info
    echo ""
    log "Container information:"
    docker ps --filter "name=meshcore-web" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    log "======================================"
}

# Function to cleanup old versions
cleanup() {
    check_container
    log "Cleaning up old versions (keeping current + 2 most recent)..."
    
    docker exec "$CONTAINER_NAME" /app/scripts/update-meshcore.sh cleanup
    log "Cleanup completed"
}

# Function to show help
show_help() {
    echo "MeshCore Version Management Utility"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                    - List all available versions"
    echo "  current                 - Show current version information"
    echo "  switch <version>        - Switch to a specific version"
    echo "  update                  - Force update to latest version"
    echo "  validate               - Validate current version"
    echo "  status                 - Show detailed status information"
    echo "  cleanup                - Remove old versions (keep current + 2 recent)"
    echo "  help                   - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 current"
    echo "  $0 switch build-time"
    echo "  $0 update"
    echo "  $0 status"
    echo ""
}

# Main command handler
case "${1:-help}" in
    "list")
        list_versions
        ;;
    "current")
        show_current
        ;;
    "switch")
        switch_version "$2"
        ;;
    "update")
        force_update
        ;;
    "validate")
        validate_current
        ;;
    "status")
        show_status
        ;;
    "cleanup")
        cleanup
        ;;
    "help"|*)
        show_help
        ;;
esac
