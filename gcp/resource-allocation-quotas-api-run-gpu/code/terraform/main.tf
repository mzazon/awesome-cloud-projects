# Intelligent Resource Allocation with Cloud Quotas API and Cloud Run GPU
# This Terraform configuration deploys a complete intelligent resource allocation system
# that automatically monitors Cloud Run GPU workloads and adjusts quotas dynamically

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Standardized resource names
  function_name    = "quota-manager-${local.resource_suffix}"
  service_name     = "ai-inference-${local.resource_suffix}"
  bucket_name      = "${var.project_id}-quota-policies-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudquotas.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "firestore.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for quota policies and configuration
resource "google_storage_bucket" "quota_policies" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id

  # Enable versioning for policy change tracking
  versioning {
    enabled = true
  }

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload quota management policy configuration
resource "google_storage_bucket_object" "quota_policy" {
  name   = "quota-policy.json"
  bucket = google_storage_bucket.quota_policies.name
  
  content = jsonencode({
    allocation_thresholds = {
      gpu_utilization_trigger    = var.gpu_utilization_threshold
      cpu_utilization_trigger    = 0.75
      memory_utilization_trigger = 0.85
    }
    gpu_families = {
      "nvidia-l4" = {
        max_quota      = var.max_gpu_quota
        min_quota      = var.min_gpu_quota
        increment_size = 2
      }
      "nvidia-t4" = {
        max_quota      = var.max_gpu_quota - 2
        min_quota      = var.min_gpu_quota
        increment_size = 1
      }
    }
    regions = [var.region, "us-west1", "us-east1"]
    cost_optimization = {
      enable_preemptible  = var.enable_cost_optimization
      max_cost_per_hour   = var.max_cost_per_hour
    }
  })

  depends_on = [google_storage_bucket.quota_policies]
}

# Initialize Firestore database for usage history
resource "google_firestore_database" "quota_history" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.required_apis]
}

# IAM Service Account for Cloud Function
resource "google_service_account" "quota_manager" {
  account_id   = "quota-manager-${local.resource_suffix}"
  display_name = "Quota Manager Service Account"
  description  = "Service account for intelligent quota management functions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM permissions to the service account
resource "google_project_iam_member" "quota_manager_permissions" {
  for_each = toset([
    "roles/monitoring.viewer",
    "roles/cloudquotas.admin", 
    "roles/datastore.user",
    "roles/storage.objectViewer",
    "roles/run.viewer",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.quota_manager.email}"
}

# Create source archive for Cloud Function
data "archive_file" "quota_function_source" {
  type        = "zip"
  output_path = "${path.module}/quota-manager-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id    = var.project_id
      bucket_name   = local.bucket_name
      region        = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "quota_function_source" {
  name   = "quota-manager-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.quota_policies.name
  source = data.archive_file.quota_function_source.output_path

  depends_on = [data.archive_file.quota_function_source]
}

# Deploy Cloud Function for quota intelligence
resource "google_cloudfunctions2_function" "quota_manager" {
  name     = local.function_name
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python311"
    entry_point = "analyze_gpu_utilization"
    
    source {
      storage_source {
        bucket = google_storage_bucket.quota_policies.name
        object = google_storage_bucket_object.quota_function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.quota_manager.email

    environment_variables = {
      PROJECT_ID    = var.project_id
      REGION        = var.region
      BUCKET_NAME   = local.bucket_name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.quota_function_source,
    google_project_iam_member.quota_manager_permissions
  ]
}

# Create Cloud Function IAM binding for public access
resource "google_cloudfunctions2_function_iam_member" "quota_manager_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.quota_manager.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# IAM Service Account for Cloud Run service
resource "google_service_account" "ai_inference" {
  account_id   = "ai-inference-${local.resource_suffix}"
  display_name = "AI Inference Service Account"
  description  = "Service account for AI inference Cloud Run service"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM permissions for Cloud Run service
resource "google_project_iam_member" "ai_inference_permissions" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ai_inference.email}"
}

# Create Artifact Registry repository for container images
resource "google_artifact_registry_repository" "ai_inference" {
  location      = var.region
  project       = var.project_id
  repository_id = "ai-inference-${local.resource_suffix}"
  description   = "Repository for AI inference container images"
  format        = "DOCKER"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create source archive for AI inference service
data "archive_file" "ai_inference_source" {
  type        = "zip"
  output_path = "${path.module}/ai-inference-service.zip"
  
  source {
    content = file("${path.module}/service_code/Dockerfile")
    filename = "Dockerfile"
  }
  
  source {
    content = file("${path.module}/service_code/app.py")
    filename = "app.py"
  }
  
  source {
    content = file("${path.module}/service_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload service source to Cloud Storage
resource "google_storage_bucket_object" "ai_inference_source" {
  name   = "ai-inference-service-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.quota_policies.name
  source = data.archive_file.ai_inference_source.output_path

  depends_on = [data.archive_file.ai_inference_source]
}

# Build container image using Cloud Build
resource "google_cloudbuild_trigger" "ai_inference_build" {
  name        = "ai-inference-build-${local.resource_suffix}"
  description = "Build trigger for AI inference service"
  project     = var.project_id
  location    = var.region

  source_to_build {
    uri       = "gs://${google_storage_bucket.quota_policies.name}/${google_storage_bucket_object.ai_inference_source.name}"
    ref       = "main"
    repo_type = "UNKNOWN"
  }

  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_inference.repository_id}/${local.service_name}:latest",
        "."
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "push",
        "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_inference.repository_id}/${local.service_name}:latest"
      ]
    }

    images = [
      "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_inference.repository_id}/${local.service_name}:latest"
    ]
  }

  depends_on = [
    google_artifact_registry_repository.ai_inference,
    google_storage_bucket_object.ai_inference_source
  ]
}

# Deploy Cloud Run service with GPU
resource "google_cloud_run_v2_service" "ai_inference" {
  name     = local.service_name
  location = var.region
  project  = var.project_id

  template {
    labels = local.common_labels
    
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    service_account = google_service_account.ai_inference.email

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.ai_inference.repository_id}/${local.service_name}:latest"

      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        
        # GPU configuration
        cpu_idle = true
        startup_cpu_boost = true
      }

      ports {
        container_port = 8080
      }

      env {
        name  = "GOOGLE_CLOUD_PROJECT"
        value = var.project_id
      }
      
      env {
        name  = "GOOGLE_CLOUD_REGION"
        value = var.region
      }
    }

    # GPU allocation - Note: GPU support in Cloud Run is limited
    # This configuration represents the intended GPU allocation
    annotations = {
      "run.googleapis.com/gpu-type"  = var.cloud_run_gpu_type
      "run.googleapis.com/gpu-count" = tostring(var.cloud_run_gpu_count)
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_cloudbuild_trigger.ai_inference_build,
    google_project_iam_member.ai_inference_permissions
  ]
}

# Allow unauthenticated access to Cloud Run service
resource "google_cloud_run_service_iam_member" "ai_inference_public" {
  location = google_cloud_run_v2_service.ai_inference.location
  project  = google_cloud_run_v2_service.ai_inference.project
  service  = google_cloud_run_v2_service.ai_inference.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create Cloud Scheduler jobs for automated quota analysis
resource "google_cloud_scheduler_job" "quota_analysis" {
  name        = "quota-analysis-${local.resource_suffix}"
  description = "Automated GPU quota analysis and adjustment"
  project     = var.project_id
  region      = var.region
  schedule    = var.quota_analysis_schedule
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.quota_manager.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      project_id = var.project_id
      region     = var.region
    }))
  }

  depends_on = [
    google_cloudfunctions2_function.quota_manager,
    google_cloudfunctions2_function_iam_member.quota_manager_invoker
  ]
}

# Create peak hour analysis scheduler job
resource "google_cloud_scheduler_job" "peak_analysis" {
  name        = "peak-analysis-${local.resource_suffix}"
  description = "Peak hour intensive quota analysis"
  project     = var.project_id
  region      = var.region
  schedule    = var.peak_analysis_schedule
  time_zone   = "UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.quota_manager.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      project_id     = var.project_id
      region         = var.region
      analysis_type  = "peak"
    }))
  }

  depends_on = [
    google_cloudfunctions2_function.quota_manager,
    google_cloudfunctions2_function_iam_member.quota_manager_invoker
  ]
}

# Create monitoring alert policy for high GPU utilization
resource "google_monitoring_alert_policy" "high_gpu_utilization" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "High GPU Utilization Alert - ${local.resource_suffix}"
  project      = var.project_id
  
  combiner = "OR"
  
  conditions {
    display_name = "GPU utilization above 85%"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/gpu/utilization\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 0.85
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "GPU utilization has exceeded 85% for the AI inference service. Consider quota adjustment."
    mime_type = "text/markdown"
  }

  enabled = true
}

# Create monitoring dashboard for quota intelligence
resource "google_monitoring_dashboard" "quota_dashboard" {
  count        = var.enable_monitoring ? 1 : 0
  project      = var.project_id
  dashboard_json = jsonencode({
    displayName = "GPU Quota Intelligence Dashboard - ${local.resource_suffix}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "GPU Utilization Trends"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/gpu/utilization\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run GPU Instances"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/instance_count\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_MAX"
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
            }
          }
        }
      ]
    }
  })
}