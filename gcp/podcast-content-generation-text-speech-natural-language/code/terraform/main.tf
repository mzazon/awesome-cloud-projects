# Main Terraform configuration for GCP Podcast Content Generation System
# This infrastructure deploys a complete podcast generation pipeline using
# Google Cloud Text-to-Speech, Natural Language API, Cloud Storage, and Cloud Functions

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.bucket_name_prefix}-${local.resource_suffix}"
  
  # Common labels to apply to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    project     = var.project_id
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "enabled_apis" {
  for_each = toset(var.api_services)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create service account for podcast generation with least privilege access
resource "google_service_account" "podcast_generator" {
  account_id   = var.service_account_name
  display_name = "Podcast Content Generator"
  description  = "Service account for Text-to-Speech and Natural Language API access"
  project      = var.project_id
  
  depends_on = [google_project_service.enabled_apis]
}

# Service account key for authentication
resource "google_service_account_key" "podcast_generator_key" {
  service_account_id = google_service_account.podcast_generator.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# IAM roles for the service account
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.podcast_generator.email}"
}

resource "google_project_iam_member" "ml_developer" {
  project = var.project_id
  role    = "roles/ml.developer"
  member  = "serviceAccount:${google_service_account.podcast_generator.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.podcast_generator.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.podcast_generator.email}"
}

# Cloud Storage bucket for content, processing, and audio files
resource "google_storage_bucket" "podcast_content" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  storage_class               = var.bucket_storage_class
  project                     = var.project_id
  uniform_bucket_level_access = true
  
  # Enable versioning for content protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for old versions
  dynamic "lifecycle_rule" {
    for_each = var.enable_versioning ? [1] : []
    content {
      condition {
        age                   = 7
        with_state           = "ARCHIVED"
        num_newer_versions   = 3
      }
      action {
        type = "Delete"
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.enabled_apis]
}

# Create directory structure in the bucket
resource "google_storage_bucket_object" "input_folder" {
  name   = "input/"
  bucket = google_storage_bucket.podcast_content.name
  source = "/dev/null"
}

resource "google_storage_bucket_object" "processed_folder" {
  name   = "processed/"
  bucket = google_storage_bucket.podcast_content.name
  source = "/dev/null"
}

resource "google_storage_bucket_object" "audio_folder" {
  name   = "audio/"
  bucket = google_storage_bucket.podcast_content.name
  source = "/dev/null"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py.tpl", {
      bucket_name = local.bucket_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to a staging bucket (if source bucket not provided)
resource "google_storage_bucket" "function_source" {
  count                       = var.function_source_bucket == "" ? 1 : 0
  name                        = "${local.bucket_name}-functions"
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  project                     = var.project_id
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })
  
  depends_on = [google_project_service.enabled_apis]
}

resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = var.function_source_bucket != "" ? var.function_source_bucket : google_storage_bucket.function_source[0].name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for podcast content processing
resource "google_cloudfunctions_function" "podcast_processor" {
  name        = var.function_name
  project     = var.project_id
  region      = var.region
  description = "Processes text content for podcast generation using NL and TTS APIs"
  
  runtime               = "python311"
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "analyze_and_generate"
  service_account_email = google_service_account.podcast_generator.email
  
  # Function source configuration
  source_archive_bucket = var.function_source_bucket != "" ? var.function_source_bucket : google_storage_bucket.function_source[0].name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Environment variables for the function
  environment_variables = {
    BUCKET_NAME   = google_storage_bucket.podcast_content.name
    PROJECT_ID    = var.project_id
    REGION        = var.region
    ENVIRONMENT   = var.environment
  }
  
  # Scaling configuration
  min_instances = var.function_min_instances
  max_instances = var.function_max_instances
  
  # VPC connector (optional)
  dynamic "vpc_connector" {
    for_each = var.enable_vpc_connector ? [1] : []
    content {
      name = var.vpc_connector_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.enabled_apis,
    google_project_iam_member.storage_admin,
    google_project_iam_member.ml_developer
  ]
}

# IAM policy to allow unauthenticated access to the function
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.podcast_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Monitoring notification channel for alerts (optional)
resource "google_monitoring_notification_channel" "email" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Podcast Generation Email Alerts"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = "admin@example.com" # Replace with actual email
  }
  
  depends_on = [google_project_service.enabled_apis]
}

# Log-based metric for podcast generation count
resource "google_logging_metric" "podcast_generation_count" {
  count  = var.enable_monitoring ? 1 : 0
  name   = "podcast_generation_count"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${var.function_name}"
    textPayload:"podcast generation"
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Podcast Generation Count"
  }
  
  depends_on = [google_project_service.enabled_apis]
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count               = var.enable_monitoring ? 1 : 0
  display_name        = "Podcast Generation Function Errors"
  project             = var.project_id
  combiner            = "OR"
  enabled             = true
  alert_strategy {
    auto_close = "1800s"
  }
  
  conditions {
    display_name = "Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.label.\"function_name\"=\"${var.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.enable_monitoring ? google_monitoring_notification_channel.email : []
    content {
      notification_channels = [notification_channels.value.name]
    }
  }
  
  depends_on = [google_project_service.enabled_apis]
}

# Create sample content for testing
resource "google_storage_bucket_object" "sample_content" {
  name   = "input/sample-article.txt"
  bucket = google_storage_bucket.podcast_content.name
  content = <<-EOT
    Welcome to today's technology podcast. We're exploring the fascinating world of artificial intelligence and its impact on creative industries.
    
    Artificial intelligence has revolutionized content creation in remarkable ways. From automated writing assistants to voice synthesis, AI tools are empowering creators to produce high-quality content more efficiently than ever before.
    
    However, this technological advancement also raises important questions about authenticity and human creativity. Many artists worry that AI might replace human ingenuity, but experts suggest that AI serves as a powerful collaborative tool rather than a replacement.
    
    The future of creative AI lies in human-machine collaboration, where technology amplifies human creativity rather than replacing it. This partnership approach has already shown promising results in various creative fields.
    
    Thank you for listening to today's episode. We'll continue exploring these exciting developments in our next session.
  EOT
}

# Create additional sample content for batch testing
resource "google_storage_bucket_object" "tech_news_content" {
  name   = "input/tech-news.txt"
  bucket = google_storage_bucket.podcast_content.name
  content = <<-EOT
    Breaking news in the technology sector today! Major cloud providers are announcing significant improvements to their AI services.
    
    Google Cloud has enhanced its Natural Language processing capabilities, while competitors are focusing on speech synthesis improvements. This competitive landscape is driving rapid innovation.
    
    Industry experts are excited about these developments, predicting that AI-powered content creation will become mainstream within the next two years.
  EOT
}