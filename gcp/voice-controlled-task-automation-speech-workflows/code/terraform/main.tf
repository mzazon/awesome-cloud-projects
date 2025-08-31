# Voice-Controlled Task Automation Infrastructure with Speech-to-Text and Workflows
# This configuration creates a complete serverless voice automation system on Google Cloud

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming and labeling
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.name_prefix}-${var.environment}"
  
  # Resource names with unique suffixes
  voice_function_name     = "${local.common_name}-voice-processor-${local.resource_suffix}"
  task_function_name      = "${local.common_name}-task-processor-${local.resource_suffix}"
  workflow_name          = "${local.common_name}-workflow-${local.resource_suffix}"
  bucket_name            = "${local.common_name}-audio-${var.project_id}-${local.resource_suffix}"
  queue_name             = "${local.common_name}-queue-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    suffix     = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "speech.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudtasks.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying to avoid dependency issues
  disable_on_destroy = false
}

# Cloud Storage bucket for audio file storage
resource "google_storage_bucket" "audio_files" {
  name     = local.bucket_name
  location = var.bucket_location
  
  # Storage configuration
  storage_class               = var.bucket_storage_class
  uniform_bucket_level_access = true
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.audio_file_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Delete versioned objects after retention period
  lifecycle_rule {
    condition {
      age                        = var.audio_file_retention_days
      with_state                = "ARCHIVED"
      matches_storage_class     = [var.bucket_storage_class]
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for web uploads
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Tasks queue for asynchronous task processing
resource "google_cloud_tasks_queue" "task_queue" {
  name     = local.queue_name
  location = var.region
  
  # Rate limiting configuration
  rate_limits {
    max_dispatches_per_second = var.task_queue_max_dispatches_per_second
    max_concurrent_dispatches = var.task_queue_max_concurrent_dispatches
  }
  
  # Retry configuration for reliability
  retry_config {
    max_attempts       = 5
    max_retry_duration = "300s"
    max_backoff        = "60s"
    min_backoff        = "1s"
    max_doublings      = 5
  }
  
  depends_on = [google_project_service.required_apis]
}

# Service account for voice processing function
resource "google_service_account" "voice_processor_sa" {
  account_id   = "${local.common_name}-voice-sa-${local.resource_suffix}"
  display_name = "Voice Processor Service Account"
  description  = "Service account for voice processing Cloud Function"
}

# Service account for task processing function
resource "google_service_account" "task_processor_sa" {
  account_id   = "${local.common_name}-task-sa-${local.resource_suffix}"
  display_name = "Task Processor Service Account"
  description  = "Service account for task processing Cloud Function"
}

# IAM role bindings for voice processor function
resource "google_project_iam_member" "voice_processor_speech_client" {
  project = var.project_id
  role    = "roles/speech.client"
  member  = "serviceAccount:${google_service_account.voice_processor_sa.email}"
}

resource "google_project_iam_member" "voice_processor_workflows_invoker" {
  project = var.project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${google_service_account.voice_processor_sa.email}"
}

resource "google_storage_bucket_iam_member" "voice_processor_storage_viewer" {
  bucket = google_storage_bucket.audio_files.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.voice_processor_sa.email}"
}

# IAM role bindings for task processor function
resource "google_project_iam_member" "task_processor_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.task_processor_sa.email}"
}

resource "google_storage_bucket_iam_member" "task_processor_storage_viewer" {
  bucket = google_storage_bucket.audio_files.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.task_processor_sa.email}"
}

# IAM role bindings for Cloud Workflows service account
resource "google_project_iam_member" "workflows_cloudtasks_admin" {
  project = var.project_id
  role    = "roles/cloudtasks.admin"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

resource "google_project_iam_member" "workflows_functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

# Create function source files first
resource "local_file" "voice_processor_main_py" {
  filename = "${path.module}/function_sources/voice_processor_main.py"
  content = templatefile("${path.module}/templates/voice_processor_main.py.tpl", {
    project_id    = var.project_id
    region        = var.region
    workflow_name = local.workflow_name
    language_code = var.speech_language_code
    speech_model  = var.speech_model
  })
}

resource "local_file" "voice_processor_requirements_txt" {
  filename = "${path.module}/function_sources/voice_processor_requirements.txt"
  content  = file("${path.module}/templates/voice_processor_requirements.txt")
}

resource "local_file" "task_processor_main_py" {
  filename = "${path.module}/function_sources/task_processor_main.py"
  content  = file("${path.module}/templates/task_processor_main.py")
}

resource "local_file" "task_processor_requirements_txt" {
  filename = "${path.module}/function_sources/task_processor_requirements.txt"
  content  = file("${path.module}/templates/task_processor_requirements.txt")
}

resource "local_file" "workflow_definition" {
  filename = "${path.module}/workflow_sources/task_automation_workflow.yaml"
  content = templatefile("${path.module}/templates/task_automation_workflow.yaml.tpl", {
    project_id              = var.project_id
    region                  = var.region
    queue_name              = local.queue_name
    task_processor_function = local.task_function_name
    resource_suffix         = local.resource_suffix
  })
}

# Create source code archives for Cloud Functions
data "archive_file" "voice_processor_source" {
  type        = "zip"
  output_path = "${path.module}/voice-processor-source.zip"
  
  source {
    content  = local_file.voice_processor_main_py.content
    filename = "main.py"
  }
  
  source {
    content  = local_file.voice_processor_requirements_txt.content
    filename = "requirements.txt"
  }
  
  depends_on = [
    local_file.voice_processor_main_py,
    local_file.voice_processor_requirements_txt
  ]
}

data "archive_file" "task_processor_source" {
  type        = "zip"
  output_path = "${path.module}/task-processor-source.zip"
  
  source {
    content  = local_file.task_processor_main_py.content
    filename = "main.py"
  }
  
  source {
    content  = local_file.task_processor_requirements_txt.content
    filename = "requirements.txt"
  }
  
  depends_on = [
    local_file.task_processor_main_py,
    local_file.task_processor_requirements_txt
  ]
}

# Cloud Storage buckets for function source code
resource "google_storage_bucket" "functions_source" {
  name                        = "${local.common_name}-functions-${local.resource_suffix}"
  location                    = var.region
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "voice_processor_source" {
  name   = "voice-processor-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.voice_processor_source.output_path
}

resource "google_storage_bucket_object" "task_processor_source" {
  name   = "task-processor-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.task_processor_source.output_path
}

# Voice processing Cloud Function
resource "google_cloudfunctions_function" "voice_processor" {
  name        = local.voice_function_name
  description = "Processes voice commands using Speech-to-Text and triggers workflows"
  region      = var.region
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.functions_source.name
  source_archive_object = google_storage_bucket_object.voice_processor_source.name
  
  # Function configuration
  runtime     = "python311"
  entry_point = "process_voice_command"
  
  # HTTP trigger configuration
  trigger {
    http_trigger {}
  }
  
  # Resource allocation
  available_memory_mb = var.voice_processor_memory
  timeout             = var.voice_processor_timeout
  
  # Environment variables
  environment_variables = {
    GCP_PROJECT    = var.project_id
    REGION         = var.region
    WORKFLOW_NAME  = local.workflow_name
    QUEUE_NAME     = local.queue_name
    LANGUAGE_CODE  = var.speech_language_code
    SPEECH_MODEL   = var.speech_model
  }
  
  # Service account
  service_account_email = google_service_account.voice_processor_sa.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.voice_processor_speech_client,
    google_project_iam_member.voice_processor_workflows_invoker
  ]
}

# Task processing Cloud Function
resource "google_cloudfunctions_function" "task_processor" {
  name        = local.task_function_name
  description = "Processes tasks created by voice commands"
  region      = var.region
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.functions_source.name
  source_archive_object = google_storage_bucket_object.task_processor_source.name
  
  # Function configuration
  runtime     = "python311"
  entry_point = "process_task"
  
  # HTTP trigger configuration
  trigger {
    http_trigger {}
  }
  
  # Resource allocation
  available_memory_mb = var.task_processor_memory
  timeout             = var.task_processor_timeout
  
  # Environment variables
  environment_variables = {
    GCP_PROJECT = var.project_id
    REGION      = var.region
  }
  
  # Service account
  service_account_email = google_service_account.task_processor_sa.email
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.task_processor_logging_writer
  ]
}

# IAM policy for Cloud Functions (conditional)
resource "google_cloudfunctions_function_iam_member" "voice_processor_invoker" {
  count = var.allow_unauthenticated_functions ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.voice_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "task_processor_invoker" {
  count = var.allow_unauthenticated_functions ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.task_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Workflow for task automation orchestration
resource "google_workflows_workflow" "task_automation" {
  name        = local.workflow_name
  region      = var.region
  description = "Orchestrates voice-triggered task automation processes"
  
  # Workflow definition with task processing logic
  source_contents = local_file.workflow_definition.content
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.task_processor,
    google_cloud_tasks_queue.task_queue,
    local_file.workflow_definition
  ]
}

# Cloud Logging configuration for structured logging
resource "google_logging_project_sink" "voice_automation_logs" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  name        = "${local.common_name}-logs-${local.resource_suffix}"
  description = "Centralized logging for voice automation system"
  
  # Log filter for voice automation components
  filter = <<-EOT
    resource.type="cloud_function" AND
    (resource.labels.function_name="${local.voice_function_name}" OR
     resource.labels.function_name="${local.task_function_name}") OR
    resource.type="workflows.googleapis.com/Workflow" AND
    resource.labels.workflow_id="${local.workflow_name}" OR
    resource.type="gce_instance" AND
    jsonPayload.component="voice-automation"
  EOT
  
  # Use the same project for log storage (can be configured to use different project)
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/${local.common_name}-centralized-${local.resource_suffix}"
  
  # Unique writer identity
  unique_writer_identity = true
}

# Monitoring dashboard for voice automation system
resource "google_monitoring_dashboard" "voice_automation_dashboard" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    project_id              = var.project_id
    voice_function_name     = local.voice_function_name
    task_function_name      = local.task_function_name
    workflow_name          = local.workflow_name
    queue_name             = local.queue_name
  })
  
  depends_on = [
    google_cloudfunctions_function.voice_processor,
    google_cloudfunctions_function.task_processor,
    google_workflows_workflow.task_automation
  ]
}

