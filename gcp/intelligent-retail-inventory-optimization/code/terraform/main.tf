# Main Terraform configuration for intelligent retail inventory optimization
# This configuration deploys a comprehensive solution including BigQuery analytics,
# Vertex AI for demand forecasting, Cloud Optimization AI, Fleet Engine integration,
# and Cloud Run microservices for real-time inventory management

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and resource organization
locals {
  # Use provided suffix or generate random one
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common resource naming pattern
  name_prefix = "retail-inventory"
  
  # Common labels applied to all resources
  common_labels = merge({
    project       = "intelligent-retail-inventory"
    solution      = "inventory-optimization"
    terraform     = "true"
    environment   = var.environment
    created-by    = "terraform"
  }, var.deployment_labels)
  
  # Service account email pattern
  service_account_email = "inventory-optimizer-sa@${var.project_id}.iam.gserviceaccount.com"
  
  # BigQuery dataset and table names
  bigquery_dataset_name = "${var.bigquery_dataset_id}_${local.resource_suffix}"
  
  # Cloud Storage bucket names
  data_bucket_name = "${local.name_prefix}-data-${var.project_id}-${local.resource_suffix}"
  
  # Cloud Run service names
  analytics_service_name = "${local.name_prefix}-analytics-${local.resource_suffix}"
  optimizer_service_name = "${local.name_prefix}-optimizer-${local.resource_suffix}"
  
  # Required APIs for the solution
  required_apis = [
    "bigquery.googleapis.com",
    "aiplatform.googleapis.com", 
    "optimization.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ]
  
  # Fleet Engine APIs (optional, requires special access)
  fleet_apis = var.enable_fleet_engine ? [
    "fleetengine.googleapis.com",
    "maps-android-backend.googleapis.com",
    "maps-ios-backend.googleapis.com"
  ] : []
  
  all_apis = concat(local.required_apis, local.fleet_apis)
}

#
# Enable Required Google Cloud APIs
#

resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.all_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying infrastructure
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Wait for APIs to be fully enabled before creating dependent resources
resource "time_sleep" "wait_for_apis" {
  count = var.enable_apis ? 1 : 0
  
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

#
# Service Account for Inventory Optimization System
#

resource "google_service_account" "inventory_optimizer" {
  account_id   = "inventory-optimizer-sa"
  display_name = "Inventory Optimization Service Account"
  description  = "Service account for intelligent retail inventory optimization system"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "inventory_optimizer_roles" {
  for_each = toset([
    "roles/bigquery.admin",
    "roles/aiplatform.user", 
    "roles/storage.admin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/run.invoker"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.inventory_optimizer.email}"
}

# Additional roles for Fleet Engine if enabled
resource "google_project_iam_member" "fleet_engine_roles" {
  for_each = var.enable_fleet_engine ? toset([
    "roles/fleetengine.admin",
    "roles/optimization.admin"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.inventory_optimizer.email}"
}

#
# Cloud Storage Infrastructure
#

# Primary data bucket for analytics pipeline
resource "google_storage_bucket" "data_bucket" {
  name     = local.data_bucket_name
  location = var.storage_bucket_location
  project  = var.project_id
  
  # Storage class configuration
  storage_class = var.storage_bucket_storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days * 3
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Create organized directory structure in the bucket
resource "google_storage_bucket_object" "bucket_directories" {
  for_each = toset([
    "raw-data/.keep",
    "processed-data/.keep", 
    "ml-models/.keep",
    "optimization-results/.keep",
    "fleet-configs/.keep"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.data_bucket.name
  content = " " # Empty content for directory markers
}

# Grant service account access to the bucket
resource "google_storage_bucket_iam_member" "data_bucket_access" {
  bucket = google_storage_bucket.data_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.inventory_optimizer.email}"
}

#
# BigQuery Data Warehouse Infrastructure
#

# BigQuery dataset for retail analytics
resource "google_bigquery_dataset" "retail_analytics" {
  dataset_id  = local.bigquery_dataset_name
  project     = var.project_id
  location    = var.bigquery_location
  description = "Retail inventory optimization analytics dataset"
  
  # Access control
  access {
    role          = "OWNER"
    user_by_email = google_service_account.inventory_optimizer.email
  }
  
  access {
    role         = "READER"
    special_group = "projectReaders"
  }
  
  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }
  
  # Data retention and lifecycle
  default_table_expiration_ms = var.bigquery_default_table_expiration_ms
  delete_contents_on_destroy  = var.bigquery_delete_contents_on_destroy
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Inventory levels table
resource "google_bigquery_table" "inventory_levels" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "inventory_levels"
  project    = var.project_id
  
  description = "Current inventory levels across all store locations"
  
  schema = jsonencode([
    {
      name = "store_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for store location"
    },
    {
      name = "product_id"
      type = "STRING" 
      mode = "REQUIRED"
      description = "Unique identifier for product"
    },
    {
      name = "current_stock"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Current inventory quantity"
    },
    {
      name = "max_capacity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Maximum storage capacity for this product"
    },
    {
      name = "min_threshold"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Minimum stock threshold before reorder"
    },
    {
      name = "last_updated"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp of last inventory update"
    }
  ])
  
  labels = local.common_labels
}

# Sales history table for ML training
resource "google_bigquery_table" "sales_history" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "sales_history"
  project    = var.project_id
  
  description = "Historical sales data for demand forecasting"
  
  schema = jsonencode([
    {
      name = "transaction_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique transaction identifier"
    },
    {
      name = "store_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Store location identifier"
    },
    {
      name = "product_id"
      type = "STRING"
      mode = "REQUIRED" 
      description = "Product identifier"
    },
    {
      name = "quantity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Quantity sold"
    },
    {
      name = "price"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Sale price per unit"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Transaction timestamp"
    },
    {
      name = "customer_demographics"
      type = "STRING"
      mode = "NULLABLE"
      description = "Customer demographic information"
    }
  ])
  
  labels = local.common_labels
}

# Store locations table for geographic optimization
resource "google_bigquery_table" "store_locations" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "store_locations"
  project    = var.project_id
  
  description = "Store location and capacity information"
  
  schema = jsonencode([
    {
      name = "store_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique store identifier"
    },
    {
      name = "store_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Store display name"
    },
    {
      name = "latitude"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Store latitude coordinate"
    },
    {
      name = "longitude"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Store longitude coordinate"
    },
    {
      name = "region"
      type = "STRING"
      mode = "REQUIRED"
      description = "Geographic region or district"
    },
    {
      name = "store_type"
      type = "STRING"
      mode = "REQUIRED" 
      description = "Store type or format"
    },
    {
      name = "capacity_tier"
      type = "STRING"
      mode = "REQUIRED"
      description = "Store capacity classification"
    }
  ])
  
  labels = local.common_labels
}

# Training data table for demand forecasting
resource "google_bigquery_table" "demand_training_data" {
  dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
  table_id   = "demand_training_data"
  project    = var.project_id
  
  description = "Training data for demand forecasting ML model"
  
  schema = jsonencode([
    {
      name = "store_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Store identifier"
    },
    {
      name = "product_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Product identifier"
    },
    {
      name = "date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date of sales data"
    },
    {
      name = "sales_quantity"
      type = "INTEGER"
      mode = "REQUIRED"
      description = "Quantity sold on this date"
    },
    {
      name = "weather_condition"
      type = "STRING"
      mode = "NULLABLE"
      description = "Weather condition for the day"
    },
    {
      name = "promotion_active"
      type = "BOOLEAN"
      mode = "NULLABLE"
      description = "Whether promotion was active"
    },
    {
      name = "competitor_price"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Competitor pricing information"
    },
    {
      name = "season"
      type = "STRING"
      mode = "NULLABLE"
      description = "Season classification"
    }
  ])
  
  labels = local.common_labels
}

#
# Vertex AI Infrastructure
#

# Vertex AI Metadata Store for ML artifact tracking
resource "google_vertex_ai_metadata_store" "inventory_ml_store" {
  count = var.enable_vertex_ai_metadata_store ? 1 : 0
  
  name        = "inventory-ml-metadata-${local.resource_suffix}"
  description = "Metadata store for inventory optimization ML artifacts"
  region      = var.vertex_ai_region
  project     = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Vertex AI Tensorboard for model monitoring
resource "google_vertex_ai_tensorboard" "inventory_tensorboard" {
  count = var.enable_vertex_ai_tensorboard ? 1 : 0
  
  display_name = "inventory-optimization-tensorboard-${local.resource_suffix}"
  description  = "Tensorboard for monitoring inventory optimization models"
  region       = var.vertex_ai_region
  project      = var.project_id
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

#
# Cloud Run Analytics Service
#

resource "google_cloud_run_v2_service" "analytics_service" {
  name     = local.analytics_service_name
  location = var.region
  project  = var.project_id
  
  deletion_policy = "ABANDON"
  
  template {
    # Service account configuration
    service_account = google_service_account.inventory_optimizer.email
    
    # Scaling configuration
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    # Container configuration
    containers {
      # Use a placeholder image - will be replaced during deployment
      image = "gcr.io/cloudrun/hello"
      
      # Resource limits
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "DATASET_NAME"
        value = google_bigquery_dataset.retail_analytics.dataset_id
      }
      
      env {
        name  = "BUCKET_NAME" 
        value = google_storage_bucket.data_bucket.name
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      
      # Health check endpoint
      ports {
        container_port = 8080
      }
    }
    
    # Request timeout
    timeout = "${var.cloud_run_timeout}s"
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  labels = local.common_labels
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_bigquery_dataset.retail_analytics,
    google_storage_bucket.data_bucket
  ]
}

# IAM policy for analytics service (optional unauthenticated access)
resource "google_cloud_run_service_iam_member" "analytics_invoker" {
  count = var.allow_unauthenticated_cloud_run ? 1 : 0
  
  service  = google_cloud_run_v2_service.analytics_service.name
  location = google_cloud_run_v2_service.analytics_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = var.project_id
}

#
# Cloud Run Optimization Service
#

resource "google_cloud_run_v2_service" "optimizer_service" {
  name     = local.optimizer_service_name
  location = var.region
  project  = var.project_id
  
  deletion_policy = "ABANDON"
  
  template {
    # Service account configuration
    service_account = google_service_account.inventory_optimizer.email
    
    # Scaling configuration
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    # Container configuration
    containers {
      # Use a placeholder image - will be replaced during deployment
      image = "gcr.io/cloudrun/hello"
      
      # Resource limits (optimizer needs more resources)
      resources {
        limits = {
          cpu    = "2"
          memory = "4Gi"
        }
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "BUCKET_NAME"
        value = google_storage_bucket.data_bucket.name
      }
      
      env {
        name  = "ANALYTICS_URL"
        value = google_cloud_run_v2_service.analytics_service.uri
      }
      
      env {
        name  = "FLEET_ENGINE_ENABLED"
        value = tostring(var.enable_fleet_engine)
      }
      
      env {
        name  = "FLEET_PROVIDER_ID"
        value = var.fleet_engine_provider_id
      }
      
      # Health check endpoint
      ports {
        container_port = 8080
      }
    }
    
    # Extended timeout for optimization processing
    timeout = "900s"
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  labels = local.common_labels
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_cloud_run_v2_service.analytics_service
  ]
}

# IAM policy for optimizer service (optional unauthenticated access)
resource "google_cloud_run_service_iam_member" "optimizer_invoker" {
  count = var.allow_unauthenticated_cloud_run ? 1 : 0
  
  service  = google_cloud_run_v2_service.optimizer_service.name
  location = google_cloud_run_v2_service.optimizer_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = var.project_id
}

#
# Cloud Monitoring Infrastructure
#

# Log sink for Cloud Run services
resource "google_logging_project_sink" "cloud_run_logs" {
  count = var.enable_cloud_monitoring ? 1 : 0
  
  name        = "inventory-optimization-logs-${local.resource_suffix}"
  description = "Log sink for inventory optimization Cloud Run services"
  
  # Send logs to BigQuery for analysis
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.retail_analytics.dataset_id}"
  
  # Filter for Cloud Run logs
  filter = <<EOF
resource.type="cloud_run_revision"
resource.labels.service_name="${local.analytics_service_name}" OR 
resource.labels.service_name="${local.optimizer_service_name}"
EOF
  
  # Create a unique writer identity
  unique_writer_identity = true
}

# Grant BigQuery Data Editor role to log sink writer
resource "google_project_iam_member" "log_sink_writer" {
  count = var.enable_cloud_monitoring ? 1 : 0
  
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.cloud_run_logs[0].writer_identity
}

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_cloud_monitoring && var.monitoring_notification_email != "" ? 1 : 0
  
  display_name = "Inventory Optimization Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.monitoring_notification_email
  }
  
  description = "Email notifications for inventory optimization system alerts"
}

# Alert policy for Cloud Run service errors
resource "google_monitoring_alert_policy" "cloud_run_errors" {
  count = var.enable_cloud_monitoring ? 1 : 0
  
  display_name = "Inventory Optimization Service Errors"
  project      = var.project_id
  
  documentation {
    content   = "Alert when inventory optimization services experience high error rates"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Send notifications if email is configured
  dynamic "notification_channels" {
    for_each = var.monitoring_notification_email != "" ? [1] : []
    content {
      notification_channels = [google_monitoring_notification_channel.email[0].id]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  enabled = true
}

#
# Sample Data Creation (for development/testing)
#

# Upload sample training data to BigQuery
resource "google_bigquery_job" "load_sample_data" {
  count = var.create_sample_data ? 1 : 0
  
  job_id   = "load-sample-data-${local.resource_suffix}"
  project  = var.project_id
  location = var.bigquery_location
  
  load {
    source_uris = [
      "gs://${google_storage_bucket.data_bucket.name}/sample-data/*"
    ]
    
    destination_table {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.retail_analytics.dataset_id
      table_id   = google_bigquery_table.demand_training_data.table_id
    }
    
    source_format = "CSV"
    skip_leading_rows = 1
    write_disposition = "WRITE_TRUNCATE"
    
    schema_update_options = ["ALLOW_FIELD_ADDITION"]
  }
  
  # Only run after bucket and tables are created
  depends_on = [
    google_storage_bucket.data_bucket,
    google_bigquery_table.demand_training_data
  ]
}