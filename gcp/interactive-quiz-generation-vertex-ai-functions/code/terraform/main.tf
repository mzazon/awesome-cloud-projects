# Interactive Quiz Generation with Vertex AI and Cloud Functions
# This Terraform configuration deploys a complete quiz generation system using
# Google Cloud services including Vertex AI, Cloud Functions, and Cloud Storage

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
  })

  # Resource names with prefix and random suffix
  bucket_name               = "${var.resource_prefix}-materials-${random_id.suffix.hex}"
  service_account_name      = "${var.resource_prefix}-ai-service"
  generator_function_name   = "${var.resource_prefix}-generator-${random_id.suffix.hex}"
  delivery_function_name    = "${var.resource_prefix}-delivery-${random_id.suffix.hex}"
  scoring_function_name     = "${var.resource_prefix}-scoring-${random_id.suffix.hex}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "aiplatform" {
  project = var.project_id
  service = "aiplatform.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloudfunctions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloudbuild" {
  count   = var.enable_cloud_build ? 1 : 0
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "artifactregistry" {
  count   = var.enable_artifact_registry ? 1 : 0
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Service Account for AI and storage operations
resource "google_service_account" "quiz_ai_service" {
  account_id   = local.service_account_name
  display_name = "Quiz Generation AI Service"
  description  = "Service account for Vertex AI quiz generation and storage operations"
  project      = var.project_id

  depends_on = [
    google_project_service.aiplatform,
    google_project_service.storage
  ]
}

# IAM binding for Vertex AI User role
resource "google_project_iam_member" "ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.quiz_ai_service.email}"

  depends_on = [google_service_account.quiz_ai_service]
}

# IAM binding for Cloud Storage Object Admin role
resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.quiz_ai_service.email}"

  depends_on = [google_service_account.quiz_ai_service]
}

# Cloud Storage bucket for learning materials and quiz storage
resource "google_storage_bucket" "quiz_materials" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  project       = var.project_id

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = var.enable_uniform_bucket_access

  # Enable versioning for content tracking
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle policy for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_policy ? [1] : []
    content {
      condition {
        age = var.nearline_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.enable_lifecycle_policy ? [1] : []
    content {
      condition {
        age = var.coldline_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
    }
  }

  # CORS configuration for web application access
  cors {
    origin          = var.allowed_cors_origins
    method          = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    response_header = ["Content-Type", "Authorization"]
    max_age_seconds = 3600
  }

  labels = local.common_labels

  depends_on = [google_project_service.storage]
}

# Create bucket structure with empty objects as placeholders
resource "google_storage_bucket_object" "uploads_folder" {
  name    = "uploads/.keep"
  content = ""
  bucket  = google_storage_bucket.quiz_materials.name
}

resource "google_storage_bucket_object" "quizzes_folder" {
  name    = "quizzes/.keep"
  content = ""
  bucket  = google_storage_bucket.quiz_materials.name
}

resource "google_storage_bucket_object" "results_folder" {
  name    = "results/.keep"
  content = ""
  bucket  = google_storage_bucket.quiz_materials.name
}

# Archive the quiz generator function source code
data "archive_file" "generator_function_source" {
  type        = "zip"
  output_path = "${path.module}/generator_function.zip"
  source {
    content = templatefile("${path.module}/function_sources/generator_main.py", {
      bucket_name = google_storage_bucket.quiz_materials.name
      region      = var.region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_sources/generator_requirements.txt")
    filename = "requirements.txt"
  }
}

# Archive the quiz delivery function source code
data "archive_file" "delivery_function_source" {
  type        = "zip"
  output_path = "${path.module}/delivery_function.zip"
  source {
    content = templatefile("${path.module}/function_sources/delivery_main.py", {
      bucket_name = google_storage_bucket.quiz_materials.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_sources/delivery_requirements.txt")
    filename = "requirements.txt"
  }
}

# Archive the quiz scoring function source code
data "archive_file" "scoring_function_source" {
  type        = "zip"
  output_path = "${path.module}/scoring_function.zip"
  source {
    content = templatefile("${path.module}/function_sources/scoring_main.py", {
      bucket_name = google_storage_bucket.quiz_materials.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_sources/scoring_requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-functions"
  location      = var.region
  storage_class = "STANDARD"
  project       = var.project_id

  # Function source doesn't need versioning
  versioning {
    enabled = false
  }

  labels = local.common_labels

  depends_on = [google_project_service.storage]
}

# Upload generator function source to Cloud Storage
resource "google_storage_bucket_object" "generator_function_source" {
  name   = "generator_function.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.generator_function_source.output_path

  depends_on = [data.archive_file.generator_function_source]
}

# Upload delivery function source to Cloud Storage
resource "google_storage_bucket_object" "delivery_function_source" {
  name   = "delivery_function.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.delivery_function_source.output_path

  depends_on = [data.archive_file.delivery_function_source]
}

# Upload scoring function source to Cloud Storage
resource "google_storage_bucket_object" "scoring_function_source" {
  name   = "scoring_function.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.scoring_function_source.output_path

  depends_on = [data.archive_file.scoring_function_source]
}

# Quiz Generator Cloud Function
resource "google_cloudfunctions_function" "quiz_generator" {
  name        = local.generator_function_name
  description = "Generate quizzes from educational content using Vertex AI"
  region      = var.region
  project     = var.project_id

  runtime               = "python312"
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "generate_quiz"
  service_account_email = google_service_account.quiz_ai_service.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.generator_function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    BUCKET_NAME = google_storage_bucket.quiz_materials.name
    REGION      = var.region
    GCP_PROJECT = var.project_id
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.cloudfunctions,
    google_storage_bucket_object.generator_function_source,
    google_project_iam_member.ai_user,
    google_project_iam_member.storage_admin
  ]
}

# Quiz Delivery Cloud Function
resource "google_cloudfunctions_function" "quiz_delivery" {
  name        = local.delivery_function_name
  description = "Deliver quizzes to students with proper formatting"
  region      = var.region
  project     = var.project_id

  runtime               = "python312"
  available_memory_mb   = var.delivery_function_memory
  timeout               = 60
  entry_point          = "deliver_quiz"
  service_account_email = google_service_account.quiz_ai_service.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.delivery_function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    BUCKET_NAME = google_storage_bucket.quiz_materials.name
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.cloudfunctions,
    google_storage_bucket_object.delivery_function_source,
    google_project_iam_member.storage_admin
  ]
}

# Quiz Scoring Cloud Function
resource "google_cloudfunctions_function" "quiz_scoring" {
  name        = local.scoring_function_name
  description = "Score submitted quizzes and provide feedback"
  region      = var.region
  project     = var.project_id

  runtime               = "python312"
  available_memory_mb   = var.scoring_function_memory
  timeout               = 60
  entry_point          = "score_quiz"
  service_account_email = google_service_account.quiz_ai_service.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.scoring_function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    BUCKET_NAME = google_storage_bucket.quiz_materials.name
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.cloudfunctions,
    google_storage_bucket_object.scoring_function_source,
    google_project_iam_member.storage_admin
  ]
}

# IAM policy to allow unauthenticated access to functions (for educational use)
# Note: In production, consider implementing proper authentication
resource "google_cloudfunctions_function_iam_member" "generator_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.quiz_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "delivery_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.quiz_delivery.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions_function_iam_member" "scoring_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.quiz_scoring.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}