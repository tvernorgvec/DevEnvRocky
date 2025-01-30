#!/bin/bash

# 1.1 System Update and User Setup
echo "Checking connectivity..."
if ! ping -c 4 mirror.rockylinux.org; then
    echo "Error: Cannot reach Rocky Linux mirrors"
    exit 1
fi

# Update system packages
echo "Updating system packages..."
dnf update -y
dnf upgrade -y

# Create development user with secure password
echo "Creating development user..."
useradd -m -s /bin/bash developer
echo "developer" | passwd developer --stdin
usermod -aG wheel developer

# Configure strong password policy
echo "Configuring password policy..."
cat > /etc/pam.d/system-auth <<EOF
password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 minclass=4 enforce_for_root
password sufficient pam_unix.so sha512 shadow nullok try_first_pass use_authtok remember=5
EOF

cat > /etc/pam.d/password-auth <<EOF
password requisite pam_pwquality.so retry=3 minlen=12 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1 minclass=4 enforce_for_root
password sufficient pam_unix.so sha512 shadow nullok try_first_pass use_authtok remember=5
EOF

# 1.2 SELinux Configuration
echo "Configuring SELinux..."
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
setenforce 1

# Verify SELinux status
if [ "$(getenforce)" != "Enforcing" ]; then
    echo "Error: Failed to enable SELinux"
    exit 1
fi

# 1.3 Firewall Configuration
echo "Configuring firewall..."
# Install firewalld if not present
dnf install -y firewalld
systemctl enable --now firewalld

# Configure ports
declare -a ports=(
    "80/tcp"   # HTTP
    "443/tcp"  # HTTPS
    "22/tcp"   # SSH
    "3000/tcp" # Grafana
    "9090/tcp" # Prometheus
    "9093/tcp" # Alertmanager
    "8443/tcp" # VS Code Server
    "6379/tcp" # Redis
    "5601/tcp" # Kibana
    "5000/tcp" # Docker Registry
    "9000/tcp" # Portainer
    "9100/tcp" # Node Exporter
    "3100/tcp" # Loki
)

for port in "${ports[@]}"; do
    firewall-cmd --permanent --add-port="$port"
done

firewall-cmd --reload

# Verify firewall configuration
for port in "${ports[@]}"; do
    if ! firewall-cmd --list-ports | grep -q "$port"; then
        echo "Error: Port $port not properly configured in firewall"
        exit 1
    fi
done

# 1.4 Install Essential Tools
echo "Installing essential tools..."
# Install development tools group
dnf groupinstall "Development Tools" -y

# Install EPEL repository
dnf install -y epel-release

# Install essential packages
dnf install -y \
    git \
    vim \
    wget \
    curl \
    net-tools \
    htop \
    lynis \
    openscap-scanner \
    python3-certbot-nginx \
    jq \
    tmux \
    tree \
    trivy \
    sysdig \
    tcpdump \
    iotop \
    strace \
    lsof \
    nmap-ncat \
    python3-pip \
    nodejs \
    npm \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    bash-completion \
    mlocate \
    rsync \
    tar \
    zip \
    unzip \
    chrony

# Update system's locate database
updatedb

# Configure chrony for time synchronization
systemctl enable --now chronyd

# Verify installations
echo "Verifying installations..."
declare -a tools=(
    "git"
    "vim"
    "wget"
    "curl"
    "netstat"
    "htop"
    "lynis"
    "oscap"
    "certbot"
    "jq"
    "tmux"
    "tree"
    "trivy"
    "sysdig"
    "tcpdump"
    "iotop"
    "strace"
    "lsof"
    "nc"
    "python3"
    "node"
    "npm"
)

for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: $tool not properly installed"
        exit 1
    fi
done

echo "Basic system setup completed successfully"