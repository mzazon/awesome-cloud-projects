# Social Media Video Creation with Veo 3 and Vertex AI
# This Terraform configuration deploys a serverless video generation pipeline
# using Google Cloud Functions, Storage, and Vertex AI services

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource configuration
locals {
  project_id      = var.project_id
  region          = var.region
  bucket_name     = "${var.bucket_prefix}-${random_id.suffix.hex}"
  function_prefix = var.function_prefix
  
  # Function source configuration
  function_source_dir = var.function_source_dir
  
  # Environment variables for all functions
  common_env_vars = {
    BUCKET_NAME  = google_storage_bucket.video_storage.name
    GCP_PROJECT  = local.project_id
    REGION       = local.region
  }

  # Required APIs for the video generation pipeline
  required_apis = [
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com", 
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = local.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service account for Cloud Functions with appropriate permissions
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_prefix}-sa-${random_id.suffix.hex}"
  display_name = "Video Generation Functions Service Account"
  description  = "Service account for video generation, validation, and monitoring functions"
  project      = local.project_id
}

# IAM roles for the service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",           # Full access to Cloud Storage objects
    "roles/aiplatform.user",              # Access to Vertex AI services
    "roles/logging.logWriter",            # Write access to Cloud Logging
    "roles/monitoring.metricWriter",      # Write access to Cloud Monitoring
    "roles/cloudfunctions.invoker"        # Ability to invoke Cloud Functions
  ])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Cloud Storage bucket for video files and metadata
resource "google_storage_bucket" "video_storage" {
  name                        = local.bucket_name
  location                    = local.region
  project                     = local.project_id
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy              = var.force_destroy_bucket

  # Enable versioning for video management and history
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30 # Delete objects older than 30 days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 7 # Move to nearline storage after 7 days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # Enable soft delete for accidental deletion recovery
  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }

  # Labels for organization and cost tracking
  labels = merge(var.labels, {
    component = "video-storage"
    purpose   = "ai-generated-content"
  })

  depends_on = [google_project_service.required_apis]
}

# Create organized folder structure in bucket using storage objects
resource "google_storage_bucket_object" "folder_structure" {
  for_each = toset([
    "raw-videos/.keep",
    "processed-videos/.keep", 
    "metadata/.keep",
    "function-source/.keep"
  ])

  name    = each.value
  content = ""
  bucket  = google_storage_bucket.video_storage.name

  depends_on = [google_storage_bucket.video_storage]
}

# Archive and upload function source code for video generator
data "archive_file" "video_generator_source" {
  type        = "zip"
  output_path = "${path.module}/video-generator-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/video-generator/main.py", {
      project_id  = local.project_id
      bucket_name = google_storage_bucket.video_storage.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/video-generator/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "video_generator_source" {
  name   = "function-source/video-generator-${data.archive_file.video_generator_source.output_md5}.zip"
  bucket = google_storage_bucket.video_storage.name
  source = data.archive_file.video_generator_source.output_path

  depends_on = [
    google_storage_bucket.video_storage,
    data.archive_file.video_generator_source
  ]
}

# Cloud Function for video generation using Veo 3
resource "google_cloudfunctions2_function" "video_generator" {
  name        = "${local.function_prefix}-generator-${random_id.suffix.hex}"
  location    = local.region
  project     = local.project_id
  description = "Generate videos using Google Veo 3 model"

  build_config {
    runtime     = "python311"
    entry_point = "generate_video"
    
    environment_variables = {
      BUILD_CONFIG_PROJECT = local.project_id
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.video_storage.name
        object = google_storage_bucket_object.video_generator_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.max_instances
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 540
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables        = local.common_env_vars
    service_account_email       = google_service_account.function_sa.email
    ingress_settings           = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }

  # Labels for organization
  labels = merge(var.labels, {
    component = "video-generator"
    function  = "ai-video-creation"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.video_generator_source,
    google_project_iam_member.function_permissions
  ]
}

# Archive and upload function source code for quality validator
data "archive_file" "quality_validator_source" {
  type        = "zip"
  output_path = "${path.module}/quality-validator-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/quality-validator/main.py", {
      project_id  = local.project_id
      bucket_name = google_storage_bucket.video_storage.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/quality-validator/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "quality_validator_source" {
  name   = "function-source/quality-validator-${data.archive_file.quality_validator_source.output_md5}.zip"
  bucket = google_storage_bucket.video_storage.name
  source = data.archive_file.quality_validator_source.output_path

  depends_on = [
    google_storage_bucket.video_storage,
    data.archive_file.quality_validator_source
  ]
}

# Cloud Function for content quality validation using Gemini
resource "google_cloudfunctions2_function" "quality_validator" {
  name        = "${local.function_prefix}-validator-${random_id.suffix.hex}"
  location    = local.region
  project     = local.project_id
  description = "Validate video content quality using Gemini AI"

  build_config {
    runtime     = "python311"
    entry_point = "validate_content"
    
    environment_variables = {
      BUILD_CONFIG_PROJECT = local.project_id
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.video_storage.name
        object = google_storage_bucket_object.quality_validator_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.max_instances
    min_instance_count               = 0
    available_memory                 = "1Gi"
    timeout_seconds                  = 300
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables        = local.common_env_vars
    service_account_email       = google_service_account.function_sa.email
    ingress_settings           = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }

  # Labels for organization
  labels = merge(var.labels, {
    component = "quality-validator"
    function  = "ai-content-analysis"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.quality_validator_source,
    google_project_iam_member.function_permissions
  ]
}

# Archive and upload function source code for operation monitor
data "archive_file" "operation_monitor_source" {
  type        = "zip"
  output_path = "${path.module}/operation-monitor-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/operation-monitor/main.py", {
      project_id  = local.project_id
      bucket_name = google_storage_bucket.video_storage.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/operation-monitor/requirements.txt")
    filename = "requirements.txt"
  }
}

resource "google_storage_bucket_object" "operation_monitor_source" {
  name   = "function-source/operation-monitor-${data.archive_file.operation_monitor_source.output_md5}.zip"
  bucket = google_storage_bucket.video_storage.name
  source = data.archive_file.operation_monitor_source.output_path

  depends_on = [
    google_storage_bucket.video_storage,
    data.archive_file.operation_monitor_source
  ]
}

# Cloud Function for monitoring video generation operations
resource "google_cloudfunctions2_function" "operation_monitor" {
  name        = "${local.function_prefix}-monitor-${random_id.suffix.hex}"
  location    = local.region
  project     = local.project_id
  description = "Monitor video generation operation status and completion"

  build_config {
    runtime     = "python311"
    entry_point = "monitor_operations"
    
    environment_variables = {
      BUILD_CONFIG_PROJECT = local.project_id
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.video_storage.name
        object = google_storage_bucket_object.operation_monitor_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.max_instances
    min_instance_count               = 0
    available_memory                 = "256Mi"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 10
    available_cpu                    = "1"
    
    environment_variables        = local.common_env_vars
    service_account_email       = google_service_account.function_sa.email
    ingress_settings           = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }

  # Labels for organization
  labels = merge(var.labels, {
    component = "operation-monitor"
    function  = "status-tracking"
  })

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.operation_monitor_source,
    google_project_iam_member.function_permissions
  ]
}

# IAM binding to allow unauthenticated invocation of functions (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_invoker" {
  for_each = var.allow_unauthenticated_invocation ? toset([
    google_cloudfunctions2_function.video_generator.name,
    google_cloudfunctions2_function.quality_validator.name,
    google_cloudfunctions2_function.operation_monitor.name
  ]) : toset([])

  project        = local.project_id
  location       = local.region
  cloud_function = each.value
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [
    google_cloudfunctions2_function.video_generator,
    google_cloudfunctions2_function.quality_validator,
    google_cloudfunctions2_function.operation_monitor
  ]
}

# Cloud Run service IAM for unauthenticated access (if enabled)
resource "google_cloud_run_service_iam_member" "public_run_invoker" {
  for_each = var.allow_unauthenticated_invocation ? toset([
    google_cloudfunctions2_function.video_generator.name,
    google_cloudfunctions2_function.quality_validator.name,
    google_cloudfunctions2_function.operation_monitor.name
  ]) : toset([])

  project  = local.project_id
  location = local.region
  service  = each.value
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [
    google_cloudfunctions2_function.video_generator,
    google_cloudfunctions2_function.quality_validator,
    google_cloudfunctions2_function.operation_monitor
  ]
}