FROM nginx:alpine

# Install required tools for downloading and processing the web app
RUN apk add --no-cache wget curl grep sed findutils file bash unzip

# Create directories
RUN mkdir -p /app/web /app/scripts /app/versions

# Copy scripts first (for better layer caching)
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Create loading page directory and copy the loading HTML
RUN mkdir -p /app/versions/loading
COPY loading.html /app/versions/loading/index.html

# Create a version file for the loading page
RUN echo '{"status":"loading","version":"loading-page","description":"MeshCore is downloading..."}' > /app/versions/loading/.version

# Set up the initial symlink to the loading page
RUN ln -sf /app/versions/loading /app/web/current

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Environment variables for MeshCore download configuration
ENV MESHCORE_BASE_URL="https://files.liamcottle.net/MeshCore"
ENV MESHCORE_ZIP_URL="https://files.liamcottle.net/MeshCore/v1.25.0/MeshCore-v1.25.0+47-aef292a-web.zip"

# Expose port 80
EXPOSE 80

# Set entrypoint
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
