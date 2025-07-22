# Database Disaster Recovery with Backup and DR Service and Cloud SQL
# This configuration creates a comprehensive disaster recovery solution for Cloud SQL
# using Google Cloud's Backup and DR Service, cross-region replicas, and automated orchestration

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

locals {
  # Generate unique names for resources
  db_instance_name  = var.db_instance_name != "" ? var.db_instance_name : "${var.environment}-db-${random_id.suffix.hex}"
  dr_replica_name   = "${local.db_instance_name}-dr"
  backup_vault_primary = "backup-vault-primary-${random_id.suffix.hex}"
  backup_vault_secondary = "backup-vault-secondary-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.primary_region
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "backupdr.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# VPC network data source (uses default or specified network)
data "google_compute_network" "vpc_network" {
  name    = var.network_name
  project = var.project_id
}

# Create storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "dr-functions-${var.project_id}-${random_id.suffix.hex}"
  location = var.primary_region
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
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
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/dr-functions.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
      primary_region = var.primary_region
      secondary_region = var.secondary_region
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to storage bucket
resource "google_storage_bucket_object" "function_zip" {
  name   = "dr-functions-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

#------------------------------------------------------------------------------
# IAM SERVICE ACCOUNTS AND PERMISSIONS
#------------------------------------------------------------------------------

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "dr-function-sa-${random_id.suffix.hex}"
  display_name = "Disaster Recovery Function Service Account"
  description  = "Service account for disaster recovery orchestration functions"
  
  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "dr-scheduler-sa-${random_id.suffix.hex}"
  display_name = "Disaster Recovery Scheduler Service Account"
  description  = "Service account for disaster recovery scheduled jobs"
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for function service account
resource "google_project_iam_member" "function_roles" {
  for_each = toset([
    "roles/cloudsql.admin",
    "roles/backupdr.admin",
    "roles/pubsub.editor",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/cloudfunctions.invoker"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM roles for scheduler service account
resource "google_project_iam_member" "scheduler_roles" {
  for_each = toset([
    "roles/cloudfunctions.invoker",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# Allow Backup and DR service to access Cloud SQL
resource "google_project_iam_member" "backup_service_sql" {
  project = var.project_id
  role    = "roles/cloudsql.serviceAgent"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-backupdr.iam.gserviceaccount.com"
  
  depends_on = [google_project_service.required_apis]
}

#------------------------------------------------------------------------------
# CLOUD SQL INSTANCES
#------------------------------------------------------------------------------

# Primary Cloud SQL instance with high availability
resource "google_sql_database_instance" "primary" {
  name             = local.db_instance_name
  database_version = var.database_version
  region           = var.primary_region
  
  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.storage_size_gb
    disk_autoresize   = true
    
    backup_configuration {
      enabled                        = true
      start_time                     = var.backup_start_time
      location                      = var.primary_region
      point_in_time_recovery_enabled = var.enable_binary_logging
      backup_retention_settings {
        retained_backups = var.backup_retention_days
        retention_unit   = "COUNT"
      }
      transaction_log_retention_days = 7
      binary_log_enabled            = var.enable_binary_logging
    }
    
    ip_configuration {
      ipv4_enabled                                  = !var.enable_private_ip
      private_network                              = var.enable_private_ip ? data.google_compute_network.vpc_network.id : null
      enable_private_path_for_google_cloud_services = var.enable_private_ip
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    database_flags {
      name  = "max_connections"
      value = var.max_connections
    }
    
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    maintenance_window {
      day          = 7  # Sunday
      hour         = 4  # 4 AM UTC
      update_track = "stable"
    }
    
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }
  
  deletion_protection = var.enable_deletion_protection
  
  lifecycle {
    prevent_destroy = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Disaster recovery replica in secondary region
resource "google_sql_database_instance" "dr_replica" {
  name                 = local.dr_replica_name
  database_version     = var.database_version
  region               = var.secondary_region
  master_instance_name = google_sql_database_instance.primary.name
  
  replica_configuration {
    failover_target = true
  }
  
  settings {
    tier              = var.db_tier
    availability_type = "REGIONAL"
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    
    ip_configuration {
      ipv4_enabled                                  = !var.enable_private_ip
      private_network                              = var.enable_private_ip ? data.google_compute_network.vpc_network.id : null
      enable_private_path_for_google_cloud_services = var.enable_private_ip
    }
    
    database_flags {
      name  = "max_connections"
      value = var.max_connections
    }
    
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
  }
  
  depends_on = [google_sql_database_instance.primary]
}

# Create test database for validation
resource "google_sql_database" "test_db" {
  name     = "test_dr_db"
  instance = google_sql_database_instance.primary.name
  
  depends_on = [google_sql_database_instance.primary]
}

#------------------------------------------------------------------------------
# BACKUP AND DR SERVICE
#------------------------------------------------------------------------------

# Primary backup vault
resource "google_backup_dr_backup_vault" "primary_vault" {
  location                                    = var.primary_region
  backup_vault_id                            = local.backup_vault_primary
  backup_minimum_enforced_retention_duration = "${var.backup_retention_days * 24 * 3600}s"
  description                                = "Primary backup vault for disaster recovery"
  access_restriction                         = "WITHIN_ORGANIZATION"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Secondary backup vault
resource "google_backup_dr_backup_vault" "secondary_vault" {
  location                                    = var.secondary_region
  backup_vault_id                            = local.backup_vault_secondary
  backup_minimum_enforced_retention_duration = "${var.backup_retention_days * 24 * 3600}s"
  description                                = "Secondary backup vault for cross-region DR"
  access_restriction                         = "WITHIN_ORGANIZATION"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Backup plan for primary instance
resource "google_backup_dr_backup_plan" "primary_backup_plan" {
  location       = var.primary_region
  backup_plan_id = "backup-plan-${local.db_instance_name}"
  resource_type  = "sqladmin.googleapis.com/Instance"
  backup_vault   = google_backup_dr_backup_vault.primary_vault.id
  description    = "Daily backup plan for primary SQL instance"
  
  backup_rules {
    rule_id               = "daily-backup"
    backup_retention_days = var.backup_retention_days
    
    standard_schedule {
      recurrence_type = "DAILY"
      time_zone      = "UTC"
      
      backup_window {
        start_hour_of_day = 2
        end_hour_of_day   = 6
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_backup_dr_backup_vault.primary_vault]
}

# Backup plan association for primary instance
resource "google_backup_dr_backup_plan_association" "primary_association" {
  location        = var.primary_region
  backup_plan_id  = google_backup_dr_backup_plan.primary_backup_plan.backup_plan_id
  resource        = "projects/${var.project_id}/instances/${google_sql_database_instance.primary.name}"
  resource_type   = "sqladmin.googleapis.com/Instance"
  
  depends_on = [
    google_backup_dr_backup_plan.primary_backup_plan,
    google_sql_database_instance.primary
  ]
}

#------------------------------------------------------------------------------
# PUB/SUB FOR ALERTING
#------------------------------------------------------------------------------

# Pub/Sub topic for disaster recovery alerts
resource "google_pubsub_topic" "dr_alerts" {
  name = "disaster-recovery-alerts-${random_id.suffix.hex}"
  
  message_retention_duration = "86400s" # 24 hours
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for alert processing
resource "google_pubsub_subscription" "alert_processor" {
  name  = "dr-alert-processor-${random_id.suffix.hex}"
  topic = google_pubsub_topic.dr_alerts.id
  
  ack_deadline_seconds = 60
  
  push_config {
    push_endpoint = google_cloudfunctions2_function.dr_orchestrator.service_config[0].uri
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  labels = local.common_labels
  
  depends_on = [google_cloudfunctions2_function.dr_orchestrator]
}

#------------------------------------------------------------------------------
# CLOUD FUNCTIONS
#------------------------------------------------------------------------------

# Disaster recovery orchestration function
resource "google_cloudfunctions2_function" "dr_orchestrator" {
  name        = "disaster-recovery-orchestrator-${random_id.suffix.hex}"
  location    = var.primary_region
  description = "Orchestrates disaster recovery procedures for Cloud SQL"
  
  build_config {
    runtime     = "python312"
    entry_point = "orchestrate_disaster_recovery"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout_seconds
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      PRIMARY_REGION   = var.primary_region
      SECONDARY_REGION = var.secondary_region
      PRIMARY_INSTANCE = google_sql_database_instance.primary.name
      DR_REPLICA       = google_sql_database_instance.dr_replica.name
      PUBSUB_TOPIC     = google_pubsub_topic.dr_alerts.name
    }
  }
  
  event_trigger {
    trigger_region = var.primary_region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.dr_alerts.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_zip,
    google_project_iam_member.function_roles
  ]
}

# Backup validation function
resource "google_cloudfunctions2_function" "backup_validator" {
  name        = "backup-validator-${random_id.suffix.hex}"
  location    = var.primary_region
  description = "Validates backup integrity and DR readiness"
  
  build_config {
    runtime     = "python312"
    entry_point = "validate_backups"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 5
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 300
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      PROJECT_ID       = var.project_id
      PRIMARY_INSTANCE = google_sql_database_instance.primary.name
      DR_REPLICA       = google_sql_database_instance.dr_replica.name
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_zip,
    google_project_iam_member.function_roles
  ]
}

#------------------------------------------------------------------------------
# CLOUD SCHEDULER
#------------------------------------------------------------------------------

# Scheduled job for disaster recovery monitoring
resource "google_cloud_scheduler_job" "dr_monitoring" {
  name        = "dr-monitoring-${random_id.suffix.hex}"
  description = "Monitor database health and trigger DR procedures if needed"
  schedule    = var.monitoring_schedule
  time_zone   = "UTC"
  region      = var.primary_region
  
  http_target {
    uri         = google_cloudfunctions2_function.dr_orchestrator.service_config[0].uri
    http_method = "POST"
    
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience             = google_cloudfunctions2_function.dr_orchestrator.service_config[0].uri
    }
    
    body = base64encode(jsonencode({
      action = "health_check"
      source = "scheduler"
      timestamp = timestamp()
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.dr_orchestrator,
    google_project_iam_member.scheduler_roles
  ]
}

# Scheduled job for backup validation
resource "google_cloud_scheduler_job" "backup_validation" {
  name        = "backup-validation-${random_id.suffix.hex}"
  description = "Weekly validation of backup integrity"
  schedule    = "0 4 * * 1" # Every Monday at 4 AM UTC
  time_zone   = "UTC"
  region      = var.primary_region
  
  http_target {
    uri         = google_cloudfunctions2_function.backup_validator.service_config[0].uri
    http_method = "POST"
    
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience             = google_cloudfunctions2_function.backup_validator.service_config[0].uri
    }
    
    body = base64encode(jsonencode({
      action = "validate_backups"
      test_mode = true
    }))
    
    headers = {
      "Content-Type" = "application/json"
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.backup_validator,
    google_project_iam_member.scheduler_roles
  ]
}

#------------------------------------------------------------------------------
# MONITORING AND ALERTING
#------------------------------------------------------------------------------

# Alert policy for Cloud SQL instance health
resource "google_monitoring_alert_policy" "sql_instance_down" {
  display_name = "Cloud SQL Primary Instance Health Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Cloud SQL instance down"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.primary.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  notification_channels = var.alert_notification_channels
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.primary
  ]
}

# Alert policy for backup failures
resource "google_monitoring_alert_policy" "backup_failure" {
  display_name = "Cloud SQL Backup Failure Alert"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Backup operation failed"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/backup/success\""
      duration        = "300s"
      comparison      = "COMPARISON_EQUAL"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "3600s"
  }
  
  notification_channels = var.alert_notification_channels
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.primary
  ]
}