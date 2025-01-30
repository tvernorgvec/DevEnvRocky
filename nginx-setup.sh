#!/bin/bash

# Nginx Installation and Configuration
echo "Setting up Nginx..."

# 4.1 Install Nginx and dependencies
echo "Installing Nginx and dependencies..."
dnf install -y nginx certbot python3-certbot-nginx libmodsecurity nginx-mod-modsecurity

# Create necessary directories
mkdir -p /etc/nginx/conf.d
mkdir -p /etc/nginx/ssl
mkdir -p /etc/nginx/modsec
mkdir -p /var/www/html
mkdir -p /var/log/nginx

# 4.2 Configure ModSecurity (WAF)
echo "Configuring ModSecurity..."
cp /etc/nginx/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf

# Configure ModSecurity base settings
cat > /etc/nginx/modsec/main.conf <<EOF
Include /etc/nginx/modsec/modsecurity.conf
Include /etc/nginx/modsec/rules/*.conf

SecRuleEngine On
SecRequestBodyAccess On
SecRequestBodyLimit 13107200
SecRequestBodyNoFilesLimit 131072
SecRequestBodyInMemoryLimit 131072
SecRequestBodyLimitAction Reject
SecRule REQUEST_HEADERS:Content-Type "text/xml" \
     "id:'200000',phase:1,t:none,t:lowercase,pass,nolog,ctl:requestBodyProcessor=XML"
SecRule REQBODY_ERROR "!@eq 0" \
    "id:'200001', phase:2,t:none,log,deny,status:400,msg:'Failed to parse request body.',logdata:'%{reqbody_error_msg}',severity:2"
SecRule MULTIPART_STRICT_ERROR "!@eq 0" \
    "id:'200002',phase:2,t:none,log,deny,status:400,msg:'Multipart request body failed strict validation.',logdata:'%{MULTIPART_STRICT_ERROR}',severity:2"
EOF

# Create ModSecurity rules directory
mkdir -p /etc/nginx/modsec/rules

# Download OWASP Core Rule Set
curl -L https://github.com/coreruleset/coreruleset/archive/v3.3.2.tar.gz | \
    tar xz -C /etc/nginx/modsec/rules --strip-components=1

# 4.3 Configure main Nginx configuration
cat > /etc/nginx/nginx.conf <<EOF
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

    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main buffer=16k;
    error_log /var/log/nginx/error.log warn;

    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 100M;
    client_body_buffer_size 128k;

    # SSL Settings
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

    # ModSecurity
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsec/main.conf;

    # Gzip Settings
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # Rate Limiting
    limit_req_zone \$binary_remote_addr zone=one:10m rate=1r/s;
    limit_conn_zone \$binary_remote_addr zone=addr:10m;

    # Virtual Host Configs
    include /etc/nginx/conf.d/*.conf;
}
EOF

# 4.4 Configure virtual hosts
cat > /etc/nginx/conf.d/default.conf <<EOF
# HTTP redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name isp-pybox.gvec.net;
    
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
    server_name isp-pybox.gvec.net;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/isp-pybox.gvec.net/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/isp-pybox.gvec.net/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/isp-pybox.gvec.net/chain.pem;
    ssl_dhparam /etc/nginx/ssl/dhparam.pem;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Permissions-Policy "geolocation=(), midi=(), sync-xhr=(), microphone=(), camera=(), magnetometer=(), gyroscope=(), fullscreen=(self), payment=()" always;

    # Rate Limiting
    limit_req zone=one burst=5 nodelay;
    limit_conn addr 10;

    # Proxy Settings
    proxy_http_version 1.1;
    proxy_cache_bypass \$http_upgrade;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_buffering on;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;

    # Service Locations
    location /grafana/ {
        proxy_pass http://localhost:3000/;
        auth_request /auth;
    }

    location /prometheus/ {
        proxy_pass http://localhost:9090/;
        auth_request /auth;
    }

    location /alertmanager/ {
        proxy_pass http://localhost:9093/;
        auth_request /auth;
    }

    location /kibana/ {
        proxy_pass http://localhost:5601/;
        auth_request /auth;
    }

    location /vscode/ {
        proxy_pass http://localhost:8443/;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        auth_request /auth;
    }

    location /portainer/ {
        proxy_pass http://localhost:9000/;
        auth_request /auth;
    }

    # Auth endpoint
    location = /auth {
        internal;
        proxy_pass http://localhost:8080/auth;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI \$request_uri;
    }

    # Root location
    location / {
        root /var/www/html;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
    }

    # Error pages
    error_page 404 /404.html;
    location = /404.html {
        root /var/www/html;
        internal;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /var/www/html;
        internal;
    }
}
EOF

# 4.5 Generate DH parameters
openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

# 4.6 Set permissions
chown -R nginx:nginx /etc/nginx
chown -R nginx:nginx /var/www/html
chmod -R 755 /var/www/html

# 4.7 Enable and start Nginx
systemctl enable nginx
systemctl start nginx

# 4.8 Configure SSL with Certbot
VAULT_EMAIL=$(vault kv get -field=email secret/nginx)
certbot --nginx \
    -d isp-pybox.gvec.net \
    --non-interactive \
    --agree-tos \
    --email "$VAULT_EMAIL" \
    --redirect \
    --staple-ocsp \
    --must-staple

# 4.9 Test configuration
nginx -t

# 4.10 Reload Nginx
systemctl reload nginx

echo "Nginx setup completed successfully"