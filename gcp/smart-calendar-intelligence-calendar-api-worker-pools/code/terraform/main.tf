# Smart Calendar Intelligence Infrastructure with Cloud Run Worker Pools
# This configuration deploys a complete calendar intelligence solution using
# Google Cloud services including Worker Pools, Cloud Tasks, Vertex AI, and BigQuery

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

locals {
  # Computed values for resource naming and configuration
  suffix = random_id.suffix.hex
  
  # Resource names with computed suffix
  worker_pool_name = "${var.resource_prefix}-${var.worker_pool_config.name}-${local.suffix}"
  api_service_name = "${var.resource_prefix}-${var.api_service_config.name}-${local.suffix}"
  task_queue_name  = "${var.resource_prefix}-${var.task_queue_config.name}-${local.suffix}"
  bucket_name      = var.storage_config.bucket_name != null ? var.storage_config.bucket_name : "${var.resource_prefix}-${var.project_id}-${local.suffix}"
  dataset_id       = "${var.bigquery_config.dataset_id}_${local.suffix}"
  
  # Service account names
  worker_service_account_name = "${var.resource_prefix}-worker-${local.suffix}"
  api_service_account_name    = "${var.resource_prefix}-api-${local.suffix}"
  
  # Combined labels
  common_labels = merge(var.labels, {
    environment = var.environment
    suffix      = local.suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "calendar-json.googleapis.com",
    "run.googleapis.com", 
    "cloudtasks.googleapis.com",
    "aiplatform.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project                    = var.project_id
  service                   = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Wait for APIs to be enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.required_apis]
  create_duration = "60s"
}

# ============================================================================
# IAM SERVICE ACCOUNTS
# ============================================================================

# Service account for Calendar Intelligence Worker Pool
resource "google_service_account" "worker_service_account" {
  count = var.iam_config.create_service_accounts ? 1 : 0
  
  account_id   = local.worker_service_account_name
  display_name = "Calendar Intelligence Worker Pool Service Account"
  description  = "Service account for calendar analysis worker pool with AI processing permissions"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# Service account for API Service
resource "google_service_account" "api_service_account" {
  count = var.iam_config.create_service_accounts ? 1 : 0
  
  account_id   = local.api_service_account_name
  display_name = "Calendar Intelligence API Service Account"
  description  = "Service account for calendar intelligence API service"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM bindings for worker service account
resource "google_project_iam_member" "worker_permissions" {
  for_each = var.iam_config.create_service_accounts ? toset([
    "roles/aiplatform.user",
    "roles/bigquery.dataEditor", 
    "roles/storage.objectAdmin",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.worker_service_account[0].email}"
  
  depends_on = [google_service_account.worker_service_account]
}

# IAM bindings for API service account
resource "google_project_iam_member" "api_permissions" {
  for_each = var.iam_config.create_service_accounts ? toset([
    "roles/cloudtasks.enqueuer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.api_service_account[0].email}"
  
  depends_on = [google_service_account.api_service_account]
}

# ============================================================================
# ARTIFACT REGISTRY
# ============================================================================

# Artifact Registry repository for container images
resource "google_artifact_registry_repository" "calendar_intelligence" {
  repository_id = "${var.resource_prefix}-repository-${local.suffix}"
  location      = var.region
  format        = "DOCKER"
  description   = "Container repository for calendar intelligence services"
  project       = var.project_id
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# ============================================================================
# CLOUD STORAGE
# ============================================================================

# Cloud Storage bucket for model artifacts and data storage
resource "google_storage_bucket" "calendar_intelligence" {
  name     = local.bucket_name
  location = var.storage_config.location
  project  = var.project_id
  
  storage_class                = var.storage_config.storage_class
  uniform_bucket_level_access  = true
  force_destroy               = var.bigquery_config.delete_contents_on_destroy
  
  labels = local.common_labels
  
  # Versioning configuration
  dynamic "versioning" {
    for_each = var.storage_config.versioning_enabled ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle rules
  dynamic "lifecycle_rule" {
    for_each = var.storage_config.lifecycle_rules
    content {
      action {
        type = lifecycle_rule.value.action.type
      }
      condition {
        age = lifecycle_rule.value.condition.age
      }
    }
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# ============================================================================
# BIGQUERY
# ============================================================================

# BigQuery dataset for calendar analytics
resource "google_bigquery_dataset" "calendar_analytics" {
  dataset_id    = local.dataset_id
  friendly_name = "Calendar Intelligence Analytics"
  description   = var.bigquery_config.description
  location      = var.region
  project       = var.project_id
  
  delete_contents_on_destroy      = var.bigquery_config.delete_contents_on_destroy
  default_table_expiration_ms     = var.bigquery_config.default_table_expiration_ms
  
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# BigQuery table for calendar insights storage
resource "google_bigquery_table" "calendar_insights" {
  dataset_id = google_bigquery_dataset.calendar_analytics.dataset_id
  table_id   = "calendar_insights"
  project    = var.project_id
  
  description = "Storage for calendar intelligence insights and analysis results"
  
  labels = local.common_labels
  
  schema = jsonencode([
    {
      name = "calendar_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Unique identifier for the calendar being analyzed"
    },
    {
      name = "analysis_timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Timestamp when the analysis was performed"
    },
    {
      name = "insights"
      type = "STRING"
      mode = "NULLABLE"
      description = "AI-generated insights and recommendations in JSON format"
    },
    {
      name = "processed_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date when the calendar data was processed"
    },
    {
      name = "meeting_frequency"
      type = "INTEGER"
      mode = "NULLABLE"
      description = "Total number of meetings analyzed"
    },
    {
      name = "productivity_score"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Calculated productivity score (0-100)"
    },
    {
      name = "optimization_recommendations"
      type = "STRING"
      mode = "REPEATED"
      description = "List of specific optimization recommendations"
    }
  ])
  
  depends_on = [google_bigquery_dataset.calendar_analytics]
}

# ============================================================================
# CLOUD TASKS QUEUE
# ============================================================================

# Cloud Tasks queue for calendar analysis job distribution
resource "google_cloud_tasks_queue" "calendar_tasks" {
  name     = local.task_queue_name
  location = var.region
  project  = var.project_id
  
  rate_limits {
    max_concurrent_dispatches   = var.task_queue_config.max_concurrent_dispatches
    max_dispatches_per_second   = var.task_queue_config.max_dispatches_per_second
  }
  
  retry_config {
    max_retry_duration = var.task_queue_config.max_retry_duration
    max_attempts      = var.task_queue_config.max_attempts
    
    min_backoff = "1s"
    max_backoff = "300s"
    max_doublings = 5
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# ============================================================================
# CLOUD RUN WORKER POOL
# ============================================================================

# Cloud Run Worker Pool for calendar intelligence processing
resource "google_cloud_run_v2_worker_pool" "calendar_intelligence" {
  name     = local.worker_pool_name
  location = var.region
  project  = var.project_id
  
  deletion_protection = false
  launch_stage       = "BETA"
  
  labels = local.common_labels
  
  template {
    # Service account configuration
    service_account = var.iam_config.create_service_accounts ? google_service_account.worker_service_account[0].email : var.worker_pool_config.service_account_email
    
    # Container configuration
    containers {
      name  = "calendar-worker"
      image = var.worker_pool_config.container_image
      
      # Resource limits
      resources {
        limits = {
          cpu    = var.worker_pool_config.cpu_limit
          memory = var.worker_pool_config.memory_limit
        }
      }
      
      # Environment variables
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "GOOGLE_CLOUD_REGION"
        value = var.region
      }
      
      env {
        name  = "DATASET_NAME"
        value = local.dataset_id
      }
      
      env {
        name  = "BUCKET_NAME"
        value = local.bucket_name
      }
      
      env {
        name  = "TASK_QUEUE_NAME"
        value = local.task_queue_name
      }
      
      env {
        name  = "LOG_LEVEL"
        value = var.monitoring_config.log_level
      }
      
      # Vertex AI configuration
      dynamic "env" {
        for_each = var.vertex_ai_config.enable_vertex_ai ? [1] : []
        content {
          name  = "VERTEX_AI_MODEL"
          value = var.vertex_ai_config.model_name
        }
      }
      
      dynamic "env" {
        for_each = var.vertex_ai_config.enable_vertex_ai ? [1] : []
        content {
          name  = "VERTEX_AI_LOCATION"
          value = var.vertex_ai_config.model_location
        }
      }
    }
    
    # VPC access configuration
    dynamic "vpc_access" {
      for_each = var.network_config.enable_direct_vpc ? [1] : []
      content {
        network_interfaces {
          network    = var.network_config.vpc_network
          subnetwork = var.network_config.vpc_subnetwork
        }
      }
    }
  }
  
  # Scaling configuration
  scaling {
    scaling_mode         = "AUTOMATIC"
    min_instance_count   = var.worker_pool_config.min_instance_count
    max_instance_count   = var.worker_pool_config.max_instance_count
  }
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_service_account.worker_service_account,
    google_bigquery_dataset.calendar_analytics,
    google_storage_bucket.calendar_intelligence,
    google_cloud_tasks_queue.calendar_tasks
  ]
}

# ============================================================================
# CLOUD RUN API SERVICE
# ============================================================================

# Cloud Run service for calendar intelligence API
resource "google_cloud_run_v2_service" "calendar_api" {
  name     = local.api_service_name
  location = var.region
  project  = var.project_id
  
  deletion_protection = false
  
  labels = local.common_labels
  
  template {
    # Service account configuration  
    service_account = var.iam_config.create_service_accounts ? google_service_account.api_service_account[0].email : null
    
    # Scaling configuration
    scaling {
      min_instance_count = var.api_service_config.min_instance_count
      max_instance_count = var.api_service_config.max_instance_count
    }
    
    # Container configuration
    containers {
      name  = "calendar-api"
      image = var.api_service_config.container_image
      
      # Resource limits
      resources {
        limits = {
          cpu    = var.api_service_config.cpu_limit
          memory = var.api_service_config.memory_limit
        }
      }
      
      # Port configuration
      ports {
        name           = "http1"
        container_port = 8080
      }
      
      # Environment variables
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "GOOGLE_CLOUD_REGION" 
        value = var.region
      }
      
      env {
        name  = "TASK_QUEUE_NAME"
        value = local.task_queue_name
      }
      
      env {
        name  = "PORT"
        value = "8080"
      }
    }
    
    # VPC access configuration
    dynamic "vpc_access" {
      for_each = var.network_config.enable_direct_vpc ? [1] : []
      content {
        network_interfaces {
          network    = var.network_config.vpc_network
          subnetwork = var.network_config.vpc_subnetwork
        }
      }
    }
  }
  
  # Traffic configuration
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_service_account.api_service_account,
    google_cloud_tasks_queue.calendar_tasks
  ]
}

# Allow unauthenticated access to the API service
resource "google_cloud_run_service_iam_member" "api_public_access" {
  location = google_cloud_run_v2_service.calendar_api.location
  project  = google_cloud_run_v2_service.calendar_api.project
  service  = google_cloud_run_v2_service.calendar_api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================================
# CLOUD SCHEDULER
# ============================================================================

# Cloud Scheduler job for automated daily calendar analysis
resource "google_cloud_scheduler_job" "daily_analysis" {
  count = var.scheduler_config.enable_scheduler ? 1 : 0
  
  name        = "${var.resource_prefix}-daily-analysis-${local.suffix}"
  description = var.scheduler_config.description
  schedule    = var.scheduler_config.schedule_expression
  time_zone   = var.scheduler_config.time_zone
  region      = var.region
  project     = var.project_id
  
  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.calendar_api.uri}/trigger-analysis"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      calendar_ids = ["primary"]
      analysis_type = "daily_intelligence"
    }))
  }
  
  depends_on = [
    time_sleep.wait_for_apis,
    google_cloud_run_v2_service.calendar_api
  ]
}

# ============================================================================
# SECRET MANAGER (OPTIONAL)
# ============================================================================

# Secret for storing calendar API credentials
resource "google_secret_manager_secret" "calendar_credentials" {
  count = var.security_config.enable_secret_manager ? 1 : 0
  
  secret_id = "${var.resource_prefix}-calendar-credentials-${local.suffix}"
  project   = var.project_id
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM binding for secret access
resource "google_secret_manager_secret_iam_member" "worker_secret_access" {
  count = var.security_config.enable_secret_manager && var.iam_config.create_service_accounts ? 1 : 0
  
  project   = var.project_id
  secret_id = google_secret_manager_secret.calendar_credentials[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.worker_service_account[0].email}"
  
  depends_on = [
    google_secret_manager_secret.calendar_credentials,
    google_service_account.worker_service_account
  ]
}