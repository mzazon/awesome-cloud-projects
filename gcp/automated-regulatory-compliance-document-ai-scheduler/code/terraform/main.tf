# Main Terraform configuration for automated regulatory compliance system
# This file defines all the infrastructure resources needed for Document AI processing,
# Cloud Functions, Cloud Scheduler, and Cloud Storage integration

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    deployment  = "terraform"
  })
  
  # Resource names with unique suffix
  input_bucket_name     = "${var.resource_prefix}-input-${local.resource_suffix}"
  processed_bucket_name = "${var.resource_prefix}-processed-${local.resource_suffix}"
  reports_bucket_name   = "${var.resource_prefix}-reports-${local.resource_suffix}"
  processor_function    = "${var.resource_prefix}-document-processor-${local.resource_suffix}"
  report_function       = "${var.resource_prefix}-report-generator-${local.resource_suffix}"
  scheduler_job_prefix  = "${var.resource_prefix}-scheduler-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "documentai.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com"
  ]) : []

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Create Cloud Storage bucket for input documents
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable versioning for audit trails
  versioning {
    enabled = var.enable_versioning
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule to transition older versions to cheaper storage
  lifecycle_rule {
    condition {
      age                   = 30
      with_state           = "ARCHIVED"
      num_newer_versions   = 3
    }
    action {
      type = "Delete"
    }
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  # Force destroy for development environments (use with caution)
  force_destroy = var.force_destroy_buckets
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for processed documents
resource "google_storage_bucket" "processed_bucket" {
  name          = local.processed_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable versioning for audit trails
  versioning {
    enabled = var.enable_versioning
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  force_destroy = var.force_destroy_buckets
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for compliance reports
resource "google_storage_bucket" "reports_bucket" {
  name          = local.reports_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable versioning for audit trails
  versioning {
    enabled = var.enable_versioning
  }
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Extended lifecycle for compliance reports (longer retention)
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age * 2  # Keep reports twice as long
    }
    action {
      type = "Delete"
    }
  }
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  force_destroy = var.force_destroy_buckets
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Document AI processor for compliance document parsing
resource "google_document_ai_processor" "compliance_processor" {
  location     = var.document_ai_location
  display_name = "Compliance Form Parser"
  type         = "FORM_PARSER_PROCESSOR"
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-functions-sa"
  display_name = "Service Account for Compliance Functions"
  description  = "Service account used by Cloud Functions for document processing and report generation"
}

# Grant necessary IAM roles to the function service account
resource "google_project_iam_member" "function_documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Eventarc trigger for document processing
resource "google_eventarc_trigger" "document_trigger" {
  name     = "${var.resource_prefix}-document-trigger"
  location = var.region
  
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.input_bucket.name
  }
  
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.document_processor.name
      region  = var.region
    }
  }
  
  service_account = google_service_account.function_sa.email
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.document_processor
  ]
}

# Archive source code for document processor function
data "archive_file" "document_processor_zip" {
  type        = "zip"
  output_path = "/tmp/document_processor.zip"
  
  source {
    content = templatefile("${path.module}/functions/document_processor.py", {
      project_id       = var.project_id
      region          = var.region
      processor_id    = google_document_ai_processor.compliance_processor.name
      processed_bucket = google_storage_bucket.processed_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements_processor.txt")
    filename = "requirements.txt"
  }
}

# Archive source code for report generator function
data "archive_file" "report_generator_zip" {
  type        = "zip"
  output_path = "/tmp/report_generator.zip"
  
  source {
    content = templatefile("${path.module}/functions/report_generator.py", {
      project_id       = var.project_id
      processed_bucket = google_storage_bucket.processed_bucket.name
      reports_bucket   = google_storage_bucket.reports_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements_reporter.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "document_processor_source" {
  name   = "functions/document_processor_${data.archive_file.document_processor_zip.output_md5}.zip"
  bucket = google_storage_bucket.processed_bucket.name
  source = data.archive_file.document_processor_zip.output_path
}

resource "google_storage_bucket_object" "report_generator_source" {
  name   = "functions/report_generator_${data.archive_file.report_generator_zip.output_md5}.zip"
  bucket = google_storage_bucket.processed_bucket.name
  source = data.archive_file.report_generator_zip.output_path
}

# Deploy document processing Cloud Function (2nd generation)
resource "google_cloudfunctions2_function" "document_processor" {
  name     = local.processor_function
  location = var.region
  
  build_config {
    runtime     = "python312"
    entry_point = "process_compliance_document"
    
    source {
      storage_source {
        bucket = google_storage_bucket.processed_bucket.name
        object = google_storage_bucket_object.document_processor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      REGION          = var.region
      PROCESSOR_ID    = google_document_ai_processor.compliance_processor.name
      PROCESSED_BUCKET = google_storage_bucket.processed_bucket.name
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.document_processor_source
  ]
}

# Deploy report generation Cloud Function (2nd generation)
resource "google_cloudfunctions2_function" "report_generator" {
  name     = local.report_function
  location = var.region
  
  build_config {
    runtime     = "python312"
    entry_point = "generate_compliance_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.processed_bucket.name
        object = google_storage_bucket_object.report_generator_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 5
    min_instance_count = 0
    available_memory   = "${var.report_function_memory}M"
    timeout_seconds    = var.report_function_timeout
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      PROCESSED_BUCKET = google_storage_bucket.processed_bucket.name
      REPORTS_BUCKET   = google_storage_bucket.reports_bucket.name
    }
    
    service_account_email = google_service_account.function_sa.email
    
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.report_generator_source
  ]
}

# Create Cloud Scheduler job for daily compliance reports
resource "google_cloud_scheduler_job" "daily_compliance_report" {
  name      = "${local.scheduler_job_prefix}-daily"
  region    = var.region
  schedule  = var.daily_report_schedule
  time_zone = var.scheduler_timezone
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.report_generator.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      report_type = "daily"
    }))
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.report_generator
  ]
}

# Create Cloud Scheduler job for weekly compliance reports
resource "google_cloud_scheduler_job" "weekly_compliance_report" {
  name      = "${local.scheduler_job_prefix}-weekly"
  region    = var.region
  schedule  = var.weekly_report_schedule
  time_zone = var.scheduler_timezone
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.report_generator.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      report_type = "weekly"
    }))
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.report_generator
  ]
}

# Create Cloud Scheduler job for monthly compliance reports
resource "google_cloud_scheduler_job" "monthly_compliance_report" {
  name      = "${local.scheduler_job_prefix}-monthly"
  region    = var.region
  schedule  = var.monthly_report_schedule
  time_zone = var.scheduler_timezone
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.report_generator.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      report_type = "monthly"
    }))
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.report_generator
  ]
}

# Create log-based metrics for monitoring compliance violations
resource "google_logging_metric" "compliance_violations" {
  name   = "compliance_violations"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"NON_COMPLIANT\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Compliance Violations"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create log-based metrics for monitoring processing errors
resource "google_logging_metric" "processing_errors" {
  name   = "processing_errors"
  filter = "resource.type=\"cloud_function\" AND severity=\"ERROR\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Processing Errors"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create log-based metrics for successful processing
resource "google_logging_metric" "successful_processing" {
  name   = "successful_processing"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"Document processed successfully\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Successful Processing"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create notification channel for compliance alerts
resource "google_monitoring_notification_channel" "compliance_email" {
  display_name = "Compliance Team Email"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for compliance violations
resource "google_monitoring_alert_policy" "compliance_violations_alert" {
  display_name = "High Compliance Violations"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Compliance violations exceed threshold"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/compliance_violations\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.compliance_email.id]
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.compliance_violations
  ]
}

# Create alerting policy for processing errors
resource "google_monitoring_alert_policy" "processing_errors_alert" {
  display_name = "High Processing Error Rate"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Processing errors exceed threshold"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/processing_errors\""
      duration        = "600s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.compliance_email.id]
  
  alert_strategy {
    auto_close = "604800s"  # 7 days
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.processing_errors
  ]
}