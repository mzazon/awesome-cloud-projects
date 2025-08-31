# Smart Document Review Workflow with ADK and Storage
# Main Terraform configuration file defining all infrastructure resources

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common naming convention
  resource_suffix = random_id.suffix.hex
  common_name     = "${var.resource_prefix}-${var.environment}-${local.resource_suffix}"
  
  # Storage bucket names (must be globally unique)
  input_bucket_name   = "${local.common_name}-input"
  results_bucket_name = "${local.common_name}-results"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment    = var.environment
    resource-group = "document-review-workflow"
    created-by     = "terraform"
    timestamp      = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent automatic disabling when destroying
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  display_name = "Document Review Function Service Account"
  description  = "Service account for document review Cloud Function with ADK integration"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for function service account
resource "google_project_iam_member" "function_storage_object_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_object_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Storage bucket for document inputs
resource "google_storage_bucket" "input_bucket" {
  name          = local.input_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for enhanced security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = var.lifecycle_age
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for review results
resource "google_storage_bucket" "results_bucket" {
  name          = local.results_bucket_name
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for enhanced security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for results retention
  lifecycle_rule {
    condition {
      age = var.lifecycle_age * 2  # Keep results longer than inputs
    }
    action {
      type = "Delete"
    }
  }
  
  # CORS configuration for result access
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# IAM binding for function to access input bucket
resource "google_storage_bucket_iam_member" "input_bucket_object_viewer" {
  bucket = google_storage_bucket.input_bucket.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for function to access results bucket
resource "google_storage_bucket_iam_member" "results_bucket_object_admin" {
  bucket = google_storage_bucket.results_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create ZIP archive for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id           = var.project_id
      input_bucket_name    = google_storage_bucket.input_bucket.name
      results_bucket_name  = google_storage_bucket.results_bucket.name
      gemini_model        = var.gemini_model
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/requirements.txt", {})
    filename = "requirements.txt"
  }
  
  source {
    content = templatefile("${path.module}/function_code/agents/__init__.py", {})
    filename = "agents/__init__.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/agents/grammar_agent.py", {
      gemini_model = var.gemini_model
    })
    filename = "agents/grammar_agent.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/agents/accuracy_agent.py", {
      gemini_model = var.gemini_model
    })
    filename = "agents/accuracy_agent.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/agents/style_agent.py", {
      gemini_model = var.gemini_model
    })
    filename = "agents/style_agent.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/agents/coordinator.py", {})
    filename = "agents/coordinator.py"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.results_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Content hash for deployment tracking
  content_type = "application/zip"
}

# Cloud Function for document processing
resource "google_cloudfunctions2_function" "document_processor" {
  name        = "${var.resource_prefix}-processor-${local.resource_suffix}"
  location    = var.region
  project     = var.project_id
  description = "Multi-agent document review processor using ADK"
  
  build_config {
    runtime     = var.python_runtime
    entry_point = "process_document"
    
    source {
      storage_source {
        bucket = google_storage_bucket.results_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    environment_variables = {
      PROJECT_ID           = var.project_id
      INPUT_BUCKET        = google_storage_bucket.input_bucket.name
      RESULTS_BUCKET      = google_storage_bucket.results_bucket.name
      GEMINI_MODEL        = var.gemini_model
      ENVIRONMENT         = var.environment
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = 0
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      PROJECT_ID           = var.project_id
      INPUT_BUCKET        = google_storage_bucket.input_bucket.name
      RESULTS_BUCKET      = google_storage_bucket.results_bucket.name
      GEMINI_MODEL        = var.gemini_model
      ENVIRONMENT         = var.environment
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.input_bucket.name
    }
  }
  
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_storage_object_viewer,
    google_project_iam_member.function_storage_object_creator,
    google_project_iam_member.function_vertex_ai_user,
    google_project_iam_member.function_eventarc_receiver
  ]
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Document Processor Function Error Rate"
  project      = var.project_id
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" resource.labels.function_name=\"${google_cloudfunctions2_function.document_processor.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "1800s"
  }
  
  combiner     = "OR"
  enabled      = true
  
  documentation {
    content   = "Alert when document processor function error rate exceeds 10%"
    mime_type = "text/markdown"
  }
}

# Log sink for function logs
resource "google_logging_project_sink" "function_logs" {
  name        = "${var.resource_prefix}-function-logs-${local.resource_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.results_bucket.name}/logs"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.document_processor.name}"
  EOT
  
  unique_writer_identity = true
}

# Grant log sink permission to write to bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.results_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity
}

# Budget alert for cost monitoring
resource "google_billing_budget" "project_budget" {
  count = var.enable_budget_alerts ? 1 : 0
  
  billing_account = data.google_billing_account.account.id
  display_name    = "Document Review Workflow Budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  threshold_rules {
    threshold_percent = 0.8
    spend_basis      = "CURRENT_SPEND"
  }
  
  threshold_rules {
    threshold_percent = 1.0
    spend_basis      = "CURRENT_SPEND"
  }
}

# Data source for billing account
data "google_billing_account" "account" {
  open = true
}

# Pub/Sub topic for notifications (optional)
resource "google_pubsub_topic" "notifications" {
  name    = "${var.resource_prefix}-notifications-${local.resource_suffix}"
  project = var.project_id
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# IAM binding for function to publish notifications
resource "google_pubsub_topic_iam_member" "function_publisher" {
  topic   = google_pubsub_topic.notifications.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
  project = var.project_id
}