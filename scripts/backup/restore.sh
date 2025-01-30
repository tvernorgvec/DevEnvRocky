#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
BACKUP_DIR="/var/backup"
ENCRYPTED_BACKUP_DIR="/var/backup/encrypted"
RESTORE_DIR="/var/backup/restore"
LOG_DIR="/var/log/dev-sandbox"
RESTORE_LOG="$LOG_DIR/restore.log"

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$RESTORE_LOG"
}

# Select backup to restore
select_backup() {
    echo "Available backups:"
    select BACKUP in $(ls -t "$ENCRYPTED_BACKUP_DIR"); do
        if [ -n "$BACKUP" ]; then
            echo "Selected backup: $BACKUP"
            return 0
        else
            echo "Invalid selection"
            return 1
        fi
    done
}

# Decrypt backup
decrypt_backup() {
    log "Decrypting backup..."
    
    # Get encryption key from Vault
    ENCRYPTION_KEY=$(vault kv get -field=backup_key secret/backup)
    
    mkdir -p "$RESTORE_DIR"
    openssl enc -aes-256-cbc -d -in "$ENCRYPTED_BACKUP_DIR/$BACKUP" \
        -pass pass:"$ENCRYPTION_KEY" | tar xz -C "$RESTORE_DIR"
    
    if [ $? -eq 0 ]; then
        log "Backup decrypted successfully"
        return 0
    else
        log "Error: Backup decryption failed" "$RED"
        return 1
    fi
}

# Stop services
stop_services() {
    log "Stopping services..."
    docker-compose down
}

# Restore databases
restore_databases() {
    log "Restoring databases..."
    
    # Start database containers
    docker-compose up -d postgres redis influxdb
    sleep 10  # Wait for databases to start
    
    # Restore PostgreSQL
    cat "$RESTORE_DIR/*/postgres_backup.sql" | docker exec -i postgres psql -U postgres
    if [ $? -ne 0 ]; then
        log "Error: PostgreSQL restore failed" "$RED"
        return 1
    fi
    
    # Restore Redis
    docker cp "$RESTORE_DIR/*/redis_backup.rdb" redis:/data/dump.rdb
    docker exec redis redis-cli SHUTDOWN SAVE
    if [ $? -ne 0 ]; then
        log "Error: Redis restore failed" "$RED"
        return 1
    fi
    
    # Restore InfluxDB
    docker exec influxdb influxd restore -portable "$RESTORE_DIR/*/influxdb"
    if [ $? -ne 0 ]; then
        log "Error: InfluxDB restore failed" "$RED"
        return 1
    fi
    
    return 0
}

# Restore configurations
restore_configs() {
    log "Restoring configurations..."
    
    # Restore Docker configurations
    cp -r "$RESTORE_DIR/*/docker" /etc/
    cp -r "$RESTORE_DIR/*/nginx" /etc/
    
    # Restore service configurations
    cp -r "$RESTORE_DIR/*/prometheus" /etc/
    cp -r "$RESTORE_DIR/*/grafana" /etc/
    cp -r "$RESTORE_DIR/*/alertmanager" /etc/
    
    return 0
}

# Start services
start_services() {
    log "Starting services..."
    docker-compose up -d
}

# Verify restoration
verify_restoration() {
    log "Verifying restoration..."
    
    # Check database connections
    if ! docker exec postgres pg_isready; then
        log "Error: PostgreSQL verification failed" "$RED"
        return 1
    fi
    
    if ! docker exec redis redis-cli PING; then
        log "Error: Redis verification failed" "$RED"
        return 1
    fi
    
    # Check service health
    for service in $(docker-compose ps --services); do
        if ! docker-compose ps "$service" | grep -q "Up"; then
            log "Error: Service $service failed to start" "$RED"
            return 1
        fi
    done
    
    return 0
}

# Cleanup
cleanup() {
    log "Cleaning up..."
    rm -rf "$RESTORE_DIR"
}

# Main restore procedure
main() {
    mkdir -p "$LOG_DIR"
    log "Starting restore process..."
    
    select_backup || exit 1
    decrypt_backup || exit 1
    stop_services
    restore_databases || exit 1
    restore_configs || exit 1
    start_services
    verify_restoration || exit 1
    cleanup
    
    log "Restore process completed successfully"
}

# Execute main function
main "$@"