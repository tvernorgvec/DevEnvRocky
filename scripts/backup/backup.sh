#!/bin/bash

# Configuration
BACKUP_DIR="/var/backup"
LOG_FILE="/var/backup/backup.log"
RETENTION_DAYS=7

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Get timestamp for backup file
TIMESTAMP=$(date +%Y-%m-%d_%H_%M_%S)
BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.sql"
ENCRYPTED_FILE="$BACKUP_FILE.enc"

# Perform database backup
echo "Starting backup at $(date)" >> "$LOG_FILE"
pg_dumpall > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    # Encrypt backup (using OpenSSL as a simpler alternative to Vault in this context)
    openssl enc -aes-256-cbc -salt -in "$BACKUP_FILE" \
        -out "$ENCRYPTED_FILE" \
        -pass pass:"${BACKUP_ENCRYPTION_KEY:-default_key}"
    
    if [ $? -eq 0 ]; then
        echo "Backup encrypted successfully at $(date)" >> "$LOG_FILE"
        rm "$BACKUP_FILE"  # Remove unencrypted backup
        
        # Cleanup old backups
        find "$BACKUP_DIR" -name "*.enc" -mtime +$RETENTION_DAYS -delete
        
        # Verify backup
        echo "Verifying backup..." >> "$LOG_FILE"
        if [ -s "$ENCRYPTED_FILE" ]; then
            echo "Backup completed and verified at $(date)" >> "$LOG_FILE"
        else
            echo "ERROR: Backup verification failed at $(date)" >> "$LOG_FILE"
        fi
    else
        echo "ERROR: Backup encryption failed at $(date)" >> "$LOG_FILE"
        rm "$BACKUP_FILE"
    fi
else
    echo "ERROR: Database backup failed at $(date)" >> "$LOG_FILE"
fi