terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.0"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Network Configuration
resource "docker_network" "frontend" {
  name = "frontend"
  driver = "bridge"
  ipam_config {
    subnet = "172.20.0.0/16"
  }
}

resource "docker_network" "backend" {
  name = "backend"
  driver = "bridge"
  internal = true
  ipam_config {
    subnet = "172.21.0.0/16"
  }
}

# Volume Configuration
resource "docker_volume" "prometheus_data" {
  name = "prometheus_data"
}

resource "docker_volume" "grafana_data" {
  name = "grafana_data"
}

# Container Definitions
resource "docker_container" "prometheus" {
  name  = "prometheus"
  image = "prom/prometheus:latest"
  
  volumes {
    container_path = "/etc/prometheus"
    host_path      = "${path.cwd}/config/prometheus"
  }
  
  volumes {
    container_path = "/prometheus"
    volume_name    = docker_volume.prometheus_data.name
  }
  
  ports {
    internal = 9090
    external = 9090
  }
  
  networks_advanced {
    name = docker_network.backend.name
  }
  
  restart = "unless-stopped"
}