# Centralized Database Fleet Governance with Database Center and Cloud Asset Inventory
# Terraform Infrastructure as Code

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Compute derived values
  suffix                  = random_id.suffix.hex
  service_account_email   = "${google_service_account.governance_sa.account_id}@${var.project_id}.iam.gserviceaccount.com"
  bigquery_location      = var.bigquery_dataset_location != "" ? var.bigquery_dataset_location : var.region
  notification_email     = var.notification_email != "" ? var.notification_email : data.google_client_config.current.access_token != "" ? "admin@${var.project_id}.iam.gserviceaccount.com" : ""
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    governance-component = "database-fleet"
    random-suffix       = local.suffix
  })

  # Required Google Cloud APIs for database governance
  required_apis = [
    "cloudasset.googleapis.com",
    "workflows.googleapis.com", 
    "monitoring.googleapis.com",
    "sqladmin.googleapis.com",
    "spanner.googleapis.com",
    "bigtableadmin.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "securitycenter.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com"
  ]
}

# Get current client configuration
data "google_client_config" "current" {}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service Account for Database Governance Automation
resource "google_service_account" "governance_sa" {
  account_id   = "db-governance-sa-${local.suffix}"
  display_name = "Database Governance Service Account"
  description  = "Service account for automated database governance workflows and compliance reporting"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for governance service account
resource "google_project_iam_member" "governance_sa_roles" {
  for_each = toset([
    "roles/cloudasset.viewer",
    "roles/workflows.invoker", 
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/pubsub.publisher",
    "roles/cloudsql.viewer",
    "roles/spanner.databaseReader",
    "roles/bigtable.reader"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.service_account_email}"

  depends_on = [google_service_account.governance_sa]
}

# Additional IAM for Gemini AI integration
resource "google_project_iam_member" "governance_sa_ai_platform" {
  count = var.enable_gemini_integration ? 1 : 0
  
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${local.service_account_email}"

  depends_on = [google_service_account.governance_sa]
}

# =============================================================================
# DATA LAYER: BigQuery, Cloud Storage, Pub/Sub
# =============================================================================

# BigQuery dataset for Cloud Asset Inventory exports
resource "google_bigquery_dataset" "database_governance" {
  dataset_id  = "database_governance_${local.suffix}"
  description = "Database fleet asset inventory and governance data"
  location    = local.bigquery_location
  project     = var.project_id

  labels = local.common_labels

  # Access control for service account
  access {
    role          = "WRITER"
    user_by_email = local.service_account_email
  }

  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.access_token != "" ? data.google_client_config.current.access_token : "admin@${var.project_id}.iam.gserviceaccount.com"
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.governance_sa
  ]
}

# BigQuery table for asset inventory
resource "google_bigquery_table" "asset_inventory" {
  dataset_id = google_bigquery_dataset.database_governance.dataset_id
  table_id   = "asset_inventory"
  project    = var.project_id

  description = "Cloud Asset Inventory exports for database resources"

  labels = local.common_labels

  # Schema for Cloud Asset Inventory exports
  schema = jsonencode([
    {
      name = "name"
      type = "STRING"
      mode = "REQUIRED"
      description = "Full resource name of the asset"
    },
    {
      name = "asset_type"
      type = "STRING"
      mode = "REQUIRED"
      description = "Type of the asset (e.g., sqladmin.googleapis.com/Instance)"
    },
    {
      name = "resource"
      type = "RECORD"
      mode = "NULLABLE"
      description = "Representation of the resource"
      fields = [
        {
          name = "version"
          type = "STRING"
          mode = "NULLABLE"
        },
        {
          name = "discovery_document_uri"
          type = "STRING"
          mode = "NULLABLE"
        },
        {
          name = "discovery_name"
          type = "STRING"
          mode = "NULLABLE"
        },
        {
          name = "resource_url"
          type = "STRING"
          mode = "NULLABLE"
        },
        {
          name = "parent"
          type = "STRING"
          mode = "NULLABLE"
        },
        {
          name = "data"
          type = "JSON"
          mode = "NULLABLE"
          description = "Resource configuration data"
        }
      ]
    },
    {
      name = "ancestors"
      type = "STRING"
      mode = "REPEATED"
      description = "Ancestry path of the asset"
    }
  ])

  depends_on = [google_bigquery_dataset.database_governance]
}

# Cloud Storage bucket for compliance reports and exports
resource "google_storage_bucket" "governance_assets" {
  name          = "db-governance-assets-${local.suffix}"
  location      = var.region
  project       = var.project_id
  storage_class = var.storage_class
  
  labels = local.common_labels

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

  # Versioning for audit compliance
  versioning {
    enabled = true
  }

  # Public access prevention
  public_access_prevention = "enforced"

  depends_on = [google_project_service.required_apis]
}

# IAM for storage bucket access
resource "google_storage_bucket_iam_member" "governance_sa_storage" {
  bucket = google_storage_bucket.governance_assets.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.service_account_email}"

  depends_on = [google_storage_bucket.governance_assets]
}

# Pub/Sub topic for real-time asset change notifications
resource "google_pubsub_topic" "database_asset_changes" {
  name    = "database-asset-changes-${local.suffix}"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# SAMPLE DATABASE FLEET (Conditional)
# =============================================================================

# Cloud SQL PostgreSQL instance for governance testing
resource "google_sql_database_instance" "fleet_sql" {
  count = var.create_sample_databases ? 1 : 0
  
  name             = "fleet-sql-${local.suffix}"
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id

  deletion_protection = var.enable_deletion_protection

  settings {
    tier = "db-f1-micro"
    
    # Backup configuration for compliance
    backup_configuration {
      enabled                        = true
      start_time                     = var.database_backup_start_time
      location                      = var.region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    # IP configuration with private networking
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.governance_vpc[0].self_link
      require_ssl     = true
    }

    # Database flags for security
    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_disconnections"
      value = "on"
    }

    # Maintenance window
    maintenance_window {
      day          = 7
      hour         = 2
      update_track = "stable"
    }

    # User labels for governance tracking
    user_labels = merge(local.common_labels, {
      database-type = "postgresql"
      governance-enabled = "true"
    })
  }

  depends_on = [
    google_project_service.required_apis,
    google_compute_network.governance_vpc
  ]
}

# VPC network for private database access
resource "google_compute_network" "governance_vpc" {
  count = var.create_sample_databases ? 1 : 0
  
  name                    = "governance-vpc-${local.suffix}"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.required_apis]
}

# Subnet for database resources
resource "google_compute_subnetwork" "governance_subnet" {
  count = var.create_sample_databases ? 1 : 0
  
  name          = "governance-subnet-${local.suffix}"
  project       = var.project_id
  network       = google_compute_network.governance_vpc[0].name
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region

  depends_on = [google_compute_network.governance_vpc]
}

# Private service access for Cloud SQL
resource "google_compute_global_address" "private_service_range" {
  count = var.create_sample_databases ? 1 : 0
  
  name          = "private-service-range-${local.suffix}"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24
  network       = google_compute_network.governance_vpc[0].id

  depends_on = [google_compute_network.governance_vpc]
}

resource "google_service_networking_connection" "private_service_connection" {
  count = var.create_sample_databases ? 1 : 0
  
  network                 = google_compute_network.governance_vpc[0].id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range[0].name]

  depends_on = [
    google_compute_global_address.private_service_range,
    google_project_service.required_apis
  ]
}

# Spanner instance for distributed database governance
resource "google_spanner_instance" "fleet_spanner" {
  count = var.create_sample_databases ? 1 : 0
  
  name         = "fleet-spanner-${local.suffix}"
  config       = "regional-${var.region}"
  display_name = "Fleet Governance Spanner Instance"
  num_nodes    = var.spanner_node_count
  project      = var.project_id

  labels = merge(local.common_labels, {
    database-type = "spanner"
    governance-enabled = "true"
  })

  depends_on = [google_project_service.required_apis]
}

# Bigtable instance for NoSQL governance
resource "google_bigtable_instance" "fleet_bigtable" {
  count = var.create_sample_databases ? 1 : 0
  
  name         = "fleet-bigtable-${local.suffix}"
  project      = var.project_id
  instance_type = var.bigtable_instance_type

  labels = merge(local.common_labels, {
    database-type = "bigtable"
    governance-enabled = "true"
  })

  cluster {
    cluster_id   = "fleet-cluster"
    zone         = var.zone
    num_nodes    = var.bigtable_num_nodes
    storage_type = "SSD"
  }

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD WORKFLOWS FOR GOVERNANCE AUTOMATION
# =============================================================================

# Cloud Workflows definition for governance automation
resource "google_workflows_workflow" "database_governance" {
  count = var.enable_workflows ? 1 : 0
  
  name        = "database-governance-workflow-${local.suffix}"
  project     = var.project_id
  region      = var.region
  description = "Automated database governance and compliance checking workflow"

  labels = local.common_labels

  service_account = local.service_account_email

  # Workflow definition for governance processes
  source_contents = yamlencode({
    main = {
      params = ["input"]
      steps = [
        {
          checkAssetChange = {
            call = "http.get"
            args = {
              url = "${'https://cloudasset.googleapis.com/v1/projects/' + sys.get_env('PROJECT_ID') + '/assets'}"
              auth = {
                type = "OAuth2"
              }
            }
            result = "assets"
          }
        },
        {
          evaluateCompliance = {
            for = {
              value = "asset"
              in = "$\{assets.body.assets}"
              steps = [
                {
                  checkDatabaseSecurity = {
                    switch = [
                      {
                        condition = "$\{asset.assetType == 'sqladmin.googleapis.com/Instance'}"
                        steps = [
                          {
                            validateCloudSQL = {
                              call = "validateSQLSecurity"
                              args = {
                                instance = "$\{asset}"
                              }
                            }
                          }
                        ]
                      },
                      {
                        condition = "$\{asset.assetType == 'spanner.googleapis.com/Instance'}"
                        steps = [
                          {
                            validateSpanner = {
                              call = "validateSpannerSecurity"
                              args = {
                                instance = "$\{asset}"
                              }
                            }
                          }
                        ]
                      }
                    ]
                  }
                }
              ]
            }
          }
        },
        {
          generateReport = {
            call = "http.post"
            args = {
              url = "${'https://monitoring.googleapis.com/v3/projects/' + sys.get_env('PROJECT_ID') + '/timeSeries'}"
              auth = {
                type = "OAuth2"
              }
              body = {
                timeSeries = [
                  {
                    metric = {
                      type = "custom.googleapis.com/database/governance_score"
                    }
                    points = [
                      {
                        value = {
                          doubleValue = 0.95
                        }
                        interval = {
                          endTime = "$\{time.now()}"
                        }
                      }
                    ]
                  }
                ]
              }
            }
          }
        }
      ]
    }
    validateSQLSecurity = {
      params = ["instance"]
      steps = [
        {
          checkBackupConfig = {
            return = "$\{default(instance.resource.data.settings.backupConfiguration.enabled, false)}"
          }
        }
      ]
    }
    validateSpannerSecurity = {
      params = ["instance"]
      steps = [
        {
          checkEncryption = {
            return = "$\{instance.resource.data.encryptionConfig != null}"
          }
        }
      ]
    }
  })

  depends_on = [
    google_project_service.required_apis,
    google_service_account.governance_sa
  ]
}

# =============================================================================
# CLOUD MONITORING AND ALERTING
# =============================================================================

# Log-based metric for database compliance scoring
resource "google_logging_metric" "database_compliance_score" {
  name    = "database_compliance_score_${local.suffix}"
  project = var.project_id
  
  filter = "resource.type=\"cloud_function\" AND \"compliance\""
  
  label_extractors = {
    project_id = "EXTRACT(jsonPayload.project_id)"
    compliance_score = "EXTRACT(jsonPayload.compliance_percentage)"
  }

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Database Fleet Compliance Score"
  }

  depends_on = [google_project_service.required_apis]
}

# Log-based metric for governance events
resource "google_logging_metric" "governance_events" {
  name    = "governance_events_${local.suffix}"
  project = var.project_id
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"compliance-reporter\""

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Database Governance Events Counter"
  }

  depends_on = [google_project_service.required_apis]
}

# Notification channel for governance alerts
resource "google_monitoring_notification_channel" "governance_alerts" {
  count = var.enable_monitoring_alerts && local.notification_email != "" ? 1 : 0
  
  display_name = "Database Governance Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = local.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for governance violations
resource "google_monitoring_alert_policy" "governance_violations" {
  count = var.enable_monitoring_alerts && length(google_monitoring_notification_channel.governance_alerts) > 0 ? 1 : 0
  
  display_name = "Database Governance Violations"
  project      = var.project_id

  conditions {
    display_name = "Low compliance score"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/database_compliance_score_${local.suffix}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      duration        = "300s"
    }
  }

  notification_channels = [google_monitoring_notification_channel.governance_alerts[0].name]

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true

  depends_on = [
    google_logging_metric.database_compliance_score,
    google_monitoring_notification_channel.governance_alerts
  ]
}

# =============================================================================
# CLOUD FUNCTIONS FOR COMPLIANCE REPORTING
# =============================================================================

# Archive source code for compliance reporting function
data "archive_file" "compliance_reporter_source" {
  type        = "zip"
  output_path = "${path.module}/compliance-reporter-${local.suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
      suffix     = local.suffix
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage object for function source code
resource "google_storage_bucket_object" "compliance_reporter_source" {
  name   = "compliance-reporter-${local.suffix}.zip"
  bucket = google_storage_bucket.governance_assets.name
  source = data.archive_file.compliance_reporter_source.output_path

  depends_on = [data.archive_file.compliance_reporter_source]
}

# Cloud Function for automated compliance reporting
resource "google_cloudfunctions_function" "compliance_reporter" {
  name        = "compliance-reporter-${local.suffix}"
  project     = var.project_id
  region      = var.region
  description = "Automated compliance reporting for database governance"

  runtime     = var.cloud_function_runtime
  entry_point = "generate_compliance_report"

  available_memory_mb   = 256
  timeout              = 540
  max_instances        = 10
  service_account_email = local.service_account_email

  source_archive_bucket = google_storage_bucket.governance_assets.name
  source_archive_object = google_storage_bucket_object.compliance_reporter_source.name

  labels = local.common_labels

  # HTTP trigger
  trigger {
    https_trigger {}
  }

  # Environment variables
  environment_variables = {
    PROJECT_ID = var.project_id
    SUFFIX     = local.suffix
  }

  depends_on = [
    google_project_service.required_apis,
    google_service_account.governance_sa,
    google_storage_bucket_object.compliance_reporter_source
  ]
}

# IAM to allow unauthenticated invocation (for scheduler)
resource "google_cloudfunctions_function_iam_member" "compliance_reporter_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.compliance_reporter.name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"

  depends_on = [google_cloudfunctions_function.compliance_reporter]
}

# =============================================================================
# CLOUD SCHEDULER FOR CONTINUOUS GOVERNANCE
# =============================================================================

# Cloud Scheduler job for continuous governance checks
resource "google_cloud_scheduler_job" "governance_scheduler" {
  name        = "governance-scheduler-${local.suffix}"
  project     = var.project_id
  region      = var.region
  description = "Automated governance compliance checks every 6 hours"

  schedule  = var.governance_check_schedule
  time_zone = var.governance_scheduler_timezone

  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.compliance_reporter.https_trigger_url
    
    oidc_token {
      service_account_email = local.service_account_email
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.compliance_reporter
  ]
}

# =============================================================================
# PUB/SUB INTEGRATION FOR REAL-TIME GOVERNANCE
# =============================================================================

# Pub/Sub subscription for asset change notifications
resource "google_pubsub_subscription" "governance_automation" {
  name    = "governance-automation-${local.suffix}"
  project = var.project_id
  topic   = google_pubsub_topic.database_asset_changes.name

  # Push configuration to trigger workflows
  push_config {
    push_endpoint = var.enable_workflows && length(google_workflows_workflow.database_governance) > 0 ? "https://workflows.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.database_governance[0].name}/executions" : ""
    
    oidc_token {
      service_account_email = local.service_account_email
    }
  }

  # Message retention and acknowledgment settings
  message_retention_duration = "604800s" # 7 days
  ack_deadline_seconds      = 60

  labels = local.common_labels

  depends_on = [
    google_pubsub_topic.database_asset_changes,
    google_workflows_workflow.database_governance
  ]
}

# =============================================================================
# ASSET INVENTORY EXPORT CONFIGURATION
# =============================================================================

# Cloud Asset Inventory export (executed via local-exec provisioner)
resource "null_resource" "asset_inventory_export" {
  count = var.enable_asset_inventory_export ? 1 : 0

  triggers = {
    bigquery_table = google_bigquery_table.asset_inventory.id
    project_id     = var.project_id
  }

  provisioner "local-exec" {
    command = <<-EOT
      gcloud asset export \
        --project=${var.project_id} \
        --bigquery-table=//bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.database_governance.dataset_id}/tables/${google_bigquery_table.asset_inventory.table_id} \
        --content-type=resource \
        --asset-types="sqladmin.googleapis.com/Instance,spanner.googleapis.com/Instance,bigtableadmin.googleapis.com/Instance" || true
    EOT
  }

  depends_on = [
    google_bigquery_table.asset_inventory,
    google_project_service.required_apis
  ]
}