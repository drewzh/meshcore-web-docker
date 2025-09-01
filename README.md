# MeshCore Web Docker

A Docker container that downloads and hosts the MeshCore web application from [files.liamcottle.net](https://files.liamcottle.net/MeshCore/).

## Features

- **Runtime Download**: Downloads MeshCore from official zip files when the container starts
- **Loading Page**: Shows an attractive loading page with auto-refresh while the app is being downloaded
- **Version Management**: Automatically detects and downloads the latest version or use a specific version
- **Atomic Switching**: Uses symlinks for zero-downtime version switching
- **Persistent Storage**: Stores versions in a Docker volume for faster subsequent starts
- **Graceful Fallback**: Uses cached version if download fails
- **Production Ready**: Includes nginx with optimized configuration and health checks
- **Auto-Updates**: Checks for newer versions on container restart

## Quick Start

### Using Docker Compose (Recommended)

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

The application will be available at http://localhost:8080

### Using Docker directly

```bash
# Run the container
docker run -d \
  --name meshcore-web \
  -p 8080:80 \
  -v meshcore-data:/app/versions \
  ghcr.io/drewzh/meshcore-web-docker:latest

# Check logs
docker logs -f meshcore-web
```

## Configuration

### Environment Variables

| Variable            | Default                                 | Description                    |
| ------------------- | --------------------------------------- | ------------------------------ |
| `TZ`                | `UTC`                                   | Timezone for logs              |
| `MESHCORE_BASE_URL` | `https://files.liamcottle.net/MeshCore` | Base URL for MeshCore releases |

### Ports

- `80`: nginx web server (map to desired host port)

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

## Version Management

The container automatically manages MeshCore versions by:

1. Checking files.liamcottle.net for the latest available version
2. Downloading and installing it if not already cached
3. Switching to the new version automatically

This ensures you always have the latest MeshCore features and bug fixes without any manual intervention.

### Unraid Integration

For Unraid users, this container is perfect for hosting MeshCore:

1. Install from Community Applications or add the repository manually
2. Set your desired port mapping (e.g., 8080:80)
3. Configure a volume mapping for `/app/versions` to persist downloads
4. The container will automatically use the latest MeshCore version

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
