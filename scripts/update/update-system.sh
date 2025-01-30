#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
LOG_DIR="/var/log/dev-sandbox"
UPDATE_LOG="$LOG_DIR/updates.log"
BACKUP_DIR="/var/backup/pre-update"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$UPDATE_LOG"
}

# Pre-update checks
pre_update_check() {
    log "Starting pre-update checks..."
    
    # Check disk space
    DISK_SPACE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_SPACE" -gt 80 ]; then
        log "Warning: Low disk space ($DISK_SPACE% used)" "$YELLOW"
    fi
    
    # Check system load
    LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1)
    if [ "$(echo "$LOAD > 2" | bc)" -eq 1 ]; then
        log "Warning: High system load ($LOAD)" "$YELLOW"
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR/$TIMESTAMP"
}

# Backup configurations
backup_configs() {
    log "Backing up configurations..."
    
    # Backup important configurations
    cp -r /etc/docker "$BACKUP_DIR/$TIMESTAMP/"
    cp -r /etc/nginx "$BACKUP_DIR/$TIMESTAMP/"
    docker-compose config > "$BACKUP_DIR/$TIMESTAMP/docker-compose.yml"
    
    # Backup database schemas
    docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/$TIMESTAMP/database_backup.sql"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    
    if ! dnf update -y >> "$UPDATE_LOG" 2>&1; then
        log "Error: System update failed" "$RED"
        return 1
    fi
}

# Update Docker components
update_docker() {
    log "Updating Docker components..."
    
    # Update Docker packages
    dnf update -y docker-ce docker-ce-cli containerd.io >> "$UPDATE_LOG" 2>&1
    
    # Update Docker Compose
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep "tag_name" | cut -d '"' -f 4)
    curl -L "https://github.com/docker/compose/releases/download/$LATEST_COMPOSE/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

# Update services
update_services() {
    log "Updating Docker services..."
    
    # Pull latest images
    docker-compose pull >> "$UPDATE_LOG" 2>&1
    
    # Update services one by one
    docker-compose up -d --no-deps --build prometheus
    docker-compose up -d --no-deps --build grafana
    docker-compose up -d --no-deps --build alertmanager
}

# Update security components
update_security() {
    log "Updating security components..."
    
    dnf update -y vault lynis openscap-scanner >> "$UPDATE_LOG" 2>&1
}

# Post-update health checks
health_check() {
    log "Running health checks..."
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log "Error: Docker service is not running" "$RED"
        return 1
    fi
    
    # Check container health
    for container in $(docker ps --format '{{.Names}}'); do
        HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
        if [ "$HEALTH" != "healthy" ] && [ -n "$HEALTH" ]; then
            log "Warning: Container $container is not healthy ($HEALTH)" "$YELLOW"
        fi
    done
    
    # Check critical services
    services=("nginx" "docker" "vault")
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            log "Error: $service is not running" "$RED"
            return 1
        fi
    done
}

# Cleanup old backups and logs
cleanup() {
    log "Cleaning up old backups and logs..."
    
    # Keep last 5 backups
    cd "$BACKUP_DIR" || exit
    ls -t | tail -n +6 | xargs -r rm -rf
    
    # Rotate logs
    find "$LOG_DIR" -name "*.log" -mtime +30 -exec rm {} \;
}

# Main update procedure
main() {
    mkdir -p "$LOG_DIR"
    log "Starting system update process..."
    
    pre_update_check || exit 1
    backup_configs || exit 1
    update_system || exit 1
    update_docker || exit 1
    update_services || exit 1
    update_security || exit 1
    health_check || exit 1
    cleanup
    
    log "Update process completed successfully"
}

# Execute main function
main "$@"