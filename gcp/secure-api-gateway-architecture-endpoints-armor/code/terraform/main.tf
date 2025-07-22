# Secure API Gateway Architecture with Cloud Endpoints and Cloud Armor
# This configuration creates a production-ready API gateway with comprehensive security

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

locals {
  # Resource naming with random suffix for uniqueness
  api_name               = "${var.api_name}-${random_id.suffix.hex}"
  backend_service_name   = "api-backend-${random_id.suffix.hex}"
  esp_proxy_name         = "esp-proxy-${random_id.suffix.hex}"
  security_policy_name   = "api-security-policy-${random_id.suffix.hex}"
  instance_group_name    = "esp-proxy-group-${random_id.suffix.hex}"
  
  # Computed values
  endpoints_service_name = "${local.api_name}.endpoints.${var.project_id}.cloud.goog"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    api-name    = local.api_name
  })
}

# Enable required APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "servicemanagement.googleapis.com",
    "servicecontrol.googleapis.com",
    "endpoints.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent services from being disabled when resources are destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create startup script for backend API service
resource "local_file" "backend_startup_script" {
  filename = "${path.module}/backend-startup.sh"
  content = templatefile("${path.module}/templates/backend-startup.sh.tpl", {
    backend_port = var.backend_port
  })
}

# Backend service VM instance running Flask API
resource "google_compute_instance" "backend_service" {
  name                      = local.backend_service_name
  machine_type              = var.backend_machine_type
  zone                      = var.zone
  allow_stopping_for_update = true
  
  # Labels for resource management
  labels = local.common_labels
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  # Network interface configuration
  network_interface {
    network    = "default"
    network_ip = null
    
    # Ephemeral external IP for outbound internet access
    access_config {
      nat_ip                 = null
      public_ptr_domain_name = null
      network_tier           = "PREMIUM"
    }
  }
  
  # Service account with minimal required permissions
  service_account {
    email = google_service_account.backend_service.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write"
    ]
  }
  
  # Network tags for firewall rules
  tags = ["backend-service", "http-server"]
  
  # Startup script to install and configure Flask API
  metadata_startup_script = templatefile("${path.module}/templates/backend-startup.sh.tpl", {
    backend_port = var.backend_port
  })
  
  # Ensure APIs are enabled before creating instance
  depends_on = [google_project_service.required_apis]
}

# Service account for backend service
resource "google_service_account" "backend_service" {
  account_id   = "backend-service-${random_id.suffix.hex}"
  display_name = "Backend Service Account"
  description  = "Service account for backend API service"
  project      = var.project_id
}

# Create OpenAPI specification for Cloud Endpoints
resource "local_file" "openapi_spec" {
  filename = "${path.module}/openapi-spec.yaml"
  content = templatefile("${path.module}/templates/openapi-spec.yaml.tpl", {
    api_name              = local.api_name
    project_id            = var.project_id
    backend_service_name  = local.backend_service_name
    zone                  = var.zone
    backend_port          = var.backend_port
  })
}

# Deploy API configuration to Cloud Endpoints
resource "google_endpoints_service" "api_service" {
  service_name   = local.endpoints_service_name
  project        = var.project_id
  openapi_config = local_file.openapi_spec.content
  
  # Ensure backend service is created before deploying API
  depends_on = [
    google_compute_instance.backend_service,
    google_project_service.required_apis
  ]
}

# Create API key for authentication
resource "google_apikeys_key" "api_key" {
  name         = "secure-api-gateway-key-${random_id.suffix.hex}"
  display_name = "Secure API Gateway Key"
  
  restrictions {
    api_targets {
      service = local.endpoints_service_name
    }
  }
  
  depends_on = [google_endpoints_service.api_service]
}

# Cloud Armor security policy with comprehensive protection
resource "google_compute_security_policy" "api_security_policy" {
  name        = local.security_policy_name
  description = "Security policy for API gateway with rate limiting and threat protection"
  project     = var.project_id
  
  # Default rule - allow traffic that doesn't match other rules
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule - allow all traffic not matched by other rules"
  }
  
  # Rate limiting rule - prevent abuse
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Rate limiting rule - ${var.rate_limit_threshold} requests per minute per IP"
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      
      rate_limit_threshold {
        count        = var.rate_limit_threshold
        interval_sec = 60
      }
      
      ban_duration_sec = var.ban_duration_sec
    }
  }
  
  # OWASP XSS protection rule
  dynamic "rule" {
    for_each = var.enable_owasp_protection ? [1] : []
    content {
      action   = "deny(403)"
      priority = "2000"
      match {
        expr {
          expression = "evaluatePreconfiguredExpr('xss-canary')"
        }
      }
      description = "OWASP XSS protection rule"
    }
  }
  
  # OWASP SQL injection protection rule
  dynamic "rule" {
    for_each = var.enable_owasp_protection ? [1] : []
    content {
      action   = "deny(403)"
      priority = "3000"
      match {
        expr {
          expression = "evaluatePreconfiguredExpr('sqli-canary')"
        }
      }
      description = "OWASP SQL injection protection rule"
    }
  }
  
  # Geographic restriction rule
  dynamic "rule" {
    for_each = var.enable_geo_restriction && length(var.blocked_countries) > 0 ? [1] : []
    content {
      action   = "deny(403)"
      priority = "4000"
      match {
        expr {
          expression = join(" || ", [
            for country in var.blocked_countries : "origin.region_code == '${country}'"
          ])
        }
      }
      description = "Geographic restriction rule - block ${join(", ", var.blocked_countries)}"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Endpoints Service Proxy (ESP) container instance
resource "google_compute_instance" "esp_proxy" {
  name                      = local.esp_proxy_name
  machine_type              = var.esp_machine_type
  zone                      = var.zone
  allow_stopping_for_update = true
  
  # Labels for resource management
  labels = local.common_labels
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  # Network interface configuration
  network_interface {
    network    = "default"
    network_ip = null
    
    # Ephemeral external IP for load balancer access
    access_config {
      nat_ip                 = null
      public_ptr_domain_name = null
      network_tier           = "PREMIUM"
    }
  }
  
  # Service account with minimal required permissions
  service_account {
    email = google_service_account.esp_proxy.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/servicecontrol"
    ]
  }
  
  # Network tags for firewall rules
  tags = ["esp-proxy", "http-server", "https-server"]
  
  # Container configuration for ESP
  metadata = {
    gce-container-declaration = templatefile("${path.module}/templates/esp-container.yaml.tpl", {
      endpoints_service_name = local.endpoints_service_name
      backend_service_ip     = google_compute_instance.backend_service.network_interface[0].network_ip
      backend_port           = var.backend_port
    })
  }
  
  # Ensure backend service and API configuration are ready
  depends_on = [
    google_compute_instance.backend_service,
    google_endpoints_service.api_service
  ]
}

# Service account for ESP proxy
resource "google_service_account" "esp_proxy" {
  account_id   = "esp-proxy-${random_id.suffix.hex}"
  display_name = "ESP Proxy Service Account"
  description  = "Service account for Endpoints Service Proxy"
  project      = var.project_id
}

# Firewall rule for ESP proxy
resource "google_compute_firewall" "allow_esp_proxy" {
  name    = "allow-esp-proxy-${random_id.suffix.hex}"
  network = "default"
  project = var.project_id
  
  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["esp-proxy"]
  
  description = "Allow traffic to ESP proxy instances"
}

# Unmanaged instance group for ESP proxy
resource "google_compute_instance_group" "esp_proxy_group" {
  name        = local.instance_group_name
  description = "Instance group for ESP proxy instances"
  zone        = var.zone
  project     = var.project_id
  
  instances = [
    google_compute_instance.esp_proxy.id
  ]
  
  named_port {
    name = "http"
    port = 8080
  }
}

# Health check for backend service
resource "google_compute_health_check" "esp_health_check" {
  name                = "esp-health-check-${random_id.suffix.hex}"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3
  project             = var.project_id
  
  http_health_check {
    port         = 8080
    request_path = var.health_check_path
  }
  
  description = "Health check for ESP proxy instances"
}

# Backend service for load balancer
resource "google_compute_backend_service" "esp_backend_service" {
  name                  = "esp-backend-service-${random_id.suffix.hex}"
  description           = "Backend service for ESP proxy with Cloud Armor integration"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  project               = var.project_id
  
  # Attach Cloud Armor security policy
  security_policy = google_compute_security_policy.api_security_policy.id
  
  backend {
    group           = google_compute_instance_group.esp_proxy_group.id
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  health_checks = [google_compute_health_check.esp_health_check.id]
  
  # Enable logging for monitoring
  dynamic "log_config" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      enable      = true
      sample_rate = 1.0
    }
  }
}

# URL map for routing requests
resource "google_compute_url_map" "esp_url_map" {
  name            = "esp-url-map-${random_id.suffix.hex}"
  description     = "URL map for ESP backend service"
  default_service = google_compute_backend_service.esp_backend_service.id
  project         = var.project_id
}

# Reserve static IP address for load balancer
resource "google_compute_global_address" "esp_gateway_ip" {
  name         = "esp-gateway-ip-${random_id.suffix.hex}"
  description  = "Static IP address for API gateway"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  project      = var.project_id
}

# HTTP target proxy for non-SSL traffic
resource "google_compute_target_http_proxy" "esp_http_proxy" {
  name    = "esp-http-proxy-${random_id.suffix.hex}"
  url_map = google_compute_url_map.esp_url_map.id
  project = var.project_id
}

# Global forwarding rule for HTTP traffic
resource "google_compute_global_forwarding_rule" "esp_forwarding_rule_http" {
  name                  = "esp-forwarding-rule-http-${random_id.suffix.hex}"
  description           = "Global forwarding rule for HTTP traffic"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.esp_http_proxy.id
  ip_address            = google_compute_global_address.esp_gateway_ip.id
  project               = var.project_id
}

# Optional SSL configuration for HTTPS termination
resource "google_compute_managed_ssl_certificate" "esp_ssl_cert" {
  count   = var.enable_ssl && var.custom_domain != "" ? 1 : 0
  name    = "esp-ssl-cert-${random_id.suffix.hex}"
  project = var.project_id
  
  managed {
    domains = [var.custom_domain]
  }
}

# HTTPS target proxy (only created if SSL is enabled)
resource "google_compute_target_https_proxy" "esp_https_proxy" {
  count           = var.enable_ssl ? 1 : 0
  name            = "esp-https-proxy-${random_id.suffix.hex}"
  url_map         = google_compute_url_map.esp_url_map.id
  ssl_certificates = var.custom_domain != "" ? [google_compute_managed_ssl_certificate.esp_ssl_cert[0].id] : []
  project         = var.project_id
}

# Global forwarding rule for HTTPS traffic (only created if SSL is enabled)
resource "google_compute_global_forwarding_rule" "esp_forwarding_rule_https" {
  count                 = var.enable_ssl ? 1 : 0
  name                  = "esp-forwarding-rule-https-${random_id.suffix.hex}"
  description           = "Global forwarding rule for HTTPS traffic"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.esp_https_proxy[0].id
  ip_address            = google_compute_global_address.esp_gateway_ip.id
  project               = var.project_id
}