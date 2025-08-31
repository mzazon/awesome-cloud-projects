# Main Terraform configuration for GCP Intelligent Resource Optimization
# This configuration deploys a complete AI-powered resource optimization system using
# Vertex AI Agent Builder, Cloud Asset Inventory, BigQuery, and Cloud Scheduler

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed configurations
locals {
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project-id  = var.project_id
  })
  
  # Unique resource names with random suffix
  dataset_name          = "${var.dataset_name}_${random_id.suffix.hex}"
  bucket_name          = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  scheduler_job_name   = "asset-export-${random_id.suffix.hex}"
  service_account_name = "asset-export-scheduler-${random_id.suffix.hex}"
  function_name        = "asset-export-trigger-${random_id.suffix.hex}"
}

# ================================
# API ENABLEMENT
# ================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudasset.googleapis.com",
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ]) : toset([])

  project                    = var.project_id
  service                   = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# ================================
# IAM SERVICE ACCOUNTS
# ================================

# Service account for Cloud Scheduler and asset export operations
resource "google_service_account" "asset_export_scheduler" {
  account_id   = local.service_account_name
  display_name = "Asset Export Scheduler Service Account"
  description  = "Service account for automated asset inventory exports to BigQuery"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Asset Viewer role to service account
resource "google_project_iam_member" "asset_viewer" {
  project = var.project_id
  role    = "roles/cloudasset.viewer"
  member  = "serviceAccount:${google_service_account.asset_export_scheduler.email}"
}

# Grant BigQuery Data Editor role to service account
resource "google_project_iam_member" "bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.asset_export_scheduler.email}"
}

# Grant BigQuery Job User role to service account
resource "google_project_iam_member" "bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.asset_export_scheduler.email}"
}

# Grant Cloud Functions Invoker role to service account
resource "google_project_iam_member" "functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.asset_export_scheduler.email}"
}

# Service account for Vertex AI Agent Engine
resource "google_service_account" "vertex_ai_agent" {
  account_id   = "vertex-ai-agent-${random_id.suffix.hex}"
  display_name = "Vertex AI Agent Service Account"
  description  = "Service account for Vertex AI Agent Engine resource optimization"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant Vertex AI User role to agent service account
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.vertex_ai_agent.email}"
}

# Grant BigQuery Data Viewer role to agent service account
resource "google_project_iam_member" "agent_bigquery_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.vertex_ai_agent.email}"
}

# Grant Storage Object Viewer role to agent service account
resource "google_service_account_iam_member" "agent_storage_access" {
  service_account_id = google_service_account.vertex_ai_agent.name
  role               = "roles/storage.objectViewer"
  member             = "serviceAccount:${google_service_account.vertex_ai_agent.email}"
}

# ================================
# STORAGE INFRASTRUCTURE
# ================================

# Cloud Storage bucket for Vertex AI Agent Engine staging and function code
resource "google_storage_bucket" "agent_staging" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id

  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true

  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Apply labels
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# ================================
# BIGQUERY INFRASTRUCTURE
# ================================

# BigQuery dataset for asset inventory and optimization analytics
resource "google_bigquery_dataset" "asset_optimization" {
  dataset_id    = local.dataset_name
  project       = var.project_id
  friendly_name = "Asset Optimization Analytics"
  description   = "BigQuery dataset for storing and analyzing cloud asset inventory data for cost optimization"
  location      = var.region

  # Configure data retention
  default_table_expiration_ms = var.retention_days * 24 * 60 * 60 * 1000

  # Apply labels
  labels = local.common_labels

  # Grant access to service accounts
  access {
    role          = "WRITER"
    user_by_email = google_service_account.asset_export_scheduler.email
  }

  access {
    role          = "READER"
    user_by_email = google_service_account.vertex_ai_agent.email
  }

  depends_on = [google_project_service.required_apis]
}

# BigQuery view for resource optimization analysis
resource "google_bigquery_table" "resource_optimization_analysis" {
  dataset_id = google_bigquery_dataset.asset_optimization.dataset_id
  table_id   = "resource_optimization_analysis"
  project    = var.project_id

  view {
    query = templatefile("${path.module}/sql/resource_optimization_analysis.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_dataset.asset_optimization]
}

# BigQuery view for cost impact summary
resource "google_bigquery_table" "cost_impact_summary" {
  dataset_id = google_bigquery_dataset.asset_optimization.dataset_id
  table_id   = "cost_impact_summary"
  project    = var.project_id

  view {
    query = templatefile("${path.module}/sql/cost_impact_summary.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_table.resource_optimization_analysis]
}

# BigQuery table for optimization metrics tracking
resource "google_bigquery_table" "optimization_metrics" {
  dataset_id = google_bigquery_dataset.asset_optimization.dataset_id
  table_id   = "optimization_metrics"
  project    = var.project_id

  schema = file("${path.module}/schemas/optimization_metrics.json")

  time_partitioning {
    type  = "DAY"
    field = "analysis_time"
  }

  clustering = ["optimization_category"]

  depends_on = [google_bigquery_dataset.asset_optimization]
}

# ================================
# CLOUD FUNCTIONS
# ================================

# Create zip file for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/tmp/function-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/asset_export_trigger.py", {
      project_id    = var.project_id
      dataset_name  = local.dataset_name
      asset_types   = jsonencode(var.asset_types)
      organization_id = var.organization_id
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.agent_staging.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function to trigger asset exports
resource "google_cloudfunctions_function" "asset_export_trigger" {
  name        = local.function_name
  project     = var.project_id
  region      = var.region
  description = "HTTP function to trigger Cloud Asset Inventory exports to BigQuery"

  runtime = "python310"

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.agent_staging.name
  source_archive_object = google_storage_bucket_object.function_source.name
  trigger {
    http_trigger {
      url = ""
    }
  }
  timeout = 60
  entry_point = "trigger_asset_export"

  service_account_email = google_service_account.asset_export_scheduler.email

  environment_variables = {
    PROJECT_ID       = var.project_id
    DATASET_NAME     = local.dataset_name
    ORGANIZATION_ID  = var.organization_id
    ASSET_TYPES      = jsonencode(var.asset_types)
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# ================================
# CLOUD SCHEDULER
# ================================

# Scheduled job for daily asset inventory exports
resource "google_cloud_scheduler_job" "asset_export" {
  name        = local.scheduler_job_name
  project     = var.project_id
  region      = var.region
  description = "Scheduled job for automated Cloud Asset Inventory exports to BigQuery"
  schedule    = var.export_schedule
  time_zone   = var.schedule_timezone

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.asset_export_trigger.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      organization_id = var.organization_id
      project_id      = var.project_id
      dataset_name    = local.dataset_name
      asset_types     = var.asset_types
    }))

    oidc_token {
      service_account_email = google_service_account.asset_export_scheduler.email
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.asset_export_trigger
  ]
}

# ================================
# MONITORING AND ALERTING
# ================================

# Monitoring alert policy for high optimization scores
resource "google_monitoring_alert_policy" "high_optimization_score" {
  display_name = "High-Impact Resource Optimization Alert"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High Optimization Score Detected"
    
    condition_threshold {
      filter         = "resource.type=\"bigquery_table\" AND resource.labels.table_id=\"optimization_metrics\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 10.0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "604800s"  # 7 days
  }

  notification_channels = var.monitoring_notification_channels

  documentation {
    content = "High-impact resource optimization opportunities detected. Review the optimization recommendations in BigQuery."
  }

  depends_on = [google_project_service.required_apis]
}

# ================================
# VERTEX AI AGENT CONFIGURATION
# ================================

# Note: Vertex AI Agent Engine deployment is typically done through the Python SDK
# as shown in the recipe. The following resources prepare the infrastructure.

# Cloud Storage bucket object for agent requirements
resource "google_storage_bucket_object" "agent_requirements" {
  name    = "agent/requirements.txt"
  bucket  = google_storage_bucket.agent_staging.name
  content = file("${path.module}/agent/requirements.txt")
}

# Cloud Storage bucket object for agent implementation
resource "google_storage_bucket_object" "agent_implementation" {
  name   = "agent/optimization_agent.py"
  bucket = google_storage_bucket.agent_staging.name
  content = templatefile("${path.module}/agent/optimization_agent.py", {
    project_id    = var.project_id
    region        = var.region
    bucket_name   = local.bucket_name
    dataset_name  = local.dataset_name
    model         = var.vertex_ai_model
    temperature   = var.agent_temperature
    max_tokens    = var.agent_max_tokens
  })
}

# ================================
# INITIAL DATA POPULATION
# ================================

# Trigger initial asset export using null_resource
resource "null_resource" "initial_asset_export" {
  triggers = {
    function_url = google_cloudfunctions_function.asset_export_trigger.https_trigger_url
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for function to be ready
      sleep 30
      
      # Trigger initial asset export
      curl -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{"organization_id":"${var.organization_id}","project_id":"${var.project_id}","dataset_name":"${local.dataset_name}","asset_types":${jsonencode(var.asset_types)}}' \
        "${google_cloudfunctions_function.asset_export_trigger.https_trigger_url}"
    EOT
  }

  depends_on = [
    google_cloudfunctions_function.asset_export_trigger,
    google_bigquery_dataset.asset_optimization
  ]
}