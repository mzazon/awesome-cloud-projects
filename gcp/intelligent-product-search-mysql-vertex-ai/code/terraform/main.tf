# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  instance_name   = "${var.resource_prefix}-db-${local.resource_suffix}"
  bucket_name     = "${var.project_id}-${var.resource_prefix}-${local.resource_suffix}"
  function_name   = "${var.resource_prefix}-search-${local.resource_suffix}"
  
  # Database configuration
  db_password = random_password.db_password.result
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    resource-suffix = local.resource_suffix
    created-by      = "terraform"
    deployment-date = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Generate secure random password for Cloud SQL
resource "random_password" "db_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    read   = "10m"
  }
}

# Cloud Storage bucket for product data and function source code
resource "google_storage_bucket" "product_data" {
  name     = local.bucket_name
  location = var.region
  
  # Storage configuration
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.uniform_bucket_level_access
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 365
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
  
  # Public access prevention
  public_access_prevention = "enforced"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud SQL MySQL instance optimized for vector operations
resource "google_sql_database_instance" "product_db" {
  name             = local.instance_name
  database_version = "MYSQL_8_0"
  region           = var.region
  
  deletion_protection = var.deletion_protection
  
  settings {
    # Instance configuration
    tier              = var.db_instance_tier
    availability_type = "ZONAL"
    disk_type         = var.db_storage_type
    disk_size         = var.db_storage_size
    disk_autoresize   = var.enable_auto_increase
    
    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                     = var.db_backup_start_time
      location                       = var.region
      binary_log_enabled             = var.enable_binary_log
      transaction_log_retention_days = var.enable_binary_log_retention
      point_in_time_recovery_enabled = var.enable_point_in_time_recovery
      
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # Maintenance window
    maintenance_window {
      day  = var.db_maintenance_window_day
      hour = var.db_maintenance_window_hour
    }
    
    # IP configuration
    ip_configuration {
      ipv4_enabled = true
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
      
      require_ssl = var.enable_ssl
    }
    
    # Database flags for optimization
    database_flags {
      name  = "innodb_buffer_pool_size"
      value = "75%"
    }
    
    database_flags {
      name  = "max_connections"
      value = "1000"
    }
    
    database_flags {
      name  = "innodb_log_file_size"
      value = "256M"
    }
    
    # Insights configuration for monitoring
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
    
    user_labels = local.common_labels
  }
  
  depends_on = [google_project_service.required_apis]
}

# Set root password for Cloud SQL instance
resource "google_sql_user" "root" {
  name     = "root"
  instance = google_sql_database_instance.product_db.name
  host     = "%"
  password = local.db_password
  
  depends_on = [google_sql_database_instance.product_db]
}

# Create products database
resource "google_sql_database" "products" {
  name     = "products"
  instance = google_sql_database_instance.product_db.name
  charset  = "utf8mb4"
  collation = "utf8mb4_unicode_ci"
  
  depends_on = [google_sql_database_instance.product_db]
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  display_name = "Intelligent Product Search Function Service Account"
  description  = "Service account for Cloud Functions that handle product search and embedding generation"
}

# IAM binding for Cloud Functions service account - Cloud SQL Client
resource "google_project_iam_member" "function_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Functions service account - Vertex AI User
resource "google_project_iam_member" "function_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Functions service account - Storage Object Viewer
resource "google_project_iam_member" "function_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Functions service account - Logging
resource "google_project_iam_member" "function_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source-${local.resource_suffix}.zip"
  
  source {
    content  = file("${path.module}/function_code/main.py")
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.product_data.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for product search
resource "google_cloudfunctions2_function" "product_search" {
  name     = "${local.function_name}-search"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "search_products"
    
    source {
      storage_source {
        bucket = google_storage_bucket.product_data.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      PROJECT_ID    = var.project_id
      REGION        = var.region
      INSTANCE_NAME = local.instance_name
      DB_PASSWORD   = local.db_password
      LOG_LEVEL     = var.log_level
    }
    
    # VPC connector for private IP if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_private_ip ? [1] : []
      content {
        vpc_connector = google_vpc_access_connector.connector[0].id
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# Cloud Function for adding products
resource "google_cloudfunctions2_function" "product_add" {
  name     = "${local.function_name}-add"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "add_product"
    
    source {
      storage_source {
        bucket = google_storage_bucket.product_data.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      PROJECT_ID    = var.project_id
      REGION        = var.region
      INSTANCE_NAME = local.instance_name
      DB_PASSWORD   = local.db_password
      LOG_LEVEL     = var.log_level
    }
    
    # VPC connector for private IP if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_private_ip ? [1] : []
      content {
        vpc_connector = google_vpc_access_connector.connector[0].id
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# IAM for public access to Cloud Functions (can be restricted in production)
resource "google_cloudfunctions2_function_iam_member" "search_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.product_search.location
  cloud_function = google_cloudfunctions2_function.product_search.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "add_invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.product_add.location
  cloud_function = google_cloudfunctions2_function.product_add.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# VPC Connector for private IP access (optional)
resource "google_vpc_access_connector" "connector" {
  count   = var.enable_private_ip ? 1 : 0
  
  name          = "${var.resource_prefix}-vpc-connector-${local.resource_suffix}"
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
  region        = var.region
  
  machine_type   = "e2-micro"
  min_instances  = 2
  max_instances  = 3
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring Alert Policy for database CPU usage
resource "google_monitoring_alert_policy" "db_cpu_alert" {
  display_name = "Cloud SQL High CPU Usage - ${local.instance_name}"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud SQL instance CPU usage"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${local.instance_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring Alert Policy for function errors
resource "google_monitoring_alert_policy" "function_error_alert" {
  display_name = "Cloud Function High Error Rate - ${local.function_name}"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}-search\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.function_name"]
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Logging Sink for function logs (optional - for centralized logging)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${var.resource_prefix}-function-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.product_data.name}/logs"
  filter      = "resource.type=\"cloud_function\" AND resource.labels.function_name:\"${local.function_name}\""
  
  unique_writer_identity = true
}

# Grant logging sink permission to write to bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.product_data.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}