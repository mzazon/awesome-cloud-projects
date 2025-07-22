# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming conventions
  name_prefix = "${var.application_name}-${var.environment}"
  bucket_name = "${local.name_prefix}-artifacts-${random_id.suffix.hex}"
  topic_name  = "${local.name_prefix}-events-${random_id.suffix.hex}"
  function_name = "${local.name_prefix}-review-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    timestamp  = timestamp()
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "firebase.googleapis.com",
    "run.googleapis.com",
    "aiplatform.googleapis.com",
    "pubsub.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent deletion of services on destroy
  disable_on_destroy = false
}

# Create service account for development workflow automation
resource "google_service_account" "workflow_sa" {
  account_id   = "${local.name_prefix}-workflow-sa"
  display_name = "Development Workflow Automation Service Account"
  description  = "Service account for AI-powered development workflow automation"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the workflow service account
resource "google_project_iam_member" "workflow_sa_roles" {
  for_each = toset([
    "roles/storage.objectAdmin",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudfunctions.invoker",
    "roles/eventarc.eventReceiver",
    "roles/firebase.admin",
    "roles/aiplatform.user",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"

  depends_on = [google_service_account.workflow_sa]
}

# Cloud Storage bucket for development artifacts
resource "google_storage_bucket" "dev_artifacts" {
  name                        = local.bucket_name
  location                    = var.storage_location
  storage_class               = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"
  project                     = var.project_id

  # Enable versioning for code history
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for versioned objects
  lifecycle_rule {
    condition {
      age                   = 7
      with_state           = "ARCHIVED"
      num_newer_versions   = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for development events
resource "google_pubsub_topic" "dev_events" {
  name    = local.topic_name
  project = var.project_id

  # Message retention duration
  message_retention_duration = var.message_retention_duration

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for processing events
resource "google_pubsub_subscription" "dev_events_sub" {
  name    = "${local.topic_name}-sub"
  topic   = google_pubsub_topic.dev_events.name
  project = var.project_id

  # Acknowledgment deadline
  ack_deadline_seconds = var.subscription_ack_deadline

  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  # Retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels

  depends_on = [google_pubsub_topic.dev_events]
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dead-letter"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.bucket_name}-function-source"
  location                    = var.storage_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  project                     = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/index.js", {
      topic_name   = google_pubsub_topic.dev_events.name
      bucket_name  = google_storage_bucket.dev_artifacts.name
      project_id   = var.project_id
      gemini_model = var.gemini_model
    })
    filename = "index.js"
  }
  
  source {
    content = templatefile("${path.module}/function_code/package.json", {})
    filename = "package.json"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for intelligent code review automation
resource "google_cloudfunctions2_function" "code_review" {
  name        = local.function_name
  location    = var.region
  description = "AI-powered code review automation function"
  project     = var.project_id

  build_config {
    runtime     = var.function_runtime
    entry_point = "codeReviewAutomation"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = var.function_max_instances
    min_instance_count    = 0
    available_memory      = "${var.function_memory}M"
    timeout_seconds       = var.function_timeout
    ingress_settings      = var.function_ingress_settings
    all_traffic_on_latest_revision = true
    
    service_account_email = google_service_account.workflow_sa.email

    environment_variables = {
      TOPIC_NAME        = google_pubsub_topic.dev_events.name
      BUCKET_NAME       = google_storage_bucket.dev_artifacts.name
      PROJECT_ID        = var.project_id
      GEMINI_MODEL      = var.gemini_model
      ENVIRONMENT       = var.environment
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.storage.object.v1.finalized"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.workflow_sa.email

    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.dev_artifacts.name
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.workflow_sa,
    google_project_iam_member.workflow_sa_roles
  ]
}

# Firebase project initialization
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Firebase Hosting site (if enabled)
resource "google_firebase_hosting_site" "dev_workspace" {
  count    = var.enable_firebase_hosting ? 1 : 0
  provider = google-beta
  project  = var.project_id
  site_id  = "${local.name_prefix}-workspace"

  depends_on = [google_firebase_project.default]
}

# Firebase Firestore database for workspace data
resource "google_firestore_database" "workspace_db" {
  provider                    = google-beta
  project                     = var.project_id
  name                        = "(default)"
  location_id                 = var.firebase_location
  type                        = "FIRESTORE_NATIVE"
  concurrency_mode            = "OPTIMISTIC"
  app_engine_integration_mode = "DISABLED"

  depends_on = [google_firebase_project.default]
}

# Cloud Monitoring notification channel (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  display_name = "Development Workflow Email Notifications"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Code Review Function Errors"
  project      = var.project_id

  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true

  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring dashboard for development workflow
resource "google_monitoring_dashboard" "workflow_dashboard" {
  count          = var.enable_monitoring ? 1 : 0
  project        = var.project_id
  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    function_name = local.function_name
    bucket_name   = local.bucket_name
    topic_name    = local.topic_name
    project_id    = var.project_id
  })

  depends_on = [google_project_service.required_apis]
}

# Vertex AI Workbench instance for development (if enabled)
resource "google_workbench_instance" "dev_workbench" {
  count    = var.enable_vertex_ai ? 1 : 0
  name     = "${local.name_prefix}-workbench"
  location = var.zone
  project  = var.project_id

  gce_setup {
    machine_type = var.workspace_machine_type
    
    boot_disk {
      disk_size_gb = var.workspace_disk_size
      disk_type    = "PD_STANDARD"
    }

    # Network configuration
    network_interfaces {
      network = "default"
    }

    # Service account
    service_accounts {
      email = google_service_account.workflow_sa.email
    }

    # Enable IP forwarding for networking
    enable_ip_forwarding = false

    # Tags for firewall rules
    tags = ["ai-development", "workbench"]

    # Metadata for startup script
    metadata = {
      "notebook-disable-downloads" = "false"
      "notebook-disable-terminal"  = "false"
      "enable-oslogin"             = "true"
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_account.workflow_sa
  ]
}

# IAM binding for Workbench access
resource "google_project_iam_member" "workbench_user" {
  count   = var.enable_vertex_ai ? 1 : 0
  project = var.project_id
  role    = "roles/notebooks.admin"
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"

  depends_on = [google_service_account.workflow_sa]
}

# Cloud Build trigger for automated deployments
resource "google_cloudbuild_trigger" "deploy_trigger" {
  name        = "${local.name_prefix}-deploy-trigger"
  project     = var.project_id
  description = "Automated deployment trigger for AI-generated applications"

  # Trigger on Cloud Storage object creation in generated code folder
  pubsub_config {
    topic = google_pubsub_topic.dev_events.id
  }

  # Build configuration
  build {
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "functions", "deploy", local.function_name,
        "--runtime", var.function_runtime,
        "--trigger-bucket", google_storage_bucket.dev_artifacts.name,
        "--source", "."
      ]
    }

    # Deploy to Firebase Hosting if enabled
    dynamic "step" {
      for_each = var.enable_firebase_hosting ? [1] : []
      content {
        name = "gcr.io/cloud-builders/npm"
        args = ["run", "build"]
      }
    }

    dynamic "step" {
      for_each = var.enable_firebase_hosting ? [1] : []
      content {
        name = "gcr.io/$PROJECT_ID/firebase"
        args = ["deploy", "--only", "hosting"]
      }
    }

    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }

  service_account = google_service_account.workflow_sa.id

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.dev_events,
    google_service_account.workflow_sa
  ]
}

# Secret Manager secret for storing API keys and configuration
resource "google_secret_manager_secret" "ai_config" {
  secret_id = "${local.name_prefix}-ai-config"
  project   = var.project_id

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Secret version with default AI configuration
resource "google_secret_manager_secret_version" "ai_config_version" {
  secret = google_secret_manager_secret.ai_config.id
  secret_data = jsonencode({
    gemini_model = var.gemini_model
    features = {
      code_generation   = true
      code_completion   = true
      chat_assistance   = true
      code_review      = true
    }
    integrations = {
      firebase_studio = true
      cloud_storage   = true
      eventarc       = true
    }
  })

  depends_on = [google_secret_manager_secret.ai_config]
}

# IAM binding for secret access
resource "google_secret_manager_secret_iam_member" "workflow_sa_secret_access" {
  secret_id = google_secret_manager_secret.ai_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workflow_sa.email}"

  depends_on = [
    google_secret_manager_secret.ai_config,
    google_service_account.workflow_sa
  ]
}