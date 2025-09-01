#!/bin/bash

set -e

# Configuration
MESHCORE_BASE_URL="${MESHCORE_BASE_URL:-https://files.liamcottle.net/MeshCore}"
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
    
    # Check if content is in a web subdirectory (newer format) or root directory (older format)
    local web_content_dir
    if [ -d "$temp_dir/web" ] && [ -f "$temp_dir/web/index.html" ]; then
        log "Found web content in subdirectory: $temp_dir/web"
        web_content_dir="$temp_dir/web"
    else
        # Find the extracted directory (should be something like MeshCore-v1.25.0+47-aef292a-web)
        local extracted_dir
        extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
        
        if [ ! -d "$extracted_dir" ]; then
            log "ERROR: Could not find extracted directory"
            return 1
        fi
        
        log "Found extracted directory: $(basename "$extracted_dir")"
        
        if [ -d "$extracted_dir/web" ] && [ -f "$extracted_dir/web/index.html" ]; then
            log "Found web content in nested subdirectory: $extracted_dir/web"
            web_content_dir="$extracted_dir/web"
        elif [ -f "$extracted_dir/index.html" ]; then
            log "Found web content in root directory: $extracted_dir"
            web_content_dir="$extracted_dir"
        else
            log "ERROR: No index.html found in extracted content"
            log "Contents of temp directory:"
            ls -la "$temp_dir" || true
            if [ -d "$extracted_dir" ]; then
                log "Contents of extracted directory:"
                ls -la "$extracted_dir" || true
                if [ -d "$extracted_dir/web" ]; then
                    log "Contents of web subdirectory:"
                    ls -la "$extracted_dir/web" || true
                fi
            fi
            return 1
        fi
    fi
    
    # Move web content to target directory
    rm -rf "$target_dir"
    mv "$web_content_dir" "$target_dir"
    
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

# Function to initialize directory structure
init_directories() {
    log "Initializing directory structure..."
    
    # Create main directories with proper permissions
    if ! mkdir -p "$VERSIONS_DIR" "$WEB_DIR" 2>/dev/null; then
        log "ERROR: Failed to create directories. Checking permissions..."
        log "VERSIONS_DIR: $VERSIONS_DIR (exists: $([ -d "$VERSIONS_DIR" ] && echo "Yes" || echo "No"))"
        log "WEB_DIR: $WEB_DIR (exists: $([ -d "$WEB_DIR" ] && echo "Yes" || echo "No"))"
        
        # Try with more verbose error reporting
        if ! mkdir -p "$VERSIONS_DIR" 2>&1; then
            log "ERROR: Cannot create $VERSIONS_DIR"
            return 1
        fi
        if ! mkdir -p "$WEB_DIR" 2>&1; then
            log "ERROR: Cannot create $WEB_DIR"  
            return 1
        fi
    fi
    
    # Ensure loading page exists (important for volume mounts)
    local loading_dir="$VERSIONS_DIR/loading"
    if [ ! -d "$loading_dir" ]; then
        log "Creating loading page directory: $loading_dir"
        mkdir -p "$loading_dir"
    fi
    
    # Create loading page if it doesn't exist (volume mount scenario)
    if [ ! -f "$loading_dir/index.html" ]; then
        log "Creating loading page content (volume mount detected)"
        cat > "$loading_dir/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MeshCore - Loading</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0; padding: 40px; text-align: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh; display: flex; align-items: center; justify-content: center;
            color: white;
        }
        .container { background: rgba(255,255,255,0.1); padding: 40px; border-radius: 20px; backdrop-filter: blur(10px); }
        .spinner { border: 4px solid rgba(255,255,255,0.3); border-top: 4px solid white; border-radius: 50%; width: 60px; height: 60px; animation: spin 1s linear infinite; margin: 20px auto; }
        @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        h1 { margin: 0 0 20px 0; font-size: 2.5em; font-weight: 300; }
        p { font-size: 1.2em; margin: 10px 0; opacity: 0.9; }
    </style>
    <script>
        let dots = 0;
        setInterval(() => {
            dots = (dots + 1) % 4;
            const loading = document.querySelector('.loading-text');
            if (loading) loading.textContent = 'Downloading MeshCore' + '.'.repeat(dots);
        }, 500);
        setTimeout(() => location.reload(), 5000);
    </script>
</head>
<body>
    <div class="container">
        <h1>🌐 MeshCore</h1>
        <div class="spinner"></div>
        <p class="loading-text">Downloading MeshCore</p>
        <p style="font-size:0.9em; opacity:0.7;">This page will refresh automatically...</p>
    </div>
</body>
</html>
EOF
    fi
    
    # Create loading page version file if it doesn't exist  
    if [ ! -f "$loading_dir/.version" ]; then
        log "Creating loading page version file"
        cat > "$loading_dir/.version" << 'EOF'
{"status":"loading","version":"loading-page","description":"MeshCore is downloading..."}
EOF
    fi
    
    # Set proper permissions for Unraid compatibility
    chmod -R 755 "$VERSIONS_DIR" 2>/dev/null || true
    chmod -R 755 "$WEB_DIR" 2>/dev/null || true
    
    log "Directory structure initialized successfully"
    return 0
}

# Function to update MeshCore
update_meshcore() {
    log "Starting MeshCore update process..."
    
    # Initialize directory structure (handles volume mounts)
    if ! init_directories; then
        log "ERROR: Failed to initialize directory structure"
        return 1
    fi
    
    # Always auto-detect the latest version
    log "Finding latest MeshCore version..."
    if latest_version=$(find_latest_version); then
        if download_url=$(get_download_url "$latest_version"); then
            version_name="$latest_version"
            log "Auto-detected version: $version_name"
            log "Auto-detected URL: $download_url"
            
            # Check if we already have this version downloaded
            local target_version_dir="$VERSIONS_DIR/$version_name"
            if [ -d "$target_version_dir" ] && [ -f "$target_version_dir/index.html" ]; then
                log "Version $version_name already downloaded, switching to it"
                rm -f "$CURRENT_LINK"
                ln -sf "$target_version_dir" "$CURRENT_LINK"
                log "Symlink updated: $CURRENT_LINK -> $target_version_dir"
                log "Successfully switched to cached version: $version_name"
                return 0
            fi
        else
            log "Failed to get download URL for version $latest_version"
            return 1
        fi
    else
        log "Failed to find latest version"
        return 1
    fi
    
    log "Using download URL: $download_url"
    log "Version name: $version_name"
    
    # Download to new version directory
    if download_meshcore "$download_url" "$target_version_dir" "$version_name"; then
        log "Download successful, switching to new version"
        
        # Switch symlink to new version (remove existing link first)
        rm -f "$CURRENT_LINK"
        ln -sf "$target_version_dir" "$CURRENT_LINK"
        
        log "Symlink updated: $CURRENT_LINK -> $target_version_dir"
        
        log "Successfully updated to version: $version_name"
        
        # Clean up old versions (keep last 3)
        cleanup_old_versions
        
        return 0
    else
        log "Download failed"
        rm -rf "$target_version_dir" 2>/dev/null || true
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
    
    # First, ensure directories exist (important for volume mounts)
    if [ ! -d "$VERSIONS_DIR" ] || [ ! -d "$WEB_DIR" ]; then
        log "Directories missing, initializing structure..."
        if ! init_directories; then
            log "ERROR: Failed to initialize directory structure"
            return 1
        fi
    fi
    
    # First, check if we have any downloaded versions available (prefer them over loading page)
    local latest_downloaded_version
    if latest_downloaded_version=$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d -name "v*" 2>/dev/null | sort -V | tail -1); then
        if [ -n "$latest_downloaded_version" ] && [ -d "$latest_downloaded_version" ] && [ -f "$latest_downloaded_version/index.html" ]; then
            log "Found downloaded version: $(basename "$latest_downloaded_version")"
            rm -f "$CURRENT_LINK"
            ln -sf "$latest_downloaded_version" "$CURRENT_LINK"
            log "Switched to downloaded version: $(basename "$latest_downloaded_version")"
            return 0
        fi
    fi
    
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
    
    # Ensure loading page exists as fallback (create if needed for volume mounts)
    if [ ! -d "$VERSIONS_DIR/loading" ] || [ ! -f "$VERSIONS_DIR/loading/index.html" ]; then
        log "Loading page missing, recreating..."
        if ! init_directories; then
            log "ERROR: Failed to initialize loading page"
            return 1
        fi
    fi
    
    # Set up symlink to loading page
    if [ -d "$VERSIONS_DIR/loading" ] && [ -f "$VERSIONS_DIR/loading/index.html" ]; then
        rm -f "$CURRENT_LINK"
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
    log "=== Final Status Check ==="
    if [ -L "$CURRENT_LINK" ]; then
        local current_target
        current_target=$(readlink "$CURRENT_LINK")
        log "Symlink exists: $CURRENT_LINK"
        log "Points to: $current_target"
        log "Final version: $(basename "$current_target")"
        log "Target directory exists: $([ -d "$current_target" ] && echo "Yes" || echo "No")"
        if [ -f "$CURRENT_LINK/.version" ]; then
            log "Version info: $(cat "$CURRENT_LINK/.version")"
        else
            log "No .version file found"
        fi
        if [ -f "$CURRENT_LINK/index.html" ]; then
            log "index.html present: Yes"
        else
            log "index.html present: No"
        fi
    else
        log "ERROR: No symlink found at $CURRENT_LINK"
    fi
    
    log "MeshCore is ready to serve"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
