# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming
locals {
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Resource names with suffix
  healthcare_dataset_name = "${var.healthcare_dataset_name}-${local.resource_suffix}"
  fhir_store_name        = "${var.fhir_store_name}-${local.resource_suffix}"
  function_name          = "${var.function_name}-${local.resource_suffix}"
  pubsub_topic_name      = "${var.pubsub_topic_name}-${local.resource_suffix}"
  bigquery_dataset_id    = "${var.bigquery_dataset_id}_${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    solution    = "patient-sentiment-analysis"
    managed-by  = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "healthcare.googleapis.com",
    "language.googleapis.com",
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ]) : toset([])

  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Healthcare Dataset
resource "google_healthcare_dataset" "patient_records" {
  provider = google-beta
  
  name     = local.healthcare_dataset_name
  location = var.region
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for FHIR notifications
resource "google_pubsub_topic" "fhir_notifications" {
  name = local.pubsub_topic_name
  
  labels = local.common_labels
  
  # Message retention duration
  message_retention_duration = "86400s" # 24 hours
  
  depends_on = [google_project_service.required_apis]
}

# Create FHIR store with Pub/Sub notifications
resource "google_healthcare_fhir_store" "patient_fhir" {
  provider = google-beta
  
  name    = local.fhir_store_name
  dataset = google_healthcare_dataset.patient_records.id
  version = var.fhir_version
  
  # Enable search and indexing
  enable_update_create          = true
  disable_referential_integrity = false
  disable_resource_versioning   = false
  enable_history_import         = false
  
  # Configure Pub/Sub notifications for new/updated resources
  notification_configs {
    pubsub_topic                = google_pubsub_topic.fhir_notifications.id
    send_full_resource         = true
    send_previous_resource_on_delete = false
  }
  
  labels = local.common_labels
}

# Create BigQuery dataset for sentiment analysis results
resource "google_bigquery_dataset" "sentiment_analysis" {
  dataset_id  = local.bigquery_dataset_id
  location    = var.bigquery_location
  description = "Patient sentiment analysis results from Healthcare API and Natural Language AI"
  
  # Data retention and lifecycle
  default_table_expiration_ms = 0 # No expiration by default
  delete_contents_on_destroy  = !var.deletion_protection
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery table for sentiment analysis results
resource "google_bigquery_table" "sentiment_results" {
  dataset_id          = google_bigquery_dataset.sentiment_analysis.dataset_id
  table_id            = var.bigquery_table_id
  description         = "Sentiment analysis results for patient records and feedback"
  deletion_protection = var.deletion_protection
  
  # Define table schema for sentiment analysis results
  schema = jsonencode([
    {
      name = "patient_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "FHIR Patient ID"
    },
    {
      name = "observation_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "FHIR Observation ID"
    },
    {
      name = "text_content"
      type = "STRING"
      mode = "REQUIRED"
      description = "Original text content analyzed for sentiment"
    },
    {
      name = "sentiment_score"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Sentiment score from -1.0 (negative) to 1.0 (positive)"
    },
    {
      name = "magnitude"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Sentiment magnitude indicating emotional intensity"
    },
    {
      name = "overall_sentiment"
      type = "STRING"
      mode = "REQUIRED"
      description = "Overall sentiment classification: POSITIVE, NEGATIVE, or NEUTRAL"
    },
    {
      name = "processing_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when sentiment analysis was performed"
    },
    {
      name = "fhir_resource_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of FHIR resource (e.g., Observation, DocumentReference)"
    }
  ])
  
  labels = local.common_labels
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "cf-source-${var.project_id}-${local.resource_suffix}"
  location = var.region
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/sentiment-function-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id         = var.project_id
      bigquery_dataset   = google_bigquery_dataset.sentiment_analysis.dataset_id
      bigquery_table     = google_bigquery_table.sentiment_results.table_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "sentiment-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "sentiment-function-sa-${local.resource_suffix}"
  display_name = "Sentiment Analysis Function Service Account"
  description  = "Service account for sentiment analysis Cloud Function with healthcare and AI permissions"
}

# Grant Healthcare API FHIR resource reader permissions
resource "google_project_iam_member" "function_healthcare_reader" {
  project = var.project_id
  role    = "roles/healthcare.fhirResourceReader"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Natural Language API permissions
resource "google_project_iam_member" "function_ml_developer" {
  project = var.project_id
  role    = "roles/ml.developer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant BigQuery data editor permissions
resource "google_project_iam_member" "function_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant BigQuery job user permissions
resource "google_project_iam_member" "function_bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create the sentiment analysis Cloud Function
resource "google_cloudfunctions2_function" "sentiment_processor" {
  name        = local.function_name
  location    = var.region
  description = "Processes FHIR events and performs sentiment analysis using Natural Language AI"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "process_fhir_sentiment"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      GCP_PROJECT    = var.project_id
      BQ_DATASET     = google_bigquery_dataset.sentiment_analysis.dataset_id
      BQ_TABLE       = google_bigquery_table.sentiment_results.table_id
      FUNCTION_REGION = var.region
    }
    
    service_account_email = google_service_account.function_sa.email
    
    # VPC connector configuration (optional)
    # vpc_connector                 = var.vpc_connector
    # vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.fhir_notifications.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_healthcare_reader,
    google_project_iam_member.function_ml_developer,
    google_project_iam_member.function_bigquery_editor,
    google_project_iam_member.function_bigquery_user,
    google_project_iam_member.function_logging
  ]
}

# Create function source code directory and files
resource "local_file" "function_main_py" {
  filename = "${path.module}/function_code/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id       = var.project_id
    bigquery_dataset = local.bigquery_dataset_id
    bigquery_table   = var.bigquery_table_id
  })
}

resource "local_file" "function_requirements_txt" {
  filename = "${path.module}/function_code/requirements.txt"
  content  = file("${path.module}/templates/requirements.txt")
}

# Create BigQuery views for analytics
resource "google_bigquery_table" "sentiment_summary_view" {
  dataset_id = google_bigquery_dataset.sentiment_analysis.dataset_id
  table_id   = "sentiment_summary"
  
  view {
    query = templatefile("${path.module}/sql/sentiment_summary.sql", {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.sentiment_analysis.dataset_id
      table_id   = google_bigquery_table.sentiment_results.table_id
    })
    use_legacy_sql = false
  }
  
  description = "Summary view of patient sentiment analysis results"
  labels      = local.common_labels
}

# Create monitoring and alerting (optional)
resource "google_monitoring_notification_channel" "email_channel" {
  count = var.environment == "prod" ? 1 : 0
  
  display_name = "Healthcare Sentiment Analysis Alerts"
  type         = "email"
  
  labels = {
    email_address = "healthcare-alerts@${var.project_id}.iam.gserviceaccount.com"
  }
  
  description = "Email notifications for critical healthcare sentiment analysis issues"
}

# Create log-based metrics for monitoring
resource "google_logging_metric" "function_errors" {
  name   = "sentiment_function_errors"
  filter = "resource.type=\"cloud_function\" resource.labels.function_name=\"${local.function_name}\" severity>=ERROR"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Sentiment Function Errors"
  }
  
  label_extractors = {
    "function_name" = "EXTRACT(resource.labels.function_name)"
  }
}

# Create alerting policy for function errors
resource "google_monitoring_alert_policy" "function_error_alert" {
  count = var.environment == "prod" ? 1 : 0
  
  display_name = "Sentiment Analysis Function Errors"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Function error rate"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/sentiment_function_errors\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  
  notification_channels = var.environment == "prod" ? [google_monitoring_notification_channel.email_channel[0].id] : []
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}

# Output important resource information
output "deployment_summary" {
  description = "Summary of deployed healthcare sentiment analysis infrastructure"
  value = {
    healthcare_dataset    = google_healthcare_dataset.patient_records.name
    fhir_store           = google_healthcare_fhir_store.patient_fhir.name
    bigquery_dataset     = google_bigquery_dataset.sentiment_analysis.dataset_id
    bigquery_table       = google_bigquery_table.sentiment_results.table_id
    cloud_function       = google_cloudfunctions2_function.sentiment_processor.name
    pubsub_topic         = google_pubsub_topic.fhir_notifications.name
    function_service_account = google_service_account.function_sa.email
  }
}