# GCP Resource Governance with Policy Simulator and Resource Manager
# This Terraform configuration implements automated governance for GCP resources
# using Policy Simulator, Resource Manager, and serverless automation

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  common_labels = merge({
    environment    = var.environment
    team          = var.team
    cost-center   = var.cost_center
    project-code  = "governance"
    managed-by    = "terraform"
    solution      = "resource-governance"
  }, var.tags)

  function_name    = "governance-automation-${random_string.suffix.result}"
  bucket_name     = "governance-reports-${random_string.suffix.result}"
  topic_name      = "governance-events-${random_string.suffix.result}"
  
  # Convert region list to constraint condition
  region_condition = join("', '", var.allowed_compute_regions)
  
  # Required labels condition for organization policy
  required_labels_condition = join(" && ", [
    for label in var.required_resource_labels :
    "has(resource.labels.${replace(label, "-", "_")})"
  ])
}

# Enable required APIs for governance functionality
resource "google_project_service" "required_apis" {
  for_each = toset([
    "policysimulator.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudasset.googleapis.com",
    "bigquery.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create service account for policy simulation operations
resource "google_service_account" "policy_simulator" {
  account_id   = "policy-simulator-sa"
  display_name = "Policy Simulator Service Account"
  description  = "Service account for automated policy simulation and governance"

  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions for policy simulation at organization level
resource "google_organization_iam_member" "policy_simulator_permissions" {
  for_each = toset([
    "roles/policysimulator.admin",
    "roles/iam.securityReviewer",
    "roles/resourcemanager.organizationViewer"
  ])

  org_id = var.organization_id
  role   = each.value
  member = "serviceAccount:${google_service_account.policy_simulator.email}"
}

# Create service account for billing operations
resource "google_service_account" "billing_governance" {
  account_id   = "billing-governance-sa"
  display_name = "Billing Governance Service Account"
  description  = "Service account for billing and cost governance operations"

  depends_on = [google_project_service.required_apis]
}

# Grant billing viewer permissions at organization level
resource "google_organization_iam_member" "billing_governance_permissions" {
  for_each = var.enable_billing_monitoring ? toset([
    "roles/billing.viewer",
    "roles/billing.budgetViewer"
  ]) : toset([])

  org_id = var.organization_id
  role   = each.value
  member = "serviceAccount:${google_service_account.billing_governance.email}"
}

# Create service account for Cloud Function
resource "google_service_account" "governance_function" {
  account_id   = "governance-function-sa"
  display_name = "Governance Function Service Account"
  description  = "Service account for governance automation function"

  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/cloudasset.viewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher",
    "roles/storage.objectAdmin"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.governance_function.email}"
}

# Organization-level permissions for the function
resource "google_organization_iam_member" "function_org_permissions" {
  for_each = toset([
    "roles/cloudasset.viewer",
    "roles/resourcemanager.organizationViewer"
  ])

  org_id = var.organization_id
  role   = each.value
  member = "serviceAccount:${google_service_account.governance_function.email}"
}

# Create Pub/Sub topic for governance events
resource "google_pubsub_topic" "governance_events" {
  name = local.topic_name

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for function source and reports
resource "google_storage_bucket" "governance_reports" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = true

  # Enable versioning for audit trail
  versioning {
    enabled = true
  }

  # Configure lifecycle for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  # Ensure secure access
  uniform_bucket_level_access = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create BigQuery dataset for governance analytics
resource "google_bigquery_dataset" "governance_analytics" {
  count = var.enable_asset_inventory ? 1 : 0

  dataset_id                 = "governance_analytics"
  friendly_name             = "Governance Analytics Dataset"
  description               = "Dataset for storing governance and compliance analytics"
  location                  = var.region
  delete_contents_on_destroy = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create archive for Cloud Function source code
data "archive_file" "governance_function_source" {
  type        = "zip"
  output_path = "${path.module}/governance-function.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      project_id      = var.project_id
      organization_id = var.organization_id
      bucket_name     = local.bucket_name
      topic_name      = local.topic_name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "governance_function_source" {
  name   = "governance-function-${random_string.suffix.result}.zip"
  bucket = google_storage_bucket.governance_reports.name
  source = data.archive_file.governance_function_source.output_path

  depends_on = [data.archive_file.governance_function_source]
}

# Deploy Cloud Function for governance automation
resource "google_cloudfunctions2_function" "governance_automation" {
  name        = local.function_name
  location    = var.region
  description = "Automated governance function for policy simulation and compliance monitoring"

  build_config {
    runtime     = "python311"
    entry_point = "governance_automation"
    
    source {
      storage_source {
        bucket = google_storage_bucket.governance_reports.name
        object = google_storage_bucket_object.governance_function_source.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "256M"
    timeout_seconds    = 540
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      ORGANIZATION_ID = var.organization_id
      BUCKET_NAME     = local.bucket_name
      TOPIC_NAME      = local.topic_name
      ENVIRONMENT     = var.environment
    }

    service_account_email = google_service_account.governance_function.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.governance_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.governance_function_source
  ]
}

# Create Cloud Scheduler job for regular governance audits
resource "google_cloud_scheduler_job" "governance_audit" {
  name             = "governance-audit-job"
  description      = "Weekly governance audit across organization"
  schedule         = var.audit_schedule
  time_zone        = "America/New_York"
  attempt_deadline = "180s"

  pubsub_target {
    topic_name = google_pubsub_topic.governance_events.id
    data       = base64encode(jsonencode({
      audit_type    = "full"
      project_scope = "organization"
      timestamp     = timestamp()
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Scheduler job for cost monitoring
resource "google_cloud_scheduler_job" "cost_monitoring" {
  count = var.enable_billing_monitoring ? 1 : 0

  name             = "cost-monitoring-job"
  description      = "Daily cost and budget monitoring"
  schedule         = var.cost_monitoring_schedule
  time_zone        = "America/New_York"
  attempt_deadline = "180s"

  pubsub_target {
    topic_name = google_pubsub_topic.governance_events.id
    data       = base64encode(jsonencode({
      audit_type     = "billing"
      check_budgets  = true
      timestamp      = timestamp()
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# Create billing budget for governance monitoring
resource "google_billing_budget" "governance_budget" {
  count = var.enable_billing_monitoring && var.billing_account != "" ? 1 : 0

  billing_account = var.billing_account
  display_name    = "Governance Budget Alert"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = var.budget_threshold_percent
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic                     = google_pubsub_topic.governance_events.id
    schema_version                   = "1.0"
    monitoring_notification_channels = []
  }

  depends_on = [google_project_service.required_apis]
}

# Use the verified terraform-google-modules/org-policy/google module for organization policies
module "location_constraint_policy" {
  source  = "terraform-google-modules/org-policy/google"
  version = "~> 7.1"

  organization_id = var.organization_id
  policy_for      = "organization"

  constraint = "compute.vmExternalIpAccess"
  policy_type = "list"
  
  allow_list_length = length(var.allowed_compute_regions)
  allow           = var.allowed_compute_regions
  
  depends_on = [google_project_service.required_apis]
}

# Create organization policy for required resource labels
module "resource_labels_policy" {
  source  = "terraform-google-modules/org-policy/google"
  version = "~> 7.1"

  organization_id = var.organization_id
  policy_for      = "organization"

  constraint = "gcp.resourceLocations"
  policy_type = "list"
  
  allow_list_length = length(var.allowed_compute_regions)
  allow           = var.allowed_compute_regions
  
  depends_on = [google_project_service.required_apis]
}

# Create monitoring alert policy for governance violations
resource "google_monitoring_alert_policy" "governance_violations" {
  display_name = "Governance Policy Violations"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Governance Function Errors"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "60s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "Governance function has encountered errors. Check function logs for details."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}

# Create function source files as local files for deployment
resource "local_file" "function_main_py" {
  filename = "${path.module}/function-source/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id      = var.project_id
    organization_id = var.organization_id
    bucket_name     = local.bucket_name
    topic_name      = local.topic_name
  })
}

resource "local_file" "function_requirements_txt" {
  filename = "${path.module}/function-source/requirements.txt"
  content = templatefile("${path.module}/templates/requirements.txt.tpl", {})
}