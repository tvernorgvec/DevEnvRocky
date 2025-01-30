#!/bin/bash

# InfluxDB and Vault Installation
echo "Setting up InfluxDB and Vault..."

# 3.1 Install and Configure InfluxDB
echo "Installing InfluxDB..."

# Add InfluxDB repository
cat > /etc/yum.repos.d/influxdb.repo <<EOF
[influxdb]
name=InfluxDB Repository - RHEL
baseurl=https://repos.influxdata.com/rhel/9/x86_64/stable
enabled=1
gpgcheck=1
gpgkey=https://repos.influxdata.com/influxdb.key
EOF

# Import InfluxDB GPG key
curl -sL https://repos.influxdata.com/influxdb.key | gpg --dearmor | tee /etc/pki/rpm-gpg/influxdb.gpg > /dev/null

# Install InfluxDB
if ! dnf install -y influxdb; then
    echo "Error: InfluxDB installation failed"
    exit 1
fi

# Create InfluxDB directories and set permissions
mkdir -p /var/lib/influxdb
mkdir -p /etc/influxdb
chown -R influxdb:influxdb /var/lib/influxdb
chown -R influxdb:influxdb /etc/influxdb

# Configure InfluxDB
cat > /etc/influxdb/influxdb.conf <<EOF
[meta]
  dir = "/var/lib/influxdb/meta"

[data]
  dir = "/var/lib/influxdb/data"
  wal-dir = "/var/lib/influxdb/wal"
  series-id-set-cache-size = 100

[coordinator]
  write-timeout = "10s"
  max-concurrent-queries = 10
  query-timeout = "30s"
  log-queries-after = "10s"
  max-select-point = 50000
  max-select-series = 1000
  max-select-buckets = 1000

[retention]
  enabled = true
  check-interval = "30m"

[shard-precreation]
  enabled = true
  check-interval = "10m"
  advance-period = "30m"

[monitor]
  store-enabled = true
  store-database = "_internal"
  store-interval = "10s"

[http]
  enabled = true
  bind-address = ":8086"
  auth-enabled = true
  log-enabled = true
  write-tracing = false
  pprof-enabled = false
  https-enabled = false
  max-row-limit = 10000
  max-connection-limit = 0
  shared-secret = ""
  realm = "InfluxDB"
  unix-socket-enabled = false
  bind-socket = "/var/run/influxdb.sock"

[logging]
  format = "auto"
  level = "info"
  suppress-logo = false
EOF

# Start and enable InfluxDB
systemctl start influxdb
systemctl enable influxdb

# Verify InfluxDB is running
if ! systemctl is-active --quiet influxdb; then
    echo "Error: InfluxDB failed to start"
    exit 1
fi

# 3.2 Install and Configure Vault
echo "Installing Vault..."

# Add HashiCorp repository
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo

# Install Vault
if ! dnf install -y vault; then
    echo "Error: Vault installation failed"
    exit 1
fi

# Create Vault configuration directory
mkdir -p /etc/vault.d
mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault

# Configure Vault
cat > /etc/vault.d/vault.hcl <<EOF
storage "file" {
    path = "/opt/vault/data"
}

listener "tcp" {
    address = "127.0.0.1:8200"
    tls_disable = 1
}

ui = true
api_addr = "http://127.0.0.1:8200"
disable_mlock = true

telemetry {
    prometheus_retention_time = "30s"
    disable_hostname = true
}
EOF

# Set Vault file permissions
chown -R vault:vault /etc/vault.d
chmod 640 /etc/vault.d/vault.hcl

# Start and enable Vault
systemctl start vault
systemctl enable vault

# Verify Vault is running
if ! systemctl is-active --quiet vault; then
    echo "Error: Vault failed to start"
    exit 1
fi

# 3.3 Configure InfluxDB with Vault
echo "Configuring InfluxDB with Vault..."

# Wait for Vault to be ready
sleep 5

# Initialize Vault if needed
if ! vault operator init -status > /dev/null 2>&1; then
    echo "Initializing Vault..."
    vault operator init > /root/vault-keys.txt
    chmod 600 /root/vault-keys.txt
    echo "Vault initialization keys saved to /root/vault-keys.txt"
fi

# Create InfluxDB admin user and password
INFLUXDB_ADMIN_USER="admin"
INFLUXDB_ADMIN_PASSWORD=$(openssl rand -base64 32)

# Store InfluxDB credentials in Vault
vault kv put secret/influxdb \
    admin_user="$INFLUXDB_ADMIN_USER" \
    admin_password="$INFLUXDB_ADMIN_PASSWORD"

# Create initial InfluxDB admin user
curl -XPOST "http://localhost:8086/query" \
    --data-urlencode "q=CREATE USER ${INFLUXDB_ADMIN_USER} WITH PASSWORD '${INFLUXDB_ADMIN_PASSWORD}' WITH ALL PRIVILEGES"

# Verify InfluxDB admin user
if ! curl -s -XPOST "http://localhost:8086/query" \
    -u "${INFLUXDB_ADMIN_USER}:${INFLUXDB_ADMIN_PASSWORD}" \
    --data-urlencode "q=SHOW USERS" | grep -q "${INFLUXDB_ADMIN_USER}"; then
    echo "Error: Failed to create InfluxDB admin user"
    exit 1
fi

echo "InfluxDB and Vault setup completed successfully"
echo "Important: Please securely store the Vault initialization keys from /root/vault-keys.txt"