# Smart Expense Processing using Document AI and Gemini
# Terraform configuration for GCP infrastructure

# Configure the Google Cloud Provider
terraform {
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
      version = "~> 3.1"
    }
  }
}

# Random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local variables for consistent resource naming and configuration
locals {
  project_id = var.project_id
  region     = var.region
  zone       = var.zone
  
  # Resource naming with random suffix for uniqueness
  expense_processor_name = "expense-parser-${random_id.suffix.hex}"
  db_instance_name      = "expense-db-${random_id.suffix.hex}"
  bucket_name          = "expense-receipts-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    project     = "smart-expense-processing"
    managed-by  = "terraform"
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "documentai.googleapis.com",
    "aiplatform.googleapis.com",
    "workflows.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])

  project = local.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Cloud Storage bucket for receipt storage
resource "google_storage_bucket" "expense_receipts" {
  name          = local.bucket_name
  location      = local.region
  project       = local.project_id
  force_destroy = var.force_destroy

  # Enable versioning for audit trail
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

  # Security configurations
  uniform_bucket_level_access = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for reports
resource "google_storage_bucket_object" "reports_folder" {
  name   = "reports/"
  bucket = google_storage_bucket.expense_receipts.name
  content = " "
}

# Document AI Processor for expense parsing
# Note: Document AI processors must be created via REST API or Console
# This data source assumes the processor exists or will be created manually
data "google_document_ai_processor" "expense_parser" {
  count      = var.create_document_ai_processor ? 0 : 1
  location   = local.region
  processor_id = var.document_ai_processor_id
}

# Cloud SQL PostgreSQL instance for expense data
resource "google_sql_database_instance" "expense_db" {
  name             = local.db_instance_name
  database_version = var.database_version
  region          = local.region
  project         = local.project_id

  settings {
    tier = var.database_tier
    
    # Disk configuration
    disk_type    = "PD_SSD"
    disk_size    = var.database_disk_size
    disk_autoresize = true
    disk_autoresize_limit = 50

    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                    = "03:00"
      location                      = local.region
      binary_log_enabled            = false
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    # IP configuration
    ip_configuration {
      ipv4_enabled    = true
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }

    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM
      update_track = "stable"
    }

    # User labels
    user_labels = local.common_labels
  }

  deletion_protection = var.deletion_protection

  depends_on = [google_project_service.required_apis]
}

# Cloud SQL database for expenses
resource "google_sql_database" "expenses" {
  name     = "expenses"
  instance = google_sql_database_instance.expense_db.name
  project  = local.project_id
}

# Database user for applications
resource "google_sql_user" "app_user" {
  name     = var.database_user
  instance = google_sql_database_instance.expense_db.name
  password = var.database_password
  project  = local.project_id
}

# Service account for Cloud Functions
resource "google_service_account" "expense_functions_sa" {
  account_id   = "expense-functions-sa-${random_id.suffix.hex}"
  display_name = "Service Account for Expense Processing Functions"
  description  = "Service account used by Cloud Functions for expense processing"
  project      = local.project_id
}

# IAM roles for the service account
resource "google_project_iam_member" "expense_functions_roles" {
  for_each = toset([
    "roles/aiplatform.user",
    "roles/documentai.apiUser",
    "roles/cloudsql.client",
    "roles/storage.objectAdmin",
    "roles/workflows.invoker",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.expense_functions_sa.email}"
}

# Archive source code for validation function
data "archive_file" "validator_source" {
  type        = "zip"
  output_path = "/tmp/validator_source.zip"
  source {
    content = templatefile("${path.module}/functions/validator/main.py", {
      project_id = local.project_id
      region     = local.region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/validator/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-functions"
  location      = local.region
  project       = local.project_id
  force_destroy = var.force_destroy

  uniform_bucket_level_access = true
  labels                     = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload validator function source code
resource "google_storage_bucket_object" "validator_source" {
  name   = "validator-${data.archive_file.validator_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.validator_source.output_path
}

# Cloud Function for expense validation using Gemini
resource "google_cloudfunctions2_function" "expense_validator" {
  name        = "expense-validator-${random_id.suffix.hex}"
  location    = local.region
  project     = local.project_id
  description = "Validates expenses using Gemini AI"

  build_config {
    runtime     = "python311"
    entry_point = "validate_expense"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.validator_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.max_function_instances
    min_instance_count = 0
    available_memory   = "512Mi"
    timeout_seconds    = 300
    
    environment_variables = {
      PROJECT_ID = local.project_id
      REGION     = local.region
    }

    service_account_email = google_service_account.expense_functions_sa.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.validator_source
  ]
}

# Archive source code for report generator function
data "archive_file" "report_generator_source" {
  type        = "zip"
  output_path = "/tmp/report_generator_source.zip"
  source {
    content = templatefile("${path.module}/functions/report-generator/main.py", {
      bucket_name = google_storage_bucket.expense_receipts.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/functions/report-generator/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload report generator function source code
resource "google_storage_bucket_object" "report_generator_source" {
  name   = "report-generator-${data.archive_file.report_generator_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.report_generator_source.output_path
}

# Cloud Function for report generation
resource "google_cloudfunctions2_function" "report_generator" {
  name        = "expense-report-generator-${random_id.suffix.hex}"
  location    = local.region
  project     = local.project_id
  description = "Generates automated expense reports"

  build_config {
    runtime     = "python311"
    entry_point = "generate_expense_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.report_generator_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.max_function_instances
    min_instance_count = 0
    available_memory   = "256Mi"
    timeout_seconds    = 180
    
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.expense_receipts.name
      PROJECT_ID  = local.project_id
    }

    service_account_email = google_service_account.expense_functions_sa.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.report_generator_source
  ]
}

# Cloud Workflows for expense processing orchestration
resource "google_workflows_workflow" "expense_processing" {
  name            = "expense-processing-workflow-${random_id.suffix.hex}"
  region          = local.region
  project         = local.project_id
  description     = "Orchestrates expense processing from receipt to approval"
  service_account = google_service_account.expense_functions_sa.id

  source_contents = templatefile("${path.module}/workflows/expense-workflow.yaml", {
    project_id    = local.project_id
    region        = local.region
    processor_id  = var.document_ai_processor_id
    validator_url = google_cloudfunctions2_function.expense_validator.service_config[0].uri
  })

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.expense_validator
  ]
}

# Cloud Monitoring Dashboard for expense processing
resource "google_monitoring_dashboard" "expense_dashboard" {
  dashboard_json = templatefile("${path.module}/monitoring/dashboard.json", {
    project_id = local.project_id
  })

  depends_on = [google_project_service.required_apis]
}

# Cloud Scheduler job for automated reporting
resource "google_cloud_scheduler_job" "weekly_reports" {
  count    = var.enable_scheduled_reports ? 1 : 0
  name     = "weekly-expense-reports-${random_id.suffix.hex}"
  region   = local.region
  project  = local.project_id
  schedule = var.report_schedule

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.report_generator.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.expense_functions_sa.email
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.report_generator
  ]
}

# IAM policy for Cloud Functions invocation
resource "google_cloudfunctions2_function_iam_member" "validator_invoker" {
  project        = local.project_id
  location       = local.region
  cloud_function = google_cloudfunctions2_function.expense_validator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

resource "google_cloudfunctions2_function_iam_member" "report_generator_invoker" {
  project        = local.project_id
  location       = local.region
  cloud_function = google_cloudfunctions2_function.report_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.expense_functions_sa.email}"
}

# Cloud SQL Proxy IAM binding for secure database access
resource "google_project_iam_member" "sql_proxy_user" {
  project = local.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.expense_functions_sa.email}"
}

# Secret Manager secret for database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "expense-db-credentials-${random_id.suffix.hex}"
  project   = local.project_id

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "db_credentials_version" {
  secret = google_secret_manager_secret.db_credentials.id

  secret_data = jsonencode({
    username = google_sql_user.app_user.name
    password = var.database_password
    host     = google_sql_database_instance.expense_db.connection_name
    database = google_sql_database.expenses.name
  })
}

# Grant access to the secret
resource "google_secret_manager_secret_iam_member" "db_credentials_access" {
  secret_id = google_secret_manager_secret.db_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.expense_functions_sa.email}"
  project   = local.project_id
}