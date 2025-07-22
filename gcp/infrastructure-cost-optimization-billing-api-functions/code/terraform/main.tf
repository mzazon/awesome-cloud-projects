# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  dataset_name    = "${var.resource_prefix}_${local.resource_suffix}"
  function_prefix = "${var.resource_prefix}-${local.resource_suffix}"
  
  # Merge default and custom labels
  common_labels = merge(var.labels, {
    resource-group = "cost-optimization"
    created-by     = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  timeouts {
    create = "30m"
    update = "40m"
  }
  
  disable_dependent_services = true
}

# Create service account for Cloud Functions
resource "google_service_account" "cost_optimization" {
  account_id   = "${var.resource_prefix}-functions-${local.resource_suffix}"
  display_name = "Cost Optimization Functions Service Account"
  description  = "Service account for cost optimization Cloud Functions"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "cost_optimization_roles" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/billing.viewer",
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cost_optimization.email}"
}

# Create BigQuery dataset for cost analytics
resource "google_bigquery_dataset" "cost_optimization" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.dataset_location
  description = var.dataset_description
  
  labels = local.common_labels
  
  access {
    role          = "OWNER"
    user_by_email = google_service_account.cost_optimization.email
  }
  
  access {
    role         = "OWNER"
    special_group = "projectOwners"
  }
  
  access {
    role         = "READER"
    special_group = "projectReaders"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create table for cost anomaly tracking
resource "google_bigquery_table" "cost_anomalies" {
  dataset_id = google_bigquery_dataset.cost_optimization.dataset_id
  table_id   = "cost_anomalies"
  project    = var.project_id
  
  labels = local.common_labels
  
  schema = jsonencode([
    {
      name = "detection_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Date and time when the anomaly was detected"
    },
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud project ID where the anomaly occurred"
    },
    {
      name = "service"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud service associated with the cost anomaly"
    },
    {
      name = "expected_cost"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Expected cost based on historical patterns"
    },
    {
      name = "actual_cost"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Actual cost that triggered the anomaly detection"
    },
    {
      name = "deviation_percent"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Percentage deviation from expected cost"
    },
    {
      name = "anomaly_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of anomaly detected (e.g., statistical_anomaly, threshold_breach)"
    }
  ])
}

# Create Pub/Sub topic for cost optimization alerts
resource "google_pubsub_topic" "cost_optimization_alerts" {
  name    = "cost-optimization-alerts"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscriptions
resource "google_pubsub_subscription" "budget_alerts" {
  name  = "budget-alerts-sub"
  topic = google_pubsub_topic.cost_optimization_alerts.name
  project = var.project_id
  
  labels = local.common_labels
  
  # Message retention duration
  message_retention_duration = "604800s" # 7 days
  
  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.cost_optimization_alerts.id
    max_delivery_attempts = 10
  }
}

resource "google_pubsub_subscription" "anomaly_detection" {
  name  = "anomaly-detection-sub"
  topic = google_pubsub_topic.cost_optimization_alerts.name
  project = var.project_id
  
  labels = local.common_labels
  
  # Message retention duration
  message_retention_duration = "604800s" # 7 days
  
  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-cost-functions-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  # Enable versioning for source code tracking
  versioning {
    enabled = true
  }
  
  # Lifecycle management for old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create ZIP archives for Cloud Functions source code
data "archive_file" "cost_analysis_source" {
  type        = "zip"
  output_path = "${path.module}/cost-analysis-function.zip"
  
  source {
    content = templatefile("${path.module}/functions/cost_analysis.py", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "anomaly_detection_source" {
  type        = "zip"
  output_path = "${path.module}/anomaly-detection-function.zip"
  
  source {
    content = templatefile("${path.module}/functions/anomaly_detection.py", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "optimization_source" {
  type        = "zip"
  output_path = "${path.module}/optimization-function.zip"
  
  source {
    content = templatefile("${path.module}/functions/optimization.py", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "cost_analysis_source" {
  name   = "cost-analysis-${data.archive_file.cost_analysis_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.cost_analysis_source.output_path
}

resource "google_storage_bucket_object" "anomaly_detection_source" {
  name   = "anomaly-detection-${data.archive_file.anomaly_detection_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.anomaly_detection_source.output_path
}

resource "google_storage_bucket_object" "optimization_source" {
  name   = "optimization-${data.archive_file.optimization_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.optimization_source.output_path
}

# Deploy Cost Analysis Cloud Function
resource "google_cloudfunctions2_function" "cost_analysis" {
  name     = "${local.function_prefix}-cost-analysis"
  location = var.region
  project  = var.project_id
  
  description = "Analyzes cost trends and generates optimization recommendations"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "analyze_costs"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.cost_analysis_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.cost_optimization.email
    
    environment_variables = {
      GCP_PROJECT   = var.project_id
      DATASET_NAME  = local.dataset_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Deploy Anomaly Detection Cloud Function
resource "google_cloudfunctions2_function" "anomaly_detection" {
  name     = "${local.function_prefix}-anomaly-detection"
  location = var.region
  project  = var.project_id
  
  description = "Detects cost anomalies and sends alerts"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "detect_anomalies"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.anomaly_detection_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.cost_optimization.email
    
    environment_variables = {
      GCP_PROJECT   = var.project_id
      DATASET_NAME  = local.dataset_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Deploy Resource Optimization Cloud Function
resource "google_cloudfunctions2_function" "optimization" {
  name     = "${local.function_prefix}-optimization"
  location = var.region
  project  = var.project_id
  
  description = "Generates resource optimization recommendations"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "optimize_resources"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.optimization_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.cost_optimization.email
    
    environment_variables = {
      GCP_PROJECT   = var.project_id
      DATASET_NAME  = local.dataset_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub trigger for anomaly detection function
resource "google_eventarc_trigger" "anomaly_detection_trigger" {
  name     = "${local.function_prefix}-anomaly-trigger"
  location = var.region
  project  = var.project_id
  
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }
  
  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.anomaly_detection.name
      region  = var.region
    }
  }
  
  transport {
    pubsub {
      topic = google_pubsub_topic.cost_optimization_alerts.id
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Scheduler jobs for automated analysis
resource "google_cloud_scheduler_job" "cost_analysis" {
  name      = "${local.function_prefix}-cost-analysis-scheduler"
  region    = var.region
  project   = var.project_id
  schedule  = var.cost_analysis_schedule
  time_zone = "UTC"
  
  description = "Daily cost analysis and optimization recommendations"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.cost_analysis.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.cost_optimization.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "optimization" {
  name      = "${local.function_prefix}-optimization-scheduler"
  region    = var.region
  project   = var.project_id
  schedule  = var.optimization_schedule
  time_zone = "UTC"
  
  description = "Weekly resource optimization analysis"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.optimization.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.cost_optimization.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create billing budget (requires Google Cloud Billing API)
resource "google_billing_budget" "cost_optimization" {
  billing_account = var.billing_account_id
  display_name    = "Cost Optimization Budget - ${local.resource_suffix}"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.budget_amount
    }
  }
  
  # Configure threshold rules for budget alerts
  dynamic "threshold_rules" {
    for_each = var.budget_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = threshold_rules.value < 1.0 ? "CURRENT_SPEND" : "FORECASTED_SPEND"
    }
  }
  
  # Configure notifications to Pub/Sub
  all_updates_rule {
    pubsub_topic = google_pubsub_topic.cost_optimization_alerts.id
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Monitoring alert policies for cost anomalies
resource "google_monitoring_alert_policy" "high_cost_anomaly" {
  display_name = "High Cost Anomaly Detected"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "High Cost Anomaly Condition"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${google_cloudfunctions2_function.anomaly_detection.name}\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}