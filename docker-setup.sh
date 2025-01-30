#!/bin/bash

# Docker Installation and Configuration
echo "Setting up Docker..."

# 2.1 Docker Installation
echo "Installing Docker..."

# Remove any old versions
dnf remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine

# Set up Docker repository
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker packages
if ! dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    echo "Error: Docker installation failed"
    exit 1
fi

# Create docker daemon configuration
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 64000,
            "Soft": 64000
        }
    },
    "userland-proxy": false,
    "live-restore": true,
    "iptables": false,
    "storage-driver": "overlay2",
    "metrics-addr": "127.0.0.1:9323",
    "experimental": true,
    "features": {
        "buildkit": true
    },
    "default-address-pools": [
        {
            "base": "172.30.0.0/16",
            "size": 24
        }
    ]
}
EOF

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Verify Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Error: Docker failed to start"
    exit 1
fi

# Add developer user to Docker group
usermod -aG docker developer

# 2.2 Install Docker Compose
echo "Installing Docker Compose..."

# Download Docker Compose
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d '"' -f 4)
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Make Docker Compose executable
chmod +x /usr/local/bin/docker-compose

# Create symbolic link
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
if ! docker-compose --version; then
    echo "Error: Docker Compose installation failed"
    exit 1
fi

# 2.3 Docker Security Configuration
echo "Configuring Docker security..."

# Create Docker security limits
cat > /etc/security/limits.d/docker.conf <<EOF
*       soft    nofile      64000
*       hard    nofile      64000
EOF

# Configure Docker daemon to start with specific security options
mkdir -p /etc/systemd/system/docker.service.d
cat > /etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --userns-remap=default --live-restore --userland-proxy=false
EOF

# Reload systemd and restart Docker
systemctl daemon-reload
systemctl restart docker

# Run Docker security benchmark
echo "Running Docker security benchmark..."
docker run --rm -it \
    --net host \
    --pid host \
    --userns host \
    --cap-add audit_control \
    -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
    -v /var/lib:/var/lib \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /usr/lib/systemd:/usr/lib/systemd \
    -v /etc:/etc --label docker_bench_security \
    docker/docker-bench-security

# Configure Docker content trust
echo "export DOCKER_CONTENT_TRUST=1" >> /etc/profile.d/docker.sh

# Run vulnerability scanning
echo "Running vulnerability scan on base images..."
for image in ubuntu:latest alpine:latest python:3.9; do
    echo "Scanning $image..."
    trivy image --no-progress --ignore-unfixed "$image"
done

# Verify Docker configuration
echo "Verifying Docker configuration..."
docker info
docker version
docker-compose version

echo "Docker setup completed successfully"