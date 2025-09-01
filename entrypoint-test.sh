#!/bin/bash

# Minimal entrypoint for testing
echo "Minimal entrypoint starting..."
echo "Current directory: $(pwd)"
echo "Entrypoint exists: $(test -f /entrypoint.sh && echo 'yes' || echo 'no')"
echo "Loading page exists: $(test -f /app/versions/loading/index.html && echo 'yes' || echo 'no')"

# Just start nginx without all the update logic for testing
if [ "$1" = "--test-mode" ]; then
    echo "Test mode - starting nginx directly"
    exec nginx -g "daemon off;"
fi

# Normal entrypoint logic
exec /entrypoint.sh
