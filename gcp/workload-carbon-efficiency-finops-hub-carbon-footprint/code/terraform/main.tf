# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    carbon-efficiency = "enabled"
    finops-hub       = "integrated"
  })
  
  # Service account email
  service_account_email = google_service_account.carbon_efficiency.email
  
  # Function source paths
  correlation_function_source = "carbon-efficiency-function"
  optimization_function_source = "optimization-automation"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbilling.googleapis.com",
    "recommender.googleapis.com", 
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "workflows.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Service account for carbon efficiency monitoring
resource "google_service_account" "carbon_efficiency" {
  account_id   = "carbon-efficiency-sa-${local.resource_suffix}"
  display_name = "Carbon Efficiency Service Account"
  description  = "Service account for carbon footprint and FinOps monitoring"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "carbon_efficiency_roles" {
  for_each = toset([
    "roles/billing.carbonViewer",
    "roles/recommender.viewer", 
    "roles/monitoring.editor",
    "roles/cloudfunctions.invoker",
    "roles/logging.logWriter",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.carbon_efficiency.email}"
  
  depends_on = [google_service_account.carbon_efficiency]
}

# BigQuery dataset for FinOps Hub insights (conditional)
resource "google_bigquery_dataset" "carbon_efficiency" {
  count = var.create_bigquery_dataset ? 1 : 0
  
  dataset_id    = var.bigquery_dataset_id
  friendly_name = "Carbon Efficiency Analytics"
  description   = "Dataset for storing FinOps Hub insights and carbon efficiency data"
  location      = var.region
  project       = var.project_id
  
  default_table_expiration_ms = var.dataset_retention_days * 24 * 60 * 60 * 1000
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for FinOps Hub insights
resource "google_logging_project_sink" "finops_hub_insights" {
  count = var.create_bigquery_dataset ? 1 : 0
  
  name        = "finops-hub-insights-${local.resource_suffix}"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${var.bigquery_dataset_id}"
  
  filter = <<-EOT
    resource.type="global" AND 
    jsonPayload.source="finops-hub" OR
    jsonPayload.optimization_type EXISTS OR
    protoPayload.serviceName="recommender.googleapis.com"
  EOT
  
  unique_writer_identity = true
  
  bigquery_options {
    use_partitioned_tables = true
  }
  
  depends_on = [google_bigquery_dataset.carbon_efficiency]
}

# Grant BigQuery data editor role to log sink writer
resource "google_bigquery_dataset_iam_member" "log_sink_writer" {
  count = var.create_bigquery_dataset ? 1 : 0
  
  dataset_id = google_bigquery_dataset.carbon_efficiency[0].dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.finops_hub_insights[0].writer_identity
  
  depends_on = [google_logging_project_sink.finops_hub_insights]
}

# Create source code archives for Cloud Functions
data "archive_file" "correlation_function_zip" {
  type        = "zip"
  output_path = "${path.module}/correlation-function-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/correlation_main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/correlation_requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "optimization_function_zip" {
  type        = "zip"
  output_path = "${path.module}/optimization-function-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/optimization_main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/optimization_requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "carbon-efficiency-functions-${var.project_id}-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  uniform_bucket_level_access = true
  force_destroy = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "correlation_function_source" {
  name   = "correlation-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.correlation_function_zip.output_path
  
  depends_on = [data.archive_file.correlation_function_zip]
}

resource "google_storage_bucket_object" "optimization_function_source" {
  name   = "optimization-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.optimization_function_zip.output_path
  
  depends_on = [data.archive_file.optimization_function_zip]
}

# Carbon efficiency correlation Cloud Function
resource "google_cloudfunctions_function" "carbon_efficiency_correlator" {
  name        = "carbon-efficiency-correlator-${local.resource_suffix}"
  description = "Correlates FinOps Hub utilization insights with carbon footprint data"
  runtime     = "python39"
  region      = var.region
  project     = var.project_id
  
  available_memory_mb   = var.carbon_efficiency_memory
  timeout              = var.function_timeout
  entry_point          = "correlate_carbon_efficiency"
  service_account_email = google_service_account.carbon_efficiency.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.correlation_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    GCP_PROJECT        = var.project_id
    BILLING_ACCOUNT_ID = ""  # Will be set during deployment
    EFFICIENCY_THRESHOLD = tostring(var.carbon_efficiency_threshold)
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.carbon_efficiency,
    google_project_iam_member.carbon_efficiency_roles
  ]
}

# Pub/Sub topic for optimization triggers
resource "google_pubsub_topic" "carbon_optimization" {
  name    = "carbon-optimization-${local.resource_suffix}"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Carbon efficiency optimization Cloud Function
resource "google_cloudfunctions_function" "carbon_efficiency_optimizer" {
  name        = "carbon-efficiency-optimizer-${local.resource_suffix}"
  description = "Implements approved carbon efficiency optimizations"
  runtime     = "python39"
  region      = var.region
  project     = var.project_id
  
  available_memory_mb   = var.optimization_memory
  timeout              = var.function_timeout
  entry_point          = "optimize_carbon_efficiency"
  service_account_email = google_service_account.carbon_efficiency.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.optimization_function_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.carbon_optimization.name
  }
  
  environment_variables = {
    GCP_PROJECT     = var.project_id
    ENABLE_AUTOMATION = tostring(var.enable_automation)
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.carbon_efficiency,
    google_project_iam_member.carbon_efficiency_roles,
    google_pubsub_topic.carbon_optimization
  ]
}

# Cloud Workflows for carbon efficiency automation
resource "google_workflows_workflow" "carbon_efficiency" {
  name          = "carbon-efficiency-workflow-${local.resource_suffix}"
  region        = var.region
  project       = var.project_id
  description   = "Automated carbon efficiency analysis and reporting workflow"
  
  service_account = google_service_account.carbon_efficiency.email
  
  source_contents = templatefile("${path.module}/workflow_templates/carbon_efficiency_workflow.yaml", {
    project_id    = var.project_id
    function_url  = google_cloudfunctions_function.carbon_efficiency_correlator.https_trigger_url
    region        = var.region
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.carbon_efficiency_correlator
  ]
}

# Cloud Scheduler job for automated analysis
resource "google_cloud_scheduler_job" "carbon_efficiency" {
  name        = "carbon-efficiency-scheduler-${local.resource_suffix}"
  description = "Scheduled trigger for carbon efficiency analysis"
  schedule    = var.efficiency_analysis_schedule
  time_zone   = "UTC"
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.carbon_efficiency.name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        trigger = "scheduled"
      })
    }))
    
    oidc_token {
      service_account_email = google_service_account.carbon_efficiency.email
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.carbon_efficiency
  ]
}

# Custom metrics descriptors for carbon efficiency tracking
resource "google_monitoring_metric_descriptor" "carbon_efficiency_score" {
  type         = "custom.googleapis.com/carbon_efficiency/score"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "1"
  description  = "Carbon efficiency score based on FinOps Hub insights and carbon footprint"
  display_name = "Carbon Efficiency Score"
  project      = var.project_id
  
  labels {
    key         = "region"
    value_type  = "STRING"
    description = "Google Cloud region"
  }
  
  labels {
    key         = "service"
    value_type  = "STRING"
    description = "Google Cloud service"
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_monitoring_metric_descriptor" "optimization_impact" {
  type         = "custom.googleapis.com/optimization/carbon_impact"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "kg"
  description  = "Estimated carbon impact reduction from optimization actions"
  display_name = "Carbon Impact Reduction"
  project      = var.project_id
  
  labels {
    key         = "optimization_type"
    value_type  = "STRING"
    description = "Type of optimization applied"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring dashboard for carbon efficiency
resource "google_monitoring_dashboard" "carbon_efficiency" {
  dashboard_json = templatefile("${path.module}/dashboard_templates/carbon_efficiency_dashboard.json", {
    project_id = var.project_id
  })
  project = var.project_id
  
  depends_on = [
    google_monitoring_metric_descriptor.carbon_efficiency_score,
    google_monitoring_metric_descriptor.optimization_impact
  ]
}

# Alert policy for low carbon efficiency scores
resource "google_monitoring_alert_policy" "carbon_efficiency_alert" {
  display_name = "Carbon Efficiency Alert - ${local.resource_suffix}"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id
  
  conditions {
    display_name = "Low Carbon Efficiency Score"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/carbon_efficiency/score\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = var.carbon_efficiency_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_channels
    content {
      id = notification_channels.value
    }
  }
  
  documentation {
    content = <<-EOT
      Carbon efficiency score has dropped below ${var.carbon_efficiency_threshold}%.
      This indicates potential optimization opportunities for both cost and environmental impact.
      
      Review FinOps Hub recommendations and consider implementing suggested optimizations.
    EOT
    mime_type = "text/markdown"
  }
  
  depends_on = [google_monitoring_metric_descriptor.carbon_efficiency_score]
}