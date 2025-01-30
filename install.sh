#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Version
VERSION="1.0.0"

# Configuration
CONFIG_DIR="/etc/dev-sandbox"
CONFIG_FILE="$CONFIG_DIR/config.conf"
LOG_DIR="/var/log/dev-sandbox"
LOG_FILE="$LOG_DIR/install.log"
ERROR_LOG="$LOG_DIR/error.log"
BACKUP_DIR="/var/backups/dev-sandbox"
DOMAIN="isp-pybox.gvec.net"
ADMIN_EMAIL="tvernor@gvec.org"

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

# Function to check command availability
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR" "Required command $1 not found"
        return 1
    fi
}

# Function to check service status
check_service() {
    if ! systemctl is-active --quiet "$1"; then
        log "ERROR" "Required service $1 not running"
        return 1
    fi
}

# Function to create required directories
create_directories() {
    local dirs=(
        "/var/lib/prometheus"
        "/var/lib/grafana"
        "/var/lib/elasticsearch"
        "/var/backup/postgres"
        "/var/backup/redis"
        "/var/backup/influxdb"
        "$LOG_DIR"
        "$CONFIG_DIR"
        "$BACKUP_DIR"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir" || {
            log "ERROR" "Failed to create directory: $dir"
            return 1
        }
    done

    # Set correct permissions
    chmod 700 /var/backup/*
    chown -R 65534:65534 /var/lib/prometheus
    chown -R 472:472 /var/lib/grafana
    chown -R 1000:1000 /var/lib/elasticsearch

    return 0
}

# Function to check system requirements
check_requirements() {
    log "INFO" "Checking system requirements..."
    
    # Check OS
    if ! grep -q "Rocky Linux" /etc/os-release; then
        log "ERROR" "This script requires Rocky Linux 9.x"
        return 1
    fi

    # Check memory
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt 4096 ]; then
        log "ERROR" "Insufficient memory. Required: 4GB, Available: ${total_mem}MB"
        return 1
    fi

    # Check disk space
    local free_space=$(df -m / | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 10240 ]; then
        log "ERROR" "Insufficient disk space. Required: 10GB, Available: ${free_space}MB"
        return 1
    fi

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root"
        return 1
    fi

    # Check network connectivity
    if ! ping -c 1 mirror.rockylinux.org &> /dev/null; then
        log "ERROR" "No network connectivity to Rocky Linux mirrors"
        return 1
    fi

    log "INFO" "System requirements check passed"
    return 0
}

# Function to configure repositories
configure_repositories() {
    log "INFO" "Configuring repositories..."
    
    # Enable CRB repository
    dnf config-manager --set-enabled crb || {
        log "ERROR" "Failed to enable CRB repository"
        return 1
    }

    # Install EPEL repository
    dnf install -y epel-release || {
        log "ERROR" "Failed to install EPEL repository"
        return 1
    }

    # Add Docker repository
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || {
        log "WARNING" "Failed to add Docker repository via dnf, trying curl..."
        curl -fsSL https://download.docker.com/linux/centos/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo || {
            log "ERROR" "Failed to add Docker repository"
            return 1
        }
    }

    return 0
}

# Function to install base packages
install_base_packages() {
    log "INFO" "Installing base packages..."
    
    # Update system first
    dnf update -y || {
        log "ERROR" "Failed to update system packages"
        return 1
    }
    
    # Install core system utilities
    log "INFO" "Installing core utilities..."
    dnf install -y git vim wget curl net-tools htop || {
        log "ERROR" "Failed to install core utilities"
        return 1
    }

    # Install security tools
    log "INFO" "Installing security tools..."
    # First install EPEL and enable PowerTools/CRB for certbot dependencies
    dnf install -y epel-release
    dnf config-manager --set-enabled crb
    # Now install certbot with nginx plugin
    dnf install -y certbot python3-certbot-nginx lynis scap-security-guide fail2ban || {
        log "WARNING" "Some security tools failed to install"
    }

    # Install development tools
    log "INFO" "Installing development tools..."
    dnf install -y jq tmux tree yum-utils device-mapper-persistent-data lvm2 || {
        log "WARNING" "Some development tools failed to install"
    }

    # Install required dependencies
    log "INFO" "Installing required dependencies..."
    dnf install -y ca-certificates openssl python3-pip policycoreutils-python-utils || {
        log "ERROR" "Failed to install required dependencies"
        return 1
    }

    # Install Docker
    log "INFO" "Installing Docker..."
    dnf install -y docker-ce docker-ce-cli containerd.io || {
        log "ERROR" "Failed to install Docker"
        return 1
    }

    # Install Docker Compose using the official binary instead of pip
    log "INFO" "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || {
        log "ERROR" "Failed to download Docker Compose"
        return 1
    }
    chmod +x /usr/local/bin/docker-compose || {
        log "ERROR" "Failed to make Docker Compose executable"
        return 1
    }
    
    return 0
}

# Function to configure system
configure_system() {
    log "INFO" "Configuring system..."

    # Configure kernel parameters
    cat > /etc/sysctl.d/99-docker-network.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
    sysctl --system || {
        log "ERROR" "Failed to apply sysctl settings"
        return 1
    }

    # Configure kernel modules
    cat > /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
    modprobe overlay
    modprobe br_netfilter

    # Configure system limits
    cat > /etc/security/limits.d/99-docker.conf <<EOF
*       soft    nofile      65536
*       hard    nofile      65536
*       soft    nproc       65536
*       hard    nproc       65536
EOF

    # Configure log rotation
    cat > /etc/logrotate.d/sandbox <<EOF
/var/log/dev-sandbox/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

    return 0
}

# Function to configure SELinux
configure_selinux() {
    log "INFO" "Configuring SELinux..."
    
    # Set SELinux to enforcing
    setenforce 1
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config

    # Configure SELinux contexts
    setsebool -P container_manage_cgroup 1 || {
        log "ERROR" "Failed to set container_manage_cgroup boolean"
        return 1
    }

    # Configure SELinux ports
    for port in 3000 9090; do
        semanage port -l | grep -q "^http_port_t.*$port" || {
            semanage port -a -t http_port_t -p tcp $port || {
                log "WARNING" "Failed to add SELinux port $port"
            }
        }
    done
    
    return 0
}

# Function to configure firewall
configure_firewall() {
    log "INFO" "Configuring firewall..."
    
    # Start and enable firewalld
    systemctl enable --now firewalld || {
        log "ERROR" "Failed to enable firewalld"
        return 1
    }
    
    # Configure services and ports
    local ports=(
        "http"
        "https"
        "3000/tcp"
        "9090/tcp"
        "22/tcp"
        "8443/tcp"
        "6379/tcp"
        "5601/tcp"
        "5000/tcp"
    )

    for port in "${ports[@]}"; do
        if [[ $port =~ ^(http|https)$ ]]; then
            firewall-cmd --permanent --zone=public --add-service="$port" || {
                log "WARNING" "Failed to add service $port to firewall"
            }
        else
            firewall-cmd --permanent --zone=public --add-port="$port" || {
                log "WARNING" "Failed to add port $port to firewall"
            }
        fi
    done
    
    # Reload firewall
    firewall-cmd --reload || {
        log "ERROR" "Failed to reload firewall configuration"
        return 1
    }
    
    return 0
}

# Function to configure services
configure_services() {
    log "INFO" "Configuring services..."
    
    # Enable and start chronyd
    systemctl enable --now chronyd || {
        log "ERROR" "Failed to enable chronyd"
        return 1
    }

    # Start and enable Docker
    systemctl enable --now docker || {
        log "ERROR" "Failed to enable Docker"
        return 1
    }

    # Verify services are running
    local services=("chronyd" "docker" "firewalld")
    for service in "${services[@]}"; do
        check_service "$service" || {
            log "ERROR" "Service $service failed to start"
            return 1
        }
    done

    return 0
}

# Main installation function
install() {
    log "INFO" "Starting installation process..."
    
    # Create necessary directories
    create_directories || exit 1
    
    # Check requirements
    check_requirements || {
        log "ERROR" "System requirements check failed"
        exit 1
    }
    
    # Install and configure components
    configure_repositories || exit 1
    install_base_packages || exit 1
    configure_system || exit 1
    configure_selinux || exit 1
    configure_firewall || exit 1
    configure_services || exit 1
    
    log "INFO" "Installation completed successfully"
    
    # Display post-installation information
    cat <<EOF

====================================
Installation Complete
====================================

Next Steps:
1. Configure Vault secrets
2. Set up additional services as needed
3. Review security settings
4. Configure backup strategy

For more information, see the documentation.
EOF
}

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --install    Install the development sandbox"
    echo "  --help       Display this help message"
    echo "  --version    Display version information"
}

# Main script execution
case "$1" in
    --install)
        install
        ;;
    --help)
        show_help
        ;;
    --version)
        echo "Development Sandbox Installer v${VERSION}"
        ;;
    *)
        show_help
        exit 1
        ;;
esac