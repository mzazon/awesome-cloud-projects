# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming
  resource_suffix = random_id.suffix.hex
  dataset_name    = "${var.resource_prefix}-${var.environment}-${local.resource_suffix}"
  bucket_name     = "${var.project_id}-billing-export-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.default_labels, {
    environment    = var.environment
    project_id     = var.project_id
    resource_group = "cost-allocation"
  })
  
  # Cloud Function source files
  function_source_dir = "${path.module}/function_code"
  
  # Required APIs for the solution
  required_apis = var.enable_apis ? [
    "cloudasset.googleapis.com",
    "policysimulator.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbilling.googleapis.com",
    "orgpolicy.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "eventarc.googleapis.com"
  ] : []
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Pub/Sub topic for asset change notifications
resource "google_pubsub_topic" "asset_changes" {
  name    = "${var.resource_prefix}-asset-changes-${local.resource_suffix}"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Asset Inventory feed for resource monitoring
resource "google_cloud_asset_folder_feed" "resource_compliance" {
  count = var.organization_id != "" ? 1 : 0
  
  billing_project = var.project_id
  folder          = "folders/${var.organization_id}"
  feed_id         = "${var.resource_prefix}-compliance-feed-${local.resource_suffix}"
  
  asset_types = var.monitored_asset_types
  
  content_type = "RESOURCE"
  
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alternative project-level asset feed if organization ID not provided
resource "google_cloud_asset_project_feed" "resource_compliance_project" {
  count = var.organization_id == "" ? 1 : 0
  
  project = var.project_id
  feed_id = "${var.resource_prefix}-compliance-feed-${local.resource_suffix}"
  
  asset_types = var.monitored_asset_types
  
  content_type = "RESOURCE"
  
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create BigQuery dataset for cost allocation analytics
resource "google_bigquery_dataset" "cost_allocation" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.dataset_location
  description = var.dataset_description
  
  # Dataset access controls
  access {
    role          = "OWNER"
    user_by_email = data.google_client_openid_userinfo.current.email
  }
  
  access {
    role         = "READER"
    special_group = "projectReaders"
  }
  
  access {
    role         = "WRITER"
    special_group = "projectWriters"
  }
  
  # Enable deletion protection for production environments
  delete_contents_on_destroy = var.environment != "prod"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# BigQuery table for tag compliance tracking
resource "google_bigquery_table" "tag_compliance" {
  dataset_id = google_bigquery_dataset.cost_allocation.dataset_id
  table_id   = "tag_compliance"
  project    = var.project_id
  
  description = "Table for tracking resource tag compliance status"
  
  schema = jsonencode([
    {
      name = "resource_name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Full resource name"
    },
    {
      name = "resource_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of Google Cloud resource"
    },
    {
      name = "labels"
      type = "JSON"
      mode = "NULLABLE"
      description = "Resource labels in JSON format"
    },
    {
      name = "compliant"
      type = "BOOLEAN"
      mode = "REQUIRED"
      description = "Whether resource meets tagging requirements"
    },
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "When compliance was checked"
    },
    {
      name = "cost_center"
      type = "STRING"
      mode = "NULLABLE"
      description = "Cost center from resource labels"
    },
    {
      name = "department"
      type = "STRING"
      mode = "NULLABLE"
      description = "Department from resource labels"
    },
    {
      name = "environment"
      type = "STRING"
      mode = "NULLABLE"
      description = "Environment from resource labels"
    },
    {
      name = "project_code"
      type = "STRING"
      mode = "NULLABLE"
      description = "Project code from resource labels"
    }
  ])
  
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }
  
  labels = local.common_labels
}

# BigQuery table for cost allocation data
resource "google_bigquery_table" "cost_allocation" {
  dataset_id = google_bigquery_dataset.cost_allocation.dataset_id
  table_id   = "cost_allocation"
  project    = var.project_id
  
  description = "Table for cost allocation analytics"
  
  schema = jsonencode([
    {
      name = "billing_date"
      type = "DATE"
      mode = "REQUIRED"
      description = "Date of billing usage"
    },
    {
      name = "project_id"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud project ID"
    },
    {
      name = "service"
      type = "STRING"
      mode = "REQUIRED"
      description = "Google Cloud service name"
    },
    {
      name = "sku"
      type = "STRING"
      mode = "REQUIRED"
      description = "Service SKU identifier"
    },
    {
      name = "cost"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Cost amount"
    },
    {
      name = "currency"
      type = "STRING"
      mode = "REQUIRED"
      description = "Cost currency code"
    },
    {
      name = "department"
      type = "STRING"
      mode = "NULLABLE"
      description = "Department allocation"
    },
    {
      name = "cost_center"
      type = "STRING"
      mode = "NULLABLE"
      description = "Cost center allocation"
    },
    {
      name = "environment"
      type = "STRING"
      mode = "NULLABLE"
      description = "Environment allocation"
    },
    {
      name = "project_code"
      type = "STRING"
      mode = "NULLABLE"
      description = "Project code allocation"
    }
  ])
  
  time_partitioning {
    type  = "DAY"
    field = "billing_date"
  }
  
  clustering = ["department", "cost_center", "service"]
  
  labels = local.common_labels
}

# Create BigQuery views for cost allocation analytics
resource "google_bigquery_table" "cost_allocation_summary" {
  dataset_id = google_bigquery_dataset.cost_allocation.dataset_id
  table_id   = "cost_allocation_summary"
  project    = var.project_id
  
  description = "View for cost allocation summary analytics"
  
  view {
    query = templatefile("${path.module}/sql/cost_allocation_summary.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.cost_allocation]
}

resource "google_bigquery_table" "compliance_summary" {
  dataset_id = google_bigquery_dataset.cost_allocation.dataset_id
  table_id   = "compliance_summary"
  project    = var.project_id
  
  description = "View for tag compliance summary analytics"
  
  view {
    query = templatefile("${path.module}/sql/compliance_summary.sql", {
      project_id   = var.project_id
      dataset_name = local.dataset_name
    })
    use_legacy_sql = false
  }
  
  labels = local.common_labels
  
  depends_on = [google_bigquery_table.tag_compliance]
}

# Cloud Storage bucket for billing export and function source
resource "google_storage_bucket" "billing_export" {
  name     = local.bucket_name
  project  = var.project_id
  location = var.region
  
  storage_class = var.storage_class
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 1095 # 3 years
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Versioning for data protection
  versioning {
    enabled = true
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code files
resource "local_file" "tag_compliance_function" {
  filename = "${local.function_source_dir}/main.py"
  content = templatefile("${path.module}/templates/tag_compliance_function.py.tpl", {
    project_id   = var.project_id
    dataset_name = local.dataset_name
    mandatory_labels = jsonencode(var.mandatory_labels)
  })
}

resource "local_file" "function_requirements" {
  filename = "${local.function_source_dir}/requirements.txt"
  content  = file("${path.module}/templates/requirements.txt")
}

# Archive function source code
data "archive_file" "tag_compliance_function" {
  type        = "zip"
  source_dir  = local.function_source_dir
  output_path = "${path.module}/tag_compliance_function.zip"
  
  depends_on = [
    local_file.tag_compliance_function,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "tag_compliance_function" {
  name   = "functions/tag-compliance-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.billing_export.name
  source = data.archive_file.tag_compliance_function.output_path
  
  content_type = "application/zip"
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-func-sa-${local.resource_suffix}"
  display_name = "Cost Allocation Function Service Account"
  description  = "Service account for cost allocation and compliance monitoring functions"
  project      = var.project_id
}

# IAM roles for function service account
resource "google_project_iam_member" "function_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_asset_viewer" {
  project = var.project_id
  role    = "roles/cloudasset.viewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Function for tag compliance monitoring
resource "google_cloudfunctions2_function" "tag_compliance" {
  name     = "${var.resource_prefix}-tag-compliance-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  description = "Function to monitor and track resource tag compliance"
  
  build_config {
    runtime     = "python311"
    entry_point = "process_asset_change"
    
    source {
      storage_source {
        bucket = google_storage_bucket.billing_export.name
        object = google_storage_bucket_object.tag_compliance_function.name
      }
    }
  }
  
  service_config {
    max_instance_count = 10
    available_memory   = "${var.function_memory}Mi"
    timeout_seconds    = var.function_timeout
    
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      PROJECT_ID    = var.project_id
      DATASET_NAME  = local.dataset_name
      MANDATORY_LABELS = jsonencode(var.mandatory_labels)
    }
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.asset_changes.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create organization policy constraint (if enabled and organization_id provided)
resource "google_org_policy_custom_constraint" "mandatory_tags" {
  count = var.enforce_org_policy && var.organization_id != "" ? 1 : 0
  
  parent = "organizations/${var.organization_id}"
  name   = "custom.mandatoryResourceTags"
  
  display_name = "Mandatory Resource Tags"
  description  = "Requires specific labels on all resources for cost allocation"
  
  action_type    = "ALLOW"
  method_types   = ["CREATE", "UPDATE"]
  resource_types = var.monitored_asset_types
  
  condition = templatefile("${path.module}/templates/org_policy_condition.cel", {
    mandatory_labels = var.mandatory_labels
  })
  
  depends_on = [google_project_service.required_apis]
}

# Organization policy to enforce the constraint
resource "google_org_policy_policy" "mandatory_tags" {
  count = var.enforce_org_policy && var.organization_id != "" ? 1 : 0
  
  parent = "organizations/${var.organization_id}"
  name   = "organizations/${var.organization_id}/policies/custom.mandatoryResourceTags"
  
  spec {
    rules {
      enforce = "TRUE"
    }
  }
  
  depends_on = [google_org_policy_custom_constraint.mandatory_tags]
}

# Cloud Scheduler job for automated reporting (if enabled)
resource "google_cloud_scheduler_job" "cost_allocation_report" {
  count = var.enable_automated_reporting ? 1 : 0
  
  name             = "${var.resource_prefix}-cost-report-${local.resource_suffix}"
  description      = "Automated cost allocation reporting job"
  schedule         = var.report_schedule
  time_zone        = "UTC"
  attempt_deadline = "300s"
  
  retry_config {
    retry_count = 3
  }
  
  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.cost_allocation_reporter[0].service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Additional Cloud Function for automated reporting
resource "local_file" "reporting_function" {
  count = var.enable_automated_reporting ? 1 : 0
  
  filename = "${local.function_source_dir}/reporting_main.py"
  content = templatefile("${path.module}/templates/reporting_function.py.tpl", {
    project_id   = var.project_id
    dataset_name = local.dataset_name
    bucket_name  = local.bucket_name
  })
}

data "archive_file" "reporting_function" {
  count = var.enable_automated_reporting ? 1 : 0
  
  type        = "zip"
  source_dir  = local.function_source_dir
  output_path = "${path.module}/reporting_function.zip"
  
  depends_on = [
    local_file.reporting_function,
    local_file.function_requirements
  ]
}

resource "google_storage_bucket_object" "reporting_function" {
  count = var.enable_automated_reporting ? 1 : 0
  
  name   = "functions/cost-reporting-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.billing_export.name
  source = data.archive_file.reporting_function[0].output_path
  
  content_type = "application/zip"
}

resource "google_cloudfunctions2_function" "cost_allocation_reporter" {
  count = var.enable_automated_reporting ? 1 : 0
  
  name     = "${var.resource_prefix}-cost-reporter-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  description = "Function to generate automated cost allocation reports"
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_cost_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.billing_export.name
        object = google_storage_bucket_object.reporting_function[0].name
      }
    }
  }
  
  service_config {
    max_instance_count = 5
    available_memory   = "512Mi"
    timeout_seconds    = 300
    
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      PROJECT_ID   = var.project_id
      DATASET_NAME = local.dataset_name
      BUCKET_NAME  = local.bucket_name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Current user info for IAM configuration
data "google_client_openid_userinfo" "current" {}

# Additional IAM role for storage access
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}