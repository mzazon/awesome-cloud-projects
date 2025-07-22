# GCP Infrastructure Cost Optimization with Cloud Batch and Cloud Monitoring
#
# This Terraform configuration deploys a comprehensive cost optimization solution that
# combines Cloud Batch for scalable infrastructure analysis, Cloud Monitoring for
# real-time alerting, Cloud Functions for automated remediation, and BigQuery for
# analytics and reporting.

# ==============================================================================
# LOCAL VALUES AND RESOURCE NAMING
# ==============================================================================

locals {
  # Generate consistent naming across all resources
  name_prefix = "${var.environment}-${var.application_name}"
  
  # Create unique suffix for globally unique resources (if not provided)
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common labels applied to all resources for consistent governance
  common_labels = merge(
    {
      environment     = var.environment
      application     = var.application_name
      managed_by      = "terraform"
      cost_center     = var.cost_center
      owner           = var.owner
      created_date    = formatdate("YYYY-MM-DD", timestamp())
      recipe_id       = "f3a2b8c7"
      solution_type   = "cost-optimization"
    },
    var.additional_labels
  )
  
  # Resource names following Google Cloud naming conventions
  resource_names = {
    storage_bucket         = "${local.name_prefix}-data-${local.resource_suffix}"
    bigquery_dataset      = replace("${local.name_prefix}_analytics_${local.resource_suffix}", "-", "_")
    function_name         = "${local.name_prefix}-optimizer-${local.resource_suffix}"
    service_account       = "${local.name_prefix}-sa-${local.resource_suffix}"
    pubsub_topic_events   = "${local.name_prefix}-cost-events"
    pubsub_topic_batch    = "${local.name_prefix}-batch-notifications"
    scheduler_daily       = "${local.name_prefix}-daily-optimization"
    scheduler_weekly      = "${local.name_prefix}-weekly-analysis"
    batch_job_template    = "${local.name_prefix}-analysis-template"
  }
  
  # BigQuery location defaults to region if not specified
  bigquery_location = var.bigquery_location != "" ? var.bigquery_location : var.region
}

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# ==============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ==============================================================================

# Enable all APIs required for the cost optimization solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "batch.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent destruction during terraform destroy
  disable_on_destroy = false
}

# ==============================================================================
# IAM SERVICE ACCOUNT AND PERMISSIONS
# ==============================================================================

# Service account for cost optimization workloads with least privilege permissions
resource "google_service_account" "cost_optimizer" {
  account_id   = local.resource_names.service_account
  display_name = "Cost Optimization Service Account"
  description  = "Service account for automated infrastructure cost optimization tasks"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account with granular permissions
resource "google_project_iam_member" "cost_optimizer_permissions" {
  for_each = toset([
    "roles/compute.viewer",              # View compute instances for analysis
    "roles/monitoring.viewer",           # Read monitoring metrics
    "roles/bigquery.dataEditor",         # Write to BigQuery tables
    "roles/storage.objectAdmin",         # Manage storage bucket contents
    "roles/pubsub.publisher",           # Publish to Pub/Sub topics
    "roles/batch.jobsEditor",           # Create and manage batch jobs
    "roles/logging.logWriter",          # Write logs for debugging
    "roles/compute.instanceAdmin",      # Manage instances for optimization (limited scope)
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cost_optimizer.email}"
  
  depends_on = [google_service_account.cost_optimizer]
}

# ==============================================================================
# CLOUD STORAGE FOR ANALYTICS DATA
# ==============================================================================

# Primary storage bucket for cost optimization data with intelligent lifecycle policies
resource "google_storage_bucket" "cost_optimization_data" {
  name          = local.resource_names.storage_bucket
  location      = var.region
  storage_class = var.storage_class
  project       = var.project_id
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Intelligent lifecycle management for cost optimization
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 30
    }
  }
  
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age = 90
    }
  }
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = var.data_retention_days
    }
  }
  
  # Security configuration
  uniform_bucket_level_access = true
  
  # Enable audit logging if requested
  dynamic "logging" {
    for_each = var.enable_audit_logging ? [1] : []
    content {
      log_bucket = google_storage_bucket.cost_optimization_data.name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for service account access to storage bucket
resource "google_storage_bucket_iam_member" "cost_optimizer_storage_access" {
  bucket = google_storage_bucket.cost_optimization_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cost_optimizer.email}"
  
  depends_on = [google_storage_bucket.cost_optimization_data]
}

# ==============================================================================
# BIGQUERY ANALYTICS DATASET AND TABLES
# ==============================================================================

# BigQuery dataset for cost optimization analytics with appropriate security
resource "google_bigquery_dataset" "cost_analytics" {
  dataset_id                 = local.resource_names.bigquery_dataset
  friendly_name             = "Cost Optimization Analytics"
  description               = "Analytics dataset for infrastructure cost optimization metrics and recommendations"
  location                  = local.bigquery_location
  project                   = var.project_id
  
  # Default table expiration for automatic cleanup
  default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000
  
  # Access controls
  access {
    role          = "OWNER"
    user_by_email = google_service_account.cost_optimizer.email
  }
  
  # Additional access for specified members
  dynamic "access" {
    for_each = var.allowed_members
    content {
      role          = "READER"
      user_by_email = access.value
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Table for storing resource utilization metrics
resource "google_bigquery_table" "resource_utilization" {
  dataset_id = google_bigquery_dataset.cost_analytics.dataset_id
  table_id   = "resource_utilization"
  project    = var.project_id
  
  description = "Real-time resource utilization metrics for cost optimization analysis"
  
  # Table schema optimized for analytics queries
  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the metric was recorded"
    },
    {
      name        = "resource_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Unique identifier for the resource"
    },
    {
      name        = "resource_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of resource (e.g., compute_instance, gke_cluster)"
    },
    {
      name        = "project_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Google Cloud project containing the resource"
    },
    {
      name        = "zone"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Zone where the resource is located"
    },
    {
      name        = "cpu_utilization"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "CPU utilization percentage (0.0-1.0)"
    },
    {
      name        = "memory_utilization"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Memory utilization percentage (0.0-1.0)"
    },
    {
      name        = "cost_per_hour"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Estimated cost per hour in USD"
    },
    {
      name        = "recommendation"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Optimization recommendation (resize, stop, migrate)"
    },
    {
      name        = "machine_type"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Current machine type or size"
    },
    {
      name        = "labels"
      type        = "JSON"
      mode        = "NULLABLE"
      description = "Resource labels for categorization"
    }
  ])
  
  # Partitioning for performance optimization
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  # Clustering for improved query performance
  clustering = ["resource_type", "project_id"]
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.cost_analytics]
}

# Table for tracking optimization actions and their results
resource "google_bigquery_table" "optimization_actions" {
  dataset_id = google_bigquery_dataset.cost_analytics.dataset_id
  table_id   = "optimization_actions"
  project    = var.project_id
  
  description = "Historical record of cost optimization actions and their effectiveness"
  
  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "When the optimization action was taken"
    },
    {
      name        = "resource_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Resource that was optimized"
    },
    {
      name        = "action_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of optimization action (resize, stop, migrate, label)"
    },
    {
      name        = "previous_state"
      type        = "JSON"
      mode        = "NULLABLE"
      description = "Resource configuration before optimization"
    },
    {
      name        = "new_state"
      type        = "JSON"
      mode        = "NULLABLE"
      description = "Resource configuration after optimization"
    },
    {
      name        = "estimated_savings"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Estimated monthly savings in USD"
    },
    {
      name        = "actual_savings"
      type        = "FLOAT"
      mode        = "NULLABLE"
      description = "Actual measured savings in USD (populated later)"
    },
    {
      name        = "status"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Action status (pending, completed, failed, rolled_back)"
    },
    {
      name        = "initiated_by"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Who or what initiated the optimization"
    },
    {
      name        = "failure_reason"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Reason for failure if action was unsuccessful"
    }
  ])
  
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  clustering = ["action_type", "status"]
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.cost_analytics]
}

# ==============================================================================
# PUB/SUB MESSAGING FOR EVENT-DRIVEN OPTIMIZATION
# ==============================================================================

# Topic for cost optimization events and alerts
resource "google_pubsub_topic" "cost_optimization_events" {
  name    = local.resource_names.pubsub_topic_events
  project = var.project_id
  
  # Message retention for reliable processing
  message_retention_duration = "604800s"  # 7 days
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Subscription for processing optimization events
resource "google_pubsub_subscription" "cost_optimization_processor" {
  name    = "${local.resource_names.pubsub_topic_events}-processor"
  topic   = google_pubsub_topic.cost_optimization_events.name
  project = var.project_id
  
  # Acknowledgment deadline for message processing
  ack_deadline_seconds = 300
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter queue for unprocessable messages
  dynamic "dead_letter_policy" {
    for_each = var.enable_pubsub_dead_letter ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter_queue[0].id
      max_delivery_attempts = 5
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.cost_optimization_events]
}

# Topic for batch job notifications
resource "google_pubsub_topic" "batch_job_notifications" {
  name    = local.resource_names.pubsub_topic_batch
  project = var.project_id
  
  message_retention_duration = "604800s"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Subscription for batch job completion handling
resource "google_pubsub_subscription" "batch_completion_handler" {
  name    = "${local.resource_names.pubsub_topic_batch}-handler"
  topic   = google_pubsub_topic.batch_job_notifications.name
  project = var.project_id
  
  ack_deadline_seconds = 300
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.batch_job_notifications]
}

# Dead letter queue for unprocessable messages (optional)
resource "google_pubsub_topic" "dead_letter_queue" {
  count   = var.enable_pubsub_dead_letter ? 1 : 0
  name    = "${local.name_prefix}-dead-letter-queue"
  project = var.project_id
  
  message_retention_duration = "604800s"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# CLOUD FUNCTIONS FOR AUTOMATED OPTIMIZATION
# ==============================================================================

# Create source code archive for the Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = file("${path.module}/function_code/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to storage bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.cost_optimization_data.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for cost optimization logic (Gen 2)
resource "google_cloudfunctions2_function" "cost_optimizer" {
  name        = local.resource_names.function_name
  location    = var.region
  project     = var.project_id
  description = "Automated infrastructure cost optimization function"
  
  build_config {
    runtime     = "python311"
    entry_point = "optimize_infrastructure"
    
    source {
      storage_source {
        bucket = google_storage_bucket.cost_optimization_data.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    
    # Use dedicated service account
    service_account_email = google_service_account.cost_optimizer.email
    
    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID              = var.project_id
      DATASET_NAME           = google_bigquery_dataset.cost_analytics.dataset_id
      BUCKET_NAME            = google_storage_bucket.cost_optimization_data.name
      CPU_THRESHOLD          = var.cpu_utilization_threshold
      MEMORY_THRESHOLD       = var.memory_utilization_threshold
      PUBSUB_TOPIC_EVENTS    = google_pubsub_topic.cost_optimization_events.name
      PUBSUB_TOPIC_BATCH     = google_pubsub_topic.batch_job_notifications.name
    }
    
    # Ingress settings for security
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    
    # VPC connector if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = var.vpc_connector_name
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# IAM binding to allow internal invocation
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.cost_optimizer.location
  cloud_function = google_cloudfunctions2_function.cost_optimizer.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.cost_optimizer.email}"
  
  depends_on = [google_cloudfunctions2_function.cost_optimizer]
}

# ==============================================================================
# CLOUD MONITORING ALERT POLICIES
# ==============================================================================

# Alert policy for detecting underutilized compute instances
resource "google_monitoring_alert_policy" "high_cost_low_utilization" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  display_name = "High Cost Low Utilization Alert"
  project      = var.project_id
  
  documentation {
    content = "This alert triggers when compute instances have low CPU utilization but high cost, indicating potential optimization opportunities."
  }
  
  conditions {
    display_name = "CPU utilization below ${var.cpu_utilization_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      duration        = "${var.monitoring_duration}s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = var.cpu_utilization_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Notification configuration (could be extended with notification channels)
  enabled = true
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for memory utilization monitoring
resource "google_monitoring_alert_policy" "memory_underutilization" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  display_name = "Memory Underutilization Alert"
  project      = var.project_id
  
  documentation {
    content = "Alert for instances with consistently low memory utilization that could be rightsized."
  }
  
  conditions {
    display_name = "Memory utilization below ${var.memory_utilization_threshold * 100}%"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/memory/utilization\""
      duration        = "${var.monitoring_duration}s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = var.memory_utilization_threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  enabled = true
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# CLOUD BATCH JOB DEFINITION FOR INFRASTRUCTURE ANALYSIS
# ==============================================================================

# Create batch job definition for comprehensive infrastructure analysis
resource "google_batch_job" "infrastructure_analysis_template" {
  name     = local.resource_names.batch_job_template
  location = var.region
  project  = var.project_id
  
  task_groups {
    task_count  = 1
    parallelism = var.batch_parallelism
    
    task_spec {
      compute_resource {
        cpu_milli      = 1000  # 1 vCPU
        memory_mib     = 2048  # 2 GB RAM
        max_retry_count = 3
      }
      
      max_retry_count = 3
      max_run_duration = "${var.batch_job_timeout}s"
      
      runnables {
        container {
          image_uri = "gcr.io/google-containers/toolbox"
          
          commands = ["/bin/bash", "-c"]
          arguments = [
            <<-EOT
            echo "Starting infrastructure cost analysis..."
            
            # Set up authentication and project
            export PROJECT_ID="${var.project_id}"
            export BUCKET_NAME="${google_storage_bucket.cost_optimization_data.name}"
            export DATASET_NAME="${google_bigquery_dataset.cost_analytics.dataset_id}"
            
            # Generate timestamp for unique file naming
            TIMESTAMP=$(date +%Y%m%d-%H%M%S)
            
            # Analyze compute instances
            echo "Analyzing compute instances..."
            gcloud compute instances list --format=json > /tmp/instances-$TIMESTAMP.json
            
            # Analyze GKE clusters
            echo "Analyzing GKE clusters..."
            gcloud container clusters list --format=json > /tmp/clusters-$TIMESTAMP.json
            
            # Upload analysis results to storage
            echo "Uploading analysis results..."
            gsutil cp /tmp/instances-$TIMESTAMP.json gs://$BUCKET_NAME/analysis/
            gsutil cp /tmp/clusters-$TIMESTAMP.json gs://$BUCKET_NAME/analysis/
            
            # Trigger cost optimization function
            echo "Triggering optimization analysis..."
            curl -X POST \
              -H "Authorization: Bearer $(gcloud auth print-access-token)" \
              -H "Content-Type: application/json" \
              -d '{"source":"batch_job","timestamp":"'$TIMESTAMP'"}' \
              "${google_cloudfunctions2_function.cost_optimizer.service_config[0].uri}"
            
            echo "Infrastructure analysis completed successfully"
            EOT
          ]
        }
        
        environment {
          variables = {
            PROJECT_ID   = var.project_id
            BUCKET_NAME  = google_storage_bucket.cost_optimization_data.name
            DATASET_NAME = google_bigquery_dataset.cost_analytics.dataset_id
          }
        }
      }
    }
  }
  
  allocation_policy {
    instances {
      policy {
        machine_type = var.batch_machine_type
        
        # Use preemptible instances for cost optimization
        provisioning_model = var.enable_preemptible_instances ? "PREEMPTIBLE" : "STANDARD"
      }
    }
    
    # Service account for batch job
    service_account {
      email = google_service_account.cost_optimizer.email
    }
  }
  
  logs_policy {
    destination = "CLOUD_LOGGING"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.cost_optimizer
  ]
}

# ==============================================================================
# CLOUD SCHEDULER FOR AUTOMATED OPTIMIZATION
# ==============================================================================

# Daily cost optimization scheduler
resource "google_cloud_scheduler_job" "daily_optimization" {
  count       = var.enable_scheduler_jobs ? 1 : 0
  name        = local.resource_names.scheduler_daily
  description = "Daily infrastructure cost optimization analysis"
  schedule    = var.optimization_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.cost_optimizer.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      source      = "daily_scheduler"
      analysis_type = "quick_scan"
      trigger_time = "daily"
    }))
    
    oidc_token {
      service_account_email = google_service_account.cost_optimizer.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.cost_optimizer
  ]
}

# Weekly comprehensive batch analysis scheduler
resource "google_cloud_scheduler_job" "weekly_batch_analysis" {
  count       = var.enable_scheduler_jobs ? 1 : 0
  name        = local.resource_names.scheduler_weekly
  description = "Weekly comprehensive infrastructure analysis using Cloud Batch"
  schedule    = var.batch_analysis_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "POST"
    uri         = "https://batch.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/jobs"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    # Submit a new batch job based on the template
    body = base64encode(jsonencode({
      parent = "projects/${var.project_id}/locations/${var.region}"
      job_id = "${local.resource_names.batch_job_template}-${formatdate("YYYYMMDD-HHmmss", timestamp())}"
      job    = google_batch_job.infrastructure_analysis_template
    }))
    
    oauth_token {
      service_account_email = google_service_account.cost_optimizer.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_batch_job.infrastructure_analysis_template
  ]
}