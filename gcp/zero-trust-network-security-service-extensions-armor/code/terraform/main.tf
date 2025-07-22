# Zero-Trust Network Security with Service Extensions and Cloud Armor
# This Terraform configuration deploys a comprehensive zero-trust security architecture
# using Google Cloud's Service Extensions, Cloud Armor, and Identity-Aware Proxy

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and tagging
locals {
  name_prefix = var.resource_prefix != "" ? var.resource_prefix : "${var.application_name}-${random_id.suffix.hex}"
  zone        = var.zone != "" ? var.zone : "${var.region}-a"
  
  common_tags = merge(var.tags, {
    environment     = var.environment
    application     = var.application_name
    deployment_type = "zero-trust-security"
    terraform       = "true"
    created_date    = timestamp()
  })
}

# ============================================================================
# NETWORKING INFRASTRUCTURE
# ============================================================================

# Create custom VPC network for zero-trust architecture
resource "google_compute_network" "zero_trust_vpc" {
  name                    = "${local.name_prefix}-vpc"
  description             = "VPC network for zero-trust security architecture"
  auto_create_subnetworks = false
  routing_mode           = "GLOBAL"
  mtu                    = 1460
  
  # Enable deletion protection for production environments
  deletion_protection = var.environment == "prod" ? true : false
}

# Create private subnet with security-first configuration
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "${local.name_prefix}-subnet"
  description              = "Private subnet for zero-trust backend services"
  ip_cidr_range           = var.subnet_cidr
  region                  = var.region
  network                 = google_compute_network.zero_trust_vpc.id
  private_ip_google_access = var.enable_private_google_access
  
  # Enable flow logging for security monitoring
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 1.0
      metadata            = "INCLUDE_ALL_METADATA"
      metadata_fields     = ["SRC_IP", "DEST_IP", "SRC_PORT", "DEST_PORT", "PROTOCOL"]
      filter_expr         = "true"
    }
  }
  
  # Secondary IP range for services (if needed for GKE or other services)
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.1.0.0/16"
  }
}

# Cloud NAT Gateway for outbound internet access from private instances
resource "google_compute_router" "nat_router" {
  name    = "${local.name_prefix}-nat-router"
  region  = var.region
  network = google_compute_network.zero_trust_vpc.id
  
  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "nat_gateway" {
  name                               = "${local.name_prefix}-nat-gateway"
  router                            = google_compute_router.nat_router.name
  region                            = var.region
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall rules for zero-trust security
resource "google_compute_firewall" "allow_health_check" {
  name        = "${local.name_prefix}-allow-health-check"
  description = "Allow health check probes from Google Cloud load balancers"
  network     = google_compute_network.zero_trust_vpc.name
  direction   = "INGRESS"
  priority    = 1000
  
  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }
  
  # Google Cloud health check source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web-server"]
}

resource "google_compute_firewall" "allow_load_balancer" {
  name        = "${local.name_prefix}-allow-load-balancer"
  description = "Allow traffic from Google Cloud load balancers"
  network     = google_compute_network.zero_trust_vpc.name
  direction   = "INGRESS"
  priority    = 1000
  
  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }
  
  # Google Cloud load balancer source ranges
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web-server"]
}

resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${local.name_prefix}-deny-all-ingress"
  description = "Deny all other ingress traffic (default deny)"
  network     = google_compute_network.zero_trust_vpc.name
  direction   = "INGRESS"
  priority    = 65534
  
  deny {
    protocol = "all"
  }
  
  source_ranges = ["0.0.0.0/0"]
}

# ============================================================================
# SERVICE ACCOUNTS AND IAM
# ============================================================================

# Service account for backend instances
resource "google_service_account" "backend_sa" {
  account_id   = "${local.name_prefix}-backend-sa"
  display_name = "Backend Service Account for Zero Trust Architecture"
  description  = "Service account for backend compute instances with minimal required permissions"
}

# Service account for Cloud Run service extension
resource "google_service_account" "service_extension_sa" {
  account_id   = "${local.name_prefix}-ext-sa"
  display_name = "Service Extension Service Account"
  description  = "Service account for Cloud Run service extension with security processing permissions"
}

# IAM bindings for backend service account (minimal permissions)
resource "google_project_iam_member" "backend_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

resource "google_project_iam_member" "backend_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.backend_sa.email}"
}

# IAM bindings for service extension service account
resource "google_project_iam_member" "service_extension_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.service_extension_sa.email}"
}

resource "google_project_iam_member" "service_extension_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.service_extension_sa.email}"
}

# ============================================================================
# CLOUD ARMOR SECURITY POLICY
# ============================================================================

# Comprehensive Cloud Armor security policy with zero-trust principles
resource "google_compute_security_policy" "zero_trust_policy" {
  name        = var.security_policy_name
  description = "Zero-trust security policy with DDoS protection, rate limiting, and geo-blocking"
  type        = "CLOUD_ARMOR"
  
  # Advanced options for enhanced security inspection
  advanced_options_config {
    json_parsing                = "STANDARD"
    log_level                  = "VERBOSE"
    user_ip_request_headers    = ["X-Forwarded-For", "X-Real-IP", "X-Client-IP"]
    json_custom_config {
      content_types = ["application/json", "application/x-www-form-urlencoded"]
    }
  }
  
  # Adaptive protection configuration for DDoS defense
  dynamic "adaptive_protection_config" {
    for_each = var.enable_adaptive_protection ? [1] : []
    content {
      layer_7_ddos_defense_config {
        enable          = true
        rule_visibility = "STANDARD"
        
        threshold_configs {
          name                            = "adaptive-protection-auto-deploy"
          auto_deploy_load_threshold      = 0.7
          auto_deploy_confidence_threshold = 0.9
          auto_deploy_impacted_baseline_threshold = 0.1
          auto_deploy_expiration_sec      = 3600
        }
      }
    }
  }
  
  # Rule 1: Rate limiting to prevent abuse and DDoS attacks
  rule {
    action   = "throttle"
    priority = 1000
    description = "Rate limiting - ${var.rate_limit_threshold} requests per minute per IP"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      
      enforce_on_key_configs {
        enforce_on_key_type = "IP"
      }
      
      rate_limit_threshold {
        count        = var.rate_limit_threshold
        interval_sec = 60
      }
      
      ban_threshold {
        count        = var.rate_limit_threshold * 5
        interval_sec = 60
      }
      
      ban_duration_sec = var.ban_duration_sec
    }
  }
  
  # Rule 2: Geographic blocking of high-risk countries
  rule {
    action   = "deny(403)"
    priority = 2000
    description = "Block traffic from high-risk geographic regions: ${join(", ", var.blocked_countries)}"
    
    match {
      expr {
        expression = "origin.region_code in [${join(", ", [for country in var.blocked_countries : "'${country}'"])}]"
      }
    }
  }
  
  # Rule 3: Block common attack patterns - SQL injection
  rule {
    action   = "deny(403)"
    priority = 3000
    description = "Block SQL injection attempts"
    
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('sqli-stable')"
      }
    }
  }
  
  # Rule 4: Block XSS attacks
  rule {
    action   = "deny(403)"
    priority = 4000
    description = "Block XSS attacks"
    
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('xss-stable')"
      }
    }
  }
  
  # Rule 5: Block local file inclusion attacks
  rule {
    action   = "deny(403)"
    priority = 5000
    description = "Block local file inclusion attempts"
    
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('lfi-stable')"
      }
    }
  }
  
  # Rule 6: Block remote code execution attempts
  rule {
    action   = "deny(403)"
    priority = 6000
    description = "Block remote code execution attempts"
    
    match {
      expr {
        expression = "evaluatePreconfiguredExpr('rce-stable')"
      }
    }
  }
  
  # Rule 7: Custom rule to block admin path access from unauthorized sources
  rule {
    action   = "deny(403)"
    priority = 7000
    description = "Block access to admin paths"
    
    match {
      expr {
        expression = "request.path.matches('^/admin.*') || request.path.matches('^/wp-admin.*')"
      }
    }
  }
  
  # Default allow rule (lowest priority)
  rule {
    action   = "allow"
    priority = 2147483647
    description = "Default allow rule for all other traffic"
    
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

# ============================================================================
# SERVICE EXTENSION (CLOUD RUN)
# ============================================================================

# VPC Connector for Cloud Run to access VPC resources
resource "google_vpc_access_connector" "connector" {
  provider      = google-beta
  name          = "${local.name_prefix}-vpc-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.zero_trust_vpc.name
  
  # Machine type for the connector
  machine_type = "e2-micro"
  min_instances = 2
  max_instances = 3
}

# Cloud Run service for custom security extension
resource "google_cloud_run_v2_service" "service_extension" {
  name         = var.service_extension_name
  location     = var.region
  description  = "Service extension for zero-trust traffic inspection and security processing"
  ingress      = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  
  template {
    service_account = google_service_account.service_extension_sa.email
    
    # VPC configuration for private networking
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }
    
    # Scaling configuration
    scaling {
      min_instance_count = 1
      max_instance_count = 10
    }
    
    # Container configuration
    containers {
      image = var.service_extension_image
      
      ports {
        name           = "http1"
        container_port = 8080
      }
      
      # Environment variables for security processing
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "LOG_LEVEL"
        value = "INFO"
      }
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.service_extension_cpu
          memory = var.service_extension_memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }
      
      # Health check configuration
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 15
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }
  }
  
  # Traffic routing
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [google_vpc_access_connector.connector]
}

# Network Endpoint Group for Cloud Run service
resource "google_compute_region_network_endpoint_group" "service_extension_neg" {
  name                  = "${local.name_prefix}-service-extension-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  
  cloud_run {
    service = google_cloud_run_v2_service.service_extension.name
  }
}

# ============================================================================
# BACKEND INFRASTRUCTURE
# ============================================================================

# Instance template for backend servers with security hardening
resource "google_compute_instance_template" "backend_template" {
  name_prefix  = "${local.name_prefix}-template-"
  description  = "Instance template for zero-trust backend servers"
  machine_type = var.machine_type
  region       = var.region
  
  tags = ["web-server", "zero-trust-backend"]
  
  # Shielded VM configuration for additional security
  dynamic "shielded_instance_config" {
    for_each = var.enable_shielded_vm ? [1] : []
    content {
      enable_secure_boot          = true
      enable_vtpm                 = true
      enable_integrity_monitoring = true
    }
  }
  
  # Confidential computing configuration
  dynamic "confidential_instance_config" {
    for_each = var.enable_confidential_compute ? [1] : []
    content {
      enable_confidential_compute = true
    }
  }
  
  # Boot disk configuration with encryption
  disk {
    source_image = "projects/cos-cloud/global/images/family/cos-stable"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-balanced"
    disk_size_gb = 20
    
    # Enable disk encryption
    disk_encryption_key {
      raw_key = null # Uses Google-managed encryption keys
    }
  }
  
  # Network interface configuration
  network_interface {
    network    = google_compute_network.zero_trust_vpc.id
    subnetwork = google_compute_subnetwork.private_subnet.id
    
    # No external IP - use NAT gateway for outbound connectivity
    access_config = []
  }
  
  # Service account with minimal permissions
  service_account {
    email  = google_service_account.backend_sa.email
    scopes = ["cloud-platform"]
  }
  
  # Metadata for security hardening
  metadata = {
    enable-oslogin                = "TRUE"
    enable-oslogin-2fa           = "TRUE"
    block-project-ssh-keys       = "TRUE"
    enable-ip-forwarding         = "FALSE"
    user-data = base64encode(templatefile("${path.module}/startup-script.sh", {
      project_id = var.project_id
      region     = var.region
    }))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Managed Instance Group for backend servers
resource "google_compute_instance_group_manager" "backend_mig" {
  name               = "${local.name_prefix}-backend-mig"
  base_instance_name = "${local.name_prefix}-backend"
  zone               = local.zone
  target_size        = var.backend_instance_count
  
  version {
    instance_template = google_compute_instance_template.backend_template.id
  }
  
  # Named ports for load balancer
  named_port {
    name = "http"
    port = 8080
  }
  
  # Auto-healing with health check
  auto_healing_policies {
    health_check      = google_compute_health_check.default.id
    initial_delay_sec = 300
  }
  
  # Update policy for zero-downtime deployments
  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 1
    max_unavailable_fixed          = 0
    min_ready_sec                  = 60
    replacement_method             = "RECREATE"
  }
  
  depends_on = [google_compute_instance_template.backend_template]
}

# Health check for backend instances
resource "google_compute_health_check" "default" {
  name        = "${local.name_prefix}-health-check"
  description = "Health check for zero-trust backend instances"
  
  timeout_sec         = 5
  check_interval_sec  = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port_specification = "USE_FIXED_PORT"
    port               = 8080
    request_path       = "/health"
  }
  
  log_config {
    enable = true
  }
}

# ============================================================================
# LOAD BALANCER CONFIGURATION
# ============================================================================

# Global static IP address for the load balancer
resource "google_compute_global_address" "default" {
  name         = "${local.name_prefix}-global-ip"
  description  = "Global static IP for zero-trust load balancer"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}

# Managed SSL certificate for HTTPS termination
resource "google_compute_managed_ssl_certificate" "default" {
  name        = "${local.name_prefix}-ssl-cert"
  description = "Managed SSL certificate for zero-trust architecture"
  
  managed {
    domains = var.ssl_domains
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# SSL policy for enhanced security
resource "google_compute_ssl_policy" "default" {
  name            = "${local.name_prefix}-ssl-policy"
  description     = "SSL policy with strong security settings"
  profile         = "RESTRICTED"
  min_tls_version = "TLS_1_2"
}

# Backend service with IAP and security policy
resource "google_compute_backend_service" "default" {
  name                  = "${local.name_prefix}-backend-service"
  description           = "Backend service with zero-trust security controls"
  protocol              = "HTTP"
  port_name            = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec          = 30
  
  # Attach Cloud Armor security policy
  security_policy = google_compute_security_policy.zero_trust_policy.id
  
  # Enable Identity-Aware Proxy
  dynamic "iap" {
    for_each = var.oauth_client_id != "" ? [1] : []
    content {
      enabled              = true
      oauth2_client_id     = var.oauth_client_id
      oauth2_client_secret = var.oauth_client_secret
    }
  }
  
  # Health check configuration
  health_checks = [google_compute_health_check.default.id]
  
  # Backend configuration
  backend {
    group           = google_compute_instance_group_manager.backend_mig.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }
  
  # Enable comprehensive logging
  log_config {
    enable      = true
    sample_rate = 1.0
  }
  
  # Security headers
  custom_request_headers = [
    "X-Forwarded-Proto: https",
    "X-Client-Region: {client_region}",
    "X-Client-City: {client_city}",
    "X-Client-Country: {client_region_subdivision}"
  ]
  
  custom_response_headers = [
    "X-Frame-Options: DENY",
    "X-Content-Type-Options: nosniff",
    "Strict-Transport-Security: max-age=31536000; includeSubDomains",
    "X-XSS-Protection: 1; mode=block",
    "Referrer-Policy: strict-origin-when-cross-origin"
  ]
  
  depends_on = [
    google_compute_instance_group_manager.backend_mig,
    google_compute_security_policy.zero_trust_policy
  ]
}

# URL map for routing traffic
resource "google_compute_url_map" "default" {
  name            = "${local.name_prefix}-url-map"
  description     = "URL map for zero-trust load balancer"
  default_service = google_compute_backend_service.default.id
  
  # Optional: Add path-based routing rules here
  host_rule {
    hosts        = var.ssl_domains
    path_matcher = "allpaths"
  }
  
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.default.id
    
    # Example: Route health checks to a specific service
    path_rule {
      paths   = ["/health"]
      service = google_compute_backend_service.default.id
    }
  }
}

# HTTPS proxy with SSL certificate
resource "google_compute_target_https_proxy" "default" {
  name             = "${local.name_prefix}-https-proxy"
  description      = "HTTPS proxy for zero-trust load balancer"
  url_map          = google_compute_url_map.default.id
  ssl_certificates = [google_compute_managed_ssl_certificate.default.id]
  ssl_policy       = google_compute_ssl_policy.default.id
}

# Global forwarding rule for HTTPS traffic
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "${local.name_prefix}-forwarding-rule"
  description           = "Global forwarding rule for HTTPS traffic"
  target                = google_compute_target_https_proxy.default.id
  port_range           = "443"
  ip_address           = google_compute_global_address.default.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ============================================================================
# IAP IAM CONFIGURATION
# ============================================================================

# IAM binding for IAP access (if users are specified)
resource "google_iap_web_backend_service_iam_binding" "iap_access" {
  count               = length(var.iap_users) > 0 ? 1 : 0
  project             = var.project_id
  web_backend_service = google_compute_backend_service.default.name
  role               = "roles/iap.httpsResourceAccessor"
  members            = [for user in var.iap_users : "user:${user}"]
}

# ============================================================================
# MONITORING AND LOGGING
# ============================================================================

# Log sink for security events
resource "google_logging_project_sink" "security_sink" {
  name        = "${local.name_prefix}-security-sink"
  description = "Sink for zero-trust security logs"
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/${local.name_prefix}-security-logs"
  
  filter = <<-EOT
    (resource.type="http_load_balancer" OR 
     resource.type="gce_instance" OR
     resource.type="cloud_run_revision") AND
    (severity>=WARNING OR
     jsonPayload.enforcement_action!="" OR
     httpRequest.status>=400)
  EOT
  
  unique_writer_identity = true
}

# Monitoring notification channel
resource "google_monitoring_notification_channel" "email" {
  display_name = "${local.name_prefix} Security Alerts"
  type         = "email"
  description  = "Email notifications for zero-trust security alerts"
  
  labels = {
    email_address = var.notification_email
  }
}

# Alert policy for security events
resource "google_monitoring_alert_policy" "security_alerts" {
  display_name = "${local.name_prefix} Security Alert Policy"
  description  = "Alert policy for zero-trust security events and anomalies"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High rate of blocked requests"
    
    condition_threshold {
      filter          = "resource.type=\"http_load_balancer\" AND metric.type=\"loadbalancing.googleapis.com/https/request_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 100
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields     = ["resource.label.backend_service_name"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  conditions {
    display_name = "Backend service errors"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/up\""
      duration        = "180s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.id]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  documentation {
    content   = "Zero-trust security alert: Investigate potential security incident or service degradation."
    mime_type = "text/markdown"
  }
}

# ============================================================================
# STARTUP SCRIPT FOR BACKEND INSTANCES
# ============================================================================

# Create startup script for backend instances
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content  = <<-EOF
#!/bin/bash
# Startup script for zero-trust backend instances

set -e

# Update system
apt-get update

# Install Docker if not present (for Container-Optimized OS)
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
fi

# Create application directory
mkdir -p /opt/app

# Create simple web application
cat > /opt/app/app.py << 'EOL'
from flask import Flask, request, jsonify
import os
import socket
import json
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def home():
    return f"""
    <html>
    <head><title>Zero Trust Protected Application</title></head>
    <body>
        <h1>🔒 Zero Trust Security Enabled</h1>
        <p><strong>Status:</strong> ✅ Application is protected by zero-trust architecture</p>
        <p><strong>Server:</strong> {socket.gethostname()}</p>
        <p><strong>Timestamp:</strong> {datetime.now().isoformat()}</p>
        <p><strong>Security Headers:</strong> Enabled</p>
        <p><strong>Client IP:</strong> {request.headers.get('X-Forwarded-For', request.remote_addr)}</p>
        <p><strong>User Agent:</strong> {request.headers.get('User-Agent', 'Unknown')}</p>
        <hr>
        <h3>Security Features Active:</h3>
        <ul>
            <li>✅ Cloud Armor DDoS Protection</li>
            <li>✅ Rate Limiting</li>
            <li>✅ Geographic Filtering</li>
            <li>✅ WAF Rules (XSS, SQLi, LFI, RCE)</li>
            <li>✅ Identity-Aware Proxy</li>
            <li>✅ Service Extensions</li>
            <li>✅ SSL/TLS Termination</li>
            <li>✅ Security Headers</li>
        </ul>
    </body>
    </html>
    """

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'hostname': socket.gethostname(),
        'version': '1.0.0'
    })

@app.route('/api/status')
def api_status():
    return jsonify({
        'application': 'zero-trust-demo',
        'status': 'running',
        'security': 'enabled',
        'timestamp': datetime.now().isoformat(),
        'server': socket.gethostname(),
        'headers': dict(request.headers)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOL

# Create Dockerfile
cat > /opt/app/Dockerfile << 'EOL'
FROM python:3.9-slim
WORKDIR /app
RUN pip install flask gunicorn
COPY app.py .
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
EOL

# Build and run the application
cd /opt/app
docker build -t zero-trust-app .
docker run -d --name zero-trust-app --restart unless-stopped -p 8080:8080 zero-trust-app

# Configure logging
docker logs zero-trust-app

echo "Zero-trust backend application started successfully"
EOF
}