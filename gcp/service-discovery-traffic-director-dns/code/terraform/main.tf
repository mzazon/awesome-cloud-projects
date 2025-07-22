# ==============================================================================
# Service Discovery with Traffic Director and Cloud DNS - Main Configuration
# ==============================================================================

# Configure the Google Cloud Provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  service_name     = "${var.service_name}-${random_id.suffix.hex}"
  dns_zone_name    = "${var.dns_zone_name}-${random_id.suffix.hex}"
  domain_name      = "${local.service_name}.${var.base_domain}"
  zones            = ["${var.region}-a", "${var.region}-b", "${var.region}-c"]
  
  common_tags = {
    project     = var.project_id
    environment = var.environment
    managed_by  = "terraform"
    recipe      = "service-discovery-traffic-director-dns"
  }
}

# ==============================================================================
# VPC Network Infrastructure
# ==============================================================================

# Create custom VPC network for service mesh
resource "google_compute_network" "service_mesh_vpc" {
  name                    = "${local.service_name}-vpc"
  auto_create_subnetworks = false
  routing_mode           = "GLOBAL"
  description            = "VPC network for service mesh with Traffic Director"
}

# Create subnet for service instances
resource "google_compute_subnetwork" "service_mesh_subnet" {
  name          = "${local.service_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.service_mesh_vpc.id
  description   = "Subnet for service mesh instances"
  
  # Enable private Google access for better connectivity
  private_ip_google_access = true
}

# ==============================================================================
# Firewall Rules
# ==============================================================================

# Allow HTTP traffic for service instances
resource "google_compute_firewall" "allow_http" {
  name    = "${local.service_name}-allow-http"
  network = google_compute_network.service_mesh_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["service-mesh", "http-server"]
  description   = "Allow HTTP traffic within service mesh"
}

# Allow Google Cloud health check traffic
resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.service_name}-allow-health-check"
  network = google_compute_network.service_mesh_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  # Google Cloud health check source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["service-mesh"]
  description   = "Allow Google Cloud health check traffic"
}

# Allow SSH for management (optional, can be removed in production)
resource "google_compute_firewall" "allow_ssh" {
  count = var.enable_ssh ? 1 : 0
  
  name    = "${local.service_name}-allow-ssh"
  network = google_compute_network.service_mesh_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["service-mesh"]
  description   = "Allow SSH access for management"
}

# ==============================================================================
# Cloud DNS Configuration
# ==============================================================================

# Private DNS zone for internal service discovery
resource "google_dns_managed_zone" "private_zone" {
  name        = local.dns_zone_name
  dns_name    = "${local.domain_name}."
  description = "Private DNS zone for microservice discovery"
  
  visibility = "private"
  
  private_visibility_config {
    networks {
      network_url = google_compute_network.service_mesh_vpc.id
    }
  }
  
  labels = local.common_tags
}

# Public DNS zone for external access (optional)
resource "google_dns_managed_zone" "public_zone" {
  count = var.create_public_dns ? 1 : 0
  
  name        = "${local.dns_zone_name}-public"
  dns_name    = "${local.domain_name}."
  description = "Public DNS zone for external service access"
  
  visibility = "public"
  labels     = local.common_tags
}

# ==============================================================================
# Service Instance Template
# ==============================================================================

# Instance template for service deployment
resource "google_compute_instance_template" "service_template" {
  name_prefix  = "${local.service_name}-template-"
  machine_type = var.machine_type
  description  = "Template for service mesh instances"

  disk {
    source_image = var.source_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.disk_size_gb
  }

  network_interface {
    subnetwork = google_compute_subnetwork.service_mesh_subnet.id
    
    # Don't assign external IP by default for security
    dynamic "access_config" {
      for_each = var.assign_external_ip ? [1] : []
      content {}
    }
  }

  # Service configuration and health endpoint setup
  metadata_startup_script = templatefile("${path.module}/templates/startup.sh.tpl", {
    service_name = local.service_name
  })

  tags = ["service-mesh", "http-server"]
  
  labels = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# Compute Instances Across Multiple Zones
# ==============================================================================

# Deploy service instances across multiple zones for high availability
resource "google_compute_instance_from_template" "service_instances" {
  for_each = {
    for idx, zone in local.zones : "${zone}-${idx % var.instances_per_zone + 1}" => {
      zone     = zone
      instance = idx % var.instances_per_zone + 1
    }
  }

  name = "${local.service_name}-${each.key}"
  zone = each.value.zone
  
  source_instance_template = google_compute_instance_template.service_template.id
  
  # Override startup script with actual zone information
  metadata = {
    startup-script = templatefile("${path.module}/templates/startup.sh.tpl", {
      service_name = local.service_name
    })
  }

  labels = merge(local.common_tags, {
    zone = each.value.zone
  })
}

# ==============================================================================
# Network Endpoint Groups (NEGs)
# ==============================================================================

# Create zonal NEGs for Traffic Director
resource "google_compute_network_endpoint_group" "service_negs" {
  for_each = toset(local.zones)
  
  name         = "${local.service_name}-neg-${each.key}"
  network      = google_compute_network.service_mesh_vpc.id
  subnetwork   = google_compute_subnetwork.service_mesh_subnet.id
  zone         = each.key
  description  = "Network endpoint group for zone ${each.key}"
  
  network_endpoint_type = "GCE_VM_IP_PORT"
  default_port         = 80
}

# Add instance endpoints to NEGs
resource "google_compute_network_endpoint" "service_endpoints" {
  for_each = {
    for instance_key, instance in google_compute_instance_from_template.service_instances : 
    instance_key => instance
  }
  
  network_endpoint_group = google_compute_network_endpoint_group.service_negs[each.value.zone].name
  zone                  = each.value.zone
  instance              = each.value.name
  port                  = 80
  ip_address           = each.value.network_interface[0].network_ip
}

# ==============================================================================
# Health Check Configuration
# ==============================================================================

# HTTP health check for service monitoring
resource "google_compute_health_check" "service_health_check" {
  name        = "${local.service_name}-health-check"
  description = "Health check for ${local.service_name} instances"
  
  timeout_sec         = var.health_check_timeout
  check_interval_sec  = var.health_check_interval
  healthy_threshold   = var.health_check_healthy_threshold
  unhealthy_threshold = var.health_check_unhealthy_threshold
  
  http_health_check {
    port               = 80
    request_path       = "/health"
    proxy_header       = "NONE"
    response           = ""
  }
}

# ==============================================================================
# Traffic Director Backend Service
# ==============================================================================

# Backend service for Traffic Director with intelligent load balancing
resource "google_compute_backend_service" "service_backend" {
  name        = "${local.service_name}-backend"
  description = "Backend service for intelligent service discovery"
  
  protocol                        = "HTTP"
  load_balancing_scheme          = "INTERNAL_SELF_MANAGED"
  locality_lb_policy             = var.locality_lb_policy
  connection_draining_timeout_sec = var.connection_draining_timeout
  
  health_checks = [google_compute_health_check.service_health_check.id]
  
  # Add NEGs as backends with zone-aware configuration
  dynamic "backend" {
    for_each = google_compute_network_endpoint_group.service_negs
    content {
      group           = backend.value.id
      balancing_mode  = "RATE"
      max_rate_per_endpoint = var.max_rate_per_endpoint
      capacity_scaler = 1.0
      description     = "Backend for zone ${backend.key}"
    }
  }
  
  # Circuit breaker configuration for resilience
  circuit_breakers {
    max_requests_per_connection = var.max_requests_per_connection
    max_connections             = var.max_connections
    max_pending_requests        = var.max_pending_requests
    max_retries                = var.max_retries
  }
  
  # Outlier detection for automatic failure isolation
  outlier_detection {
    consecutive_errors                    = var.consecutive_errors
    interval_sec                         = var.outlier_detection_interval
    base_ejection_time_sec               = var.base_ejection_time
    max_ejection_percent                 = var.max_ejection_percent
    min_health_percent                   = var.min_health_percent
    split_external_local_origin_errors   = true
  }
}

# ==============================================================================
# Traffic Director URL Map and Routing
# ==============================================================================

# URL map for intelligent traffic routing
resource "google_compute_url_map" "service_url_map" {
  name            = "${local.service_name}-url-map"
  description     = "URL map for intelligent service discovery routing"
  default_service = google_compute_backend_service.service_backend.id
  
  # Host rule for the service domain
  host_rule {
    hosts        = [local.domain_name]
    path_matcher = "service-matcher"
  }
  
  # Path matcher with default routing to backend service
  path_matcher {
    name            = "service-matcher"
    default_service = google_compute_backend_service.service_backend.id
    
    # Health check route
    path_rule {
      paths   = ["/health", "/health/*"]
      service = google_compute_backend_service.service_backend.id
    }
    
    # API versioning support (example for future extensions)
    path_rule {
      paths   = ["/v1/*", "/api/v1/*"]
      service = google_compute_backend_service.service_backend.id
    }
  }
}

# Target HTTP proxy for Traffic Director
resource "google_compute_target_http_proxy" "service_proxy" {
  name        = "${local.service_name}-proxy"
  url_map     = google_compute_url_map.service_url_map.id
  description = "HTTP proxy for Traffic Director service mesh"
}

# ==============================================================================
# Global Forwarding Rule
# ==============================================================================

# Global forwarding rule for service access
resource "google_compute_global_forwarding_rule" "service_forwarding_rule" {
  name        = "${local.service_name}-forwarding-rule"
  description = "Global forwarding rule for intelligent service discovery"
  
  load_balancing_scheme = "INTERNAL_SELF_MANAGED"
  ip_address           = var.service_vip
  port_range           = "80"
  target               = google_compute_target_http_proxy.service_proxy.id
  network              = google_compute_network.service_mesh_vpc.id
  ip_protocol          = "TCP"
}

# ==============================================================================
# DNS Records for Service Discovery
# ==============================================================================

# A record pointing to Traffic Director VIP
resource "google_dns_record_set" "service_a_record" {
  name         = "${local.domain_name}."
  managed_zone = google_dns_managed_zone.private_zone.name
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas      = [google_compute_global_forwarding_rule.service_forwarding_rule.ip_address]
}

# SRV record for service discovery with port information
resource "google_dns_record_set" "service_srv_record" {
  name         = "_http._tcp.${local.domain_name}."
  managed_zone = google_dns_managed_zone.private_zone.name
  type         = "SRV"
  ttl          = var.dns_ttl
  rrdatas      = ["10 5 80 ${local.domain_name}."]
}

# Health check DNS record
resource "google_dns_record_set" "health_record" {
  name         = "health.${local.domain_name}."
  managed_zone = google_dns_managed_zone.private_zone.name
  type         = "A"
  ttl          = var.health_dns_ttl
  rrdatas      = [google_compute_global_forwarding_rule.service_forwarding_rule.ip_address]
}

# Public DNS records (if public zone is created)
resource "google_dns_record_set" "public_a_record" {
  count = var.create_public_dns ? 1 : 0
  
  name         = "${local.domain_name}."
  managed_zone = google_dns_managed_zone.public_zone[0].name
  type         = "A"
  ttl          = var.dns_ttl
  rrdatas      = [google_compute_global_forwarding_rule.service_forwarding_rule.ip_address]
}

# ==============================================================================
# Test Client Instance (Optional)
# ==============================================================================

# Optional test client for validation
resource "google_compute_instance" "test_client" {
  count = var.create_test_client ? 1 : 0
  
  name         = "${local.service_name}-test-client"
  machine_type = "e2-micro"
  zone         = local.zones[0]
  description  = "Test client for service discovery validation"
  
  boot_disk {
    initialize_params {
      image = var.source_image
      size  = 10
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.service_mesh_subnet.id
    
    dynamic "access_config" {
      for_each = var.assign_external_ip ? [1] : []
      content {}
    }
  }
  
  # Install testing tools
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y curl jq dnsutils
    
    # Create test script
    cat > /home/test_service.sh << 'EOL'
    #!/bin/bash
    echo "Testing service discovery..."
    echo "DNS Resolution:"
    nslookup ${local.domain_name}
    echo ""
    echo "Service Response:"
    curl -s http://${local.domain_name}/ | jq .
    echo ""
    echo "Health Check:"
    curl -s http://${local.domain_name}/health | jq .
    EOL
    
    chmod +x /home/test_service.sh
  EOF
  
  tags = ["service-mesh"]
  labels = merge(local.common_tags, {
    role = "test-client"
  })
}

# ==============================================================================
# Note: Startup script is managed through templates/startup.sh.tpl
# This script is automatically applied to instances during deployment
# ==============================================================================