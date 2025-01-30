#!/bin/bash

# Configuration
BACKUP_DIR="/var/backup/pre-update"
LOG_DIR="/var/log/dev-sandbox"
ROLLBACK_LOG="$LOG_DIR/rollback.log"

# Get latest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -n1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "No backup found to rollback to"
    exit 1
fi

echo "Rolling back to backup: $LATEST_BACKUP"

# Stop services
docker-compose down

# Restore configurations
cp -r "$BACKUP_DIR/$LATEST_BACKUP/docker" /etc/
cp -r "$BACKUP_DIR/$LATEST_BACKUP/nginx" /etc/

# Restore database
docker-compose up -d postgres
sleep 10  # Wait for PostgreSQL to start
cat "$BACKUP_DIR/$LATEST_BACKUP/database_backup.sql" | docker exec -i postgres psql -U postgres

# Restart services
docker-compose up -d

echo "Rollback completed"