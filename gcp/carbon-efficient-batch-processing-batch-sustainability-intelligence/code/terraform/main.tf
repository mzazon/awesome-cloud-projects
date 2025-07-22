# Main Terraform Configuration
# Carbon-Efficient Batch Processing with Cloud Batch and Sustainability Intelligence

# Generate random suffix for resource names to ensure uniqueness
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  # Common resource naming convention
  resource_prefix = "${var.name_prefix}-${random_string.suffix.result}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    region     = var.region
    timestamp  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Carbon intelligence configuration
  carbon_config = {
    threshold_intensity = var.carbon_intensity_threshold
    threshold_cfe       = var.cfe_percentage_threshold
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "batch.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for carbon data and job artifacts
resource "google_storage_bucket" "carbon_data_bucket" {
  name                        = "${local.resource_prefix}-carbon-data"
  location                    = var.region
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age * 3
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Security and compliance
  encryption {
    default_kms_key_name = google_kms_crypto_key.carbon_data_key.id
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create organized directories in the bucket
resource "google_storage_bucket_object" "carbon_data_directories" {
  for_each = toset([
    "carbon-data/",
    "job-scripts/",
    "results/",
    "configs/"
  ])
  
  name    = "${each.key}.keep"
  content = "# This file maintains the directory structure"
  bucket  = google_storage_bucket.carbon_data_bucket.name
}

# KMS key for encrypting carbon data
resource "google_kms_key_ring" "carbon_keyring" {
  name     = "${local.resource_prefix}-carbon-keyring"
  location = var.region
  
  depends_on = [google_project_service.required_apis]
}

resource "google_kms_crypto_key" "carbon_data_key" {
  name     = "${local.resource_prefix}-carbon-data-key"
  key_ring = google_kms_key_ring.carbon_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  rotation_period = "7776000s" # 90 days
  
  labels = local.common_labels
}

# Pub/Sub topic for carbon optimization events
resource "google_pubsub_topic" "carbon_events" {
  name = "${local.resource_prefix}-carbon-events"
  
  labels = local.common_labels
  
  # Message retention for sustainability reporting
  message_retention_duration = "604800s" # 7 days
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for carbon event processing
resource "google_pubsub_subscription" "carbon_events_sub" {
  name  = "${local.resource_prefix}-carbon-sub"
  topic = google_pubsub_topic.carbon_events.name
  
  # Longer ack deadline for batch processing
  ack_deadline_seconds = 600
  
  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.carbon_events_dlq.id
    max_delivery_attempts = 5
  }
  
  # Retry policy for sustainability data processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  labels = local.common_labels
}

# Dead letter queue for failed carbon events
resource "google_pubsub_topic" "carbon_events_dlq" {
  name = "${local.resource_prefix}-carbon-events-dlq"
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
}

# Service account for batch jobs with carbon intelligence
resource "google_service_account" "carbon_batch_sa" {
  account_id   = "${local.resource_prefix}-batch-sa"
  display_name = "Carbon-Aware Batch Service Account"
  description  = "Service account for carbon-efficient batch processing"
}

# IAM roles for carbon batch service account
resource "google_project_iam_member" "carbon_batch_permissions" {
  for_each = toset([
    "roles/batch.agentReporter",
    "roles/batch.jobsEditor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/storage.objectAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.carbon_batch_sa.email}"
}

# Service account for carbon scheduler function
resource "google_service_account" "carbon_scheduler_sa" {
  account_id   = "${local.resource_prefix}-scheduler-sa"
  display_name = "Carbon Scheduler Service Account"
  description  = "Service account for carbon-aware scheduling function"
}

# IAM roles for carbon scheduler
resource "google_project_iam_member" "carbon_scheduler_permissions" {
  for_each = toset([
    "roles/batch.jobsEditor",
    "roles/pubsub.publisher",
    "roles/storage.objectViewer",
    "roles/monitoring.viewer",
    "roles/cloudfunctions.invoker"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.carbon_scheduler_sa.email}"
}

# Carbon-aware job script stored in Cloud Storage
resource "google_storage_bucket_object" "carbon_job_script" {
  name    = "job-scripts/carbon_aware_job.py"
  bucket  = google_storage_bucket.carbon_data_bucket.name
  content = templatefile("${path.module}/scripts/carbon_aware_job.py", {
    project_id   = var.project_id
    region       = var.region
    topic_name   = google_pubsub_topic.carbon_events.name
    bucket_name  = google_storage_bucket.carbon_data_bucket.name
  })
}

# Archive carbon scheduler function source code
data "archive_file" "carbon_scheduler_source" {
  type        = "zip"
  output_path = "${path.module}/tmp/carbon_scheduler.zip"
  
  source {
    content = templatefile("${path.module}/functions/carbon_scheduler.py", {
      project_id                = var.project_id
      topic_name               = google_pubsub_topic.carbon_events.name
      carbon_intensity_threshold = var.carbon_intensity_threshold
      cfe_percentage_threshold   = var.cfe_percentage_threshold
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload carbon scheduler function source to Cloud Storage
resource "google_storage_bucket_object" "carbon_scheduler_source" {
  name   = "functions/carbon-scheduler-${random_string.suffix.result}.zip"
  bucket = google_storage_bucket.carbon_data_bucket.name
  source = data.archive_file.carbon_scheduler_source.output_path
}

# Carbon-aware scheduler Cloud Function
resource "google_cloudfunctions_function" "carbon_scheduler" {
  name        = "${local.resource_prefix}-carbon-scheduler"
  description = "Carbon-aware batch job scheduler with sustainability intelligence"
  region      = var.region
  
  runtime               = "python39"
  available_memory_mb   = var.function_memory
  timeout              = var.function_timeout
  entry_point          = "carbon_aware_scheduler"
  service_account_email = google_service_account.carbon_scheduler_sa.email
  
  source_archive_bucket = google_storage_bucket.carbon_data_bucket.name
  source_archive_object = google_storage_bucket_object.carbon_scheduler_source.name
  
  # HTTP trigger for external invocation
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Environment variables for carbon intelligence
  environment_variables = {
    PROJECT_ID                   = var.project_id
    REGION                      = var.region
    TOPIC_NAME                  = google_pubsub_topic.carbon_events.name
    BUCKET_NAME                 = google_storage_bucket.carbon_data_bucket.name
    CARBON_INTENSITY_THRESHOLD  = var.carbon_intensity_threshold
    CFE_PERCENTAGE_THRESHOLD    = var.cfe_percentage_threshold
    ENABLE_CARBON_MONITORING    = var.enable_carbon_monitoring
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Batch job template for carbon-efficient processing
resource "google_batch_job" "carbon_batch_template" {
  count    = 0  # Template only - not created by default
  name     = "${local.resource_prefix}-carbon-job-template"
  location = var.region
  
  allocation_policy {
    instances {
      policy {
        machine_type = var.batch_machine_type
        
        # Use preemptible instances for carbon efficiency
        provisioning_model = var.use_preemptible_instances ? "PREEMPTIBLE" : "STANDARD"
      }
    }
    
    location {
      allowed_locations = ["zones/${var.zone}"]
    }
    
    # Service account for carbon intelligence
    service_account {
      email = google_service_account.carbon_batch_sa.email
    }
  }
  
  task_groups {
    task_count = var.batch_job_parallelism
    
    task_spec {
      runnables {
        container {
          image_uri = "python:3.9-slim"
          commands  = ["/bin/bash"]
          options   = "--workdir=/workspace"
        }
        
        script {
          text = "pip install google-cloud-pubsub google-cloud-monitoring google-cloud-storage && python /workspace/carbon_aware_job.py"
        }
        
        environment {
          variables = {
            PROJECT_ID               = var.project_id
            REGION                  = var.region
            TOPIC_NAME              = google_pubsub_topic.carbon_events.name
            BUCKET_NAME             = google_storage_bucket.carbon_data_bucket.name
            CARBON_INTENSITY_THRESHOLD = var.carbon_intensity_threshold
            CFE_PERCENTAGE_THRESHOLD   = var.cfe_percentage_threshold
          }
        }
      }
      
      compute_resource {
        cpu_milli   = "2000"  # 2 vCPUs
        memory_mib  = "4096"  # 4 GB RAM
      }
      
      max_retry_count   = 2
      max_run_duration = "3600s"  # 1 hour max
    }
  }
  
  logs_policy {
    destination = "CLOUD_LOGGING"
  }
  
  labels = local.common_labels
}

# Custom monitoring metrics for carbon tracking
resource "google_monitoring_custom_service" "carbon_monitoring" {
  count = var.enable_carbon_monitoring ? 1 : 0
  
  service_id   = "${local.resource_prefix}-carbon-monitoring"
  display_name = "Carbon Efficiency Monitoring"
  
  telemetry {
    resource_name = "//batch.googleapis.com/projects/${var.project_id}/locations/${var.region}"
  }
}

# Alert policy for high carbon impact
resource "google_monitoring_alert_policy" "high_carbon_impact" {
  count = var.enable_carbon_monitoring ? 1 : 0
  
  display_name = "High Carbon Impact Alert - ${local.resource_prefix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Carbon Impact Threshold Exceeded"
    
    condition_threshold {
      filter          = "resource.type=\"generic_task\" AND metric.type=\"custom.googleapis.com/batch/carbon_impact\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.5  # kgCO2e
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  documentation {
    content   = "Alert triggered when batch jobs exceed carbon intensity thresholds. Review workload scheduling and regional placement."
    mime_type = "text/markdown"
  }
  
  labels = local.common_labels
}

# Log sink for carbon efficiency analysis
resource "google_logging_project_sink" "carbon_logs" {
  name        = "${local.resource_prefix}-carbon-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.carbon_data_bucket.name}"
  
  # Filter for carbon-related logs
  filter = "resource.type=\"batch_job\" OR resource.type=\"cloud_function\" AND jsonPayload.carbon_metrics.carbon_impact>0"
  
  # Unique writer identity for the sink
  unique_writer_identity = true
}

# Grant storage permissions to log sink
resource "google_storage_bucket_iam_member" "carbon_logs_writer" {
  bucket = google_storage_bucket.carbon_data_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.carbon_logs.writer_identity
}

# Cloud Scheduler job for periodic carbon optimization
resource "google_cloud_scheduler_job" "carbon_optimizer" {
  name             = "${local.resource_prefix}-carbon-optimizer"
  description      = "Periodic carbon-aware optimization and reporting"
  schedule         = "0 */6 * * *"  # Every 6 hours
  time_zone        = "UTC"
  attempt_deadline = "180s"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.carbon_scheduler.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      project_id = var.project_id
      topic_name = google_pubsub_topic.carbon_events.name
      trigger    = "scheduled_optimization"
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}