#!/bin/bash

set -e

MESHCORE_URL="https://app.meshcore.nz"
VERSIONS_DIR="/app/versions"
WEB_DIR="/app/web"
CURRENT_LINK="$WEB_DIR/current"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] UPDATE: $1"
}

# Function to test if MeshCore site is reachable
test_site_reachable() {
    log "Testing if MeshCore site is reachable..."
    
    if curl --silent --head --fail --max-time 10 "$MESHCORE_URL" > /dev/null 2>&1; then
        log "MeshCore site is reachable"
        return 0
    else
        log "MeshCore site is not reachable"
        return 1
    fi
}

# Function to validate downloaded content (copied from download-meshcore.sh)
validate_download() {
    local dir="$1"
    
    log "Validating content in $dir..."
    
    # Check if directory exists and is not empty
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        log "ERROR: Directory is empty or doesn't exist"
        return 1
    fi
    
    # Check for index.html or index.htm
    if [ ! -f "$dir/index.html" ] && [ ! -f "$dir/index.htm" ]; then
        log "ERROR: No index.html or index.htm found"
        return 1
    fi
    
    local index_file
    if [ -f "$dir/index.html" ]; then
        index_file="$dir/index.html"
    else
        index_file="$dir/index.htm"
    fi
    
    # Check if index file has reasonable content (not just an error page)
    local file_size
    file_size=$(stat -c%s "$index_file" 2>/dev/null || stat -f%z "$index_file" 2>/dev/null || echo "0")
    
    if [ "$file_size" -lt 100 ]; then
        log "ERROR: Index file is too small ($file_size bytes), likely an error page"
        return 1
    fi
    
    # Check for HTML content
    if ! grep -qi "html\|<title\|<head\|<body" "$index_file"; then
        log "ERROR: Index file doesn't appear to contain valid HTML"
        return 1
    fi
    
    # Check for error indicators
    if grep -qi "error\|not found\|404\|500\|503" "$index_file"; then
        log "WARNING: Index file may contain error content"
        # Don't fail on this, as the app might legitimately contain these words
    fi
    
    # Count files to ensure we got a reasonable amount of content
    local file_count
    file_count=$(find "$dir" -type f | wc -l | tr -d ' ')
    
    if [ "$file_count" -lt 1 ]; then
        log "ERROR: Too few files downloaded ($file_count), this doesn't look like a complete web application"
        return 1
    fi
    
    log "Validation passed: $file_count files, index file size: $file_size bytes"
    return 0
}

# Function to download the web application to a specific directory
download_meshcore() {
    local target_dir="$1"
    local version_name="${2:-$(date '+%Y%m%d-%H%M%S')}"
    
    log "Starting download of MeshCore web application to $target_dir..."
    
    # Create target directory
    mkdir -p "$target_dir"
    
    # Create temporary directory for download
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Cleanup function
    cleanup() {
        log "Cleaning up temporary directory: $temp_dir"
        rm -rf "$temp_dir"
    }
    trap cleanup EXIT
    
    log "Using temporary directory: $temp_dir"
    
    # Download the main page and all linked resources
    log "Downloading main page and linked resources..."
    if ! wget --quiet --page-requisites --html-extension --convert-links \
         --domains=app.meshcore.nz --no-parent --directory-prefix="$temp_dir" \
         --user-agent="Mozilla/5.0 (compatible; MeshCore-Docker/1.0)" \
         --timeout=30 --tries=3 --retry-connrefused \
         --adjust-extension --backup-converted \
         "$MESHCORE_URL/"; then
        log "ERROR: Failed to download main page"
        return 1
    fi
    
    # Try to download common static assets that might not be linked directly
    log "Downloading additional static assets..."
    local common_paths=(
        "/favicon.ico"
        "/manifest.json"
        "/robots.txt"
        "/sitemap.xml"
        "/sw.js"
        "/service-worker.js"
        "/apple-touch-icon.png"
        "/icon-192x192.png"
        "/icon-512x512.png"
    )
    
    for path in "${common_paths[@]}"; do
        wget --quiet --timeout=10 --tries=1 \
             --directory-prefix="$temp_dir/app.meshcore.nz" \
             --no-check-certificate \
             "$MESHCORE_URL$path" 2>/dev/null || true
    done
    
    # Verify we have the downloaded content
    local source_dir="$temp_dir/app.meshcore.nz"
    if [ ! -d "$source_dir" ]; then
        log "ERROR: Downloaded content not found in expected location: $source_dir"
        return 1
    fi
    
    # Validate the download
    log "Validating downloaded content..."
    if ! validate_download "$source_dir"; then
        log "ERROR: Downloaded content failed validation"
        return 1
    fi
    
    # Move validated content to target directory
    log "Moving validated content to target directory..."
    rm -rf "$target_dir"
    mv "$source_dir" "$target_dir"
    
    # Create version info file
    cat > "$target_dir/.version" << EOF
{
    "version": "$version_name",
    "downloaded_at": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
    "source_url": "$MESHCORE_URL",
    "download_method": "wget"
}
EOF
    
    log "Download completed successfully to $target_dir"
    return 0
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
    
    # Get all versions except current and loading, sorted by name (which includes timestamp)
    local versions_to_delete
    versions_to_delete=$(list_versions | grep -v "^$current_version$" | grep -v "^loading$" | head -n -2)
    
    if [ -n "$versions_to_delete" ]; then
        while IFS= read -r version; do
            if [ -n "$version" ] && [ "$version" != "$current_version" ] && [ "$version" != "loading" ]; then
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
    if [ -L "$CURRENT_LINK" ] && [ -d "$CURRENT_LINK" ]; then
        local current_version
        current_version=$(get_current_version)
        
        # If we're pointing to the loading page, that's okay for initial startup
        if [[ "$CURRENT_LINK" == */loading ]] || [[ "$(readlink "$CURRENT_LINK")" == */loading ]]; then
            log "Currently showing loading page - will attempt to download actual application"
            return 0
        fi
        
        # For actual app versions, validate them
        if validate_download "$CURRENT_LINK"; then
            log "Current version '$current_version' is valid"
            return 0
        fi
    fi
    
    log "Current version is invalid or missing, looking for alternatives..."
    
    # Try to find any valid version (excluding loading page)
    local versions
    versions=$(list_versions | grep -v "^loading$")
    
    if [ -n "$versions" ]; then
        while IFS= read -r version; do
            if [ -n "$version" ] && [ "$version" != "loading" ]; then
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
    
    # If no valid versions found, ensure we at least have the loading page
    if [ -d "$VERSIONS_DIR/loading" ]; then
        log "No valid app versions found, using loading page"
        switch_version "loading"
        return 0
    fi
    
    log "ERROR: No valid versions found and no loading page available!"
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
