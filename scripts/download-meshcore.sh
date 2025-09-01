#!/bin/bash

set -e

MESHCORE_URL="https://app.meshcore.nz"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DOWNLOAD: $1"
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

# Function to validate downloaded content
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

# Main function
main() {
    local target_dir="$1"
    local version_name="$2"
    
    if [ -z "$target_dir" ]; then
        echo "Usage: $0 <target_directory> [version_name]"
        echo "Example: $0 /app/versions/latest"
        exit 1
    fi
    
    if [ -z "$version_name" ]; then
        version_name=$(date '+%Y%m%d-%H%M%S')
    fi
    
    log "MeshCore downloader starting..."
    log "Target directory: $target_dir"
    log "Version name: $version_name"
    
    # Test if site is reachable first
    if ! test_site_reachable; then
        log "ERROR: Cannot reach MeshCore site, download aborted"
        exit 1
    fi
    
    # Perform the download
    if download_meshcore "$target_dir" "$version_name"; then
        log "SUCCESS: MeshCore web application downloaded successfully"
        exit 0
    else
        log "FAILURE: Failed to download MeshCore web application"
        exit 1
    fi
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
