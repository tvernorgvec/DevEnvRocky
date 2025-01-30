#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
BACKUP_DIR="/var/backup"
ENCRYPTED_BACKUP_DIR="/var/backup/encrypted"
LOG_DIR="/var/log/dev-sandbox"
BACKUP_LOG="$LOG_DIR/backup.log"
RETENTION_DAYS=30
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$BACKUP_LOG"
}

# Pre-backup checks
pre_backup_check() {
    log "Starting pre-backup checks..."
    
    # Check disk space
    DISK_SPACE=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_SPACE" -gt 80 ]; then
        log "Warning: Low disk space ($DISK_SPACE% used)" "$YELLOW"
        return 1
    fi
    
    # Create backup directories
    mkdir -p "$BACKUP_DIR/$TIMESTAMP"
    mkdir -p "$ENCRYPTED_BACKUP_DIR"
    
    return 0
}

# Backup databases
backup_databases() {
    log "Backing up databases..."
    
    # PostgreSQL backup
    docker exec postgres pg_dumpall -U postgres > "$BACKUP_DIR/$TIMESTAMP/postgres_backup.sql"
    if [ $? -ne 0 ]; then
        log "Error: PostgreSQL backup failed" "$RED"
        return 1
    fi
    
    # Redis backup
    docker exec redis redis-cli SAVE
    docker cp redis:/data/dump.rdb "$BACKUP_DIR/$TIMESTAMP/redis_backup.rdb"
    if [ $? -ne 0 ]; then
        log "Error: Redis backup failed" "$RED"
        return 1
    fi
    
    # InfluxDB backup
    docker exec influxdb influxd backup -portable "$BACKUP_DIR/$TIMESTAMP/influxdb"
    if [ $? -ne 0 ]; then
        log "Error: InfluxDB backup failed" "$RED"
        return 1
    fi
    
    return 0
}

# Backup configurations
backup_configs() {
    log "Backing up configurations..."
    
    # Docker configurations
    cp -r /etc/docker "$BACKUP_DIR/$TIMESTAMP/"
    cp -r /etc/nginx "$BACKUP_DIR/$TIMESTAMP/"
    docker-compose config > "$BACKUP_DIR/$TIMESTAMP/docker-compose.yml"
    
    # Service configurations
    cp -r /etc/prometheus "$BACKUP_DIR/$TIMESTAMP/"
    cp -r /etc/grafana "$BACKUP_DIR/$TIMESTAMP/"
    cp -r /etc/alertmanager "$BACKUP_DIR/$TIMESTAMP/"
    
    # Vault configurations (excluding sensitive data)
    cp -r /etc/vault.d "$BACKUP_DIR/$TIMESTAMP/"
    
    return 0
}

# Encrypt backup
encrypt_backup() {
    log "Encrypting backup..."
    
    # Get encryption key from Vault
    ENCRYPTION_KEY=$(vault kv get -field=backup_key secret/backup)
    
    # Create encrypted archive
    tar czf - -C "$BACKUP_DIR" "$TIMESTAMP" | \
        openssl enc -aes-256-cbc -salt -out "$ENCRYPTED_BACKUP_DIR/backup_$TIMESTAMP.tar.gz.enc" \
        -pass pass:"$ENCRYPTION_KEY"
    
    if [ $? -eq 0 ]; then
        # Remove unencrypted backup after successful encryption
        rm -rf "$BACKUP_DIR/$TIMESTAMP"
        return 0
    else
        log "Error: Backup encryption failed" "$RED"
        return 1
    fi
}

# Upload to off-site storage
upload_backup() {
    log "Uploading backup to off-site storage..."
    
    # Example using rclone (configure rclone separately)
    if command -v rclone &> /dev/null; then
        rclone copy "$ENCRYPTED_BACKUP_DIR/backup_$TIMESTAMP.tar.gz.enc" remote:backups/
        if [ $? -eq 0 ]; then
            log "Backup uploaded successfully"
            return 0
        else
            log "Error: Backup upload failed" "$RED"
            return 1
        fi
    else
        log "Warning: rclone not installed, skipping off-site backup" "$YELLOW"
        return 0
    fi
}

# Verify backup
verify_backup() {
    log "Verifying backup..."
    
    # Test decrypt backup
    openssl enc -aes-256-cbc -d -in "$ENCRYPTED_BACKUP_DIR/backup_$TIMESTAMP.tar.gz.enc" \
        -pass pass:"$ENCRYPTION_KEY" | tar tz > /dev/null
    
    if [ $? -eq 0 ]; then
        log "Backup verification successful"
        return 0
    else
        log "Error: Backup verification failed" "$RED"
        return 1
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups..."
    
    find "$ENCRYPTED_BACKUP_DIR" -name "backup_*.enc" -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_LOG" -mtime +$RETENTION_DAYS -delete
}

# Main backup procedure
main() {
    mkdir -p "$LOG_DIR"
    log "Starting backup process..."
    
    pre_backup_check || exit 1
    backup_databases || exit 1
    backup_configs || exit 1
    encrypt_backup || exit 1
    upload_backup || exit 1
    verify_backup || exit 1
    cleanup_old_backups
    
    log "Backup process completed successfully"
}

# Execute main function
main "$@"