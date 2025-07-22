# Main Terraform Configuration for Multi-Modal AI Content Generation Platform
# This file creates the complete infrastructure for Lyria music generation, Veo video generation,
# and synchronized content creation using Google Cloud's advanced AI services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Common name suffix using random ID
  name_suffix = random_id.suffix.hex
  
  # Resource names with suffix
  bucket_name                = "${var.content_bucket_name}-${local.name_suffix}"
  service_account_name      = "${var.service_account_name}-${local.name_suffix}"
  
  # Function names
  music_function_name       = "music-generation-${local.name_suffix}"
  video_function_name       = "video-generation-${local.name_suffix}"
  quality_function_name     = "quality-assessment-${local.name_suffix}"
  
  # Cloud Run service name
  orchestrator_service_name = "content-orchestrator-${local.name_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    deployment-id = local.name_suffix
    created-by    = "terraform"
  })
}

# ========================================
# API ENABLEMENT
# ========================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.apis_to_enable) : toset([])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# ========================================
# STORAGE INFRASTRUCTURE
# ========================================

# Primary content storage bucket
resource "google_storage_bucket" "content_bucket" {
  name                        = local.bucket_name
  location                    = var.content_bucket_location
  storage_class              = var.content_bucket_storage_class
  force_destroy              = !var.deletion_protection
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  labels = local.common_labels
  
  # Enable versioning for content protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Configure lifecycle management
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
  
  # Enable CORS for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create structured folders in the bucket
resource "google_storage_bucket_object" "content_folders" {
  for_each = toset([
    "prompts/.keep",
    "music/.keep",
    "video/.keep", 
    "speech/.keep",
    "compositions/.keep",
    "quality-reports/.keep"
  ])
  
  name   = each.value
  bucket = google_storage_bucket.content_bucket.name
  source = "/dev/null"
  
  depends_on = [google_storage_bucket.content_bucket]
}

# ========================================
# IAM CONFIGURATION
# ========================================

# Service account for AI content generation services
resource "google_service_account" "content_ai_service_account" {
  account_id   = local.service_account_name
  display_name = "Content AI Generation Service Account"
  description  = "Service account for multi-modal content generation with Lyria and Vertex AI"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account
resource "google_project_iam_member" "content_ai_roles" {
  for_each = toset([
    "roles/aiplatform.user",           # Access to Vertex AI models including Lyria and Veo
    "roles/storage.objectAdmin",       # Full access to Cloud Storage objects
    "roles/cloudfunctions.invoker",    # Invoke Cloud Functions
    "roles/run.invoker",              # Invoke Cloud Run services
    "roles/monitoring.metricWriter",   # Write custom metrics
    "roles/logging.logWriter",        # Write logs
    "roles/speech.client",            # Access to Speech-to-Text and Text-to-Speech
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.content_ai_service_account.email}"
  
  depends_on = [google_service_account.content_ai_service_account]
}

# Service account key for authentication
resource "google_service_account_key" "content_ai_key" {
  service_account_id = google_service_account.content_ai_service_account.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# ========================================
# CLOUD FUNCTIONS DEPLOYMENT
# ========================================

# Create Cloud Build trigger for function deployment (if needed)
resource "google_cloudbuild_trigger" "function_build" {
  count       = var.enable_apis ? 1 : 0
  project     = var.project_id
  name        = "content-generation-functions-${local.name_suffix}"
  description = "Build trigger for content generation functions"
  
  # Manual trigger for now - can be configured for Git integration
  source_to_build {
    uri       = "https://github.com/example/content-generation"
    ref       = "refs/heads/main"
    repo_type = "GITHUB"
  }
  
  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = "https://github.com/example/content-generation"
    revision  = "refs/heads/main"
    repo_type = "GITHUB"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Music generation function using Lyria 2
resource "google_cloudfunctions2_function" "music_generation" {
  name        = local.music_function_name
  location    = var.region
  description = "Lyria 2 music generation function for multi-modal content creation"
  
  build_config {
    runtime     = "python312"
    entry_point = "generate_music"
    
    source {
      storage_source {
        bucket = google_storage_bucket.content_bucket.name
        object = "functions/music-generation.zip"
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = var.cloud_function_memory
    timeout_seconds                 = var.cloud_function_timeout
    max_instance_request_concurrency = 1
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      REGION       = var.region
      BUCKET_NAME  = google_storage_bucket.content_bucket.name
    }
    
    service_account_email = google_service_account.content_ai_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.content_ai_service_account,
    google_storage_bucket.content_bucket
  ]
}

# Video generation function using Veo 3
resource "google_cloudfunctions2_function" "video_generation" {
  name        = local.video_function_name
  location    = var.region
  description = "Veo 3 video generation function for multi-modal content creation"
  
  build_config {
    runtime     = "python312"
    entry_point = "generate_video"
    
    source {
      storage_source {
        bucket = google_storage_bucket.content_bucket.name
        object = "functions/video-generation.zip"
      }
    }
  }
  
  service_config {
    max_instance_count               = 50
    min_instance_count               = 0
    available_memory                 = "2Gi"
    timeout_seconds                 = 600
    max_instance_request_concurrency = 1
    available_cpu                   = "2"
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      REGION       = var.region
      BUCKET_NAME  = google_storage_bucket.content_bucket.name
    }
    
    service_account_email = google_service_account.content_ai_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.content_ai_service_account,
    google_storage_bucket.content_bucket
  ]
}

# Quality assessment function
resource "google_cloudfunctions2_function" "quality_assessment" {
  name        = local.quality_function_name
  location    = var.region
  description = "Content quality assessment function for multi-modal AI output"
  
  build_config {
    runtime     = "python312"
    entry_point = "assess_content_quality"
    
    source {
      storage_source {
        bucket = google_storage_bucket.content_bucket.name
        object = "functions/quality-assessment.zip"
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = var.cloud_function_memory
    timeout_seconds                 = var.cloud_function_timeout
    max_instance_request_concurrency = 1
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      BUCKET_NAME  = google_storage_bucket.content_bucket.name
    }
    
    service_account_email = google_service_account.content_ai_service_account.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.content_ai_service_account,
    google_storage_bucket.content_bucket
  ]
}

# ========================================
# CLOUD RUN ORCHESTRATION SERVICE
# ========================================

# Cloud Run service for content orchestration
resource "google_cloud_run_v2_service" "content_orchestrator" {
  name     = local.orchestrator_service_name
  location = var.region
  project  = var.project_id
  
  template {
    labels = local.common_labels
    
    scaling {
      max_instance_count = var.cloud_run_max_instances
      min_instance_count = var.cloud_run_min_instances
    }
    
    containers {
      image = "gcr.io/${var.project_id}/content-orchestrator:latest"
      
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle = true
        startup_cpu_boost = true
      }
      
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
        value = google_storage_bucket.content_bucket.name
      }
      
      env {
        name  = "MUSIC_FUNCTION_URL"
        value = google_cloudfunctions2_function.music_generation.service_config[0].uri
      }
      
      env {
        name  = "VIDEO_FUNCTION_URL"
        value = google_cloudfunctions2_function.video_generation.service_config[0].uri
      }
      
      env {
        name  = "QUALITY_FUNCTION_URL"
        value = google_cloudfunctions2_function.quality_assessment.service_config[0].uri
      }
      
      ports {
        container_port = 8080
        name          = "http1"
      }
      
      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds      = 240
        period_seconds       = 240
        failure_threshold    = 1
        tcp_socket {
          port = 8080
        }
      }
      
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
    
    service_account = google_service_account.content_ai_service_account.email
    
    timeout = "900s"
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.content_ai_service_account,
    google_cloudfunctions2_function.music_generation,
    google_cloudfunctions2_function.video_generation,
    google_cloudfunctions2_function.quality_assessment
  ]
}

# Cloud Run IAM policy for public access (if needed)
resource "google_cloud_run_service_iam_member" "orchestrator_public_access" {
  count    = var.environment == "dev" ? 1 : 0
  service  = google_cloud_run_v2_service.content_orchestrator.name
  location = google_cloud_run_v2_service.content_orchestrator.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ========================================
# MONITORING AND ALERTING
# ========================================

# Custom metric for content generation requests
resource "google_monitoring_metric_descriptor" "content_generation_requests" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Content Generation Requests"
  description  = "Number of content generation requests processed"
  type        = "custom.googleapis.com/content_generation/requests"
  metric_kind = "CUMULATIVE"
  value_type  = "INT64"
  unit        = "1"
  
  labels {
    key         = "content_type"
    value_type  = "STRING"
    description = "Type of content generated (music, video, speech)"
  }
  
  labels {
    key         = "status"
    value_type  = "STRING"
    description = "Request status (success, error)"
  }
  
  labels {
    key         = "region"
    value_type  = "STRING"
    description = "Region where request was processed"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Custom metric for content generation latency
resource "google_monitoring_metric_descriptor" "content_generation_latency" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Content Generation Latency"
  description  = "Latency distribution for content generation requests"
  type        = "custom.googleapis.com/content_generation/latency"
  metric_kind = "GAUGE"
  value_type  = "DISTRIBUTION"
  unit        = "s"
  
  labels {
    key         = "content_type"
    value_type  = "STRING"
    description = "Type of content generated"
  }
  
  labels {
    key         = "model_version"
    value_type  = "STRING"
    description = "AI model version used"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alerting policy for high error rates
resource "google_monitoring_alert_policy" "high_error_rate" {
  count        = var.enable_monitoring && length(var.notification_channels) > 0 ? 1 : 0
  display_name = "Content Generation High Error Rate - ${local.name_suffix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud Functions Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${local.music_function_name}|${local.video_function_name}|${local.quality_function_name}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alerting policy for Cloud Run service availability
resource "google_monitoring_alert_policy" "orchestrator_availability" {
  count        = var.enable_monitoring && length(var.notification_channels) > 0 ? 1 : 0
  display_name = "Content Orchestrator Service Availability - ${local.name_suffix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud Run Service Down"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.orchestrator_service_name}\""
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# ========================================
# SECURITY CONFIGURATION
# ========================================

# VPC for secure networking (if advanced security is needed)
resource "google_compute_network" "content_vpc" {
  count                   = var.environment == "prod" ? 1 : 0
  name                    = "content-generation-vpc-${local.name_suffix}"
  description             = "VPC for content generation platform security"
  auto_create_subnetworks = false
  mtu                     = 1460
  
  depends_on = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "content_subnet" {
  count         = var.environment == "prod" ? 1 : 0
  name          = "content-generation-subnet-${local.name_suffix}"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.content_vpc[0].id
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }
  
  depends_on = [google_compute_network.content_vpc]
}

# Cloud Armor security policy (for production environments)
resource "google_compute_security_policy" "content_security_policy" {
  count       = var.environment == "prod" ? 1 : 0
  name        = "content-generation-security-policy-${local.name_suffix}"
  description = "Security policy for content generation platform"
  
  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }
  
  rule {
    action   = "deny(403)"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default deny rule"
  }
  
  depends_on = [google_project_service.required_apis]
}