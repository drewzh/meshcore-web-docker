FROM nginx:alpine

# Install required tools for downloading, processing, and SSL certificates
RUN apk add --no-cache curl grep sed findutils file bash unzip openssl

# Create directories
RUN mkdir -p /app/web /app/scripts /app/versions /etc/nginx/ssl

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

# Copy nginx configuration template
COPY nginx.conf /etc/nginx/nginx.conf.template

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Environment variables for MeshCore download configuration
ENV MESHCORE_BASE_URL="https://files.liamcottle.net/MeshCore"

# Environment variables for Unraid compatibility (optional)
ENV PUID=""
ENV PGID=""

# Environment variable for HTTPS configuration
ENV ENABLE_HTTPS="false"

# Expose ports 80 and 443 (443 only used when ENABLE_HTTPS=true)
EXPOSE 80 443

# Set entrypoint
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
