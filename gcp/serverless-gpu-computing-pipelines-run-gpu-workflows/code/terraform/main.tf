# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed names and configurations
locals {
  resource_suffix = random_id.suffix.hex
  service_prefix  = "${var.service_prefix}-${local.resource_suffix}"
  
  # Service names
  gpu_service_name        = "${local.service_prefix}-gpu-inference"
  preprocess_service_name = "${local.service_prefix}-preprocess"
  postprocess_service_name = "${local.service_prefix}-postprocess"
  
  # Storage bucket names
  input_bucket_name  = "${local.service_prefix}-input"
  model_bucket_name  = "${local.service_prefix}-models"
  output_bucket_name = "${local.service_prefix}-output"
  
  # Workflow and trigger names
  workflow_name = "${local.service_prefix}-ml-pipeline"
  trigger_name  = "${local.service_prefix}-storage-trigger"
  
  # Service account names
  eventarc_sa_name = "${local.service_prefix}-eventarc"
  workflow_sa_name = "${local.service_prefix}-workflow"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment    = var.environment
    resource_group = "ml-pipeline"
    created_by     = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",
    "workflows.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create Cloud Storage buckets for the ML pipeline
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.storage_config.location
  storage_class = var.storage_config.storage_class
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  lifecycle_rule {
    condition {
      age = var.storage_config.lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  versioning {
    enabled = true
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "model_bucket" {
  name          = local.model_bucket_name
  location      = var.storage_config.location
  storage_class = var.storage_config.storage_class
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  lifecycle_rule {
    condition {
      age = var.storage_config.lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  versioning {
    enabled = true
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_storage_bucket" "output_bucket" {
  name          = local.output_bucket_name
  location      = var.storage_config.location
  storage_class = var.storage_config.storage_class
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  lifecycle_rule {
    condition {
      age = var.storage_config.lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  versioning {
    enabled = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Artifact Registry for container images
resource "google_artifact_registry_repository" "container_registry" {
  provider = google-beta
  
  location      = var.container_registry.location
  repository_id = "${local.service_prefix}-containers"
  description   = "Container registry for ML pipeline services"
  format        = var.container_registry.format
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Eventarc
resource "google_service_account" "eventarc_sa" {
  account_id   = local.eventarc_sa_name
  display_name = var.iam_config.eventarc_sa_display_name
  description  = "Service account for Eventarc triggers in ML pipeline"
}

# Create service account for Workflow execution
resource "google_service_account" "workflow_sa" {
  account_id   = local.workflow_sa_name
  display_name = var.iam_config.workflow_sa_display_name
  description  = "Service account for Workflow execution in ML pipeline"
}

# IAM bindings for Eventarc service account
resource "google_project_iam_member" "eventarc_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

resource "google_project_iam_member" "eventarc_event_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.eventarc_sa.email}"
}

# IAM bindings for Workflow service account
resource "google_project_iam_member" "workflow_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_storage_objectViewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

resource "google_project_iam_member" "workflow_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# GPU Inference Service - Cloud Run with GPU support
resource "google_cloud_run_v2_service" "gpu_inference_service" {
  provider = google-beta
  
  name     = local.gpu_service_name
  location = var.region
  
  deletion_protection = var.deletion_protection
  
  template {
    service_account = google_service_account.workflow_sa.email
    
    timeout = "${var.gpu_service_config.timeout_seconds}s"
    
    scaling {
      max_instance_count = var.gpu_service_config.max_instances
      min_instance_count = 0
    }
    
    containers {
      # This would be populated with the actual container image after build
      image = "gcr.io/cloudrun/hello"
      
      resources {
        limits = {
          cpu    = var.gpu_service_config.cpu_count
          memory = "${var.gpu_service_config.memory_gb}Gi"
        }
        cpu_idle          = false
        startup_cpu_boost = true
      }
      
      # GPU configuration
      dynamic "gpu" {
        for_each = var.gpu_service_config.gpu_count > 0 ? [1] : []
        content {
          type  = var.gpu_service_config.gpu_type
          count = var.gpu_service_config.gpu_count
        }
      }
      
      ports {
        name           = "http1"
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
      
      env {
        name  = "SERVICE_NAME"
        value = "gpu-inference"
      }
    }
    
    max_instance_request_concurrency = var.gpu_service_config.concurrency
    
    labels = local.common_labels
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.workflow_sa
  ]
}

# Preprocessing Service - Cloud Run CPU
resource "google_cloud_run_v2_service" "preprocess_service" {
  provider = google-beta
  
  name     = local.preprocess_service_name
  location = var.region
  
  deletion_protection = var.deletion_protection
  
  template {
    service_account = google_service_account.workflow_sa.email
    
    timeout = "${var.cpu_service_config.timeout_seconds}s"
    
    scaling {
      max_instance_count = var.cpu_service_config.max_instances
      min_instance_count = 0
    }
    
    containers {
      # This would be populated with the actual container image after build
      image = "gcr.io/cloudrun/hello"
      
      resources {
        limits = {
          cpu    = var.cpu_service_config.preprocess_cpu_count
          memory = "${var.cpu_service_config.preprocess_memory_gb}Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }
      
      ports {
        name           = "http1"
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
      
      env {
        name  = "SERVICE_NAME"
        value = "preprocess"
      }
      
      env {
        name  = "INPUT_BUCKET"
        value = google_storage_bucket.input_bucket.name
      }
    }
    
    labels = local.common_labels
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.workflow_sa
  ]
}

# Postprocessing Service - Cloud Run CPU
resource "google_cloud_run_v2_service" "postprocess_service" {
  provider = google-beta
  
  name     = local.postprocess_service_name
  location = var.region
  
  deletion_protection = var.deletion_protection
  
  template {
    service_account = google_service_account.workflow_sa.email
    
    timeout = "${var.cpu_service_config.timeout_seconds}s"
    
    scaling {
      max_instance_count = var.cpu_service_config.max_instances
      min_instance_count = 0
    }
    
    containers {
      # This would be populated with the actual container image after build
      image = "gcr.io/cloudrun/hello"
      
      resources {
        limits = {
          cpu    = var.cpu_service_config.postprocess_cpu_count
          memory = "${var.cpu_service_config.postprocess_memory_gb}Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }
      
      ports {
        name           = "http1"
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
      
      env {
        name  = "SERVICE_NAME"
        value = "postprocess"
      }
      
      env {
        name  = "OUTPUT_BUCKET"
        value = google_storage_bucket.output_bucket.name
      }
    }
    
    labels = local.common_labels
  }
  
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.workflow_sa
  ]
}

# Cloud Run IAM bindings for unauthenticated access (if enabled)
resource "google_cloud_run_service_iam_member" "gpu_inference_noauth" {
  count = var.security_config.require_authentication ? 0 : 1
  
  provider = google-beta
  location = google_cloud_run_v2_service.gpu_inference_service.location
  service  = google_cloud_run_v2_service.gpu_inference_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "preprocess_noauth" {
  count = var.security_config.require_authentication ? 0 : 1
  
  provider = google-beta
  location = google_cloud_run_v2_service.preprocess_service.location
  service  = google_cloud_run_v2_service.preprocess_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "postprocess_noauth" {
  count = var.security_config.require_authentication ? 0 : 1
  
  provider = google-beta
  location = google_cloud_run_v2_service.postprocess_service.location
  service  = google_cloud_run_v2_service.postprocess_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create the workflow definition file
resource "local_file" "workflow_definition" {
  filename = "${path.module}/workflow-definition.yaml"
  content = templatefile("${path.module}/templates/workflow-definition.yaml.tpl", {
    project_id           = var.project_id
    input_bucket         = google_storage_bucket.input_bucket.name
    output_bucket        = google_storage_bucket.output_bucket.name
    preprocess_url       = google_cloud_run_v2_service.preprocess_service.uri
    inference_url        = google_cloud_run_v2_service.gpu_inference_service.uri
    postprocess_url      = google_cloud_run_v2_service.postprocess_service.uri
  })
  
  depends_on = [
    google_cloud_run_v2_service.gpu_inference_service,
    google_cloud_run_v2_service.preprocess_service,
    google_cloud_run_v2_service.postprocess_service
  ]
}

# Cloud Workflows for ML pipeline orchestration
resource "google_workflows_workflow" "ml_pipeline" {
  name          = local.workflow_name
  description   = var.workflow_config.description
  region        = var.region
  service_account = google_service_account.workflow_sa.email
  
  labels = local.common_labels
  
  call_log_level = var.workflow_config.call_log_level
  
  source_contents = local_file.workflow_definition.content
  
  depends_on = [
    google_project_service.required_apis,
    local_file.workflow_definition
  ]
}

# Eventarc trigger for Cloud Storage events
resource "google_eventarc_trigger" "storage_trigger" {
  name     = local.trigger_name
  location = var.region
  
  service_account = google_service_account.eventarc_sa.email
  
  matching_criteria {
    attribute = "type"
    value     = var.eventarc_config.event_type
  }
  
  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.input_bucket.name
  }
  
  destination {
    workflow = google_workflows_workflow.ml_pipeline.id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.ml_pipeline
  ]
}

# Cloud Monitoring alert policy for GPU service
resource "google_monitoring_alert_policy" "gpu_service_alert" {
  count = var.monitoring_config.enable_cloud_monitoring ? 1 : 0
  
  display_name = "GPU Service High CPU Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "GPU Service CPU Usage"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.gpu_service_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.monitoring_config.alert_threshold_cpu
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring dashboard for the ML pipeline
resource "google_monitoring_dashboard" "ml_pipeline_dashboard" {
  count = var.monitoring_config.enable_cloud_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "ML Pipeline Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "GPU Service Request Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${local.gpu_service_name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
              yAxis = {
                label = "Requests per second"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Workflow Execution Status"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"workflows.googleapis.com/Workflow\" AND resource.labels.workflow_id=\"${local.workflow_name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
              yAxis = {
                label = "Executions per second"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for aggregating pipeline logs
resource "google_logging_project_sink" "ml_pipeline_logs" {
  count = var.monitoring_config.enable_cloud_monitoring ? 1 : 0
  
  name        = "${local.service_prefix}-logs"
  description = "Log sink for ML pipeline components"
  
  destination = "storage.googleapis.com/${google_storage_bucket.output_bucket.name}/logs"
  
  filter = "resource.type=\"cloud_run_revision\" AND (resource.labels.service_name=\"${local.gpu_service_name}\" OR resource.labels.service_name=\"${local.preprocess_service_name}\" OR resource.labels.service_name=\"${local.postprocess_service_name}\") OR resource.type=\"workflows.googleapis.com/Workflow\" AND resource.labels.workflow_id=\"${local.workflow_name}\""
  
  unique_writer_identity = true
}

# Grant log sink the necessary permissions
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.monitoring_config.enable_cloud_monitoring ? 1 : 0
  
  bucket = google_storage_bucket.output_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.ml_pipeline_logs[0].writer_identity
}