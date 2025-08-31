# Main Terraform configuration for smart contract security auditing infrastructure

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  bucket_name         = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  function_source_dir = "${path.module}/function-source"
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "documentai.googleapis.com",
    "aiplatform.googleapis.com", 
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Cloud Storage bucket for contract artifacts and audit reports
resource "google_storage_bucket" "contract_bucket" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Enable versioning for audit trail compliance
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Apply labels
  labels = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Document AI processor for contract analysis
resource "google_document_ai_processor" "contract_processor" {
  provider     = google-beta
  project      = var.project_id
  location     = var.region
  display_name = var.processor_display_name
  type         = var.processor_type
  
  depends_on = [google_project_service.required_apis]
}

# Create a service account for the Cloud Function
resource "google_service_account" "function_sa" {
  project      = var.project_id
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name}"
  description  = "Service account used by the smart contract security analyzer function"
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_documentai_user" {
  project = var.project_id
  role    = "roles/documentai.apiUser"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant the service account access to the specific bucket
resource "google_storage_bucket_iam_member" "function_bucket_access" {
  bucket = google_storage_bucket.contract_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create the function source code directory and files
resource "local_file" "function_main" {
  filename = "${local.function_source_dir}/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    vertex_ai_model = var.vertex_ai_model
  })
  
  provisioner "local-exec" {
    command = "mkdir -p ${local.function_source_dir}"
  }
}

resource "local_file" "function_requirements" {
  filename = "${local.function_source_dir}/requirements.txt"
  content = file("${path.module}/templates/requirements.txt")
}

# Create ZIP archive of the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${local.function_source_dir}.zip"
  source_dir  = local.function_source_dir
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.contract_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create the Cloud Function for contract security analysis
resource "google_cloudfunctions2_function" "contract_analyzer" {
  project  = var.project_id
  name     = var.function_name
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "analyze_contract_security"
    
    source {
      storage_source {
        bucket = google_storage_bucket.contract_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = 10
    min_instance_count = 0
    
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      GCP_PROJECT        = var.project_id
      PROCESSOR_ID       = google_document_ai_processor.contract_processor.name
      PROCESSOR_LOCATION = var.region
      VERTEX_AI_MODEL    = var.vertex_ai_model
      BUCKET_NAME        = google_storage_bucket.contract_bucket.name
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.contract_bucket.name
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = var.labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create bucket folders for organizing contract files and reports
resource "google_storage_bucket_object" "contracts_folder" {
  name    = "contracts/"
  bucket  = google_storage_bucket.contract_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "documentation_folder" {
  name    = "documentation/"
  bucket  = google_storage_bucket.contract_bucket.name
  content = " "
}

resource "google_storage_bucket_object" "audit_reports_folder" {
  name    = "audit-reports/"
  bucket  = google_storage_bucket.contract_bucket.name
  content = " "
}

# Optional: Create Pub/Sub topic for audit completion notifications
resource "google_pubsub_topic" "audit_notifications" {
  count   = var.notification_email != "" ? 1 : 0
  project = var.project_id
  name    = "${var.function_name}-notifications"
  
  labels = var.labels
  
  depends_on = [google_project_service.required_apis]
}

# Optional: Create Pub/Sub subscription for email notifications
resource "google_pubsub_subscription" "audit_email_notifications" {
  count   = var.notification_email != "" ? 1 : 0
  project = var.project_id
  name    = "${var.function_name}-email-notifications"
  topic   = google_pubsub_topic.audit_notifications[0].name
  
  # Configure push subscription to Cloud Function for email processing
  push_config {
    push_endpoint = google_cloudfunctions2_function.contract_analyzer.service_config[0].uri
  }
  
  depends_on = [google_pubsub_topic.audit_notifications]
}

# Sample vulnerable smart contract for testing
resource "google_storage_bucket_object" "sample_contract" {
  name    = "contracts/sample_vulnerable_contract.sol"
  bucket  = google_storage_bucket.contract_bucket.name
  content = file("${path.module}/templates/sample_vulnerable_contract.sol")
  
  depends_on = [google_storage_bucket_object.contracts_folder]
}

# Sample contract documentation for enhanced analysis
resource "google_storage_bucket_object" "sample_documentation" {
  name    = "documentation/contract_security_spec.md"
  bucket  = google_storage_bucket.contract_bucket.name
  content = file("${path.module}/templates/contract_security_spec.md")
  
  depends_on = [google_storage_bucket_object.documentation_folder]
}