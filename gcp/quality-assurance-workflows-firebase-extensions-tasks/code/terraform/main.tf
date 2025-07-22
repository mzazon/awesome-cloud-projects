# Quality Assurance Workflows with Firebase Extensions and Cloud Tasks
# This Terraform configuration deploys a comprehensive QA automation pipeline
# using Firebase Extensions, Cloud Tasks, Cloud Storage, and Vertex AI

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  project_id           = var.project_id
  region              = var.region
  zone                = var.zone
  random_suffix       = random_id.suffix.hex
  qa_bucket_name      = "qa-artifacts-${local.random_suffix}"
  task_queue_name     = "qa-orchestration-${local.random_suffix}"
  firestore_collection = "qa-workflows"
  
  # Common labels for all resources
  common_labels = {
    project     = "qa-workflows"
    environment = var.environment
    managed-by  = "terraform"
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "firebase.googleapis.com",
    "cloudtasks.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "appengine.googleapis.com"
  ])
  
  project = local.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create App Engine application (required for Cloud Tasks)
resource "google_app_engine_application" "app" {
  project     = local.project_id
  location_id = var.app_engine_location
  
  depends_on = [google_project_service.required_apis]
}

# Initialize Firebase project
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = local.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create Firestore database
resource "google_firestore_database" "database" {
  provider = google-beta
  project  = local.project_id
  name     = "(default)"
  
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  depends_on = [google_firebase_project.default]
}

# Cloud Storage bucket for QA artifacts
resource "google_storage_bucket" "qa_artifacts" {
  name     = local.qa_bucket_name
  location = local.region
  project  = local.project_id
  
  # Enable versioning for artifact history
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
    condition {
      age = 30
    }
  }
  
  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition {
      age = 90
    }
  }
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Tasks queues for test orchestration
resource "google_cloud_tasks_queue" "qa_orchestration" {
  name     = local.task_queue_name
  location = local.region
  project  = local.project_id
  
  rate_limits {
    max_concurrent_dispatches = 10
  }
  
  retry_config {
    max_attempts       = 5
    max_retry_duration = "3600s"
    min_backoff        = "1s"
    max_backoff        = "300s"
    max_doublings      = 10
  }
  
  depends_on = [google_app_engine_application.app]
}

# Priority queue for critical tests
resource "google_cloud_tasks_queue" "qa_priority" {
  name     = "${local.task_queue_name}-priority"
  location = local.region
  project  = local.project_id
  
  rate_limits {
    max_concurrent_dispatches = 5
  }
  
  retry_config {
    max_attempts       = 3
    max_retry_duration = "1800s"
    min_backoff        = "1s"
    max_backoff        = "300s"
  }
  
  depends_on = [google_app_engine_application.app]
}

# Analysis queue for AI processing
resource "google_cloud_tasks_queue" "qa_analysis" {
  name     = "${local.task_queue_name}-analysis"
  location = local.region
  project  = local.project_id
  
  rate_limits {
    max_concurrent_dispatches = 3
  }
  
  retry_config {
    max_attempts       = 3
    max_retry_duration = "7200s"
    min_backoff        = "5s"
    max_backoff        = "600s"
  }
  
  depends_on = [google_app_engine_application.app]
}

# Service account for Cloud Functions
resource "google_service_account" "qa_functions" {
  account_id   = "qa-functions-${local.random_suffix}"
  display_name = "QA Workflow Functions Service Account"
  description  = "Service account for QA workflow Cloud Functions"
  project      = local.project_id
}

# IAM bindings for the Cloud Functions service account
resource "google_project_iam_member" "qa_functions_permissions" {
  for_each = toset([
    "roles/cloudtasks.admin",
    "roles/storage.admin",
    "roles/datastore.user",
    "roles/aiplatform.user",
    "roles/cloudsql.client",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.qa_functions.email}"
}

# Create a ZIP file for the Cloud Function source code
data "archive_file" "qa_phase_executor_source" {
  type        = "zip"
  output_path = "${path.module}/qa-phase-executor.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      qa_bucket_name = local.qa_bucket_name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source
resource "google_storage_bucket" "function_source" {
  name     = "qa-function-source-${local.random_suffix}"
  location = local.region
  project  = local.project_id
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "qa_phase_executor_source" {
  name   = "qa-phase-executor-${data.archive_file.qa_phase_executor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.qa_phase_executor_source.output_path
}

# Cloud Function for QA phase execution
resource "google_cloudfunctions2_function" "qa_phase_executor" {
  name     = "qa-phase-executor-${local.random_suffix}"
  location = local.region
  project  = local.project_id
  
  build_config {
    runtime     = "python311"
    entry_point = "qa_phase_executor"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.qa_phase_executor_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 540
    service_account_email = google_service_account.qa_functions.email
    
    environment_variables = {
      QA_BUCKET_NAME     = local.qa_bucket_name
      GOOGLE_CLOUD_PROJECT = local.project_id
      FIRESTORE_COLLECTION = local.firestore_collection
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.qa_phase_executor_source
  ]
}

# Make the Cloud Function publicly accessible
resource "google_cloudfunctions2_function_iam_member" "qa_phase_executor_invoker" {
  project        = local.project_id
  location       = local.region
  cloud_function = google_cloudfunctions2_function.qa_phase_executor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Service account for QA Dashboard
resource "google_service_account" "qa_dashboard" {
  account_id   = "qa-dashboard-${local.random_suffix}"
  display_name = "QA Dashboard Service Account"
  description  = "Service account for QA Dashboard Cloud Run service"
  project      = local.project_id
}

# IAM permissions for QA Dashboard
resource "google_project_iam_member" "qa_dashboard_permissions" {
  for_each = toset([
    "roles/datastore.user",
    "roles/storage.objectViewer",
    "roles/aiplatform.user"
  ])
  
  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.qa_dashboard.email}"
}

# Cloud Run service for QA Dashboard
resource "google_cloud_run_v2_service" "qa_dashboard" {
  name     = "qa-dashboard-${local.random_suffix}"
  location = local.region
  project  = local.project_id
  
  template {
    service_account = google_service_account.qa_dashboard.email
    
    containers {
      image = var.dashboard_image
      
      ports {
        container_port = 8080
      }
      
      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = local.project_id
      }
      
      env {
        name  = "QA_BUCKET_NAME"
        value = local.qa_bucket_name
      }
      
      env {
        name  = "FIRESTORE_COLLECTION"
        value = local.firestore_collection
      }
      
      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
    
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Make the Cloud Run service publicly accessible
resource "google_cloud_run_service_iam_member" "qa_dashboard_invoker" {
  project  = local.project_id
  location = local.region
  service  = google_cloud_run_v2_service.qa_dashboard.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Vertex AI Dataset for quality analysis
resource "google_vertex_ai_dataset" "qa_metrics" {
  display_name        = "QA Metrics Dataset"
  metadata_schema_uri = "gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml"
  region              = local.region
  project             = local.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery dataset for ML training data
resource "google_bigquery_dataset" "qa_analysis" {
  dataset_id    = "qa_analysis_${replace(local.random_suffix, "-", "_")}"
  friendly_name = "QA Analysis Dataset"
  description   = "Dataset for QA workflow analysis and ML training"
  location      = "US"
  project       = local.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for workflow metrics
resource "google_bigquery_table" "workflow_metrics" {
  dataset_id = google_bigquery_dataset.qa_analysis.dataset_id
  table_id   = "workflow_metrics"
  project    = local.project_id
  
  schema = jsonencode([
    {
      name = "workflow_id"
      type = "STRING"
      mode = "REQUIRED"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
    },
    {
      name = "code_coverage"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "tests_passed"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "tests_failed"
      type = "INTEGER"
      mode = "NULLABLE"
    },
    {
      name = "avg_response_time"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "quality_score"
      type = "FLOAT"
      mode = "NULLABLE"
    },
    {
      name = "risk_level"
      type = "STRING"
      mode = "NULLABLE"
    }
  ])
  
  labels = local.common_labels
}

# Cloud Monitoring alert policy for failed QA workflows
resource "google_monitoring_alert_policy" "qa_workflow_failures" {
  display_name = "QA Workflow Failures"
  project      = local.project_id
  
  conditions {
    display_name = "QA workflow failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.qa_phase_executor.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Firestore security rules
resource "google_firebaserules_ruleset" "firestore_rules" {
  provider = google-beta
  project  = local.project_id
  
  source {
    files {
      name = "firestore.rules"
      content = templatefile("${path.module}/firestore.rules", {
        firestore_collection = local.firestore_collection
      })
    }
  }
  
  depends_on = [google_firestore_database.database]
}

# Release the Firestore rules
resource "google_firebaserules_release" "firestore" {
  provider     = google-beta
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore_rules.name
  project      = local.project_id
  
  depends_on = [google_firestore_database.database]
}