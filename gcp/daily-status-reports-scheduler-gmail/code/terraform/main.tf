# ==============================================================================
# DAILY STATUS REPORTS WITH CLOUD SCHEDULER AND GMAIL
# ==============================================================================
# This Terraform configuration creates a daily system status reporting solution
# using Google Cloud Scheduler, Cloud Functions, and Gmail API integration.
# The solution provides automated daily insights about GCP infrastructure health
# and resource utilization via email reports.

# Data source to get current GCP project details
data "google_project" "current" {}

# Data source to get current GCP client configuration
data "google_client_config" "current" {}

# ==============================================================================
# GOOGLE CLOUD STORAGE BUCKET FOR FUNCTION SOURCE CODE
# ==============================================================================
# Storage bucket to host the Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-function-source-${random_id.bucket_suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment = var.environment
    purpose     = "function-source"
    recipe      = "daily-status-reports"
  }
}

# Random suffix for unique bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ==============================================================================
# SERVICE ACCOUNT FOR CLOUD FUNCTION
# ==============================================================================
# Service account for the Cloud Function with minimal required permissions
resource "google_service_account" "status_reporter" {
  account_id   = "${var.service_account_name}-${random_id.sa_suffix.hex}"
  display_name = "Daily Status Reporter Service Account"
  description  = "Service account for automated system status reports with Cloud Monitoring access"
}

# Random suffix for unique service account naming
resource "random_id" "sa_suffix" {
  byte_length = 3
}

# Grant Cloud Monitoring Viewer role to service account
resource "google_project_iam_member" "monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.status_reporter.email}"
}

# Grant Cloud Functions Service Agent role for function execution
resource "google_project_iam_member" "functions_service_agent" {
  project = var.project_id
  role    = "roles/cloudfunctions.serviceAgent"
  member  = "serviceAccount:${google_service_account.status_reporter.email}"
}

# ==============================================================================
# CLOUD FUNCTION SOURCE CODE ARCHIVE
# ==============================================================================
# Create ZIP archive with Cloud Function source code and dependencies
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to storage bucket
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# ==============================================================================
# CLOUD FUNCTION DEPLOYMENT
# ==============================================================================
# Deploy Cloud Function for status report generation
resource "google_cloudfunctions_function" "status_report_generator" {
  name        = "${var.function_name}-${random_id.function_suffix.hex}"
  description = "Daily system status report generator with Cloud Monitoring integration"
  runtime     = "python312"
  region      = var.region

  available_memory_mb   = 256
  timeout               = 60
  entry_point          = "generate_status_report"
  service_account_email = google_service_account.status_reporter.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    http_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    GCP_PROJECT      = var.project_id
    SENDER_EMAIL     = var.sender_email
    SENDER_PASSWORD  = var.sender_password
    RECIPIENT_EMAIL  = var.recipient_email
  }

  labels = {
    environment = var.environment
    purpose     = "status-reporting"
    recipe      = "daily-status-reports"
  }

  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.monitoring_viewer,
    google_project_iam_member.functions_service_agent
  ]
}

# Random suffix for unique function naming
resource "random_id" "function_suffix" {
  byte_length = 3
}

# ==============================================================================
# CLOUD SCHEDULER JOB
# ==============================================================================
# Create Cloud Scheduler job for daily report generation
resource "google_cloud_scheduler_job" "daily_report_trigger" {
  name             = "${var.job_name}-${random_id.job_suffix.hex}"
  description      = "Daily system status report trigger - executes every day at 9 AM UTC"
  schedule         = var.cron_schedule
  time_zone        = var.timezone
  region           = var.region
  attempt_deadline = "320s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.status_report_generator.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.status_reporter.email
    }

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      message = "Daily status report trigger"
      timestamp = timestamp()
    }))
  }

  depends_on = [
    google_cloudfunctions_function.status_report_generator
  ]
}

# Random suffix for unique job naming
resource "random_id" "job_suffix" {
  byte_length = 3
}

# ==============================================================================
# IAM PERMISSIONS FOR CLOUD SCHEDULER
# ==============================================================================
# Grant Cloud Functions Invoker role to service account for scheduler access
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.status_report_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.status_reporter.email}"
}

# Grant Cloud Scheduler Service Agent role
resource "google_project_iam_member" "scheduler_service_agent" {
  project = var.project_id
  role    = "roles/cloudscheduler.serviceAgent"
  member  = "serviceAccount:${google_service_account.status_reporter.email}"
}

# ==============================================================================
# REQUIRED API ENABLEMENT
# ==============================================================================
# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "gmail.googleapis.com",
    "storage.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy         = false
}