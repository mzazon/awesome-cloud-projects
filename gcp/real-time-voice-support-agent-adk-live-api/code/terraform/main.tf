# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention with random suffix
  name_prefix = "${var.voice_agent_name}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    component = "voice-support-agent"
    version   = "1.0"
  })
  
  # Required Google Cloud APIs for the voice support agent
  required_apis = [
    "aiplatform.googleapis.com",      # Vertex AI for Gemini Live API
    "cloudfunctions.googleapis.com",  # Cloud Functions for serverless deployment
    "cloudbuild.googleapis.com",      # Cloud Build for function deployment
    "logging.googleapis.com",         # Cloud Logging for application logs
    "monitoring.googleapis.com",      # Cloud Monitoring for metrics
    "speech.googleapis.com",          # Speech-to-Text API
    "texttospeech.googleapis.com",    # Text-to-Speech API
    "cloudresourcemanager.googleapis.com" # Resource Manager API
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "voice_agent_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying terraform
  disable_dependent_services = false
  disable_on_destroy         = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for the voice support agent
resource "google_service_account" "voice_agent_sa" {
  account_id   = "${local.name_prefix}-sa"
  display_name = "Voice Support Agent Service Account"
  description  = "Service account for Voice Support Agent with ADK and Gemini Live API access"
  project      = var.project_id
  
  depends_on = [google_project_service.voice_agent_apis]
}

# Grant Vertex AI User role to service account for Gemini Live API access
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.voice_agent_sa.email}"
  
  depends_on = [google_service_account.voice_agent_sa]
}

# Grant Cloud Functions Invoker role for function execution
resource "google_project_iam_member" "functions_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.voice_agent_sa.email}"
  
  depends_on = [google_service_account.voice_agent_sa]
}

# Grant Logging Writer role for application logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.voice_agent_sa.email}"
  
  depends_on = [google_service_account.voice_agent_sa]
}

# Grant Monitoring Metric Writer role for custom metrics
resource "google_project_iam_member" "monitoring_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.voice_agent_sa.email}"
  
  depends_on = [google_service_account.voice_agent_sa]
}

# Grant Cloud Trace Agent role for distributed tracing
resource "google_project_iam_member" "trace_agent" {
  count = var.enable_tracing ? 1 : 0
  
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.voice_agent_sa.email}"
  
  depends_on = [google_service_account.voice_agent_sa]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source"
  location = var.region
  project  = var.project_id
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Configure versioning for source code history
  versioning {
    enabled = true
  }
  
  # Lifecycle rules to manage storage costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.voice_agent_apis]
}

# Create source code archive for Cloud Function
data "archive_file" "voice_agent_source" {
  type        = "zip"
  output_path = "/tmp/voice-agent-source.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id          = var.project_id
      region              = var.region
      gemini_model        = var.gemini_model
      voice_name          = var.voice_name
      language_code       = var.language_code
      log_level           = var.log_level
      customer_db_enabled = var.customer_database_enabled
      knowledge_enabled   = var.knowledge_base_enabled
      ticket_enabled      = var.ticket_system_enabled
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_source/voice_agent.py", {
      gemini_model  = var.gemini_model
      voice_name    = var.voice_name
      language_code = var.language_code
    })
    filename = "agent_src/voice_agent.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
  
  source {
    content = ""
    filename = "agent_src/__init__.py"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "voice_agent_source" {
  name   = "voice-agent-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.voice_agent_source.output_path
  
  # Ensure source is re-uploaded if it changes
  source_hash = data.archive_file.voice_agent_source.output_base64sha256
}

# Deploy the Voice Support Agent Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "voice_support_agent" {
  name     = local.name_prefix
  location = var.region
  project  = var.project_id
  
  description = "Real-time voice support agent using ADK and Gemini Live API"
  
  build_config {
    runtime     = "python312"
    entry_point = "voice_support_endpoint"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.voice_agent_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      GOOGLE_FUNCTION_TARGET = "voice_support_endpoint"
    }
  }
  
  service_config {
    max_instance_count = var.max_instances
    min_instance_count = var.min_instances
    
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    
    # Configure service account for secure API access
    service_account_email = google_service_account.voice_agent_sa.email
    
    # Environment variables for runtime
    environment_variables = {
      PROJECT_ID              = var.project_id
      REGION                  = var.region
      VERTEX_AI_LOCATION      = var.vertex_ai_location
      GEMINI_MODEL           = var.gemini_model
      VOICE_NAME             = var.voice_name
      LANGUAGE_CODE          = var.language_code
      LOG_LEVEL              = var.log_level
      CUSTOMER_DATABASE_ENABLED = tostring(var.customer_database_enabled)
      KNOWLEDGE_BASE_ENABLED    = tostring(var.knowledge_base_enabled)
      TICKET_SYSTEM_ENABLED     = tostring(var.ticket_system_enabled)
      ENABLE_MONITORING         = tostring(var.enable_monitoring)
      ENABLE_TRACING           = tostring(var.enable_tracing)
    }
    
    # Configure ingress for external access
    ingress_settings = "ALLOW_ALL"
    
    # Configure VPC connector if needed (optional)
    # vpc_connector = var.vpc_connector_name
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.voice_agent_apis,
    google_service_account.voice_agent_sa,
    google_storage_bucket_object.voice_agent_source
  ]
}

# Create IAM policy for unauthenticated access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.voice_support_agent.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create custom monitoring dashboard for voice agent metrics
resource "google_monitoring_dashboard" "voice_agent_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Voice Support Agent Monitoring"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Invocations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.voice_support_agent.name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Duration"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.voice_support_agent.name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Error Rate"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.voice_support_agent.name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields = ["metric.labels.status"]
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
  
  project = var.project_id
  
  depends_on = [
    google_cloudfunctions2_function.voice_support_agent,
    google_project_service.voice_agent_apis
  ]
}

# Create log-based metrics for custom monitoring
resource "google_logging_metric" "voice_agent_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${local.name_prefix}-errors"
  project = var.project_id
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.voice_support_agent.name}\" AND severity>=ERROR"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Voice Agent Error Count"
  }
  
  label_extractors = {
    severity = "EXTRACT(severity)"
  }
}

# Create alerting policy for high error rates
resource "google_monitoring_alert_policy" "voice_agent_error_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Voice Agent High Error Rate"
  project      = var.project_id
  
  combiner = "OR"
  
  conditions {
    display_name = "Error rate condition"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.voice_support_agent.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_cloudfunctions2_function.voice_support_agent]
}

# Create test client configuration files
resource "local_file" "voice_test_html" {
  content = templatefile("${path.module}/templates/voice_test.html.tpl", {
    function_url = google_cloudfunctions2_function.voice_support_agent.service_config[0].uri
    agent_name   = var.voice_agent_name
  })
  filename = "${path.root}/voice_test.html"
  
  depends_on = [google_cloudfunctions2_function.voice_support_agent]
}

# Output configuration for client applications
resource "local_file" "agent_config" {
  content = jsonencode({
    agent_url           = google_cloudfunctions2_function.voice_support_agent.service_config[0].uri
    project_id          = var.project_id
    region              = var.region
    voice_name          = var.voice_name
    language_code       = var.language_code
    gemini_model        = var.gemini_model
    service_account     = google_service_account.voice_agent_sa.email
    monitoring_enabled  = var.enable_monitoring
    tracing_enabled     = var.enable_tracing
  })
  filename = "${path.root}/voice_agent_config.json"
  
  depends_on = [google_cloudfunctions2_function.voice_support_agent]
}