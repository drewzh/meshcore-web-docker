# MeshCore Web Docker

A Docker container that downloads and hosts the MeshCore web application from [files.liamcottle.net](https://files.liamcottle.net/MeshCore/).

**Note:** This container serves HTTP only. For Bluetooth functionality, you'll need to set up a reverse proxy with HTTPS as MeshCore requires HTTPS to access Bluetooth devices through the Web Bluetooth API.

## Features

- **Runtime Download**: Downloads MeshCore from official zip files when the container starts
- **Loading Page**: Shows an attractive loading page with auto-refresh while the app is being downloaded
- **Version Management**: Automatically detects and downloads the latest version or use a specific version
- **Atomic Switching**: Uses symlinks for zero-downtime version switching
- **Persistent Storage**: Stores versions in a Docker volume for faster subsequent starts
- **Graceful Fallback**: Uses cached version if download fails
- **Production Ready**: Includes nginx with optimized configuration and health checks
- **Auto-Updates**: Checks for newer versions on container restart
- **Reverse Proxy Ready**: HTTP-only design perfect for use behind HTTPS reverse proxies

## Quick Start

### Basic Setup

```yaml
# docker-compose.yml
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

volumes:
  meshcore-data:
```

```bash
# Start the container
docker-compose up -d

# Check logs
docker-compose logs -f meshcore
```

**Access:** http://localhost:8080

## HTTPS Setup with Reverse Proxies

Since MeshCore requires HTTPS for Bluetooth functionality, here are several ways to add HTTPS:

### Option 1: nginx Proxy Manager (Easiest - GUI Based)

Perfect for beginners! Provides a web interface for managing reverse proxies.

```yaml
# docker-compose.yml with nginx Proxy Manager
version: "3.8"
services:
  meshcore:
    image: ghcr.io/drewzh/meshcore-web-docker:latest
    volumes:
      - meshcore-data:/app/versions
    environment:
      - TZ=UTC
    # No ports exposed - internal only

  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    ports:
      - "80:80"
      - "443:443"
      - "81:81" # Admin interface
    volumes:
      - npm-data:/data
      - npm-letsencrypt:/etc/letsencrypt
    depends_on:
      - meshcore

volumes:
  meshcore-data:
  npm-data:
  npm-letsencrypt:
```

1. Access admin interface at http://localhost:81
2. Add a proxy host pointing to `meshcore:80`
3. Enable SSL with Let's Encrypt

### Option 2: Traefik (Automatic HTTPS)

Great for Docker-based setups with automatic Let's Encrypt certificates.

```yaml
# docker-compose.yml with Traefik
version: "3.8"
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.email=your-email@example.com"
      - "--certificatesresolvers.letsencrypt.acme.storage=/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "traefik-acme:/acme.json"

  meshcore:
    image: ghcr.io/drewzh/meshcore-web-docker:latest
    volumes:
      - meshcore-data:/app/versions
    environment:
      - TZ=UTC
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.meshcore.rule=Host(`meshcore.yourdomain.com`)"
      - "traefik.http.routers.meshcore.tls.certresolver=letsencrypt"

volumes:
  meshcore-data:
  traefik-acme:
```

### Option 3: Caddy (Simplest Configuration)

Caddy automatically handles HTTPS certificates with minimal configuration.

```yaml
# docker-compose.yml with Caddy
version: "3.8"
services:
  caddy:
    image: caddy:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      - meshcore

  meshcore:
    image: ghcr.io/drewzh/meshcore-web-docker:latest
    volumes:
      - meshcore-data:/app/versions
    environment:
      - TZ=UTC

volumes:
  meshcore-data:
  caddy-data:
  caddy-config:
```

Create a `Caddyfile`:

```
meshcore.yourdomain.com {
    reverse_proxy meshcore:80
}
```

### Option 4: Cloudflare Tunnel (Zero Configuration)

Perfect for external access without port forwarding or certificates.

```bash
# Install cloudflared
docker run -d \
  --name cloudflare-tunnel \
  cloudflare/cloudflared:latest tunnel \
  --no-autoupdate run \
  --token YOUR_TUNNEL_TOKEN

# Your MeshCore container runs normally
docker run -d \
  --name meshcore \
  -v meshcore-data:/app/versions \
  ghcr.io/drewzh/meshcore-web-docker:latest
```

1. Create tunnel at https://dash.cloudflare.com
2. Point tunnel to `http://meshcore:80`
3. Access via your Cloudflare domain (automatically HTTPS)

### Option 5: Traditional nginx

For advanced users who want full control.

```yaml
# docker-compose.yml with nginx
version: "3.8"
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./ssl:/etc/nginx/ssl
    depends_on:
      - meshcore

  meshcore:
    image: ghcr.io/drewzh/meshcore-web-docker:latest
    volumes:
      - meshcore-data:/app/versions
    environment:
      - TZ=UTC

volumes:
  meshcore-data:
```

Create an `nginx.conf` with SSL configuration and proxy to `http://meshcore:80`.

````

### Accessing the Application

- Application: http://localhost:8080
- **Note:** Bluetooth features require HTTPS - use a reverse proxy for Bluetooth functionality

### Using Docker Directly

```bash
docker run -d \
  --name meshcore-web \
  -p 8080:80 \
  -v meshcore-data:/app/versions \
  ghcr.io/drewzh/meshcore-web-docker:latest
```

```bash
# Check logs
docker logs -f meshcore-web
```

## Configuration

### Environment Variables

| Variable            | Default                                 | Description                                  |
| ------------------- | --------------------------------------- | -------------------------------------------- |
| `TZ`                | `UTC`                                   | Timezone for logs                            |
| `MESHCORE_BASE_URL` | `https://files.liamcottle.net/MeshCore` | Base URL for MeshCore releases               |
| `PUID`              | (empty)                                 | User ID for Unraid compatibility (optional)  |
| `PGID`              | (empty)                                 | Group ID for Unraid compatibility (optional) |

### Ports

- `80`: HTTP web server

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

- `/` - MeshCore web application (or loading page during download)
- `/health` - Health check endpoint (returns "healthy")
- `/version` - JSON information about the currently active version

**Direct Access:** `http://localhost:8080/` (when mapped to port 8080)

> **🔑 Important**: For Bluetooth functionality, you MUST use HTTPS via a reverse proxy.

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

```
Container Port: 80 -> Host Port: 8080
Container Path: /app/versions -> Host Path: /mnt/user/appdata/meshcore-web
```

#### Optional: Set User Permissions (for appdata compatibility):

- **PUID**: Set to your user ID (usually 99 for Unraid)
- **PGID**: Set to your group ID (usually 100 for Unraid)

**Example Docker Run for Unraid:**

```bash
docker run -d \
  --name=meshcore-web \
  -p 8080:80 \
  -v /mnt/user/appdata/meshcore-web:/app/versions \
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
````
