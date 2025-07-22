# Network Security Monitoring with VPC Flow Logs and Security Command Center
# This Terraform configuration deploys a comprehensive network security monitoring solution
# using VPC Flow Logs, Cloud Logging, and Cloud Security Command Center

# Data source to get current project information
data "google_project" "current" {}

# Data source to get current client configuration (for project_id)
data "google_client_config" "current" {}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for resource naming and configuration
locals {
  project_id      = data.google_project.current.project_id
  random_suffix   = random_id.suffix.hex
  vpc_name        = "${var.vpc_name}-${local.random_suffix}"
  subnet_name     = "${var.subnet_name}-${local.random_suffix}"
  instance_name   = "${var.instance_name}-${local.random_suffix}"
  log_sink_name   = "${var.log_sink_name}-${local.random_suffix}"
  
  # Network configuration
  subnet_cidr = var.subnet_cidr
  
  # Common tags/labels for all resources
  common_labels = {
    environment = var.environment
    purpose     = "network-security-monitoring"
    managed_by  = "terraform"
    recipe      = "vpc-flow-logs-security-monitoring"
  }
}

# Enable required APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "securitycenter.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com"
  ])
  
  project = local.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create custom VPC network for security monitoring
resource "google_compute_network" "security_monitoring_vpc" {
  name                    = local.vpc_name
  description             = "VPC network for network security monitoring demonstration"
  auto_create_subnetworks = false
  routing_mode           = "REGIONAL"
  
  depends_on = [google_project_service.required_apis]
  
  labels = local.common_labels
}

# Create subnet with VPC Flow Logs enabled for comprehensive monitoring
resource "google_compute_subnetwork" "monitored_subnet" {
  name          = local.subnet_name
  region        = var.region
  network       = google_compute_network.security_monitoring_vpc.id
  ip_cidr_range = local.subnet_cidr
  description   = "Subnet with VPC Flow Logs enabled for security monitoring"
  
  # Enable VPC Flow Logs with comprehensive settings
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1.0
    metadata             = "INCLUDE_ALL_METADATA"
    metadata_fields = [
      "CUSTOM_METADATA",
      "DNS_METADATA",
      "ROUTE_METADATA"
    ]
    filter_expr = "true"  # Capture all traffic
  }
  
  # Enable private Google access for instances
  private_ip_google_access = true
  
  depends_on = [google_compute_network.security_monitoring_vpc]
}

# Firewall rule: Allow SSH access for instance management
resource "google_compute_firewall" "allow_ssh" {
  name          = "allow-ssh-${local.random_suffix}"
  network       = google_compute_network.security_monitoring_vpc.id
  description   = "Allow SSH access for security monitoring test instances"
  direction     = "INGRESS"
  priority      = 1000
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.allowed_ssh_sources
  target_tags   = ["security-test"]
  
  depends_on = [google_compute_network.security_monitoring_vpc]
}

# Firewall rule: Allow HTTP/HTTPS traffic for web service testing
resource "google_compute_firewall" "allow_http" {
  name          = "allow-http-${local.random_suffix}"
  network       = google_compute_network.security_monitoring_vpc.id
  description   = "Allow HTTP/HTTPS traffic for web service monitoring"
  direction     = "INGRESS"
  priority      = 1000
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]
  
  depends_on = [google_compute_network.security_monitoring_vpc]
}

# Firewall rule: Allow internal traffic for comprehensive monitoring
resource "google_compute_firewall" "allow_internal" {
  name          = "allow-internal-${local.random_suffix}"
  network       = google_compute_network.security_monitoring_vpc.id
  description   = "Allow internal subnet communication for monitoring"
  direction     = "INGRESS"
  priority      = 1000
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [local.subnet_cidr]
  target_tags   = ["security-test"]
  
  depends_on = [google_compute_network.security_monitoring_vpc]
}

# Service account for the test VM instance
resource "google_service_account" "test_vm_sa" {
  account_id   = "test-vm-sa-${local.random_suffix}"
  display_name = "Test VM Service Account for Security Monitoring"
  description  = "Service account for test VM instances in security monitoring demo"
}

# IAM binding for the service account to have logging write permissions
resource "google_project_iam_member" "test_vm_logging" {
  project = local.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.test_vm_sa.email}"
}

# IAM binding for the service account to have monitoring metric writer permissions
resource "google_project_iam_member" "test_vm_monitoring" {
  project = local.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.test_vm_sa.email}"
}

# Test VM instance for traffic generation and monitoring
resource "google_compute_instance" "test_vm" {
  name         = local.instance_name
  zone         = var.zone
  machine_type = var.machine_type
  description  = "Test VM instance for network security monitoring demonstration"
  
  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
      size  = 10
      type  = "pd-standard"
    }
  }
  
  network_interface {
    subnetwork = google_compute_subnetwork.monitored_subnet.id
    
    # Assign external IP for testing
    access_config {
      network_tier = "PREMIUM"
    }
  }
  
  service_account {
    email  = google_service_account.test_vm_sa.email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  
  tags = ["security-test", "web-server"]
  
  labels = merge(local.common_labels, {
    instance_type = "test-vm"
  })
  
  # Startup script to install Apache and basic monitoring tools
  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    project_id = local.project_id
  })
  
  depends_on = [
    google_compute_subnetwork.monitored_subnet,
    google_service_account.test_vm_sa,
    google_project_iam_member.test_vm_logging,
    google_project_iam_member.test_vm_monitoring
  ]
}

# BigQuery dataset for VPC Flow Logs storage and analysis
resource "google_bigquery_dataset" "security_monitoring" {
  dataset_id    = "security_monitoring_${local.random_suffix}"
  friendly_name = "Security Monitoring Dataset"
  description   = "Dataset for VPC Flow Logs security analysis and monitoring"
  location      = var.bigquery_location
  
  default_table_expiration_ms = var.log_retention_days * 24 * 60 * 60 * 1000  # Convert days to milliseconds
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Service account for the logging sink
resource "google_service_account" "logging_sink_sa" {
  account_id   = "logging-sink-sa-${local.random_suffix}"
  display_name = "Logging Sink Service Account"
  description  = "Service account for VPC Flow Logs sink to BigQuery"
}

# IAM binding for the logging sink service account
resource "google_project_iam_member" "logging_sink_bigquery" {
  project = local.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.logging_sink_sa.email}"
}

# Logging sink to route VPC Flow Logs to BigQuery
resource "google_logging_project_sink" "vpc_flow_logs_sink" {
  name        = local.log_sink_name
  description = "Sink for VPC Flow Logs to BigQuery for security monitoring"
  
  # Route VPC Flow Logs to BigQuery dataset
  destination = "bigquery.googleapis.com/projects/${local.project_id}/datasets/${google_bigquery_dataset.security_monitoring.dataset_id}"
  
  # Filter for VPC Flow Logs
  filter = <<-EOT
    resource.type="gce_subnetwork" AND
    logName="projects/${local.project_id}/logs/compute.googleapis.com%2Fvpc_flows"
  EOT
  
  # Use dedicated service account
  writer_identity = google_service_account.logging_sink_sa.email
  
  # Create BigQuery table automatically
  bigquery_options {
    use_partitioned_tables = true
  }
  
  depends_on = [
    google_bigquery_dataset.security_monitoring,
    google_service_account.logging_sink_sa,
    google_project_iam_member.logging_sink_bigquery
  ]
}

# Pub/Sub topic for Security Command Center notifications
resource "google_pubsub_topic" "security_findings" {
  name = "security-findings-${local.random_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Notification channel for Cloud Monitoring alerts (email)
resource "google_monitoring_notification_channel" "email_notification" {
  count = length(var.notification_emails) > 0 ? 1 : 0
  
  display_name = "Email Notification Channel"
  description  = "Email notification channel for security monitoring alerts"
  type         = "email"
  
  labels = {
    email_address = var.notification_emails[0]  # Use first email if provided
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for high network traffic volume
resource "google_monitoring_alert_policy" "high_traffic_alert" {
  display_name = "High Network Traffic Volume Alert"
  combiner     = "OR"
  enabled      = var.enable_monitoring_alerts
  
  documentation {
    content   = "Alert triggered when network traffic exceeds normal thresholds. This may indicate a DDoS attack, data exfiltration, or other suspicious network activity."
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High egress traffic condition"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.high_traffic_threshold_bytes
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  notification_channels = var.notification_emails != [] ? [google_monitoring_notification_channel.email_notification[0].id] : []
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for suspicious connection patterns
resource "google_monitoring_alert_policy" "suspicious_connections_alert" {
  display_name = "Suspicious Connection Patterns Alert"
  combiner     = "OR"
  enabled      = var.enable_monitoring_alerts
  
  documentation {
    content   = "Alert for unusual connection patterns that may indicate security threats such as port scanning, brute force attacks, or lateral movement."
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High connection rate condition"
    
    condition_threshold {
      filter          = "resource.type=\"gce_subnetwork\""
      duration        = "180s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.suspicious_connections_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_COUNT"
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  notification_channels = var.notification_emails != [] ? [google_monitoring_notification_channel.email_notification[0].id] : []
  
  alert_strategy {
    auto_close = "43200s"  # 12 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring dashboard for network security monitoring
resource "google_monitoring_dashboard" "network_security_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Network Security Monitoring Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "VPC Flow Logs Volume"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_subnetwork\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Logs per second"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Network Traffic Volume"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/network/sent_bytes_count\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Bytes per second"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}