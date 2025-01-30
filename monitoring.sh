#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONFIG_DIR="/etc/dev-sandbox"
LOG_DIR="/var/log/dev-sandbox"
LOG_FILE="$LOG_DIR/monitoring.log"
ERROR_LOG="$LOG_DIR/error.log"
DOMAIN="isp-pybox.gvec.net"
ADMIN_EMAIL="tvernor@gvec.org"
MONITORING_DIR="/opt/monitoring"

# Function to log messages
log() {
    local level=$1
    shift
    local message=$@
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] [$level] $message" >> "$ERROR_LOG"
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! systemctl is-active --quiet docker; then
        log "ERROR" "Docker is not running. Please install and start Docker first."
        return 1
    fi

    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        log "ERROR" "Docker Compose is not installed. Please install it first."
        return 1
    fi

    # Check if monitoring directory exists
    mkdir -p "$MONITORING_DIR" || {
        log "ERROR" "Failed to create monitoring directory"
        return 1
    }

    log "INFO" "Prerequisites check passed"
    return 0
}

# Function to setup Prometheus
setup_prometheus() {
    log "INFO" "Setting up Prometheus..."
    
    mkdir -p "$MONITORING_DIR/prometheus" || {
        log "ERROR" "Failed to create Prometheus directory"
        return 1
    }

    # Create Prometheus configuration
    cat > "$MONITORING_DIR/prometheus/prometheus.yml" <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - "rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'influxdb'
    static_configs:
      - targets: ['influxdb:8086']

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']

  - job_name: 'vault'
    metrics_path: '/v1/sys/metrics'
    params:
      format: ['prometheus']
    static_configs:
      - targets: ['vault:8200']

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
EOF

    # Create alert rules directory
    mkdir -p "$MONITORING_DIR/prometheus/rules"
    
    # Create basic alert rules
    cat > "$MONITORING_DIR/prometheus/rules/alerts.yml" <<EOF
groups:
- name: basic_alerts
  rules:
  - alert: HighCPUUsage
    expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High CPU usage on {{ \$labels.instance }}
      description: CPU usage is above 80% for 5 minutes

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High memory usage on {{ \$labels.instance }}
      description: Memory usage is above 80% for 5 minutes

  - alert: DiskSpaceRunningOut
    expr: (node_filesystem_size_bytes{mountpoint="/"} - node_filesystem_free_bytes{mountpoint="/"}) / node_filesystem_size_bytes{mountpoint="/"} * 100 > 80
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: High disk usage on {{ \$labels.instance }}
      description: Disk usage is above 80% for 5 minutes
EOF

    log "INFO" "Prometheus configuration completed"
    return 0
}

# Function to setup Alertmanager
setup_alertmanager() {
    log "INFO" "Setting up Alertmanager..."
    
    mkdir -p "$MONITORING_DIR/alertmanager" || {
        log "ERROR" "Failed to create Alertmanager directory"
        return 1
    }

    # Create Alertmanager configuration
    cat > "$MONITORING_DIR/alertmanager/config.yml" <<EOF
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'alertmanager@${DOMAIN}'
  smtp_auth_username: '${ADMIN_EMAIL}'
  smtp_auth_password: '${SMTP_PASSWORD:-$(vault kv get -field=smtp_password secret/alertmanager)}'
  smtp_require_tls: true

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'email-notifications'
  routes:
  - match:
      severity: critical
    receiver: 'email-notifications'
    repeat_interval: 1h

receivers:
- name: 'email-notifications'
  email_configs:
  - to: '${ADMIN_EMAIL}'
    send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
EOF

    log "INFO" "Alertmanager configuration completed"
    return 0
}

# Function to setup Grafana
setup_grafana() {
    log "INFO" "Setting up Grafana..."
    
    mkdir -p "$MONITORING_DIR/grafana/provisioning/datasources" || {
        log "ERROR" "Failed to create Grafana directories"
        return 1
    }

    # Create Grafana datasources configuration
    cat > "$MONITORING_DIR/grafana/provisioning/datasources/datasources.yml" <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: false

  - name: InfluxDB
    type: influxdb
    access: proxy
    url: http://influxdb:8086
    database: metrics
    user: \${INFLUXDB_USER:-$(vault kv get -field=user secret/influxdb)}
    secureJsonData:
      password: \${INFLUXDB_PASSWORD:-$(vault kv get -field=password secret/influxdb)}
    editable: false
EOF

    # Create Grafana dashboard provisioning configuration
    mkdir -p "$MONITORING_DIR/grafana/provisioning/dashboards"
    cat > "$MONITORING_DIR/grafana/provisioning/dashboards/dashboards.yml" <<EOF
apiVersion: 1

providers:
  - name: 'Default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
EOF

    log "INFO" "Grafana configuration completed"
    return 0
}

# Function to create Docker Compose configuration
create_docker_compose() {
    log "INFO" "Creating Docker Compose configuration..."
    
    cat > "$MONITORING_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus:/etc/prometheus
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1'
        reservations:
          memory: 1G
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  alertmanager:
    image: prom/alertmanager:latest
    volumes:
      - ./alertmanager:/etc/alertmanager
    command:
      - '--config.file=/etc/alertmanager/config.yml'
      - '--storage.path=/alertmanager'
    ports:
      - "9093:9093"
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.25'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:9093/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_PASSWORD:-admin}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=https://\${DOMAIN:-localhost}/grafana
      - GF_INSTALL_PLUGINS=grafana-piechart-panel,grafana-worldmap-panel
    ports:
      - "3000:3000"
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1'
        reservations:
          memory: 512M
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  node-exporter:
    image: prom/node-exporter:latest
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.1'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:9100/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M
          cpus: '0.1'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./loki:/etc/loki
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1'
        reservations:
          memory: 512M
          cpus: '0.5'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log
      - ./promtail:/etc/promtail
    command: -config.file=/etc/promtail/config.yml
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.1'
    healthcheck:
      test: ["CMD", "wget", "--spider", "http://localhost:9080/ready"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - monitoring
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  monitoring:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16

volumes:
  prometheus_data:
    driver: local
  grafana_data:
    driver: local
EOF

    log "INFO" "Docker Compose configuration created"
    return 0
}

# Function to start monitoring stack
start_monitoring() {
    log "INFO" "Starting monitoring stack..."
    
    cd "$MONITORING_DIR" || {
        log "ERROR" "Failed to change to monitoring directory"
        return 1
    }

    docker-compose up -d || {
        log "ERROR" "Failed to start monitoring stack"
        return 1
    }

    log "INFO" "Monitoring stack started successfully"
    return 0
}

# Main function
main() {
    log "INFO" "Starting monitoring setup..."
    
    check_prerequisites || exit 1
    setup_prometheus || exit 1
    setup_alertmanager || exit 1
    setup_grafana || exit 1
    create_docker_compose || exit 1
    start_monitoring || exit 1
    
    log "INFO" "Monitoring setup completed successfully"
    
    cat <<EOF

====================================
Monitoring Setup Complete
====================================

Access your monitoring services at:
- Grafana: https://${DOMAIN}/grafana
- Prometheus: https://${DOMAIN}/prometheus
- Alertmanager: https://${DOMAIN}/alertmanager

Default Credentials for Grafana:
- Username: admin
- Password: ${GRAFANA_PASSWORD:-$(vault kv get -field=password secret/grafana)}

Next Steps:
1. Review and customize alert rules in Prometheus
2. Configure additional Grafana dashboards as needed
3. Verify email notifications from Alertmanager
4. Set up additional metrics collection as required

For more information, see the documentation.
EOF
}

# Script execution
main "$@"