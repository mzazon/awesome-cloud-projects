# Multi-Language Customer Support Automation with Cloud AI Services
# This Terraform configuration deploys a complete multilingual customer support system
# using Google Cloud AI services including Speech-to-Text, Translation, Natural Language,
# Text-to-Speech, Cloud Functions, and Workflows.

terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    application = "multilingual-customer-support"
    managed-by  = "terraform"
    cost-center = var.cost_center
  }

  # Unique resource names
  bucket_name      = "${var.project_id}-customer-support-${random_id.suffix.hex}"
  function_name    = "multilang-processor-${random_id.suffix.hex}"
  workflow_name    = "support-workflow-${random_id.suffix.hex}"
  service_account  = "ai-services-sa-${random_id.suffix.hex}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "speech.googleapis.com",           # Cloud Speech-to-Text API
    "translate.googleapis.com",        # Cloud Translation API
    "language.googleapis.com",         # Cloud Natural Language API
    "texttospeech.googleapis.com",     # Cloud Text-to-Speech API
    "cloudfunctions.googleapis.com",   # Cloud Functions API
    "workflows.googleapis.com",        # Cloud Workflows API
    "firestore.googleapis.com",        # Firestore API
    "storage.googleapis.com",          # Cloud Storage API
    "monitoring.googleapis.com",       # Cloud Monitoring API
    "logging.googleapis.com",          # Cloud Logging API
    "cloudbuild.googleapis.com",       # Cloud Build API (for function deployment)
    "eventarc.googleapis.com",         # Eventarc API (for event-driven functions)
    "run.googleapis.com",              # Cloud Run API (required for 2nd gen functions)
    "artifactregistry.googleapis.com", # Artifact Registry API
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental service disruption
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Service Account for AI Services
resource "google_service_account" "ai_services" {
  account_id   = local.service_account
  display_name = "AI Services Service Account"
  description  = "Service account for multilingual customer support AI services"

  depends_on = [google_project_service.required_apis]
}

# IAM permissions for the AI services service account
resource "google_project_iam_member" "ai_services_permissions" {
  for_each = toset([
    "roles/aiplatform.user",           # AI Platform access
    "roles/ml.serviceAgent",           # ML services access
    "roles/storage.objectAdmin",       # Cloud Storage access
    "roles/datastore.user",            # Firestore access
    "roles/cloudfunctions.invoker",    # Cloud Functions invoker
    "roles/workflows.invoker",         # Workflows invoker
    "roles/logging.logWriter",         # Cloud Logging write access
    "roles/monitoring.metricWriter",   # Cloud Monitoring write access
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ai_services.email}"

  depends_on = [google_service_account.ai_services]
}

# Firestore Database for conversation management
resource "google_firestore_database" "support_database" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_region
  type        = "FIRESTORE_NATIVE"

  # Enable features for production use
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = "DELETE_PROTECTION_ENABLED"

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for audio files and configurations
resource "google_storage_bucket" "customer_support_storage" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = var.force_destroy_bucket

  # Enable uniform bucket-level access for simplified security
  uniform_bucket_level_access = true

  # Configure versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 7
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # CORS configuration for web uploads
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-source"
  location      = var.region
  force_destroy = var.force_destroy_bucket

  uniform_bucket_level_access = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create configuration files for AI services
resource "google_storage_bucket_object" "speech_config" {
  name   = "config/speech-config.json"
  bucket = google_storage_bucket.customer_support_storage.name
  content = jsonencode({
    config = {
      encoding                = "WEBM_OPUS"
      sampleRateHertz        = 48000
      languageCode           = "en-US"
      alternativeLanguageCodes = var.supported_languages
      enableAutomaticPunctuation = true
      enableWordTimeOffsets     = true
      enableSpeakerDiarization  = true
      diarizationConfig = {
        enableSpeakerDiarization = true
        minSpeakerCount         = 1
        maxSpeakerCount         = 2
      }
      model = "latest_long"
    }
  })

  depends_on = [google_storage_bucket.customer_support_storage]
}

resource "google_storage_bucket_object" "translation_config" {
  name   = "config/translation-config.json"
  bucket = google_storage_bucket.customer_support_storage.name
  content = jsonencode({
    supportedLanguages = [
      for lang in var.supported_languages : {
        code = lang
        name = var.language_names[lang]
      }
    ]
    defaultTargetLanguage = "en"
    glossarySupport      = true
    model               = "nmt"
  })

  depends_on = [google_storage_bucket.customer_support_storage]
}

resource "google_storage_bucket_object" "sentiment_config" {
  name   = "config/sentiment-config.json"
  bucket = google_storage_bucket.customer_support_storage.name
  content = jsonencode({
    features = {
      sentiment       = true
      entities        = true
      entitySentiment = true
      syntax         = false
      classification = true
    }
    thresholds = {
      negative = -0.2
      positive = 0.2
      urgency  = -0.5
    }
    entityTypes = [
      "PERSON",
      "ORGANIZATION",
      "LOCATION",
      "EVENT",
      "WORK_OF_ART",
      "CONSUMER_GOOD"
    ]
  })

  depends_on = [google_storage_bucket.customer_support_storage]
}

resource "google_storage_bucket_object" "tts_config" {
  name   = "config/tts-config.json"
  bucket = google_storage_bucket.customer_support_storage.name
  content = jsonencode({
    voices = var.tts_voice_config
    audioConfig = {
      audioEncoding = "MP3"
      speakingRate  = 1.0
      pitch         = 0.0
      volumeGainDb  = 0.0
    }
  })

  depends_on = [google_storage_bucket.customer_support_storage]
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      bucket_name = google_storage_bucket.customer_support_storage.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_archive" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for AI service orchestration (2nd generation)
resource "google_cloudfunctions2_function" "multilang_processor" {
  name        = local.function_name
  location    = var.region
  description = "Processes customer audio through AI pipeline for multilingual support"

  build_config {
    runtime     = "python311"
    entry_point = "process_customer_audio"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_archive.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = "1Gi"
    timeout_seconds                  = 60
    max_instance_request_concurrency = 10
    available_cpu                    = "1"

    environment_variables = {
      BUCKET_NAME        = google_storage_bucket.customer_support_storage.name
      PROJECT_ID         = var.project_id
      FIRESTORE_DATABASE = google_firestore_database.support_database.name
    }

    service_account_email = google_service_account.ai_services.email

    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source_archive,
    google_project_iam_member.ai_services_permissions
  ]
}

# IAM policy to allow unauthenticated invocation of the function
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.multilang_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.multilang_processor]
}

# Cloud Workflows for complex support scenarios
resource "google_workflows_workflow" "support_orchestrator" {
  name   = local.workflow_name
  region = var.region

  description = "Orchestrates complex multilingual customer support scenarios"

  source_contents = templatefile("${path.module}/workflow.yaml", {
    project_id    = var.project_id
    region        = var.region
    function_name = google_cloudfunctions2_function.multilang_processor.name
  })

  service_account = google_service_account.ai_services.email

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.multilang_processor,
    google_project_iam_member.ai_services_permissions
  ]
}

# Cloud Monitoring - Alert Policy for High Error Rate
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "Multilingual Support Function - High Error Rate"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Function execution error rate"

    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = var.error_rate_threshold

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.function_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channels

  alert_strategy {
    auto_close = "86400s" # 24 hours
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.multilang_processor
  ]
}

# Cloud Monitoring - Alert Policy for High Negative Sentiment
resource "google_monitoring_alert_policy" "negative_sentiment" {
  display_name = "Multilingual Support - High Negative Sentiment"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High negative sentiment rate"

    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/user/sentiment_score\""
      duration       = "600s"
      comparison     = "COMPARISON_LT"
      threshold_value = -0.3

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_channels

  alert_strategy {
    auto_close = "3600s" # 1 hour
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.multilang_processor
  ]
}

# Log-based metric for sentiment tracking
resource "google_logging_metric" "sentiment_score" {
  name   = "sentiment_score_${random_id.suffix.hex}"
  filter = "resource.type=\"cloud_function\" AND jsonPayload.sentiment_score exists"

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Customer Sentiment Score"
  }

  value_extractor = "EXTRACT(jsonPayload.sentiment_score)"

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.multilang_processor
  ]
}

# Log-based metric for language detection tracking
resource "google_logging_metric" "language_detection" {
  name   = "language_detection_${random_id.suffix.hex}"
  filter = "resource.type=\"cloud_function\" AND jsonPayload.detected_language exists"

  metric_descriptor {
    metric_kind = "CUMULATIVE"
    value_type  = "INT64"
    display_name = "Language Detection Count"
  }

  label_extractors = {
    language = "EXTRACT(jsonPayload.detected_language)"
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.multilang_processor
  ]
}

# Cloud Monitoring Dashboard
resource "google_monitoring_dashboard" "multilingual_support" {
  dashboard_json = jsonencode({
    displayName = "Multilingual Customer Support Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Invocations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Sentiment Score Distribution"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/sentiment_score_${random_id.suffix.hex}\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "sentiment score"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Language Detection by Language"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/language_detection_${random_id.suffix.hex}\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["metric.label.language"]
                      }
                    }
                  }
                  plotType = "STACKED_BAR"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "detections/sec"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.sentiment_score,
    google_logging_metric.language_detection
  ]
}