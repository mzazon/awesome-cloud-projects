# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  suffix           = random_id.suffix.hex
  dataset_name     = "${var.resource_prefix}-${local.suffix}"
  bucket_name      = "${var.resource_prefix}-${var.project_id}-${local.suffix}"
  topic_name       = "${var.resource_prefix}-topic-${local.suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    deployment-id = local.suffix
    recipe-name   = "multi-cloud-cost-optimization"
  })
}

# Enable required APIs for cost optimization
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbilling.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "recommender.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = true
  disable_on_destroy         = false
}

# BigQuery dataset for cost analytics
resource "google_bigquery_dataset" "cost_optimization" {
  dataset_id  = local.dataset_name
  location    = var.dataset_location
  description = "Cost optimization analytics dataset"

  labels = local.common_labels

  # Data retention and access controls
  default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000

  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.me.email
  }

  access {
    role           = "READER"
    special_group  = "projectReaders"
  }

  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }

  depends_on = [google_project_service.required_apis]
}

# Get current user info for BigQuery access control
data "google_client_openid_userinfo" "me" {}

# Cost analysis table schema
resource "google_bigquery_table" "cost_analysis" {
  dataset_id = google_bigquery_dataset.cost_optimization.dataset_id
  table_id   = "cost_analysis"

  description = "Table for storing cost analysis data across projects"
  labels      = local.common_labels

  schema = jsonencode([
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud project ID"
    },
    {
      name = "billing_account_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Billing account identifier"
    },
    {
      name = "service"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud service name"
    },
    {
      name = "cost"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Cost amount in billing currency"
    },
    {
      name = "currency"
      type = "STRING"
      mode = "REQUIRED"
      description = "Currency code (e.g., USD, EUR)"
    },
    {
      name = "usage_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date of resource usage"
    },
    {
      name = "optimization_potential"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Potential cost savings identified"
    }
  ])

  time_partitioning {
    type  = "DAY"
    field = "usage_date"
  }
}

# Recommendations table schema
resource "google_bigquery_table" "recommendations" {
  dataset_id = google_bigquery_dataset.cost_optimization.dataset_id
  table_id   = "recommendations"

  description = "Table for storing cost optimization recommendations"
  labels      = local.common_labels

  schema = jsonencode([
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud project ID"
    },
    {
      name = "recommender_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of recommender (e.g., machine_type, disk_size)"
    },
    {
      name = "recommendation_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique recommendation identifier"
    },
    {
      name = "description"
      type = "STRING"
      mode = "REQUIRED"
      description = "Human-readable recommendation description"
    },
    {
      name = "potential_savings"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Estimated cost savings from implementing recommendation"
    },
    {
      name = "priority"
      type = "STRING"
      mode = "NULLABLE"
      description = "Recommendation priority level"
    },
    {
      name = "created_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when recommendation was generated"
    }
  ])

  time_partitioning {
    type  = "DAY"
    field = "created_date"
  }
}

# Cloud Storage bucket for reports and data
resource "google_storage_bucket" "cost_optimization" {
  name     = local.bucket_name
  location = var.region

  labels                      = local.common_labels
  uniform_bucket_level_access = true
  storage_class               = var.storage_class

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age * 2
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Versioning for data protection
  versioning {
    enabled = true
  }

  depends_on = [google_project_service.required_apis]
}

# Create bucket folders for organization
resource "google_storage_bucket_object" "folders" {
  for_each = toset(["reports/", "recommendations/", "exports/"])

  name   = each.value
  bucket = google_storage_bucket.cost_optimization.name
  content = " "
}

# Pub/Sub topic for cost optimization events
resource "google_pubsub_topic" "cost_optimization" {
  name   = local.topic_name
  labels = local.common_labels

  message_retention_duration = "604800s" # 7 days

  depends_on = [google_project_service.required_apis]
}

# Additional Pub/Sub topics for specific workflows
resource "google_pubsub_topic" "cost_analysis_results" {
  name   = "cost-analysis-results"
  labels = local.common_labels

  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "recommendations_generated" {
  name   = "recommendations-generated"
  labels = local.common_labels

  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "optimization_alerts" {
  name   = "optimization-alerts"
  labels = local.common_labels

  message_retention_duration = "604800s"
}

# Pub/Sub subscriptions for Cloud Functions
resource "google_pubsub_subscription" "cost_analysis" {
  name  = "cost-analysis-sub"
  topic = google_pubsub_topic.cost_optimization.name

  labels = local.common_labels

  # Configure subscription for reliable message processing
  message_retention_duration = "604800s"
  retain_acked_messages      = false
  ack_deadline_seconds       = 60

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.optimization_alerts.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_subscription" "recommendations" {
  name  = "recommendations-sub"
  topic = google_pubsub_topic.recommendations_generated.name

  labels = local.common_labels

  message_retention_duration = "604800s"
  retain_acked_messages      = false
  ack_deadline_seconds       = 60

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

resource "google_pubsub_subscription" "alerts" {
  name  = "alerts-sub"
  topic = google_pubsub_topic.optimization_alerts.name

  labels = local.common_labels

  message_retention_duration = "604800s"
  retain_acked_messages      = false
  ack_deadline_seconds       = 60
}

# Service account for Cloud Functions
resource "google_service_account" "cost_optimization_functions" {
  account_id   = "${var.resource_prefix}-functions-${local.suffix}"
  display_name = "Cost Optimization Functions Service Account"
  description  = "Service account for cost optimization Cloud Functions"
}

# IAM roles for the service account
resource "google_project_iam_member" "function_roles" {
  for_each = toset([
    "roles/billing.viewer",
    "roles/recommender.viewer",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/storage.objectAdmin",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cost_optimization_functions.email}"
}

# Create source code archives for Cloud Functions
data "archive_file" "cost_analysis_source" {
  type        = "zip"
  output_path = "${path.module}/cost-analysis-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/cost_analysis.py", {
      dataset_name = local.dataset_name
      project_id   = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "recommendation_engine_source" {
  type        = "zip"
  output_path = "${path.module}/recommendation-engine-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/recommendation_engine.py", {
      dataset_name = local.dataset_name
      project_id   = var.project_id
      bucket_name  = local.bucket_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "optimization_automation_source" {
  type        = "zip"
  output_path = "${path.module}/optimization-automation-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/optimization_automation.py", {
      project_id        = var.project_id
      cost_threshold    = var.cost_threshold
      slack_webhook_url = var.slack_webhook_url
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage objects for function source code
resource "google_storage_bucket_object" "cost_analysis_source" {
  name   = "functions/cost-analysis-${local.suffix}.zip"
  bucket = google_storage_bucket.cost_optimization.name
  source = data.archive_file.cost_analysis_source.output_path
}

resource "google_storage_bucket_object" "recommendation_engine_source" {
  name   = "functions/recommendation-engine-${local.suffix}.zip"
  bucket = google_storage_bucket.cost_optimization.name
  source = data.archive_file.recommendation_engine_source.output_path
}

resource "google_storage_bucket_object" "optimization_automation_source" {
  name   = "functions/optimization-automation-${local.suffix}.zip"
  bucket = google_storage_bucket.cost_optimization.name
  source = data.archive_file.optimization_automation_source.output_path
}

# Cost Analysis Cloud Function
resource "google_cloudfunctions_function" "analyze_costs" {
  name        = "analyze-costs-${local.suffix}"
  description = "Analyze costs across projects and detect anomalies"
  runtime     = var.function_runtime

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  service_account_email = google_service_account.cost_optimization_functions.email
  labels                = local.common_labels

  source_archive_bucket = google_storage_bucket.cost_optimization.name
  source_archive_object = google_storage_bucket_object.cost_analysis_source.name

  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.cost_optimization.name
  }

  environment_variables = {
    DATASET_NAME = local.dataset_name
    PROJECT_ID   = var.project_id
    TOPIC_NAME   = google_pubsub_topic.recommendations_generated.name
  }

  depends_on = [google_project_service.required_apis]
}

# Recommendation Engine Cloud Function
resource "google_cloudfunctions_function" "generate_recommendations" {
  name        = "generate-recommendations-${local.suffix}"
  description = "Generate cost optimization recommendations"
  runtime     = var.function_runtime

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  service_account_email = google_service_account.cost_optimization_functions.email
  labels                = local.common_labels

  source_archive_bucket = google_storage_bucket.cost_optimization.name
  source_archive_object = google_storage_bucket_object.recommendation_engine_source.name

  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.recommendations_generated.name
  }

  environment_variables = {
    DATASET_NAME = local.dataset_name
    PROJECT_ID   = var.project_id
    BUCKET_NAME  = local.bucket_name
  }

  depends_on = [google_project_service.required_apis]
}

# Optimization Automation Cloud Function
resource "google_cloudfunctions_function" "optimize_resources" {
  name        = "optimize-resources-${local.suffix}"
  description = "Automate resource optimization based on recommendations"
  runtime     = var.function_runtime

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  service_account_email = google_service_account.cost_optimization_functions.email
  labels                = local.common_labels

  source_archive_bucket = google_storage_bucket.cost_optimization.name
  source_archive_object = google_storage_bucket_object.optimization_automation_source.name

  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.recommendations_generated.name
  }

  environment_variables = {
    PROJECT_ID          = var.project_id
    COST_THRESHOLD      = var.cost_threshold
    SLACK_WEBHOOK_URL   = var.slack_webhook_url
    ALERT_TOPIC         = google_pubsub_topic.optimization_alerts.name
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Scheduler jobs for automated cost analysis
resource "google_cloud_scheduler_job" "daily_cost_analysis" {
  name             = "daily-cost-analysis-${local.suffix}"
  description      = "Daily cost analysis across all projects"
  schedule         = var.cost_analysis_schedule
  time_zone        = var.schedule_timezone
  attempt_deadline = "320s"

  pubsub_target {
    topic_name = google_pubsub_topic.cost_optimization.id
    data       = base64encode(jsonencode({
      trigger = "scheduled_analysis"
      type    = "daily"
    }))
  }

  retry_config {
    retry_count = 3
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "weekly_cost_report" {
  name             = "weekly-cost-report-${local.suffix}"
  description      = "Weekly comprehensive cost optimization report"
  schedule         = var.weekly_report_schedule
  time_zone        = var.schedule_timezone
  attempt_deadline = "320s"

  pubsub_target {
    topic_name = google_pubsub_topic.cost_optimization.id
    data       = base64encode(jsonencode({
      trigger = "weekly_report"
      type    = "comprehensive"
    }))
  }

  retry_config {
    retry_count = 3
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "monthly_optimization_review" {
  name             = "monthly-optimization-review-${local.suffix}"
  description      = "Monthly optimization opportunities review"
  schedule         = var.monthly_review_schedule
  time_zone        = var.schedule_timezone
  attempt_deadline = "320s"

  pubsub_target {
    topic_name = google_pubsub_topic.cost_optimization.id
    data       = base64encode(jsonencode({
      trigger = "monthly_review"
      type    = "optimization"
    }))
  }

  retry_config {
    retry_count = 3
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring notification channel (email)
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0

  display_name = "Cost Optimization Email Alerts"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
  
  enabled = true
}

# Cloud Monitoring alert policy for high cost optimization potential
resource "google_monitoring_alert_policy" "high_cost_optimization" {
  count = var.enable_detailed_monitoring ? 1 : 0

  display_name = "High Cost Optimization Potential - ${local.suffix}"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High potential savings detected"
    
    condition_threshold {
      filter          = "resource.type=\"global\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.cost_threshold

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []

  documentation {
    content = "Cost optimization potential exceeds ${var.cost_threshold} USD. Review recommendations and consider implementing optimizations."
  }
}

# Log sink for cost optimization function logs
resource "google_logging_project_sink" "cost_optimization_logs" {
  count = var.enable_detailed_monitoring ? 1 : 0

  name        = "cost-optimization-logs-${local.suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.cost_optimization.name}"

  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name=~"^(analyze-costs|generate-recommendations|optimize-resources)-${local.suffix}$"
  EOT

  unique_writer_identity = true
}

# Grant the log sink service account storage admin permissions
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_detailed_monitoring ? 1 : 0

  bucket = google_storage_bucket.cost_optimization.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.cost_optimization_logs[0].writer_identity
}