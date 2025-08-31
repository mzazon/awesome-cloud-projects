# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.apis_to_enable) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when the resource is destroyed
  disable_on_destroy = false
  
  # Allow time for API enablement to propagate
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Pub/Sub topic for file upload notifications
resource "google_pubsub_topic" "file_notifications" {
  name    = "${var.topic_name}-${random_id.suffix.hex}"
  project = var.project_id
  labels  = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for consuming notifications
resource "google_pubsub_subscription" "file_processor" {
  name    = "${var.subscription_name}-${random_id.suffix.hex}"
  project = var.project_id
  topic   = google_pubsub_topic.file_notifications.name
  labels  = var.labels
  
  # Configure message acknowledgment settings
  ack_deadline_seconds = var.ack_deadline_seconds
  
  # Configure message retention
  message_retention_duration = var.message_retention_duration
  
  # Configure retry policy with exponential backoff
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Enable exactly once delivery for better message processing guarantees
  enable_exactly_once_delivery = true
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for file uploads
resource "google_storage_bucket" "file_uploads" {
  name     = "${var.bucket_name_prefix}-${var.project_id}-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
  labels   = var.labels
  
  # Configure default storage class
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for simplified IAM
  uniform_bucket_level_access = var.uniform_bucket_level_access
  
  # Enable versioning for better data protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management to optimize costs
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
  
  # Configure CORS for web applications (optional)
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Storage service account permission to publish to Pub/Sub topic
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.file_notifications.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create notification configuration for bucket events
resource "google_storage_notification" "file_upload_notification" {
  bucket         = google_storage_bucket.file_uploads.name
  topic          = google_pubsub_topic.file_notifications.id
  payload_format = var.notification_payload_format
  event_types    = var.notification_event_types
  
  # Add custom attributes to help with message routing
  custom_attributes = {
    bucket_name = google_storage_bucket.file_uploads.name
    region      = var.region
    environment = lookup(var.labels, "environment", "unknown")
  }
  
  # Ensure proper dependencies
  depends_on = [
    google_pubsub_topic_iam_member.storage_publisher,
    google_storage_bucket.file_uploads,
    google_pubsub_topic.file_notifications
  ]
}

# Optional: Create a sample Cloud Function to process notifications (commented out by default)
# Uncomment and customize based on your processing needs
/*
resource "google_cloudfunctions2_function" "file_processor" {
  name     = "file-processor-${random_id.suffix.hex}"
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = "python39"
    entry_point = "process_file_notification"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    available_memory      = "256Mi"
    timeout_seconds       = 60
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.file_uploads.name
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.file_notifications.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_subscription.file_processor
  ]
}
*/

# Output important resource information for verification and integration
locals {
  # Create a map of all created resources for easy reference
  created_resources = {
    pubsub_topic_name      = google_pubsub_topic.file_notifications.name
    pubsub_topic_id        = google_pubsub_topic.file_notifications.id
    subscription_name      = google_pubsub_subscription.file_processor.name
    subscription_id        = google_pubsub_subscription.file_processor.id
    bucket_name            = google_storage_bucket.file_uploads.name
    bucket_url             = google_storage_bucket.file_uploads.url
    notification_id        = google_storage_notification.file_upload_notification.id
    project_id             = var.project_id
    region                 = var.region
    random_suffix          = random_id.suffix.hex
  }
}