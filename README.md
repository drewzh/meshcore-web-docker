# MeshCore Web Docker

A Docker container that downloads and hosts the MeshCore web application from https://app.meshcore.nz/.

## Features

- **Pre-built Version**: Includes a pre-downloaded version of the app built into the image for offline usage
- **Staged Downloads**: Downloads are validated before replacing the current version
- **Atomic Switching**: Uses symlinks for zero-downtime version switching
- **Persistent Storage**: Stores multiple versions in a Docker volume for rollback capability
- **Auto-Update**: Checks for and downloads updates on container restart (when the site is reachable)
- **Graceful Fallback**: Uses cached version if the original site is unreachable or download fails
- **Version Management**: Keep multiple versions and switch between them
- **Production Ready**: Includes nginx with optimized configuration, security headers, and health checks

## Quick Start

### Using Docker Compose (Recommended)

```bash
# Clone the repository
git clone https://github.com/drewzh/meshcore-web-docker.git
cd meshcore-web-docker

# Start the container
docker-compose up -d

# Check logs
docker-compose logs -f
```

The application will be available at http://localhost:8080

### Using Docker directly

```bash
# Build the image
docker build -t meshcore-web .

# Run the container
docker run -d \
  --name meshcore-web \
  -p 8080:80 \
  -v meshcore-data:/app/web \
  meshcore-web

# Check logs
docker logs -f meshcore-web
```

## Configuration

### Environment Variables

- `TZ`: Timezone (default: UTC)

### Ports

- `80`: nginx web server (mapped to host port 8080 in examples)

### Volumes

- `/app/versions`: Version storage directory (should be mounted to persist downloads and enable rollbacks)

## How It Works

1. **Build Time**: Downloads the MeshCore web application during Docker image build for offline availability
2. **First Run**:
   - Sets up symlink to the pre-built version
   - Attempts to download the latest version if internet is available
   - Validates downloads before switching versions
3. **Subsequent Runs**:
   - Checks if the original site is reachable
   - If reachable: Downloads and validates the latest version, then atomically switches to it
   - If unreachable or download fails: Continues using the current cached version
4. **Serving**: nginx serves the static files through a symlink to the current version
5. **Version Management**: Keeps multiple versions for rollback capability

## Health Check

The container includes a health check endpoint at `/health` that returns "healthy" when the service is running properly.

Additionally, there's a `/version` endpoint that returns JSON information about the currently active version.

## Version Management

The container supports multiple versions and provides tools for managing them:

### Using the version management script

```bash
# Show current version and available versions
./manage-versions.sh status

# List all available versions
./manage-versions.sh list

# Switch to a specific version (e.g., rollback)
./manage-versions.sh switch build-time

# Force update to latest version
./manage-versions.sh update

# Validate current version
./manage-versions.sh validate

# Clean up old versions (keeps current + 2 most recent)
./manage-versions.sh cleanup
```

### Manual version management

```bash
# Check what versions are available
docker exec <container-name> ls -la /app/versions/

# See current version info
docker exec <container-name> cat /app/web/current/.version

# Check which version is currently active
docker exec <container-name> readlink /app/web/current
```

## Build Arguments

None currently supported.

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
