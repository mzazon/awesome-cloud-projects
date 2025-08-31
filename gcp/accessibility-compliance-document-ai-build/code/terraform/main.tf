# =====================================================
# Accessibility Compliance Infrastructure with Document AI and Cloud Build
# This Terraform configuration creates an automated accessibility compliance 
# testing system using Google Cloud services.
# =====================================================

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming
locals {
  resource_suffix = random_string.suffix.result
  bucket_name     = "${var.resource_prefix}-${var.environment}-${local.resource_suffix}"
  function_name   = "${var.resource_prefix}-notifier-${local.resource_suffix}"
  topic_name      = "${var.resource_prefix}-alerts-${local.resource_suffix}"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    component   = "accessibility-compliance"
  })
}

# =====================================================
# API Services
# Enable required Google Cloud APIs
# =====================================================

resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
  disable_on_destroy         = false
}

# =====================================================
# Document AI
# Create processor for content analysis and OCR
# =====================================================

resource "google_document_ai_processor" "accessibility_processor" {
  location     = var.region
  display_name = var.document_ai_processor_display_name
  type         = var.document_ai_processor_type
  project      = var.project_id

  depends_on = [
    google_project_service.required_apis["documentai.googleapis.com"]
  ]

  timeouts {
    create = "10m"
    delete = "10m"
  }
}

# =====================================================
# Cloud Storage
# Bucket for storing compliance reports and artifacts
# =====================================================

resource "google_storage_bucket" "compliance_reports" {
  name          = local.bucket_name
  location      = var.storage_bucket_location
  storage_class = var.storage_bucket_storage_class
  project       = var.project_id

  # Prevent accidental deletion
  force_destroy = false

  # Enable uniform bucket-level access
  uniform_bucket_level_access = true

  # Versioning for compliance audit trail
  versioning {
    enabled = true
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for old versions
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

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["storage.googleapis.com"]
  ]
}

# IAM binding for Cloud Build to access storage bucket
resource "google_storage_bucket_iam_member" "cloudbuild_storage_access" {
  bucket = google_storage_bucket.compliance_reports.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [
    google_project_service.required_apis["cloudbuild.googleapis.com"]
  ]
}

# =====================================================
# Pub/Sub
# Topic for compliance notifications
# =====================================================

resource "google_pubsub_topic" "compliance_alerts" {
  name    = local.topic_name
  project = var.project_id

  labels = local.common_labels

  # Message retention for 7 days
  message_retention_duration = "604800s"

  depends_on = [
    google_project_service.required_apis["pubsub.googleapis.com"]
  ]
}

# Subscription for Cloud Functions
resource "google_pubsub_subscription" "compliance_alerts_subscription" {
  name    = "${local.topic_name}-subscription"
  topic   = google_pubsub_topic.compliance_alerts.name
  project = var.project_id

  # Push configuration for Cloud Functions
  push_config {
    push_endpoint = google_cloudfunctions_function.compliance_notifier.https_trigger_url
  }

  # Acknowledgment deadline
  ack_deadline_seconds = 20

  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels
}

# =====================================================
# Security Command Center
# Source for accessibility compliance findings
# =====================================================

# Get organization data
data "google_organization" "org" {
  count  = var.organization_id != "" ? 1 : 0
  org_id = var.organization_id
}

resource "google_scc_source" "accessibility_compliance" {
  count = var.organization_id != "" ? 1 : 0
  
  display_name = var.scc_source_display_name
  organization = data.google_organization.org[0].name
  description  = var.scc_source_description

  depends_on = [
    google_project_service.required_apis["securitycenter.googleapis.com"]
  ]
}

# Notification configuration for Security Command Center
resource "google_scc_notification_config" "accessibility_alerts" {
  count = var.organization_id != "" ? 1 : 0

  config_id    = "accessibility-compliance-alerts"
  organization = data.google_organization.org[0].name
  description  = var.scc_notification_description
  
  pubsub_topic = google_pubsub_topic.compliance_alerts.id

  streaming_config {
    filter = "category=\"ACCESSIBILITY_COMPLIANCE\""
  }

  depends_on = [
    google_scc_source.accessibility_compliance[0]
  ]
}

# =====================================================
# Cloud Functions
# Function for processing compliance notifications
# =====================================================

# Create ZIP archive for Cloud Function source code
data "archive_file" "compliance_notifier_zip" {
  type        = "zip"
  output_path = "/tmp/compliance_notifier.zip"
  
  source {
    content = templatefile("${path.module}/templates/main.py.tpl", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to storage bucket
resource "google_storage_bucket_object" "compliance_notifier_source" {
  name   = "compliance_notifier_${data.archive_file.compliance_notifier_zip.output_md5}.zip"
  bucket = google_storage_bucket.compliance_reports.name
  source = data.archive_file.compliance_notifier_zip.output_path
}

# Cloud Function for processing compliance alerts
resource "google_cloudfunctions_function" "compliance_notifier" {
  name        = local.function_name
  project     = var.project_id
  region      = var.region
  description = "Process accessibility compliance alerts and send notifications"

  runtime     = var.function_runtime
  entry_point = "process_compliance_alert"

  # Function configuration
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout

  # Source code configuration
  source_archive_bucket = google_storage_bucket.compliance_reports.name
  source_archive_object = google_storage_bucket_object.compliance_notifier_source.name

  # Event trigger configuration
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.compliance_alerts.name
  }

  # Environment variables
  environment_variables = {
    PROJECT_ID     = var.project_id
    TOPIC_NAME     = google_pubsub_topic.compliance_alerts.name
    BUCKET_NAME    = google_storage_bucket.compliance_reports.name
    ENABLE_EMAIL   = var.enable_email_notifications
    NOTIFICATION_EMAIL = var.notification_email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_storage_bucket_object.compliance_notifier_source
  ]
}

# =====================================================
# Cloud Build
# Build trigger for automated accessibility testing
# =====================================================

# Cloud Build trigger for GitHub repositories
resource "google_cloudbuild_trigger" "accessibility_testing" {
  count = var.github_repo_name != "" && var.github_repo_owner != "" ? 1 : 0

  project     = var.project_id
  name        = "${var.resource_prefix}-accessibility-trigger"
  description = "Automated accessibility compliance testing"

  # GitHub trigger configuration
  github {
    owner = var.github_repo_owner
    name  = var.github_repo_name
    
    push {
      branch = var.build_trigger_branch_pattern
    }
  }

  # Build configuration file
  filename = var.build_config_filename

  # Substitution variables for the build
  substitutions = merge({
    _PROCESSOR_ID = google_document_ai_processor.accessibility_processor.name
    _BUCKET_NAME  = google_storage_bucket.compliance_reports.name
    _TOPIC_NAME   = google_pubsub_topic.compliance_alerts.name
    _PROJECT_ID   = var.project_id
    _REGION       = var.region
  }, var.build_substitutions)

  # Apply common labels
  tags = [for k, v in local.common_labels : "${k}:${v}"]

  depends_on = [
    google_project_service.required_apis["cloudbuild.googleapis.com"]
  ]
}

# Manual trigger for testing
resource "google_cloudbuild_trigger" "accessibility_manual" {
  project     = var.project_id
  name        = "${var.resource_prefix}-accessibility-manual"
  description = "Manual accessibility compliance testing trigger"

  # Manual trigger - no source repository
  trigger_template {
    project_id = var.project_id
    repo_name  = "manual-trigger"
  }

  # Build configuration file
  filename = var.build_config_filename

  # Substitution variables for the build
  substitutions = merge({
    _PROCESSOR_ID = google_document_ai_processor.accessibility_processor.name
    _BUCKET_NAME  = google_storage_bucket.compliance_reports.name
    _TOPIC_NAME   = google_pubsub_topic.compliance_alerts.name
    _PROJECT_ID   = var.project_id
    _REGION       = var.region
  }, var.build_substitutions)

  # Apply common labels
  tags = [for k, v in local.common_labels : "${k}:${v}"]

  depends_on = [
    google_project_service.required_apis["cloudbuild.googleapis.com"]
  ]
}

# =====================================================
# IAM Permissions
# Service account and permissions for Cloud Build
# =====================================================

# Get project information for service account references
data "google_project" "project" {
  project_id = var.project_id
}

# Create locals for project number reference
locals {
  project_number = data.google_project.project.number
}

# IAM binding for Cloud Build to use Document AI
resource "google_project_iam_member" "cloudbuild_documentai" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [
    google_project_service.required_apis["cloudbuild.googleapis.com"]
  ]
}

# IAM binding for Cloud Build to publish to Pub/Sub
resource "google_project_iam_member" "cloudbuild_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [
    google_project_service.required_apis["cloudbuild.googleapis.com"]
  ]
}

# IAM binding for Cloud Build to create Security Command Center findings
resource "google_project_iam_member" "cloudbuild_scc" {
  count = var.organization_id != "" ? 1 : 0
  
  project = var.project_id
  role    = "roles/securitycenter.findingsEditor"
  member  = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"

  depends_on = [
    google_project_service.required_apis["cloudbuild.googleapis.com"]
  ]
}

# IAM binding for Cloud Functions to access storage
resource "google_project_iam_member" "function_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_cloudfunctions_function.compliance_notifier.service_account_email}"
}

