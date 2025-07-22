# TimesFM BigQuery DataCanvas Time Series Forecasting Infrastructure

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for computed names and configurations
locals {
  # Unique resource names
  bucket_name = "${var.storage_bucket_name}-${random_id.suffix.hex}"
  function_name = "${var.function_name}-${random_id.suffix.hex}"
  
  # Common labels
  common_labels = merge(var.labels, {
    terraform   = "true"
    recipe      = "timesfm-bigquery-datacanvas"
    created_by  = "terraform"
  })
  
  # API services required for the solution
  required_apis = var.enable_apis ? [
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com", 
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled
resource "time_sleep" "api_enablement" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Security and lifecycle configuration
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# Create BigQuery dataset for financial time series data
resource "google_bigquery_dataset" "financial_forecasting" {
  dataset_id  = var.dataset_name
  project     = var.project_id
  location    = var.bigquery_location
  
  friendly_name   = "Financial Time Series Forecasting Dataset"
  description     = "Dataset containing financial time series data and forecasting results using TimesFM"
  
  # Data retention and access controls
  default_table_expiration_ms = 1000 * 60 * 60 * 24 * 365 # 1 year
  delete_contents_on_destroy  = !var.deletion_protection
  
  labels = local.common_labels
  
  depends_on = [time_sleep.api_enablement]
}

# Create stock prices table with partitioning and clustering
resource "google_bigquery_table" "stock_prices" {
  dataset_id          = google_bigquery_dataset.financial_forecasting.dataset_id
  table_id            = "stock_prices"
  project             = var.project_id
  deletion_protection = var.deletion_protection
  
  description = "Historical stock price data partitioned by date and clustered by symbol for optimal query performance"
  
  # Time partitioning by date for efficient time-based queries
  time_partitioning {
    type  = "DAY"
    field = "date"
  }
  
  # Clustering by symbol for improved performance
  clustering = ["symbol"]
  
  # Schema definition
  schema = jsonencode([
    {
      name = "date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Trading date"
    },
    {
      name = "symbol"
      type = "STRING"
      mode = "REQUIRED"
      description = "Stock symbol (e.g., AAPL, GOOGL)"
    },
    {
      name = "close_price"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Closing price for the trading day"
    },
    {
      name = "volume"
      type = "INT64"
      mode = "NULLABLE"
      description = "Trading volume"
    },
    {
      name = "market_cap"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Market capitalization"
    },
    {
      name = "created_at"
      type = "TIMESTAMP"
      mode = "NULLABLE"
      description = "Record creation timestamp"
    }
  ])
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.financial_forecasting]
}

# Create TimesFM forecasts table
resource "google_bigquery_table" "timesfm_forecasts" {
  dataset_id          = google_bigquery_dataset.financial_forecasting.dataset_id
  table_id            = "timesfm_forecasts"
  project             = var.project_id
  deletion_protection = var.deletion_protection
  
  description = "TimesFM forecast results with prediction intervals and metadata"
  
  # Time partitioning by forecast timestamp
  time_partitioning {
    type  = "DAY"
    field = "forecast_timestamp"
  }
  
  # Clustering for query optimization
  clustering = ["symbol", "forecast_created_at"]
  
  # Schema for forecast results
  schema = jsonencode([
    {
      name = "symbol"
      type = "STRING"
      mode = "REQUIRED"
      description = "Stock symbol"
    },
    {
      name = "forecast_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp for the forecasted value"
    },
    {
      name = "forecast_value"
      type = "FLOAT64"
      mode = "REQUIRED"
      description = "Predicted value from TimesFM model"
    },
    {
      name = "prediction_interval_lower_bound"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Lower bound of prediction interval"
    },
    {
      name = "prediction_interval_upper_bound"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Upper bound of prediction interval"
    },
    {
      name = "forecast_created_at"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When the forecast was generated"
    },
    {
      name = "model_version"
      type = "STRING"
      mode = "NULLABLE"
      description = "TimesFM model version used"
    },
    {
      name = "confidence_level"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Confidence level for prediction intervals"
    }
  ])
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.financial_forecasting]
}

# Create forecast analytics view for DataCanvas
resource "google_bigquery_table" "forecast_analytics_view" {
  dataset_id = google_bigquery_dataset.financial_forecasting.dataset_id
  table_id   = "forecast_analytics"
  project    = var.project_id
  
  description = "Analytics view comparing forecasts with actual values for accuracy assessment"
  
  view {
    query = templatefile("${path.module}/sql/forecast_analytics_view.sql", {
      project_id   = var.project_id
      dataset_name = var.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_bigquery_table.stock_prices,
    google_bigquery_table.timesfm_forecasts
  ]
}

# Create trend analysis view for advanced analytics
resource "google_bigquery_table" "trend_analysis_view" {
  dataset_id = google_bigquery_dataset.financial_forecasting.dataset_id
  table_id   = "trend_analysis"
  project    = var.project_id
  
  description = "Trend analysis view with moving averages and volatility metrics"
  
  view {
    query = templatefile("${path.module}/sql/trend_analysis_view.sql", {
      project_id   = var.project_id
      dataset_name = var.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.stock_prices]
}

# Create service account for Cloud Function with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = "timesfm-function-${random_id.suffix.hex}"
  display_name = "TimesFM Cloud Function Service Account"
  description  = "Service account for Cloud Function processing financial data and triggering forecasts"
  project      = var.project_id
  
  depends_on = [time_sleep.api_enablement]
}

# Grant BigQuery Data Editor role to function service account
resource "google_project_iam_member" "function_bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant BigQuery Job User role for running queries
resource "google_project_iam_member" "function_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant Vertex AI User role for TimesFM model access
resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions
resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create archive of Cloud Function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id            = var.project_id
      dataset_name          = var.dataset_name
      forecast_horizon_days = var.forecast_horizon_days
      confidence_level      = var.confidence_level
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_object" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source_zip.output_path
  
  # Ensure new deployment on code changes
  detect_md5hash = data.archive_file.function_source_zip.output_md5
}

# Deploy Cloud Function for financial data processing
resource "google_cloudfunctions2_function" "forecast_processor" {
  name     = local.function_name
  location = var.region
  project  = var.project_id
  
  description = "Processes financial data and triggers TimesFM forecasting workflows"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_financial_data"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_object.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory_mb}Mi"
    timeout_seconds       = var.function_timeout_seconds
    service_account_email = google_service_account.function_sa.email
    
    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID            = var.project_id
      DATASET_NAME          = var.dataset_name
      FORECAST_HORIZON_DAYS = var.forecast_horizon_days
      CONFIDENCE_LEVEL      = var.confidence_level
      SYMBOLS               = join(",", var.forecast_symbols)
    }
    
    ingress_settings = "ALLOW_ALL"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_service_account.function_sa,
    google_project_iam_member.function_bigquery_data_editor,
    google_project_iam_member.function_bigquery_job_user,
    google_project_iam_member.function_vertex_ai_user
  ]
}

# Make Cloud Function publicly invokable (for HTTP trigger)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.forecast_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Cloud Scheduler job for daily forecasting
resource "google_cloud_scheduler_job" "daily_forecast" {
  name      = "daily-forecast-${random_id.suffix.hex}"
  region    = var.region
  project   = var.project_id
  schedule  = var.daily_forecast_schedule
  time_zone = var.scheduler_timezone
  
  description = "Automated daily financial forecasting using TimesFM"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.forecast_processor.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      action  = "daily_forecast"
      symbols = var.forecast_symbols
    }))
  }
  
  retry_config {
    retry_count = 3
  }
  
  depends_on = [google_cloudfunctions2_function.forecast_processor]
}

# Create Cloud Scheduler job for forecast accuracy monitoring
resource "google_cloud_scheduler_job" "forecast_monitor" {
  name      = "forecast-monitor-${random_id.suffix.hex}"
  region    = var.region
  project   = var.project_id
  schedule  = var.monitoring_schedule
  time_zone = var.scheduler_timezone
  
  description = "Monitor forecast accuracy and performance metrics"
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.forecast_processor.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      action = "monitor_accuracy"
    }))
  }
  
  retry_config {
    retry_count = 2
  }
  
  depends_on = [google_cloudfunctions2_function.forecast_processor]
}

# Create monitoring metrics table for forecast accuracy tracking
resource "google_bigquery_table" "forecast_metrics" {
  dataset_id          = google_bigquery_dataset.financial_forecasting.dataset_id
  table_id            = "forecast_metrics"
  project             = var.project_id
  deletion_protection = var.deletion_protection
  
  description = "Aggregated metrics for monitoring forecast accuracy and performance"
  
  # Partitioning for efficient metric queries
  time_partitioning {
    type  = "DAY"
    field = "metric_date"
  }
  
  clustering = ["symbol"]
  
  schema = jsonencode([
    {
      name = "symbol"
      type = "STRING"
      mode = "REQUIRED"
      description = "Stock symbol"
    },
    {
      name = "metric_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date for which metrics are calculated"
    },
    {
      name = "avg_percentage_error"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Average percentage error for forecasts"
    },
    {
      name = "error_std_dev"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Standard deviation of forecast errors"
    },
    {
      name = "forecast_count"
      type = "INT64"
      mode = "NULLABLE"
      description = "Number of forecasts evaluated"
    },
    {
      name = "accuracy_rate"
      type = "FLOAT64"
      mode = "NULLABLE"
      description = "Percentage of forecasts within confidence intervals"
    },
    {
      name = "calculated_at"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When metrics were calculated"
    }
  ])
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_dataset.financial_forecasting]
}

# Create alert conditions view for monitoring
resource "google_bigquery_table" "alert_conditions_view" {
  dataset_id = google_bigquery_dataset.financial_forecasting.dataset_id
  table_id   = "alert_conditions"
  project    = var.project_id
  
  description = "Alert conditions based on forecast accuracy thresholds"
  
  view {
    query = templatefile("${path.module}/sql/alert_conditions_view.sql", {
      project_id   = var.project_id
      dataset_name = var.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.forecast_metrics]
}