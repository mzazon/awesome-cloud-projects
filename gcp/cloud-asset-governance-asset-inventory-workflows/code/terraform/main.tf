# Main Terraform Configuration for Cloud Asset Governance System
# This file creates a comprehensive governance infrastructure using Cloud Asset Inventory,
# Cloud Workflows, Cloud Functions, and supporting services for automated compliance monitoring.

# Generate random suffix for unique resource naming
resource "random_id" "governance_suffix" {
  byte_length = 3
  
  keepers = {
    project_id = var.project_id
  }
}

# Local values for consistent resource naming and configuration
locals {
  # Use provided suffix or generate random one
  governance_suffix = var.governance_suffix != "" ? var.governance_suffix : "gov-${random_id.governance_suffix.hex}"
  
  # Resource naming with consistent patterns
  governance_bucket_name = "${var.project_id}-governance-${local.governance_suffix}"
  asset_topic_name       = "asset-changes-${local.governance_suffix}"
  workflow_subscription  = "workflow-processor-${local.governance_suffix}"
  governance_sa_name     = "governance-engine-${local.governance_suffix}"
  bq_dataset_id         = "asset_governance_${replace(local.governance_suffix, "-", "_")}"
  feed_name             = "governance-feed-${local.governance_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.governance_labels, {
    governance-system = "cloud-asset-governance"
    deployment-id     = local.governance_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for governance artifacts and policies
resource "google_storage_bucket" "governance_bucket" {
  name     = local.governance_bucket_name
  location = var.region
  project  = var.project_id
  
  # Storage configuration for compliance and cost optimization
  storage_class                   = var.storage_class
  uniform_bucket_level_access     = var.enable_uniform_bucket_access
  public_access_prevention        = "enforced"
  force_destroy                   = false
  
  # Versioning for audit trail compliance
  versioning {
    enabled = var.enable_bucket_versioning
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
  
  # Security and compliance configuration
  encryption {
    default_kms_key_name = google_kms_crypto_key.governance_key.id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_member.storage_encryption
  ]
}

# Create folder structure in governance bucket
resource "google_storage_bucket_object" "governance_folders" {
  for_each = toset(["policies/", "reports/", "workflows/", "templates/"])
  
  name         = each.value
  content      = "# Governance folder: ${each.value}"
  bucket       = google_storage_bucket.governance_bucket.name
  content_type = "text/plain"
}

# KMS key ring for encryption
resource "google_kms_key_ring" "governance_keyring" {
  name     = "governance-keyring-${local.governance_suffix}"
  location = var.region
  project  = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# KMS crypto key for governance data encryption
resource "google_kms_crypto_key" "governance_key" {
  name     = "governance-key-${local.governance_suffix}"
  key_ring = google_kms_key_ring.governance_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  # Key rotation for security best practices
  rotation_period = "7776000s" # 90 days
  
  labels = local.common_labels
}

# IAM binding for storage service to use KMS key
resource "google_kms_crypto_key_iam_member" "storage_encryption" {
  crypto_key_id = google_kms_crypto_key.governance_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# BigQuery dataset for governance analytics and compliance reporting
resource "google_bigquery_dataset" "governance_dataset" {
  dataset_id  = local.bq_dataset_id
  project     = var.project_id
  location    = var.bigquery_location
  description = "Cloud Asset Governance Analytics Dataset for compliance monitoring and reporting"
  
  # Data governance and access control
  default_table_expiration_ms = 31536000000 # 1 year retention
  delete_contents_on_destroy  = false
  
  labels = local.common_labels
  
  # Access control for governance team
  access {
    role          = "OWNER"
    user_by_email = "governance-admin@${var.project_id}.iam.gserviceaccount.com"
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for asset violation tracking
resource "google_bigquery_table" "asset_violations" {
  dataset_id = google_bigquery_dataset.governance_dataset.dataset_id
  table_id   = "asset_violations"
  project    = var.project_id
  
  description = "Table for tracking governance policy violations across cloud assets"
  
  # Schema definition for violation tracking
  schema = jsonencode([
    {
      name = "violation_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the violation"
    },
    {
      name = "resource_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Full resource name of the violating asset"
    },
    {
      name = "policy_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Name of the governance policy that was violated"
    },
    {
      name = "violation_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Description of the specific violation"
    },
    {
      name = "severity"
      type = "STRING"
      mode = "REQUIRED"
      description = "Severity level: HIGH, MEDIUM, LOW"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the violation was detected"
    },
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Project containing the violating resource"
    },
    {
      name = "remediation_status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Current remediation status: DETECTED, IN_PROGRESS, RESOLVED, IGNORED"
    },
    {
      name = "asset_type"
      type = "STRING"
      mode = "NULLABLE"
      description = "Type of the Google Cloud asset"
    },
    {
      name = "remediation_actions"
      type = "STRING"
      mode = "REPEATED"
      description = "List of recommended or taken remediation actions"
    }
  ])
  
  # Table clustering and partitioning for performance
  time_partitioning {
    type          = "DAY"
    field         = "timestamp"
    expiration_ms = 31536000000 # 1 year
  }
  
  clustering = ["project_id", "severity", "policy_name"]
  
  labels = local.common_labels
}

# BigQuery table for compliance reporting
resource "google_bigquery_table" "compliance_reports" {
  dataset_id = google_bigquery_dataset.governance_dataset.dataset_id
  table_id   = "compliance_reports"
  project    = var.project_id
  
  description = "Table for storing periodic compliance assessment reports"
  
  schema = jsonencode([
    {
      name = "report_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the compliance report"
    },
    {
      name = "scan_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the compliance scan was performed"
    },
    {
      name = "total_resources"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Total number of resources scanned"
    },
    {
      name = "violations_found"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Total number of policy violations found"
    },
    {
      name = "high_severity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of high severity violations"
    },
    {
      name = "medium_severity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of medium severity violations"
    },
    {
      name = "low_severity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of low severity violations"
    },
    {
      name = "compliance_score"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Overall compliance score (0-100)"
    },
    {
      name = "scan_scope"
      type = "STRING"
      mode = "NULLABLE"
      description = "Scope of the compliance scan (organization, folder, project)"
    },
    {
      name = "policy_versions"
      type = "RECORD"
      mode = "REPEATED"
      description = "Versions of policies used in the scan"
      fields = [
        {
          name = "policy_name"
          type = "STRING"
          mode = "REQUIRED"
        },
        {
          name = "version"
          type = "STRING"
          mode = "REQUIRED"
        }
      ]
    }
  ])
  
  time_partitioning {
    type          = "DAY"
    field         = "scan_timestamp"
    expiration_ms = 94608000000 # 3 years
  }
  
  labels = local.common_labels
}

# Pub/Sub topic for asset change notifications
resource "google_pubsub_topic" "asset_changes" {
  name    = local.asset_topic_name
  project = var.project_id
  
  # Message retention for audit and replay capabilities
  message_retention_duration = "${var.message_retention_days * 24}h"
  
  # Message storage policy for compliance
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for workflow processing
resource "google_pubsub_subscription" "workflow_processor" {
  name    = local.workflow_subscription
  topic   = google_pubsub_topic.asset_changes.name
  project = var.project_id
  
  # Subscription configuration for reliable processing
  ack_deadline_seconds       = 600
  message_retention_duration = "${var.message_retention_days * 24}h"
  retain_acked_messages      = true
  
  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Exponential backoff for retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

# Dead letter topic for failed governance messages
resource "google_pubsub_topic" "dead_letter" {
  name    = "governance-dead-letter-${local.governance_suffix}"
  project = var.project_id
  
  message_retention_duration = "168h" # 7 days
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Service account for governance operations
resource "google_service_account" "governance_engine" {
  account_id   = local.governance_sa_name
  display_name = "Cloud Asset Governance Engine"
  description  = "Service account for automated governance operations and policy enforcement"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for governance service account - Organization level permissions
resource "google_organization_iam_member" "cloudasset_viewer" {
  org_id = var.organization_id
  role   = "roles/cloudasset.viewer"
  member = "serviceAccount:${google_service_account.governance_engine.email}"
}

# Project-level IAM bindings for governance operations
resource "google_project_iam_member" "governance_permissions" {
  for_each = toset([
    "roles/workflows.invoker",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/pubsub.subscriber",
    "roles/pubsub.publisher",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudfunctions.invoker"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.governance_engine.email}"
}

# Create ZIP archive for policy evaluation function
data "archive_file" "policy_function_zip" {
  type        = "zip"
  output_path = "/tmp/governance-policy-function-${local.governance_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/policy_evaluator.py", {
      governance_suffix = local.governance_suffix
      project_id       = var.project_id
      dataset_id       = local.bq_dataset_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to storage
resource "google_storage_bucket_object" "policy_function_source" {
  name   = "function-source/governance-policy-evaluator-${local.governance_suffix}.zip"
  bucket = google_storage_bucket.governance_bucket.name
  source = data.archive_file.policy_function_zip.output_path
  
  # Trigger function deployment on source changes
  content_encoding = "gzip"
  
  depends_on = [data.archive_file.policy_function_zip]
}

# Cloud Function for policy evaluation
resource "google_cloudfunctions2_function" "policy_evaluator" {
  name        = "governance-policy-evaluator-${local.governance_suffix}"
  location    = var.region
  project     = var.project_id
  description = "Evaluates cloud assets against governance policies and records violations"
  
  build_config {
    runtime     = "python311"
    entry_point = "evaluate_governance_policy"
    
    source {
      storage_source {
        bucket = google_storage_bucket.governance_bucket.name
        object = google_storage_bucket_object.policy_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.max_function_instances
    min_instance_count = 0
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    
    # Environment variables for function configuration
    environment_variables = {
      GOVERNANCE_SUFFIX = local.governance_suffix
      PROJECT_ID       = var.project_id
      DATASET_ID       = local.bq_dataset_id
      REGION           = var.region
    }
    
    # Security configuration
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.governance_engine.email
  }
  
  # Event trigger for HTTP requests
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.asset_changes.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.policy_function_source
  ]
}

# Create ZIP archive for workflow trigger function
data "archive_file" "workflow_trigger_zip" {
  type        = "zip"
  output_path = "/tmp/governance-workflow-trigger-${local.governance_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/workflow_trigger.py", {
      governance_suffix = local.governance_suffix
      project_id       = var.project_id
      region           = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload workflow trigger function source
resource "google_storage_bucket_object" "workflow_trigger_source" {
  name   = "function-source/governance-workflow-trigger-${local.governance_suffix}.zip"
  bucket = google_storage_bucket.governance_bucket.name
  source = data.archive_file.workflow_trigger_zip.output_path
  
  depends_on = [data.archive_file.workflow_trigger_zip]
}

# Cloud Function to trigger workflow from Pub/Sub
resource "google_cloudfunctions2_function" "workflow_trigger" {
  name        = "governance-workflow-trigger-${local.governance_suffix}"
  location    = var.region
  project     = var.project_id
  description = "Triggers governance workflow execution from Pub/Sub asset change notifications"
  
  build_config {
    runtime     = "python311"
    entry_point = "trigger_governance_workflow"
    
    source {
      storage_source {
        bucket = google_storage_bucket.governance_bucket.name
        object = google_storage_bucket_object.workflow_trigger_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.max_function_instances
    available_memory   = "256M"
    timeout_seconds    = 60
    
    environment_variables = {
      GOVERNANCE_SUFFIX = local.governance_suffix
      PROJECT_ID       = var.project_id
      REGION           = var.region
      WORKFLOW_NAME    = "governance-orchestrator-${local.governance_suffix}"
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.governance_engine.email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.asset_changes.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.workflow_trigger_source
  ]
}

# Cloud Workflow for governance orchestration
resource "google_workflows_workflow" "governance_orchestrator" {
  name        = "governance-orchestrator-${local.governance_suffix}"
  region      = var.region
  project     = var.project_id
  description = var.workflow_description
  
  # Workflow definition in YAML format
  source_contents = templatefile("${path.module}/workflow_definitions/governance_workflow.yaml", {
    project_id        = var.project_id
    governance_suffix = local.governance_suffix
    region           = var.region
    function_url     = "https://${var.region}-${var.project_id}.cloudfunctions.net/governance-policy-evaluator-${local.governance_suffix}"
  })
  
  service_account = google_service_account.governance_engine.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.policy_evaluator
  ]
}

# IAM binding for Cloud Asset Inventory service to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "asset_publisher" {
  topic   = google_pubsub_topic.asset_changes.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudasset.iam.gserviceaccount.com"
  project = var.project_id
}

# Cloud Asset Inventory feed for organization-wide monitoring
resource "google_cloud_asset_organization_feed" "governance_feed" {
  billing_project  = var.project_id
  org_id          = var.organization_id
  feed_id         = local.feed_name
  content_type    = var.content_type
  
  # Asset types to monitor for governance
  asset_types = var.asset_types_to_monitor
  
  # Pub/Sub destination for asset change notifications
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }
  
  # Condition to filter which assets trigger notifications
  condition {
    expression = "!temporal_asset.deleted && (temporal_asset.prior_asset_state == google.cloud.asset.v1.TemporalAsset.PriorAssetState.DOES_NOT_EXIST || temporal_asset.prior_asset != temporal_asset.asset)"
    title      = "Governance Asset Filter"
    description = "Monitor asset creation and updates for governance compliance"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic_iam_member.asset_publisher
  ]
}

# Cloud Monitoring notification channel for governance alerts
resource "google_monitoring_notification_channel" "governance_email" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Governance Violations Email"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
  
  description = "Email notifications for governance policy violations"
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for high severity governance violations
resource "google_monitoring_alert_policy" "high_severity_violations" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "High Severity Governance Violations"
  project      = var.project_id
  
  combiner = "OR"
  
  conditions {
    display_name = "High Severity Violation Rate"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"custom.googleapis.com/governance/violations\" AND metadata.user_labels.severity=\"HIGH\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = ["resource.project_id"]
      }
    }
  }
  
  # Alert routing to notification channels
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.governance_email[0].name]
    }
  }
  
  documentation {
    content = "High severity governance policy violations detected. Immediate review and remediation required."
    mime_type = "text/markdown"
  }
  
  depends_on = [google_project_service.required_apis]
}