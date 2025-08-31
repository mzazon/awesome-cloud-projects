# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  suffix             = random_id.suffix.hex
  templates_bucket   = "${var.resource_prefix}-templates-${local.suffix}"
  client_data_bucket = "${var.resource_prefix}-client-data-${local.suffix}"
  output_bucket      = "${var.resource_prefix}-generated-proposals-${local.suffix}"
  function_name      = "${var.resource_prefix}-function-${local.suffix}"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    suffix      = local.suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com"
  ]) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = true
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    read   = "5m"
    update = "10m"
    delete = "10m"
  }
}

# Cloud Storage bucket for proposal templates
resource "google_storage_bucket" "templates_bucket" {
  name                        = local.templates_bucket
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = var.bucket_uniform_access
  storage_class               = var.storage_class
  labels                      = local.common_labels

  # Enable versioning for template management
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  # Security configurations
  public_access_prevention = "enforced"

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for client data uploads (triggers function)
resource "google_storage_bucket" "client_data_bucket" {
  name                        = local.client_data_bucket
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = var.bucket_uniform_access
  storage_class               = var.storage_class
  labels                      = local.common_labels

  # Enable versioning for data integrity
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Security configurations
  public_access_prevention = "enforced"

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for generated proposals
resource "google_storage_bucket" "output_bucket" {
  name                        = local.output_bucket
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = var.bucket_uniform_access
  storage_class               = var.storage_class
  labels                      = local.common_labels

  # Enable versioning for proposal history
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Lifecycle management for long-term storage
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 1095 # 3 years
    }
    action {
      type = "Delete"
    }
  }

  # Security configurations
  public_access_prevention = "enforced"

  depends_on = [google_project_service.required_apis]
}

# Upload sample proposal template to templates bucket
resource "google_storage_bucket_object" "proposal_template" {
  name   = "proposal-template.txt"
  bucket = google_storage_bucket.templates_bucket.name
  content = <<-EOT
    BUSINESS PROPOSAL TEMPLATE

    Dear {{CLIENT_NAME}},

    Thank you for considering our services for {{PROJECT_TYPE}}. Based on our understanding of your requirements, we propose the following solution:

    PROJECT OVERVIEW:
    {{PROJECT_OVERVIEW}}

    SOLUTION APPROACH:
    {{SOLUTION_APPROACH}}

    TIMELINE:
    {{TIMELINE}}

    INVESTMENT:
    {{INVESTMENT}}

    NEXT STEPS:
    {{NEXT_STEPS}}

    We look forward to partnering with you.

    Best regards,
    Business Development Team
  EOT

  depends_on = [google_storage_bucket.templates_bucket]
}

# Service account for Cloud Function with appropriate permissions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.suffix}"
  display_name = "Proposal Generator Function Service Account"
  description  = "Service account for the business proposal generator Cloud Function"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM binding for function service account - Storage access
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# IAM binding for function service account - Vertex AI access
resource "google_project_iam_member" "function_vertexai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# IAM binding for function service account - Logging
resource "google_project_iam_member" "function_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    filename = "index.js"
    content = templatefile("${path.module}/function-source/index.js.tpl", {
      vertex_ai_model       = var.vertex_ai_model
      max_output_tokens     = var.vertex_ai_max_tokens
      temperature           = var.vertex_ai_temperature
      top_p                 = var.vertex_ai_top_p
      top_k                 = var.vertex_ai_top_k
      templates_bucket      = local.templates_bucket
      output_bucket         = local.output_bucket
      region                = var.region
    })
  }
  
  source {
    filename = "package.json"
    content = jsonencode({
      name = "proposal-generator"
      version = "1.0.0"
      description = "AI-powered business proposal generator"
      main = "index.js"
      dependencies = {
        "@google-cloud/vertexai" = "^1.0.0"
        "@google-cloud/storage" = "^7.0.0"
        "@google-cloud/functions-framework" = "^3.0.0"
      }
    })
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.suffix}.zip"
  bucket = google_storage_bucket.templates_bucket.name
  source = data.archive_file.function_source.output_path

  depends_on = [
    google_storage_bucket.templates_bucket,
    data.archive_file.function_source
  ]
}

# Cloud Function for proposal generation
resource "google_cloudfunctions2_function" "proposal_generator" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "AI-powered business proposal generator triggered by Cloud Storage uploads"
  labels      = local.common_labels

  build_config {
    runtime     = var.function_runtime
    entry_point = "generateProposal"
    
    source {
      storage_source {
        bucket = google_storage_bucket.templates_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = 0
    available_memory      = "${var.function_memory_mb}Mi"
    timeout_seconds       = var.function_timeout_seconds
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      TEMPLATES_BUCKET = local.templates_bucket
      OUTPUT_BUCKET    = local.output_bucket
      REGION          = var.region
      VERTEX_AI_MODEL = var.vertex_ai_model
    }

    # Security configurations
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.client_data_bucket.name
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_vertexai_user,
    google_project_iam_member.function_logs_writer
  ]
}

# Cloud Storage notification for additional monitoring (optional)
resource "google_storage_notification" "client_data_notification" {
  count  = var.enable_monitoring ? 1 : 0
  bucket = google_storage_bucket.client_data_bucket.name
  
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.function_notifications[0].id
  event_types = [
    "OBJECT_FINALIZE",
    "OBJECT_DELETE"
  ]

  depends_on = [
    google_storage_bucket.client_data_bucket,
    google_pubsub_topic.function_notifications
  ]
}

# Pub/Sub topic for function notifications (optional monitoring)
resource "google_pubsub_topic" "function_notifications" {
  count   = var.enable_monitoring ? 1 : 0
  name    = "${var.resource_prefix}-notifications-${local.suffix}"
  project = var.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Log sink for function monitoring (optional)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "${var.resource_prefix}-function-logs-${local.suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.output_bucket.name}/logs"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${local.function_name}"
    resource.labels.region="${var.region}"
  EOT
  
  unique_writer_identity = true

  depends_on = [
    google_cloudfunctions2_function.proposal_generator,
    google_storage_bucket.output_bucket
  ]
}

# IAM binding for log sink
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count  = var.enable_monitoring ? 1 : 0
  bucket = google_storage_bucket.output_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}