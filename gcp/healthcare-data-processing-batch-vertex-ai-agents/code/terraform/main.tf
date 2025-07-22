# Healthcare Data Processing with Cloud Batch and Vertex AI Agents
# Terraform Infrastructure as Code
# This configuration deploys a complete healthcare data processing pipeline
# with HIPAA compliance, AI analysis, and FHIR-compliant data handling

terraform {
  required_version = ">= 1.5"
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "healthcare" {
  service = "healthcare.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "batch" {
  service = "batch.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "aiplatform" {
  service = "aiplatform.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "storage" {
  service = "storage.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "cloudfunctions" {
  service = "cloudfunctions.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "cloudbuild" {
  service = "cloudbuild.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "eventarc" {
  service = "eventarc.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "monitoring" {
  service = "monitoring.googleapis.com"
  
  disable_dependent_services = false
}

resource "google_project_service" "logging" {
  service = "logging.googleapis.com"
  
  disable_dependent_services = false
}

# HIPAA-compliant Cloud Storage bucket for healthcare data
resource "google_storage_bucket" "healthcare_data" {
  name          = "${var.healthcare_bucket_prefix}-${random_id.suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"
  
  # Enable versioning for data protection and compliance
  versioning {
    enabled = true
  }
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable audit logging for HIPAA compliance
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
      age = 2555 # 7 years for healthcare data retention
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    purpose     = "healthcare"
    environment = var.environment
    compliance  = "hipaa"
  }
  
  depends_on = [google_project_service.storage]
}

# Create a subdirectory for processing scripts
resource "google_storage_bucket_object" "scripts_folder" {
  name    = "scripts/"
  content = " "
  bucket  = google_storage_bucket.healthcare_data.name
}

# Healthcare dataset for FHIR-compliant data storage
resource "google_healthcare_dataset" "healthcare_dataset" {
  name     = "${var.healthcare_dataset_prefix}_${random_id.suffix.hex}"
  location = var.region
  
  labels = {
    purpose     = "healthcare"
    environment = var.environment
    compliance  = "hipaa"
  }
  
  depends_on = [google_project_service.healthcare]
}

# FHIR store for patient records with R4 compliance
resource "google_healthcare_fhir_store" "patient_records" {
  name    = "${var.fhir_store_prefix}_${random_id.suffix.hex}"
  dataset = google_healthcare_dataset.healthcare_dataset.id
  version = "R4"
  
  # Enable update and create operations
  enable_update_create = true
  
  # Enable history for audit trails
  enable_history_import = true
  
  # Configure notification for data changes
  notification_configs {
    pubsub_topic = google_pubsub_topic.fhir_notifications.id
  }
  
  labels = {
    purpose     = "patient-records"
    environment = var.environment
    compliance  = "hipaa"
  }
}

# Pub/Sub topic for FHIR store notifications
resource "google_pubsub_topic" "fhir_notifications" {
  name = "fhir-notifications-${random_id.suffix.hex}"
  
  labels = {
    purpose     = "healthcare-notifications"
    environment = var.environment
  }
}

# Service account for Vertex AI healthcare agent
resource "google_service_account" "healthcare_ai_agent" {
  account_id   = "healthcare-ai-agent-${random_id.suffix.hex}"
  display_name = "Healthcare AI Analysis Agent"
  description  = "Service account for AI-powered healthcare data analysis"
}

# IAM bindings for healthcare AI agent
resource "google_project_iam_member" "ai_agent_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.healthcare_ai_agent.email}"
}

resource "google_project_iam_member" "ai_agent_healthcare" {
  project = var.project_id
  role    = "roles/healthcare.fhirResourceEditor"
  member  = "serviceAccount:${google_service_account.healthcare_ai_agent.email}"
}

resource "google_project_iam_member" "ai_agent_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.healthcare_ai_agent.email}"
}

resource "google_project_iam_member" "ai_agent_batch" {
  project = var.project_id
  role    = "roles/batch.jobsEditor"
  member  = "serviceAccount:${google_service_account.healthcare_ai_agent.email}"
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "healthcare-function-${random_id.suffix.hex}"
  display_name = "Healthcare Processing Function"
  description  = "Service account for healthcare data processing function"
}

# IAM bindings for Cloud Function service account
resource "google_project_iam_member" "function_batch" {
  project = var.project_id
  role    = "roles/batch.jobsEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_healthcare" {
  project = var.project_id
  role    = "roles/healthcare.fhirResourceEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "healthcare-function-source-${random_id.suffix.hex}"
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = {
    purpose     = "function-source"
    environment = var.environment
  }
  
  depends_on = [google_project_service.storage]
}

# Create function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/healthcare_function_source.zip"
  source {
    content  = file("${path.module}/function_source/main.py")
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to storage
resource "google_storage_bucket_object" "function_source" {
  name   = "healthcare-function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for automated job triggering
resource "google_cloudfunctions2_function" "healthcare_processor" {
  name        = "healthcare-processor-trigger-${random_id.suffix.hex}"
  location    = var.region
  description = "Triggers healthcare data processing when files are uploaded"
  
  build_config {
    runtime     = "python311"
    entry_point = "trigger_healthcare_processing"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = 10
    min_instance_count               = 0
    available_memory                 = "512Mi"
    timeout_seconds                  = 540
    max_instance_request_concurrency = 1
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      FHIR_STORE = google_healthcare_fhir_store.patient_records.name
      DATASET_ID = google_healthcare_dataset.healthcare_dataset.name
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.healthcare_data.name
    }
  }
  
  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.eventarc
  ]
}

# Monitoring dashboard for healthcare processing
resource "google_monitoring_dashboard" "healthcare_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Healthcare Data Processing Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Batch Job Success Rate"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/num_tasks_completed\""
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
              gaugeView = {
                upperBound = 100.0
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Healthcare Processing Latency"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/task/completion_time\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "FHIR Store Operations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"healthcare_fhir_store\" AND metric.type=\"healthcare.googleapis.com/fhir_store/request_count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.monitoring]
}

# Alert policy for HIPAA compliance violations
resource "google_monitoring_alert_policy" "compliance_alert" {
  display_name = "Healthcare Compliance Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "HIPAA Compliance Violation"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/user/compliance_violation\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  documentation {
    content   = "Alert triggered when HIPAA compliance violations are detected in healthcare data processing"
    mime_type = "text/markdown"
  }
  
  depends_on = [google_project_service.monitoring]
}

# Alert policy for batch job failures
resource "google_monitoring_alert_policy" "batch_failure_alert" {
  display_name = "Batch Job Failure Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Batch Job Failed"
    
    condition_threshold {
      filter          = "resource.type=\"batch_job\" AND metric.type=\"batch.googleapis.com/job/num_tasks_failed\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
  
  alert_strategy {
    auto_close = "3600s"
  }
  
  documentation {
    content   = "Alert triggered when healthcare data processing batch jobs fail"
    mime_type = "text/markdown"
  }
  
  depends_on = [google_project_service.monitoring]
}

# BigQuery dataset for healthcare analytics (optional)
resource "google_bigquery_dataset" "healthcare_analytics" {
  dataset_id  = "healthcare_analytics_${random_id.suffix.hex}"
  location    = var.region
  description = "Dataset for healthcare data analytics and reporting"
  
  access {
    role          = "OWNER"
    user_by_email = google_service_account.healthcare_ai_agent.email
  }
  
  labels = {
    purpose     = "healthcare-analytics"
    environment = var.environment
    compliance  = "hipaa"
  }
}

# Log sink for healthcare audit logs
resource "google_logging_project_sink" "healthcare_audit_sink" {
  name        = "healthcare-audit-sink-${random_id.suffix.hex}"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.healthcare_analytics.dataset_id}"
  
  filter = <<EOF
    (resource.type="healthcare_dataset" OR 
     resource.type="healthcare_fhir_store" OR 
     resource.type="batch_job" OR
     resource.type="cloud_function") AND
    (protoPayload.methodName=~"healthcare" OR 
     protoPayload.methodName=~"batch" OR
     protoPayload.methodName=~"storage")
  EOF
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.logging]
}

# Grant BigQuery Data Editor role to the log sink service account
resource "google_project_iam_member" "audit_sink_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.healthcare_audit_sink.writer_identity
}

# Security: IAM binding to restrict bucket access
resource "google_storage_bucket_iam_member" "healthcare_bucket_viewer" {
  bucket = google_storage_bucket.healthcare_data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.healthcare_ai_agent.email}"
}

# Security: IAM binding for function bucket access
resource "google_storage_bucket_iam_member" "function_bucket_viewer" {
  bucket = google_storage_bucket.healthcare_data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}