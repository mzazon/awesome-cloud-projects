# Outputs for Development Lifecycle Automation Infrastructure
# Provides important resource information for verification and integration

# Project and Environment Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "environment" {
  description = "The deployment environment (dev, staging, prod)"
  value       = var.environment
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
  sensitive   = false
}

# Cloud Composer Environment Outputs
output "composer_environment_name" {
  description = "Name of the Cloud Composer environment"
  value       = google_composer_environment.intelligent_devops.name
}

output "composer_environment_id" {
  description = "Full ID of the Cloud Composer environment"
  value       = google_composer_environment.intelligent_devops.id
}

output "composer_airflow_uri" {
  description = "URI of the Apache Airflow web server for the Cloud Composer environment"
  value       = google_composer_environment.intelligent_devops.config[0].airflow_uri
  sensitive   = true
}

output "composer_gcs_bucket" {
  description = "Cloud Storage bucket used by Cloud Composer for DAGs and data"
  value       = google_composer_environment.intelligent_devops.config[0].dag_gcs_prefix
}

output "composer_service_account" {
  description = "Service account email used by Cloud Composer"
  value       = google_service_account.composer_sa.email
}

# Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.dev_database.name
}

output "database_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.dev_database.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.dev_database.private_ip_address
  sensitive   = true
}

output "database_public_ip" {
  description = "Public IP address of the Cloud SQL instance (if enabled)"
  value       = length(google_sql_database_instance.dev_database.ip_address) > 0 ? google_sql_database_instance.dev_database.ip_address[0].ip_address : null
  sensitive   = true
}

output "database_name" {
  description = "Name of the application database"
  value       = google_sql_database.app_database.name
}

output "database_password" {
  description = "Password for the database root user"
  value       = random_password.db_password.result
  sensitive   = true
}

# Storage Outputs
output "workflow_assets_bucket" {
  description = "Name of the Cloud Storage bucket for workflow assets"
  value       = google_storage_bucket.workflow_assets.name
}

output "workflow_assets_bucket_url" {
  description = "Full URL of the workflow assets bucket"
  value       = google_storage_bucket.workflow_assets.url
}

# Artifact Registry Outputs
output "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository for containers"
  value       = google_artifact_registry_repository.container_repo.repository_id
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.location
}

output "container_registry_url" {
  description = "Full URL for pushing containers to Artifact Registry"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}"
}

# Datastream Outputs
output "datastream_name" {
  description = "Name of the Datastream for change data capture"
  value       = google_datastream_stream.schema_changes.stream_id
}

output "datastream_id" {
  description = "Full ID of the Datastream"
  value       = google_datastream_stream.schema_changes.id
}

output "datastream_state" {
  description = "Current state of the Datastream"
  value       = google_datastream_stream.schema_changes.state
}

output "source_connection_profile" {
  description = "ID of the source connection profile for Datastream"
  value       = google_datastream_connection_profile.source_profile.connection_profile_id
}

output "destination_connection_profile" {
  description = "ID of the destination connection profile for Datastream"
  value       = google_datastream_connection_profile.destination_profile.connection_profile_id
}

# Cloud Workflows Outputs
output "compliance_workflow_name" {
  description = "Name of the Cloud Workflow for compliance validation"
  value       = google_workflows_workflow.compliance_workflow.name
}

output "compliance_workflow_id" {
  description = "Full ID of the compliance workflow"
  value       = google_workflows_workflow.compliance_workflow.id
}

output "workflow_service_account" {
  description = "Service account email used by Cloud Workflows"
  value       = google_service_account.workflow_sa.email
}

# Security Outputs
output "binary_authorization_policy_enabled" {
  description = "Whether Binary Authorization policy is enabled"
  value       = var.enable_binary_authorization
}

output "security_attestor_name" {
  description = "Name of the Binary Authorization security attestor"
  value       = var.enable_binary_authorization ? google_binary_authorization_attestor.security_attestor[0].name : null
}

output "vulnerability_scanning_enabled" {
  description = "Whether vulnerability scanning is enabled for containers"
  value       = var.enable_vulnerability_scanning
}

# Monitoring Outputs
output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "bigquery_dataset" {
  description = "BigQuery dataset for storing DevOps metrics"
  value       = var.enable_monitoring ? google_bigquery_dataset.devops_metrics[0].dataset_id : null
}

output "notification_channel" {
  description = "Monitoring notification channel for alerts"
  value       = var.enable_monitoring && var.notification_email != "" ? google_monitoring_notification_channel.email_channel[0].name : null
}

# Network Outputs (if private IP enabled)
output "vpc_network" {
  description = "Name of the VPC network (if private IP enabled)"
  value       = var.enable_private_ip ? google_compute_network.composer_network[0].name : null
}

output "vpc_subnet" {
  description = "Name of the VPC subnet (if private IP enabled)"
  value       = var.enable_private_ip ? google_compute_subnetwork.composer_subnet[0].name : null
}

# Connection Information for External Tools
output "connection_info" {
  description = "Connection information for external tools and scripts"
  value = {
    composer_environment = google_composer_environment.intelligent_devops.name
    bucket_name         = google_storage_bucket.workflow_assets.name
    artifact_repo       = google_artifact_registry_repository.container_repo.repository_id
    database_instance   = google_sql_database_instance.dev_database.name
    database_name       = google_sql_database.app_database.name
    datastream_name     = google_datastream_stream.schema_changes.stream_id
    workflow_name       = google_workflows_workflow.compliance_workflow.name
    region             = var.region
    project_id         = var.project_id
  }
  sensitive = false
}

# Environment Variables for DAGs
output "dag_environment_variables" {
  description = "Environment variables to be used in Airflow DAGs"
  value = {
    BUCKET_NAME   = google_storage_bucket.workflow_assets.name
    PROJECT_ID    = var.project_id
    ARTIFACT_REPO = google_artifact_registry_repository.container_repo.repository_id
    REGION        = var.region
    DATABASE_HOST = google_sql_database_instance.dev_database.private_ip_address
    DATABASE_NAME = google_sql_database.app_database.name
  }
  sensitive = false
}

# Quick Start Commands
output "quick_start_commands" {
  description = "Commands for quick verification and testing"
  value = {
    check_composer_status = "gcloud composer environments describe ${google_composer_environment.intelligent_devops.name} --location=${var.region}"
    access_airflow_ui     = "echo 'Access Airflow UI at: ${google_composer_environment.intelligent_devops.config[0].airflow_uri}'"
    check_datastream      = "gcloud datastream streams describe ${google_datastream_stream.schema_changes.stream_id} --location=${var.region}"
    list_artifacts        = "gcloud artifacts repositories describe ${google_artifact_registry_repository.container_repo.repository_id} --location=${var.region}"
    execute_workflow      = "gcloud workflows execute ${google_workflows_workflow.compliance_workflow.name} --location=${var.region} --data='{\"test\": true}'"
  }
}

# Resource URLs and Links
output "resource_links" {
  description = "Direct links to important resources in Google Cloud Console"
  value = {
    composer_console_url = "https://console.cloud.google.com/composer/environments/detail/${var.region}/${google_composer_environment.intelligent_devops.name}?project=${var.project_id}"
    airflow_ui_url      = google_composer_environment.intelligent_devops.config[0].airflow_uri
    storage_console_url = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.workflow_assets.name}?project=${var.project_id}"
    database_console_url = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.dev_database.name}/overview?project=${var.project_id}"
    datastream_console_url = "https://console.cloud.google.com/datastream/streams/${var.region}/${google_datastream_stream.schema_changes.stream_id}?project=${var.project_id}"
    workflows_console_url = "https://console.cloud.google.com/workflows/workflow/${var.region}/${google_workflows_workflow.compliance_workflow.name}?project=${var.project_id}"
    artifacts_console_url = "https://console.cloud.google.com/artifacts/docker/${var.project_id}/${var.region}/${google_artifact_registry_repository.container_repo.repository_id}?project=${var.project_id}"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD, approximate)"
  value = {
    composer_environment = "~$250-400 (depending on node count and usage)"
    cloud_sql_instance  = "~$7-15 (db-f1-micro tier)"
    cloud_storage       = "~$5-20 (depending on storage usage)"
    datastream          = "~$10-50 (depending on data volume)"
    artifact_registry   = "~$0.10 per GB stored"
    workflows           = "~$0.01 per 1000 executions"
    total_estimated     = "~$270-500 per month"
    note               = "Costs vary based on usage patterns and data volumes"
  }
}

# Cleanup Commands
output "cleanup_commands" {
  description = "Commands for cleaning up resources (use with caution)"
  value = {
    delete_composer     = "gcloud composer environments delete ${google_composer_environment.intelligent_devops.name} --location=${var.region} --quiet"
    delete_datastream   = "gcloud datastream streams delete ${google_datastream_stream.schema_changes.stream_id} --location=${var.region} --quiet"
    delete_database     = "gcloud sql instances delete ${google_sql_database_instance.dev_database.name} --quiet"
    delete_bucket       = "gsutil -m rm -r gs://${google_storage_bucket.workflow_assets.name}"
    delete_artifact_repo = "gcloud artifacts repositories delete ${google_artifact_registry_repository.container_repo.repository_id} --location=${var.region} --quiet"
    delete_workflow     = "gcloud workflows delete ${google_workflows_workflow.compliance_workflow.name} --location=${var.region} --quiet"
    terraform_destroy   = "terraform destroy -auto-approve"
  }
}