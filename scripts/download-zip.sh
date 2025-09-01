#!/bin/bash

set -e

# Configuration
MESHCORE_BASE_URL="${MESHCORE_BASE_URL:-https://files.liamcottle.net/MeshCore}"
MESHCORE_ZIP_URL="${MESHCORE_ZIP_URL:-}"  # Empty means auto-detect
VERSIONS_DIR="${VERSIONS_DIR:-/app/versions}"
WEB_DIR="${WEB_DIR:-/app/web}"
CURRENT_LINK="$WEB_DIR/current"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DOWNLOAD: $1"
}

# Function to find latest version from the files server
find_latest_version() {
    log "Attempting to find latest version from $MESHCORE_BASE_URL..." >&2
    
    # Try to get directory listing and find the latest version
    if latest_version=$(curl -s --max-time 15 "$MESHCORE_BASE_URL/" | grep -oE 'href="\.\/v[0-9]+\.[0-9]+\.[0-9]+\/"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1); then
        if [ -n "$latest_version" ]; then
            log "Found latest version: $latest_version" >&2
            echo "$latest_version"
            return 0
        fi
    fi
    
    log "Could not auto-detect latest version, using default" >&2
    return 1
}

# Function to construct download URL from version
get_download_url() {
    local version="$1"
    
    log "Getting download URL for version: $version" >&2
    
    # Try to get the exact filename from the version directory
    local version_url="$MESHCORE_BASE_URL/$version/"
    log "Checking directory: $version_url" >&2
    
    if zip_filename=$(curl -s --max-time 15 "$version_url" | grep -oE 'href="\.\/MeshCore[^"]*-web\.zip"' | grep -oE 'MeshCore[^"]*-web\.zip' | head -1); then
        local download_url="$MESHCORE_BASE_URL/$version/$zip_filename"
        log "Found zip file: $zip_filename" >&2
        log "Download URL: $download_url" >&2
        echo "$download_url"
        return 0
    fi
    
    log "Could not find zip file in $version_url" >&2
    return 1
}

# Function to download and extract MeshCore
download_meshcore() {
    local zip_url="$1"
    local target_dir="$2"
    local version_name="$3"
    
    log "Downloading MeshCore from: $zip_url"
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    local zip_file="$temp_dir/meshcore.zip"
    
    # Cleanup function
    cleanup() {
        rm -rf "$temp_dir"
    }
    trap cleanup EXIT
    
    # Download the zip file
    if ! curl -L --fail --max-time 60 -o "$zip_file" "$zip_url"; then
        log "ERROR: Failed to download $zip_url"
        return 1
    fi
    
    log "Download completed, extracting..."
    
    # Extract the zip file
    if ! unzip -q "$zip_file" -d "$temp_dir"; then
        log "ERROR: Failed to extract zip file"
        return 1
    fi
    
    # Find the extracted directory (should be something like MeshCore-v1.25.0+47-aef292a-web)
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
    
    if [ ! -d "$extracted_dir" ]; then
        log "ERROR: Could not find extracted directory"
        return 1
    fi
    
    log "Found extracted directory: $(basename "$extracted_dir")"
    
    # Validate the extracted content
    if [ ! -f "$extracted_dir/index.html" ]; then
        log "ERROR: No index.html found in extracted content"
        return 1
    fi
    
    # Move content to target directory
    rm -rf "$target_dir"
    mv "$extracted_dir" "$target_dir"
    
    # Create version info file
    cat > "$target_dir/.version" << EOF
{
    "version": "$version_name",
    "downloaded_at": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
    "source_url": "$zip_url",
    "download_method": "zip"
}
EOF
    
    log "MeshCore extracted successfully to $target_dir"
    return 0
}

# Function to update MeshCore
update_meshcore() {
    log "Starting MeshCore update process..."
    
    # Create directories
    mkdir -p "$VERSIONS_DIR" "$WEB_DIR"
    
    local download_url="$MESHCORE_ZIP_URL"
    local version_name="manual"
    
    # Auto-detect latest version if no specific URL is provided
    if [ -z "$MESHCORE_ZIP_URL" ]; then
        log "No specific ZIP URL provided, attempting to find latest version..."
        if latest_version=$(find_latest_version); then
            if auto_url=$(get_download_url "$latest_version"); then
                download_url="$auto_url"
                version_name="$latest_version"
                log "Auto-detected version: $version_name"
                log "Auto-detected URL: $download_url"
            else
                log "Failed to get download URL for version $latest_version"
                return 1
            fi
        else
            log "Failed to find latest version"
            return 1
        fi
    else
        # Extract version from custom URL if possible
        if custom_version=$(echo "$MESHCORE_ZIP_URL" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+'); then
            version_name="$custom_version"
        else
            version_name="custom-$(date '+%Y%m%d-%H%M%S')"
        fi
    fi
    
    log "Using download URL: $download_url"
    log "Version name: $version_name"
    
    # Download to new version directory
    local new_version_dir="$VERSIONS_DIR/$version_name"
    
    if download_meshcore "$download_url" "$new_version_dir" "$version_name"; then
        log "Download successful, switching to new version"
        
        # Switch symlink to new version
        ln -sf "$new_version_dir" "$CURRENT_LINK"
        
        log "Successfully updated to version: $version_name"
        
        # Clean up old versions (keep last 3)
        cleanup_old_versions
        
        return 0
    else
        log "Download failed"
        rm -rf "$new_version_dir" 2>/dev/null || true
        return 1
    fi
}

# Function to cleanup old versions
cleanup_old_versions() {
    log "Cleaning up old versions (keeping last 3)..."
    
    # Get all version directories except loading, sorted by modification time
    local old_versions
    old_versions=$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name "*" ! -name "loading" -printf "%T@ %p\n" | sort -n | head -n -3 | cut -d' ' -f2-)
    
    if [ -n "$old_versions" ]; then
        while IFS= read -r version_dir; do
            if [ -n "$version_dir" ] && [ -d "$version_dir" ]; then
                log "Removing old version: $(basename "$version_dir")"
                rm -rf "$version_dir"
            fi
        done <<< "$old_versions"
    else
        log "No old versions to clean up"
    fi
}

# Function to ensure we have a working installation
ensure_working_version() {
    log "Ensuring we have a working MeshCore installation..."
    
    # Check if current symlink exists and is valid
    if [ -L "$CURRENT_LINK" ] && [ -d "$CURRENT_LINK" ] && [ -f "$CURRENT_LINK/index.html" ]; then
        local current_version
        if [ -f "$CURRENT_LINK/.version" ]; then
            current_version=$(grep '"version"' "$CURRENT_LINK/.version" | sed 's/.*"version": *"\([^"]*\)".*/\1/' || echo "unknown")
        else
            current_version="unknown"
        fi
        log "Current version '$current_version' is valid"
        return 0
    fi
    
    log "No valid current version found, falling back to loading page"
    
    # Ensure loading page exists as fallback
    if [ -d "$VERSIONS_DIR/loading" ] && [ -f "$VERSIONS_DIR/loading/index.html" ]; then
        ln -sf "$VERSIONS_DIR/loading" "$CURRENT_LINK"
        log "Using loading page as fallback"
        return 0
    fi
    
    log "ERROR: No working version available and no loading page fallback"
    return 1
}

# Main function
main() {
    log "MeshCore zip downloader starting..."
    log "Base URL: $MESHCORE_BASE_URL"
    log "Zip URL: $MESHCORE_ZIP_URL"
    
    # Ensure we have a working version first (loading page)
    if ! ensure_working_version; then
        log "CRITICAL: No working version available"
        exit 1
    fi
    
    # Attempt to update to latest version
    if update_meshcore; then
        log "Update completed successfully"
    else
        log "Update failed, continuing with current version"
        # Ensure we still have a working version
        if ! ensure_working_version; then
            log "CRITICAL: Lost working version"
            exit 1
        fi
    fi
    
    # Show final status
    if [ -L "$CURRENT_LINK" ]; then
        local current_target
        current_target=$(readlink "$CURRENT_LINK")
        log "Final version: $(basename "$current_target")"
        if [ -f "$CURRENT_LINK/.version" ]; then
            log "Version info: $(cat "$CURRENT_LINK/.version")"
        fi
    fi
    
    log "MeshCore is ready to serve"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
