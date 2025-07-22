# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "apigee.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "dns.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    read   = "5m"
  }
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Combine user-provided suffix with random suffix
  resource_suffix = var.resource_suffix != "" ? "${var.resource_suffix}-${random_id.suffix.hex}" : random_id.suffix.hex
  
  # Resource names with suffix
  network_name         = "${var.network_name}-${local.resource_suffix}"
  subnet_us_name      = "apigee-subnet-us-${local.resource_suffix}"
  subnet_eu_name      = "apigee-subnet-eu-${local.resource_suffix}"
  armor_policy_name   = "api-security-policy-${local.resource_suffix}"
  lb_name             = "global-api-lb-${local.resource_suffix}"
  ssl_cert_name       = "api-ssl-cert-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    recipe           = "multi-regional-api-gateways"
  })
}

# Global VPC Network for multi-regional deployment
resource "google_compute_network" "apigee_network" {
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode           = "GLOBAL"
  description            = "Global VPC network for multi-regional Apigee deployment"
  
  depends_on = [google_project_service.required_apis]
}

# Primary region subnet (US)
resource "google_compute_subnetwork" "apigee_subnet_us" {
  name          = local.subnet_us_name
  network       = google_compute_network.apigee_network.id
  ip_cidr_range = var.primary_subnet_cidr
  region        = var.primary_region
  description   = "Subnet for Apigee instances in ${var.primary_region}"
  
  # Enable private Google access for API connectivity
  private_ip_google_access = true
  
  # Secondary ranges for potential future use (pods, services)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "192.168.0.0/18"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "192.168.64.0/18"
  }
}

# Secondary region subnet (EU)
resource "google_compute_subnetwork" "apigee_subnet_eu" {
  name          = local.subnet_eu_name
  network       = google_compute_network.apigee_network.id
  ip_cidr_range = var.secondary_subnet_cidr
  region        = var.secondary_region
  description   = "Subnet for Apigee instances in ${var.secondary_region}"
  
  # Enable private Google access for API connectivity
  private_ip_google_access = true
  
  # Secondary ranges for potential future use (pods, services)
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "192.168.128.0/18"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "192.168.192.0/18"
  }
}

# Service Networking Connection for Apigee
resource "google_service_networking_connection" "apigee_service_connection" {
  network                 = google_compute_network.apigee_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = []
  
  depends_on = [google_project_service.required_apis]
  
  timeouts {
    create = "20m"
    update = "10m"
    delete = "10m"
  }
}

# Apigee Organization
resource "google_apigee_organization" "main" {
  analytics_region                     = var.primary_region
  project_id                          = var.project_id
  billing_type                        = var.apigee_billing_type
  runtime_type                        = var.apigee_runtime_type
  authorized_network                  = google_compute_network.apigee_network.id
  runtime_database_encryption_key_name = null
  
  # Properties for additional configuration
  properties = {
    property {
      name  = "features.hybrid.enabled"
      value = "false"
    }
    property {
      name  = "features.mart.connect.enabled"
      value = "true"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.apigee_service_connection
  ]
  
  timeouts {
    create = "45m"
    update = "20m"
    delete = "20m"
  }
}

# Apigee Instance in US Region
resource "google_apigee_instance" "us_instance" {
  name             = "us-instance"
  location         = var.primary_region
  org_id           = google_apigee_organization.main.name
  peering_cidr_range = "SLASH_16"
  description      = "Apigee instance in ${var.primary_region}"
  
  depends_on = [google_apigee_organization.main]
  
  timeouts {
    create = "30m"
    update = "20m"
    delete = "20m"
  }
}

# Apigee Instance in EU Region
resource "google_apigee_instance" "eu_instance" {
  name             = "eu-instance"
  location         = var.secondary_region
  org_id           = google_apigee_organization.main.name
  peering_cidr_range = "SLASH_16"
  description      = "Apigee instance in ${var.secondary_region}"
  
  depends_on = [google_apigee_organization.main]
  
  timeouts {
    create = "30m"
    update = "20m"
    delete = "20m"
  }
}

# Apigee Environment for US
resource "google_apigee_environment" "production_us" {
  name         = "production-us"
  description  = "Production environment for US region"
  org_id       = google_apigee_organization.main.name
  display_name = "Production US"
  
  depends_on = [google_apigee_organization.main]
}

# Apigee Environment for EU
resource "google_apigee_environment" "production_eu" {
  name         = "production-eu"
  description  = "Production environment for EU region"
  org_id       = google_apigee_organization.main.name
  display_name = "Production EU"
  
  depends_on = [google_apigee_organization.main]
}

# Apigee Environment Group for US
resource "google_apigee_envgroup" "prod_us" {
  name      = "prod-us"
  org_id    = google_apigee_organization.main.name
  hostnames = length(var.domain_names) > 0 ? [var.domain_names[0]] : ["api-${local.resource_suffix}.example.com"]
  
  depends_on = [google_apigee_organization.main]
}

# Apigee Environment Group for EU
resource "google_apigee_envgroup" "prod_eu" {
  name      = "prod-eu"
  org_id    = google_apigee_organization.main.name
  hostnames = length(var.domain_names) > 1 ? [var.domain_names[1]] : ["eu-api-${local.resource_suffix}.example.com"]
  
  depends_on = [google_apigee_organization.main]
}

# Attach Environment to Instance - US
resource "google_apigee_instance_attachment" "us_attachment" {
  instance_id = google_apigee_instance.us_instance.id
  environment = google_apigee_environment.production_us.name
  
  depends_on = [
    google_apigee_instance.us_instance,
    google_apigee_environment.production_us
  ]
  
  timeouts {
    create = "20m"
    delete = "20m"
  }
}

# Attach Environment to Instance - EU
resource "google_apigee_instance_attachment" "eu_attachment" {
  instance_id = google_apigee_instance.eu_instance.id
  environment = google_apigee_environment.production_eu.name
  
  depends_on = [
    google_apigee_instance.eu_instance,
    google_apigee_environment.production_eu
  ]
  
  timeouts {
    create = "20m"
    delete = "20m"
  }
}

# Attach Environment to Environment Group - US
resource "google_apigee_envgroup_attachment" "us_envgroup_attachment" {
  envgroup_id = google_apigee_envgroup.prod_us.id
  environment = google_apigee_environment.production_us.name
  
  depends_on = [
    google_apigee_envgroup.prod_us,
    google_apigee_environment.production_us
  ]
}

# Attach Environment to Environment Group - EU
resource "google_apigee_envgroup_attachment" "eu_envgroup_attachment" {
  envgroup_id = google_apigee_envgroup.prod_eu.id
  environment = google_apigee_environment.production_eu.name
  
  depends_on = [
    google_apigee_envgroup.prod_eu,
    google_apigee_environment.production_eu
  ]
}

# Cloud Armor Security Policy
resource "google_compute_security_policy" "api_security_policy" {
  name        = local.armor_policy_name
  description = "Multi-regional API security policy with comprehensive protection"
  
  # Default rule - allow all traffic that doesn't match other rules
  rule {
    action   = "allow"
    priority = 2147483647
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
  
  # Block traffic from specified regions
  dynamic "rule" {
    for_each = length(var.blocked_regions) > 0 ? [1] : []
    content {
      action   = "deny(403)"
      priority = 1000
      match {
        expr {
          expression = join(" || ", [for region in var.blocked_regions : "origin.region_code == '${region}'"])
        }
      }
      description = "Block traffic from high-risk regions: ${join(", ", var.blocked_regions)}"
    }
  }
  
  # Rate limiting rule for DDoS protection
  rule {
    action   = "rate_based_ban"
    priority = 2000
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_threshold
        interval_sec = 60
      }
      ban_duration_sec = var.ban_duration_seconds
    }
    description = "Rate limiting for DDoS protection - ${var.rate_limit_threshold} requests per minute"
  }
  
  # SQL injection protection
  rule {
    action   = "deny(403)"
    priority = 3000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
    description = "Block SQL injection attacks"
  }
  
  # Cross-site scripting (XSS) protection
  rule {
    action   = "deny(403)"
    priority = 4000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
    description = "Block cross-site scripting attacks"
  }
  
  # Local file inclusion (LFI) protection
  rule {
    action   = "deny(403)"
    priority = 5000
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }
    description = "Block local file inclusion attacks"
  }
  
  # Block known malicious user agents
  rule {
    action   = "deny(403)"
    priority = 6000
    match {
      expr {
        expression = "request.headers['user-agent'].contains('BadBot') || request.headers['user-agent'].contains('MaliciousScanner')"
      }
    }
    description = "Block known malicious user agents"
  }
  
  # Adaptive protection (requires Cloud Armor Advanced)
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
  
  # Advanced DDoS protection
  advanced_options_config {
    log_level    = var.enable_cloud_armor_logging ? "VERBOSE" : "NORMAL"
    json_parsing = "STANDARD"
    
    json_custom_config {
      content_types = ["application/json", "application/json; charset=utf-8"]
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Global static IP address for load balancer
resource "google_compute_global_address" "api_ip" {
  name         = "${local.lb_name}-ip"
  description  = "Global static IP for API load balancer"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  
  depends_on = [google_project_service.required_apis]
}

# Health check for backend services
resource "google_compute_health_check" "api_health_check" {
  name        = "api-health-check-${local.resource_suffix}"
  description = "Health check for API backend services"
  
  timeout_sec         = 5
  check_interval_sec  = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port               = var.health_check_port
    request_path       = var.health_check_path
    port_specification = "USE_FIXED_PORT"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Backend service for US region
resource "google_compute_backend_service" "apigee_backend_us" {
  name                            = "apigee-backend-us-${local.resource_suffix}"
  description                     = "Backend service for Apigee US region"
  protocol                        = "HTTPS"
  port_name                       = "https"
  timeout_sec                     = 30
  enable_cdn                      = false
  connection_draining_timeout_sec = 300
  
  backend {
    group           = google_apigee_instance.us_instance.service_attachment
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  health_checks         = [google_compute_health_check.api_health_check.id]
  security_policy       = google_compute_security_policy.api_security_policy.id
  load_balancing_scheme = "EXTERNAL"
  
  # Connection and circuit breaker settings
  circuit_breakers {
    max_requests_per_connection = 1000
    max_connections             = 1000
    max_pending_requests        = 1000
    max_requests                = 1000
    max_retries                 = 3
  }
  
  # Consistent hash for session affinity (if needed)
  consistent_hash {
    http_header_name = "x-session-id"
  }
  
  depends_on = [
    google_apigee_instance.us_instance,
    google_compute_health_check.api_health_check,
    google_compute_security_policy.api_security_policy
  ]
}

# Backend service for EU region
resource "google_compute_backend_service" "apigee_backend_eu" {
  name                            = "apigee-backend-eu-${local.resource_suffix}"
  description                     = "Backend service for Apigee EU region"
  protocol                        = "HTTPS"
  port_name                       = "https"
  timeout_sec                     = 30
  enable_cdn                      = false
  connection_draining_timeout_sec = 300
  
  backend {
    group           = google_apigee_instance.eu_instance.service_attachment
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  health_checks         = [google_compute_health_check.api_health_check.id]
  security_policy       = google_compute_security_policy.api_security_policy.id
  load_balancing_scheme = "EXTERNAL"
  
  # Connection and circuit breaker settings
  circuit_breakers {
    max_requests_per_connection = 1000
    max_connections             = 1000
    max_pending_requests        = 1000
    max_requests                = 1000
    max_retries                 = 3
  }
  
  # Consistent hash for session affinity (if needed)
  consistent_hash {
    http_header_name = "x-session-id"
  }
  
  depends_on = [
    google_apigee_instance.eu_instance,
    google_compute_health_check.api_health_check,
    google_compute_security_policy.api_security_policy
  ]
}

# Managed SSL certificate (only if domain names are provided)
resource "google_compute_managed_ssl_certificate" "api_ssl_cert" {
  count = length(var.domain_names) > 0 ? 1 : 0
  
  name        = local.ssl_cert_name
  description = "Managed SSL certificate for API domains"
  
  managed {
    domains = var.domain_names
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# URL map for routing traffic
resource "google_compute_url_map" "api_url_map" {
  name            = "${local.lb_name}-url-map"
  description     = "URL map for multi-regional API routing"
  default_service = google_compute_backend_service.apigee_backend_us.id
  
  # Path matcher for EU traffic
  path_matcher {
    name            = "eu-matcher"
    default_service = google_compute_backend_service.apigee_backend_eu.id
    
    path_rule {
      paths   = ["/eu/*"]
      service = google_compute_backend_service.apigee_backend_eu.id
    }
  }
  
  # Host rule for EU domains
  dynamic "host_rule" {
    for_each = length(var.domain_names) > 1 ? [var.domain_names[1]] : []
    content {
      hosts        = [host_rule.value]
      path_matcher = "eu-matcher"
    }
  }
  
  depends_on = [
    google_compute_backend_service.apigee_backend_us,
    google_compute_backend_service.apigee_backend_eu
  ]
}

# Target HTTPS proxy
resource "google_compute_target_https_proxy" "api_proxy" {
  name             = "${local.lb_name}-proxy"
  description      = "HTTPS proxy for API load balancer"
  url_map          = google_compute_url_map.api_url_map.id
  ssl_certificates = length(var.domain_names) > 0 ? [google_compute_managed_ssl_certificate.api_ssl_cert[0].id] : []
  
  # SSL policy for security
  ssl_policy = google_compute_ssl_policy.api_ssl_policy.id
  
  depends_on = [
    google_compute_url_map.api_url_map,
    google_compute_ssl_policy.api_ssl_policy
  ]
}

# SSL Policy for enhanced security
resource "google_compute_ssl_policy" "api_ssl_policy" {
  name            = "api-ssl-policy-${local.resource_suffix}"
  description     = "SSL policy for API security"
  profile         = "MODERN"
  min_tls_version = var.minimum_tls_version
  
  depends_on = [google_project_service.required_apis]
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "api_https_rule" {
  name                  = "${local.lb_name}-https-rule"
  description          = "Global forwarding rule for HTTPS API traffic"
  target               = google_compute_target_https_proxy.api_proxy.id
  port_range           = "443"
  load_balancing_scheme = "EXTERNAL"
  ip_address           = google_compute_global_address.api_ip.address
  
  depends_on = [google_compute_target_https_proxy.api_proxy]
}

# HTTP to HTTPS redirect (optional)
resource "google_compute_url_map" "api_http_redirect" {
  count = var.enable_ssl_redirect ? 1 : 0
  
  name        = "${local.lb_name}-http-redirect"
  description = "URL map for HTTP to HTTPS redirect"
  
  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "api_http_proxy" {
  count = var.enable_ssl_redirect ? 1 : 0
  
  name        = "${local.lb_name}-http-proxy"
  description = "HTTP proxy for redirect to HTTPS"
  url_map     = google_compute_url_map.api_http_redirect[0].id
}

resource "google_compute_global_forwarding_rule" "api_http_rule" {
  count = var.enable_ssl_redirect ? 1 : 0
  
  name                  = "${local.lb_name}-http-rule"
  description          = "Global forwarding rule for HTTP redirect"
  target               = google_compute_target_http_proxy.api_http_proxy[0].id
  port_range           = "80"
  load_balancing_scheme = "EXTERNAL"
  ip_address           = google_compute_global_address.api_ip.address
}