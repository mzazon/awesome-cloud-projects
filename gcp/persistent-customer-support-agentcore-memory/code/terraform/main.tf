# Main Terraform configuration for GCP Persistent AI Customer Support
# with Agent Engine Memory using Vertex AI, Firestore, and Cloud Functions

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  
  # Function names with unique suffixes
  memory_function_name = "${var.resource_prefix}-memory-${local.resource_suffix}"
  chat_function_name   = "${var.resource_prefix}-chat-${local.resource_suffix}"
  
  # Service account name
  service_account_name = "${var.resource_prefix}-functions-sa-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    deployment_id = local.resource_suffix
    recipe_name   = "persistent-customer-support-agentcore-memory"
  })
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "cloudfunctions.googleapis.com",
    "firestore.googleapis.com",
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "storage.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create a dedicated service account for Cloud Functions
resource "google_service_account" "functions_sa" {
  count = var.create_service_account ? 1 : 0
  
  account_id   = local.service_account_name
  display_name = "AI Support Functions Service Account"
  description  = "Service account for AI Customer Support Cloud Functions"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for the service account to access required services
resource "google_project_iam_member" "functions_sa_roles" {
  for_each = var.create_service_account ? toset([
    "roles/firestore.user",           # Access to Firestore
    "roles/aiplatform.user",          # Access to Vertex AI
    "roles/logging.logWriter",        # Write logs
    "roles/monitoring.metricWriter",  # Write metrics
    "roles/cloudsql.client",         # If using Cloud SQL in future
    "roles/storage.objectViewer"      # Access to Cloud Storage for function source
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.functions_sa[0].email}"
  
  depends_on = [google_service_account.functions_sa]
}

# Create Firestore database for conversation memory storage
resource "google_firestore_database" "conversation_memory" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  # Prevent accidental deletion
  deletion_policy = "DELETE"
  
  depends_on = [google_project_service.required_apis]
}

# Create Firestore index for efficient conversation queries
resource "google_firestore_index" "conversation_queries" {
  project    = var.project_id
  database   = google_firestore_database.conversation_memory.name
  collection = "conversations"
  
  fields {
    field_path = "customer_id"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.conversation_memory]
}

# VPC Connector for Cloud Functions (optional)
resource "google_vpc_access_connector" "functions_connector" {
  count = var.enable_vpc_connector ? 1 : 0
  
  name          = var.vpc_connector_config.name
  project       = var.project_id
  region        = var.region
  ip_cidr_range = var.vpc_connector_config.ip_cidr_range
  network       = var.vpc_connector_config.network
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-${var.resource_prefix}-functions-${local.resource_suffix}"
  project  = var.project_id
  location = var.region
  
  # Enable versioning for function source code
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create memory retrieval function source archive
data "archive_file" "memory_function_source" {
  type        = "zip"
  output_path = "${path.module}/memory_function_source.zip"
  
  source {
    content = templatefile("${path.module}/functions/memory_retrieval/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/memory_retrieval/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload memory retrieval function source to Cloud Storage
resource "google_storage_bucket_object" "memory_function_source" {
  name   = "memory_function_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.memory_function_source.output_path
  
  depends_on = [data.archive_file.memory_function_source]
}

# Create chat function source archive
data "archive_file" "chat_function_source" {
  type        = "zip"
  output_path = "${path.module}/chat_function_source.zip"
  
  source {
    content = templatefile("${path.module}/functions/chat/main.py", {
      project_id            = var.project_id
      region               = var.region
      model_name           = var.vertex_ai_config.model_name
      max_output_tokens    = var.vertex_ai_config.max_output_tokens
      temperature          = var.vertex_ai_config.temperature
      top_p                = var.vertex_ai_config.top_p
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/chat/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload chat function source to Cloud Storage
resource "google_storage_bucket_object" "chat_function_source" {
  name   = "chat_function_source_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.chat_function_source.output_path
  
  depends_on = [data.archive_file.chat_function_source]
}

# Deploy memory retrieval Cloud Function
resource "google_cloudfunctions2_function" "memory_retrieval" {
  name        = local.memory_function_name
  project     = var.project_id
  location    = var.region
  description = "Retrieves conversation memory for customer context in AI support system"
  
  build_config {
    runtime     = var.memory_retrieval_function_config.runtime
    entry_point = var.memory_retrieval_function_config.entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.memory_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.memory_retrieval_function_config.max_instances
    min_instance_count               = var.memory_retrieval_function_config.min_instances
    available_memory                 = "${var.memory_retrieval_function_config.memory_mb}M"
    timeout_seconds                  = var.memory_retrieval_function_config.timeout_seconds
    max_instance_request_concurrency = 10
    available_cpu                    = var.memory_retrieval_function_config.available_cpu
    
    # Use dedicated service account if created
    service_account_email = var.create_service_account ? google_service_account.functions_sa[0].email : null
    
    # Environment variables
    environment_variables = {
      GCP_PROJECT    = var.project_id
      GCP_REGION     = var.region
      FIRESTORE_DB   = google_firestore_database.conversation_memory.name
      FUNCTION_ENV   = var.environment
    }
    
    # VPC connector if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = google_vpc_access_connector.functions_connector[0].id
      }
    }
    
    ingress_settings = var.memory_retrieval_function_config.ingress_settings
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.memory_function_source,
    google_firestore_database.conversation_memory
  ]
}

# Deploy AI chat Cloud Function
resource "google_cloudfunctions2_function" "ai_chat" {
  name        = local.chat_function_name
  project     = var.project_id
  location    = var.region
  description = "Main AI chat function with memory integration and Vertex AI"
  
  build_config {
    runtime     = var.chat_function_config.runtime
    entry_point = var.chat_function_config.entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.chat_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.chat_function_config.max_instances
    min_instance_count               = var.chat_function_config.min_instances
    available_memory                 = "${var.chat_function_config.memory_mb}M"
    timeout_seconds                  = var.chat_function_config.timeout_seconds
    max_instance_request_concurrency = 10
    available_cpu                    = var.chat_function_config.available_cpu
    
    # Use dedicated service account if created
    service_account_email = var.create_service_account ? google_service_account.functions_sa[0].email : null
    
    # Environment variables including memory function URL
    environment_variables = {
      GCP_PROJECT           = var.project_id
      GCP_REGION            = var.region
      FIRESTORE_DB          = google_firestore_database.conversation_memory.name
      RETRIEVE_MEMORY_URL   = google_cloudfunctions2_function.memory_retrieval.service_config[0].uri
      VERTEX_AI_MODEL       = var.vertex_ai_config.model_name
      MAX_OUTPUT_TOKENS     = var.vertex_ai_config.max_output_tokens
      TEMPERATURE           = var.vertex_ai_config.temperature
      TOP_P                 = var.vertex_ai_config.top_p
      FUNCTION_ENV          = var.environment
    }
    
    # VPC connector if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = google_vpc_access_connector.functions_connector[0].id
      }
    }
    
    ingress_settings = var.chat_function_config.ingress_settings
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.chat_function_source,
    google_cloudfunctions2_function.memory_retrieval,
    google_firestore_database.conversation_memory
  ]
}

# IAM policy to allow public access to memory retrieval function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "memory_function_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.memory_retrieval.name
  role           = "roles/run.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.memory_retrieval]
}

# IAM policy to allow public access to chat function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "chat_function_invoker" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.ai_chat.name
  role           = "roles/run.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.ai_chat]
}

# Allow memory function to be called by chat function
resource "google_cloudfunctions2_function_iam_member" "memory_function_chat_invoker" {
  count = var.create_service_account ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.memory_retrieval.name
  role           = "roles/run.invoker"
  member         = "serviceAccount:${google_service_account.functions_sa[0].email}"
  
  depends_on = [google_cloudfunctions2_function.memory_retrieval]
}

# Cloud Monitoring notification channels (optional)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "AI Support Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = "admin@example.com" # Change this to your email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "AI Support Function Errors"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.enable_monitoring ? [google_monitoring_notification_channel.email[0].id] : []
  
  depends_on = [google_project_service.required_apis]
}

# Output important resource information
output "summary" {
  description = "Deployment summary for AI Customer Support system"
  value = {
    project_id            = var.project_id
    region               = var.region
    deployment_id        = local.resource_suffix
    memory_function_name = google_cloudfunctions2_function.memory_retrieval.name
    chat_function_name   = google_cloudfunctions2_function.ai_chat.name
    firestore_database   = google_firestore_database.conversation_memory.name
    service_account      = var.create_service_account ? google_service_account.functions_sa[0].email : "default"
  }
}