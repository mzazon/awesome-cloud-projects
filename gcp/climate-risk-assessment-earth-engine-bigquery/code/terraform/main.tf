# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for resource naming and configuration
locals {
  # Resource naming
  resource_suffix = random_string.suffix.result
  dataset_id      = "${var.project_name}-${var.environment}-${local.resource_suffix}"
  bucket_name     = "${var.project_name}-data-${var.environment}-${local.resource_suffix}"
  
  # Function names
  climate_processor_name = "${var.project_name}-processor-${var.environment}-${local.resource_suffix}"
  climate_monitor_name   = "${var.project_name}-monitor-${var.environment}-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    created-by = "terraform"
    project    = var.project_name
    env        = var.environment
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Functions
resource "google_service_account" "climate_functions_sa" {
  account_id   = "${var.project_name}-functions-sa"
  display_name = "Climate Risk Assessment Functions Service Account"
  description  = "Service account for climate risk assessment Cloud Functions"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "climate_functions_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.climate_functions_sa.email}"
}

resource "google_project_iam_member" "climate_functions_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.climate_functions_sa.email}"
}

resource "google_project_iam_member" "climate_functions_earth_engine" {
  project = var.project_id
  role    = "roles/earthengine.viewer"
  member  = "serviceAccount:${google_service_account.climate_functions_sa.email}"
}

resource "google_project_iam_member" "climate_functions_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.climate_functions_sa.email}"
}

resource "google_project_iam_member" "climate_functions_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.climate_functions_sa.email}"
}

# Create Cloud Storage bucket for climate data
resource "google_storage_bucket" "climate_data" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.storage_class
  project       = var.project_id
  
  # Enable versioning
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age_days
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Security settings
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.bucket_public_access_prevention
  
  # Labels
  labels = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create BigQuery dataset for climate data
resource "google_bigquery_dataset" "climate_dataset" {
  dataset_id    = local.dataset_id
  friendly_name = "Climate Risk Assessment Dataset"
  description   = var.dataset_description
  location      = var.dataset_location
  project       = var.project_id
  
  # Set dataset expiration if specified
  dynamic "default_table_expiration_ms" {
    for_each = var.table_expiration_days != null ? [1] : []
    content {
      default_table_expiration_ms = var.table_expiration_days * 24 * 60 * 60 * 1000
    }
  }
  
  # Access controls
  access {
    role          = "OWNER"
    user_by_email = google_service_account.climate_functions_sa.email
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }
  
  # Labels
  labels = local.common_labels
  
  delete_contents_on_destroy = var.dataset_delete_contents_on_destroy
  
  depends_on = [google_project_service.apis]
}

# Create BigQuery table for climate indicators
resource "google_bigquery_table" "climate_indicators" {
  dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
  table_id   = "climate_indicators"
  project    = var.project_id
  
  description = "Table storing processed climate indicators from Earth Engine satellite data"
  
  # Define table schema
  schema = jsonencode([
    {
      name = "longitude"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Longitude coordinate of the data point"
    },
    {
      name = "latitude"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Latitude coordinate of the data point"
    },
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "NULLABLE"
      description = "Geographic point location"
    },
    {
      name = "avg_day_temp_c"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average daytime temperature in Celsius"
    },
    {
      name = "avg_night_temp_c"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average nighttime temperature in Celsius"
    },
    {
      name = "total_precipitation_mm"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total precipitation in millimeters"
    },
    {
      name = "avg_ndvi"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average Normalized Difference Vegetation Index"
    },
    {
      name = "avg_evi"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average Enhanced Vegetation Index"
    },
    {
      name = "analysis_date"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Timestamp when the analysis was performed"
    },
    {
      name = "analysis_period_start"
      type = "DATE"
      mode = "NULLABLE"
      description = "Start date of the analysis period"
    },
    {
      name = "analysis_period_end"
      type = "DATE"
      mode = "NULLABLE"
      description = "End date of the analysis period"
    }
  ])
  
  # Clustering for better query performance
  clustering = ["analysis_period_start", "analysis_period_end"]
  
  # Time partitioning for efficient querying
  time_partitioning {
    type                     = "DAY"
    field                    = "analysis_date"
    require_partition_filter = false
  }
  
  labels = local.common_labels
}

# Create BigQuery table for climate extremes
resource "google_bigquery_table" "climate_extremes" {
  dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
  table_id   = "climate_extremes"
  project    = var.project_id
  
  description = "Table storing climate extreme events and risk assessments"
  
  schema = jsonencode([
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "REQUIRED"
      description = "Geographic location of the extreme event"
    },
    {
      name = "region_name"
      type = "STRING"
      mode = "NULLABLE"
      description = "Name of the geographic region"
    },
    {
      name = "extreme_heat_days"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of extreme heat days"
    },
    {
      name = "extreme_cold_days"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of extreme cold days"
    },
    {
      name = "drought_severity_index"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Drought severity index score"
    },
    {
      name = "flood_risk_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Flood risk assessment score"
    },
    {
      name = "temperature_trend_slope"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Temperature trend slope over time"
    },
    {
      name = "precipitation_trend_slope"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Precipitation trend slope over time"
    },
    {
      name = "vegetation_stress_indicator"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Vegetation stress indicator value"
    },
    {
      name = "risk_level"
      type = "STRING"
      mode = "NULLABLE"
      description = "Risk level classification (LOW, MEDIUM, HIGH)"
    },
    {
      name = "confidence_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Confidence score for the risk assessment"
    },
    {
      name = "last_updated"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Timestamp of last update"
    },
    {
      name = "data_source"
      type = "STRING"
      mode = "NULLABLE"
      description = "Source of the climate data"
    }
  ])
  
  # Clustering for better query performance
  clustering = ["risk_level", "region_name"]
  
  # Time partitioning
  time_partitioning {
    type                     = "DAY"
    field                    = "last_updated"
    require_partition_filter = false
  }
  
  labels = local.common_labels
}

# Create BigQuery table for risk assessments
resource "google_bigquery_table" "risk_assessments" {
  dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
  table_id   = "risk_assessments"
  project    = var.project_id
  
  description = "Table storing comprehensive climate risk assessments"
  
  schema = jsonencode([
    {
      name = "assessment_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the risk assessment"
    },
    {
      name = "location"
      type = "GEOGRAPHY"
      mode = "REQUIRED"
      description = "Geographic location of the assessment"
    },
    {
      name = "assessment_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Date and time of the risk assessment"
    },
    {
      name = "overall_risk_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Overall composite risk score"
    },
    {
      name = "heat_risk_component"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Heat-related risk component score"
    },
    {
      name = "drought_risk_component"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Drought-related risk component score"
    },
    {
      name = "flood_risk_component"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Flood-related risk component score"
    },
    {
      name = "ecosystem_risk_component"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Ecosystem-related risk component score"
    },
    {
      name = "adaptation_priority"
      type = "STRING"
      mode = "NULLABLE"
      description = "Adaptation priority level"
    },
    {
      name = "recommended_actions"
      type = "STRING"
      mode = "REPEATED"
      description = "List of recommended adaptation actions"
    },
    {
      name = "confidence_interval"
      type = "RECORD"
      mode = "NULLABLE"
      description = "Confidence interval for risk assessment"
      fields = [
        {
          name = "lower_bound"
          type = "FLOAT"
          mode = "NULLABLE"
        },
        {
          name = "upper_bound"
          type = "FLOAT"
          mode = "NULLABLE"
        }
      ]
    }
  ])
  
  # Clustering for better query performance
  clustering = ["adaptation_priority"]
  
  # Time partitioning
  time_partitioning {
    type                     = "DAY"
    field                    = "assessment_date"
    require_partition_filter = false
  }
  
  labels = local.common_labels
}

# Create BigQuery views for climate risk analysis
resource "google_bigquery_table" "climate_risk_analysis_view" {
  dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
  table_id   = "climate_risk_analysis"
  project    = var.project_id
  
  description = "View for analyzing climate risk patterns and trends"
  
  view {
    query = templatefile("${path.module}/sql/climate_risk_analysis.sql", {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.climate_indicators]
}

# Create BigQuery view for dashboard summary
resource "google_bigquery_table" "risk_dashboard_summary_view" {
  dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
  table_id   = "risk_dashboard_summary"
  project    = var.project_id
  
  description = "View providing dashboard summary data for climate risk visualization"
  
  view {
    query = templatefile("${path.module}/sql/risk_dashboard_summary.sql", {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.climate_dataset.dataset_id
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.climate_risk_analysis_view]
}

# Create source code archive for climate processor function
data "archive_file" "climate_processor_source" {
  type        = "zip"
  output_path = "${path.module}/climate_processor_source.zip"
  source_dir  = "${path.module}/functions/climate_processor"
}

# Create Cloud Function for climate data processing
resource "google_cloudfunctions_function" "climate_processor" {
  name        = local.climate_processor_name
  description = "Processes climate data from Earth Engine and loads to BigQuery"
  project     = var.project_id
  region      = var.region
  runtime     = var.function_runtime
  
  available_memory_mb   = var.function_memory_mb
  timeout               = var.function_timeout_seconds
  max_instances         = var.function_max_instances
  entry_point          = "process_climate_data"
  
  # Source code
  source_archive_bucket = google_storage_bucket.climate_data.name
  source_archive_object = google_storage_bucket_object.climate_processor_source.name
  
  # Trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Service account
  service_account_email = google_service_account.climate_functions_sa.email
  
  # Environment variables
  environment_variables = {
    PROJECT_ID     = var.project_id
    DATASET_ID     = google_bigquery_dataset.climate_dataset.dataset_id
    BUCKET_NAME    = google_storage_bucket.climate_data.name
    REGION         = var.region
    DEFAULT_START_DATE = var.default_analysis_start_date
    DEFAULT_END_DATE   = var.default_analysis_end_date
  }
  
  # Labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.climate_processor_source
  ]
}

# Create source code archive for climate monitoring function
data "archive_file" "climate_monitor_source" {
  type        = "zip"
  output_path = "${path.module}/climate_monitor_source.zip"
  source_dir  = "${path.module}/functions/climate_monitor"
}

# Create Cloud Function for climate monitoring
resource "google_cloudfunctions_function" "climate_monitor" {
  name        = local.climate_monitor_name
  description = "Monitors climate risk levels and generates alerts"
  project     = var.project_id
  region      = var.region
  runtime     = var.function_runtime
  
  available_memory_mb = 1024
  timeout            = 300
  max_instances      = 5
  entry_point        = "monitor_climate_risks"
  
  # Source code
  source_archive_bucket = google_storage_bucket.climate_data.name
  source_archive_object = google_storage_bucket_object.climate_monitor_source.name
  
  # Trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Service account
  service_account_email = google_service_account.climate_functions_sa.email
  
  # Environment variables
  environment_variables = {
    PROJECT_ID = var.project_id
    DATASET_ID = google_bigquery_dataset.climate_dataset.dataset_id
    REGION     = var.region
  }
  
  # Labels
  labels = local.common_labels
  
  depends_on = [
    google_project_service.apis,
    google_storage_bucket_object.climate_monitor_source
  ]
}

# Upload climate processor source code to Cloud Storage
resource "google_storage_bucket_object" "climate_processor_source" {
  name   = "climate_processor_source.zip"
  bucket = google_storage_bucket.climate_data.name
  source = data.archive_file.climate_processor_source.output_path
  
  depends_on = [data.archive_file.climate_processor_source]
}

# Upload climate monitor source code to Cloud Storage
resource "google_storage_bucket_object" "climate_monitor_source" {
  name   = "climate_monitor_source.zip"
  bucket = google_storage_bucket.climate_data.name
  source = data.archive_file.climate_monitor_source.output_path
  
  depends_on = [data.archive_file.climate_monitor_source]
}

# Create Cloud Monitoring alert policy for high climate risk
resource "google_monitoring_alert_policy" "high_climate_risk" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "High Climate Risk Alert"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "High risk percentage threshold"
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/climate_risk/high_risk_percentage\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 25.0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Notification channels
  dynamic "notification_channels" {
    for_each = var.notification_channels
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Monitoring dashboard for climate risk
resource "google_monitoring_dashboard" "climate_risk_dashboard" {
  project        = var.project_id
  dashboard_json = templatefile("${path.module}/monitoring/climate_risk_dashboard.json", {
    project_id = var.project_id
    region     = var.region
  })
  
  depends_on = [google_project_service.apis]
}