#!/bin/bash

# Create systemd timer for weekly updates
cat > /etc/systemd/system/sandbox-update.service <<EOF
[Unit]
Description=Development Sandbox Update Service
After=network.target

[Service]
Type=oneshot
ExecStart=/home/project/scripts/update/update-system.sh
StandardOutput=append:/var/log/dev-sandbox/scheduled-updates.log
StandardError=append:/var/log/dev-sandbox/scheduled-updates.log

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/sandbox-update.timer <<EOF
[Unit]
Description=Weekly Development Sandbox Updates
Requires=sandbox-update.service

[Timer]
OnCalendar=Sun 02:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd and enable timer
systemctl daemon-reload
systemctl enable sandbox-update.timer
systemctl start sandbox-update.timer

echo "Update scheduler installed and configured"