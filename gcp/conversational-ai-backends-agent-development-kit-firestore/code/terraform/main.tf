# Main Terraform configuration for Conversational AI Backend with Agent Development Kit and Firestore
# This configuration creates a complete conversational AI infrastructure on Google Cloud Platform

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Computed values for resource naming and configuration
  project_name           = "conversational-ai-${random_id.suffix.hex}"
  function_name         = "chat-processor-${random_id.suffix.hex}"
  history_function_name = "chat-history-${random_id.suffix.hex}"
  bucket_name          = "${var.project_id}-conversations-${random_id.suffix.hex}"
  firestore_database   = "chat-conversations-${random_id.suffix.hex}"
  vertex_ai_region     = var.vertex_ai_region != "" ? var.vertex_ai_region : var.region
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
  })
  
  # Required APIs for the conversational AI system
  required_apis = [
    "aiplatform.googleapis.com",           # Vertex AI for Agent Development Kit
    "cloudfunctions.googleapis.com",       # Cloud Functions for API layer
    "firestore.googleapis.com",           # Firestore for conversation storage
    "storage.googleapis.com",             # Cloud Storage for artifacts
    "cloudbuild.googleapis.com",          # Cloud Build for function deployment
    "run.googleapis.com",                 # Cloud Run (required for 2nd gen functions)
    "eventarc.googleapis.com",            # Eventarc for event-driven architecture
    "pubsub.googleapis.com",              # Pub/Sub for async processing
    "monitoring.googleapis.com",          # Cloud Monitoring for observability
    "logging.googleapis.com",             # Cloud Logging for debugging
    "secretmanager.googleapis.com",       # Secret Manager for API keys
    "iamcredentials.googleapis.com"       # IAM Service Account Credentials API
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent automatic disabling of APIs when Terraform is destroyed
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Firestore database for conversation storage
resource "google_firestore_database" "conversation_db" {
  provider = google-beta
  
  project                           = var.project_id
  name                             = local.firestore_database
  location_id                      = var.firestore_location
  type                            = "FIRESTORE_NATIVE"
  concurrency_mode                = "OPTIMISTIC"
  app_engine_integration_mode     = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state         = "DELETE_PROTECTION_DISABLED"
  deletion_policy                 = "DELETE"
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create composite index for efficient conversation queries
resource "google_firestore_index" "conversation_index" {
  provider = google-beta
  
  project    = var.project_id
  database   = google_firestore_database.conversation_db.name
  collection = "conversations"
  
  fields {
    field_path = "userId"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.conversation_db]
}

# Create additional index for user context queries
resource "google_firestore_index" "user_context_index" {
  provider = google-beta
  
  project    = var.project_id
  database   = google_firestore_database.conversation_db.name
  collection = "user_contexts"
  
  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "last_active"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.conversation_db]
}

# Create Cloud Storage bucket for conversation artifacts
resource "google_storage_bucket" "conversation_artifacts" {
  name                        = local.bucket_name
  location                   = var.region
  storage_class              = var.storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for conversation artifact protection
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age
      matches_prefix = ["conversations/archived/"]
    }
    action {
      type = "Delete"
    }
  }
  
  # Additional lifecycle rule for automatic archiving
  lifecycle_rule {
    condition {
      age = 30
      matches_prefix = ["conversations/active/"]
    }
    action {
      type = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # CORS configuration for web application access
  cors {
    origin          = var.allowed_origins
    method          = ["GET", "POST", "PUT", "DELETE"]
    response_header = ["Content-Type", "Authorization"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create service account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "conversational-ai-functions"
  display_name = "Conversational AI Cloud Functions Service Account"
  description  = "Service account for conversational AI Cloud Functions with access to Firestore, Storage, and Vertex AI"
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "function_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
}

# Create Cloud Function source code files
resource "local_file" "conversation_agent_code" {
  filename = "${path.module}/function_source/agent_config.py"
  content = templatefile("${path.module}/templates/agent_config.py.tpl", {
    project_id         = var.project_id
    region            = local.vertex_ai_region
    firestore_database = google_firestore_database.conversation_db.name
    bucket_name       = google_storage_bucket.conversation_artifacts.name
  })
}

resource "local_file" "main_function_code" {
  filename = "${path.module}/function_source/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id         = var.project_id
    region            = local.vertex_ai_region
    firestore_database = google_firestore_database.conversation_db.name
    bucket_name       = google_storage_bucket.conversation_artifacts.name
  })
}

resource "local_file" "requirements_txt" {
  filename = "${path.module}/function_source/requirements.txt"
  content  = file("${path.module}/templates/requirements.txt")
}

# Create ZIP archive for Cloud Function deployment
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"
  
  depends_on = [
    local_file.conversation_agent_code,
    local_file.main_function_code,
    local_file.requirements_txt
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.conversation_artifacts.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Deploy main conversation processing Cloud Function
resource "google_cloudfunctions2_function" "chat_processor" {
  name        = local.function_name
  location    = var.region
  description = "Main conversation processing function with Agent Development Kit"
  
  build_config {
    runtime     = "python310"
    entry_point = "chat_processor"
    
    source {
      storage_source {
        bucket = google_storage_bucket.conversation_artifacts.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.max_instances
    min_instance_count              = var.min_instances
    available_memory                = "${var.function_memory}M"
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 80
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID          = var.project_id
      REGION             = local.vertex_ai_region
      FIRESTORE_DATABASE = google_firestore_database.conversation_db.name
      BUCKET_NAME        = google_storage_bucket.conversation_artifacts.name
      ENVIRONMENT        = var.environment
    }
    
    service_account_email = google_service_account.function_service_account.email
    
    # Enable all traffic for public access (consider restricting in production)
    ingress_settings = "ALLOW_ALL"
    
    # Enable Cloud Function insights
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_firestore_user,
    google_project_iam_member.function_vertex_ai_user,
    google_project_iam_member.function_storage_admin
  ]
}

# Deploy conversation history retrieval Cloud Function
resource "google_cloudfunctions2_function" "chat_history" {
  name        = local.history_function_name
  location    = var.region
  description = "Conversation history retrieval function"
  
  build_config {
    runtime     = "python310"
    entry_point = "get_conversation_history"
    
    source {
      storage_source {
        bucket = google_storage_bucket.conversation_artifacts.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.max_instances
    min_instance_count              = var.min_instances
    available_memory                = "${var.history_function_memory}M"
    timeout_seconds                 = 30
    max_instance_request_concurrency = 100
    available_cpu                   = "1"
    
    environment_variables = {
      PROJECT_ID          = var.project_id
      REGION             = local.vertex_ai_region
      FIRESTORE_DATABASE = google_firestore_database.conversation_db.name
      BUCKET_NAME        = google_storage_bucket.conversation_artifacts.name
      ENVIRONMENT        = var.environment
    }
    
    service_account_email = google_service_account.function_service_account.email
    
    ingress_settings = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_firestore_user,
    google_project_iam_member.function_storage_admin
  ]
}

# Configure IAM for public access to Cloud Functions (adjust for production security)
resource "google_cloudfunctions2_function_iam_member" "chat_processor_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.chat_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "chat_history_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.chat_history.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create custom monitoring dashboard
resource "google_monitoring_dashboard" "conversation_ai_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  project        = var.project_id
  dashboard_json = templatefile("${path.module}/templates/monitoring_dashboard.json.tpl", {
    project_id = var.project_id
    region     = var.region
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.chat_processor,
    google_cloudfunctions2_function.chat_history
  ]
}

# Create notification channel for alerts (email-based)
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.enable_monitoring ? 1 : 0
  
  project      = var.project_id
  display_name = "Conversational AI Email Notifications"
  type         = "email"
  
  labels = {
    email_address = "admin@example.com"  # Replace with actual email
  }
  
  description = "Email notifications for conversational AI system alerts"
}

# Create alerting policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  project      = var.project_id
  display_name = "High Error Rate - Conversational AI Functions"
  combiner     = "OR"
  
  conditions {
    display_name = "Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${local.function_name}.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1  # 10% error rate
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email_notification[0].id]
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
}

# Create Secret Manager secret for storing sensitive configuration
resource "google_secret_manager_secret" "ai_config" {
  secret_id = "conversational-ai-config-${random_id.suffix.hex}"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Store default configuration in Secret Manager
resource "google_secret_manager_secret_version" "ai_config_version" {
  secret = google_secret_manager_secret.ai_config.id
  
  secret_data = jsonencode({
    gemini_model    = "gemini-pro"
    max_tokens      = 2048
    temperature     = 0.7
    conversation_limit = 50
  })
}

# Grant Cloud Functions access to secrets
resource "google_secret_manager_secret_iam_member" "function_secret_accessor" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.ai_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_service_account.email}"
}