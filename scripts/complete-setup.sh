#!/bin/bash

# Source the main installation script
source /home/project/install.sh

# Function to initialize Vault
init_vault() {
    log "INFO" "Initializing Vault..."
    
    # Start Vault service
    systemctl start vault || {
        log "ERROR" "Failed to start Vault"
        return 1
    }

    # Initialize Vault and save keys securely
    VAULT_INIT=$(vault operator init -key-shares=5 -key-threshold=3)
    echo "$VAULT_INIT" | sudo tee /root/vault-keys.txt > /dev/null
    chmod 600 /root/vault-keys.txt

    # Extract root token
    ROOT_TOKEN=$(echo "$VAULT_INIT" | grep "Initial Root Token:" | cut -d: -f2 | tr -d " ")
    export VAULT_TOKEN="$ROOT_TOKEN"

    # Unseal Vault using first three keys
    for i in {1..3}; do
        KEY=$(echo "$VAULT_INIT" | grep "Unseal Key $i:" | cut -d: -f2 | tr -d " ")
        vault operator unseal "$KEY" || {
            log "ERROR" "Failed to unseal Vault"
            return 1
        }
    done

    return 0
}

# Function to setup monitoring stack
setup_monitoring() {
    log "INFO" "Setting up monitoring stack..."
    
    # Create monitoring configuration
    mkdir -p /etc/prometheus
    mkdir -p /etc/alertmanager
    mkdir -p /etc/grafana

    # Generate secure passwords
    GRAFANA_ADMIN_PASS=$(openssl rand -base64 32)

    # Store credentials in Vault
    vault kv put secret/monitoring \
        grafana_admin_password="$GRAFANA_ADMIN_PASS" || {
        log "ERROR" "Failed to store monitoring credentials in Vault"
        return 1
    }

    # Start monitoring services
    docker-compose -f /home/project/docker-compose.yml up -d prometheus grafana alertmanager || {
        log "ERROR" "Failed to start monitoring services"
        return 1
    }

    return 0
}

# Function to setup logging stack
setup_logging() {
    log "INFO" "Setting up logging stack..."
    
    # Start ELK stack
    docker-compose -f /home/project/docker-compose.yml up -d elasticsearch kibana logstash || {
        log "ERROR" "Failed to start logging services"
        return 1
    }

    return 0
}

# Function to setup SSL/TLS
setup_ssl() {
    log "INFO" "Setting up SSL/TLS certificates..."
    
    # Install certbot and obtain certificates
    certbot certonly --standalone \
        -d "$DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        --rsa-key-size 4096 || {
        log "ERROR" "Failed to obtain SSL certificates"
        return 1
    }

    return 0
}

# Function to setup automated backups
setup_backups() {
    log "INFO" "Setting up automated backups..."
    
    # Install backup script
    cp /home/project/scripts/backup/backup-manager.sh /usr/local/bin/
    chmod +x /usr/local/bin/backup-manager.sh

    # Create backup service and timer
    cp /home/project/scripts/backup/schedule-backups.sh /usr/local/bin/
    chmod +x /usr/local/bin/schedule-backups.sh
    
    # Initialize backup system
    /usr/local/bin/schedule-backups.sh || {
        log "ERROR" "Failed to setup backup system"
        return 1
    }

    return 0
}

# Function to verify complete setup
verify_setup() {
    log "INFO" "Verifying complete setup..."
    
    # Check all required services
    local services=(
        "docker"
        "vault"
        "prometheus"
        "grafana"
        "alertmanager"
        "elasticsearch"
        "kibana"
        "logstash"
    )

    for service in "${services[@]}"; do
        if [[ $service =~ ^(prometheus|grafana|alertmanager|elasticsearch|kibana|logstash)$ ]]; then
            docker-compose -f /home/project/docker-compose.yml ps "$service" | grep -q "Up" || {
                log "ERROR" "Service $service is not running"
                return 1
            }
        else
            systemctl is-active --quiet "$service" || {
                log "ERROR" "Service $service is not running"
                return 1
            }
        fi
    done

    # Verify Vault
    vault status || {
        log "ERROR" "Vault is not properly initialized"
        return 1
    }

    # Verify SSL certificates
    certbot certificates | grep -q "Expiry Date" || {
        log "ERROR" "SSL certificates are not properly installed"
        return 1
    }

    # Verify backup system
    systemctl is-active --quiet sandbox-backup.timer || {
        log "ERROR" "Backup system is not properly configured"
        return 1
    }

    return 0
}

# Main function
main() {
    log "INFO" "Starting complete setup..."

    # Run base installation first
    install || exit 1

    # Initialize additional components
    init_vault || exit 1
    setup_monitoring || exit 1
    setup_logging || exit 1
    setup_ssl || exit 1
    setup_backups || exit 1

    # Verify complete setup
    verify_setup || exit 1

    log "INFO" "Complete setup finished successfully"

    # Display completion message
    cat <<EOF

====================================
Complete Setup Finished
====================================

Access your services at:
- Grafana: https://${DOMAIN}:3000
- Prometheus: https://${DOMAIN}:9090
- Kibana: https://${DOMAIN}:5601
- Alertmanager: https://${DOMAIN}:9093

Credentials are stored in Vault.
Backup system is configured and running.
SSL certificates are installed and active.

Next Steps:
1. Review monitoring dashboards
2. Configure additional alerting rules
3. Review backup configuration
4. Test disaster recovery procedures

For more information, see the documentation.
EOF
}

# Execute main function
main "$@"