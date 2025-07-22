# BigQuery Query Optimization Infrastructure with AI and Cloud Composer
# This file creates the complete infrastructure for automated query optimization

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source for current project information
data "google_project" "current" {}

# Data source for client configuration
data "google_client_config" "current" {}

# Local values for computed configurations
locals {
  # Unique suffix for all resources
  suffix = random_id.suffix.hex
  
  # Full resource names
  dataset_name           = "${var.dataset_name}_${local.suffix}"
  bucket_name           = "${var.resource_prefix}-${var.project_id}-${local.suffix}"
  composer_env_name     = "${var.composer_environment_name}-${local.suffix}"
  
  # Service account names
  composer_sa_name  = "${var.resource_prefix}-composer-sa-${local.suffix}"
  bigquery_sa_name  = "${var.resource_prefix}-bigquery-sa-${local.suffix}"
  vertex_ai_sa_name = "${var.resource_prefix}-vertex-sa-${local.suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment    = var.environment
    resource-group = "query-optimization"
    created-by     = "terraform"
    suffix        = local.suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "bigquery.googleapis.com",
    "composer.googleapis.com",
    "aiplatform.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com"
  ]) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Cloud Storage bucket for Composer and ML artifacts
resource "google_storage_bucket" "optimization_bucket" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.bucket_storage_class
  labels        = local.common_labels

  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }

  # Enable versioning for important artifacts
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for multipart uploads cleanup
  lifecycle_rule {
    condition {
      age                   = 1
      with_state           = "LIVE"
      matches_storage_class = ["MULTIREGIONAL", "REGIONAL", "STANDARD"]
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  # Public access prevention
  public_access_prevention = "enforced"

  depends_on = [google_project_service.required_apis]
}

# BigQuery dataset for analytics and optimization
resource "google_bigquery_dataset" "optimization_dataset" {
  dataset_id    = local.dataset_name
  friendly_name = "Query Optimization Analytics Dataset"
  description   = var.dataset_description
  location      = var.dataset_location
  labels        = local.common_labels

  # Access controls
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.client_email
  }

  # Default table expiration for cost control
  default_table_expiration_ms = var.enable_cost_controls ? var.table_expiration_days * 24 * 60 * 60 * 1000 : null

  depends_on = [google_project_service.required_apis]
}

# Sample sales transactions table for testing optimization
resource "google_bigquery_table" "sales_transactions" {
  dataset_id = google_bigquery_dataset.optimization_dataset.dataset_id
  table_id   = "sales_transactions"
  labels     = local.common_labels

  # Table schema definition
  schema = jsonencode([
    {
      name = "transaction_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "customer_id"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "product_id"
      type = "INT64"
      mode = "REQUIRED"
    },
    {
      name = "amount"
      type = "FLOAT64"
      mode = "REQUIRED"
    },
    {
      name = "transaction_date"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "channel"
      type = "STRING"
      mode = "REQUIRED"
    }
  ])

  # Partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "transaction_date"
  }

  # Clustering for query optimization
  clustering = ["channel", "customer_id"]

  deletion_protection = false
}

# Query performance metrics view
resource "google_bigquery_table" "query_performance_view" {
  dataset_id = google_bigquery_dataset.optimization_dataset.dataset_id
  table_id   = "query_performance_metrics"
  labels     = local.common_labels

  view {
    query = templatefile("${path.module}/sql/query_performance_view.sql", {
      project_id = var.project_id
      region     = var.region
      dataset_id = local.dataset_name
    })
    use_legacy_sql = false
  }

  depends_on = [google_bigquery_dataset.optimization_dataset]
}

# Optimization recommendations table
resource "google_bigquery_table" "optimization_recommendations" {
  dataset_id = google_bigquery_dataset.optimization_dataset.dataset_id
  table_id   = "optimization_recommendations"
  labels     = local.common_labels

  schema = jsonencode([
    {
      name = "recommendation_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "query_hash"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "original_query"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "optimized_query"
      type = "STRING"
      mode = "NULLABLE"
    },
    {
      name = "optimization_type"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "estimated_improvement_percent"
      type = "FLOAT64"
      mode = "NULLABLE"
    },
    {
      name = "implementation_status"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "created_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "applied_timestamp"
      type = "TIMESTAMP"
      mode = "NULLABLE"
    }
  ])

  # Partitioning by creation date
  time_partitioning {
    type  = "DAY"
    field = "created_timestamp"
  }

  # Clustering for efficient queries
  clustering = ["optimization_type", "implementation_status"]

  deletion_protection = false
}

# Materialized view for sales summary optimization
resource "google_bigquery_table" "sales_summary_mv" {
  dataset_id = google_bigquery_dataset.optimization_dataset.dataset_id
  table_id   = "sales_summary_mv"
  labels     = local.common_labels

  materialized_view {
    query = templatefile("${path.module}/sql/sales_summary_mv.sql", {
      project_id = var.project_id
      dataset_id = local.dataset_name
      partition_days = var.materialized_view_partition_days
    })
    
    enable_refresh = true
    refresh_interval_ms = var.materialized_view_refresh_interval * 60 * 1000
  }

  # Partitioning for performance
  time_partitioning {
    type  = "DAY"
    field = "transaction_date"
  }

  # Clustering for optimization
  clustering = ["channel"]

  deletion_protection = false
  depends_on = [google_bigquery_table.sales_transactions]
}

# Service Account for Cloud Composer
resource "google_service_account" "composer_sa" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = local.composer_sa_name
  display_name = "Cloud Composer Service Account for Query Optimization"
  description  = "Service account for Cloud Composer environment managing query optimization workflows"
}

# Service Account for BigQuery operations
resource "google_service_account" "bigquery_sa" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = local.bigquery_sa_name
  display_name = "BigQuery Service Account for Query Optimization"
  description  = "Service account for BigQuery query optimization operations"
}

# Service Account for Vertex AI operations
resource "google_service_account" "vertex_ai_sa" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = local.vertex_ai_sa_name
  display_name = "Vertex AI Service Account for Query Optimization"
  description  = "Service account for Vertex AI training and prediction jobs"
}

# IAM bindings for Composer service account
resource "google_project_iam_member" "composer_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/bigquery.admin",
    "roles/storage.admin",
    "roles/aiplatform.user",
    "roles/monitoring.editor",
    "roles/composer.worker"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.composer_sa[0].email}"
}

# IAM bindings for BigQuery service account
resource "google_project_iam_member" "bigquery_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/bigquery.admin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.bigquery_sa[0].email}"
}

# IAM bindings for Vertex AI service account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/aiplatform.user",
    "roles/storage.objectUser",
    "roles/bigquery.dataViewer"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.vertex_ai_sa[0].email}"
}

# Cloud Composer environment for orchestration
resource "google_composer_environment" "optimization_env" {
  name   = local.composer_env_name
  region = var.region
  labels = local.common_labels

  config {
    node_count = var.composer_node_count

    node_config {
      zone         = var.zone
      machine_type = var.composer_machine_type
      disk_size_gb = var.composer_disk_size

      # Use custom service account if created
      service_account = var.create_service_accounts ? google_service_account.composer_sa[0].email : null

      # Network configuration
      subnetwork = "default"
    }

    software_config {
      image_version  = "composer-2-airflow-2"
      python_version = var.composer_python_version

      # Environment variables for DAGs
      env_variables = {
        PROJECT_ID    = var.project_id
        DATASET_NAME  = local.dataset_name
        BUCKET_NAME   = local.bucket_name
        REGION        = var.region
        ENVIRONMENT   = var.environment
      }

      # PyPI packages for query optimization
      pypi_packages = {
        "google-cloud-bigquery"     = ""
        "google-cloud-aiplatform"   = ""
        "google-cloud-monitoring"   = ""
        "pandas"                    = ""
        "scikit-learn"             = ""
        "numpy"                    = ""
      }
    }

    # Web server access control
    web_server_access_control {
      allowed_ip_range {
        value = "0.0.0.0/0"
      }
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.optimization_bucket,
    google_bigquery_dataset.optimization_dataset
  ]
}

# Upload query optimization DAG to Composer
resource "google_storage_bucket_object" "optimization_dag" {
  name   = "dags/query_optimization_dag.py"
  bucket = google_composer_environment.optimization_env.config[0].dag_gcs_prefix
  content = templatefile("${path.module}/dags/query_optimization_dag.py", {
    project_id   = var.project_id
    dataset_name = local.dataset_name
    bucket_name  = local.bucket_name
    region       = var.region
  })

  depends_on = [google_composer_environment.optimization_env]
}

# Upload ML training script
resource "google_storage_bucket_object" "ml_training_script" {
  name   = "ml/query_optimization_model.py"
  bucket = local.bucket_name
  content = templatefile("${path.module}/ml/query_optimization_model.py", {
    project_id   = var.project_id
    dataset_name = local.dataset_name
    bucket_name  = local.bucket_name
  })

  depends_on = [google_storage_bucket.optimization_bucket]
}

# Monitoring dashboard for query optimization
resource "google_monitoring_dashboard" "optimization_dashboard" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "BigQuery Query Optimization Dashboard"

  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    project_id = var.project_id
    dataset_id = local.dataset_name
  })

  depends_on = [google_project_service.required_apis]
}

# Alert policy for optimization failures
resource "google_monitoring_alert_policy" "optimization_failures" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Query Optimization Pipeline Failures"
  combiner     = "OR"

  conditions {
    display_name = "High failure rate in optimization pipeline"
    
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_name=~\"${local.composer_env_name}.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Notification channels (if provided)
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      name = notification_channels.value
    }
  }

  documentation {
    content   = "Alert triggered when query optimization pipeline experiences high failure rates"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for query performance degradation
resource "google_monitoring_alert_policy" "query_performance_degradation" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "BigQuery Query Performance Degradation"
  combiner     = "OR"

  conditions {
    display_name = "Average query duration increase"
    
    condition_threshold {
      filter          = "resource.type=\"bigquery_project\""
      duration        = "600s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10000 # 10 seconds

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Notification channels (if provided)
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      name = notification_channels.value
    }
  }

  documentation {
    content   = "Alert triggered when BigQuery query performance degrades significantly"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}