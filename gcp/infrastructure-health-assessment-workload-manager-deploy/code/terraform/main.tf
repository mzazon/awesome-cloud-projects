# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and tagging
locals {
  name_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = "infrastructure-health-assessment"
    managed-by  = "terraform"
  })
  
  cluster_name        = "${var.name_prefix}-cluster-${local.name_suffix}"
  function_name       = "${var.name_prefix}-assessor-${local.name_suffix}"
  bucket_name         = "${var.project_id}-${var.name_prefix}-reports-${local.name_suffix}"
  pipeline_name       = "${var.name_prefix}-pipeline-${local.name_suffix}"
  
  # Cloud Function source code
  function_source = {
    "main.py" = file("${path.module}/function_code/main.py")
    "requirements.txt" = file("${path.module}/function_code/requirements.txt")
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Cloud Storage bucket for assessment reports
resource "google_storage_bucket" "assessment_reports" {
  name          = local.bucket_name
  location      = var.storage_bucket_location
  project       = var.project_id
  force_destroy = true
  
  # Enable versioning for audit trail
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for versioned objects
  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create VPC network for GKE cluster (if using private cluster)
resource "google_compute_network" "vpc" {
  count                   = var.enable_private_cluster ? 1 : 0
  name                    = "${var.name_prefix}-vpc-${local.name_suffix}"
  project                 = var.project_id
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.apis]
}

# Create subnet for GKE cluster (if using private cluster)
resource "google_compute_subnetwork" "subnet" {
  count         = var.enable_private_cluster ? 1 : 0
  name          = "${var.name_prefix}-subnet-${local.name_suffix}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc[0].id
  ip_cidr_range = "10.0.0.0/24"
  
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
  
  private_ip_google_access = true
}

# Create GKE cluster for infrastructure assessment target
resource "google_container_cluster" "assessment_cluster" {
  count = var.cluster_enable_autopilot ? 0 : 1
  
  name     = local.cluster_name
  project  = var.project_id
  location = var.zone
  
  # Remove default node pool
  remove_default_node_pool = true
  initial_node_count       = 1
  
  # Network configuration
  network    = var.enable_private_cluster ? google_compute_network.vpc[0].id : "default"
  subnetwork = var.enable_private_cluster ? google_compute_subnetwork.subnet[0].id : null
  
  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }
  
  # IP allocation policy for secondary ranges
  dynamic "ip_allocation_policy" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      cluster_secondary_range_name  = "pods"
      services_secondary_range_name = "services"
    }
  }
  
  # Enable monitoring and logging
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    managed_prometheus {
      enabled = true
    }
  }
  
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS", "API_SERVER"]
  }
  
  # Enable Workload Identity
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
  
  # Security and maintenance settings
  enable_shielded_nodes = true
  
  maintenance_policy {
    recurring_window {
      start_time = "2023-01-01T01:00:00Z"
      end_time   = "2023-01-01T04:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA"
    }
  }
  
  # Network policy
  network_policy {
    enabled = true
  }
  
  # Resource labels
  resource_labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_compute_subnetwork.subnet
  ]
}

# Create GKE Autopilot cluster alternative
resource "google_container_cluster" "autopilot_cluster" {
  count = var.cluster_enable_autopilot ? 1 : 0
  
  name     = local.cluster_name
  project  = var.project_id
  location = var.region
  
  # Enable Autopilot
  enable_autopilot = true
  
  # Network configuration
  network    = var.enable_private_cluster ? google_compute_network.vpc[0].id : "default"
  subnetwork = var.enable_private_cluster ? google_compute_subnetwork.subnet[0].id : null
  
  # Private cluster configuration
  dynamic "private_cluster_config" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      enable_private_nodes    = true
      enable_private_endpoint = false
      master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    }
  }
  
  # IP allocation policy for secondary ranges
  dynamic "ip_allocation_policy" {
    for_each = var.enable_private_cluster ? [1] : []
    content {
      cluster_secondary_range_name  = "pods"
      services_secondary_range_name = "services"
    }
  }
  
  # Resource labels
  resource_labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_compute_subnetwork.subnet
  ]
}

# Create GKE node pool (for standard cluster only)
resource "google_container_node_pool" "assessment_nodes" {
  count = var.cluster_enable_autopilot ? 0 : 1
  
  name       = "${local.cluster_name}-nodes"
  project    = var.project_id
  location   = var.zone
  cluster    = google_container_cluster.assessment_cluster[0].name
  node_count = var.cluster_node_count
  
  node_config {
    machine_type = var.cluster_machine_type
    disk_size_gb = var.cluster_disk_size_gb
    disk_type    = "pd-standard"
    
    # Security settings
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    
    # Workload Identity
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    
    # OAuth scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
    
    labels = local.common_labels
  }
  
  # Node management
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  
  # Autoscaling
  autoscaling {
    min_node_count = 1
    max_node_count = var.cluster_node_count * 2
  }
  
  depends_on = [google_container_cluster.assessment_cluster]
}

# Create Pub/Sub topic for health assessment events
resource "google_pubsub_topic" "health_assessment_events" {
  name    = "health-assessment-events-${local.name_suffix}"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create Pub/Sub subscription for deployment pipeline
resource "google_pubsub_subscription" "health_deployment_trigger" {
  name    = "health-deployment-trigger-${local.name_suffix}"
  project = var.project_id
  topic   = google_pubsub_topic.health_assessment_events.name
  
  # Configure message retention and acknowledgment
  message_retention_duration = "604800s" # 7 days
  ack_deadline_seconds      = 60
  
  # Enable dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.health_monitoring_alerts.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Create Pub/Sub topic for monitoring alerts
resource "google_pubsub_topic" "health_monitoring_alerts" {
  name    = "health-monitoring-alerts-${local.name_suffix}"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.name_prefix}-function-sa-${local.name_suffix}"
  project      = var.project_id
  display_name = "Infrastructure Health Assessment Function Service Account"
  description  = "Service account for processing health assessment results"
}

# Grant necessary permissions to function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/pubsub.publisher",
    "roles/storage.objectViewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create ZIP archive for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  dynamic "source" {
    for_each = local.function_source
    content {
      content  = source.value
      filename = source.key
    }
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.name_suffix}.zip"
  bucket = google_storage_bucket.assessment_reports.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Deploy Cloud Function for assessment processing
resource "google_cloudfunctions_function" "assessment_processor" {
  name        = local.function_name
  project     = var.project_id
  region      = var.region
  description = "Process Workload Manager assessment results and trigger remediation"
  
  runtime     = var.function_runtime
  entry_point = "process_health_assessment"
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.assessment_reports.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Trigger configuration
  event_trigger {
    event_type = "google.storage.object.finalize"
    resource   = google_storage_bucket.assessment_reports.name
  }
  
  # Runtime configuration
  available_memory_mb   = var.function_memory_mb
  timeout              = var.function_timeout_seconds
  service_account_email = google_service_account.function_sa.email
  
  # Environment variables
  environment_variables = {
    PROJECT_ID                = var.project_id
    HEALTH_EVENTS_TOPIC      = google_pubsub_topic.health_assessment_events.name
    MONITORING_ALERTS_TOPIC  = google_pubsub_topic.health_monitoring_alerts.name
    CRITICAL_THRESHOLD       = var.alert_threshold_critical_issues
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_permissions
  ]
}

# Create service account for Cloud Deploy
resource "google_service_account" "deploy_sa" {
  account_id   = "${var.name_prefix}-deploy-sa-${local.name_suffix}"
  project      = var.project_id
  display_name = "Infrastructure Health Deploy Service Account"
  description  = "Service account for Cloud Deploy pipeline operations"
}

# Grant necessary permissions to Cloud Deploy service account
resource "google_project_iam_member" "deploy_permissions" {
  for_each = toset([
    "roles/container.developer",
    "roles/clouddeploy.serviceAgent",
    "roles/storage.objectViewer",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deploy_sa.email}"
}

# Create Cloud Deploy delivery pipeline
resource "google_clouddeploy_delivery_pipeline" "health_pipeline" {
  provider = google-beta
  
  name        = local.pipeline_name
  project     = var.project_id
  location    = var.region
  description = "Infrastructure health remediation delivery pipeline"
  
  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.staging_target.name
      profiles  = ["staging"]
    }
    
    stages {
      target_id = google_clouddeploy_target.production_target.name
      profiles  = ["production"]
    }
  }
  
  annotations = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Deploy staging target
resource "google_clouddeploy_target" "staging_target" {
  provider = google-beta
  
  name        = "${var.name_prefix}-staging-${local.name_suffix}"
  project     = var.project_id
  location    = var.region
  description = "Staging environment for health remediation testing"
  
  gke {
    cluster = var.cluster_enable_autopilot ? google_container_cluster.autopilot_cluster[0].id : google_container_cluster.assessment_cluster[0].id
  }
  
  annotations = local.common_labels
  
  depends_on = [
    google_container_cluster.assessment_cluster,
    google_container_cluster.autopilot_cluster
  ]
}

# Create Cloud Deploy production target
resource "google_clouddeploy_target" "production_target" {
  provider = google-beta
  
  name        = "${var.name_prefix}-production-${local.name_suffix}"
  project     = var.project_id
  location    = var.region
  description = "Production environment for health remediation deployment"
  
  gke {
    cluster = var.cluster_enable_autopilot ? google_container_cluster.autopilot_cluster[0].id : google_container_cluster.assessment_cluster[0].id
  }
  
  require_approval = var.deploy_require_approval
  
  annotations = local.common_labels
  
  depends_on = [
    google_container_cluster.assessment_cluster,
    google_container_cluster.autopilot_cluster
  ]
}

# Create notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Infrastructure Health Email Notifications"
  project      = var.project_id
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.apis]
}

# Create monitoring alert policy for critical health issues
resource "google_monitoring_alert_policy" "critical_health_issues" {
  display_name = "Infrastructure Health Critical Issues"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Critical assessment findings"
    
    condition_threshold {
      filter         = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${google_pubsub_topic.health_assessment_events.name}\""
      duration       = "60s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Add notification channel if email provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [
    google_project_service.apis,
    google_monitoring_notification_channel.email
  ]
}

# Create custom metric for deployment success tracking
resource "google_logging_metric" "deployment_success" {
  name   = "deployment_success_${local.name_suffix}"
  project = var.project_id
  filter = "resource.type=\"cloud_function\" AND \"deployment successful\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Successful Health Remediation Deployments"
  }
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Storage bucket for remediation templates
resource "google_storage_bucket" "remediation_templates" {
  name          = "${var.project_id}-${var.name_prefix}-templates-${local.name_suffix}"
  location      = var.storage_bucket_location
  project       = var.project_id
  force_destroy = true
  
  uniform_bucket_level_access = true
  labels                     = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Upload security remediation template
resource "google_storage_bucket_object" "security_template" {
  name    = "security-fixes.yaml"
  bucket  = google_storage_bucket.remediation_templates.name
  content = file("${path.module}/remediation_templates/security-fixes.yaml")
}

# Upload performance optimization template
resource "google_storage_bucket_object" "performance_template" {
  name    = "performance-fixes.yaml"
  bucket  = google_storage_bucket.remediation_templates.name
  content = file("${path.module}/remediation_templates/performance-fixes.yaml")
}

# Create Cloud Scheduler job for periodic assessments
resource "google_cloud_scheduler_job" "assessment_trigger" {
  name        = "${var.name_prefix}-assessment-trigger-${local.name_suffix}"
  project     = var.project_id
  region      = var.region
  description = "Trigger infrastructure health assessments"
  schedule    = var.assessment_schedule
  time_zone   = "UTC"
  
  pubsub_target {
    topic_name = google_pubsub_topic.health_assessment_events.id
    data       = base64encode(jsonencode({
      trigger_type = "scheduled"
      assessment_rules = {
        security    = var.enable_security_assessment
        performance = var.enable_performance_assessment
        cost        = var.enable_cost_assessment
      }
    }))
  }
  
  depends_on = [google_project_service.apis]
}