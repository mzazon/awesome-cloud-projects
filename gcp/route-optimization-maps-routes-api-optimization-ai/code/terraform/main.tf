# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming
  name_prefix = "${var.application_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment    = var.environment
    application    = var.application_name
    deployed-by    = "terraform"
    creation-date  = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Service names
  sql_instance_name    = "${local.name_prefix}-db-${local.name_suffix}"
  cloud_run_name      = "${local.name_prefix}-service-${local.name_suffix}"
  pubsub_topic_name   = "${local.name_prefix}-events-${local.name_suffix}"
  function_name       = "${local.name_prefix}-processor-${local.name_suffix}"
  
  # Database configuration
  database_name = "route_analytics"
  database_user = "postgres"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent automatic disabling of APIs when destroying
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Generate secure random password for Cloud SQL
resource "random_password" "db_password" {
  length  = 16
  special = true
  
  # Ensure password meets Cloud SQL requirements
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
}

# Cloud SQL instance for route analytics and persistent storage
resource "google_sql_database_instance" "route_analytics" {
  name             = local.sql_instance_name
  database_version = var.sql_database_version
  region          = var.region
  project         = var.project_id
  
  # Prevent accidental deletion in production
  deletion_protection = var.environment == "prod" ? true : false
  
  depends_on = [google_project_service.required_apis]
  
  settings {
    tier              = var.sql_tier
    availability_type = var.sql_ha_enabled ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.sql_disk_size
    disk_autoresize   = true
    
    # Backup configuration
    backup_configuration {
      enabled                        = var.sql_backup_enabled
      start_time                     = "03:00"
      location                       = var.region
      point_in_time_recovery_enabled = var.sql_backup_enabled
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration
    ip_configuration {
      ipv4_enabled                                  = !var.enable_private_ip
      private_network                               = var.enable_private_ip ? google_compute_network.vpc_network[0].id : null
      enable_private_path_for_google_cloud_services = var.enable_private_ip
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    # Database flags for optimization
    database_flags {
      name  = "max_connections"
      value = "100"
    }
    
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    
    # Maintenance window
    maintenance_window {
      day  = 7  # Sunday
      hour = 3  # 3 AM
    }
    
    # User labels
    user_labels = local.common_labels
  }
}

# Create the main database
resource "google_sql_database" "route_analytics_db" {
  name     = local.database_name
  instance = google_sql_database_instance.route_analytics.name
  project  = var.project_id
}

# Set password for the default postgres user
resource "google_sql_user" "postgres_user" {
  name     = local.database_user
  instance = google_sql_database_instance.route_analytics.name
  password = random_password.db_password.result
  project  = var.project_id
}

# VPC network for private Cloud SQL access (optional)
resource "google_compute_network" "vpc_network" {
  count                   = var.enable_private_ip ? 1 : 0
  name                    = "${local.name_prefix}-vpc-${local.name_suffix}"
  auto_create_subnetworks = false
  project                 = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Private IP allocation for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  count         = var.enable_private_ip ? 1 : 0
  name          = "${local.name_prefix}-private-ip-${local.name_suffix}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network[0].id
  project       = var.project_id
}

# Private connection for Cloud SQL
resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.enable_private_ip ? 1 : 0
  network                 = google_compute_network.vpc_network[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[0].name]
}

# Pub/Sub topic for route optimization events
resource "google_pubsub_topic" "route_events" {
  name    = local.pubsub_topic_name
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
  
  labels = local.common_labels
  
  # Message storage policy
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  # Schema settings for message validation
  schema_settings {
    encoding = "JSON"
  }
}

# Pub/Sub subscription for route processing
resource "google_pubsub_subscription" "route_events_sub" {
  name    = "${local.pubsub_topic_name}-sub"
  topic   = google_pubsub_topic.route_events.name
  project = var.project_id
  
  # Acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline
  
  # Message retention duration
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter queue configuration
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.route_events_dlq.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Dead letter queue for failed messages
resource "google_pubsub_topic" "route_events_dlq" {
  name    = "${local.pubsub_topic_name}-dlq"
  project = var.project_id
  
  labels = local.common_labels
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

resource "google_pubsub_subscription" "route_events_dlq_sub" {
  name    = "${local.pubsub_topic_name}-dlq-sub"
  topic   = google_pubsub_topic.route_events_dlq.name
  project = var.project_id
  
  labels = local.common_labels
}

# Service account for Cloud Run service
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${substr(local.name_prefix, 0, 20)}-run-${local.name_suffix}"
  display_name = "Cloud Run Service Account for Route Optimizer"
  description  = "Service account for Cloud Run route optimization service"
  project      = var.project_id
}

# IAM bindings for Cloud Run service account
resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cloud_run_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Cloud Run service for route optimization API
resource "google_cloud_run_v2_service" "route_optimizer" {
  name     = local.cloud_run_name
  location = var.region
  project  = var.project_id
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.route_analytics,
    google_pubsub_topic.route_events
  ]
  
  template {
    # Scaling configuration
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    
    # Service account
    service_account = google_service_account.cloud_run_sa.email
    
    # Timeout configuration
    timeout = "${var.cloud_run_timeout}s"
    
    containers {
      # Container image (placeholder - will be updated during deployment)
      image = "gcr.io/cloudrun/hello"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "SQL_INSTANCE"
        value = google_sql_database_instance.route_analytics.connection_name
      }
      
      env {
        name  = "DATABASE_NAME"
        value = google_sql_database.route_analytics_db.name
      }
      
      env {
        name  = "DATABASE_USER"
        value = google_sql_user.postgres_user.name
      }
      
      env {
        name = "DATABASE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      
      env {
        name  = "TOPIC_NAME"
        value = google_pubsub_topic.route_events.name
      }
      
      env {
        name = "MAPS_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.maps_api_key.secret_id
            version = "latest"
          }
        }
      }
      
      # Health check port
      ports {
        container_port = 8080
        name          = "http1"
      }
      
      # Startup probe
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 3
        failure_threshold    = 5
      }
      
      # Liveness probe
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
    }
    
    # VPC access (if private networking is enabled)
    dynamic "vpc_access" {
      for_each = var.enable_private_ip ? [1] : []
      content {
        connector = google_vpc_access_connector.connector[0].id
        egress    = "PRIVATE_RANGES_ONLY"
      }
    }
    
    # Annotations
    annotations = {
      "autoscaling.knative.dev/maxScale"         = tostring(var.cloud_run_max_instances)
      "autoscaling.knative.dev/minScale"         = tostring(var.cloud_run_min_instances)
      "run.googleapis.com/cloudsql-instances"    = google_sql_database_instance.route_analytics.connection_name
      "run.googleapis.com/cpu-throttling"        = "false"
      "run.googleapis.com/execution-environment" = "gen2"
    }
    
    labels = local.common_labels
  }
  
  # Traffic configuration
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  labels = local.common_labels
}

# VPC Access Connector for private networking (optional)
resource "google_vpc_access_connector" "connector" {
  count         = var.enable_private_ip ? 1 : 0
  name          = "${local.name_prefix}-connector-${local.name_suffix}"
  region        = var.region
  project       = var.project_id
  network       = google_compute_network.vpc_network[0].name
  ip_cidr_range = "10.8.0.0/28"
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Run IAM policy for public access
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_v2_service.route_optimizer.name
  location = google_cloud_run_v2_service.route_optimizer.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = var.project_id
}

# Secret Manager for storing sensitive configuration
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.name_prefix}-db-password-${local.name_suffix}"
  project   = var.project_id
  
  labels = local.common_labels
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret" "maps_api_key" {
  secret_id = "${local.name_prefix}-maps-api-key-${local.name_suffix}"
  project   = var.project_id
  
  labels = local.common_labels
  
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "maps_api_key" {
  secret      = google_secret_manager_secret.maps_api_key.id
  secret_data = var.maps_api_key
}

# IAM access to secrets for Cloud Run
resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
  project   = var.project_id
}

resource "google_secret_manager_secret_iam_member" "maps_api_key_access" {
  secret_id = google_secret_manager_secret.maps_api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
  project   = var.project_id
}

# Service account for Cloud Function
resource "google_service_account" "cloud_function_sa" {
  account_id   = "${substr(local.name_prefix, 0, 20)}-fn-${local.name_suffix}"
  display_name = "Cloud Function Service Account for Route Processor"
  description  = "Service account for Cloud Function route event processor"
  project      = var.project_id
}

# IAM bindings for Cloud Function service account
resource "google_project_iam_member" "cloud_function_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source-${local.name_suffix}"
  location = var.region
  project  = var.project_id
  
  # Prevent accidental deletion
  force_destroy = var.environment != "prod"
  
  # Versioning for function source code
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Function for processing route events
resource "google_cloudfunctions2_function" "route_processor" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Process route optimization events from Pub/Sub"
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_subscription.route_events_sub
  ]
  
  build_config {
    runtime     = "python311"
    entry_point = "process_route_event"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = "function-source.zip"
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "${var.cloud_function_memory}MB"
    timeout_seconds                  = var.cloud_function_timeout
    max_instance_request_concurrency = 1
    
    # Service account
    service_account_email = google_service_account.cloud_function_sa.email
    
    # Environment variables
    environment_variables = {
      PROJECT_ID    = var.project_id
      SQL_INSTANCE  = google_sql_database_instance.route_analytics.connection_name
      DATABASE_NAME = google_sql_database.route_analytics_db.name
      DATABASE_USER = google_sql_user.postgres_user.name
    }
    
    # Secret environment variables
    secret_environment_variables {
      key        = "DATABASE_PASSWORD"
      project_id = var.project_id
      secret     = google_secret_manager_secret.db_password.secret_id
      version    = "latest"
    }
    
    # VPC connector (if private networking is enabled)
    dynamic "vpc_connector" {
      for_each = var.enable_private_ip ? [1] : []
      content {
        name          = google_vpc_access_connector.connector[0].name
        egress_settings = "PRIVATE_RANGES_ONLY"
      }
    }
  }
  
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic         = google_pubsub_topic.route_events.id
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.cloud_function_sa.email
  }
  
  labels = local.common_labels
}

# Cloud Monitoring alert policies (optional)
resource "google_monitoring_alert_policy" "high_error_rate" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Route Optimizer - High Error Rate"
  project      = var.project_id
  
  conditions {
    display_name = "Cloud Run error rate too high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.route_optimizer.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  documentation {
    content = "Cloud Run service ${google_cloud_run_v2_service.route_optimizer.name} is experiencing high error rates."
  }
  
  combiner = "OR"
  enabled  = true
}

# Log router for structured logging
resource "google_logging_project_sink" "route_optimizer_sink" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "${local.name_prefix}-logs-${local.name_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.logs_bucket[0].name}"
  
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${google_cloud_run_v2_service.route_optimizer.name}\""
  
  unique_writer_identity = true
}

# Storage bucket for log archival
resource "google_storage_bucket" "logs_bucket" {
  count    = var.enable_monitoring ? 1 : 0
  name     = "${local.name_prefix}-logs-${local.name_suffix}"
  location = var.region
  project  = var.project_id
  
  # Lifecycle management for logs
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Cost optimization - move to coldline after 30 days
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  labels = local.common_labels
}

# IAM binding for log sink
resource "google_storage_bucket_iam_member" "logs_writer" {
  count  = var.enable_monitoring ? 1 : 0
  bucket = google_storage_bucket.logs_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.route_optimizer_sink[0].writer_identity
}