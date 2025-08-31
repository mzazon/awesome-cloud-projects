# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.name_prefix}-training-data-${local.resource_suffix}"
  
  # Service account names
  generator_sa_name = "${var.name_prefix}-generator-${local.resource_suffix}"
  processor_sa_name = "${var.name_prefix}-processor-${local.resource_suffix}"
  
  # Function names
  generator_function_name = "${var.name_prefix}-generator-${local.resource_suffix}"
  processor_function_name = "${var.name_prefix}-processor-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
    project     = var.project_id
  })
  
  # Bucket folder structure
  bucket_folders = [
    "raw-conversations/",
    "processed-conversations/", 
    "formatted-training/",
    "templates/"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Cloud Storage bucket for training data
resource "google_storage_bucket" "training_data" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  project       = var.project_id
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Versioning configuration
  versioning {
    enabled = var.bucket_versioning_enabled
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days * 3
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
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create bucket objects for folder structure
resource "google_storage_bucket_object" "bucket_folders" {
  for_each = toset(local.bucket_folders)
  
  name   = "${each.value}.keep"
  bucket = google_storage_bucket.training_data.name
  source = "/dev/null"
  
  depends_on = [google_storage_bucket.training_data]
}

# Upload conversation templates to bucket
resource "google_storage_bucket_object" "conversation_templates" {
  name    = "templates/conversation_templates.json"
  bucket  = google_storage_bucket.training_data.name
  content = jsonencode(var.conversation_templates)
  
  content_type = "application/json"
  
  depends_on = [google_storage_bucket.training_data]
}

# Service account for conversation generator function
resource "google_service_account" "generator_function_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.generator_sa_name
  display_name = "Conversation Generator Function Service Account"
  description  = "Service account for the conversation generator Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Service account for data processor function
resource "google_service_account" "processor_function_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.processor_sa_name
  display_name = "Data Processor Function Service Account"
  description  = "Service account for the data processor Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for generator service account - Storage access
resource "google_storage_bucket_iam_member" "generator_storage_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  bucket = google_storage_bucket.training_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.generator_function_sa[0].email}"
  
  depends_on = [google_service_account.generator_function_sa]
}

# IAM binding for processor service account - Storage access
resource "google_storage_bucket_iam_member" "processor_storage_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  bucket = google_storage_bucket.training_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.processor_function_sa[0].email}"
  
  depends_on = [google_service_account.processor_function_sa]
}

# IAM binding for generator service account - Vertex AI access
resource "google_project_iam_member" "generator_vertex_ai_user" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.generator_function_sa[0].email}"
  
  depends_on = [google_service_account.generator_function_sa]
}

# Create conversation generator function source code
data "archive_file" "generator_function_source" {
  type        = "zip"
  output_path = "${path.module}/generator-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/generator_main.py.tpl", {
      bucket_name      = google_storage_bucket.training_data.name
      vertex_ai_region = var.vertex_ai_region
      gemini_model     = var.gemini_model
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/generator_requirements.txt")
    filename = "requirements.txt"
  }
}

# Create data processor function source code
data "archive_file" "processor_function_source" {
  type        = "zip"
  output_path = "${path.module}/processor-function-source.zip"
  
  source {
    content = file("${path.module}/function_templates/processor_main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/processor_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload generator function source to bucket
resource "google_storage_bucket_object" "generator_function_source" {
  name   = "functions/generator-function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.training_data.name
  source = data.archive_file.generator_function_source.output_path
  
  depends_on = [
    google_storage_bucket.training_data,
    data.archive_file.generator_function_source
  ]
}

# Upload processor function source to bucket
resource "google_storage_bucket_object" "processor_function_source" {
  name   = "functions/processor-function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.training_data.name
  source = data.archive_file.processor_function_source.output_path
  
  depends_on = [
    google_storage_bucket.training_data,
    data.archive_file.processor_function_source
  ]
}

# Deploy conversation generator Cloud Function
resource "google_cloudfunctions2_function" "conversation_generator" {
  name        = local.generator_function_name
  location    = var.region
  project     = var.project_id
  description = "Generates conversational training data using Gemini AI"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "generate_conversations"
    
    source {
      storage_source {
        bucket = google_storage_bucket.training_data.name
        object = google_storage_bucket_object.generator_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      BUCKET_NAME      = google_storage_bucket.training_data.name
      FUNCTION_REGION  = var.vertex_ai_region
      GEMINI_MODEL     = var.gemini_model
      GCP_PROJECT      = var.project_id
    }
    
    dynamic "service_account_email" {
      for_each = var.create_service_accounts ? [1] : []
      content {
        service_account_email = google_service_account.generator_function_sa[0].email
      }
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.generator_function_source
  ]
}

# Deploy data processor Cloud Function
resource "google_cloudfunctions2_function" "data_processor" {
  name        = local.processor_function_name
  location    = var.region
  project     = var.project_id
  description = "Processes and formats conversational training data"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "process_conversations"
    
    source {
      storage_source {
        bucket = google_storage_bucket.training_data.name
        object = google_storage_bucket_object.processor_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1
    available_cpu                    = "1"
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.training_data.name
      GCP_PROJECT = var.project_id
    }
    
    dynamic "service_account_email" {
      for_each = var.create_service_accounts ? [1] : []
      content {
        service_account_email = google_service_account.processor_function_sa[0].email
      }
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.processor_function_source
  ]
}

# Create function invoker permissions for generator
resource "google_cloudfunctions2_function_iam_member" "generator_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.conversation_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create function invoker permissions for processor
resource "google_cloudfunctions2_function_iam_member" "processor_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.data_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Monitoring and Logging Resources (conditional)
resource "google_logging_metric" "conversation_generation_success" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "conversation_generation_success"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.conversation_generator.name}"
    jsonPayload.status="success"
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Successful Conversation Generation Events"
  }
  
  label_extractors = {
    scenario = "EXTRACT(jsonPayload.scenario)"
  }
  
  depends_on = [google_cloudfunctions2_function.conversation_generator]
}

resource "google_logging_metric" "conversation_generation_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "conversation_generation_errors"
  project = var.project_id
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.conversation_generator.name}"
    severity="ERROR"
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Failed Conversation Generation Events"
  }
  
  depends_on = [google_cloudfunctions2_function.conversation_generator]
}

# Create log sink for conversation generation logs (optional)
resource "google_logging_project_sink" "conversation_logs_sink" {
  count = var.enable_monitoring ? 1 : 0
  
  name        = "${var.name_prefix}-conversation-logs-${local.resource_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.training_data.name}/logs"
  
  filter = <<-EOT
    resource.type="cloud_function"
    (resource.labels.function_name="${google_cloudfunctions2_function.conversation_generator.name}" OR
     resource.labels.function_name="${google_cloudfunctions2_function.data_processor.name}")
  EOT
  
  unique_writer_identity = true
  
  depends_on = [
    google_cloudfunctions2_function.conversation_generator,
    google_cloudfunctions2_function.data_processor
  ]
}

# Grant write permissions to log sink
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0
  
  bucket = google_storage_bucket.training_data.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.conversation_logs_sink[0].writer_identity
  
  depends_on = [google_logging_project_sink.conversation_logs_sink]
}