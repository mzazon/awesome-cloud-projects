# Global Financial Compliance Monitoring with Cloud Spanner and Cloud Tasks
# This file contains the main infrastructure resources for the compliance monitoring system

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common resource naming
  base_name = "${var.resource_prefix}-${var.environment}"
  suffix    = random_id.suffix.hex
  
  # Resource names with unique suffixes
  spanner_instance_name = "${local.base_name}-instance-${local.suffix}"
  spanner_database_name = "${local.base_name}-db"
  task_queue_name       = "${local.base_name}-queue"
  service_account_name  = "${local.base_name}-sa-${local.suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
    component   = "financial-compliance"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "spanner.googleapis.com",
    "cloudtasks.googleapis.com",
    "cloudfunctions.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com"
  ])

  service = each.value
  
  # Prevent destruction of APIs to avoid service disruption
  disable_on_destroy = false
}

# Service Account for Compliance Processing
resource "google_service_account" "compliance_processor" {
  account_id   = local.service_account_name
  display_name = "Financial Compliance Processor"
  description  = "Service account for automated financial compliance processing"
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for service account
resource "google_project_iam_member" "spanner_database_user" {
  project = var.project_id
  role    = "roles/spanner.databaseUser"
  member  = "serviceAccount:${google_service_account.compliance_processor.email}"
}

resource "google_project_iam_member" "cloudtasks_enqueuer" {
  project = var.project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.compliance_processor.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.compliance_processor.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.compliance_processor.email}"
}

resource "google_project_iam_member" "pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.compliance_processor.email}"
}

resource "google_project_iam_member" "storage_object_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.compliance_processor.email}"
}

# Cloud Spanner Instance for Global Financial Data
resource "google_spanner_instance" "compliance_monitor" {
  config       = var.spanner_instance_config
  display_name = "Financial Compliance Monitor"
  name         = local.spanner_instance_name
  
  # Use either node count or processing units (not both)
  num_nodes = var.spanner_processing_units == null ? var.spanner_node_count : null
  processing_units = var.spanner_processing_units
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Spanner Database with Compliance Schema
resource "google_spanner_database" "financial_compliance" {
  instance = google_spanner_instance.compliance_monitor.name
  name     = local.spanner_database_name
  
  # Database schema DDL for financial compliance
  ddl = [
    # Transactions table with comprehensive compliance fields
    <<-EOT
    CREATE TABLE transactions (
      transaction_id STRING(36) NOT NULL,
      account_id STRING(36) NOT NULL,
      amount NUMERIC NOT NULL,
      currency STRING(3) NOT NULL,
      source_country STRING(2) NOT NULL,
      destination_country STRING(2) NOT NULL,
      transaction_type STRING(50) NOT NULL,
      timestamp TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
      compliance_status STRING(20) NOT NULL DEFAULT 'PENDING',
      risk_score NUMERIC,
      kyc_verified BOOL DEFAULT false,
      aml_checked BOOL DEFAULT false,
      regulatory_flags ARRAY<STRING(MAX)>,
      created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
      updated_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
    ) PRIMARY KEY (transaction_id)
    EOT,
    
    # Compliance checks table for audit trail
    <<-EOT
    CREATE TABLE compliance_checks (
      check_id STRING(36) NOT NULL,
      transaction_id STRING(36) NOT NULL,
      check_type STRING(50) NOT NULL,
      check_status STRING(20) NOT NULL,
      check_result JSON,
      checked_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
      checked_by STRING(100) NOT NULL,
      regulatory_requirement STRING(100)
    ) PRIMARY KEY (check_id),
    INTERLEAVE IN PARENT transactions ON DELETE CASCADE
    EOT,
    
    # Regulatory reports table
    <<-EOT
    CREATE TABLE regulatory_reports (
      report_id STRING(36) NOT NULL,
      report_type STRING(50) NOT NULL,
      jurisdiction STRING(2) NOT NULL,
      report_period_start TIMESTAMP NOT NULL,
      report_period_end TIMESTAMP NOT NULL,
      report_data JSON,
      generated_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
      status STRING(20) NOT NULL DEFAULT 'PENDING'
    ) PRIMARY KEY (report_id)
    EOT,
    
    # Compliance rules table
    <<-EOT
    CREATE TABLE compliance_rules (
      rule_id STRING(36) NOT NULL,
      rule_name STRING(100) NOT NULL,
      rule_type STRING(50) NOT NULL,
      jurisdiction STRING(2) NOT NULL,
      rule_definition JSON NOT NULL,
      effective_date TIMESTAMP NOT NULL,
      expiry_date TIMESTAMP,
      created_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
      updated_at TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
    ) PRIMARY KEY (rule_id)
    EOT
  ]
  
  deletion_protection = var.environment == "prod" ? true : false
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub Topic for Compliance Events
resource "google_pubsub_topic" "compliance_events" {
  name   = "${local.base_name}-events"
  labels = local.common_labels
  
  # Message retention for compliance audit
  message_retention_duration = "604800s" # 7 days
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Tasks Queue for Compliance Processing
resource "google_cloud_tasks_queue" "compliance_checks" {
  name     = local.task_queue_name
  location = var.region
  
  rate_limits {
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
    max_dispatches_per_second = 10
  }
  
  retry_config {
    max_attempts       = var.task_queue_max_attempts
    max_retry_duration = var.task_queue_max_retry_duration
    max_backoff        = "300s"
    min_backoff        = "10s"
    max_doublings      = 10
  }
  
  depends_on = [google_project_service.required_apis]
}

# Dead Letter Queue for Failed Compliance Checks
resource "google_cloud_tasks_queue" "compliance_checks_dlq" {
  name     = "${local.task_queue_name}-dlq"
  location = var.region
  
  rate_limits {
    max_concurrent_dispatches = 5
    max_dispatches_per_second = 1
  }
  
  retry_config {
    max_attempts       = 3
    max_retry_duration = "86400s" # 24 hours
    max_backoff        = "600s"
    min_backoff        = "60s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage Bucket for Compliance Reports
resource "google_storage_bucket" "compliance_reports" {
  name     = "${local.base_name}-reports-${local.suffix}"
  location = var.region
  
  # Uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Versioning for audit trail
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Encryption with Google-managed keys
  encryption {
    default_kms_key_name = null
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage Bucket for Function Source Code
resource "google_storage_bucket" "function_source" {
  name     = "${local.base_name}-functions-${local.suffix}"
  location = var.region
  
  uniform_bucket_level_access = true
  
  # Function source doesn't need long retention
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create source code archives for Cloud Functions
data "archive_file" "compliance_processor_source" {
  type        = "zip"
  output_path = "${path.module}/compliance-processor.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/compliance-processor.py", {
      spanner_instance = google_spanner_instance.compliance_monitor.name
      spanner_database = google_spanner_database.financial_compliance.name
      project_id       = var.project_id
      compliance_rules = var.compliance_rules
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function-templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "transaction_processor_source" {
  type        = "zip"
  output_path = "${path.module}/transaction-processor.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/transaction-processor.py", {
      spanner_instance = google_spanner_instance.compliance_monitor.name
      spanner_database = google_spanner_database.financial_compliance.name
      project_id       = var.project_id
      topic_name       = google_pubsub_topic.compliance_events.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function-templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "compliance_reporter_source" {
  type        = "zip"
  output_path = "${path.module}/compliance-reporter.zip"
  
  source {
    content = templatefile("${path.module}/function-templates/compliance-reporter.py", {
      spanner_instance = google_spanner_instance.compliance_monitor.name
      spanner_database = google_spanner_database.financial_compliance.name
      project_id       = var.project_id
      bucket_name      = google_storage_bucket.compliance_reports.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function-templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "compliance_processor_source" {
  name   = "compliance-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.compliance_processor_source.output_path
}

resource "google_storage_bucket_object" "transaction_processor_source" {
  name   = "transaction-processor-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.transaction_processor_source.output_path
}

resource "google_storage_bucket_object" "compliance_reporter_source" {
  name   = "compliance-reporter-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.compliance_reporter_source.output_path
}

# Cloud Function for Compliance Processing
resource "google_cloudfunctions2_function" "compliance_processor" {
  name     = "${local.base_name}-processor"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "process_compliance_check"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.compliance_processor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.compliance_processor.email
    
    environment_variables = {
      SPANNER_INSTANCE = google_spanner_instance.compliance_monitor.name
      SPANNER_DATABASE = google_spanner_database.financial_compliance.name
      PROJECT_ID       = var.project_id
      ENVIRONMENT      = var.environment
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.compliance_events.id
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Function for Transaction Processing API
resource "google_cloudfunctions2_function" "transaction_processor" {
  name     = "${local.base_name}-api"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "process_transaction"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.transaction_processor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = 60
    service_account_email = google_service_account.compliance_processor.email
    
    environment_variables = {
      SPANNER_INSTANCE = google_spanner_instance.compliance_monitor.name
      SPANNER_DATABASE = google_spanner_database.financial_compliance.name
      PROJECT_ID       = var.project_id
      TOPIC_NAME       = google_pubsub_topic.compliance_events.name
      ENVIRONMENT      = var.environment
    }
    
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Function for Compliance Reporting
resource "google_cloudfunctions2_function" "compliance_reporter" {
  name     = "${local.base_name}-reporter"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_compliance_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.compliance_reporter_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = var.function_min_instances
    available_memory      = "1024M"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.compliance_processor.email
    
    environment_variables = {
      SPANNER_INSTANCE = google_spanner_instance.compliance_monitor.name
      SPANNER_DATABASE = google_spanner_database.financial_compliance.name
      PROJECT_ID       = var.project_id
      BUCKET_NAME      = google_storage_bucket.compliance_reports.name
      ENVIRONMENT      = var.environment
    }
    
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding to allow public access to transaction API (restrict in production)
resource "google_cloudfunctions2_function_iam_member" "transaction_processor_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.transaction_processor.location
  cloud_function = google_cloudfunctions2_function.transaction_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "compliance_reporter_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.compliance_reporter.location
  cloud_function = google_cloudfunctions2_function.compliance_reporter.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Log Sink for Compliance Audit Trail
resource "google_logging_project_sink" "compliance_audit_sink" {
  count = var.enable_audit_logs ? 1 : 0
  
  name        = "${local.base_name}-audit-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.compliance_reports.name}"
  
  # Filter for compliance-related logs
  filter = <<-EOT
    resource.type="cloud_function" AND 
    (resource.labels.function_name="${google_cloudfunctions2_function.compliance_processor.name}" OR 
     resource.labels.function_name="${google_cloudfunctions2_function.transaction_processor.name}" OR
     resource.labels.function_name="${google_cloudfunctions2_function.compliance_reporter.name}")
  EOT
  
  # Grant sink writer permission to storage bucket
  unique_writer_identity = true
}

# Grant log sink write permissions to storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_audit_logs ? 1 : 0
  
  bucket = google_storage_bucket.compliance_reports.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.compliance_audit_sink[0].writer_identity
}

# Budget for cost monitoring
resource "google_billing_budget" "compliance_budget" {
  billing_account = data.google_billing_account.account.id
  display_name    = "${local.base_name}-budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    services = [
      "services/spanner.googleapis.com",
      "services/cloudtasks.googleapis.com",
      "services/cloudfunctions.googleapis.com",
      "services/storage.googleapis.com"
    ]
    
    labels = {
      purpose = "financial-compliance"
    }
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.budget_amount
    }
  }
  
  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value / 100
      spend_basis       = "CURRENT_SPEND"
    }
  }
  
  all_updates_rule {
    monitoring_notification_channels = var.enable_monitoring ? [
      google_monitoring_notification_channel.email[0].id
    ] : []
  }
}

# Get billing account for budget
data "google_billing_account" "account" {
  billing_account = data.google_project.current.billing_account
}

data "google_project" "current" {
  project_id = var.project_id
}

# Monitoring notification channel
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Compliance Team Email"
  type         = "email"
  
  labels = {
    email_address = "compliance-team@example.com" # Replace with actual email
  }
}

# Monitoring alert policies
resource "google_monitoring_alert_policy" "high_risk_transactions" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Risk Transaction Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "High risk score transactions"
    
    condition_threshold {
      filter          = "resource.type=\"spanner_database\" AND metric.type=\"spanner.googleapis.com/api/request_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}