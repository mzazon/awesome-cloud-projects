# Main Terraform configuration for Interview Practice Assistant
# This file creates all the infrastructure components for the GCP-based interview practice system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources
  bucket_suffix     = var.bucket_name_suffix != "" ? var.bucket_name_suffix : random_id.suffix.hex
  bucket_name       = "${var.prefix}-audio-${local.bucket_suffix}"
  function_prefix   = var.prefix
  service_account_id = var.service_account_name
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    project     = var.project_id
    region      = var.region
    environment = var.environment
  })
  
  # Required Google Cloud APIs
  required_apis = var.enable_apis ? [
    "cloudfunctions.googleapis.com",
    "speech.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Storage bucket for audio files
resource "google_storage_bucket" "audio_bucket" {
  name          = local.bucket_name
  location      = var.region
  project       = var.project_id
  force_destroy = var.force_destroy_bucket
  
  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Lifecycle rule for multipart uploads cleanup
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
  
  # Versioning configuration
  versioning {
    enabled = false
  }
  
  # Encryption configuration (Google-managed by default)
  encryption {
    default_kms_key_name = null
  }
  
  # CORS configuration for web uploads
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create custom service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_id
  display_name = "Interview Assistant Service Account"
  description  = "Service account for interview practice Cloud Functions with least privilege access"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the service account
resource "google_project_iam_member" "function_sa_speech" {
  project = var.project_id
  role    = "roles/speech.client"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_aiplatform" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create function source directories first
resource "null_resource" "create_function_directories" {
  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/function_source/speech_function ${path.module}/function_source/analysis_function ${path.module}/function_source/orchestration_function"
  }
}

# Create function source code files
resource "local_file" "speech_function_main" {
  filename = "${path.module}/function_source/speech_function/main.py"
  content = templatefile("${path.module}/templates/speech_function_main.py.tpl", {
    speech_model     = var.speech_model
    language_code    = var.speech_language_code
    enable_enhanced  = var.enable_enhanced_speech
  })
  depends_on = [null_resource.create_function_directories]
}

resource "local_file" "speech_function_requirements" {
  filename = "${path.module}/function_source/speech_function/requirements.txt"
  content  = file("${path.module}/templates/speech_function_requirements.txt")
  depends_on = [null_resource.create_function_directories]
}

resource "local_file" "analysis_function_main" {
  filename = "${path.module}/function_source/analysis_function/main.py"
  content = templatefile("${path.module}/templates/analysis_function_main.py.tpl", {
    gemini_model = var.gemini_model
    region       = var.region
  })
  depends_on = [null_resource.create_function_directories]
}

resource "local_file" "analysis_function_requirements" {
  filename = "${path.module}/function_source/analysis_function/requirements.txt"
  content  = file("${path.module}/templates/analysis_function_requirements.txt")
  depends_on = [null_resource.create_function_directories]
}

resource "local_file" "orchestration_function_main" {
  filename = "${path.module}/function_source/orchestration_function/main.py"
  content = templatefile("${path.module}/templates/orchestration_function_main.py.tpl", {
    project_id      = var.project_id
    region          = var.region
    function_prefix = local.function_prefix
  })
  depends_on = [null_resource.create_function_directories]
}

resource "local_file" "orchestration_function_requirements" {
  filename = "${path.module}/function_source/orchestration_function/requirements.txt"
  content  = file("${path.module}/templates/orchestration_function_requirements.txt")
  depends_on = [null_resource.create_function_directories]
}

# Create source code archives for Cloud Functions
data "archive_file" "speech_function_source" {
  type        = "zip"
  output_path = "${path.module}/speech_function_source.zip"
  source_dir  = "${path.module}/function_source/speech_function"
  
  depends_on = [
    local_file.speech_function_main,
    local_file.speech_function_requirements
  ]
}

data "archive_file" "analysis_function_source" {
  type        = "zip"
  output_path = "${path.module}/analysis_function_source.zip"
  source_dir  = "${path.module}/function_source/analysis_function"
  
  depends_on = [
    local_file.analysis_function_main,
    local_file.analysis_function_requirements
  ]
}

data "archive_file" "orchestration_function_source" {
  type        = "zip"
  output_path = "${path.module}/orchestration_function_source.zip"
  source_dir  = "${path.module}/function_source/orchestration_function"
  
  depends_on = [
    local_file.orchestration_function_main,
    local_file.orchestration_function_requirements
  ]
}

# Cloud Storage buckets for function source code
resource "google_storage_bucket_object" "speech_function_source" {
  name   = "speech_function_${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.audio_bucket.name
  source = data.archive_file.speech_function_source.output_path
  
  depends_on = [data.archive_file.speech_function_source]
}

resource "google_storage_bucket_object" "analysis_function_source" {
  name   = "analysis_function_${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.audio_bucket.name
  source = data.archive_file.analysis_function_source.output_path
  
  depends_on = [data.archive_file.analysis_function_source]
}

resource "google_storage_bucket_object" "orchestration_function_source" {
  name   = "orchestration_function_${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.audio_bucket.name
  source = data.archive_file.orchestration_function_source.output_path
  
  depends_on = [data.archive_file.orchestration_function_source]
}

# Speech-to-Text Cloud Function
resource "google_cloudfunctions_function" "speech_function" {
  name        = "${local.function_prefix}-speech"
  description = "Transcribe audio files using Google Cloud Speech-to-Text API"
  runtime     = "python311"
  region      = var.region
  project     = var.project_id
  
  available_memory_mb   = var.function_memory_mb.speech
  timeout              = var.function_timeout_seconds.speech
  entry_point          = "transcribe_audio"
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.audio_bucket.name
  source_archive_object = google_storage_bucket_object.speech_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    GCP_PROJECT          = var.project_id
    REGION              = var.region
    SPEECH_MODEL        = var.speech_model
    LANGUAGE_CODE       = var.speech_language_code
    ENABLE_ENHANCED     = var.enable_enhanced_speech
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.speech_function_source,
    google_project_iam_member.function_sa_speech,
    google_project_iam_member.function_sa_storage
  ]
}

# Analysis Cloud Function (Gemini)
resource "google_cloudfunctions_function" "analysis_function" {
  name        = "${local.function_prefix}-analysis"
  description = "Analyze interview responses using Vertex AI Gemini model"
  runtime     = "python311"
  region      = var.region
  project     = var.project_id
  
  available_memory_mb   = var.function_memory_mb.analysis
  timeout              = var.function_timeout_seconds.analysis
  entry_point          = "analyze_interview_response"
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.audio_bucket.name
  source_archive_object = google_storage_bucket_object.analysis_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    GCP_PROJECT   = var.project_id
    REGION        = var.region
    GEMINI_MODEL  = var.gemini_model
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.analysis_function_source,
    google_project_iam_member.function_sa_aiplatform
  ]
}

# Orchestration Cloud Function
resource "google_cloudfunctions_function" "orchestration_function" {
  name        = "${local.function_prefix}-orchestrate"
  description = "Orchestrate the complete interview analysis workflow"
  runtime     = "python311"
  region      = var.region
  project     = var.project_id
  
  available_memory_mb   = var.function_memory_mb.orchestration
  timeout              = var.function_timeout_seconds.orchestration
  entry_point          = "orchestrate_interview_analysis"
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.audio_bucket.name
  source_archive_object = google_storage_bucket_object.orchestration_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    GCLOUD_PROJECT = var.project_id
    GCLOUD_REGION  = var.region
    FUNCTION_PREFIX = local.function_prefix
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.orchestration_function_source,
    google_cloudfunctions_function.speech_function,
    google_cloudfunctions_function.analysis_function
  ]
}

# IAM policy for unauthenticated access (if enabled)
resource "google_cloudfunctions_function_iam_member" "speech_invoker" {
  count = var.allow_unauthenticated_functions ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.speech_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "analysis_invoker" {
  count = var.allow_unauthenticated_functions ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.analysis_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "orchestration_invoker" {
  count = var.allow_unauthenticated_functions ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.orchestration_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Sample interview questions dataset (optional)
resource "google_storage_bucket_object" "interview_questions" {
  count = var.create_sample_data ? 1 : 0
  
  name    = "interview_questions.json"
  bucket  = google_storage_bucket.audio_bucket.name
  content = jsonencode({
    behavioral = [
      "Tell me about a time when you faced a significant challenge at work. How did you handle it?",
      "Describe a situation where you had to work with a difficult team member.",
      "Give me an example of when you went above and beyond in your role.",
      "Tell me about a time when you made a mistake. How did you handle it?",
      "Describe a situation where you had to learn something quickly.",
      "Tell me about a time when you had to convince someone to see your point of view."
    ]
    technical = [
      "Walk me through your approach to solving a complex technical problem.",
      "How do you stay current with new technologies in your field?",
      "Describe your experience with [relevant technology/framework].",
      "What's your process for debugging a challenging issue?",
      "How do you handle code reviews and feedback?",
      "Explain a technical concept to someone without a technical background."
    ]
    general = [
      "Tell me about yourself.",
      "Why are you interested in this position?",
      "What are your greatest strengths and weaknesses?",
      "Where do you see yourself in five years?",
      "Why are you leaving your current position?",
      "What motivates you in your work?"
    ]
    leadership = [
      "Describe your leadership style.",
      "Tell me about a time when you had to lead a project.",
      "How do you handle conflict within your team?",
      "Describe a time when you had to make a difficult decision.",
      "How do you motivate team members?",
      "Tell me about a time when you received criticism from your manager."
    ]
  })
  
  content_type = "application/json"
  
  depends_on = [google_storage_bucket.audio_bucket]
}

