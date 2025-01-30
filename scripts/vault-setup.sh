#!/bin/bash

# Configuration
VAULT_CONFIG_DIR="/home/project/vault/config"
VAULT_DATA_DIR="/home/project/vault/data"
VAULT_LOGS_DIR="/home/project/vault/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to log messages
log() {
    local level=$1
    shift
    local message=$@
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[$timestamp] [$level]${NC} $message"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR" "Required command $1 not found"
        return 1
    fi
}

# Function to setup Vault directories
setup_vault_dirs() {
    log "INFO" "Creating Vault directories..."
    
    mkdir -p "$VAULT_CONFIG_DIR"
    mkdir -p "$VAULT_DATA_DIR"
    mkdir -p "$VAULT_LOGS_DIR"
    
    chmod 700 "$VAULT_DATA_DIR"
}

# Function to configure Vault
configure_vault() {
    log "INFO" "Configuring Vault..."
    
    cat > "$VAULT_CONFIG_DIR/vault.hcl" <<EOF
storage "file" {
    path = "${VAULT_DATA_DIR}"
}

listener "tcp" {
    address = "127.0.0.1:8200"
    tls_disable = 1
}

api_addr = "http://127.0.0.1:8200"
ui = true

telemetry {
    disable_hostname = true
    prometheus_retention_time = "30s"
}

# Basic audit logging to file
audit {
    type = "file"
    path = "${VAULT_LOGS_DIR}/audit.log"
}
EOF

    chmod 640 "$VAULT_CONFIG_DIR/vault.hcl"
}

# Function to initialize Vault
init_vault() {
    log "INFO" "Initializing Vault..."
    
    # Check if vault command is available
    check_command vault || {
        log "ERROR" "Vault command not found. Please install Vault first."
        return 1
    }
    
    # Start Vault
    vault server -config="$VAULT_CONFIG_DIR/vault.hcl" &
    VAULT_PID=$!
    
    # Wait for Vault to start
    sleep 5
    
    export VAULT_ADDR='http://127.0.0.1:8200'

    # Initialize Vault with 5 key shares and 3 key threshold
    VAULT_INIT=$(vault operator init -key-shares=5 -key-threshold=3)
    
    # Save initialization output
    echo "$VAULT_INIT" > "$VAULT_CONFIG_DIR/vault-init.txt"
    chmod 600 "$VAULT_CONFIG_DIR/vault-init.txt"
    
    # Extract root token and first three unseal keys
    ROOT_TOKEN=$(echo "$VAULT_INIT" | grep "Initial Root Token:" | cut -d: -f2 | tr -d " ")
    UNSEAL_KEY_1=$(echo "$VAULT_INIT" | grep "Unseal Key 1:" | cut -d: -f2 | tr -d " ")
    UNSEAL_KEY_2=$(echo "$VAULT_INIT" | grep "Unseal Key 2:" | cut -d: -f2 | tr -d " ")
    UNSEAL_KEY_3=$(echo "$VAULT_INIT" | grep "Unseal Key 3:" | cut -d: -f2 | tr -d " ")
    
    # Unseal Vault
    vault operator unseal "$UNSEAL_KEY_1"
    vault operator unseal "$UNSEAL_KEY_2"
    vault operator unseal "$UNSEAL_KEY_3"
    
    # Set root token for further operations
    export VAULT_TOKEN="$ROOT_TOKEN"
}

# Function to configure secrets
configure_secrets() {
    log "INFO" "Configuring secrets engines..."
    
    # Enable KV secrets engine
    vault secrets enable -version=2 kv || {
        log "ERROR" "Failed to enable KV secrets engine"
        return 1
    }
    
    # Create secret paths
    vault kv put kv/database/postgresql \
        username="postgres" \
        password="$(openssl rand -base64 32)" || {
        log "ERROR" "Failed to create PostgreSQL secrets"
        return 1
    }
        
    vault kv put kv/database/redis \
        password="$(openssl rand -base64 32)" || {
        log "ERROR" "Failed to create Redis secrets"
        return 1
    }
        
    vault kv put kv/database/influxdb \
        username="admin" \
        password="$(openssl rand -base64 32)" || {
        log "ERROR" "Failed to create InfluxDB secrets"
        return 1
    }
        
    vault kv put kv/monitoring/grafana \
        admin_password="$(openssl rand -base64 32)" || {
        log "ERROR" "Failed to create Grafana secrets"
        return 1
    }
        
    vault kv put kv/ssl/certbot \
        email="admin@example.com" || {
        log "ERROR" "Failed to create SSL secrets"
        return 1
    }
        
    vault kv put kv/backup \
        encryption_key="$(openssl rand -base64 32)" || {
        log "ERROR" "Failed to create backup secrets"
        return 1
    }
        
    vault kv put kv/api \
        key="$(openssl rand -base64 32)" || {
        log "ERROR" "Failed to create API secrets"
        return 1
    }
}

# Function to create policies
create_policies() {
    log "INFO" "Creating Vault policies..."
    
    # Create policy for database access
    cat > "$VAULT_CONFIG_DIR/database-policy.hcl" <<EOF
path "kv/data/database/*" {
    capabilities = ["read"]
}
EOF
    vault policy write database-access "$VAULT_CONFIG_DIR/database-policy.hcl" || {
        log "ERROR" "Failed to create database policy"
        return 1
    }
    
    # Create policy for monitoring access
    cat > "$VAULT_CONFIG_DIR/monitoring-policy.hcl" <<EOF
path "kv/data/monitoring/*" {
    capabilities = ["read"]
}
EOF
    vault policy write monitoring-access "$VAULT_CONFIG_DIR/monitoring-policy.hcl" || {
        log "ERROR" "Failed to create monitoring policy"
        return 1
    }
    
    # Create policy for backup access
    cat > "$VAULT_CONFIG_DIR/backup-policy.hcl" <<EOF
path "kv/data/backup/*" {
    capabilities = ["read"]
}
EOF
    vault policy write backup-access "$VAULT_CONFIG_DIR/backup-policy.hcl" || {
        log "ERROR" "Failed to create backup policy"
        return 1
    }
}

# Function to cleanup
cleanup() {
    if [ -n "$VAULT_PID" ]; then
        kill $VAULT_PID
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Main function
main() {
    log "INFO" "Starting Vault setup..."
    
    setup_vault_dirs || {
        log "ERROR" "Failed to setup Vault directories"
        exit 1
    }
    
    configure_vault || {
        log "ERROR" "Failed to configure Vault"
        exit 1
    }
    
    init_vault || {
        log "ERROR" "Failed to initialize Vault"
        exit 1
    }
    
    configure_secrets || {
        log "ERROR" "Failed to configure secrets"
        exit 1
    }
    
    create_policies || {
        log "ERROR" "Failed to create policies"
        exit 1
    }
    
    log "INFO" "Vault setup completed successfully"
    
    cat <<EOF

====================================
Vault Setup Complete
====================================

Important Information:
- Root token and unseal keys are stored in $VAULT_CONFIG_DIR/vault-init.txt
- Vault is configured with 5 key shares and 3 key threshold
- Basic audit logging is enabled
- Secrets are stored in the KV secrets engine
- Policies are created for different access levels

Configured Secrets:
- Database credentials (PostgreSQL, Redis, InfluxDB)
- Monitoring system credentials (Grafana)
- SSL certificate information
- Backup encryption keys
- API keys

Next Steps:
1. Securely distribute unseal keys to trusted operators
2. Configure additional authentication methods if needed
3. Review and customize policies as required
4. Test secret access from services

IMPORTANT: Make sure to securely store the unseal keys and root token!
EOF
}

# Execute main function
main "$@"