# AI Model Bias Detection with Vertex AI Monitoring and Cloud Functions
# This Terraform configuration creates a comprehensive bias detection system for AI models

terraform {
  required_version = ">= 1.5"
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current project
data "google_project" "current" {}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])

  service = each.value
  
  # Prevent accidental deletion of critical APIs
  disable_on_destroy = false
}

# Cloud Storage bucket for bias detection reports and artifacts
resource "google_storage_bucket" "bias_detection_bucket" {
  name          = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"
  
  # Enable versioning for audit trail compliance
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = {
    purpose     = "bias-detection"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage bucket objects for folder structure
resource "google_storage_bucket_object" "reports_readme" {
  name    = "reports/README.txt"
  bucket  = google_storage_bucket.bias_detection_bucket.name
  content = "Bias Detection Reports - Contains automated bias analysis reports and audit results"
}

resource "google_storage_bucket_object" "datasets_readme" {
  name    = "datasets/README.txt"
  bucket  = google_storage_bucket.bias_detection_bucket.name
  content = "Reference Datasets - Contains reference datasets for model monitoring and bias detection"
}

resource "google_storage_bucket_object" "models_readme" {
  name    = "models/README.txt"
  bucket  = google_storage_bucket.bias_detection_bucket.name
  content = "Model Artifacts - Contains model artifacts and monitoring configurations"
}

# Pub/Sub topic for model monitoring alerts
resource "google_pubsub_topic" "model_monitoring_alerts" {
  name = var.pubsub_topic_name
  
  # Message retention for reliability
  message_retention_duration = "604800s" # 7 days
  
  labels = {
    purpose     = "bias-detection"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub subscription for bias detection processing
resource "google_pubsub_subscription" "bias_detection_sub" {
  name  = "bias-detection-sub"
  topic = google_pubsub_topic.model_monitoring_alerts.name
  
  # Acknowledgment deadline for processing
  ack_deadline_seconds = 300
  
  # Message retention for reliability
  message_retention_duration = "604800s" # 7 days
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  # Dead letter policy for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }
  
  labels = {
    purpose     = "bias-detection"
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter_topic" {
  name = "${var.pubsub_topic_name}-dead-letter"
  
  labels = {
    purpose     = "bias-detection-dlq"
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "bias-detection-functions"
  display_name = "Bias Detection Functions Service Account"
  description  = "Service account for bias detection Cloud Functions with minimal required permissions"
}

# IAM roles for the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/pubsub.subscriber",
    "roles/pubsub.publisher",
    "roles/logging.logWriter",
    "roles/aiplatform.user"
  ])
  
  project = data.google_project.current.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Storage bucket IAM for function service account
resource "google_storage_bucket_iam_member" "function_bucket_access" {
  bucket = google_storage_bucket.bias_detection_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Archive for bias detection function source code
data "archive_file" "bias_detection_function_zip" {
  type        = "zip"
  output_path = "${path.module}/bias-detection-function.zip"
  
  source {
    content = templatefile("${path.module}/function-code/bias-detector/main.py", {
      bucket_name = google_storage_bucket.bias_detection_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-code/bias-detector/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for bias detection function source
resource "google_storage_bucket_object" "bias_detection_function_source" {
  name   = "functions/bias-detection-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.bias_detection_bucket.name
  source = data.archive_file.bias_detection_function_zip.output_path
  
  depends_on = [data.archive_file.bias_detection_function_zip]
}

# Bias Detection Cloud Function
resource "google_cloudfunctions2_function" "bias_detection_function" {
  name        = var.bias_detection_function_name
  location    = var.region
  description = "Processes model monitoring alerts for bias detection and fairness analysis"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_bias_alert"
    
    source {
      storage_source {
        bucket = google_storage_bucket.bias_detection_bucket.name
        object = google_storage_bucket_object.bias_detection_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 300
    max_instance_request_concurrency = 10
    available_cpu                    = "1"
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.bias_detection_bucket.name
      PROJECT_ID  = data.google_project.current.project_id
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # VPC connector for secure networking (if needed)
    # vpc_connector = var.vpc_connector_name
    
    # Security settings
    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.model_monitoring_alerts.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = {
    purpose     = "bias-detection"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.bias_detection_function_source
  ]
}

# Archive for alert processing function source code
data "archive_file" "alert_processing_function_zip" {
  type        = "zip"
  output_path = "${path.module}/alert-processing-function.zip"
  
  source {
    content  = file("${path.module}/function-code/alert-processor/main.py")
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-code/alert-processor/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for alert processing function source
resource "google_storage_bucket_object" "alert_processing_function_source" {
  name   = "functions/alert-processing-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.bias_detection_bucket.name
  source = data.archive_file.alert_processing_function_zip.output_path
  
  depends_on = [data.archive_file.alert_processing_function_zip]
}

# Alert Processing Cloud Function
resource "google_cloudfunctions2_function" "alert_processing_function" {
  name        = var.alert_processing_function_name
  location    = var.region
  description = "Processes and routes bias alerts based on severity levels"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_bias_alerts"
    
    source {
      storage_source {
        bucket = google_storage_bucket.bias_detection_bucket.name
        object = google_storage_bucket_object.alert_processing_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 50
    min_instance_count               = 0
    available_memory                 = "256Mi"
    timeout_seconds                  = 120
    max_instance_request_concurrency = 10
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = data.google_project.current.project_id
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # Allow public access for HTTP trigger (adjust as needed for security)
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = {
    purpose     = "bias-alert-processing"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.alert_processing_function_source
  ]
}

# Archive for audit function source code
data "archive_file" "audit_function_zip" {
  type        = "zip"
  output_path = "${path.module}/audit-function.zip"
  
  source {
    content = templatefile("${path.module}/function-code/audit-scheduler/main.py", {
      bucket_name = google_storage_bucket.bias_detection_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-code/audit-scheduler/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for audit function source
resource "google_storage_bucket_object" "audit_function_source" {
  name   = "functions/audit-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.bias_detection_bucket.name
  source = data.archive_file.audit_function_zip.output_path
  
  depends_on = [data.archive_file.audit_function_zip]
}

# Audit Function
resource "google_cloudfunctions2_function" "audit_function" {
  name        = var.audit_function_name
  location    = var.region
  description = "Generates comprehensive bias audit reports on a scheduled basis"
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_bias_audit"
    
    source {
      storage_source {
        bucket = google_storage_bucket.bias_detection_bucket.name
        object = google_storage_bucket_object.audit_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 600
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.bias_detection_bucket.name
      PROJECT_ID  = data.google_project.current.project_id
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # Allow internal access only for security
    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }
  
  labels = {
    purpose     = "bias-audit"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.audit_function_source
  ]
}

# Cloud Scheduler job for regular bias audits
resource "google_cloud_scheduler_job" "bias_audit_scheduler" {
  name             = var.scheduler_job_name
  description      = "Triggers weekly comprehensive bias audits for model governance"
  schedule         = "0 9 * * 1"  # Every Monday at 9:00 AM
  time_zone        = "America/New_York"
  region           = var.region
  attempt_deadline = "600s"
  
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    max_backoff_duration = "60s"
    min_backoff_duration = "10s"
    max_doublings        = 3
  }
  
  http_target {
    uri         = google_cloudfunctions2_function.audit_function.service_config[0].uri
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      audit_type = "scheduled"
      trigger    = "weekly"
    }))
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
      audience              = google_cloudfunctions2_function.audit_function.service_config[0].uri
    }
  }
  
  depends_on = [
    google_project_service.apis,
    google_cloudfunctions2_function.audit_function
  ]
}

# IAM policy for Cloud Scheduler to invoke the audit function
resource "google_cloudfunctions2_function_iam_member" "audit_function_invoker" {
  project        = data.google_project.current.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.audit_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM policy for alert processing function (public access - adjust for security)
resource "google_cloudfunctions2_function_iam_member" "alert_function_public_invoker" {
  project        = data.google_project.current.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.alert_processing_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Log sink for bias detection compliance events
resource "google_logging_project_sink" "bias_detection_sink" {
  name        = "bias-detection-compliance-sink"
  description = "Exports bias detection and compliance events to BigQuery for analysis"
  
  # Export to BigQuery for long-term analysis (optional)
  destination = "bigquery.googleapis.com/projects/${data.google_project.current.project_id}/datasets/${google_bigquery_dataset.bias_logs.dataset_id}"
  
  # Filter for bias detection related logs
  filter = <<-EOT
    resource.type="cloud_function"
    (jsonPayload.message:"BIAS_ANALYSIS" OR 
     jsonPayload.message:"COMPLIANCE_EVENT" OR 
     jsonPayload.message:"AUDIT_COMPLETED")
  EOT
  
  # Use partitioned tables for better performance
  bigquery_options {
    use_partitioned_tables = true
  }
  
  unique_writer_identity = true
}

# BigQuery dataset for bias detection logs (optional)
resource "google_bigquery_dataset" "bias_logs" {
  dataset_id    = "bias_detection_logs"
  friendly_name = "Bias Detection Logs"
  description   = "Dataset for storing bias detection compliance and audit logs"
  location      = var.region
  
  # Data retention for compliance
  default_table_expiration_ms = 31536000000 # 1 year
  
  labels = {
    purpose     = "bias-detection-logs"
    environment = var.environment
    managed-by  = "terraform"
  }
  
  depends_on = [google_project_service.apis]
}

# IAM for log sink to write to BigQuery
resource "google_bigquery_dataset_iam_member" "log_sink_writer" {
  dataset_id = google_bigquery_dataset.bias_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.bias_detection_sink.writer_identity
}

# Monitoring alert policy for critical bias violations
resource "google_monitoring_alert_policy" "critical_bias_alert" {
  display_name = "Critical Bias Violations"
  combiner     = "OR"
  
  conditions {
    display_name = "Critical bias score detected"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND jsonPayload.severity=\"CRITICAL\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }
  
  depends_on = [google_project_service.apis]
}