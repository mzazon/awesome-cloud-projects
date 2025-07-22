# main.tf - Database Fleet Governance with Database Center and Cloud Asset Inventory
# Main infrastructure configuration for comprehensive database governance solution

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length
}

locals {
  # Common resource naming pattern
  resource_name = "${var.resource_prefix}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment     = var.environment
    project        = var.project_id
    solution       = "database-governance"
    resource-group = local.resource_name
  })
  
  # Database asset types for monitoring
  database_asset_types = [
    "sqladmin.googleapis.com/Instance",
    "spanner.googleapis.com/Instance",
    "spanner.googleapis.com/Database",
    "alloydb.googleapis.com/Cluster",
    "alloydb.googleapis.com/Instance",
    "bigtableadmin.googleapis.com/Instance",
    "bigtableadmin.googleapis.com/Cluster",
    "firestore.googleapis.com/Database"
  ]
}

# ========================================
# API Services Enablement
# ========================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudasset.googleapis.com",
    "workflows.googleapis.com",
    "monitoring.googleapis.com",
    "sqladmin.googleapis.com",
    "spanner.googleapis.com",
    "alloydb.googleapis.com",
    "bigtableadmin.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "securitycenter.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  # Prevent accidental deletion of critical APIs
  disable_on_destroy = false

  # Ensure APIs are enabled before other resources
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ========================================
# IAM Service Accounts and Permissions
# ========================================

# Service account for database governance automation
resource "google_service_account" "database_governance" {
  account_id   = "${var.resource_prefix}-sa"
  display_name = "Database Governance Service Account"
  description  = "Service account for automated database fleet governance operations"

  depends_on = [google_project_service.required_apis]
}

# Custom IAM role for database governance with minimal required permissions
resource "google_project_iam_custom_role" "database_governance" {
  role_id     = "${replace(var.resource_prefix, "-", "_")}_governance_role"
  title       = "Database Governance Role"
  description = "Custom role for database governance with least-privilege permissions"

  permissions = [
    # Cloud Asset Inventory permissions
    "cloudasset.assets.searchAllResources",
    "cloudasset.assets.exportResource",
    "cloudasset.feeds.create",
    "cloudasset.feeds.get",
    "cloudasset.feeds.list",
    "cloudasset.feeds.update",
    
    # Database viewing permissions
    "cloudsql.instances.list",
    "cloudsql.instances.get",
    "cloudsql.databases.list",
    "cloudsql.databases.get",
    "spanner.instances.list",
    "spanner.instances.get",
    "spanner.databases.list",
    "spanner.databases.get",
    "alloydb.clusters.list",
    "alloydb.clusters.get",
    "alloydb.instances.list",
    "alloydb.instances.get",
    "bigtable.instances.list",
    "bigtable.instances.get",
    "bigtable.clusters.list",
    "bigtable.clusters.get",
    
    # Monitoring and logging permissions
    "monitoring.timeSeries.list",
    "monitoring.timeSeries.create",
    "monitoring.metricDescriptors.list",
    "logging.logEntries.create",
    "logging.logEntries.list",
    
    # Workflow and function permissions
    "workflows.executions.create",
    "workflows.executions.get",
    "cloudfunctions.functions.invoke",
    
    # Storage permissions for compliance reports
    "storage.objects.create",
    "storage.objects.get",
    "storage.objects.list",
    
    # BigQuery permissions for asset data
    "bigquery.datasets.get",
    "bigquery.tables.get",
    "bigquery.tables.getData",
    "bigquery.jobs.create"
  ]

  depends_on = [google_project_service.required_apis]
}

# Assign custom role to service account
resource "google_project_iam_member" "governance_custom_role" {
  project = var.project_id
  role    = google_project_iam_custom_role.database_governance.name
  member  = "serviceAccount:${google_service_account.database_governance.email}"
}

# Additional required roles for comprehensive governance
resource "google_project_iam_member" "governance_additional_roles" {
  for_each = toset([
    "roles/pubsub.subscriber",
    "roles/pubsub.publisher",
    "roles/bigquery.dataEditor",
    "roles/workflows.invoker"
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.database_governance.email}"
}

# ========================================
# Storage Resources
# ========================================

# BigQuery dataset for asset inventory and governance data
resource "google_bigquery_dataset" "governance_dataset" {
  dataset_id  = replace(local.resource_name, "-", "_")
  description = "Dataset for database governance and asset inventory data"
  location    = var.bigquery_dataset_location

  # Data retention and access settings
  default_table_expiration_ms = 7776000000 # 90 days
  
  labels = local.common_labels

  # Access control
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  access {
    role         = "READER"
    user_by_email = google_service_account.database_governance.email
  }

  access {
    role         = "WRITER"
    user_by_email = google_service_account.database_governance.email
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for compliance reports and asset exports
resource "google_storage_bucket" "governance_storage" {
  name     = "${local.resource_name}-storage"
  location = var.storage_bucket_location

  # Storage configuration
  storage_class               = var.storage_bucket_storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90 # Days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365 # Days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Versioning for audit trail
  versioning {
    enabled = true
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Grant storage access to governance service account
resource "google_storage_bucket_iam_member" "governance_storage_access" {
  for_each = toset([
    "roles/storage.objectCreator",
    "roles/storage.objectViewer"
  ])

  bucket = google_storage_bucket.governance_storage.name
  role   = each.key
  member = "serviceAccount:${google_service_account.database_governance.email}"
}

# ========================================
# Pub/Sub for Real-time Asset Changes
# ========================================

# Pub/Sub topic for database asset change notifications
resource "google_pubsub_topic" "database_asset_changes" {
  name = "${local.resource_name}-asset-changes"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for governance automation
resource "google_pubsub_subscription" "governance_automation" {
  name  = "${local.resource_name}-governance-sub"
  topic = google_pubsub_topic.database_asset_changes.name

  # Message retention and acknowledgment settings
  message_retention_duration = "604800s" # 7 days
  ack_deadline_seconds       = 300

  # Dead letter policy for failed processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.governance_dead_letter.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "governance_dead_letter" {
  name = "${local.resource_name}-dead-letter"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# ========================================
# Cloud Asset Inventory Configuration
# ========================================

# Project-level asset feed for real-time database changes
resource "google_cloud_asset_project_feed" "database_feed" {
  project     = var.project_id
  feed_id     = "${local.resource_name}-feed"
  content_type = "RESOURCE"

  # Monitor all database-related asset types
  asset_types = local.database_asset_types

  # Send changes to Pub/Sub topic
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.database_asset_changes.id
    }
  }

  # Only monitor creation, updates, and deletions
  condition {
    expression = "!temporal_asset.deleted || temporal_asset.prior_asset_state != google.cloud.asset.v1.TemporalAsset.PriorAssetState.DOES_NOT_EXIST"
    title       = "database_resource_changes"
    description = "Monitor database resource lifecycle changes"
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.database_asset_changes
  ]
}

# ========================================
# Sample Database Fleet (Optional)
# ========================================

# Cloud SQL instance for governance testing
resource "google_sql_database_instance" "governance_test_sql" {
  count = var.create_sample_databases ? 1 : 0

  name             = "${local.resource_name}-sql"
  database_version = var.cloudsql_database_version
  region           = var.region

  settings {
    tier = var.cloudsql_instance_tier

    # Backup configuration for compliance testing
    backup_configuration {
      enabled    = true
      start_time = "02:00"
      
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    # Security settings
    ip_configuration {
      ipv4_enabled    = false # Private IP only
      private_network = google_compute_network.governance_vpc[0].id
      require_ssl     = true
    }

    # Maintenance window
    maintenance_window {
      day          = 7 # Sunday
      hour         = 3
      update_track = "stable"
    }

    # High availability for production-like testing
    availability_type = "ZONAL"

    # Database flags for security compliance
    database_flags {
      name  = "log_statement"
      value = "all"
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
  }

  # Deletion protection
  deletion_protection = var.enable_deletion_protection

  depends_on = [
    google_project_service.required_apis,
    google_service_networking_connection.private_vpc_connection
  ]
}

# Spanner instance for distributed database governance
resource "google_spanner_instance" "governance_test_spanner" {
  count = var.create_sample_databases ? 1 : 0

  name             = "${local.resource_name}-spanner"
  config           = var.spanner_instance_config
  display_name     = "Database Governance Test Spanner"
  processing_units = var.spanner_processing_units

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Spanner database
resource "google_spanner_database" "governance_test_db" {
  count = var.create_sample_databases ? 1 : 0

  instance = google_spanner_instance.governance_test_spanner[0].name
  name     = "governance-test-db"

  # Sample schema for governance testing
  ddl = [
    "CREATE TABLE Users (UserId INT64 NOT NULL, Name STRING(100)) PRIMARY KEY (UserId)",
    "CREATE TABLE Orders (OrderId INT64 NOT NULL, UserId INT64 NOT NULL, Amount FLOAT64) PRIMARY KEY (OrderId)",
  ]

  depends_on = [google_spanner_instance.governance_test_spanner]
}

# Bigtable instance for NoSQL governance
resource "google_bigtable_instance" "governance_test_bigtable" {
  count = var.create_sample_databases ? 1 : 0

  name         = "${local.resource_name}-bigtable"
  instance_type = var.bigtable_instance_type
  
  cluster {
    cluster_id   = "${local.resource_name}-cluster"
    zone         = var.zone
    num_nodes    = var.bigtable_cluster_num_nodes
    storage_type = "SSD"
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# ========================================
# Networking for Private Database Access
# ========================================

# VPC network for private database connectivity
resource "google_compute_network" "governance_vpc" {
  count = var.create_sample_databases ? 1 : 0

  name                    = "${local.resource_name}-vpc"
  auto_create_subnetworks = false
  description             = "VPC network for database governance infrastructure"
}

# Subnet for database resources
resource "google_compute_subnetwork" "governance_subnet" {
  count = var.create_sample_databases ? 1 : 0

  name          = "${local.resource_name}-subnet"
  network       = google_compute_network.governance_vpc[0].name
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  description   = "Subnet for database governance resources"

  # Enable private Google access for Cloud APIs
  private_ip_google_access = true
}

# Private service networking for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  count = var.create_sample_databases ? 1 : 0

  name          = "${local.resource_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.governance_vpc[0].id
}

# Service networking connection
resource "google_service_networking_connection" "private_vpc_connection" {
  count = var.create_sample_databases ? 1 : 0

  network                 = google_compute_network.governance_vpc[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[0].name]

  depends_on = [google_project_service.required_apis]
}

# ========================================
# Cloud Functions for Compliance Reporting
# ========================================

# Archive the function source code
data "archive_file" "compliance_function_source" {
  type        = "zip"
  output_path = "/tmp/${local.resource_name}-compliance-function.zip"
  
  source {
    content = templatefile("${path.module}/function_code/compliance_reporter.py", {
      project_id = var.project_id
      dataset_id = google_bigquery_dataset.governance_dataset.dataset_id
      bucket_name = google_storage_bucket.governance_storage.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket_object" "compliance_function_code" {
  name   = "compliance-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.governance_storage.name
  source = data.archive_file.compliance_function_source.output_path

  depends_on = [data.archive_file.compliance_function_source]
}

# Cloud Function for compliance reporting
resource "google_cloudfunctions2_function" "compliance_reporter" {
  name     = "${local.resource_name}-compliance-reporter"
  location = var.region

  build_config {
    runtime     = "python39"
    entry_point = "generate_compliance_report"
    
    source {
      storage_source {
        bucket = google_storage_bucket.governance_storage.name
        object = google_storage_bucket_object.compliance_function_code.name
      }
    }
  }

  service_config {
    max_instance_count = 10
    min_instance_count = 0
    available_memory   = "512M"
    timeout_seconds    = var.governance_workflow_timeout
    
    environment_variables = {
      PROJECT_ID  = var.project_id
      DATASET_ID  = google_bigquery_dataset.governance_dataset.dataset_id
      BUCKET_NAME = google_storage_bucket.governance_storage.name
    }
    
    service_account_email = google_service_account.database_governance.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.compliance_function_code
  ]
}

# ========================================
# Cloud Workflows for Governance Automation
# ========================================

# Governance workflow for automated compliance checking
resource "google_workflows_workflow" "database_governance" {
  name            = "${local.resource_name}-workflow"
  region          = var.region
  description     = "Automated workflow for database governance and compliance checking"
  service_account = google_service_account.database_governance.id

  source_contents = templatefile("${path.module}/workflow_definitions/governance_workflow.yaml", {
    project_id          = var.project_id
    region              = var.region
    function_name       = google_cloudfunctions2_function.compliance_reporter.name
    compliance_threshold = var.compliance_threshold
  })

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.compliance_reporter
  ]
}

# ========================================
# Cloud Scheduler for Automated Governance
# ========================================

# Scheduler job for regular compliance checks
resource "google_cloud_scheduler_job" "governance_scheduler" {
  name             = "${local.resource_name}-scheduler"
  description      = "Automated database governance compliance checks"
  schedule         = var.compliance_report_schedule
  time_zone        = "America/New_York"
  attempt_deadline = "${var.governance_workflow_timeout}s"

  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.database_governance.name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      argument = jsonencode({
        trigger = "scheduled"
        project = var.project_id
      })
    }))

    oauth_token {
      service_account_email = google_service_account.database_governance.email
      scope                = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.database_governance
  ]
}

# ========================================
# Monitoring and Alerting
# ========================================

# Log-based metric for compliance scoring
resource "google_logging_metric" "database_compliance_score" {
  name   = "${replace(local.resource_name, "-", "_")}_compliance_score"
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.compliance_reporter.name}\" AND \"compliance_score\""

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "1"
    display_name = "Database Compliance Score"
  }

  value_extractor = "EXTRACT(jsonPayload.compliance_score)"

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.compliance_reporter
  ]
}

# Notification channels for governance alerts
resource "google_monitoring_notification_channel" "email_alerts" {
  count = length(var.alert_email_addresses)

  display_name = "Database Governance Alerts - ${var.alert_email_addresses[count.index]}"
  type         = "email"
  
  labels = {
    email_address = var.alert_email_addresses[count.index]
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for governance violations
resource "google_monitoring_alert_policy" "governance_violations" {
  count = length(var.alert_email_addresses) > 0 ? 1 : 0

  display_name = "Database Governance Violations"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Low compliance score"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.database_compliance_score.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = var.compliance_threshold

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = ["resource.label.project_id"]
      }
    }
  }

  notification_channels = [for nc in google_monitoring_notification_channel.email_alerts : nc.name]

  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }

  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.database_compliance_score
  ]
}

# Custom monitoring dashboard for database governance
resource "google_monitoring_dashboard" "governance_dashboard" {
  count = var.enable_dashboard ? 1 : 0

  dashboard_json = templatefile("${path.module}/dashboard_config/governance_dashboard.json", {
    project_id = var.project_id
    resource_name = local.resource_name
    compliance_metric = google_logging_metric.database_compliance_score.name
  })

  depends_on = [
    google_project_service.required_apis,
    google_logging_metric.database_compliance_score
  ]
}