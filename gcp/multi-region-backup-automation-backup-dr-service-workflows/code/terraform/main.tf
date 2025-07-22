# Multi-Region Backup Automation Infrastructure
# This configuration creates a comprehensive backup automation system using
# GCP Backup and DR Service, Cloud Workflows, and Cloud Scheduler

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with random suffix
  resource_suffix = random_id.suffix.hex
  
  # Backup vault names
  backup_vault_primary   = "${var.resource_prefix}-primary-${local.resource_suffix}"
  backup_vault_secondary = "${var.resource_prefix}-secondary-${local.resource_suffix}"
  
  # Service account and workflow names
  service_account_id = "${var.resource_prefix}-sa-${local.resource_suffix}"
  workflow_name      = "${var.resource_prefix}-workflow-${local.resource_suffix}"
  
  # Scheduler job names
  backup_scheduler_job    = "${var.resource_prefix}-daily-${local.resource_suffix}"
  validation_scheduler_job = "${var.resource_prefix}-validation-${local.resource_suffix}"
  
  # Test instance names (if enabled)
  test_instance_name = "${var.resource_prefix}-test-${local.resource_suffix}"
  test_disk_name     = "${var.resource_prefix}-test-disk-${local.resource_suffix}"
  
  # Determine test instance zone
  test_zone = var.test_instance_zone != "" ? var.test_instance_zone : "${var.primary_region}-a"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment      = var.environment
    solution         = "backup-automation"
    managed-by       = "terraform"
    primary-region   = var.primary_region
    secondary-region = var.secondary_region
  })
  
  # Calculate retention duration in seconds
  backup_retention_seconds = var.backup_retention_days * 24 * 3600
}

# Enable required APIs for the backup automation solution
resource "google_project_service" "required_apis" {
  for_each = toset(var.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when this resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# IAM Service Account for Backup Automation
# This service account will be used by workflows and scheduler jobs
resource "google_service_account" "backup_automation" {
  account_id   = local.service_account_id
  display_name = "Backup Automation Service Account"
  description  = var.service_account_description
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the backup automation service account
# These permissions allow the service account to manage backup operations
resource "google_project_iam_member" "backup_automation_roles" {
  for_each = toset([
    "roles/backupdr.admin",           # Full access to Backup and DR Service
    "roles/workflows.invoker",        # Ability to invoke workflows
    "roles/compute.instanceAdmin.v1", # Manage compute instances for testing
    "roles/storage.admin",            # Manage storage for backup operations
    "roles/monitoring.editor",        # Create monitoring resources
    "roles/logging.logWriter"         # Write logs for monitoring
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.backup_automation.email}"
  
  depends_on = [google_service_account.backup_automation]
}

# Primary region backup vault
# This vault stores primary backups and enforces retention policies
resource "google_backup_dr_backup_vault" "primary" {
  location                                = var.primary_region
  backup_vault_id                        = local.backup_vault_primary
  description                            = "Primary backup vault for automated multi-region backup solution"
  backup_minimum_enforced_retention_duration = "${local.backup_retention_seconds}s"
  
  # Security and access configuration
  access_restriction              = var.backup_vault_access_restriction
  ignore_inactive_datasources     = true
  ignore_backup_plan_references   = true
  allow_missing                   = true
  force_update                    = true
  
  # Resource labels
  labels = merge(local.common_labels, {
    vault-type = "primary"
    region     = var.primary_region
  })
  
  # Annotations for additional metadata
  annotations = {
    purpose          = "primary-backup-storage"
    automation-level = "fully-automated"
    retention-days   = tostring(var.backup_retention_days)
  }
  
  depends_on = [google_project_service.required_apis]
}

# Secondary region backup vault
# This vault stores cross-region backup copies for disaster recovery
resource "google_backup_dr_backup_vault" "secondary" {
  location                                = var.secondary_region
  backup_vault_id                        = local.backup_vault_secondary
  description                            = "Secondary backup vault for cross-region disaster recovery"
  backup_minimum_enforced_retention_duration = "${local.backup_retention_seconds}s"
  
  # Security and access configuration  
  access_restriction              = var.backup_vault_access_restriction
  ignore_inactive_datasources     = true
  ignore_backup_plan_references   = true
  allow_missing                   = true
  force_update                    = true
  
  # Resource labels
  labels = merge(local.common_labels, {
    vault-type = "secondary"
    region     = var.secondary_region
  })
  
  # Annotations for additional metadata
  annotations = {
    purpose          = "disaster-recovery-backup-storage"
    automation-level = "fully-automated"
    retention-days   = tostring(var.backup_retention_days)
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Workflow for backup orchestration
# This workflow manages multi-region backup operations with error handling
resource "google_workflows_workflow" "backup_orchestration" {
  name            = local.workflow_name
  region          = var.primary_region
  description     = "Automated workflow for multi-region backup operations and disaster recovery"
  service_account = google_service_account.backup_automation.id
  
  # Workflow configuration
  call_log_level          = var.workflow_call_log_level
  execution_history_level = var.workflow_execution_history_level
  
  # Resource labels
  labels = merge(local.common_labels, {
    component = "backup-orchestration"
    region    = var.primary_region
  })
  
  # Environment variables for workflow execution
  user_env_vars = {
    PROJECT_ID               = var.project_id
    PRIMARY_REGION          = var.primary_region
    SECONDARY_REGION        = var.secondary_region
    BACKUP_VAULT_PRIMARY    = local.backup_vault_primary
    BACKUP_VAULT_SECONDARY  = local.backup_vault_secondary
    TEST_INSTANCE_NAME      = var.create_test_resources ? local.test_instance_name : ""
    TEST_INSTANCE_ZONE      = var.create_test_resources ? local.test_zone : ""
  }
  
  # Workflow definition with comprehensive backup orchestration logic
  source_contents = templatefile("${path.module}/workflow-definition.yaml", {
    project_id              = var.project_id
    primary_region         = var.primary_region
    secondary_region       = var.secondary_region
    backup_vault_primary   = local.backup_vault_primary
    backup_vault_secondary = local.backup_vault_secondary
    test_instance_name     = var.create_test_resources ? local.test_instance_name : ""
    test_instance_zone     = var.create_test_resources ? local.test_zone : ""
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.backup_automation,
    google_project_iam_member.backup_automation_roles,
    google_backup_dr_backup_vault.primary,
    google_backup_dr_backup_vault.secondary
  ]
}

# Cloud Scheduler job for daily backup execution
# This job triggers the backup workflow on a scheduled basis
resource "google_cloud_scheduler_job" "daily_backup" {
  name         = local.backup_scheduler_job
  region       = var.primary_region
  description  = "Daily backup automation job for multi-region backup operations"
  schedule     = var.backup_schedule
  time_zone    = var.schedule_timezone
  
  # Retry configuration for reliability
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "10s"
    max_backoff_duration = "60s"
    max_doublings        = 3
  }
  
  # HTTP target configuration to invoke the workflow
  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.primary_region}/workflows/${local.workflow_name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    # Request body with backup parameters
    body = base64encode(jsonencode({
      argument = jsonencode({
        backup_type = "scheduled_daily"
        retention_days = var.backup_retention_days
        timestamp = "$${timestamp}"
      })
    }))
    
    # OAuth authentication using the service account
    oauth_token {
      service_account_email = google_service_account.backup_automation.email
      scope                = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_workflows_workflow.backup_orchestration,
    google_project_iam_member.backup_automation_roles
  ]
}

# Cloud Scheduler job for weekly backup validation
# This job performs validation checks on backup integrity and recovery capabilities
resource "google_cloud_scheduler_job" "weekly_validation" {
  name         = local.validation_scheduler_job
  region       = var.primary_region
  description  = "Weekly backup validation job for testing backup integrity and recovery"
  schedule     = var.validation_schedule
  time_zone    = var.schedule_timezone
  
  # Retry configuration for reliability
  retry_config {
    retry_count          = 2
    max_retry_duration   = "600s"
    min_backoff_duration = "30s"
    max_backoff_duration = "120s"
    max_doublings        = 2
  }
  
  # HTTP target configuration to invoke the workflow
  http_target {
    http_method = "POST"
    uri         = "https://workflowexecutions.googleapis.com/v1/projects/${var.project_id}/locations/${var.primary_region}/workflows/${local.workflow_name}/executions"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    # Request body with validation parameters
    body = base64encode(jsonencode({
      argument = jsonencode({
        backup_type = "validation_weekly"
        test_recovery = true
        validate_cross_region = true
        timestamp = "$${timestamp}"
      })
    }))
    
    # OAuth authentication using the service account
    oauth_token {
      service_account_email = google_service_account.backup_automation.email
      scope                = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
  
  depends_on = [
    google_workflows_workflow.backup_orchestration,
    google_project_iam_member.backup_automation_roles
  ]
}

# Test compute instance for backup validation (conditional)
# This instance serves as a test workload for backup operations
resource "google_compute_instance" "test_instance" {
  count = var.create_test_resources ? 1 : 0
  
  name         = local.test_instance_name
  machine_type = var.test_instance_machine_type
  zone         = local.test_zone
  
  # Boot disk configuration
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-standard"
    }
  }
  
  # Network configuration
  network_interface {
    network = "default"
    
    # Ephemeral external IP for testing
    access_config {}
  }
  
  # Resource labels and metadata
  labels = merge(local.common_labels, {
    component = "test-workload"
    zone      = local.test_zone
  })
  
  metadata = {
    backup-policy     = "critical"
    environment      = var.environment
    backup-schedule  = "daily"
    startup-script   = "#!/bin/bash\necho 'Test instance for backup automation' > /var/log/test-instance.log"
  }
  
  # Service account for the instance
  service_account {
    email  = google_service_account.backup_automation.email
    scopes = ["cloud-platform"]
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.backup_automation
  ]
}

# Additional persistent disk for backup testing (conditional)
# This disk provides additional test data for backup validation
resource "google_compute_disk" "test_data_disk" {
  count = var.create_test_resources ? 1 : 0
  
  name = local.test_disk_name
  zone = local.test_zone
  size = var.test_disk_size_gb
  type = "pd-standard"
  
  # Resource labels
  labels = merge(local.common_labels, {
    component = "test-storage"
    zone      = local.test_zone
  })
  
  depends_on = [google_project_service.required_apis]
}

# Attach the test data disk to the test instance (conditional)
resource "google_compute_attached_disk" "test_disk_attachment" {
  count = var.create_test_resources ? 1 : 0
  
  disk     = google_compute_disk.test_data_disk[0].id
  instance = google_compute_instance.test_instance[0].id
  
  depends_on = [
    google_compute_instance.test_instance,
    google_compute_disk.test_data_disk
  ]
}

# Create workflow definition file locally for reference
resource "local_file" "workflow_definition" {
  filename = "${path.module}/workflow-definition.yaml"
  content = templatefile("${path.module}/templates/workflow-definition.yaml.tpl", {
    project_id              = var.project_id
    primary_region         = var.primary_region
    secondary_region       = var.secondary_region
    backup_vault_primary   = local.backup_vault_primary
    backup_vault_secondary = local.backup_vault_secondary
    test_instance_name     = var.create_test_resources ? local.test_instance_name : ""
    test_instance_zone     = var.create_test_resources ? local.test_zone : ""
  })
}

# Monitoring alert policy for backup failures (conditional)
resource "google_monitoring_alert_policy" "backup_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Backup Workflow Failures - ${var.environment}"
  
  documentation {
    content   = "Alert triggered when backup workflows fail execution. This requires immediate attention to ensure data protection continuity."
    mime_type = "text/markdown"
  }
  
  # Alert condition for workflow failures
  conditions {
    display_name = "Workflow execution failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"workflows.googleapis.com/Workflow\" AND protoPayload.methodName=\"google.cloud.workflows.executions.v1.Executions.CreateExecution\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Alert strategy
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  combiner = "OR"
  enabled  = true
  
  depends_on = [google_project_service.required_apis]
}

# Create notification channel for email alerts (conditional)
resource "google_monitoring_notification_channel" "email_alert" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Backup Alerts Email - ${var.environment}"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Update alert policy to use notification channel
resource "google_monitoring_alert_policy" "backup_failure_alert_with_notification" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Backup Workflow Failures with Email - ${var.environment}"
  
  documentation {
    content   = "Alert triggered when backup workflows fail execution. Email notifications will be sent to ${var.notification_email}."
    mime_type = "text/markdown"
  }
  
  # Alert condition for workflow failures
  conditions {
    display_name = "Workflow execution failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"workflows.googleapis.com/Workflow\" AND protoPayload.methodName=\"google.cloud.workflows.executions.v1.Executions.CreateExecution\""
      comparison      = "COMPARISON_GT" 
      threshold_value = 0
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Notification channels
  notification_channels = [
    google_monitoring_notification_channel.email_alert[0].id
  ]
  
  # Alert strategy
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  combiner = "OR"
  enabled  = true
  
  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.email_alert
  ]
}