# Main Terraform configuration for GCP Automated Cost Analytics Infrastructure
# This file creates a serverless cost analytics pipeline using Cloud Run, BigQuery, and Pub/Sub

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix for uniqueness
  name_suffix = random_id.suffix.hex
  dataset_id  = "${var.name_prefix}_${local.name_suffix}"
  topic_name  = "${var.name_prefix}-topic-${local.name_suffix}"
  service_name = "${var.name_prefix}-worker-${local.name_suffix}"
  subscription_name = "${var.name_prefix}-sub-${local.name_suffix}"
  scheduler_job_name = "${var.name_prefix}-job-${local.name_suffix}"
  service_account_id = "${var.name_prefix}-sa-${local.name_suffix}"

  # Common labels for all resources
  common_labels = merge(var.labels, {
    service     = "cost-analytics"
    environment = var.environment
    created_by  = "terraform"
    managed_by  = "terraform"
  })

  # List of required APIs for the cost analytics solution
  required_apis = [
    "cloudbilling.googleapis.com",
    "bigquery.googleapis.com", 
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
}

# Enable required GCP APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  project = var.project_id
  service = each.value

  # Prevent disabling APIs when resource is destroyed to avoid dependency issues
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service Account for Cost Analytics Worker
resource "google_service_account" "cost_worker" {
  account_id   = local.service_account_id
  display_name = var.service_account_display_name
  description  = "Service account for automated cost analytics worker processes"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cost_worker.email}"
}

resource "google_project_iam_member" "billing_viewer" {
  project = var.project_id
  role    = "roles/billing.viewer"
  member  = "serviceAccount:${google_service_account.cost_worker.email}"
}

resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.cost_worker.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cost_worker.email}"
}

# BigQuery Dataset for Cost Analytics
resource "google_bigquery_dataset" "cost_analytics" {
  dataset_id    = local.dataset_id
  friendly_name = "Cost Analytics Dataset"
  description   = var.dataset_description
  location      = var.dataset_location
  project       = var.project_id

  # Enable deletion protection for production data
  delete_contents_on_destroy = var.environment != "prod"

  # Set default table expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.table_expiration_days > 0 ? [1] : []
    content {
      default_table_expiration_ms = var.table_expiration_days * 24 * 60 * 60 * 1000
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# BigQuery Table for Daily Cost Data with Partitioning
resource "google_bigquery_table" "daily_costs" {
  dataset_id = google_bigquery_dataset.cost_analytics.dataset_id
  table_id   = "daily_costs"
  project    = var.project_id

  description = "Daily cost analytics with project breakdown and time partitioning"

  # Time partitioning for optimal query performance and cost management
  time_partitioning {
    type  = "DAY"
    field = "usage_date"
  }

  # Schema definition for cost data
  schema = jsonencode([
    {
      name        = "usage_date"
      type        = "DATE"
      mode        = "REQUIRED"
      description = "Date of resource usage"
    },
    {
      name        = "project_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "GCP project identifier"
    },
    {
      name        = "service"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "GCP service name (e.g., Compute Engine, BigQuery)"
    },
    {
      name        = "sku"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Stock Keeping Unit for the resource"
    },
    {
      name        = "cost"
      type        = "FLOAT"
      mode        = "REQUIRED"
      description = "Cost amount for the usage"
    },
    {
      name        = "currency"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Currency code (e.g., USD, EUR)"
    },
    {
      name        = "labels"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "JSON string of resource labels"
    }
  ])

  labels = local.common_labels
}

# BigQuery View for Monthly Cost Summary
resource "google_bigquery_table" "monthly_cost_summary" {
  dataset_id = google_bigquery_dataset.cost_analytics.dataset_id
  table_id   = "monthly_cost_summary"
  project    = var.project_id

  description = "Monthly cost summary by project and service"

  view {
    query = <<-EOF
      SELECT 
        FORMAT_DATE("%Y-%m", usage_date) as month,
        project_id,
        service,
        SUM(cost) as total_cost,
        currency,
        COUNT(*) as usage_records
      FROM `${var.project_id}.${local.dataset_id}.daily_costs`
      WHERE usage_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
      GROUP BY month, project_id, service, currency
      ORDER BY month DESC, total_cost DESC
    EOF
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.daily_costs]
}

# BigQuery View for Cost Trend Analysis
resource "google_bigquery_table" "cost_trend_analysis" {
  dataset_id = google_bigquery_dataset.cost_analytics.dataset_id
  table_id   = "cost_trend_analysis"
  project    = var.project_id

  description = "Cost trend analysis with week-over-week comparison"

  view {
    query = <<-EOF
      WITH weekly_costs AS (
        SELECT 
          DATE_TRUNC(usage_date, WEEK) as week_start,
          project_id,
          service,
          SUM(cost) as weekly_cost
        FROM `${var.project_id}.${local.dataset_id}.daily_costs`
        GROUP BY week_start, project_id, service
      )
      SELECT 
        week_start,
        project_id,
        service,
        weekly_cost,
        LAG(weekly_cost) OVER (
          PARTITION BY project_id, service 
          ORDER BY week_start
        ) as previous_week_cost,
        ROUND(
          (weekly_cost - LAG(weekly_cost) OVER (
            PARTITION BY project_id, service 
            ORDER BY week_start
          )) / NULLIF(LAG(weekly_cost) OVER (
            PARTITION BY project_id, service 
            ORDER BY week_start
          ), 0) * 100, 2
        ) as week_over_week_change_percent
      FROM weekly_costs
      ORDER BY week_start DESC, weekly_cost DESC
    EOF
    use_legacy_sql = false
  }

  labels = local.common_labels

  depends_on = [google_bigquery_table.daily_costs]
}

# Pub/Sub Topic for Cost Processing Events
resource "google_pubsub_topic" "cost_processing" {
  name    = local.topic_name
  project = var.project_id

  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Run Service for Cost Processing Worker
resource "google_cloud_run_service" "cost_worker" {
  name     = local.service_name
  location = var.region
  project  = var.project_id

  template {
    metadata {
      labels = local.common_labels
      annotations = {
        "autoscaling.knative.dev/minScale" = var.cloud_run_min_instances
        "autoscaling.knative.dev/maxScale" = var.cloud_run_max_instances
        "run.googleapis.com/execution-environment" = "gen2"
      }
    }

    spec {
      service_account_name  = google_service_account.cost_worker.email
      container_concurrency = var.cloud_run_concurrency
      timeout_seconds       = var.cloud_run_timeout

      containers {
        # Use a default Python image - in practice, this would be replaced with the actual worker image
        image = var.worker_container_image != "" ? var.worker_container_image : "gcr.io/cloudrun/hello"

        # Resource allocation
        resources {
          limits = {
            cpu    = var.cloud_run_cpu
            memory = var.cloud_run_memory
          }
        }

        # Environment variables for the worker
        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = var.project_id
        }

        env {
          name  = "DATASET_NAME"
          value = local.dataset_id
        }

        env {
          name  = "BILLING_ACCOUNT"
          value = var.billing_account_id
        }

        env {
          name  = "ENVIRONMENT"
          value = var.environment
        }

        # Container port configuration
        ports {
          container_port = 8080
        }
      }
    }
  }

  # Traffic configuration
  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.cost_worker
  ]
}

# Pub/Sub Subscription with Push to Cloud Run
resource "google_pubsub_subscription" "cost_processing" {
  name    = local.subscription_name
  topic   = google_pubsub_topic.cost_processing.name
  project = var.project_id

  # Acknowledgment deadline configuration
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds

  # Push configuration to Cloud Run service
  push_config {
    push_endpoint = google_cloud_run_service.cost_worker.status[0].url

    # Attributes for authentication
    attributes = {
      "x-goog-version" = "v1"
    }

    # OIDC token for secure authentication
    oidc_token {
      service_account_email = google_service_account.cost_worker.email
    }
  }

  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration

  # Retry policy for failed deliveries
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels

  depends_on = [
    google_cloud_run_service.cost_worker,
    google_pubsub_topic.cost_processing
  ]
}

# IAM policy for Pub/Sub to invoke Cloud Run
resource "google_cloud_run_service_iam_member" "pubsub_invoker" {
  service  = google_cloud_run_service.cost_worker.name
  location = google_cloud_run_service.cost_worker.location
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cost_worker.email}"
  project  = var.project_id
}

# Cloud Scheduler Job for Automated Processing
resource "google_cloud_scheduler_job" "daily_cost_analysis" {
  name        = local.scheduler_job_name
  description = var.scheduler_description
  schedule    = var.scheduler_cron_schedule
  time_zone   = var.scheduler_timezone
  project     = var.project_id
  region      = var.region

  # Pub/Sub target configuration
  pubsub_target {
    topic_name = google_pubsub_topic.cost_processing.id
    data = base64encode(jsonencode({
      trigger = "daily_cost_analysis"
      date    = "auto"
      source  = "cloud_scheduler"
    }))
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.cost_processing
  ]
}

# Output important resource information
output "dataset_id" {
  description = "BigQuery dataset ID for cost analytics"
  value       = google_bigquery_dataset.cost_analytics.dataset_id
}

output "cloud_run_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.cost_worker.status[0].url
}

output "pubsub_topic" {
  description = "Pub/Sub topic name for cost processing events"
  value       = google_pubsub_topic.cost_processing.name
}

output "service_account_email" {
  description = "Email of the service account used by the cost worker"
  value       = google_service_account.cost_worker.email
}