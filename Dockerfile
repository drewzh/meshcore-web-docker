FROM nginx:alpine

# Install required tools for downloading and processing the web app
RUN apk add --no-cache wget curl grep sed findutils file

# Create directories
RUN mkdir -p /app/web /app/scripts /app/versions

# Copy scripts first (for better layer caching)
COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Create loading page directory and copy the loading HTML
RUN mkdir -p /app/versions/loading
COPY loading.html /app/versions/loading/index.html

# Set up the initial symlink to the loading page
RUN ln -sf /app/versions/loading /app/web/current

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Debug: Check what files are available in the build context
COPY . /debug-context/
RUN echo "=== Build context files ===" && ls -la /debug-context/

# Copy entrypoint script and make it executable (try different approach)
COPY entrypoint.sh /tmp/entrypoint.sh
RUN ls -la /tmp/entrypoint.sh && cp /tmp/entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Debug: Verify entrypoint is correctly set up
RUN ls -la /entrypoint.sh && file /entrypoint.sh && head -3 /entrypoint.sh

# Expose port 80
EXPOSE 80

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
