# Multi-Container Cloud Run Application with Cloud SQL and Secret Manager
# This configuration deploys a complete multi-container application on Google Cloud Run
# with PostgreSQL database, secure secret management, and container registry

# Local values for computed resources and naming
locals {
  # Generate unique suffix for resource names to avoid conflicts
  random_suffix = random_id.suffix.hex

  # Compute full resource names with environment and suffix
  service_name     = "${var.service_name}-${var.environment}-${local.random_suffix}"
  db_instance_name = "${var.database_instance_name}-${var.environment}-${local.random_suffix}"
  repository_name  = "${var.repository_name}-${var.environment}-${local.random_suffix}"

  # Merged labels combining default and user-provided labels
  common_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      application = "multi-container-app"
    },
    var.labels
  )

  # Cloud SQL connection name for proxy configuration
  sql_connection_name = "${var.project_id}:${var.region}:${local.db_instance_name}"
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Generate secure random password for database user
resource "random_password" "db_password" {
  length  = 32
  special = true
  upper   = true
  lower   = true
  numeric = true

  # Ensure password meets PostgreSQL requirements
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent disabling services when destroying
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Artifact Registry repository for container images
resource "google_artifact_registry_repository" "container_repo" {
  location      = var.region
  repository_id = local.repository_name
  description   = "Docker repository for multi-container application images"
  format        = "DOCKER"

  # Cleanup policies to manage storage costs
  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    
    condition {
      tag_state  = "UNTAGGED"
      older_than = "2592000s" # 30 days
    }
  }

  cleanup_policies {
    id     = "keep-recent-tagged"
    action = "KEEP"
    
    condition {
      tag_state    = "TAGGED"
      newer_than   = "86400s" # 1 day
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud SQL PostgreSQL database instance
resource "google_sql_database_instance" "postgres" {
  name             = local.db_instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  
  # Deletion protection for production environments
  deletion_protection = var.deletion_protection

  settings {
    tier                  = var.database_tier
    availability_type     = var.environment == "prod" ? "REGIONAL" : "ZONAL"
    disk_type            = "PD_SSD"
    disk_size            = var.database_disk_size
    disk_autoresize      = true
    disk_autoresize_limit = var.database_disk_size * 2

    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"  # 2 AM UTC
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }

    # Security and access settings
    ip_configuration {
      ipv4_enabled                                  = length(var.authorized_networks) > 0
      private_network                              = var.vpc_connector_name != "" ? data.google_compute_network.vpc[0].id : null
      enable_private_path_for_google_cloud_services = true
      require_ssl                                   = true

      # Authorized networks for external access (if configured)
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
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    # Performance insights
    insights_config {
      query_insights_enabled  = true
      query_plans_per_minute  = 5
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }

    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM UTC
      update_track = "stable"
    }

    user_labels = local.common_labels
  }

  depends_on = [google_project_service.required_apis]
}

# Application database within the Cloud SQL instance
resource "google_sql_database" "app_database" {
  name     = var.database_name
  instance = google_sql_database_instance.postgres.name
  charset  = "UTF8"
  collation = "en_US.UTF8"
}

# Database user for the application
resource "google_sql_user" "app_user" {
  name     = var.database_user
  instance = google_sql_database_instance.postgres.name
  password = random_password.db_password.result
  type     = "BUILT_IN"

  depends_on = [google_sql_database.app_database]
}

# Store database password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.service_name}-db-password"
  
  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Store database connection string in Secret Manager
resource "google_secret_manager_secret" "db_connection_string" {
  secret_id = "${local.service_name}-db-connection"
  
  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_connection_string" {
  secret = google_secret_manager_secret.db_connection_string.id
  secret_data = "postgresql://${var.database_user}:${random_password.db_password.result}@localhost:5432/${var.database_name}"
}

# Service account for Cloud Run service
resource "google_service_account" "cloud_run" {
  account_id   = "${local.service_name}-sa"
  display_name = "Service Account for ${local.service_name}"
  description  = "Service account used by the multi-container Cloud Run service"
}

# IAM binding for Secret Manager access
resource "google_secret_manager_secret_iam_binding" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:${google_service_account.cloud_run.email}"
  ]
}

resource "google_secret_manager_secret_iam_binding" "db_connection_access" {
  secret_id = google_secret_manager_secret.db_connection_string.secret_id
  role      = "roles/secretmanager.secretAccessor"

  members = [
    "serviceAccount:${google_service_account.cloud_run.email}"
  ]
}

# IAM binding for Cloud SQL client access
resource "google_project_iam_binding" "cloud_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"

  members = [
    "serviceAccount:${google_service_account.cloud_run.email}"
  ]
}

# Cloud Run v2 service with multi-container support
resource "google_cloud_run_v2_service" "multi_container_app" {
  name     = local.service_name
  location = var.region
  
  labels = local.common_labels

  template {
    service_account = google_service_account.cloud_run.email
    
    # Scaling configuration
    scaling {
      min_instance_count = var.min_scale
      max_instance_count = var.max_scale
    }

    # VPC connector for private networking (if configured)
    dynamic "vpc_access" {
      for_each = var.vpc_connector_name != "" ? [1] : []
      content {
        connector = var.vpc_connector_name
        egress    = "PRIVATE_RANGES_ONLY"
      }
    }

    # Proxy container (Nginx) - serves as the main container
    containers {
      name  = "proxy"
      image = var.container_images.proxy

      ports {
        name           = "http1"
        container_port = 8000
      }

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        cpu_idle = true
        startup_cpu_boost = true
      }

      # Health check for proxy
      startup_probe {
        http_get {
          path = "/health"
          port = 8000
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8000
        }
        timeout_seconds   = 5
        period_seconds    = 30
        failure_threshold = 3
      }
    }

    # Frontend container
    containers {
      name  = "frontend"
      image = var.container_images.frontend

      ports {
        name           = "frontend"
        container_port = 3000
      }

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        cpu_idle = true
      }

      env {
        name  = "NODE_ENV"
        value = var.environment == "prod" ? "production" : "development"
      }

      env {
        name  = "PORT"
        value = "3000"
      }
    }

    # Backend container
    containers {
      name  = "backend"
      image = var.container_images.backend

      ports {
        name           = "backend"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        cpu_idle = true
      }

      env {
        name  = "NODE_ENV"
        value = var.environment == "prod" ? "production" : "development"
      }

      env {
        name  = "PORT"
        value = "8080"
      }

      # Database password from Secret Manager
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      # Database connection details
      env {
        name  = "DB_HOST"
        value = "localhost"
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = var.database_name
      }

      env {
        name  = "DB_USER"
        value = var.database_user
      }
    }

    # Cloud SQL Proxy sidecar container
    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.8.0"

      args = [
        "--port=5432",
        "--address=0.0.0.0",
        local.sql_connection_name
      ]

      resources {
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
        cpu_idle = true
      }

      # Health check for SQL proxy
      startup_probe {
        tcp_socket {
          port = 5432
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 5
        failure_threshold    = 12
      }

      liveness_probe {
        tcp_socket {
          port = 5432
        }
        timeout_seconds   = 5
        period_seconds    = 60
        failure_threshold = 2
      }
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.postgres,
    google_sql_user.app_user,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_version.db_connection_string
  ]
}

# IAM policy for public access (if enabled)
resource "google_cloud_run_v2_service_iam_binding" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.multi_container_app.name
  role     = "roles/run.invoker"

  members = [
    "allUsers"
  ]
}

# Data source for VPC network (if VPC connector is used)
data "google_compute_network" "vpc" {
  count = var.vpc_connector_name != "" ? 1 : 0
  name  = split("/", var.vpc_connector_name)[5] # Extract network name from connector
}

# Wait for Cloud Run service to be ready
resource "time_sleep" "wait_for_service" {
  depends_on = [google_cloud_run_v2_service.multi_container_app]
  create_duration = "30s"
}