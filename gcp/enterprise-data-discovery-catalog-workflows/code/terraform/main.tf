# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Consistent naming convention
  resource_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    timestamp   = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Function and workflow names with suffix
  function_name = "${var.function_config.name}-${local.resource_suffix}"
  workflow_name = "${var.workflow_config.name}-${local.resource_suffix}"
  scheduler_job_daily = "${var.resource_prefix}-scheduler-${local.resource_suffix}"
  scheduler_job_weekly = "${var.resource_prefix}-scheduler-weekly-${local.resource_suffix}"
  staging_bucket_name = "${var.resource_prefix}-staging-${local.resource_suffix}"
}

# ============================================================================
# ENABLE REQUIRED APIS
# ============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "datacatalog.googleapis.com",
    "workflows.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com"
  ])
  
  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = true
  disable_on_destroy        = false
}

# ============================================================================
# IAM AND SERVICE ACCOUNTS
# ============================================================================

# Service account for data discovery operations
resource "google_service_account" "data_discovery_sa" {
  account_id   = "${var.resource_prefix}-sa-${local.resource_suffix}"
  display_name = "Data Discovery Service Account"
  description  = "Service account for automated data discovery and cataloging operations"
  
  depends_on = [google_project_service.required_apis]
}

# Assign IAM roles to the service account
resource "google_project_iam_member" "data_discovery_roles" {
  for_each = toset(var.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.data_discovery_sa.email}"
  
  depends_on = [google_service_account.data_discovery_sa]
}

# ============================================================================
# CLOUD STORAGE
# ============================================================================

# Staging bucket for Cloud Functions source code
resource "google_storage_bucket" "staging_bucket" {
  name          = local.staging_bucket_name
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = false
  }
  
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Sample storage buckets for testing data discovery
resource "google_storage_bucket" "sample_buckets" {
  for_each = var.storage_buckets
  
  name          = "${var.project_id}-${each.key}-${local.resource_suffix}"
  location      = each.value.location
  storage_class = each.value.storage_class
  
  uniform_bucket_level_access = true
  
  dynamic "versioning" {
    for_each = each.value.versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  labels = merge(local.common_labels, {
    purpose = "sample-data"
    dataset = each.key
  })
  
  depends_on = [google_project_service.required_apis]
}

# Upload sample files to storage buckets
resource "google_storage_bucket_object" "sample_files" {
  for_each = {
    for pair in flatten([
      for bucket_key, bucket_config in var.storage_buckets : [
        for file_name, file_content in bucket_config.sample_files : {
          bucket_key   = bucket_key
          file_name    = file_name
          file_content = file_content
        }
      ]
    ]) : "${pair.bucket_key}-${pair.file_name}" => pair
  }
  
  name    = each.value.file_name
  bucket  = google_storage_bucket.sample_buckets[each.value.bucket_key].name
  content = each.value.file_content
  
  depends_on = [google_storage_bucket.sample_buckets]
}

# ============================================================================
# BIGQUERY DATASETS AND TABLES
# ============================================================================

# Sample BigQuery datasets for testing discovery
resource "google_bigquery_dataset" "sample_datasets" {
  for_each = var.sample_datasets
  
  dataset_id    = "${each.key}_${local.resource_suffix}"
  friendly_name = each.value.friendly_name
  description   = each.value.description
  location      = each.value.location
  
  labels = merge(local.common_labels, {
    purpose = "sample-data"
    dataset = each.key
  })
  
  depends_on = [google_project_service.required_apis]
}

# Sample BigQuery tables
resource "google_bigquery_table" "sample_tables" {
  for_each = {
    for pair in flatten([
      for dataset_key, dataset_config in var.sample_datasets : [
        for table_name, table_config in dataset_config.tables : {
          dataset_key  = dataset_key
          table_name   = table_name
          table_config = table_config
        }
      ]
    ]) : "${pair.dataset_key}-${pair.table_name}" => pair
  }
  
  dataset_id = google_bigquery_dataset.sample_datasets[each.value.dataset_key].dataset_id
  table_id   = each.value.table_name
  
  description = each.value.table_config.description
  
  schema = jsonencode(each.value.table_config.schema)
  
  labels = merge(local.common_labels, {
    purpose = "sample-data"
    dataset = each.value.dataset_key
    table   = each.value.table_name
  })
  
  depends_on = [google_bigquery_dataset.sample_datasets]
}

# ============================================================================
# DATA CATALOG TAG TEMPLATES
# ============================================================================

# Data Catalog tag templates for metadata classification
resource "google_data_catalog_tag_template" "templates" {
  for_each = var.tag_templates
  
  tag_template_id = each.key
  region         = var.region
  display_name   = each.value.display_name
  
  dynamic "fields" {
    for_each = each.value.fields
    content {
      field_id     = fields.key
      display_name = fields.value.display_name
      is_required  = fields.value.is_required
      
      type {
        primitive_type = fields.value.type == "ENUM" ? null : fields.value.type
        
        dynamic "enum_type" {
          for_each = fields.value.type == "ENUM" ? [1] : []
          content {
            dynamic "allowed_values" {
              for_each = fields.value.enum_values
              content {
                display_name = allowed_values.value
              }
            }
          }
        }
      }
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CLOUD FUNCTION FOR METADATA EXTRACTION
# ============================================================================

# Archive source code for Cloud Function
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.staging_bucket.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Cloud Function for metadata extraction
resource "google_cloudfunctions2_function" "metadata_extractor" {
  name     = local.function_name
  location = var.region
  
  build_config {
    runtime     = var.function_config.runtime
    entry_point = "discover_and_catalog"
    
    source {
      storage_source {
        bucket = google_storage_bucket.staging_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_config.max_instances
    min_instance_count = var.function_config.min_instances
    
    available_memory   = var.function_config.memory
    timeout_seconds    = var.function_config.timeout
    
    service_account_email = google_service_account.data_discovery_sa.email
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
  }
  
  labels = merge(local.common_labels, {
    component = "metadata-extraction"
  })
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_project_iam_member.data_discovery_roles
  ]
}

# Allow unauthenticated access to the function (for testing)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.metadata_extractor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# ============================================================================
# CLOUD WORKFLOWS
# ============================================================================

# Cloud Workflows for discovery orchestration
resource "google_workflows_workflow" "data_discovery" {
  name   = local.workflow_name
  region = var.region
  
  description = var.workflow_config.description
  
  source_contents = templatefile("${path.module}/workflow_definition.yaml", {
    project_id    = var.project_id
    region        = var.region
    function_name = local.function_name
    suffix        = local.resource_suffix
  })
  
  service_account = google_service_account.data_discovery_sa.email
  
  labels = merge(local.common_labels, {
    component = "orchestration"
  })
  
  depends_on = [
    google_cloudfunctions2_function.metadata_extractor,
    google_project_iam_member.data_discovery_roles
  ]
}

# ============================================================================
# CLOUD SCHEDULER
# ============================================================================

# Daily discovery scheduler job
resource "google_cloud_scheduler_job" "daily_discovery" {
  name             = local.scheduler_job_daily
  region           = var.region
  description      = "${var.scheduler_config.description} (Daily)"
  schedule         = var.scheduler_config.daily_schedule
  time_zone        = var.scheduler_config.time_zone
  attempt_deadline = "540s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${local.workflow_name}/executions"
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        suffix       = local.resource_suffix
        scope        = "daily"
        comprehensive = false
      })
    }))
    
    oauth_token {
      service_account_email = google_service_account.data_discovery_sa.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_workflows_workflow.data_discovery,
    google_project_iam_member.data_discovery_roles
  ]
}

# Weekly comprehensive discovery scheduler job
resource "google_cloud_scheduler_job" "weekly_discovery" {
  name             = local.scheduler_job_weekly
  region           = var.region
  description      = "${var.scheduler_config.description} (Weekly Comprehensive)"
  schedule         = var.scheduler_config.weekly_schedule
  time_zone        = var.scheduler_config.time_zone
  attempt_deadline = "600s"
  
  retry_config {
    retry_count = 2
  }
  
  http_target {
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${local.workflow_name}/executions"
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        suffix        = local.resource_suffix
        scope         = "weekly"
        comprehensive = true
      })
    }))
    
    oauth_token {
      service_account_email = google_service_account.data_discovery_sa.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_workflows_workflow.data_discovery,
    google_project_iam_member.data_discovery_roles
  ]
}

# ============================================================================
# ADDITIONAL IAM FOR WORKFLOWS AND SCHEDULER
# ============================================================================

# Additional IAM permissions for Workflows to execute
resource "google_project_iam_member" "workflows_permissions" {
  for_each = toset([
    "roles/workflows.invoker",
    "roles/cloudfunctions.invoker",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.data_discovery_sa.email}"
  
  depends_on = [google_service_account.data_discovery_sa]
}