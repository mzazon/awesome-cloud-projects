# Project Information
output "project_id" {
  description = "The GCP project ID"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where resources were created"
  value       = var.zone
}

# Cloud Workstations Outputs
output "workstation_cluster_name" {
  description = "Name of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.db_migration_cluster.workstation_cluster_id
}

output "workstation_cluster_id" {
  description = "Full resource ID of the Cloud Workstations cluster"
  value       = google_workstations_workstation_cluster.db_migration_cluster.id
}

output "workstation_config_name" {
  description = "Name of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.db_migration_config.workstation_config_id
}

output "workstation_config_id" {
  description = "Full resource ID of the Cloud Workstations configuration"
  value       = google_workstations_workstation_config.db_migration_config.id
}

output "workstation_service_account_email" {
  description = "Email address of the workstation service account"
  value       = google_service_account.workstation_service_account.email
}

# Database Migration Service Outputs
output "source_connection_profile_id" {
  description = "ID of the source database connection profile"
  value       = google_database_migration_service_connection_profile.source_profile.connection_profile_id
}

output "target_connection_profile_id" {
  description = "ID of the target database connection profile"
  value       = google_database_migration_service_connection_profile.target_profile.connection_profile_id
}

# Cloud SQL Outputs
output "target_database_instance_name" {
  description = "Name of the target Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.name
}

output "target_database_connection_name" {
  description = "Connection name of the target Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.connection_name
}

output "target_database_private_ip" {
  description = "Private IP address of the target Cloud SQL instance"
  value       = google_sql_database_instance.target_mysql.private_ip_address
}

output "target_database_name" {
  description = "Name of the target database"
  value       = google_sql_database.target_database.name
}

# Secret Manager Outputs
output "database_credentials_secret_id" {
  description = "Secret Manager secret ID for database credentials"
  value       = google_secret_manager_secret.db_credentials.secret_id
}

output "database_credentials_secret_name" {
  description = "Full resource name of the database credentials secret"
  value       = google_secret_manager_secret.db_credentials.name
}

# Artifact Registry Outputs
output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.db_migration_images.name
}

output "artifact_registry_repository_url" {
  description = "URL of the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo_name}"
}

# IAM Outputs
output "custom_role_name" {
  description = "Name of the custom IAM role for database migration developers"
  value       = google_project_iam_custom_role.database_migration_developer.name
}

output "custom_role_id" {
  description = "ID of the custom IAM role for database migration developers"
  value       = google_project_iam_custom_role.database_migration_developer.role_id
}

# Cloud Build Outputs
output "cloud_build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = var.enable_cloud_build ? google_cloudbuild_trigger.db_migration_pipeline[0].name : null
}

output "cloud_build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = var.enable_cloud_build ? google_cloudbuild_trigger.db_migration_pipeline[0].trigger_id : null
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = google_monitoring_dashboard.db_migration_dashboard.id
}

output "monitoring_notification_channel_name" {
  description = "Name of the monitoring notification channel"
  value       = length(var.migration_team_members) > 0 ? google_monitoring_notification_channel.email_channel[0].name : null
}

output "alert_policy_name" {
  description = "Name of the alert policy for migration job failures"
  value       = var.enable_audit_logging ? google_monitoring_alert_policy.migration_job_failure[0].name : null
}

# Logging Outputs
output "audit_logs_bucket_name" {
  description = "Name of the audit logs storage bucket"
  value       = var.enable_audit_logging ? google_storage_bucket.audit_logs[0].name : null
}

output "audit_logs_bucket_url" {
  description = "URL of the audit logs storage bucket"
  value       = var.enable_audit_logging ? google_storage_bucket.audit_logs[0].url : null
}

output "audit_log_sink_name" {
  description = "Name of the audit log sink"
  value       = var.enable_audit_logging ? google_logging_project_sink.audit_sink[0].name : null
}

# Resource Identifiers
output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Network Information
output "network_name" {
  description = "Name of the VPC network used"
  value       = data.google_compute_network.network.name
}

output "subnet_name" {
  description = "Name of the subnet used"
  value       = data.google_compute_subnetwork.subnet.name
}

# Usage Instructions
output "workstation_creation_command" {
  description = "Command to create a workstation instance"
  value = <<-EOT
gcloud workstations create migration-dev-workspace \
  --location=${var.region} \
  --cluster=${google_workstations_workstation_cluster.db_migration_cluster.workstation_cluster_id} \
  --config=${google_workstations_workstation_config.db_migration_config.workstation_config_id}
EOT
}

output "workstation_start_command" {
  description = "Command to start a workstation instance"
  value = <<-EOT
gcloud workstations start migration-dev-workspace \
  --location=${var.region} \
  --cluster=${google_workstations_workstation_cluster.db_migration_cluster.workstation_cluster_id} \
  --config=${google_workstations_workstation_config.db_migration_config.workstation_config_id}
EOT
}

output "workstation_access_command" {
  description = "Command to access a workstation instance via SSH tunnel"
  value = <<-EOT
gcloud workstations start-tcp-tunnel migration-dev-workspace \
  --location=${var.region} \
  --cluster=${google_workstations_workstation_cluster.db_migration_cluster.workstation_cluster_id} \
  --config=${google_workstations_workstation_config.db_migration_config.workstation_config_id} \
  --port=22 \
  --local-port=2222
EOT
}

output "migration_job_creation_command" {
  description = "Command to create a Database Migration Service job"
  value = <<-EOT
gcloud database-migration migration-jobs create mysql-migration-job \
  --location=${var.region} \
  --source=${google_database_migration_service_connection_profile.source_profile.connection_profile_id} \
  --destination=${google_database_migration_service_connection_profile.target_profile.connection_profile_id} \
  --type=CONTINUOUS
EOT
}

output "container_build_command" {
  description = "Command to build and push custom container image"
  value = <<-EOT
docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo_name}/migration-workstation:latest .
docker push ${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_registry_repo_name}/migration-workstation:latest
EOT
}