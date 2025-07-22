# Outputs for GCP Multi-Region Backup Automation Infrastructure
# These outputs provide essential information for managing and monitoring the backup solution

# Project and Regional Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "primary_region" {
  description = "Primary region for backup operations"
  value       = var.primary_region
}

output "secondary_region" {
  description = "Secondary region for cross-region backup replication"
  value       = var.secondary_region
}

# Service Account Information
output "backup_service_account_email" {
  description = "Email address of the backup automation service account"
  value       = google_service_account.backup_automation.email
}

output "backup_service_account_name" {
  description = "Full resource name of the backup automation service account"
  value       = google_service_account.backup_automation.name
}

output "backup_service_account_unique_id" {
  description = "Unique ID of the backup automation service account"
  value       = google_service_account.backup_automation.unique_id
}

# Backup Vault Information
output "primary_backup_vault_id" {
  description = "ID of the primary backup vault"
  value       = google_backup_dr_backup_vault.primary.backup_vault_id
}

output "primary_backup_vault_name" {
  description = "Full resource name of the primary backup vault"
  value       = google_backup_dr_backup_vault.primary.name
}

output "primary_backup_vault_state" {
  description = "Current state of the primary backup vault"
  value       = google_backup_dr_backup_vault.primary.state
}

output "primary_backup_vault_service_account" {
  description = "Service account used by the primary backup vault"
  value       = google_backup_dr_backup_vault.primary.service_account
}

output "secondary_backup_vault_id" {
  description = "ID of the secondary backup vault"
  value       = google_backup_dr_backup_vault.secondary.backup_vault_id
}

output "secondary_backup_vault_name" {
  description = "Full resource name of the secondary backup vault"
  value       = google_backup_dr_backup_vault.secondary.name
}

output "secondary_backup_vault_state" {
  description = "Current state of the secondary backup vault"
  value       = google_backup_dr_backup_vault.secondary.state
}

output "secondary_backup_vault_service_account" {
  description = "Service account used by the secondary backup vault"
  value       = google_backup_dr_backup_vault.secondary.service_account
}

# Workflow Information
output "workflow_name" {
  description = "Name of the backup orchestration workflow"
  value       = google_workflows_workflow.backup_orchestration.name
}

output "workflow_id" {
  description = "Full resource ID of the backup orchestration workflow"
  value       = google_workflows_workflow.backup_orchestration.id
}

output "workflow_state" {
  description = "Current state of the backup orchestration workflow"
  value       = google_workflows_workflow.backup_orchestration.state
}

output "workflow_revision_id" {
  description = "Current revision ID of the backup orchestration workflow"
  value       = google_workflows_workflow.backup_orchestration.revision_id
}

output "workflow_execution_url" {
  description = "URL for manually executing the backup workflow"
  value       = "https://console.cloud.google.com/workflows/workflow/${var.primary_region}/${google_workflows_workflow.backup_orchestration.name}/executions?project=${var.project_id}"
}

# Scheduler Information
output "daily_backup_job_name" {
  description = "Name of the daily backup scheduler job"
  value       = google_cloud_scheduler_job.daily_backup.name
}

output "daily_backup_job_id" {
  description = "Full resource ID of the daily backup scheduler job"
  value       = google_cloud_scheduler_job.daily_backup.id
}

output "daily_backup_schedule" {
  description = "Cron schedule for daily backup executions"
  value       = google_cloud_scheduler_job.daily_backup.schedule
}

output "validation_job_name" {
  description = "Name of the weekly validation scheduler job"
  value       = google_cloud_scheduler_job.weekly_validation.name
}

output "validation_job_id" {
  description = "Full resource ID of the weekly validation scheduler job"
  value       = google_cloud_scheduler_job.weekly_validation.id
}

output "validation_schedule" {
  description = "Cron schedule for weekly validation executions"
  value       = google_cloud_scheduler_job.weekly_validation.schedule
}

# Test Instance Information (conditional outputs)
output "test_instance_name" {
  description = "Name of the test compute instance (if created)"
  value       = var.create_test_resources ? google_compute_instance.test_instance[0].name : null
}

output "test_instance_zone" {
  description = "Zone of the test compute instance (if created)"
  value       = var.create_test_resources ? google_compute_instance.test_instance[0].zone : null
}

output "test_instance_id" {
  description = "Full resource ID of the test compute instance (if created)"
  value       = var.create_test_resources ? google_compute_instance.test_instance[0].id : null
}

output "test_instance_self_link" {
  description = "Self link of the test compute instance (if created)"
  value       = var.create_test_resources ? google_compute_instance.test_instance[0].self_link : null
}

output "test_data_disk_name" {
  description = "Name of the test data disk (if created)"
  value       = var.create_test_resources ? google_compute_disk.test_data_disk[0].name : null
}

output "test_data_disk_id" {
  description = "Full resource ID of the test data disk (if created)"
  value       = var.create_test_resources ? google_compute_disk.test_data_disk[0].id : null
}

# Monitoring Information
output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "backup_failure_alert_policy_id" {
  description = "ID of the backup failure alert policy (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.backup_failure_alert[0].id : null
}

output "email_notification_channel_id" {
  description = "ID of the email notification channel (if email configured)"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email_alert[0].id : null
}

output "notification_email" {
  description = "Email address configured for backup alerts"
  value       = var.notification_email
  sensitive   = true
}

# Configuration Information
output "backup_retention_days" {
  description = "Configured backup retention period in days"
  value       = var.backup_retention_days
}

output "backup_retention_seconds" {
  description = "Configured backup retention period in seconds"
  value       = local.backup_retention_seconds
}

output "schedule_timezone" {
  description = "Timezone used for backup scheduling"
  value       = var.schedule_timezone
}

# Resource Naming Information
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

output "environment" {
  description = "Environment tag applied to resources"
  value       = var.environment
}

# API Information
output "enabled_apis" {
  description = "List of APIs enabled for the backup solution"
  value       = var.required_apis
}

# Useful URLs and Commands
output "cloud_console_backup_vaults_url" {
  description = "URL to view backup vaults in the Google Cloud Console"
  value       = "https://console.cloud.google.com/backup-dr/backup-vaults?project=${var.project_id}"
}

output "cloud_console_workflows_url" {
  description = "URL to view workflows in the Google Cloud Console"
  value       = "https://console.cloud.google.com/workflows?project=${var.project_id}"
}

output "cloud_console_scheduler_url" {
  description = "URL to view Cloud Scheduler jobs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
}

output "cloud_console_monitoring_url" {
  description = "URL to view Cloud Monitoring in the Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

# CLI Commands for Management
output "workflow_execution_command" {
  description = "gcloud command to manually execute the backup workflow"
  value = join(" ", [
    "gcloud workflows run",
    google_workflows_workflow.backup_orchestration.name,
    "--location=${var.primary_region}",
    "--data='{\"backup_type\": \"manual_execution\"}'"
  ])
}

output "view_workflow_executions_command" {
  description = "gcloud command to view workflow execution history"
  value = join(" ", [
    "gcloud workflows executions list",
    "--workflow=${google_workflows_workflow.backup_orchestration.name}",
    "--location=${var.primary_region}",
    "--limit=10"
  ])
}

output "backup_vault_list_command" {
  description = "gcloud command to list backup vaults in both regions"
  value = join(" && ", [
    "gcloud backup-dr backup-vaults list --location=${var.primary_region}",
    "gcloud backup-dr backup-vaults list --location=${var.secondary_region}"
  ])
}

# Summary Information
output "deployment_summary" {
  description = "Summary of the deployed backup automation infrastructure"
  value = {
    project_id                = var.project_id
    primary_region           = var.primary_region
    secondary_region         = var.secondary_region
    backup_retention_days    = var.backup_retention_days
    test_resources_created   = var.create_test_resources
    monitoring_enabled       = var.enable_monitoring
    email_notifications      = var.notification_email != ""
    daily_backup_schedule    = var.backup_schedule
    validation_schedule      = var.validation_schedule
    workflow_name           = google_workflows_workflow.backup_orchestration.name
    primary_vault_id        = google_backup_dr_backup_vault.primary.backup_vault_id
    secondary_vault_id      = google_backup_dr_backup_vault.secondary.backup_vault_id
    service_account_email   = google_service_account.backup_automation.email
  }
}