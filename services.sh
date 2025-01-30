#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONFIG_DIR="/etc/dev-sandbox"
LOG_DIR="/var/log/dev-sandbox"
LOG_FILE="$LOG_DIR/services.log"
ERROR_LOG="$LOG_DIR/error.log"
DOMAIN="isp-pybox.gvec.net"
ADMIN_EMAIL="tvernor@gvec.org"
SERVICES_DIR="/opt/services"

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

    # Check if services directory exists
    mkdir -p "$SERVICES_DIR" || {
        log "ERROR" "Failed to create services directory"
        return 1
    }

    log "INFO" "Prerequisites check passed"
    return 0
}

# Function to setup Nginx
setup_nginx() {
    log "INFO" "Setting up Nginx..."
    
    mkdir -p "$SERVICES_DIR/nginx/conf.d" || {
        log "ERROR" "Failed to create Nginx directories"
        return 1
    }

    # Create main Nginx configuration
    cat > "$SERVICES_DIR/nginx/nginx.conf" <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=one:10m rate=1r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:10m;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Load virtual host configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Create default virtual host configuration
    cat > "$SERVICES_DIR/nginx/conf.d/default.conf" <<EOF
# HTTP redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/${DOMAIN}/chain.pem;

    # Rate limiting
    limit_req zone=one burst=5 nodelay;
    limit_conn addr 10;

    # Root directory
    root /usr/share/nginx/html;
    index index.html index.htm;

    # Proxy settings
    proxy_http_version 1.1;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # Service locations
    location /grafana/ {
        proxy_pass http://grafana:3000/;
    }

    location /prometheus/ {
        proxy_pass http://prometheus:9090/;
        auth_basic "Prometheus";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }

    location /alertmanager/ {
        proxy_pass http://alertmanager:9093/;
        auth_basic "Alertmanager";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }

    location /kibana/ {
        proxy_pass http://kibana:5601/;
    }

    location /portainer/ {
        proxy_pass http://portainer:9000/;
    }

    location /registry/ {
        proxy_pass http://registry:5000/;
        client_max_body_size 0;
    }

    location /vscode/ {
        proxy_pass http://code-server:8443/;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
    }

    # Default location
    location / {
        try_files \$uri \$uri/ =404;
    }

    # Error pages
    error_page 404 /404.html;
    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF

    log "INFO" "Nginx configuration completed"
    return 0
}

# Function to setup PostgreSQL
setup_postgres() {
    log "INFO" "Setting up PostgreSQL..."
    
    mkdir -p "$SERVICES_DIR/postgres/data" || {
        log "ERROR" "Failed to create PostgreSQL directories"
        return 1
    }

    # Create PostgreSQL configuration
    cat > "$SERVICES_DIR/postgres/postgresql.conf" <<EOF
# Connection settings
listen_addresses = '*'
port = 5432
max_connections = 100

# Memory settings
shared_buffers = 128MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Write ahead log
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB

# Query tuning
random_page_cost = 1.1
effective_cache_size = 4GB

# Monitoring
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.max = 10000
pg_stat_statements.track = all

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = 1d
log_rotation_size = 0
log_min_duration_statement = 1000
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
EOF

    # Create pg_hba.conf
    cat > "$SERVICES_DIR/postgres/pg_hba.conf" <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all            all                                     trust
host    all            all             127.0.0.1/32           md5
host    all            all             ::1/128                 md5
host    all            all             0.0.0.0/0              md5
EOF

    log "INFO" "PostgreSQL configuration completed"
    return 0
}

# Function to setup Redis
setup_redis() {
    log "INFO" "Setting up Redis..."
    
    mkdir -p "$SERVICES_DIR/redis" || {
        log "ERROR" "Failed to create Redis directories"
        return 1
    }

    # Create Redis configuration
    cat > "$SERVICES_DIR/redis/redis.conf" <<EOF
# Network
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300

# General
daemonize no
supervised no
pidfile /var/run/redis_6379.pid
loglevel notice
logfile ""
databases 16

# Snapshotting
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir ./

# Memory management
maxmemory 256mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Security
requirepass \${REDIS_PASSWORD:-$(vault kv get -field=password secret/redis)}

# Append only mode
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Latency monitor
latency-monitor-threshold 100
EOF

    log "INFO" "Redis configuration completed"
    return 0
}

# Function to create Docker Compose configuration
create_docker_compose() {
    log "INFO" "Creating Docker Compose configuration..."
    
    cat > "$SERVICES_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - ./nginx/www:/usr/share/nginx/html:ro
      - certbot-etc:/etc/letsencrypt
      - certbot-var:/var/lib/letsencrypt
      - ./nginx/dhparam:/etc/ssl/certs
    depends_on:
      - postgres
      - redis
    networks:
      - frontend
      - backend
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - certbot-etc:/etc/letsencrypt
      - certbot-var:/var/lib/letsencrypt
      - ./nginx/www:/var/www/html
    depends_on:
      - nginx
    command: certonly --webroot --webroot-path=/var/www/html --email ${ADMIN_EMAIL} --agree-tos --no-eff-email --force-renewal -d ${DOMAIN}

  postgres:
    image: postgres:13-alpine
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
      - ./postgres/postgresql.conf:/etc/postgresql/postgresql.conf
      - ./postgres/pg_hba.conf:/etc/postgresql/pg_hba.conf
    environment:
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD:-$(vault kv get -field=password secret/postgres)}
      POSTGRES_DB: sandbox
    command: postgres -c config_file=/etc/postgresql/postgresql.conf
    ports:
      - "5432:5432"
    networks:
      - backend
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:alpine
    command: redis-server /usr/local/etc/redis/redis.conf
    volumes:
      - ./redis/redis.conf:/usr/local/etc/redis/redis.conf
      - redis-data:/data
    ports:
      - "6379:6379"
    networks:
      - backend
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true

volumes:
  certbot-etc:
  certbot-var:
  redis-data:
EOF

    log "INFO" "Docker Compose configuration created"
    return 0
}

# Function to start services
start_services() {
    log "INFO" "Starting services..."
    
    cd "$SERVICES_DIR" || {
        log "ERROR" "Failed to change to services directory"
        return 1
    }

    docker-compose up -d || {
        log "ERROR" "Failed to start services"
        return 1
    }

    log "INFO" "Services started successfully"
    return 0
}

# Main function
main() {
    log "INFO" "Starting services setup..."
    
    check_prerequisites || exit 1
    setup_nginx || exit 1
    setup_postgres || exit 1
    setup_redis || exit 1
    create_docker_compose || exit 1
    start_services || exit 1
    
    log "INFO" "Services setup completed successfully"
    
    cat <<EOF

====================================
Services Setup Complete
====================================

Services are now running at:
- Nginx: https://${DOMAIN}
- PostgreSQL: localhost:5432
- Redis: localhost:6379

Next Steps:
1. Configure SSL certificates with Certbot
2. Set up database users and permissions
3. Configure Redis password
4. Review Nginx configurations
5. Test all service endpoints

For more information, see the documentation.
EOF
}

# Script execution
main "$@"