#!/bin/bash

# Configuration
BACKUP_DIR="/var/backup"
LOG_FILE="/var/backup/backup.log"
TEMP_DIR="/tmp/backup_verify"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Get latest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.enc | head -n 1)

if [ -f "$LATEST_BACKUP" ]; then
    echo "Verifying backup: $LATEST_BACKUP" >> "$LOG_FILE"
    
    # Decrypt backup
    DECRYPTED_FILE="$TEMP_DIR/backup_verify.sql"
    openssl enc -aes-256-cbc -d -in "$LATEST_BACKUP" \
        -out "$DECRYPTED_FILE" \
        -pass pass:"${BACKUP_ENCRYPTION_KEY:-default_key}"
    
    if [ $? -eq 0 ]; then
        # Attempt to verify backup by checking if it's a valid SQL file
        if head -n 1 "$DECRYPTED_FILE" | grep -q "PostgreSQL database dump"; then
            echo "Backup verification successful at $(date)" >> "$LOG_FILE"
        else
            echo "ERROR: Backup verification failed - not a valid backup file" >> "$LOG_FILE"
        fi
    else
        echo "ERROR: Backup decryption failed at $(date)" >> "$LOG_FILE"
    fi
    
    # Remove temporary files
    rm -rf "$TEMP_DIR"
else
    echo "ERROR: No backup found to verify at $(date)" >> "$LOG_FILE"
fi