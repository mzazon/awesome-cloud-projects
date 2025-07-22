# Main Terraform Configuration for Document Validation Workflows
# This file defines the complete infrastructure for an intelligent document
# validation pipeline using Google Cloud Document AI, Cloud Workflows, and other services.

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Generate unique resource names with random suffix
  resource_suffix = lower(random_id.suffix.hex)
  
  # Common naming patterns
  common_name = "${var.resource_name_prefix}-${var.environment}-${local.resource_suffix}"
  
  # Storage bucket names (must be globally unique)
  input_bucket_name   = "${local.common_name}-input"
  valid_bucket_name   = "${local.common_name}-valid"
  invalid_bucket_name = "${local.common_name}-invalid"
  review_bucket_name  = "${local.common_name}-review"
  
  # BigQuery dataset name (replace hyphens with underscores)
  dataset_name = replace("${local.common_name}_analytics", "-", "_")
  
  # Service account names
  eventarc_sa_name = "${local.common_name}-eventarc-sa"
  
  # Workflow name
  workflow_name = "${local.common_name}-workflow"
  
  # Processor names
  form_processor_name    = "${local.common_name}-form-processor"
  invoice_processor_name = "${local.common_name}-invoice-processor"
  
  # Common labels with computed values
  common_labels = merge(var.labels, {
    environment = var.environment
    suffix      = local.resource_suffix
  })
}

# Enable required APIs for the project
resource "google_project_service" "required_apis" {
  for_each = toset([
    "documentai.googleapis.com",
    "workflows.googleapis.com",
    "storage.googleapis.com",
    "eventarc.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Wait for APIs to be fully enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# ================================
# DOCUMENT AI PROCESSORS
# ================================

# Form Parser processor for structured documents
resource "google_document_ai_processor" "form_parser" {
  location     = var.document_ai_location
  display_name = var.form_processor_display_name
  type         = "FORM_PARSER_PROCESSOR"
  
  # Ensure APIs are enabled before creating processors
  depends_on = [time_sleep.wait_for_apis]
  
  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# Invoice Parser processor for financial documents
resource "google_document_ai_processor" "invoice_parser" {
  location     = var.document_ai_location
  display_name = var.invoice_processor_display_name
  type         = "INVOICE_PROCESSOR"
  
  # Ensure APIs are enabled before creating processors
  depends_on = [time_sleep.wait_for_apis]
  
  timeouts {
    create = "5m"
    delete = "5m"
  }
}

# ================================
# CLOUD STORAGE BUCKETS
# ================================

# Input bucket for document uploads
resource "google_storage_bucket" "input" {
  name          = local.input_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security settings
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_rules ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Apply labels
  labels = merge(local.common_labels, {
    bucket_type = "input"
    purpose     = "document-upload"
  })
  
  # Ensure APIs are enabled
  depends_on = [time_sleep.wait_for_apis]
}

# Valid documents bucket
resource "google_storage_bucket" "valid" {
  name          = local.valid_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security settings
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_rules ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Apply labels
  labels = merge(local.common_labels, {
    bucket_type = "valid"
    purpose     = "validated-documents"
  })
  
  # Ensure APIs are enabled
  depends_on = [time_sleep.wait_for_apis]
}

# Invalid documents bucket
resource "google_storage_bucket" "invalid" {
  name          = local.invalid_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security settings
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_rules ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Apply labels
  labels = merge(local.common_labels, {
    bucket_type = "invalid"
    purpose     = "rejected-documents"
  })
  
  # Ensure APIs are enabled
  depends_on = [time_sleep.wait_for_apis]
}

# Review bucket for documents needing human review
resource "google_storage_bucket" "review" {
  name          = local.review_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Security settings
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_rules ? [1] : []
    content {
      condition {
        age = var.lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Apply labels
  labels = merge(local.common_labels, {
    bucket_type = "review"
    purpose     = "human-review-required"
  })
  
  # Ensure APIs are enabled
  depends_on = [time_sleep.wait_for_apis]
}

# ================================
# BIGQUERY DATASET AND TABLE
# ================================

# BigQuery dataset for document analytics
resource "google_bigquery_dataset" "document_analytics" {
  dataset_id    = local.dataset_name
  friendly_name = "Document Processing Analytics"
  description   = var.dataset_description
  location      = var.bigquery_location
  
  # Set table expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.table_expiration_days > 0 ? [var.table_expiration_days * 24 * 60 * 60 * 1000] : []
    content {
      default_table_expiration_ms = default_table_expiration_ms.value
    }
  }
  
  # Access control - default to project editors and owners
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  
  access {
    role          = "WRITER"
    special_group = "projectEditors"
  }
  
  access {
    role          = "READER"
    special_group = "projectViewers"
  }
  
  # Apply labels
  labels = merge(local.common_labels, {
    dataset_type = "analytics"
    purpose      = "document-processing-metrics"
  })
  
  # Ensure APIs are enabled
  depends_on = [time_sleep.wait_for_apis]
}

# BigQuery table for processing results
resource "google_bigquery_table" "processing_results" {
  dataset_id = google_bigquery_dataset.document_analytics.dataset_id
  table_id   = "processing_results"
  
  description = "Document processing results and validation metrics"
  
  # Define table schema
  schema = jsonencode([
    {
      name = "document_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the processed document"
    },
    {
      name = "processor_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of processor used (form, invoice, general)"
    },
    {
      name = "processing_time"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the document was processed"
    },
    {
      name = "validation_status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Validation result (valid, invalid, needs_review)"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average confidence score of extracted data"
    },
    {
      name = "extracted_fields"
      type = "JSON"
      mode = "NULLABLE"
      description = "JSON object containing extracted field data"
    },
    {
      name = "validation_errors"
      type = "JSON"
      mode = "NULLABLE"
      description = "JSON array of validation errors encountered"
    }
  ])
  
  # Time-based partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "processing_time"
  }
  
  # Clustering for query optimization
  clustering = ["validation_status", "processor_type"]
  
  # Apply labels
  labels = merge(local.common_labels, {
    table_type = "processing_results"
    purpose    = "document-analytics"
  })
  
  # Enable deletion protection if specified
  deletion_protection = var.enable_deletion_protection
}

# ================================
# CLOUD WORKFLOWS
# ================================

# Cloud Workflows workflow for document processing
resource "google_workflows_workflow" "document_validation" {
  name        = local.workflow_name
  region      = var.region
  description = var.workflow_description
  
  # Configure logging
  call_log_level = var.workflow_call_log_level
  
  # Environment variables for the workflow
  user_env_vars = {
    FORM_PROCESSOR_ID    = google_document_ai_processor.form_parser.name
    INVOICE_PROCESSOR_ID = google_document_ai_processor.invoice_parser.name
    VALID_BUCKET         = google_storage_bucket.valid.name
    INVALID_BUCKET       = google_storage_bucket.invalid.name
    REVIEW_BUCKET        = google_storage_bucket.review.name
    DATASET_NAME         = google_bigquery_dataset.document_analytics.dataset_id
    CONFIDENCE_THRESHOLD = var.confidence_threshold
    MAX_VALIDATION_ERRORS = var.max_validation_errors
  }
  
  # Workflow definition using the template file
  source_contents = templatefile("${path.module}/workflow-template.yaml", {
    confidence_threshold     = var.confidence_threshold
    max_validation_errors    = var.max_validation_errors
    region                   = var.region
  })
  
  # Apply labels
  labels = merge(local.common_labels, {
    workflow_type = "document_validation"
    purpose       = "ai_document_processing"
  })
  
  # Ensure deletion protection if specified
  deletion_protection = var.enable_deletion_protection
  
  # Ensure all dependencies are ready
  depends_on = [
    google_document_ai_processor.form_parser,
    google_document_ai_processor.invoice_parser,
    google_storage_bucket.input,
    google_storage_bucket.valid,
    google_storage_bucket.invalid,
    google_storage_bucket.review,
    google_bigquery_dataset.document_analytics,
    google_bigquery_table.processing_results
  ]
}

# ================================
# IAM SERVICE ACCOUNTS
# ================================

# Service account for Eventarc trigger
resource "google_service_account" "eventarc_sa" {
  account_id   = local.eventarc_sa_name
  display_name = "Eventarc Service Account"
  description  = var.eventarc_service_account_description
  
  # Ensure APIs are enabled
  depends_on = [time_sleep.wait_for_apis]
}

# Grant Workflows invoker permission to Eventarc service account
resource "google_project_iam_member" "eventarc_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

# Grant Eventarc event receiver permission to Eventarc service account
resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

# Grant necessary permissions to the Compute Engine default service account for workflow execution
data "google_compute_default_service_account" "default" {
  depends_on = [time_sleep.wait_for_apis]
}

# Document AI API User permission
resource "google_project_iam_member" "compute_sa_documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# Storage Object Admin permission
resource "google_project_iam_member" "compute_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# BigQuery Data Editor permission
resource "google_project_iam_member" "compute_sa_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# BigQuery Job User permission
resource "google_project_iam_member" "compute_sa_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# ================================
# EVENTARC TRIGGER
# ================================

# Eventarc trigger for automatic document processing
resource "google_eventarc_trigger" "document_upload" {
  name     = "${local.common_name}-trigger"
  location = var.region
  
  # Match Cloud Storage object finalization events
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }
  
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.input.name
  }
  
  # Route events to Cloud Workflows
  destination {
    workflow = google_workflows_workflow.document_validation.id
  }
  
  # Use dedicated service account
  service_account = google_service_account.eventarc_sa.email
  
  # Apply labels
  labels = merge(local.common_labels, {
    trigger_type = "storage_object_finalized"
    purpose      = "document_processing_automation"
  })
  
  # Ensure all dependencies are ready
  depends_on = [
    google_service_account.eventarc_sa,
    google_project_iam_member.eventarc_workflows_invoker,
    google_project_iam_member.eventarc_event_receiver,
    google_workflows_workflow.document_validation
  ]
}

# ================================
# MONITORING AND LOGGING
# ================================

# Optional: Create a log sink for workflow execution logs
resource "google_logging_project_sink" "workflow_logs" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "${local.common_name}-workflow-logs"
  description = "Log sink for document validation workflow execution logs"
  
  # Send logs to BigQuery
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.document_analytics.dataset_id}"
  
  # Filter for workflow execution logs
  filter = <<-EOT
    resource.type="workflows.googleapis.com/Workflow"
    resource.labels.workflow_id="${google_workflows_workflow.document_validation.name}"
  EOT
  
  # Use a unique writer identity
  unique_writer_identity = true
  
  depends_on = [
    google_bigquery_dataset.document_analytics,
    google_workflows_workflow.document_validation
  ]
}

# Grant BigQuery Data Editor permission to the log sink writer
resource "google_project_iam_member" "log_sink_bigquery_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.workflow_logs[0].writer_identity
}

# ================================
# WORKFLOW DEFINITION FILE
# ================================
# Note: The workflow definition is embedded directly in the workflow resource
# using the templatefile function and the workflow-template.yaml file.