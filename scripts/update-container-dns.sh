#!/bin/bash

# Configuration
NGINX_UPSTREAM_DIR="/etc/nginx/conf.d/upstreams"
DOMAIN="isp-pybox.gvec.net"

# Get list of running containers
CONTAINERS=$(docker ps --format '{{.Names}}')

# Create upstream entries
for CONTAINER in $CONTAINERS; do
    # Get container port mappings
    PORTS=$(docker port "$CONTAINER" | awk '{print $3}' | cut -d':' -f2)
    
    # Skip if no ports exposed
    [ -z "$PORTS" ] && continue
    
    # Create upstream configuration
    cat > "$NGINX_UPSTREAM_DIR/${CONTAINER}.conf" <<EOF
upstream ${CONTAINER} {
    server ${CONTAINER}:${PORTS};
    keepalive 32;
}
EOF

    # Add container routing to containers.conf
    sed -i "/# Dynamic container routing/a \
    if (\$container = \"${CONTAINER}\") {\n \
        proxy_pass http://${CONTAINER};\n \
    }" /etc/nginx/conf.d/containers.conf
done

# Reload Nginx configuration
nginx -t && nginx -s reload