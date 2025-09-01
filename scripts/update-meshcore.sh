#!/bin/bash

set -e

MESHCORE_URL="https://app.meshcore.nz"
VERSIONS_DIR="/app/versions"
WEB_DIR="/app/web"
CURRENT_LINK="$WEB_DIR/current"

# Source the download functions
source /app/scripts/download-meshcore.sh

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] UPDATE: $1"
}

# Function to get current version info
get_current_version() {
    if [ -L "$CURRENT_LINK" ] && [ -f "$CURRENT_LINK/.version" ]; then
        local version_info
        version_info=$(cat "$CURRENT_LINK/.version" 2>/dev/null || echo '{}')
        echo "$version_info" | grep '"version"' | sed 's/.*"version": *"\([^"]*\)".*/\1/' || echo "unknown"
    else
        echo "none"
    fi
}

# Function to get available versions
list_versions() {
    if [ -d "$VERSIONS_DIR" ]; then
        find "$VERSIONS_DIR" -maxdepth 1 -type d -name "*" ! -name "." ! -name ".." -exec basename {} \; | sort
    fi
}

# Function to switch to a specific version
switch_version() {
    local version="$1"
    local version_dir="$VERSIONS_DIR/$version"
    
    if [ ! -d "$version_dir" ]; then
        log "ERROR: Version directory not found: $version_dir"
        return 1
    fi
    
    # Validate the version before switching
    if ! validate_download "$version_dir"; then
        log "ERROR: Version $version failed validation, not switching"
        return 1
    fi
    
    log "Switching to version: $version"
    
    # Create web directory if it doesn't exist
    mkdir -p "$WEB_DIR"
    
    # Remove old symlink and create new one atomically
    local temp_link="$CURRENT_LINK.tmp.$$"
    ln -sf "$version_dir" "$temp_link"
    mv "$temp_link" "$CURRENT_LINK"
    
    log "Successfully switched to version: $version"
    return 0
}

# Function to cleanup old versions (keep last 3)
cleanup_old_versions() {
    log "Cleaning up old versions..."
    
    local current_version
    current_version=$(get_current_version)
    
    # Get all versions except current, sorted by name (which includes timestamp)
    local versions_to_delete
    versions_to_delete=$(list_versions | grep -v "^$current_version$" | grep -v "^build-time$" | head -n -2)
    
    if [ -n "$versions_to_delete" ]; then
        while IFS= read -r version; do
            if [ -n "$version" ] && [ "$version" != "$current_version" ] && [ "$version" != "build-time" ]; then
                log "Removing old version: $version"
                rm -rf "$VERSIONS_DIR/$version"
            fi
        done <<< "$versions_to_delete"
    else
        log "No old versions to clean up"
    fi
}

# Function to ensure we have a working version
ensure_working_version() {
    log "Ensuring we have a working version..."
    
    # Check if current symlink exists and points to valid content
    if [ -L "$CURRENT_LINK" ] && [ -d "$CURRENT_LINK" ] && validate_download "$CURRENT_LINK"; then
        local current_version
        current_version=$(get_current_version)
        log "Current version '$current_version' is valid"
        return 0
    fi
    
    log "Current version is invalid or missing, looking for alternatives..."
    
    # Try to find any valid version
    local versions
    versions=$(list_versions)
    
    if [ -n "$versions" ]; then
        while IFS= read -r version; do
            if [ -n "$version" ]; then
                local version_dir="$VERSIONS_DIR/$version"
                if validate_download "$version_dir"; then
                    log "Found valid version: $version"
                    switch_version "$version"
                    return 0
                else
                    log "Version $version is invalid, removing..."
                    rm -rf "$version_dir"
                fi
            fi
        done <<< "$versions"
    fi
    
    log "ERROR: No valid versions found!"
    return 1
}

# Function to attempt update
attempt_update() {
    log "Attempting to update MeshCore web application..."
    
    # Test if site is reachable
    if ! test_site_reachable; then
        log "MeshCore site is not reachable, skipping update"
        return 1
    fi
    
    # Create new version directory
    local new_version
    new_version="runtime-$(date '+%Y%m%d-%H%M%S')"
    local new_version_dir="$VERSIONS_DIR/$new_version"
    
    log "Downloading new version: $new_version"
    
    # Attempt download to staging area
    if download_meshcore "$new_version_dir" "$new_version"; then
        log "Download successful, switching to new version"
        if switch_version "$new_version"; then
            log "Update completed successfully"
            cleanup_old_versions
            return 0
        else
            log "Failed to switch to new version, cleaning up"
            rm -rf "$new_version_dir"
            return 1
        fi
    else
        log "Download failed, keeping current version"
        rm -rf "$new_version_dir" 2>/dev/null || true
        return 1
    fi
}

# Function to show status
show_status() {
    log "=== MeshCore Web Application Status ==="
    
    local current_version
    current_version=$(get_current_version)
    log "Current version: $current_version"
    
    if [ -f "$CURRENT_LINK/.version" ]; then
        local version_info
        version_info=$(cat "$CURRENT_LINK/.version" 2>/dev/null || echo "No version info available")
        log "Version details: $version_info"
    fi
    
    local versions
    versions=$(list_versions)
    if [ -n "$versions" ]; then
        log "Available versions:"
        while IFS= read -r version; do
            if [ -n "$version" ]; then
                local marker=""
                if [ "$version" = "$current_version" ]; then
                    marker=" (current)"
                fi
                log "  - $version$marker"
            fi
        done <<< "$versions"
    else
        log "No versions available"
    fi
    
    log "====================================="
}

# Main function
main() {
    log "MeshCore web application updater starting..."
    
    # Create directories
    mkdir -p "$VERSIONS_DIR" "$WEB_DIR"
    
    # Show current status
    show_status
    
    # Ensure we have a working version first
    if ! ensure_working_version; then
        log "CRITICAL: No working version available and cannot establish one"
        exit 1
    fi
    
    # Attempt to update (this is non-critical - if it fails, we keep the current version)
    if attempt_update; then
        log "Update check completed successfully"
    else
        log "Update attempt failed, continuing with current version"
    fi
    
    # Final status check
    show_status
    
    # Verify we still have a working version
    if ! ensure_working_version; then
        log "CRITICAL: Lost working version during update process"
        exit 1
    fi
    
    log "MeshCore web application is ready to serve"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
