#!/bin/bash

# Create systemd timer for daily backups
cat > /etc/systemd/system/sandbox-backup.service <<EOF
[Unit]
Description=Development Sandbox Backup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/home/project/scripts/backup/backup-manager.sh
StandardOutput=append:/var/log/dev-sandbox/scheduled-backups.log
StandardError=append:/var/log/dev-sandbox/scheduled-backups.log

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/sandbox-backup.timer <<EOF
[Unit]
Description=Daily Development Sandbox Backups
Requires=sandbox-backup.service

[Timer]
OnCalendar=*-*-* 01:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable sandbox-backup.timer
systemctl start sandbox-backup.timer

echo "Backup scheduler installed and configured"