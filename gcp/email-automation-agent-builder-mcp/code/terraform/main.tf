# GCP Email Automation with Vertex AI Agent Builder and MCP
# This Terraform configuration deploys a complete email automation system
# using Vertex AI Agent Builder, Gmail API, Cloud Functions, and Pub/Sub

# Configure the Google Cloud provider
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = random_id.suffix.hex
  
  # List of required APIs for the email automation system
  required_apis = [
    "aiplatform.googleapis.com",
    "cloudfunctions.googleapis.com",
    "gmail.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for email automation
resource "google_service_account" "email_automation" {
  account_id   = "email-automation-sa-${local.resource_suffix}"
  display_name = "Email Automation Service Account"
  description  = "Service account for email automation system"
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "email_automation_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudfunctions.invoker",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.email_automation.email}"
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-email-automation-functions-${local.resource_suffix}"
  location = var.region
  
  versioning {
    enabled = true
  }
  
  uniform_bucket_level_access = true
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 30
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for Gmail notifications
resource "google_pubsub_topic" "gmail_notifications" {
  name = "gmail-notifications-${local.resource_suffix}"
  
  labels = {
    environment = var.environment
    service     = "email-automation"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Gmail webhook
resource "google_pubsub_subscription" "gmail_webhook" {
  name  = "gmail-webhook-sub-${local.resource_suffix}"
  topic = google_pubsub_topic.gmail_notifications.name
  
  push_config {
    push_endpoint = "https://${var.region}-${var.project_id}.cloudfunctions.net/gmail-webhook-${local.resource_suffix}"
    
    attributes = {
      x-goog-version = "v1"
    }
  }
  
  ack_deadline_seconds = 300
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  depends_on = [google_cloud_functions2_function.gmail_webhook]
}

# Grant Gmail API service account permission to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  topic  = google_pubsub_topic.gmail_notifications.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}

# Create Cloud Function source archives
data "archive_file" "gmail_webhook_source" {
  type        = "zip"
  output_path = "${path.module}/gmail-webhook-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/gmail_webhook.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "mcp_integration_source" {
  type        = "zip"
  output_path = "${path.module}/mcp-integration-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/mcp_integration.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "response_generator_source" {
  type        = "zip"
  output_path = "${path.module}/response-generator-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/response_generator.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "email_workflow_source" {
  type        = "zip"
  output_path = "${path.module}/email-workflow-source.zip"
  
  source {
    content = templatefile("${path.module}/templates/email_workflow.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "gmail_webhook_source" {
  name   = "sources/gmail-webhook-${data.archive_file.gmail_webhook_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.gmail_webhook_source.output_path
}

resource "google_storage_bucket_object" "mcp_integration_source" {
  name   = "sources/mcp-integration-${data.archive_file.mcp_integration_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.mcp_integration_source.output_path
}

resource "google_storage_bucket_object" "response_generator_source" {
  name   = "sources/response-generator-${data.archive_file.response_generator_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.response_generator_source.output_path
}

resource "google_storage_bucket_object" "email_workflow_source" {
  name   = "sources/email-workflow-${data.archive_file.email_workflow_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.email_workflow_source.output_path
}

# Cloud Function for Gmail webhook processing
resource "google_cloud_functions2_function" "gmail_webhook" {
  name     = "gmail-webhook-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "gmail_webhook"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.gmail_webhook_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
    
    service_account_email = google_service_account.email_automation.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.gmail_webhook_source
  ]
}

# Cloud Function for MCP integration
resource "google_cloud_functions2_function" "mcp_integration" {
  name     = "mcp-integration-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "mcp_handler"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.mcp_integration_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 30
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
    
    service_account_email = google_service_account.email_automation.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.mcp_integration_source
  ]
}

# Cloud Function for response generation
resource "google_cloud_functions2_function" "response_generator" {
  name     = "response-generator-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_response"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.response_generator_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
    }
    
    service_account_email = google_service_account.email_automation.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.response_generator_source
  ]
}

# Cloud Function for email workflow orchestration
resource "google_cloud_functions2_function" "email_workflow" {
  name     = "email-workflow-${local.resource_suffix}"
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "email_workflow"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.email_workflow_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "1Gi"
    timeout_seconds                  = 120
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
    
    service_account_email = google_service_account.email_automation.email
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.email_workflow_source
  ]
}

# Allow unauthenticated invocations for webhook functions
resource "google_cloud_functions2_function_iam_member" "gmail_webhook_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloud_functions2_function.gmail_webhook.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloud_functions2_function_iam_member" "mcp_integration_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloud_functions2_function.mcp_integration.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloud_functions2_function_iam_member" "response_generator_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloud_functions2_function.response_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloud_functions2_function_iam_member" "email_workflow_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloud_functions2_function.email_workflow.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create a log sink for email automation monitoring
resource "google_logging_project_sink" "email_automation_sink" {
  name = "email-automation-sink-${local.resource_suffix}"
  
  # Export logs to Cloud Storage for analysis
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}/logs"
  
  # Filter for email automation related logs
  filter = <<-EOT
    resource.type="cloud_function"
    AND (
      resource.labels.function_name="${google_cloud_functions2_function.gmail_webhook.name}"
      OR resource.labels.function_name="${google_cloud_functions2_function.mcp_integration.name}"
      OR resource.labels.function_name="${google_cloud_functions2_function.response_generator.name}"
      OR resource.labels.function_name="${google_cloud_functions2_function.email_workflow.name}"
    )
  EOT
  
  unique_writer_identity = true
}

# Grant log sink write permissions to the storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.email_automation_sink.writer_identity
}

# Create MCP server configuration as a Secret Manager secret
resource "google_secret_manager_secret" "mcp_config" {
  secret_id = "mcp-server-config-${local.resource_suffix}"
  
  replication {
    auto {}
  }
  
  labels = {
    environment = var.environment
    service     = "email-automation"
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "mcp_config" {
  secret = google_secret_manager_secret.mcp_config.id
  
  secret_data = jsonencode({
    name         = "email-automation-mcp"
    version      = "1.0.0"
    description  = "MCP server for email automation context"
    capabilities = {
      resources = true
      tools     = true
    }
    tools = [
      {
        name        = "get_customer_info"
        description = "Retrieve customer information from CRM"
        inputSchema = {
          type = "object"
          properties = {
            email       = { type = "string" }
            customer_id = { type = "string" }
          }
        }
      },
      {
        name        = "search_knowledge_base"
        description = "Search internal knowledge base"
        inputSchema = {
          type = "object"
          properties = {
            query    = { type = "string" }
            category = { type = "string" }
          }
        }
      }
    ]
  })
}

# Grant the service account access to the MCP configuration secret
resource "google_secret_manager_secret_iam_member" "mcp_config_accessor" {
  secret_id = google_secret_manager_secret.mcp_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.email_automation.email}"
}