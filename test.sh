#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $1"
}

# Function to test if a service is reachable
test_service() {
    local url="$1"
    local name="$2"
    
    log "Testing $name at $url..."
    
    if curl --silent --head --fail --max-time 10 "$url" > /dev/null 2>&1; then
        log "✓ $name is reachable"
        return 0
    else
        error "✗ $name is not reachable"
        return 1
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local url="$1"
    local name="$2"
    local max_wait="${3:-60}"
    local wait_time=0
    
    log "Waiting for $name to be ready (max ${max_wait}s)..."
    
    while [ $wait_time -lt $max_wait ]; do
        if curl --silent --head --fail --max-time 5 "$url" > /dev/null 2>&1; then
            log "✓ $name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    echo ""
    error "✗ $name failed to become ready within ${max_wait}s"
    return 1
}

# Main test function
main() {
    log "Starting MeshCore Web Docker tests..."
    
    # Test if original MeshCore site is reachable
    if test_service "https://app.meshcore.nz/" "Original MeshCore site"; then
        log "Original site is accessible - updates should work"
    else
        warn "Original site is not accessible - container will use cached version only"
    fi
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running or not accessible"
        exit 1
    fi
    
    log "Docker is running"
    
    # Build the image
    log "Building Docker image..."
    if docker-compose build; then
        log "✓ Docker image built successfully"
    else
        error "✗ Failed to build Docker image"
        exit 1
    fi
    
    # Start the container
    log "Starting container..."
    if docker-compose up -d; then
        log "✓ Container started"
    else
        error "✗ Failed to start container"
        exit 1
    fi
    
    # Wait for the service to be ready
    if wait_for_service "http://localhost:8080/health" "MeshCore Web container" 120; then
        log "✓ Container is healthy"
    else
        error "✗ Container health check failed"
        docker-compose logs meshcore-web
        exit 1
    fi
    
    # Test the main application
    if test_service "http://localhost:8080/" "MeshCore Web application"; then
        log "✓ Application is serving content"
    else
        error "✗ Application is not responding"
        docker-compose logs meshcore-web
        exit 1
    fi
    
    # Test the version endpoint
    log "Testing version endpoint..."
    if curl -s http://localhost:8080/version | grep -q "version\|downloaded_at"; then
        log "✓ Version endpoint is working"
        local version_info
        version_info=$(curl -s http://localhost:8080/version 2>/dev/null || echo "Could not fetch version")
        log "Version info: $version_info"
    else
        warn "Version endpoint not working (this might be normal if using fallback content)"
    fi
    
    # Show some info about the running container
    log "Container information:"
    docker-compose ps
    
    log "Recent logs:"
    docker-compose logs --tail=10 meshcore-web
    
    log "🎉 All tests passed! MeshCore Web Docker is working correctly."
    log "   - Application: http://localhost:8080/"
    log "   - Health check: http://localhost:8080/health"
    log ""
    log "To stop: docker-compose down"
    log "To view logs: docker-compose logs -f meshcore-web"
}

# Handle script arguments
case "${1:-test}" in
    "test")
        main
        ;;
    "build")
        log "Building Docker image..."
        docker-compose build
        ;;
    "start")
        log "Starting container..."
        docker-compose up -d
        ;;
    "stop")
        log "Stopping container..."
        docker-compose down
        ;;
    "logs")
        docker-compose logs -f meshcore-web
        ;;
    "restart")
        log "Restarting container..."
        docker-compose restart meshcore-web
        ;;
    "clean")
        log "Cleaning up..."
        docker-compose down -v
        docker image rm meshcore-web-docker_meshcore-web 2>/dev/null || true
        docker volume rm meshcore-web-docker_meshcore-versions 2>/dev/null || true
        ;;
    *)
        echo "Usage: $0 [test|build|start|stop|logs|restart|clean]"
        echo ""
        echo "Commands:"
        echo "  test    - Run full test suite (default)"
        echo "  build   - Build Docker image"
        echo "  start   - Start container"
        echo "  stop    - Stop container"
        echo "  logs    - Show container logs"
        echo "  restart - Restart container"
        echo "  clean   - Stop and remove all containers and volumes"
        exit 1
        ;;
esac
