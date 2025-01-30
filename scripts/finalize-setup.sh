#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
CONFIG_DIR="/etc/dev-sandbox"
LOG_DIR="/var/log/dev-sandbox"
LOG_FILE="$LOG_DIR/finalize.log"

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Create systemd service for Docker Compose
setup_systemd() {
    log "Setting up systemd service..."
    
    cat > /etc/systemd/system/docker-compose-app.service <<EOF
[Unit]
Description=Docker Compose Application Service
Requires=docker.service
After=docker.service network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/developer/sandbox_project
ExecStartPre=/usr/bin/docker-compose down
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
User=developer
Group=developer
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable docker-compose-app.service
    systemctl start docker-compose-app.service
}

# Verify services
verify_services() {
    log "Verifying services..."
    
    services=(
        "docker"
        "prometheus"
        "grafana"
        "alertmanager"
        "nginx"
        "postgres"
        "redis"
        "vault"
    )
    
    for service in "${services[@]}"; do
        if docker-compose ps "$service" | grep -q "Up"; then
            log "✅ $service is running"
        else
            log "❌ $service is not running" "$RED"
            return 1
        fi
    done
    
    return 0
}

# Create documentation
create_documentation() {
    log "Creating documentation..."
    
    cat > README.md <<EOF
# Development Sandbox Setup

## Overview

This development environment provides a comprehensive setup for modern application development with:

- 🐳 Container Management
  - Docker and Docker Compose
  - Resource quotas and monitoring
  - Container security best practices

- 🔒 Security Features
  - SELinux enforcement
  - Fail2Ban protection
  - SSL/TLS with auto-renewal
  - Vault for secrets management
  - Network segmentation

- 📊 Monitoring & Logging
  - Prometheus metrics collection
  - Grafana dashboards
  - AlertManager for notifications
  - ELK stack for log aggregation
  - Container resource monitoring

- 🔄 CI/CD Integration
  - GitHub Actions workflows
  - Automated testing
  - Security scanning
  - Deployment automation

- 🗄️ Database Services
  - PostgreSQL with automated backups
  - Redis for caching
  - InfluxDB for time-series data

## Access Information

- Grafana: https://${DOMAIN}:3000
  - Default credentials in Vault
- Prometheus: https://${DOMAIN}:9090
- AlertManager: https://${DOMAIN}:9093
- Kibana: https://${DOMAIN}:5601

## Security Notes

1. All passwords are stored in Vault
2. SSL certificates auto-renew via Certbot
3. Regular security audits are scheduled
4. Network traffic is monitored and logged

## Maintenance

### Backups
- Daily automated backups at 1 AM
- 30-day retention policy
- Encrypted backup storage
- Off-site backup replication

### Updates
- System updates: Weekly (Sundays at 2 AM)
- Security patches: Automated
- Docker images: Weekly refresh
- SSL certificates: Auto-renewal

### Monitoring
- Resource usage alerts
- Service health monitoring
- Security event notifications
- Performance metrics tracking

## Troubleshooting

1. Service Issues
   - Check logs: \`docker-compose logs [service]\`
   - Verify health: \`docker-compose ps\`
   - Restart service: \`docker-compose restart [service]\`

2. Network Issues
   - Check firewall: \`firewall-cmd --list-all\`
   - Verify DNS: \`dig ${DOMAIN}\`
   - Test SSL: \`openssl s_client -connect ${DOMAIN}:443\`

3. Database Issues
   - Check logs: \`docker-compose logs postgres\`
   - Verify backup: \`./scripts/backup/verify_backup.sh\`
   - Test connection: \`pg_isready -h localhost\`

## Support

For issues or assistance:
1. Check the monitoring dashboard
2. Review service logs
3. Contact the system administrator

## Security Policies

1. Access Control
   - Use SSH keys only
   - 2FA required for admin access
   - Regular access audits

2. Network Security
   - Internal services isolated
   - Rate limiting enabled
   - DDoS protection active

3. Data Protection
   - Encrypted backups
   - Secure secret storage
   - Regular security scans

## Disaster Recovery

1. Backup Restoration
   \`\`\`bash
   ./scripts/backup/restore.sh
   \`\`\`

2. Service Recovery
   \`\`\`bash
   docker-compose down
   docker-compose up -d
   \`\`\`

3. System Rollback
   \`\`\`bash
   ./scripts/update/rollback.sh
   \`\`\`

EOF
}

# Verify system health
verify_system_health() {
    log "Verifying system health..."
    
    # Check system resources
    MEMORY_USAGE=$(free | awk '/Mem:/ {printf("%.2f"), $3/$2 * 100}')
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f1)
    
    log "System Status:"
    log "- Memory Usage: $MEMORY_USAGE%"
    log "- Disk Usage: $DISK_USAGE%"
    log "- CPU Load: $CPU_LOAD"
    
    # Check critical services
    systemctl is-active --quiet docker || {
        log "Error: Docker is not running" "$RED"
        return 1
    }
    
    # Verify network connectivity
    curl -s --head https://mirror.rockylinux.org > /dev/null || {
        log "Error: Network connectivity issues" "$RED"
        return 1
    }
    
    return 0
}

# Main function
main() {
    mkdir -p "$LOG_DIR"
    log "Starting final configuration..."
    
    setup_systemd || exit 1
    verify_services || exit 1
    create_documentation || exit 1
    verify_system_health || exit 1
    
    log "Final configuration completed successfully"
    
    cat <<EOF

====================================
Setup Complete
====================================

Your development environment is ready!

Access your services at:
- Grafana: https://${DOMAIN}:3000
- Prometheus: https://${DOMAIN}:9090
- AlertManager: https://${DOMAIN}:9093

Next Steps:
1. Review the README.md for detailed documentation
2. Verify all services in the monitoring dashboard
3. Test the backup and restore procedures
4. Configure additional users and access controls

For more information, see the documentation.
EOF
}

# Execute main function
main "$@"