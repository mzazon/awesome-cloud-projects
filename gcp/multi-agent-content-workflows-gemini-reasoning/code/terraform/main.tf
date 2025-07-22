# =============================================================================
# GCP Multi-Agent Content Workflows with Gemini 2.5 Reasoning
# =============================================================================
# This Terraform configuration deploys a complete multi-agent content
# processing pipeline using Gemini 2.5's advanced reasoning capabilities,
# Cloud Workflows for orchestration, and specialized AI services.
# =============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.4"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Provider Configuration
# -----------------------------------------------------------------------------
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Random Resources for Unique Naming
# -----------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 3
}

# Local Values for Resource Naming and Configuration
# -----------------------------------------------------------------------------
locals {
  # Resource naming with random suffix for uniqueness
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.project_id}-content-intelligence-${local.resource_suffix}"
  workflow_name   = "content-analysis-workflow-${local.resource_suffix}"
  function_name   = "content-trigger-${local.resource_suffix}"
  
  # Service configurations
  services_to_enable = [
    "aiplatform.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "speech.googleapis.com",
    "vision.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
  
  # IAM roles for the content intelligence service account
  service_account_roles = [
    "roles/aiplatform.user",
    "roles/workflows.invoker",
    "roles/storage.objectAdmin",
    "roles/speech.editor",
    "roles/vision.editor",
    "roles/cloudfunctions.invoker",
    "roles/eventarc.eventReceiver"
  ]
  
  # Content processing configuration
  gemini_config = {
    reasoning_config = {
      temperature         = 0.1
      top_p              = 0.9
      max_output_tokens  = 4096
      reasoning_depth    = "comprehensive"
      cross_modal_analysis = true
      confidence_threshold = 0.8
    }
    agent_configs = {
      text_agent = {
        temperature   = 0.2
        focus_areas   = ["sentiment", "entities", "themes", "quality"]
        output_format = "structured"
      }
      image_agent = {
        temperature      = 0.3
        vision_features  = ["labels", "text", "objects", "safe_search"]
        enhancement_level = "detailed"
      }
      video_agent = {
        temperature = 0.3
        audio_config = {
          enable_punctuation    = true
          enable_word_timestamps = true
          language_code        = "en-US"
        }
      }
    }
    synthesis_rules = {
      conflict_resolution    = "reasoning_based"
      confidence_weighting   = true
      cross_modal_validation = true
      business_focus        = true
    }
  }
}

# Enable Required Google Cloud APIs
# -----------------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset(local.services_to_enable)
  
  service            = each.value
  disable_on_destroy = false
  
  timeouts {
    create = "30m"
    update = "20m"
  }
}

# Cloud Storage Bucket for Content Processing
# -----------------------------------------------------------------------------
resource "google_storage_bucket" "content_bucket" {
  name     = local.bucket_name
  location = var.region
  
  # Storage configuration for multi-modal content
  storage_class = "STANDARD"
  
  # Versioning for content management
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass" 
      storage_class = "COLDLINE"
    }
  }
  
  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Labels for resource management
  labels = var.labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Storage Buckets for Different Content Types
# -----------------------------------------------------------------------------
resource "google_storage_bucket_object" "content_directories" {
  for_each = toset(["input/", "results/", "config/", "sample-content/"])
  
  name   = each.value
  bucket = google_storage_bucket.content_bucket.name
  source = "/dev/null"
}

# Service Account for Multi-Agent Workflow
# -----------------------------------------------------------------------------
resource "google_service_account" "content_intelligence_sa" {
  account_id   = "content-intelligence-sa-${local.resource_suffix}"
  display_name = "Content Intelligence Workflow Service Account"
  description  = "Service account for multi-agent content analysis workflows"
}

# IAM Bindings for Service Account
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "content_intelligence_roles" {
  for_each = toset(local.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.content_intelligence_sa.email}"
  
  depends_on = [google_service_account.content_intelligence_sa]
}

# Storage bucket IAM for service account
resource "google_storage_bucket_iam_member" "content_bucket_access" {
  bucket = google_storage_bucket.content_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.content_intelligence_sa.email}"
}

# Gemini Configuration Storage
# -----------------------------------------------------------------------------
resource "google_storage_bucket_object" "gemini_config" {
  name   = "config/gemini-config.json"
  bucket = google_storage_bucket.content_bucket.name
  content = jsonencode(local.gemini_config)
  
  # Content type for JSON configuration
  content_type = "application/json"
}

# Cloud Workflows Definition
# -----------------------------------------------------------------------------
resource "google_workflows_workflow" "content_analysis_workflow" {
  name            = local.workflow_name
  region          = var.region
  description     = "Multi-agent content analysis workflow with Gemini 2.5 reasoning"
  service_account = google_service_account.content_intelligence_sa.email
  
  # Workflow definition in YAML format
  source_contents = templatefile("${path.module}/workflow-definition.yaml", {
    project_id   = var.project_id
    region      = var.region
    bucket_name = google_storage_bucket.content_bucket.name
  })
  
  labels = var.labels
  
  depends_on = [
    google_project_service.apis,
    google_service_account.content_intelligence_sa,
    google_project_iam_member.content_intelligence_roles
  ]
}

# Cloud Function Source Code Archive
# -----------------------------------------------------------------------------
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id    = var.project_id
      region       = var.region
      workflow_name = google_workflows_workflow.content_analysis_workflow.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage Bucket for Function Source
# -----------------------------------------------------------------------------
resource "google_storage_bucket" "function_source_bucket" {
  name     = "${var.project_id}-function-source-${local.resource_suffix}"
  location = var.region
  
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = var.labels
  
  depends_on = [google_project_service.apis]
}

# Upload Function Source to Storage
# -----------------------------------------------------------------------------
resource "google_storage_bucket_object" "function_source_archive" {
  name   = "content-trigger-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function Trigger for Content Processing
# -----------------------------------------------------------------------------
resource "google_cloudfunctions2_function" "content_trigger" {
  name        = local.function_name
  location    = var.region
  description = "Triggers multi-agent content analysis workflow on storage events"
  
  build_config {
    runtime     = "python311"
    entry_point = "trigger_content_analysis"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source_archive.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.function_config.max_instances
    min_instance_count    = var.function_config.min_instances
    available_memory      = var.function_config.memory
    timeout_seconds       = var.function_config.timeout
    service_account_email = google_service_account.content_intelligence_sa.email
    
    environment_variables = {
      WORKFLOW_NAME    = google_workflows_workflow.content_analysis_workflow.name
      GCP_PROJECT     = var.project_id
      FUNCTION_REGION = var.region
      BUCKET_NAME     = google_storage_bucket.content_bucket.name
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.content_bucket.name
    }
    
    service_account_email = google_service_account.content_intelligence_sa.email
  }
  
  labels = var.labels
  
  depends_on = [
    google_project_service.apis,
    google_workflows_workflow.content_analysis_workflow,
    google_storage_bucket_object.function_source_archive
  ]
}

# IAM for Cloud Function Invocation
# -----------------------------------------------------------------------------
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.content_trigger.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.content_intelligence_sa.email}"
}

# Pub/Sub Topic for Workflow Notifications (Optional)
# -----------------------------------------------------------------------------
resource "google_pubsub_topic" "workflow_notifications" {
  name = "content-workflow-notifications-${local.resource_suffix}"
  
  labels = var.labels
  
  depends_on = [google_project_service.apis]
}

# Pub/Sub Subscription for Workflow Monitoring
# -----------------------------------------------------------------------------
resource "google_pubsub_subscription" "workflow_monitoring" {
  name  = "content-workflow-monitoring-${local.resource_suffix}"
  topic = google_pubsub_topic.workflow_notifications.name
  
  # Message retention for 7 days
  message_retention_duration = "604800s"
  
  # Acknowledge deadline
  ack_deadline_seconds = 20
  
  # Dead letter policy for failed processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.workflow_notifications.id
    max_delivery_attempts = 5
  }
  
  labels = var.labels
}

# Cloud Monitoring Alert Policy for Workflow Failures
# -----------------------------------------------------------------------------
resource "google_monitoring_alert_policy" "workflow_failures" {
  display_name = "Content Workflow Failures - ${local.resource_suffix}"
  combiner     = "OR"
  enabled      = var.monitoring_config.enable_alerts
  
  conditions {
    display_name = "Workflow execution failures"
    
    condition_threshold {
      filter          = "resource.type=\"workflows.googleapis.com/Workflow\" AND resource.label.workflow_id=\"${google_workflows_workflow.content_analysis_workflow.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  # Notification channels would be configured separately
  notification_channels = var.monitoring_config.notification_channels
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.apis]
}

# Data Loss Prevention Template (Optional)
# -----------------------------------------------------------------------------
resource "google_data_loss_prevention_inspect_template" "content_inspection" {
  count = var.enable_dlp ? 1 : 0
  
  parent       = "projects/${var.project_id}"
  description  = "DLP template for content intelligence processing"
  display_name = "Content Intelligence DLP Template"
  
  inspect_config {
    info_types {
      name = "EMAIL_ADDRESS"
    }
    info_types {
      name = "PHONE_NUMBER"
    }
    info_types {
      name = "CREDIT_CARD_NUMBER"
    }
    info_types {
      name = "US_SOCIAL_SECURITY_NUMBER"
    }
    
    min_likelihood = "POSSIBLE"
    
    limits {
      max_findings_per_item    = 100
      max_findings_per_request = 1000
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Sample Content for Testing (Optional)
# -----------------------------------------------------------------------------
resource "google_storage_bucket_object" "sample_text_content" {
  count = var.create_sample_content ? 1 : 0
  
  name   = "sample-content/sample-business-document.txt"
  bucket = google_storage_bucket.content_bucket.name
  content = <<-EOT
    Sample Business Analysis Document
    
    Executive Summary:
    Our Q4 analysis reveals significant growth opportunities in AI-powered customer service solutions.
    The market research indicates a 40% annual growth rate with total addressable market of $2.5B.
    
    Key Findings:
    - Customer satisfaction increased by 25% with AI implementation
    - Response times improved from 4 hours to 15 minutes average
    - Cost reduction of 30% in customer service operations
    
    Recommendations:
    1. Expand AI chatbot capabilities to handle complex inquiries
    2. Integrate sentiment analysis for proactive customer engagement
    3. Implement predictive analytics for customer churn prevention
    
    Next Steps:
    - Pilot program launch in Q1 2025
    - Budget allocation of $500K for initial deployment
    - Partnership evaluation with leading AI vendors
  EOT
  
  content_type = "text/plain"
  
  depends_on = [google_storage_bucket.content_bucket]
}

# Network Security (VPC and Firewall) - Optional Enhanced Configuration
# -----------------------------------------------------------------------------
resource "google_compute_network" "content_intelligence_vpc" {
  count = var.create_dedicated_network ? 1 : 0
  
  name                    = "content-intelligence-vpc-${local.resource_suffix}"
  auto_create_subnetworks = false
  description             = "Dedicated VPC for content intelligence workflows"
  
  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "content_intelligence_subnet" {
  count = var.create_dedicated_network ? 1 : 0
  
  name          = "content-intelligence-subnet-${local.resource_suffix}"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.content_intelligence_vpc[0].id
  
  # Enable private Google access for API calls
  private_ip_google_access = true
  
  # Secondary ranges for additional services if needed
  secondary_ip_range {
    range_name    = "services-range"
    ip_cidr_range = "10.1.0.0/24"
  }
}

# VPC Connector for Cloud Functions (if using dedicated VPC)
# -----------------------------------------------------------------------------
resource "google_vpc_access_connector" "content_intelligence_connector" {
  count = var.create_dedicated_network ? 1 : 0
  
  name          = "content-intel-connector-${local.resource_suffix}"
  ip_cidr_range = "10.2.0.0/28"
  network       = google_compute_network.content_intelligence_vpc[0].name
  region        = var.region
  
  # Performance settings
  min_throughput = 200
  max_throughput = 1000
  
  depends_on = [
    google_project_service.apis,
    google_compute_network.content_intelligence_vpc
  ]
}