# Content Syndication Platform - Main Infrastructure Configuration
# This Terraform configuration deploys a complete GCP-based content syndication platform
# featuring Hierarchical Namespace Storage, Agent Development Kit, and automated workflows

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct unique resource names
  bucket_name = var.content_bucket_name != "" ? var.content_bucket_name : "content-hns-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.tags, {
    environment = var.environment
    region      = var.region
    component   = "content-syndication"
  })
  
  # Service account names
  workflow_sa_name = "content-workflow-sa-${random_id.suffix.hex}"
  function_sa_name = "content-function-sa-${random_id.suffix.hex}"
  vertex_ai_sa_name = "vertex-ai-agent-sa-${random_id.suffix.hex}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",           # Cloud Storage for hierarchical namespace
    "aiplatform.googleapis.com",       # Vertex AI for Agent Development Kit
    "workflows.googleapis.com",        # Cloud Workflows for orchestration
    "cloudfunctions.googleapis.com",   # Cloud Functions for content processing
    "cloudresourcemanager.googleapis.com", # Resource management
    "iam.googleapis.com",             # Identity and Access Management
    "logging.googleapis.com",         # Cloud Logging
    "monitoring.googleapis.com",      # Cloud Monitoring
    "eventarc.googleapis.com",        # Eventarc for event-driven architecture
    "run.googleapis.com"              # Cloud Run (for 2nd gen functions)
  ])

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Hierarchical Namespace Storage Bucket for Content Syndication
# This bucket provides up to 8x higher initial QPS and file system-like operations
resource "google_storage_bucket" "content_syndication" {
  name          = local.bucket_name
  location      = var.storage_location
  project       = var.project_id
  force_destroy = var.environment != "prod" # Prevent accidental deletion in production

  # Enable Hierarchical Namespace - CRITICAL for content syndication performance
  hierarchical_namespace {
    enabled = true
  }

  # Required for HNS - provides consistent security model
  uniform_bucket_level_access = true

  # Storage class optimized for frequent access content processing
  storage_class = "STANDARD"

  # Enable versioning for content history and rollback capabilities
  versioning {
    enabled = true
  }

  # CORS configuration for web-based content distribution
  dynamic "cors" {
    for_each = var.enable_cors ? [1] : []
    content {
      origin          = var.allowed_cors_origins
      method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
      response_header = ["*"]
      max_age_seconds = 3600
    }
  }

  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_content_lifecycle ? [1] : []
    content {
      condition {
        age = var.content_retention_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }

  # Archive old content after extended retention
  dynamic "lifecycle_rule" {
    for_each = var.enable_content_lifecycle ? [1] : []
    content {
      condition {
        age = var.content_retention_days * 3 # 3x retention period for archival
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }

  # Apply common labels
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create hierarchical folder structure for content pipeline
# These folders provide organized content flow and atomic operations
resource "google_storage_bucket_object" "content_folders" {
  for_each = toset([
    "incoming/",
    "processing/",
    "categorized/",
    "categorized/video/",
    "categorized/image/", 
    "categorized/audio/",
    "categorized/document/",
    "distributed/",
    "archive/",
    "rejected/"
  ])

  name    = each.key
  bucket  = google_storage_bucket.content_syndication.name
  content = " " # Placeholder content for folder creation

  depends_on = [google_storage_bucket.content_syndication]
}

# Service Account for Cloud Workflows
resource "google_service_account" "workflow_sa" {
  account_id   = local.workflow_sa_name
  display_name = "Content Syndication Workflow Service Account"
  description  = "Service account for orchestrating content syndication workflows"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service Account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = local.function_sa_name
  display_name = "Content Processing Function Service Account"
  description  = "Service account for content processing Cloud Functions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Service Account for Vertex AI Agent Development Kit
resource "google_service_account" "vertex_ai_sa" {
  count        = var.enable_vertex_ai ? 1 : 0
  account_id   = local.vertex_ai_sa_name
  display_name = "Vertex AI Content Agent Service Account"
  description  = "Service account for Vertex AI Agent Development Kit operations"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM Bindings for Workflow Service Account
resource "google_project_iam_member" "workflow_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",      # Full access to storage objects
    "roles/workflows.invoker",        # Invoke other workflows
    "roles/cloudfunctions.invoker",   # Invoke Cloud Functions
    "roles/aiplatform.user",         # Use Vertex AI services
    "roles/logging.logWriter"        # Write logs
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.workflow_sa.email}"
}

# IAM Bindings for Function Service Account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",      # Full access to storage objects
    "roles/aiplatform.user",         # Use Vertex AI services
    "roles/workflows.invoker",        # Invoke workflows
    "roles/logging.logWriter",        # Write logs
    "roles/monitoring.metricWriter"   # Write metrics
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM Bindings for Vertex AI Service Account
resource "google_project_iam_member" "vertex_ai_permissions" {
  for_each = var.enable_vertex_ai ? toset([
    "roles/aiplatform.user",          # Use Vertex AI services
    "roles/storage.objectViewer",     # Read storage objects
    "roles/logging.logWriter"         # Write logs
  ]) : toset([])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.vertex_ai_sa[0].email}"
}

# Vertex AI Endpoint for Agent Development Kit
resource "google_vertex_ai_endpoint" "content_agent" {
  count        = var.enable_vertex_ai ? 1 : 0
  name         = "content-syndication-agent-${random_id.suffix.hex}"
  display_name = "Content Syndication Agent Endpoint"
  description  = "Vertex AI endpoint for content analysis and routing agents"
  location     = var.vertex_ai_location
  project      = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Source bucket for Cloud Function deployment
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-function-source-${random_id.suffix.hex}"
  location                    = var.storage_location
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = merge(local.common_labels, {
    purpose = "function-source"
  })

  depends_on = [google_project_service.required_apis]
}

# Create function source code files from templates
resource "local_file" "function_main_py" {
  filename = "${path.module}/function_code/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id  = var.project_id
    bucket_name = google_storage_bucket.content_syndication.name
  })
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/function_code/requirements.txt"
  content  = file("${path.module}/templates/requirements.txt")
}

# Archive the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/content-processor.zip"
  
  source {
    content  = local_file.function_main_py.content
    filename = "main.py"
  }
  
  source {
    content  = local_file.function_requirements.content
    filename = "requirements.txt"
  }
  
  depends_on = [
    local_file.function_main_py,
    local_file.function_requirements
  ]
}

# Upload function source to bucket
resource "google_storage_bucket_object" "function_zip" {
  name   = "content-processor-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [google_storage_bucket.function_source]
}

# Cloud Function for Content Processing
resource "google_cloudfunctions2_function" "content_processor" {
  name        = "content-processor-${random_id.suffix.hex}"
  location    = var.region
  description = "Content processing function for syndication platform"
  project     = var.project_id

  build_config {
    runtime     = "python311"
    entry_point = "process_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
    
    environment_variables = {
      BUILD_ENV = var.environment
    }
  }

  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = 0
    available_memory   = var.function_memory
    available_cpu      = "1"
    timeout_seconds    = var.function_timeout

    environment_variables = {
      STORAGE_BUCKET       = google_storage_bucket.content_syndication.name
      PROJECT_ID           = var.project_id
      ENVIRONMENT          = var.environment
      VERTEX_AI_LOCATION   = var.vertex_ai_location
      QUALITY_THRESHOLD    = var.quality_thresholds.minimum_score
      ENABLE_AUTO_APPROVAL = var.quality_thresholds.enable_auto_approval
    }

    service_account_email = google_service_account.function_sa.email

    # Security configuration
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }

  # Event trigger for storage object creation
  event_trigger {
    event_type            = "google.cloud.storage.object.v1.finalized"
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email

    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.content_syndication.name
    }

    event_filters {
      attribute = "name"
      value     = "incoming/*"
      operator  = "match-path-pattern"
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_zip
  ]
}

# Cloud Workflow for Content Syndication Orchestration
resource "google_workflows_workflow" "content_syndication" {
  name            = "content-syndication-workflow-${random_id.suffix.hex}"
  project         = var.project_id
  region          = var.region
  description     = "Orchestrates content syndication pipeline with AI-driven routing"
  service_account = google_service_account.workflow_sa.id

  # Logging and monitoring configuration
  call_log_level = var.workflow_call_log_level

  # Environment variables for workflow
  user_env_vars = {
    STORAGE_BUCKET     = google_storage_bucket.content_syndication.name
    PROJECT_ID         = var.project_id
    FUNCTION_URL       = google_cloudfunctions2_function.content_processor.url
    VERTEX_AI_LOCATION = var.vertex_ai_location
    ENVIRONMENT        = var.environment
  }

  labels = local.common_labels

  # Workflow definition for content syndication pipeline
  source_contents = local_file.workflow_definition.content

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.content_processor,
    local_file.workflow_definition
  ]
}

# Monitoring Dashboard for Content Syndication Platform
resource "google_monitoring_dashboard" "content_syndication" {
  count          = var.enable_monitoring ? 1 : 0
  dashboard_json = jsonencode({
    displayName = "Content Syndication Platform - ${var.environment}"
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Storage Bucket Operations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" resource.label.bucket_name=\"${google_storage_bucket.content_syndication.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Executions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" resource.label.function_name=\"${google_cloudfunctions2_function.content_processor.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Create workflow definition file from template
resource "local_file" "workflow_definition" {
  filename = "${path.module}/workflow_definition.yaml"
  content = templatefile("${path.module}/templates/workflow.yaml.tpl", {
    function_url       = google_cloudfunctions2_function.content_processor.url
    vertex_ai_location = var.vertex_ai_location
    project_id         = var.project_id
    bucket_name        = google_storage_bucket.content_syndication.name
  })
}