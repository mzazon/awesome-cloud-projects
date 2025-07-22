# Main configuration for GCP compliance reporting infrastructure
# This Terraform configuration deploys a comprehensive compliance reporting solution
# using Cloud Audit Logs, Document AI, Cloud Storage, and Cloud Functions

# Local values for consistent resource naming and configuration
locals {
  # Generate unique suffix for resource names to prevent conflicts
  resource_suffix = random_id.suffix.hex
  
  # Common naming pattern for all resources
  name_prefix = "${var.resource_prefix}-${var.environment}"
  
  # Common labels applied to all resources for compliance tracking
  common_labels = merge(var.tags, {
    environment         = var.environment
    compliance-solution = "audit-logs-document-ai"
    created-by         = "terraform"
    creation-date      = timestamp()
  })
  
  # Audit log filter for comprehensive compliance tracking
  audit_log_filter = join(" OR ", [
    "protoPayload.serviceName=\"storage.googleapis.com\"",
    "protoPayload.serviceName=\"compute.googleapis.com\"", 
    "protoPayload.serviceName=\"iam.googleapis.com\"",
    "protoPayload.serviceName=\"documentai.googleapis.com\"",
    "protoPayload.serviceName=\"cloudfunctions.googleapis.com\""
  ])
  
  # Storage lifecycle rules for cost optimization and compliance retention
  lifecycle_rules = [
    {
      condition = {
        age = 30
      }
      action = {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    },
    {
      condition = {
        age = 90
      }
      action = {
        type          = "SetStorageClass"  
        storage_class = "COLDLINE"
      }
    },
    {
      condition = {
        age = var.audit_log_retention_days
      }
      action = {
        type = "Delete"
      }
    }
  ]
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs for the compliance solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "logging.googleapis.com",
    "documentai.googleapis.com", 
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.key
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# ======================================
# CLOUD STORAGE INFRASTRUCTURE
# ======================================

# Primary storage bucket for audit logs with compliance-grade configuration
resource "google_storage_bucket" "audit_logs" {
  name                        = "${local.name_prefix}-audit-logs-${local.resource_suffix}"
  location                    = var.region
  storage_class              = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention   = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Enable versioning for audit trail integrity
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization and retention compliance
  dynamic "lifecycle_rule" {
    for_each = local.lifecycle_rules
    content {
      condition {
        age = lifecycle_rule.value.condition.age
      }
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = try(lifecycle_rule.value.action.storage_class, null)
      }
    }
  }
  
  # Encryption configuration for data protection
  encryption {
    default_kms_key_name = google_kms_crypto_key.compliance_key.id
  }
  
  # Soft delete policy for compliance requirements
  soft_delete_policy {
    retention_duration_seconds = 604800  # 7 days
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_binding.storage_key_binding
  ]
}

# Storage bucket for compliance documents with enhanced security
resource "google_storage_bucket" "compliance_documents" {
  name                        = "${local.name_prefix}-compliance-docs-${local.resource_suffix}"
  location                    = var.region
  storage_class              = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention   = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  # Enable versioning for document change tracking
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for compliance documents
  dynamic "lifecycle_rule" {
    for_each = local.lifecycle_rules
    content {
      condition {
        age = lifecycle_rule.value.condition.age
      }
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = try(lifecycle_rule.value.action.storage_class, null)
      }
    }
  }
  
  # Encryption configuration
  encryption {
    default_kms_key_name = google_kms_crypto_key.compliance_key.id
  }
  
  # Soft delete policy
  soft_delete_policy {
    retention_duration_seconds = 604800
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_binding.storage_key_binding
  ]
}

# Storage bucket for processed compliance reports
resource "google_storage_bucket" "compliance_reports" {
  name                        = "${local.name_prefix}-compliance-reports-${local.resource_suffix}"
  location                    = var.region
  storage_class              = "STANDARD"
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention   = var.enable_public_access_prevention ? "enforced" : "inherited"
  
  versioning {
    enabled = true
  }
  
  # Reports have shorter lifecycle for active access
  lifecycle_rule {
    condition {
      age = 365  # Move to nearline after 1 year
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  encryption {
    default_kms_key_name = google_kms_crypto_key.compliance_key.id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_binding.storage_key_binding
  ]
}

# ======================================
# CLOUD KMS FOR ENCRYPTION
# ======================================

# KMS keyring for compliance encryption keys
resource "google_kms_key_ring" "compliance_keyring" {
  name     = "${local.name_prefix}-compliance-keyring-${local.resource_suffix}"
  location = var.region
  
  depends_on = [google_project_service.required_apis]
}

# KMS crypto key for encrypting compliance data
resource "google_kms_crypto_key" "compliance_key" {
  name     = "${local.name_prefix}-compliance-key"
  key_ring = google_kms_key_ring.compliance_keyring.id
  purpose  = "ENCRYPT_DECRYPT"
  
  # Key rotation for enhanced security
  rotation_period = "7776000s"  # 90 days
  
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# IAM binding for Cloud Storage to use KMS key
resource "google_kms_crypto_key_iam_binding" "storage_key_binding" {
  crypto_key_id = google_kms_crypto_key.compliance_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  
  members = [
    "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
  ]
}

# ======================================
# DOCUMENT AI PROCESSORS
# ======================================

# Document AI processor for compliance document analysis
resource "google_document_ai_processor" "compliance_processor" {
  location     = var.region
  display_name = "${local.name_prefix}-compliance-processor-${local.resource_suffix}"
  type         = var.document_processor_type
  
  depends_on = [google_project_service.required_apis]
}

# Document AI processor specialized for contract analysis
resource "google_document_ai_processor" "contract_processor" {
  location     = var.region
  display_name = "${local.name_prefix}-contract-processor-${local.resource_suffix}"
  type         = "CONTRACT_PROCESSOR"
  
  depends_on = [google_project_service.required_apis]
}

# ======================================
# SERVICE ACCOUNTS AND IAM
# ======================================

# Service account for Cloud Functions with minimal required permissions
resource "google_service_account" "compliance_function_sa" {
  account_id   = "${local.name_prefix}-cf-sa-${local.resource_suffix}"
  display_name = "Compliance Functions Service Account"
  description  = "Service account for compliance processing Cloud Functions"
}

# IAM roles for the Cloud Functions service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/documentai.editor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.compliance_function_sa.email}"
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "${local.name_prefix}-scheduler-sa-${local.resource_suffix}"
  display_name = "Compliance Scheduler Service Account"
  description  = "Service account for compliance job scheduling"
}

# IAM role for scheduler to invoke functions
resource "google_project_iam_member" "scheduler_sa_roles" {
  for_each = toset([
    "roles/cloudfunctions.invoker",
    "roles/run.invoker"
  ])
  
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# ======================================
# CLOUD AUDIT LOGS CONFIGURATION
# ======================================

# IAM audit config for comprehensive logging
resource "google_project_iam_audit_config" "compliance_audit_config" {
  project = var.project_id
  service = "allServices"
  
  # Admin activity logs (always enabled for compliance)
  dynamic "audit_log_config" {
    for_each = var.enable_admin_activity_logs ? [1] : []
    content {
      log_type = "ADMIN_READ"
    }
  }
  
  # Data access logs (recommended for compliance)
  dynamic "audit_log_config" {
    for_each = var.enable_data_access_logs ? [1] : []
    content {
      log_type = "DATA_READ"
    }
  }
  
  dynamic "audit_log_config" {
    for_each = var.enable_data_access_logs ? [1] : []
    content {
      log_type = "DATA_WRITE"
    }
  }
}

# Log sink for audit logs to Cloud Storage
resource "google_logging_project_sink" "compliance_audit_sink" {
  name        = "${local.name_prefix}-audit-sink-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs.name}"
  
  filter = local.audit_log_filter
  
  # Use a unique writer for the sink
  unique_writer_identity = true
  
  depends_on = [google_storage_bucket.audit_logs]
}

# Grant the log sink writer access to the storage bucket
resource "google_storage_bucket_iam_member" "audit_sink_writer" {
  bucket = google_storage_bucket.audit_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.compliance_audit_sink.writer_identity
}

# ======================================
# CLOUD FUNCTIONS FOR PROCESSING
# ======================================

# Archive source code for document processing function
data "archive_file" "document_processor_source" {
  type        = "zip"
  output_path = "/tmp/document-processor.zip"
  
  source {
    content = templatefile("${path.module}/functions/document_processor.py", {
      project_id   = var.project_id
      region       = var.region
      processor_id = google_document_ai_processor.compliance_processor.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Storage object for document processor function source
resource "google_storage_bucket_object" "document_processor_source" {
  name   = "functions/document-processor-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.compliance_documents.name
  source = data.archive_file.document_processor_source.output_path
  
  depends_on = [data.archive_file.document_processor_source]
}

# Cloud Function for document processing
resource "google_cloudfunctions2_function" "document_processor" {
  name     = "${local.name_prefix}-doc-processor-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "process_compliance_document"
    
    source {
      storage_source {
        bucket = google_storage_bucket.compliance_documents.name
        object = google_storage_bucket_object.document_processor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = "${var.cloud_function_memory}Mi"
    timeout_seconds       = var.cloud_function_timeout
    service_account_email = google_service_account.compliance_function_sa.email
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      REGION       = var.region
      PROCESSOR_ID = google_document_ai_processor.compliance_processor.name
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.compliance_documents.name
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles
  ]
}

# Archive source code for report generation function
data "archive_file" "report_generator_source" {
  type        = "zip"
  output_path = "/tmp/report-generator.zip"
  
  source {
    content = templatefile("${path.module}/functions/report_generator.py", {
      compliance_bucket = google_storage_bucket.compliance_documents.name
      reports_bucket    = google_storage_bucket.compliance_reports.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Storage object for report generator function source
resource "google_storage_bucket_object" "report_generator_source" {
  name   = "functions/report-generator-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.compliance_documents.name
  source = data.archive_file.report_generator_source.output_path
  
  depends_on = [data.archive_file.report_generator_source]
}

# Cloud Function for report generation
resource "google_cloudfunctions2_function" "report_generator" {
  name     = "${local.name_prefix}-report-gen-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_compliance_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.compliance_documents.name
        object = google_storage_bucket_object.report_generator_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.cloud_function_memory}Mi"
    timeout_seconds       = var.cloud_function_timeout
    service_account_email = google_service_account.compliance_function_sa.email
    
    environment_variables = {
      COMPLIANCE_BUCKET = google_storage_bucket.compliance_documents.name
      REPORTS_BUCKET    = google_storage_bucket.compliance_reports.name
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles
  ]
}

# Archive source code for log analytics function
data "archive_file" "log_analytics_source" {
  type        = "zip"
  output_path = "/tmp/log-analytics.zip"
  
  source {
    content = templatefile("${path.module}/functions/log_analytics.py", {
      compliance_bucket = google_storage_bucket.compliance_documents.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Storage object for log analytics function source
resource "google_storage_bucket_object" "log_analytics_source" {
  name   = "functions/log-analytics-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.compliance_documents.name
  source = data.archive_file.log_analytics_source.output_path
  
  depends_on = [data.archive_file.log_analytics_source]
}

# Cloud Function for log analytics
resource "google_cloudfunctions2_function" "log_analytics" {
  name     = "${local.name_prefix}-log-analytics-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "analyze_compliance_logs"
    
    source {
      storage_source {
        bucket = google_storage_bucket.compliance_documents.name
        object = google_storage_bucket_object.log_analytics_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = "${var.cloud_function_memory}Mi"
    timeout_seconds       = var.cloud_function_timeout
    service_account_email = google_service_account.compliance_function_sa.email
    
    environment_variables = {
      COMPLIANCE_BUCKET = google_storage_bucket.compliance_documents.name
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles
  ]
}

# ======================================
# CLOUD SCHEDULER FOR AUTOMATION
# ======================================

# Scheduled job for compliance report generation
resource "google_cloud_scheduler_job" "compliance_report_job" {
  name             = "${local.name_prefix}-report-job-${local.resource_suffix}"
  description      = "Automated compliance report generation"
  schedule         = var.report_schedule
  time_zone        = "UTC"
  attempt_deadline = "320s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.report_generator.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    
    body = base64encode(jsonencode({
      report_type = "scheduled"
      frameworks  = var.compliance_frameworks
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.report_generator
  ]
}

# Scheduled job for compliance analytics
resource "google_cloud_scheduler_job" "compliance_analytics_job" {
  name             = "${local.name_prefix}-analytics-job-${local.resource_suffix}"
  description      = "Daily compliance log analytics processing"
  schedule         = var.analytics_schedule
  time_zone        = "UTC"
  attempt_deadline = "320s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.log_analytics.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
    
    body = base64encode(jsonencode({
      analysis_type = "daily"
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.log_analytics
  ]
}

# ======================================
# MONITORING AND ALERTING
# ======================================

# Log-based metric for compliance violations
resource "google_logging_metric" "compliance_violations" {
  name   = "${local.name_prefix}_compliance_violations"
  filter = "protoPayload.authenticationInfo.principalEmail!=\"\" AND httpRequest.status>=400"
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Compliance Violations"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log-based metric for document processing success
resource "google_logging_metric" "document_processing_success" {
  name   = "${local.name_prefix}_document_processing_success"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"Successfully processed compliance document\""
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Document Processing Success"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Notification channel for compliance alerts
resource "google_monitoring_notification_channel" "compliance_email" {
  display_name = "Compliance Team Email"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for compliance violations
resource "google_monitoring_alert_policy" "compliance_violation_alert" {
  display_name = "High Volume Compliance Violations"
  combiner     = "OR"
  
  conditions {
    display_name = "High volume of failed access attempts"
    
    condition_threshold {
      filter          = "resource.type=\"audited_resource\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.compliance_violations.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.compliance_email.name]
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.compliance_violations
  ]
}

# ======================================
# DATA SOURCES
# ======================================

# Current project information
data "google_project" "current" {
  project_id = var.project_id
}