# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  suffix                  = random_id.suffix.hex
  input_bucket_name      = "${var.project_id}-${var.input_bucket_name}-${local.suffix}"
  output_bucket_name     = "${var.project_id}-${var.output_bucket_name}-${local.suffix}"
  service_account_email  = "${var.service_account_name}-${local.suffix}@${var.project_id}.iam.gserviceaccount.com"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  service = each.key
  project = var.project_id
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service account for video generation functions
resource "google_service_account" "video_generation_sa" {
  account_id   = "${var.service_account_name}-${local.suffix}"
  display_name = var.service_account_display_name
  description  = "Service account for automated Veo 3 video generation"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "video_generation_sa_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.video_generation_sa.email}"
}

resource "google_project_iam_member" "video_generation_sa_storage" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.video_generation_sa.email}"
}

resource "google_project_iam_member" "video_generation_sa_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.video_generation_sa.email}"
}

# Input Storage bucket for creative briefs
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable versioning for content protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Uniform bucket-level access for simplified permissions
  uniform_bucket_level_access = true
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_delete_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for web uploads if needed
  cors {
    origin          = ["*"]
    method          = ["GET", "POST", "PUT", "DELETE"]
    response_header = ["Content-Type", "Content-Range", "Content-Disposition"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Output Storage bucket for generated videos
resource "google_storage_bucket" "output_bucket" {
  name          = local.output_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable versioning for content protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Uniform bucket-level access for simplified permissions
  uniform_bucket_level_access = true
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_delete_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Transition to cheaper storage classes for older content
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # CORS configuration for web access to generated videos
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type", "Content-Range", "Content-Disposition"]
    max_age_seconds = 86400
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Archive for video generation function source code
data "archive_file" "video_generation_source" {
  type        = "zip"
  output_path = "/tmp/video_generation_function.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/video_generation.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Storage bucket object for video generation function source
resource "google_storage_bucket_object" "video_generation_source" {
  name   = "video-generation-source-${local.suffix}.zip"
  bucket = google_storage_bucket.input_bucket.name
  source = data.archive_file.video_generation_source.output_path
  
  depends_on = [data.archive_file.video_generation_source]
}

# Video generation Cloud Function
resource "google_cloudfunctions2_function" "video_generation" {
  name        = "${var.resource_prefix}-video-generation-${local.suffix}"
  location    = var.region
  project     = var.project_id
  description = "Generate videos using Vertex AI Veo 3 model"
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "generate_video"
    
    source {
      storage_source {
        bucket = google_storage_bucket.input_bucket.name
        object = google_storage_bucket_object.video_generation_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.video_generation_memory}Mi"
    timeout_seconds       = var.video_generation_timeout
    service_account_email = google_service_account.video_generation_sa.email
    
    environment_variables = {
      GCP_PROJECT     = var.project_id
      FUNCTION_REGION = var.region
      OUTPUT_BUCKET   = google_storage_bucket.output_bucket.name
      VEO_MODEL_NAME  = var.veo_model_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.video_generation_source
  ]
}

# Archive for orchestrator function source code
data "archive_file" "orchestrator_source" {
  type        = "zip"
  output_path = "/tmp/orchestrator_function.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/orchestrator.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/orchestrator_requirements.txt")
    filename = "requirements.txt"
  }
}

# Storage bucket object for orchestrator function source
resource "google_storage_bucket_object" "orchestrator_source" {
  name   = "orchestrator-source-${local.suffix}.zip"
  bucket = google_storage_bucket.input_bucket.name
  source = data.archive_file.orchestrator_source.output_path
  
  depends_on = [data.archive_file.orchestrator_source]
}

# Orchestrator Cloud Function
resource "google_cloudfunctions2_function" "orchestrator" {
  name        = "${var.resource_prefix}-orchestrator-${local.suffix}"
  location    = var.region
  project     = var.project_id
  description = "Orchestrate batch video generation from creative briefs"
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "orchestrate_video_generation"
    
    source {
      storage_source {
        bucket = google_storage_bucket.input_bucket.name
        object = google_storage_bucket_object.orchestrator_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = "${var.orchestrator_memory}Mi"
    timeout_seconds       = var.orchestrator_timeout
    service_account_email = google_service_account.video_generation_sa.email
    
    environment_variables = {
      INPUT_BUCKET        = google_storage_bucket.input_bucket.name
      OUTPUT_BUCKET       = google_storage_bucket.output_bucket.name
      VIDEO_FUNCTION_URL  = google_cloudfunctions2_function.video_generation.service_config[0].uri
      PROJECT_ID          = var.project_id
      REGION              = var.region
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.orchestrator_source,
    google_cloudfunctions2_function.video_generation
  ]
}

# IAM policy to allow public access to functions (if needed for external triggers)
resource "google_cloudfunctions2_function_iam_member" "video_generation_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.video_generation.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "orchestrator_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.orchestrator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Scheduler job for automated video generation
resource "google_cloud_scheduler_job" "automated_video_generation" {
  name             = "${var.resource_prefix}-automated-generation-${local.suffix}"
  description      = "Automated video generation using Veo 3"
  schedule         = var.automated_schedule
  time_zone        = var.schedule_timezone
  region           = var.region
  project          = var.project_id
  attempt_deadline = "600s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.orchestrator.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger    = "scheduled"
      batch_size = var.automated_batch_size
    }))
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.orchestrator
  ]
}

# Cloud Scheduler job for on-demand video generation
resource "google_cloud_scheduler_job" "on_demand_video_generation" {
  name             = "${var.resource_prefix}-on-demand-generation-${local.suffix}"
  description      = "On-demand video generation using Veo 3 (manual trigger)"
  schedule         = "0 0 31 2 *"  # Never runs automatically (Feb 31st doesn't exist)
  time_zone        = var.schedule_timezone
  region           = var.region
  project          = var.project_id
  attempt_deadline = "600s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.orchestrator.service_config[0].uri
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger    = "manual"
      batch_size = var.manual_batch_size
    }))
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.orchestrator
  ]
}

# Monitoring and alerting resources (conditional based on variable)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Video Generation Function Failures - ${local.suffix}"
  project      = var.project_id
  
  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.label.status!=\"ok\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.function_error_threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content = "Video generation functions are experiencing high error rates. Check function logs and Vertex AI quota."
  }
  
  depends_on = [google_project_service.required_apis]
}

# Sample creative briefs for testing
resource "google_storage_bucket_object" "sample_product_brief" {
  name    = "briefs/sample_product_brief.json"
  bucket  = google_storage_bucket.input_bucket.name
  content_type = "application/json"
  
  content = jsonencode({
    id          = "brief_001"
    title       = "Product Launch Video"
    video_prompt = "A sleek modern smartphone floating in a minimalist white environment with soft lighting, slowly rotating to show all angles, with subtle particle effects and elegant typography appearing to highlight key features"
    resolution  = var.default_video_resolution
    duration    = "${var.default_video_duration}s"
    style       = "modern, clean, professional"
    target_audience = "tech enthusiasts"
    brand_guidelines = {
      colors = ["#1a73e8", "#ffffff", "#f8f9fa"]
      tone   = "innovative, premium"
    }
    created_at = "2025-07-12T10:00:00Z"
    created_by = "marketing_team"
  })
  
  depends_on = [google_storage_bucket.input_bucket]
}

resource "google_storage_bucket_object" "sample_lifestyle_brief" {
  name    = "briefs/sample_lifestyle_brief.json"
  bucket  = google_storage_bucket.input_bucket.name
  content_type = "application/json"
  
  content = jsonencode({
    id          = "brief_002"
    title       = "Lifestyle Brand Video"
    video_prompt = "A serene morning scene with golden sunlight streaming through a window, a steaming coffee cup on a wooden table, plants in the background, creating a warm and inviting atmosphere for wellness and mindfulness"
    resolution  = var.default_video_resolution
    duration    = "${var.default_video_duration}s"
    style       = "warm, natural, lifestyle"
    target_audience = "wellness enthusiasts"
    brand_guidelines = {
      colors = ["#8bc34a", "#ff9800", "#795548"]
      tone   = "calming, authentic"
    }
    created_at = "2025-07-12T10:15:00Z"
    created_by = "content_team"
  })
  
  depends_on = [google_storage_bucket.input_bucket]
}