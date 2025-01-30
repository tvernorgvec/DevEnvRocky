#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
LOG_DIR="/var/log/dev-sandbox"
UPDATE_LOG="$LOG_DIR/update.log"

# Function to log messages
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$UPDATE_LOG"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    dnf update -y || {
        log "Failed to update system packages" "$RED"
        return 1
    }
}

# Update Docker images
update_docker() {
    log "Updating Docker images..."
    docker-compose pull || {
        log "Failed to pull Docker images" "$RED"
        return 1
    }
    
    docker-compose up -d || {
        log "Failed to update containers" "$RED"
        return 1
    }
}

# Update container DNS entries
update_dns() {
    log "Updating container DNS entries..."
    /home/project/scripts/update-container-dns.sh || {
        log "Failed to update container DNS" "$RED"
        return 1
    }
}

# Verify services
verify_services() {
    log "Verifying services..."
    local services=(
        "nginx"
        "docker"
        "prometheus"
        "grafana"
        "alertmanager"
    )
    
    for service in "${services[@]}"; do
        if [[ $service =~ ^(prometheus|grafana|alertmanager)$ ]]; then
            if ! docker-compose ps | grep -q "$service.*Up"; then
                log "Service $service is not running" "$RED"
                return 1
            fi
        else
            if ! systemctl is-active --quiet "$service"; then
                log "Service $service is not running" "$RED"
                return 1
            fi
        fi
    done
}

# Main function
main() {
    log "Starting system update..."
    
    update_system || exit 1
    update_docker || exit 1
    update_dns || exit 1
    verify_services || exit 1
    
    log "System update completed successfully"
}

# Execute main function
main "$@"