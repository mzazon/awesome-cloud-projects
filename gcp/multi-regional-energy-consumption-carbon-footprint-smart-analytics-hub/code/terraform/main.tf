# Multi-Regional Energy Consumption Carbon Footprint Smart Analytics Hub
# This Terraform configuration deploys a complete carbon optimization system
# using Google Cloud services including Cloud Carbon Footprint, Analytics Hub,
# Cloud Scheduler, and Cloud Functions for intelligent workload scheduling.

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  random_suffix = random_id.suffix.hex
  resource_prefix = "carbon-analytics-${local.random_suffix}"
  
  # Function source code for carbon data collection
  carbon_function_source = {
    "main.py" = templatefile("${path.module}/function_code/carbon_collector.py", {
      project_id = var.project_id
      dataset_name = google_bigquery_dataset.carbon_analytics.dataset_id
    })
    "requirements.txt" = file("${path.module}/function_code/requirements.txt")
  }
  
  # Function source code for workload migration
  migration_function_source = {
    "main.py" = templatefile("${path.module}/function_code/workload_migration.py", {
      project_id = var.project_id
      dataset_name = google_bigquery_dataset.carbon_analytics.dataset_id
    })
    "requirements.txt" = file("${path.module}/function_code/requirements.txt")
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "bigquery.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "analyticshub.googleapis.com",
    "storage.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  count    = var.function_source_bucket == null ? 1 : 0
  name     = "${local.resource_prefix}-function-source"
  location = var.primary_region
  project  = var.project_id

  uniform_bucket_level_access = true
  force_destroy              = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Use existing bucket if specified
data "google_storage_bucket" "existing_function_source" {
  count = var.function_source_bucket != null ? 1 : 0
  name  = var.function_source_bucket
}

locals {
  function_bucket = var.function_source_bucket != null ? data.google_storage_bucket.existing_function_source[0] : google_storage_bucket.function_source[0]
}

# Create function source code directory structure
resource "local_file" "carbon_function_files" {
  for_each = local.carbon_function_source
  filename = "${path.module}/temp/carbon_collector/${each.key}"
  content  = each.value
}

resource "local_file" "migration_function_files" {
  for_each = local.migration_function_source
  filename = "${path.module}/temp/workload_migration/${each.key}"
  content  = each.value
}

# Create zip archives for function deployment
data "archive_file" "carbon_function_zip" {
  type        = "zip"
  output_path = "${path.module}/temp/carbon_collector.zip"
  source_dir  = "${path.module}/temp/carbon_collector"
  
  depends_on = [local_file.carbon_function_files]
}

data "archive_file" "migration_function_zip" {
  type        = "zip"
  output_path = "${path.module}/temp/workload_migration.zip"
  source_dir  = "${path.module}/temp/workload_migration"
  
  depends_on = [local_file.migration_function_files]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "carbon_function_source" {
  name   = "carbon_collector_${local.random_suffix}.zip"
  bucket = local.function_bucket.name
  source = data.archive_file.carbon_function_zip.output_path

  depends_on = [data.archive_file.carbon_function_zip]
}

resource "google_storage_bucket_object" "migration_function_source" {
  count  = var.enable_workload_migration ? 1 : 0
  name   = "workload_migration_${local.random_suffix}.zip"
  bucket = local.function_bucket.name
  source = data.archive_file.migration_function_zip.output_path

  depends_on = [data.archive_file.migration_function_zip]
}

# Create BigQuery dataset for carbon analytics
resource "google_bigquery_dataset" "carbon_analytics" {
  dataset_id  = "carbon_analytics_${local.random_suffix}"
  project     = var.project_id
  location    = var.dataset_location
  description = "Carbon footprint and energy optimization analytics dataset"

  # Set table expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.bigquery_table_expiration_ms != null ? [var.bigquery_table_expiration_ms] : []
    content {
      default_table_expiration_ms = default_table_expiration_ms.value
    }
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create BigQuery tables for carbon data
resource "google_bigquery_table" "carbon_footprint" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "carbon_footprint"
  project    = var.project_id

  description = "Table storing carbon footprint data across regions and services"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp of the carbon footprint measurement"
    },
    {
      name = "region"
      type = "STRING"
      mode = "REQUIRED"
      description = "GCP region where the measurement was taken"
    },
    {
      name = "service"
      type = "STRING"
      mode = "REQUIRED"
      description = "GCP service that generated the carbon emissions"
    },
    {
      name = "carbon_emissions_kg"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Carbon emissions in kilograms of CO2 equivalent"
    },
    {
      name = "energy_kwh"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Energy consumption in kilowatt hours"
    },
    {
      name = "carbon_intensity"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Carbon intensity in kg CO2e per kWh"
    }
  ])

  labels = var.labels
}

resource "google_bigquery_table" "workload_schedules" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "workload_schedules"
  project    = var.project_id

  description = "Table storing workload scheduling optimization decisions"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp of the scheduling decision"
    },
    {
      name = "workload_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the workload"
    },
    {
      name = "source_region"
      type = "STRING"
      mode = "REQUIRED"
      description = "Original region of the workload"
    },
    {
      name = "target_region"
      type = "STRING"
      mode = "REQUIRED"
      description = "Recommended target region for optimization"
    },
    {
      name = "carbon_savings_kg"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Estimated carbon savings in kg CO2e"
    },
    {
      name = "reason"
      type = "STRING"
      mode = "NULLABLE"
      description = "Explanation for the scheduling recommendation"
    }
  ])

  labels = var.labels
}

resource "google_bigquery_table" "migration_log" {
  count      = var.enable_workload_migration ? 1 : 0
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "migration_log"
  project    = var.project_id

  description = "Table logging workload migration execution results"

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp of the migration event"
    },
    {
      name = "workload_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the migrated workload"
    },
    {
      name = "migration_status"
      type = "STRING"
      mode = "REQUIRED"
      description = "Status of the migration (scheduled, in_progress, completed, failed)"
    },
    {
      name = "estimated_carbon_savings"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Estimated carbon savings from migration in kg CO2e"
    }
  ])

  labels = var.labels
}

# Create BigQuery views for analytics
resource "google_bigquery_table" "regional_carbon_summary" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "regional_carbon_summary"
  project    = var.project_id

  description = "View providing regional carbon footprint summary analytics"

  view {
    query = <<-EOT
      SELECT 
        region,
        DATE(timestamp) as date,
        AVG(carbon_intensity) as avg_carbon_intensity,
        SUM(carbon_emissions_kg) as total_emissions_kg,
        SUM(energy_kwh) as total_energy_kwh,
        COUNT(*) as measurements
      FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.carbon_footprint`
      GROUP BY region, DATE(timestamp)
      ORDER BY date DESC, region
    EOT
    use_legacy_sql = false
  }

  labels = var.labels
}

resource "google_bigquery_table" "optimization_impact" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "optimization_impact"
  project    = var.project_id

  description = "View showing carbon optimization impact and savings"

  view {
    query = <<-EOT
      SELECT 
        DATE(timestamp) as date,
        COUNT(*) as workloads_optimized,
        SUM(carbon_savings_kg) as total_carbon_savings_kg,
        AVG(carbon_savings_kg) as avg_savings_per_workload,
        STRING_AGG(DISTINCT target_region) as preferred_regions
      FROM `${var.project_id}.${google_bigquery_dataset.carbon_analytics.dataset_id}.workload_schedules`
      GROUP BY DATE(timestamp)
      ORDER BY date DESC
    EOT
    use_legacy_sql = false
  }

  labels = var.labels
}

resource "google_bigquery_table" "regional_efficiency_scores" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  table_id   = "regional_efficiency_scores"
  project    = var.project_id

  description = "Table with pre-computed regional carbon efficiency scores"

  schema = jsonencode([
    {
      name = "region"
      type = "STRING"
      mode = "REQUIRED"
      description = "GCP region"
    },
    {
      name = "avg_carbon_intensity"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Average carbon intensity for the region"
    },
    {
      name = "best_carbon_intensity"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Best (lowest) carbon intensity recorded"
    },
    {
      name = "worst_carbon_intensity"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Worst (highest) carbon intensity recorded"
    },
    {
      name = "carbon_intensity_variation"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Standard deviation of carbon intensity"
    },
    {
      name = "data_points"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Number of data points used in calculation"
    },
    {
      name = "efficiency_rating"
      type = "STRING"
      mode = "REQUIRED"
      description = "Efficiency rating (Excellent, Good, Fair, Needs Improvement)"
    }
  ])

  labels = var.labels
}

# Create Analytics Hub data exchange
resource "google_bigquery_analytics_hub_data_exchange" "energy_optimization" {
  location         = var.dataset_location
  data_exchange_id = "energy-optimization-exchange-${local.random_suffix}"
  display_name     = "Energy Optimization Exchange"
  description      = var.analytics_hub_description
  project          = var.project_id

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create Analytics Hub listing for carbon footprint dataset
resource "google_bigquery_analytics_hub_listing" "carbon_footprint" {
  location         = var.dataset_location
  data_exchange_id = google_bigquery_analytics_hub_data_exchange.energy_optimization.data_exchange_id
  listing_id       = "carbon-footprint-listing"
  display_name     = "Carbon Footprint Analytics"
  description      = "Regional carbon emissions and energy optimization data for sustainability initiatives"
  project          = var.project_id

  bigquery_dataset {
    dataset = google_bigquery_dataset.carbon_analytics.id
  }

  labels = var.labels
}

# Create Pub/Sub topic for workload migration triggers
resource "google_pubsub_topic" "carbon_optimization_trigger" {
  count   = var.enable_workload_migration ? 1 : 0
  name    = var.migration_topic_name
  project = var.project_id

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create Service Account for Cloud Functions
resource "google_service_account" "carbon_optimizer" {
  account_id   = "carbon-optimizer-${local.random_suffix}"
  display_name = "Carbon Optimizer Service Account"
  description  = "Service account for carbon footprint optimization functions"
  project      = var.project_id
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "carbon_optimizer_permissions" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher",
    "roles/cloudsql.client"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.carbon_optimizer.email}"
}

# Deploy carbon data collection Cloud Function
resource "google_cloudfunctions_function" "carbon_collector" {
  name        = "carbon-collector-${local.random_suffix}"
  project     = var.project_id
  region      = var.primary_region
  description = "Function to collect and process carbon footprint data for optimization"

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "collect_carbon_data"
  runtime              = "python39"
  service_account_email = google_service_account.carbon_optimizer.email

  source_archive_bucket = local.function_bucket.name
  source_archive_object = google_storage_bucket_object.carbon_function_source.name

  trigger {
    http_trigger {
      url                = null
      security_level     = "SECURE_OPTIONAL"
    }
  }

  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = google_bigquery_dataset.carbon_analytics.dataset_id
    CARBON_THRESHOLD = var.carbon_intensity_threshold
  }

  labels = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.carbon_optimizer_permissions
  ]
}

# Deploy workload migration Cloud Function
resource "google_cloudfunctions_function" "workload_migration" {
  count       = var.enable_workload_migration ? 1 : 0
  name        = "workload-migration-${local.random_suffix}"
  project     = var.project_id
  region      = var.primary_region
  description = "Function to automate workload migration based on carbon optimization"

  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "migrate_workloads"
  runtime              = "python39"
  service_account_email = google_service_account.carbon_optimizer.email

  source_archive_bucket = local.function_bucket.name
  source_archive_object = google_storage_bucket_object.migration_function_source[0].name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.carbon_optimization_trigger[0].name
  }

  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = google_bigquery_dataset.carbon_analytics.dataset_id
  }

  labels = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.carbon_optimizer_permissions
  ]
}

# Create Cloud Scheduler jobs for automated optimization
resource "google_cloud_scheduler_job" "carbon_optimization" {
  name        = "carbon-optimizer-${local.random_suffix}"
  project     = var.project_id
  region      = var.primary_region
  description = "Automated carbon footprint optimization"
  schedule    = var.carbon_optimization_schedule
  time_zone   = "UTC"

  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.carbon_collector.https_trigger_url
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "renewable_optimization" {
  name        = "renewable-optimizer-${local.random_suffix}"
  project     = var.project_id
  region      = var.primary_region
  description = "Optimization during peak renewable energy hours"
  schedule    = var.renewable_optimization_schedule
  time_zone   = "UTC"

  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.carbon_collector.https_trigger_url
  }

  depends_on = [google_project_service.required_apis]
}

# Create monitoring alert policy for high carbon intensity
resource "google_monitoring_alert_policy" "high_carbon_intensity" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  display_name = "High Carbon Intensity Alert - ${local.random_suffix}"
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "Alert when regional carbon intensity exceeds threshold, triggering workload migration recommendations."
  }

  conditions {
    display_name = "Carbon intensity threshold exceeded"

    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.carbon_collector.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.carbon_intensity_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create email notification channel if email is provided
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  project      = var.project_id
  display_name = "Carbon Optimization Email Alerts"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Create custom metric descriptor for carbon savings
resource "google_monitoring_metric_descriptor" "carbon_savings" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  type         = "custom.googleapis.com/carbon/savings_kg_per_hour"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  display_name = "Carbon Savings per Hour"
  description  = "Carbon emissions saved through workload optimization in kg CO2e per hour"

  labels {
    key         = "region"
    value_type  = "STRING"
    description = "GCP region where savings occurred"
  }

  depends_on = [google_project_service.required_apis]
}

# Create IAM bindings for Analytics Hub data sharing
resource "google_bigquery_dataset_iam_binding" "analytics_hub_viewer" {
  dataset_id = google_bigquery_dataset.carbon_analytics.dataset_id
  role       = "roles/bigquery.dataViewer"
  project    = var.project_id

  members = [
    "serviceAccount:${google_service_account.carbon_optimizer.email}",
  ]
}

# Create cross-regional backup dataset if enabled
resource "google_bigquery_dataset" "carbon_analytics_backup" {
  count       = var.enable_cross_region_replication ? 1 : 0
  dataset_id  = "carbon_analytics_backup_${local.random_suffix}"
  project     = var.project_id
  location    = var.analytics_regions[1] # Use second region for backup
  description = "Backup dataset for carbon analytics data in secondary region"

  labels = merge(var.labels, {
    backup = "true"
  })

  depends_on = [google_project_service.required_apis]
}