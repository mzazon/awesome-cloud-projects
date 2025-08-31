# Main Terraform configuration for sustainability compliance automation
# This file creates the complete infrastructure for carbon footprint tracking,
# ESG reporting, and compliance monitoring using Google Cloud services

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common labels for all resources
  common_labels = merge(var.labels, {
    solution = "sustainability-compliance"
  })
  
  # Unique resource names with random suffix
  dataset_name      = "${var.dataset_name}_${random_id.suffix.hex}"
  function_prefix   = "carbon-${random_id.suffix.hex}"
  bucket_name      = "esg-reports-${random_id.suffix.hex}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  service = each.value
  
  # Disable on destroy to prevent issues when destroying infrastructure
  disable_on_destroy = false
}

# BigQuery dataset for carbon footprint data storage
resource "google_bigquery_dataset" "carbon_footprint" {
  dataset_id    = local.dataset_name
  friendly_name = "Carbon Footprint and Sustainability Data"
  description   = "Dataset for storing carbon footprint data, sustainability metrics, and ESG reporting"
  location      = var.region
  
  # Set appropriate access controls
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.email
  }
  
  # Enable deletion of dataset with tables
  delete_contents_on_destroy = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for processed sustainability metrics
resource "google_bigquery_table" "sustainability_metrics" {
  dataset_id = google_bigquery_dataset.carbon_footprint.dataset_id
  table_id   = "sustainability_metrics"
  
  description = "Processed sustainability metrics and carbon footprint analytics"
  
  # Define table schema for sustainability metrics
  schema = jsonencode([
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud project identifier"
    },
    {
      name = "month"
      type = "DATE"
      mode = "REQUIRED"
      description = "Month of the carbon footprint data"
    },
    {
      name = "total_emissions"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Total carbon emissions in kg CO2e"
    },
    {
      name = "scope_1"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Scope 1 emissions (direct emissions)"
    },
    {
      name = "scope_2_location"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Scope 2 location-based emissions"
    },
    {
      name = "scope_2_market"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Scope 2 market-based emissions"
    },
    {
      name = "scope_3"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Scope 3 emissions (indirect emissions)"
    },
    {
      name = "service"
      type = "STRING"
      mode = "NULLABLE"
      description = "Google Cloud service name"
    },
    {
      name = "region"
      type = "STRING"
      mode = "NULLABLE"
      description = "Google Cloud region"
    }
  ])
  
  labels = local.common_labels
}

# Service account for Cloud Functions
resource "google_service_account" "functions_sa" {
  account_id   = "carbon-functions-${random_id.suffix.hex}"
  display_name = "Carbon Footprint Functions Service Account"
  description  = "Service account for carbon footprint processing functions"
}

# IAM roles for the service account
resource "google_project_iam_member" "functions_bigquery_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

resource "google_project_iam_member" "functions_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

resource "google_project_iam_member" "functions_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.functions_sa.email}"
}

# Cloud Storage bucket for ESG reports
resource "google_storage_bucket" "esg_reports" {
  name     = local.bucket_name
  location = var.region
  
  # Enable versioning for audit trails
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 365  # Move to archive after 1 year
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.function_prefix}-source"
  location = var.region
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Data sources for current configuration
data "google_client_config" "current" {}

# Create function source archives
data "archive_file" "process_function_source" {
  type        = "zip"
  output_path = "${path.module}/process_function.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/process_carbon_data.py", {
      dataset_name = local.dataset_name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "report_function_source" {
  type        = "zip"
  output_path = "${path.module}/report_function.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/generate_esg_report.py", {
      dataset_name    = local.dataset_name
      random_suffix   = random_id.suffix.hex
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_templates/requirements_report.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "alert_function_source" {
  type        = "zip"
  output_path = "${path.module}/alert_function.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/carbon_alerts.py", {
      dataset_name             = local.dataset_name
      monthly_threshold        = var.monthly_emissions_threshold
      growth_threshold         = var.growth_threshold
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "process_function_source" {
  name   = "process-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.process_function_source.output_path
}

resource "google_storage_bucket_object" "report_function_source" {
  name   = "report-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.report_function_source.output_path
}

resource "google_storage_bucket_object" "alert_function_source" {
  name   = "alert-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.alert_function_source.output_path
}

# Data Processing Cloud Function
resource "google_cloudfunctions_function" "process_carbon_data" {
  name        = "${local.function_prefix}-process-data"
  description = "Process carbon footprint data and calculate sustainability metrics"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = var.function_memory
  timeout              = var.function_timeout
  entry_point          = "process_carbon_data"
  service_account_email = google_service_account.functions_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.process_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    DATASET_NAME = local.dataset_name
    PROJECT_ID   = var.project_id
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.functions_bigquery_admin
  ]
}

# ESG Report Generation Cloud Function
resource "google_cloudfunctions_function" "generate_esg_report" {
  name        = "${local.function_prefix}-generate-report"
  description = "Generate ESG compliance reports from carbon footprint data"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = var.function_memory
  timeout              = var.function_timeout
  entry_point          = "generate_esg_report"
  service_account_email = google_service_account.functions_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.report_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    DATASET_NAME    = local.dataset_name
    PROJECT_ID      = var.project_id
    RANDOM_SUFFIX   = random_id.suffix.hex
    BUCKET_NAME     = local.bucket_name
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.functions_bigquery_admin,
    google_project_iam_member.functions_storage_admin
  ]
}

# Carbon Alert Cloud Function
resource "google_cloudfunctions_function" "carbon_alerts" {
  count = var.enable_alerts ? 1 : 0
  
  name        = "${local.function_prefix}-alerts"
  description = "Monitor carbon emissions and generate sustainability alerts"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = var.alert_function_memory
  timeout              = var.alert_function_timeout
  entry_point          = "carbon_alerts"
  service_account_email = google_service_account.functions_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.alert_function_source.name
  
  trigger {
    http_trigger {
      url = null
    }
  }
  
  environment_variables = {
    DATASET_NAME         = local.dataset_name
    PROJECT_ID           = var.project_id
    MONTHLY_THRESHOLD    = var.monthly_emissions_threshold
    GROWTH_THRESHOLD     = var.growth_threshold
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.functions_bigquery_admin
  ]
}

# Cloud Scheduler jobs for automated processing
resource "google_cloud_scheduler_job" "process_carbon_data" {
  count = var.enable_scheduled_processing ? 1 : 0
  
  name        = "process-carbon-data-${random_id.suffix.hex}"
  description = "Process carbon footprint data monthly"
  schedule    = "0 9 16 * *"  # 9 AM on the 16th of each month
  time_zone   = "UTC"
  region      = var.region
  
  http_target {
    uri         = google_cloudfunctions_function.process_carbon_data.https_trigger_url
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "scheduled"
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "generate_esg_reports" {
  count = var.enable_scheduled_processing ? 1 : 0
  
  name        = "generate-esg-reports-${random_id.suffix.hex}"
  description = "Generate monthly ESG compliance reports"
  schedule    = "0 10 16 * *"  # 10 AM on the 16th of each month
  time_zone   = "UTC"
  region      = var.region
  
  http_target {
    uri         = google_cloudfunctions_function.generate_esg_report.https_trigger_url
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "scheduled"
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}

resource "google_cloud_scheduler_job" "carbon_alerts_check" {
  count = var.enable_scheduled_processing && var.enable_alerts ? 1 : 0
  
  name        = "carbon-alerts-check-${random_id.suffix.hex}"
  description = "Weekly carbon emissions monitoring"
  schedule    = "0 8 * * 1"  # 8 AM every Monday
  time_zone   = "UTC"
  region      = var.region
  
  http_target {
    uri         = google_cloudfunctions_function.carbon_alerts[0].https_trigger_url
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "scheduled"
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery Data Transfer for Carbon Footprint
resource "google_bigquery_data_transfer_config" "carbon_footprint_export" {
  display_name   = "Carbon Footprint Export ${random_id.suffix.hex}"
  location       = var.region
  data_source_id = "carbon_footprint"  # Carbon Footprint data source
  
  # Target dataset for the export
  destination_dataset_id = google_bigquery_dataset.carbon_footprint.dataset_id
  
  # Configuration parameters for Carbon Footprint export
  params = {
    billing_account_id = var.billing_account_id
  }
  
  # Schedule for automatic data transfer (daily check, data available monthly)
  schedule = "every day 02:00"
  
  depends_on = [
    google_project_service.required_apis,
    google_bigquery_dataset.carbon_footprint
  ]
}