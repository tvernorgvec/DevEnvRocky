#!/bin/bash

# Create project directory structure
mkdir -p ~/sandbox_project/{projectx,projecty,config/{prometheus,alertmanager,grafana/{provisioning/{datasources,dashboards},dashboards}},elasticsearch,kibana,registry}

# Generate secure passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
GRAFANA_PASSWORD=$(openssl rand -base64 32)

# Store passwords in Vault
vault kv put secret/postgres password="$POSTGRES_PASSWORD"
vault kv put secret/redis password="$REDIS_PASSWORD"
vault kv put secret/grafana password="$GRAFANA_PASSWORD"

cd ~/sandbox_project