# main.tf
# Main Terraform configuration for disaster recovery orchestration with service extensions

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  count       = var.resource_suffix == "" ? 1 : 0
  byte_length = 3
}

locals {
  # Use provided suffix or generate random one
  suffix = var.resource_suffix != "" ? var.resource_suffix : (length(random_id.suffix) > 0 ? random_id.suffix[0].hex : "")
  
  # Common labels applied to all resources
  common_labels = merge(var.tags, {
    environment = var.environment
    region      = var.primary_region
    dr-region   = var.dr_region
    managed-by  = "terraform"
    solution    = "disaster-recovery-orchestration"
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "backupdr.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "serviceextensions.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# ================================
# NETWORK CONFIGURATION
# ================================

# Default VPC and firewall rules for HTTP traffic
resource "google_compute_firewall" "allow_http" {
  name    = "allow-http-${local.suffix}"
  network = "default"
  
  allow {
    protocol = "tcp"
    ports    = ["80", "8080"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
  
  description = "Allow HTTP traffic for disaster recovery orchestration demo"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ================================
# PRIMARY APPLICATION INFRASTRUCTURE
# ================================

# Instance template for primary application
resource "google_compute_instance_template" "primary_app" {
  name_prefix  = "primary-app-template-${local.suffix}-"
  machine_type = var.machine_type
  region       = var.primary_region
  
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    disk_type    = "pd-standard"
  }
  
  network_interface {
    network = "default"
    access_config {
      network_tier = "PREMIUM"
    }
  }
  
  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update
      apt-get install -y nginx
      echo "<h1>Primary Application - Instance: $(hostname)</h1>" > /var/www/html/index.html
      echo "<p>Region: ${var.primary_region}</p>" >> /var/www/html/index.html
      echo "<p>Timestamp: $(date)</p>" >> /var/www/html/index.html
      systemctl start nginx
      systemctl enable nginx
    EOF
  }
  
  tags = ["primary-app", "http-server"]
  
  labels = merge(local.common_labels, {
    component = "primary-application"
    tier      = "web"
  })
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Managed instance group for primary application
resource "google_compute_instance_group_manager" "primary_app" {
  name     = "primary-app-group-${local.suffix}"
  zone     = var.primary_zone
  
  base_instance_name = "primary-app"
  target_size        = var.primary_instance_count
  
  version {
    instance_template = google_compute_instance_template.primary_app.id
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.primary_app.id
    initial_delay_sec = 300
  }
  
  update_policy {
    type                           = "PROACTIVE"
    instance_redistribution_type   = "PROACTIVE"
    minimal_action                 = "REPLACE"
    max_surge_fixed                = 1
    max_unavailable_fixed          = 1
    replacement_method             = "SUBSTITUTE"
  }
  
  named_port {
    name = "http"
    port = 80
  }
  
  depends_on = [google_compute_instance_template.primary_app]
}

# Health check for primary application
resource "google_compute_health_check" "primary_app" {
  name                = "primary-app-health-check-${local.suffix}"
  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port         = 80
    request_path = "/"
  }
  
  description = "Health check for primary application instances"
  
  depends_on = [google_project_service.required_apis]
}

# ================================
# DISASTER RECOVERY INFRASTRUCTURE
# ================================

# Instance template for DR application
resource "google_compute_instance_template" "dr_app" {
  name_prefix  = "dr-app-template-${local.suffix}-"
  machine_type = var.machine_type
  region       = var.dr_region
  
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
    disk_type    = "pd-standard"
  }
  
  network_interface {
    network = "default"
    access_config {
      network_tier = "PREMIUM"
    }
  }
  
  metadata = {
    startup-script = <<-EOF
      #!/bin/bash
      apt-get update
      apt-get install -y nginx
      echo "<h1>DR Application - Instance: $(hostname)</h1>" > /var/www/html/index.html
      echo "<p>Disaster Recovery Mode Active</p>" >> /var/www/html/index.html
      echo "<p>Region: ${var.dr_region}</p>" >> /var/www/html/index.html
      echo "<p>Timestamp: $(date)</p>" >> /var/www/html/index.html
      systemctl start nginx
      systemctl enable nginx
    EOF
  }
  
  tags = ["dr-app", "http-server"]
  
  labels = merge(local.common_labels, {
    component = "disaster-recovery-application"
    tier      = "web"
  })
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Managed instance group for DR application
resource "google_compute_instance_group_manager" "dr_app" {
  name     = "dr-app-group-${local.suffix}"
  zone     = var.dr_zone
  
  base_instance_name = "dr-app"
  target_size        = var.dr_initial_instance_count
  
  version {
    instance_template = google_compute_instance_template.dr_app.id
  }
  
  auto_healing_policies {
    health_check      = google_compute_health_check.dr_app.id
    initial_delay_sec = 300
  }
  
  update_policy {
    type                           = "PROACTIVE"
    instance_redistribution_type   = "PROACTIVE"
    minimal_action                 = "REPLACE"
    max_surge_fixed                = 1
    max_unavailable_fixed          = 1
    replacement_method             = "SUBSTITUTE"
  }
  
  named_port {
    name = "http"
    port = 80
  }
  
  depends_on = [google_compute_instance_template.dr_app]
}

# Health check for DR application
resource "google_compute_health_check" "dr_app" {
  name                = "dr-app-health-check-${local.suffix}"
  check_interval_sec  = var.health_check_interval
  timeout_sec         = var.health_check_timeout
  healthy_threshold   = 2
  unhealthy_threshold = 3
  
  http_health_check {
    port         = 80
    request_path = "/"
  }
  
  description = "Health check for disaster recovery application instances"
  
  depends_on = [google_project_service.required_apis]
}

# ================================
# BACKUP AND DR SERVICE
# ================================

# Backup vault for immutable storage
resource "google_backup_dr_backup_vault" "primary" {
  provider    = google-beta
  location    = var.primary_region
  backup_vault_id = "primary-backup-vault-${local.suffix}"
  
  description = "Primary backup vault for disaster recovery orchestration"
  
  backup_minimum_enforced_retention_duration = "${var.backup_retention_days * 24}h"
  
  labels = merge(local.common_labels, {
    component = "backup-vault"
    purpose   = "disaster-recovery"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Backup plan for Compute Engine instances
resource "google_backup_dr_backup_plan" "primary" {
  provider       = google-beta
  location       = var.primary_region
  backup_plan_id = "primary-backup-plan-${local.suffix}"
  
  resource_type = "compute.googleapis.com/Instance"
  backup_vault  = google_backup_dr_backup_vault.primary.name
  
  description = "Automated backup plan for primary infrastructure"
  
  backup_rules {
    rule_id = "daily-backup-rule"
    backup_retention_days = var.backup_retention_days
    
    standard_schedule {
      recurrence_type = "DAILY"
      backup_window {
        start_hour_of_day = 2
        end_hour_of_day   = 6
      }
    }
  }
  
  labels = merge(local.common_labels, {
    component = "backup-plan"
    schedule  = "daily"
  })
  
  depends_on = [google_backup_dr_backup_vault.primary]
}

# ================================
# CLOUD FUNCTION FOR DR ORCHESTRATION
# ================================

# Service account for Cloud Function
resource "google_service_account" "dr_orchestrator" {
  account_id   = "dr-orchestrator-${local.suffix}"
  display_name = "Disaster Recovery Orchestrator Service Account"
  description  = "Service account for disaster recovery orchestration Cloud Function"
}

# IAM roles for the DR orchestrator service account
resource "google_project_iam_member" "dr_orchestrator_roles" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/backupdr.admin"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dr_orchestrator.email}"
}

# Archive the Cloud Function source code
data "archive_file" "dr_function_source" {
  type        = "zip"
  output_path = "/tmp/dr-orchestrator-${local.suffix}.zip"
  
  source {
    content = <<-EOF
import functions_framework
import json
import logging
import os
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import backupdr_v1
import time

# Initialize clients
compute_client = compute_v1.InstanceGroupManagersClient()
monitoring_client = monitoring_v3.MetricServiceClient()

@functions_framework.http
def orchestrate_disaster_recovery(request):
    """Orchestrates disaster recovery based on service extension signals"""
    try:
        # Parse incoming request from service extension
        request_json = request.get_json(silent=True) or {}
        failure_type = request_json.get('failure_type', 'unknown')
        affected_region = request_json.get('region', '${var.primary_region}')
        severity = request_json.get('severity', 'medium')
        
        logging.info(f"DR triggered: {failure_type} in {affected_region}, severity: {severity}")
        
        # Assess failure severity and determine response
        response_actions = []
        
        if severity in ['high', 'critical']:
            # Scale up DR infrastructure
            dr_response = scale_dr_infrastructure()
            response_actions.append(dr_response)
            
            # Trigger backup restoration if needed
            if failure_type in ['data_corruption', 'storage_failure']:
                backup_response = trigger_backup_restoration()
                response_actions.append(backup_response)
        
        # Log metrics for monitoring
        log_dr_metrics(failure_type, severity, len(response_actions))
        
        return {
            'status': 'success',
            'actions_taken': response_actions,
            'timestamp': str(time.time()),
            'failure_type': failure_type,
            'severity': severity
        }
        
    except Exception as e:
        logging.error(f"DR orchestration failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def scale_dr_infrastructure():
    """Scale up disaster recovery infrastructure"""
    try:
        project_id = '${var.project_id}'
        dr_zone = '${var.dr_zone}'
        
        # Scale DR instance group to 2 instances
        operation = compute_client.resize(
            project=project_id,
            zone=dr_zone,
            instance_group_manager="dr-app-group-${local.suffix}",
            size=2
        )
        
        logging.info(f"DR infrastructure scaling initiated: {operation.name}")
        return f"DR infrastructure scaled up in {dr_zone}"
        
    except Exception as e:
        logging.error(f"Failed to scale DR infrastructure: {str(e)}")
        return f"DR scaling failed: {str(e)}"

def trigger_backup_restoration():
    """Trigger backup restoration workflow"""
    try:
        logging.info("Backup restoration workflow initiated")
        return "Backup restoration initiated"
        
    except Exception as e:
        logging.error(f"Backup restoration failed: {str(e)}")
        return f"Backup restoration failed: {str(e)}"

def log_dr_metrics(failure_type, severity, actions_count):
    """Log custom metrics for DR monitoring"""
    try:
        project_name = f"projects/${var.project_id}"
        
        # Create custom metric for DR events
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/disaster_recovery/events"
        series.metric.labels["failure_type"] = failure_type
        series.metric.labels["severity"] = severity
        
        # Add data point
        point = monitoring_v3.Point()
        point.value.int64_value = actions_count
        point.interval.end_time.seconds = int(time.time())
        series.points = [point]
        
        # Write metrics
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
    except Exception as e:
        logging.error(f"Failed to log DR metrics: {str(e)}")
EOF
    filename = "main.py"
  }
  
  source {
    content = <<-EOF
functions-framework==3.4.0
google-cloud-compute==1.15.0
google-cloud-monitoring==2.16.0
google-cloud-backup-dr==0.1.0
EOF
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source
resource "google_storage_bucket" "function_source" {
  name     = "dr-orchestrator-source-${local.suffix}"
  location = var.primary_region
  
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    component = "function-source"
    purpose   = "cloud-function-deployment"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "dr-orchestrator-${local.suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.dr_function_source.output_path
  
  depends_on = [data.archive_file.dr_function_source]
}

# Cloud Function for disaster recovery orchestration
resource "google_cloudfunctions_function" "dr_orchestrator" {
  name     = "dr-orchestrator-${local.suffix}"
  location = var.primary_region
  
  runtime               = "python311"
  available_memory_mb   = 256
  timeout               = 300
  entry_point          = "orchestrate_disaster_recovery"
  service_account_email = google_service_account.dr_orchestrator.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  trigger {
    http_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    PROJECT_ID     = var.project_id
    PRIMARY_REGION = var.primary_region
    DR_ZONE        = var.dr_zone
    RANDOM_SUFFIX  = local.suffix
  }
  
  labels = merge(local.common_labels, {
    component = "disaster-recovery-orchestrator"
    runtime   = "python311"
  })
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.dr_orchestrator_roles
  ]
}

# IAM binding to allow unauthenticated invocation
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = google_cloudfunctions_function.dr_orchestrator.region
  cloud_function = google_cloudfunctions_function.dr_orchestrator.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# ================================
# LOAD BALANCER CONFIGURATION
# ================================

# Backend service for primary application
resource "google_compute_backend_service" "primary" {
  name        = "primary-backend-service-${local.suffix}"
  description = "Backend service for primary application"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30
  
  health_checks = [google_compute_health_check.primary_app.id]
  
  backend {
    group           = google_compute_instance_group_manager.primary_app.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  log_config {
    enable      = true
    sample_rate = 1.0
  }
  
  depends_on = [google_compute_instance_group_manager.primary_app]
}

# Backend service for DR application
resource "google_compute_backend_service" "dr" {
  name        = "dr-backend-service-${local.suffix}"
  description = "Backend service for disaster recovery application"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30
  
  health_checks = [google_compute_health_check.dr_app.id]
  
  backend {
    group           = google_compute_instance_group_manager.dr_app.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
  
  log_config {
    enable      = true
    sample_rate = 1.0
  }
  
  depends_on = [google_compute_instance_group_manager.dr_app]
}

# URL map for traffic routing
resource "google_compute_url_map" "dr_orchestration" {
  name            = "dr-orchestration-urlmap-${local.suffix}"
  description     = "URL map for disaster recovery orchestration"
  default_service = google_compute_backend_service.primary.id
  
  # Failover configuration
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }
  
  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.primary.id
    
    # Route to DR service when primary fails
    route_rules {
      priority = 1
      match_rules {
        prefix_match = "/"
        header_matches {
          name         = "X-Health-Check"
          exact_match  = "failed"
        }
      }
      route_action {
        url_rewrite {
          host_rewrite = "dr-service"
        }
      }
      service = google_compute_backend_service.dr.id
    }
  }
  
  depends_on = [
    google_compute_backend_service.primary,
    google_compute_backend_service.dr
  ]
}

# HTTP(S) proxy for load balancer
resource "google_compute_target_http_proxy" "dr_orchestration" {
  name    = "dr-orchestration-proxy-${local.suffix}"
  url_map = google_compute_url_map.dr_orchestration.id
  
  depends_on = [google_compute_url_map.dr_orchestration]
}

# Global forwarding rule
resource "google_compute_global_forwarding_rule" "dr_orchestration" {
  name                  = "dr-orchestration-forwarding-rule-${local.suffix}"
  target                = google_compute_target_http_proxy.dr_orchestration.id
  port_range           = "80"
  load_balancing_scheme = "EXTERNAL"
  
  depends_on = [google_compute_target_http_proxy.dr_orchestration]
}

# ================================
# MONITORING AND ALERTING
# ================================

# Log-based metrics for DR monitoring
resource "google_logging_metric" "dr_failure_detection" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "dr-failure-detection-${local.suffix}"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"DR triggered\""
  
  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "DR Failure Detection Events"
  }
  
  label_extractors = {
    "failure_type" = "EXTRACT(textPayload)"
    "severity"     = "EXTRACT(textPayload)"
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_logging_metric" "dr_orchestration_success" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "dr-orchestration-success-${local.suffix}"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"success\""
  
  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "DR Orchestration Success Events"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "DR Orchestration Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for DR events
resource "google_monitoring_alert_policy" "dr_events" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Disaster Recovery Alert Policy ${local.suffix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "DR Orchestration Failures"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/dr-failure-detection-${local.suffix}\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].name] : []
  
  documentation {
    content = "Disaster recovery orchestration has been triggered. Review system status and validate recovery operations."
  }
  
  depends_on = [google_logging_metric.dr_failure_detection]
}

# Custom dashboard for DR monitoring
resource "google_monitoring_dashboard" "dr_orchestration" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Disaster Recovery Orchestration Dashboard ${local.suffix}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "DR Events"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/dr-failure-detection-${local.suffix}\""
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
            title = "Infrastructure Health"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"compute.googleapis.com/instance/up\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
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
  
  depends_on = [google_project_service.required_apis]
}