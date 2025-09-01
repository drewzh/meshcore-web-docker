# MeshCore Web Docker

A Docker container that downloads and hosts the MeshCore web application from [files.liamcottle.net](https://files.liamcottle.net/MeshCore/).

## ⚠️ IMPORTANT: HTTPS Required for Bluetooth Features

**MeshCore requires HTTPS to access Bluetooth devices through the Web Bluetooth API.** You have two options:

1. **Reverse Proxy Setup** (Recommended for production): Use HTTP mode with a reverse proxy (nginx, Traefik, etc.) that handles HTTPS
2. **Direct HTTPS Access**: Enable built-in HTTPS with `ENABLE_HTTPS=true` for direct access

**Without HTTPS, you cannot connect to Bluetooth devices - the browser will block the Web Bluetooth API.**

## Features

- **Runtime Download**: Downloads MeshCore from official zip files when the container starts
- **Loading Page**: Shows an attractive loading page with auto-refresh while the app is being downloaded
- **Version Management**: Automatically detects and downloads the latest version or use a specific version
- **Atomic Switching**: Uses symlinks for zero-downtime version switching
- **Persistent Storage**: Stores versions in a Docker volume for faster subsequent starts
- **Graceful Fallback**: Uses cached version if download fails
- **Production Ready**: Includes nginx with optimized configuration and health checks
- **Auto-Updates**: Checks for newer versions on container restart
- **Configurable HTTPS**: Optional built-in HTTPS support with automatic SSL certificate generation

## Quick Start

### Option 1: HTTP Only (For Reverse Proxy Setup)

```yaml
# docker-compose.yml - HTTP only for reverse proxy
version: "3.8"
services:
  meshcore:
    image: ghcr.io/drewzh/meshcore-web-docker:latest
    ports:
      - "8080:80"
    volumes:
      - meshcore-data:/app/versions
    environment:
      - TZ=UTC
      - ENABLE_HTTPS=false # HTTP only

volumes:
  meshcore-data:
```

### Option 2: HTTPS Enabled (For Direct Access with Bluetooth)

```yaml
# docker-compose.yml - HTTPS enabled for direct access
version: "3.8"
services:
  meshcore:
    image: ghcr.io/drewzh/meshcore-web-docker:latest
    ports:
      - "8080:80" # HTTP access
      - "8443:443" # HTTPS access (required for Bluetooth)
    volumes:
      - meshcore-data:/app/versions
    environment:
      - TZ=UTC
      - ENABLE_HTTPS=true # Enable HTTPS

volumes:
  meshcore-data:
```

### Starting the Container

```bash
# Start the container
docker-compose up -d

# Check logs
docker-compose logs -f meshcore
```

### Accessing the Application

**HTTP Only Mode (Option 1):**

- Application: http://localhost:8080
- ⚠️ **Bluetooth features will NOT work** - you need HTTPS via reverse proxy

**HTTPS Enabled Mode (Option 2):**

- HTTP Access: http://localhost:8080 (basic functionality)
- **HTTPS Access: https://localhost:8443** (✅ **Bluetooth features work**)
- ⚠️ You'll see a security warning due to self-signed certificate - this is normal for local development

### Using Docker Directly

**HTTP Only Mode:**

```bash
docker run -d \
  --name meshcore-web \
  -p 8080:80 \
  -e ENABLE_HTTPS=false \
  -v meshcore-data:/app/versions \
  ghcr.io/drewzh/meshcore-web-docker:latest
```

**HTTPS Enabled Mode:**

```bash
docker run -d \
  --name meshcore-web \
  -p 8080:80 \
  -p 8443:443 \
  -e ENABLE_HTTPS=true \
  -v meshcore-data:/app/versions \
  ghcr.io/drewzh/meshcore-web-docker:latest
```

```bash
# Check logs
docker logs -f meshcore-web
```

## Configuration

### Environment Variables

| Variable            | Default                                 | Description                                   |
| ------------------- | --------------------------------------- | --------------------------------------------- |
| `TZ`                | `UTC`                                   | Timezone for logs                             |
| `MESHCORE_BASE_URL` | `https://files.liamcottle.net/MeshCore` | Base URL for MeshCore releases                |
| `ENABLE_HTTPS`      | `false`                                 | Enable HTTPS support (required for Bluetooth) |
| `PUID`              | (empty)                                 | User ID for Unraid compatibility (optional)   |
| `PGID`              | (empty)                                 | Group ID for Unraid compatibility (optional)  |

### Ports

- `80`: HTTP web server (always available)
- `443`: HTTPS web server (only when `ENABLE_HTTPS=true`)

### Volumes

- `/app/versions`: Version storage directory (should be mounted to persist downloads)

## How It Works

1. **Build Time**: Creates a loading page with auto-refresh functionality (no external downloads)
2. **Container Start**:
   - Shows loading page immediately for instant response
   - Downloads MeshCore from official zip files in the background
   - Automatically detects and downloads the latest version
   - Validates downloads before switching versions
   - Auto-refreshes browser to show the actual app once ready
3. **Version Management**:
   - Automatically detects the latest available version from files.liamcottle.net
   - Downloads and extracts zip files to versioned directories
   - Uses symlinks for atomic switching between versions
   - Keeps previously downloaded versions for faster restarts

## Endpoints

**Available on both HTTP and HTTPS (when enabled):**

- `/` - MeshCore web application (or loading page during download)
- `/health` - Health check endpoint (returns "healthy")
- `/version` - JSON information about the currently active version

**Access URLs:**

- HTTP: `http://localhost:8080/` (when mapped to port 8080)
- HTTPS: `https://localhost:8443/` (when HTTPS enabled and mapped to port 8443)

> **🔑 Important**: For Bluetooth functionality, you MUST use HTTPS - either through this container's built-in HTTPS support or via a reverse proxy.

## Version Management

The container automatically manages MeshCore versions by:

1. Checking files.liamcottle.net for the latest available version
2. Downloading and installing it if not already cached
3. Switching to the new version automatically

This ensures you always have the latest MeshCore features and bug fixes without any manual intervention.

### Unraid Integration

For Unraid users, this container is perfect for hosting MeshCore:

#### Basic Setup:

1. Install from Community Applications or add the repository manually
2. Set your desired port mapping (e.g., 8080:80)
3. Configure a volume mapping for `/app/versions` to persist downloads

#### Recommended Unraid Configuration:

**For HTTP Only (behind reverse proxy):**

```
Container Port: 80 -> Host Port: 8080
Container Path: /app/versions -> Host Path: /mnt/user/appdata/meshcore-web
Variable: ENABLE_HTTPS -> false
```

**For Direct HTTPS Access (Bluetooth support):**

```
Container Port: 80 -> Host Port: 8080
Container Port: 443 -> Host Port: 8443
Container Path: /app/versions -> Host Path: /mnt/user/appdata/meshcore-web
Variable: ENABLE_HTTPS -> true
```

#### Optional: Set User Permissions (for appdata compatibility):

- **PUID**: Set to your user ID (usually 99 for Unraid)
- **PGID**: Set to your group ID (usually 100 for Unraid)

**Example Docker Run for Unraid (HTTP only):**

```bash
docker run -d \
  --name=meshcore-web \
  -p 8080:80 \
  -v /mnt/user/appdata/meshcore-web:/app/versions \
  -e ENABLE_HTTPS=false \
  -e PUID=99 \
  -e PGID=100 \
  -e TZ=America/New_York \
  ghcr.io/drewzh/meshcore-web-docker:latest
```

**Example Docker Run for Unraid (HTTPS enabled):**

```bash
docker run -d \
  --name=meshcore-web \
  -p 8080:80 \
  -p 8443:443 \
  -v /mnt/user/appdata/meshcore-web:/app/versions \
  -e ENABLE_HTTPS=true \
  -e PUID=99 \
  -e PGID=100 \
  -e TZ=America/New_York \
  ghcr.io/drewzh/meshcore-web-docker:latest
```

The container will automatically:

- Create the appdata directory structure if it doesn't exist
- Set proper permissions for Unraid compatibility
- Download and cache MeshCore versions in your appdata folder
- Restart instantly with cached versions (no redownload needed)

## Development

### Building Locally

```bash
git clone https://github.com/drewzh/meshcore-web-docker.git
cd meshcore-web-docker
docker build -t meshcore-web .
```

### Testing

```bash
# Build and run
docker build -t meshcore-web .
docker run -p 8080:80 meshcore-web

# Check that it responds
curl http://localhost:8080/health
curl http://localhost:8080/version
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the build and functionality
5. Submit a pull request

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Acknowledgments

- [MeshCore](https://github.com/liamcottle/meshcore) by Liam Cottle for the excellent Meshtastic web interface
- [files.liamcottle.net](https://files.liamcottle.net/MeshCore/) for providing direct zip file downloads

## Development

### Building locally

```bash
docker build -t meshcore-web .
```

### Testing

```bash
# Start the container
docker-compose up -d

# Test the health endpoint
curl http://localhost:8080/health

# Test the main application
curl http://localhost:8080/
```

### Logs

```bash
# View logs
docker-compose logs -f meshcore-web

# View nginx access logs
docker-compose exec meshcore-web tail -f /var/log/nginx/access.log

# View nginx error logs
docker-compose exec meshcore-web tail -f /var/log/nginx/error.log
```

## Updating

To get the latest version of the MeshCore web application:

```bash
# Restart the container
docker-compose restart meshcore-web

# Or rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## Troubleshooting

### Container fails to start

1. Check the logs: `docker-compose logs meshcore-web`
2. Ensure the original site (https://app.meshcore.nz/) is accessible
3. Check that port 8080 is not already in use

### Application not loading

1. Verify the container is running: `docker-compose ps`
2. Check the health endpoint: `curl http://localhost:8080/health`
3. Inspect the downloaded files: `docker-compose exec meshcore-web ls -la /app/web/`

### Update issues

1. Check internet connectivity from the container
2. Verify the original site is accessible
3. Check disk space for the volume

## License

This project is provided as-is for hosting the MeshCore web application with permission from the original author. The MeshCore web application itself is subject to its own licensing terms.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `docker-compose up --build`
5. Submit a pull request

## Security

- The container runs nginx as a non-root user
- Security headers are configured in nginx
- Only necessary tools are installed in the container
- The container includes health checks for monitoring
