# ==============================================================================
# LARGE-SCALE DATA PROCESSING WITH BIGQUERY SERVERLESS SPARK
# ==============================================================================
# This Terraform configuration creates the infrastructure for large-scale data
# processing using BigQuery Serverless Spark, Cloud Storage, and supporting
# services. The infrastructure includes data lake storage, analytics datasets,
# and IAM permissions for secure data processing workflows.
# ==============================================================================

# Configure the Google Cloud Provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
  }
  required_version = ">= 1.0"
}

# Get current project information
data "google_project" "current" {}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# ==============================================================================
# API ENABLEMENT
# ==============================================================================
# Enable required Google Cloud APIs for the data processing pipeline

resource "google_project_service" "required_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "dataproc.googleapis.com",
    "notebooks.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent disabling APIs on terraform destroy
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ==============================================================================
# CLOUD STORAGE RESOURCES
# ==============================================================================
# Create Cloud Storage bucket for data lake with appropriate configuration

# Data lake bucket for raw and processed data
resource "google_storage_bucket" "data_lake" {
  name     = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id

  # Storage class for cost optimization
  storage_class = "STANDARD"

  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_transition_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = var.lifecycle_deletion_days
    }
    action {
      type = "Delete"
    }
  }

  # Public access prevention for security
  public_access_prevention = "enforced"

  # Uniform bucket-level access for simplified IAM
  uniform_bucket_level_access = true

  # Labels for resource management and billing
  labels = merge(var.labels, {
    component = "data-lake"
    service   = "cloud-storage"
    recipe    = "bigquery-serverless-spark"
  })

  depends_on = [google_project_service.required_apis]
}

# Create folder structure using storage bucket objects
resource "google_storage_bucket_object" "raw_data_folder" {
  name         = "raw-data/.gitkeep"
  content      = "# Raw data storage folder"
  bucket       = google_storage_bucket.data_lake.name
  content_type = "text/plain"
}

resource "google_storage_bucket_object" "processed_data_folder" {
  name         = "processed-data/.gitkeep"
  content      = "# Processed data storage folder"
  bucket       = google_storage_bucket.data_lake.name
  content_type = "text/plain"
}

resource "google_storage_bucket_object" "scripts_folder" {
  name         = "scripts/.gitkeep"
  content      = "# Spark scripts storage folder"
  bucket       = google_storage_bucket.data_lake.name
  content_type = "text/plain"
}

# Upload sample transaction data for demonstration
resource "google_storage_bucket_object" "sample_data" {
  name   = "raw-data/sample_transactions.csv"
  bucket = google_storage_bucket.data_lake.name
  content = templatefile("${path.module}/sample_data/sample_transactions.csv", {
    # Template variables can be added here if needed
  })
  content_type = "text/csv"

  depends_on = [google_storage_bucket_object.raw_data_folder]
}

# ==============================================================================
# BIGQUERY RESOURCES
# ==============================================================================
# Create BigQuery dataset for analytics and result storage

resource "google_bigquery_dataset" "analytics_dataset" {
  dataset_id  = "${var.dataset_name_prefix}_${random_id.suffix.hex}"
  project     = var.project_id
  location    = var.region
  description = "Analytics dataset for Serverless Spark data processing"

  # Data retention and deletion policies
  default_table_expiration_ms = var.table_expiration_days * 24 * 60 * 60 * 1000

  # Access control
  access {
    role          = "OWNER"
    user_by_email = var.dataset_owner_email
  }

  access {
    role         = "READER"
    special_group = "projectReaders"
  }

  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }

  # Enable deletion protection for production datasets
  delete_contents_on_destroy = var.enable_dataset_deletion

  # Labels for resource management
  labels = merge(var.labels, {
    component = "analytics"
    service   = "bigquery"
    recipe    = "bigquery-serverless-spark"
  })

  depends_on = [google_project_service.required_apis]
}

# Create placeholder tables for analytics results
resource "google_bigquery_table" "customer_analytics" {
  dataset_id          = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id            = "customer_analytics"
  project             = var.project_id
  description         = "Customer analytics results from Spark processing"
  deletion_protection = var.enable_table_deletion_protection

  schema = jsonencode([
    {
      name = "customer_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique customer identifier"
    },
    {
      name = "year_month"
      type = "STRING"
      mode = "REQUIRED"
      description = "Year-month period (YYYY-MM)"
    },
    {
      name = "transaction_count"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of transactions in the period"
    },
    {
      name = "total_spent"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total amount spent by customer"
    },
    {
      name = "avg_transaction_value"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average transaction value"
    },
    {
      name = "unique_categories"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of unique product categories purchased"
    },
    {
      name = "customer_segment"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer segment (Premium, Standard, Basic)"
    }
  ])

  labels = var.labels
}

resource "google_bigquery_table" "product_analytics" {
  dataset_id          = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id            = "product_analytics"
  project             = var.project_id
  description         = "Product performance analytics from Spark processing"
  deletion_protection = var.enable_table_deletion_protection

  schema = jsonencode([
    {
      name = "product_category"
      type = "STRING"
      mode = "REQUIRED"
      description = "Product category"
    },
    {
      name = "year_month"
      type = "STRING"
      mode = "REQUIRED"
      description = "Year-month period (YYYY-MM)"
    },
    {
      name = "total_quantity_sold"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total quantity sold in the period"
    },
    {
      name = "category_revenue"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total revenue for the category"
    },
    {
      name = "unique_customers"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of unique customers who purchased"
    },
    {
      name = "avg_unit_price"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average unit price in the category"
    },
    {
      name = "revenue_per_customer"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average revenue per customer"
    }
  ])

  labels = var.labels
}

resource "google_bigquery_table" "location_analytics" {
  dataset_id          = google_bigquery_dataset.analytics_dataset.dataset_id
  table_id            = "location_analytics"
  project             = var.project_id
  description         = "Location-based analytics from Spark processing"
  deletion_protection = var.enable_table_deletion_protection

  schema = jsonencode([
    {
      name = "store_location"
      type = "STRING"
      mode = "REQUIRED"
      description = "Store location"
    },
    {
      name = "product_category"
      type = "STRING"
      mode = "REQUIRED"
      description = "Product category"
    },
    {
      name = "year_month"
      type = "STRING"
      mode = "REQUIRED"
      description = "Year-month period (YYYY-MM)"
    },
    {
      name = "location_category_revenue"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Revenue for location and category combination"
    },
    {
      name = "transaction_volume"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Number of transactions"
    }
  ])

  labels = var.labels
}

# ==============================================================================
# IAM AND SERVICE ACCOUNTS
# ==============================================================================
# Create service account for Serverless Spark jobs

resource "google_service_account" "spark_service_account" {
  account_id   = "${var.service_account_prefix}-${random_id.suffix.hex}"
  display_name = "Serverless Spark Service Account"
  description  = "Service account for BigQuery Serverless Spark data processing jobs"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the Spark service account
resource "google_project_iam_member" "spark_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.spark_service_account.email}"
}

resource "google_project_iam_member" "spark_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.spark_service_account.email}"
}

resource "google_project_iam_member" "spark_dataproc_admin" {
  project = var.project_id
  role    = "roles/dataproc.admin"
  member  = "serviceAccount:${google_service_account.spark_service_account.email}"
}

resource "google_project_iam_member" "spark_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.spark_service_account.email}"
}

resource "google_project_iam_member" "spark_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.spark_service_account.email}"
}

# ==============================================================================
# DATAPROC SERVERLESS CONFIGURATION
# ==============================================================================
# Create Dataproc Serverless batch template for reusable configurations

resource "google_dataproc_batch" "spark_session_template" {
  count     = var.create_sample_batch ? 1 : 0
  batch_id  = "${var.batch_job_prefix}-${random_id.suffix.hex}"
  location  = var.region
  project   = var.project_id

  pyspark_batch {
    main_python_file_uri = "gs://${google_storage_bucket.data_lake.name}/scripts/data_processing_spark.py"
    
    jar_file_uris = [
      "gs://spark-lib/bigquery/spark-bigquery-with-dependencies_2.12-0.36.1.jar"
    ]

    args = [
      "--input-path=gs://${google_storage_bucket.data_lake.name}/raw-data/sample_transactions.csv",
      "--output-dataset=${var.project_id}.${google_bigquery_dataset.analytics_dataset.dataset_id}"
    ]
  }

  runtime_config {
    version = "2.2"
    
    properties = {
      "spark.executor.instances"                      = "2"
      "spark.executor.memory"                         = "4g"
      "spark.executor.cores"                          = "2"
      "spark.sql.adaptive.enabled"                   = "true"
      "spark.sql.adaptive.coalescePartitions.enabled" = "true"
      "spark.dynamicAllocation.enabled"              = "true"
      "spark.dynamicAllocation.minExecutors"         = "1"
      "spark.dynamicAllocation.maxExecutors"         = "10"
    }
  }

  environment_config {
    execution_config {
      service_account = google_service_account.spark_service_account.email
      
      network_tags = var.network_tags
      
      ttl = var.batch_job_ttl
    }
  }

  labels = merge(var.labels, {
    component = "spark-batch"
    service   = "dataproc-serverless"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.sample_data
  ]
}

# ==============================================================================
# MONITORING AND LOGGING
# ==============================================================================
# Create Cloud Monitoring dashboards for Spark job monitoring

resource "google_monitoring_dashboard" "spark_dashboard" {
  count        = var.create_monitoring_dashboard ? 1 : 0
  display_name = "BigQuery Serverless Spark Analytics Dashboard"
  project      = var.project_id

  dashboard_json = jsonencode({
    displayName = "BigQuery Serverless Spark Analytics Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Dataproc Batch Job Status"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"dataproc_batch\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "BigQuery Job Execution"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"bigquery_project\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Create log-based metrics for job monitoring
resource "google_logging_metric" "spark_job_success" {
  count  = var.create_log_metrics ? 1 : 0
  name   = "spark_job_success_rate"
  filter = "resource.type=\"dataproc_batch\" AND jsonPayload.message=~\".*completed successfully.*\""
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Spark Job Success Rate"
    description  = "Number of successful Spark job completions"
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_logging_metric" "spark_job_failure" {
  count  = var.create_log_metrics ? 1 : 0
  name   = "spark_job_failure_rate"
  filter = "resource.type=\"dataproc_batch\" AND (jsonPayload.message=~\".*failed.*\" OR jsonPayload.message=~\".*error.*\")"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Spark Job Failure Rate"
    description  = "Number of failed Spark job executions"
  }

  depends_on = [google_project_service.required_apis]
}

# ==============================================================================
# SAMPLE DATA AND SCRIPTS
# ==============================================================================
# Upload sample PySpark script for data processing

resource "google_storage_bucket_object" "spark_processing_script" {
  name   = "scripts/data_processing_spark.py"
  bucket = google_storage_bucket.data_lake.name
  source = "${path.module}/scripts/data_processing_spark.py"
  
  depends_on = [google_storage_bucket_object.scripts_folder]
}

# Upload Spark session configuration template
resource "google_storage_bucket_object" "spark_config" {
  name   = "scripts/spark_session_config.json"
  bucket = google_storage_bucket.data_lake.name
  content = jsonencode({
    sessionTemplate = {
      name        = "data-processing-session"
      description = "Serverless Spark session for large-scale data processing"
      runtimeConfig = {
        version = "2.2"
        properties = {
          "spark.executor.instances"                      = "auto"
          "spark.executor.memory"                         = "4g"
          "spark.executor.cores"                          = "2"
          "spark.sql.adaptive.enabled"                   = "true"
          "spark.sql.adaptive.coalescePartitions.enabled" = "true"
        }
      }
      environmentConfig = {
        executionConfig = {
          serviceAccount  = google_service_account.spark_service_account.email
          subnetworkUri   = "default"
        }
      }
    }
  })
  content_type = "application/json"
  
  depends_on = [google_storage_bucket_object.scripts_folder]
}

# ==============================================================================
# NOTIFICATION CHANNELS (OPTIONAL)
# ==============================================================================
# Create notification channels for alerting

resource "google_monitoring_notification_channel" "email_notification" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Email Notification Channel"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Create alerting policies for job failures
resource "google_monitoring_alert_policy" "spark_job_failure_alert" {
  count        = var.create_alerts && var.notification_email != "" ? 1 : 0
  display_name = "Spark Job Failure Alert"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Spark job failure condition"
    
    condition_threshold {
      filter          = "resource.type=\"dataproc_batch\" AND metric.type=\"logging.googleapis.com/user/spark_job_failure_rate\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email_notification[0].id]

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.spark_job_failure
  ]
}