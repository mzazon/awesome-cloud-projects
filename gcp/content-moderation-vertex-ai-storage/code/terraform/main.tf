# Content Moderation Infrastructure with Vertex AI and Cloud Storage
# This file creates a complete content moderation system using GCP services

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with consistent conventions
  resource_suffix = random_id.suffix.hex
  bucket_location = var.bucket_location != null ? var.bucket_location : var.region
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
    created-by  = "terraform"
  })
  
  # Bucket names with uniqueness
  bucket_incoming    = "${var.resource_prefix}-incoming-${local.resource_suffix}"
  bucket_quarantine  = "${var.resource_prefix}-quarantine-${local.resource_suffix}"
  bucket_approved    = "${var.resource_prefix}-approved-${local.resource_suffix}"
  
  # Function and topic names
  topic_name                = "${var.resource_prefix}-topic-${local.resource_suffix}"
  moderation_function_name  = "${var.resource_prefix}-moderator-${local.resource_suffix}"
  notification_function_name = "${var.resource_prefix}-notifier-${local.resource_suffix}"
  service_account_name      = "${var.resource_prefix}-sa-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent automatic disabling of APIs when resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Wait for APIs to be fully enabled before creating resources
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  
  create_duration = "60s"
}

# Create service account for content moderation functions
resource "google_service_account" "content_moderator" {
  count = var.custom_service_account_email == null ? 1 : 0
  
  account_id   = local.service_account_name
  display_name = "Content Moderation Service Account"
  description  = "Service account for automated content moderation using Vertex AI"
  project      = var.project_id
  
  depends_on = [time_sleep.wait_for_apis]
}

# IAM role bindings for service account
resource "google_project_iam_member" "content_moderator_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${var.custom_service_account_email != null ? var.custom_service_account_email : google_service_account.content_moderator[0].email}"
  
  depends_on = [google_service_account.content_moderator]
}

resource "google_project_iam_member" "content_moderator_vertex_ai" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${var.custom_service_account_email != null ? var.custom_service_account_email : google_service_account.content_moderator[0].email}"
  
  depends_on = [google_service_account.content_moderator]
}

resource "google_project_iam_member" "content_moderator_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.custom_service_account_email != null ? var.custom_service_account_email : google_service_account.content_moderator[0].email}"
  
  depends_on = [google_service_account.content_moderator]
}

resource "google_project_iam_member" "content_moderator_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.custom_service_account_email != null ? var.custom_service_account_email : google_service_account.content_moderator[0].email}"
  
  depends_on = [google_service_account.content_moderator]
}

# Cloud Storage Bucket for incoming content
resource "google_storage_bucket" "incoming" {
  name          = local.bucket_incoming
  location      = local.bucket_location
  project       = var.project_id
  storage_class = var.storage_class
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  dynamic "public_access_prevention" {
    for_each = var.enable_bucket_public_access_prevention ? [1] : []
    content {
      enforced = true
    }
  }
  
  # Versioning configuration
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  # Force destroy for cleanup (use with caution)
  force_destroy = var.force_destroy_buckets
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Storage Bucket for quarantined content
resource "google_storage_bucket" "quarantine" {
  name          = local.bucket_quarantine
  location      = local.bucket_location
  project       = var.project_id
  storage_class = var.storage_class
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  dynamic "public_access_prevention" {
    for_each = var.enable_bucket_public_access_prevention ? [1] : []
    content {
      enforced = true
    }
  }
  
  # Versioning configuration
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  # Force destroy for cleanup (use with caution)
  force_destroy = var.force_destroy_buckets
  
  depends_on = [time_sleep.wait_for_apis]
}

# Cloud Storage Bucket for approved content
resource "google_storage_bucket" "approved" {
  name          = local.bucket_approved
  location      = local.bucket_location
  project       = var.project_id
  storage_class = var.storage_class
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  dynamic "public_access_prevention" {
    for_each = var.enable_bucket_public_access_prevention ? [1] : []
    content {
      enforced = true
    }
  }
  
  # Versioning configuration
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  # Force destroy for cleanup (use with caution)
  force_destroy = var.force_destroy_buckets
  
  depends_on = [time_sleep.wait_for_apis]
}

# Pub/Sub topic for content moderation events
resource "google_pubsub_topic" "content_moderation" {
  name    = local.topic_name
  project = var.project_id
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [time_sleep.wait_for_apis]
}

# Pub/Sub subscription for content moderation function
resource "google_pubsub_subscription" "content_moderation" {
  name    = "${local.topic_name}-subscription"
  topic   = google_pubsub_topic.content_moderation.name
  project = var.project_id
  
  # Acknowledgment configuration
  ack_deadline_seconds = var.pubsub_ack_deadline
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Dead letter policy for failed messages
  dead_letter_policy {
    max_delivery_attempts = var.pubsub_max_delivery_attempts
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.content_moderation]
}

# Archive the content moderation function source code
data "archive_file" "content_moderation_function" {
  type        = "zip"
  output_path = "${path.module}/content_moderation_function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id        = var.project_id
      region           = var.vertex_ai_location
      quarantine_bucket = local.bucket_quarantine
      approved_bucket  = local.bucket_approved
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_incoming}-functions"
  location      = local.bucket_location
  project       = var.project_id
  storage_class = "STANDARD"
  
  # Security configurations
  uniform_bucket_level_access = true
  
  public_access_prevention {
    enforced = true
  }
  
  # Labels for resource management
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })
  
  force_destroy = true
  
  depends_on = [time_sleep.wait_for_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "content_moderation_function" {
  name   = "content_moderation_function-${data.archive_file.content_moderation_function.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.content_moderation_function.output_path
  
  depends_on = [data.archive_file.content_moderation_function]
}

# Cloud Function for content moderation
resource "google_cloudfunctions2_function" "content_moderator" {
  name     = local.moderation_function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = "python311"
    entry_point = "moderate_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.content_moderation_function.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    
    available_memory   = "${var.function_memory_mb}M"
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      GCP_PROJECT       = var.project_id
      FUNCTION_REGION   = var.vertex_ai_location
      QUARANTINE_BUCKET = local.bucket_quarantine
      APPROVED_BUCKET   = local.bucket_approved
    }
    
    service_account_email = var.custom_service_account_email != null ? var.custom_service_account_email : google_service_account.content_moderator[0].email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.incoming.name
    }
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_storage_bucket_object.content_moderation_function,
    google_project_iam_member.content_moderator_storage,
    google_project_iam_member.content_moderator_vertex_ai,
    google_project_iam_member.content_moderator_pubsub,
    google_project_iam_member.content_moderator_logs
  ]
}

# Archive the notification function source code
data "archive_file" "notification_function" {
  count = var.create_notification_function ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/notification_function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/notification.py", {
      project_id        = var.project_id
      quarantine_bucket = local.bucket_quarantine
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/notification_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload notification function source code to Cloud Storage
resource "google_storage_bucket_object" "notification_function" {
  count = var.create_notification_function ? 1 : 0
  
  name   = "notification_function-${data.archive_file.notification_function[0].output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.notification_function[0].output_path
  
  depends_on = [data.archive_file.notification_function]
}

# Cloud Function for quarantine notifications
resource "google_cloudfunctions2_function" "notification_handler" {
  count = var.create_notification_function ? 1 : 0
  
  name     = local.notification_function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = "python311"
    entry_point = "notify_quarantine"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.notification_function[0].name
      }
    }
  }
  
  service_config {
    max_instance_count = 5
    min_instance_count = 0
    
    available_memory = "${var.notification_function_memory_mb}M"
    timeout_seconds  = var.notification_function_timeout
    
    environment_variables = {
      QUARANTINE_BUCKET = local.bucket_quarantine
    }
    
    service_account_email = var.custom_service_account_email != null ? var.custom_service_account_email : google_service_account.content_moderator[0].email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.quarantine.name
    }
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_storage_bucket_object.notification_function,
    google_project_iam_member.content_moderator_storage,
    google_project_iam_member.content_moderator_logs
  ]
}

# Cloud Monitoring alert policy for quarantined content
resource "google_monitoring_alert_policy" "quarantine_alert" {
  display_name = "Content Moderation - Quarantine Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Quarantine bucket object count"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"${local.bucket_quarantine}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  combiner = "OR"
  enabled  = true
  
  documentation {
    content = "Alert triggered when content is quarantined for review"
  }
  
  depends_on = [google_storage_bucket.quarantine]
}

# Logging configuration for content moderation
resource "google_logging_project_sink" "content_moderation_logs" {
  name        = "${var.resource_prefix}-logs-sink"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}"
  
  filter = <<EOF
resource.type="cloud_function"
resource.labels.function_name="${local.moderation_function_name}"
OR
resource.labels.function_name="${local.notification_function_name}"
EOF
  
  unique_writer_identity = true
  
  depends_on = [
    google_cloudfunctions2_function.content_moderator,
    google_cloudfunctions2_function.notification_handler
  ]
}

# Grant logging sink permission to write to bucket
resource "google_storage_bucket_iam_member" "logs_sink_writer" {
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.content_moderation_logs.writer_identity
  
  depends_on = [google_logging_project_sink.content_moderation_logs]
}