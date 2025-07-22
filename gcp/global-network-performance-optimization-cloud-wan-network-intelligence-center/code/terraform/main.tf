# Global Network Performance Optimization with Cloud WAN and Network Intelligence Center
# This Terraform configuration deploys a comprehensive global network architecture
# with performance optimization, monitoring, and analytics capabilities

locals {
  # Generate a unique suffix for resource names to avoid conflicts
  unique_suffix = random_id.suffix.hex
  network_name  = "${var.network_name}-${local.unique_suffix}"
  
  # Common resource labels
  common_labels = merge(var.tags, {
    deployment_tool = "terraform"
    recipe_name     = "global-network-performance-optimization"
  })
}

# Generate unique suffix for resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "networksecurity.googleapis.com",
    "networkconnectivity.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy         = false
}

# ============================================================================
# GLOBAL VPC NETWORK INFRASTRUCTURE
# ============================================================================

# Create global VPC network with custom subnet mode
resource "google_compute_network" "global_wan_network" {
  name                    = local.network_name
  description             = "Global enterprise network with WAN optimization and intelligence"
  auto_create_subnetworks = false
  routing_mode           = "GLOBAL"
  
  delete_default_routes_on_create = false

  depends_on = [google_project_service.required_apis]
}

# Create regional subnets for multi-region deployment
resource "google_compute_subnetwork" "regional_subnets" {
  for_each = var.regions

  name                     = "${local.network_name}-${each.key}"
  ip_cidr_range           = each.value.subnet_cidr
  region                  = each.value.name
  network                 = google_compute_network.global_wan_network.id
  description             = "Subnet for ${each.key} region with network intelligence"
  
  private_ip_google_access = var.network_security_config.enable_private_google_access

  # Enable VPC Flow Logs for Network Intelligence Center
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []
    content {
      aggregation_interval = var.flow_logs_interval
      flow_sampling        = var.flow_logs_sampling
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }

  depends_on = [google_compute_network.global_wan_network]
}

# ============================================================================
# NETWORK SECURITY - FIREWALL RULES
# ============================================================================

# Firewall rule for internal VPC communication
resource "google_compute_firewall" "allow_internal" {
  name        = "${local.network_name}-allow-internal"
  network     = google_compute_network.global_wan_network.name
  description = "Allow internal VPC communication for global network"

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/8"]
  priority      = 1000

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule for load balancer health checks
resource "google_compute_firewall" "allow_health_checks" {
  name        = "${local.network_name}-allow-lb-health"
  network     = google_compute_network.global_wan_network.name
  description = "Allow load balancer health checks"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080"]
  }

  source_ranges = var.network_security_config.allowed_health_check_ranges
  target_tags   = ["web-server"]
  priority      = 1000

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# Firewall rule for SSH access (restrict in production)
resource "google_compute_firewall" "allow_ssh" {
  name        = "${local.network_name}-allow-ssh"
  network     = google_compute_network.global_wan_network.name
  description = "Allow SSH for management (restrict source ranges in production)"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.network_security_config.allowed_ssh_ranges
  target_tags   = ["ssh-allowed"]
  priority      = 1000

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

# ============================================================================
# REGIONAL COMPUTE INFRASTRUCTURE
# ============================================================================

# VM instances for each region to demonstrate global connectivity
resource "google_compute_instance" "regional_web_servers" {
  for_each = var.regions

  name         = "web-server-${each.key}-1"
  zone         = each.value.zone
  machine_type = var.machine_type
  description  = "Web server for ${each.key} region demonstrating global network performance"

  deletion_protection = var.enable_deletion_protection

  boot_disk {
    initialize_params {
      image = "${var.instance_image.project}/${var.instance_image.family}"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.global_wan_network.id
    subnetwork = google_compute_subnetwork.regional_subnets[each.key].id
    
    # Assign external IP for demonstration (remove in production for security)
    access_config {
      nat_ip                 = null
      public_ptr_domain_name = null
      network_tier          = "PREMIUM"
    }
  }

  # Install nginx and create region-specific content
  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    region = each.key
  })

  tags = ["web-server", "ssh-allowed", "${each.key}-region"]

  labels = merge(local.common_labels, {
    region = each.key
    role   = "web-server"
  })

  service_account {
    email  = google_service_account.compute_service_account.email
    scopes = ["cloud-platform"]
  }

  depends_on = [
    google_compute_subnetwork.regional_subnets,
    google_compute_firewall.allow_internal,
    google_compute_firewall.allow_health_checks
  ]
}

# Service account for compute instances
resource "google_service_account" "compute_service_account" {
  account_id   = "compute-sa-${local.unique_suffix}"
  display_name = "Compute Service Account for Global Network Demo"
  description  = "Service account for compute instances in global network demonstration"
}

# IAM binding for compute service account
resource "google_project_iam_member" "compute_sa_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.compute_service_account.email}"
}

resource "google_project_iam_member" "compute_sa_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.compute_service_account.email}"
}

# ============================================================================
# GLOBAL LOAD BALANCER CONFIGURATION
# ============================================================================

# Create unmanaged instance groups for each region
resource "google_compute_instance_group" "web_instance_groups" {
  for_each = var.regions

  name        = "web-group-${each.key}"
  description = "${each.key} region web servers for global load balancing"
  zone        = each.value.zone

  instances = [
    google_compute_instance.regional_web_servers[each.key].id
  ]

  named_port {
    name = "http"
    port = "80"
  }

  named_port {
    name = "https"
    port = "443"
  }
}

# Health check for load balancer
resource "google_compute_health_check" "web_health_check" {
  name        = "global-web-health-check"
  description = "Health check for global web application load balancer"

  timeout_sec         = var.health_check_config.timeout_sec
  check_interval_sec  = var.health_check_config.check_interval_sec
  healthy_threshold   = var.health_check_config.healthy_threshold
  unhealthy_threshold = var.health_check_config.unhealthy_threshold

  http_health_check {
    port         = var.health_check_config.port
    request_path = var.health_check_config.request_path
  }

  log_config {
    enable = true
  }
}

# Backend service for global load balancer
resource "google_compute_backend_service" "web_backend_service" {
  name        = "global-web-backend"
  description = "Global backend service for web application with network intelligence"

  protocol                        = "HTTP"
  load_balancing_scheme          = "EXTERNAL_MANAGED"
  timeout_sec                    = 30
  enable_cdn                     = false
  connection_draining_timeout_sec = 60

  health_checks = [google_compute_health_check.web_health_check.id]

  # Add instance groups as backends
  dynamic "backend" {
    for_each = var.regions
    content {
      group           = google_compute_instance_group.web_instance_groups[backend.key].id
      balancing_mode  = "UTILIZATION"
      max_utilization = 0.8
      capacity_scaler = 1.0
    }
  }

  # Enable logging for Network Intelligence Center
  log_config {
    enable      = true
    sample_rate = 1.0
  }

  locality_lb_policy = "ROUND_ROBIN"
}

# URL map for HTTP(S) load balancer
resource "google_compute_url_map" "web_url_map" {
  name            = "global-web-map"
  description     = "URL map for global web application routing"
  default_service = google_compute_backend_service.web_backend_service.id
}

# Managed SSL certificate for HTTPS
resource "google_compute_managed_ssl_certificate" "web_ssl_cert" {
  name        = "global-web-ssl"
  description = "Managed SSL certificate for global web application"

  managed {
    domains = var.ssl_certificate_domains
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS target proxy
resource "google_compute_target_https_proxy" "web_https_proxy" {
  name             = "global-web-https-proxy"
  description      = "HTTPS target proxy for global load balancer"
  url_map          = google_compute_url_map.web_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.web_ssl_cert.id]
}

# HTTP target proxy (for redirects)
resource "google_compute_target_http_proxy" "web_http_proxy" {
  name        = "global-web-http-proxy"
  description = "HTTP target proxy for redirects to HTTPS"
  url_map     = google_compute_url_map.web_url_map.id
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "web_https_forwarding_rule" {
  name                  = "global-web-https-rule"
  description           = "Global forwarding rule for HTTPS traffic"
  target                = google_compute_target_https_proxy.web_https_proxy.id
  port_range           = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol          = "TCP"
}

# Global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "web_http_forwarding_rule" {
  name                  = "global-web-http-rule"
  description           = "Global forwarding rule for HTTP traffic"
  target                = google_compute_target_http_proxy.web_http_proxy.id
  port_range           = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_protocol          = "TCP"
}

# ============================================================================
# NETWORK INTELLIGENCE CENTER MONITORING
# ============================================================================

# Log sink for VPC Flow Logs to BigQuery (for advanced analytics)
resource "google_logging_project_sink" "vpc_flow_logs_sink" {
  count = var.enable_flow_logs ? 1 : 0

  name        = "vpc-flow-logs-sink"
  description = "Export VPC Flow Logs to BigQuery for Network Intelligence Center analytics"
  
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.network_analytics[0].dataset_id}"
  
  filter = "resource.type=\"gce_subnetwork\" AND log_name=\"projects/${var.project_id}/logs/compute.googleapis.com%2Fvpc_flows\""

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

# BigQuery dataset for network analytics
resource "google_bigquery_dataset" "network_analytics" {
  count = var.enable_flow_logs ? 1 : 0

  dataset_id    = "network_analytics_${replace(local.unique_suffix, "-", "_")}"
  friendly_name = "Network Analytics Dataset"
  description   = "Dataset for VPC Flow Logs and network performance analytics"
  location      = "US"

  default_table_expiration_ms = var.backup_retention_days * 24 * 60 * 60 * 1000

  labels = local.common_labels
}

# IAM binding for log sink to write to BigQuery
resource "google_bigquery_dataset_iam_member" "log_sink_writer" {
  count = var.enable_flow_logs ? 1 : 0

  dataset_id = google_bigquery_dataset.network_analytics[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.vpc_flow_logs_sink[0].writer_identity
}

# ============================================================================
# CLOUD MONITORING AND ALERTING
# ============================================================================

# Monitoring dashboard for network performance
resource "google_monitoring_dashboard" "network_performance_dashboard" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "Global Network Performance Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Load Balancer Request Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "VPC Flow Logs Volume"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_subnetwork\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
}

# Alert policy for high network latency
resource "google_monitoring_alert_policy" "high_latency_alert" {
  count = var.enable_monitoring && length(var.monitoring_notification_channels) > 0 ? 1 : 0

  display_name = "High Network Latency Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High Latency Condition"
    
    condition_threshold {
      filter         = "resource.type=\"gce_instance\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 1000  # 1000ms threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.monitoring_notification_channels

  documentation {
    content   = "Network latency has exceeded 1000ms. Check Network Intelligence Center for performance insights."
    mime_type = "text/markdown"
  }
}

# Alert policy for load balancer health
resource "google_monitoring_alert_policy" "lb_health_alert" {
  count = var.enable_monitoring && length(var.monitoring_notification_channels) > 0 ? 1 : 0

  display_name = "Load Balancer Backend Health Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Unhealthy Backend Condition"
    
    condition_threshold {
      filter         = "resource.type=\"gce_backend_service\""
      duration       = "180s"
      comparison     = "COMPARISON_LT"
      threshold_value = 0.8  # Less than 80% healthy backends

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.monitoring_notification_channels

  documentation {
    content   = "Load balancer backend health has degraded. Check instance health and network connectivity."
    mime_type = "text/markdown"
  }
}

# Create startup script for web servers
resource "local_file" "startup_script" {
  filename = "${path.module}/startup-script.sh"
  content  = <<-EOF
#!/bin/bash
# Startup script for web servers demonstrating global network performance

# Update system and install nginx
apt-get update
apt-get install -y nginx

# Create region-specific content
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>${upper(var.regions[each.key].name)} Region Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .header { color: #4285F4; }
        .region { color: #34A853; font-size: 24px; }
        .info { background-color: #f8f9fa; padding: 20px; border-radius: 8px; }
    </style>
</head>
<body>
    <h1 class="header">Global Network Performance Demo</h1>
    <h2 class="region">${upper(var.regions[each.key].name)} Region Server</h2>
    <div class="info">
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>Region:</strong> ${var.regions[each.key].name}</p>
        <p><strong>Zone:</strong> ${var.regions[each.key].zone}</p>
        <p><strong>Subnet CIDR:</strong> ${var.regions[each.key].subnet_cidr}</p>
        <p><strong>Timestamp:</strong> $(date)</p>
    </div>
    <p>This server demonstrates Google Cloud's global network performance optimization capabilities.</p>
</body>
</html>
HTML

# Start nginx service
systemctl start nginx
systemctl enable nginx

# Configure nginx for health checks
cat > /etc/nginx/conf.d/health.conf << 'NGINX'
server {
    listen 80 default_server;
    server_name _;
    
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    location / {
        root /var/www/html;
        index index.html;
    }
}
NGINX

# Restart nginx to apply configuration
systemctl restart nginx

# Install Google Cloud Ops Agent for enhanced monitoring
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

echo "Web server setup completed for ${var.regions[each.key].name} region"
EOF
}