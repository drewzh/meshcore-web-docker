FROM nginx:alpine

# Install required tools for downloading and processing the web app
RUN apk add --no-cache wget curl grep sed findutils file

# Create directories
RUN mkdir -p /app/web /app/scripts /app/versions

# Copy scripts first (for better layer caching)
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Pre-fetch the MeshCore web application during build
RUN /app/scripts/download-meshcore.sh /app/versions/build-time "build-time" || \
    (echo "WARNING: Failed to download MeshCore during build - container will work offline but won't have initial content" && \
    mkdir -p /app/versions/build-time && \
    echo "<html><body><h1>MeshCore Offline</h1><p>No internet connection available during build or runtime.</p></body></html>" > /app/versions/build-time/index.html)

# Set up the initial symlink to the build-time version
RUN ln -sf /app/versions/build-time /app/web/current

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose port 80
EXPOSE 80

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
