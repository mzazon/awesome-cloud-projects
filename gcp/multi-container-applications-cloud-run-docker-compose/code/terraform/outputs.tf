# Output values for the multi-container Cloud Run application
# These outputs provide important information for accessing and managing the deployed resources

# Cloud Run Service Outputs
output "service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.multi_container_app.uri
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.multi_container_app.name
}

output "service_location" {
  description = "Location where the Cloud Run service is deployed"
  value       = google_cloud_run_v2_service.multi_container_app.location
}

output "service_id" {
  description = "Full resource ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.multi_container_app.id
}

# Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.postgres.name
}

output "database_connection_name" {
  description = "Connection name for the Cloud SQL instance (for Cloud SQL proxy)"
  value       = google_sql_database_instance.postgres.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.private_ip_address
  sensitive   = true
}

output "database_public_ip" {
  description = "Public IP address of the Cloud SQL instance (if enabled)"
  value       = google_sql_database_instance.postgres.public_ip_address
  sensitive   = true
}

output "database_name" {
  description = "Name of the application database"
  value       = google_sql_database.app_database.name
}

output "database_user" {
  description = "Username for the application database user"
  value       = google_sql_user.app_user.name
}

# Secret Manager Outputs
output "db_password_secret_name" {
  description = "Name of the Secret Manager secret containing the database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "db_password_secret_id" {
  description = "Full resource ID of the database password secret"
  value       = google_secret_manager_secret.db_password.id
}

output "db_connection_secret_name" {
  description = "Name of the Secret Manager secret containing the database connection string"
  value       = google_secret_manager_secret.db_connection_string.secret_id
}

output "db_connection_secret_id" {
  description = "Full resource ID of the database connection string secret"
  value       = google_secret_manager_secret.db_connection_string.id
}

# Artifact Registry Outputs
output "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.repository_id
}

output "artifact_registry_url" {
  description = "URL for pushing images to the Artifact Registry repository"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}"
}

output "artifact_registry_id" {
  description = "Full resource ID of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_repo.id
}

# Service Account Outputs
output "service_account_email" {
  description = "Email address of the Cloud Run service account"
  value       = google_service_account.cloud_run.email
}

output "service_account_id" {
  description = "Full resource ID of the Cloud Run service account"
  value       = google_service_account.cloud_run.id
}

# Deployment Information
output "deployment_region" {
  description = "Region where resources are deployed"
  value       = var.region
}

output "deployment_zone" {
  description = "Zone where single-zone resources are deployed"
  value       = var.zone
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
}

# Resource Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Container Configuration
output "container_images" {
  description = "Container images used in the deployment"
  value       = var.container_images
}

# Health Check URLs
output "health_check_urls" {
  description = "URLs for health checking the deployed services"
  value = {
    service_health = "${google_cloud_run_v2_service.multi_container_app.uri}/health"
    api_health     = "${google_cloud_run_v2_service.multi_container_app.uri}/api/health"
  }
}

# gcloud Commands for Management
output "gcloud_commands" {
  description = "Useful gcloud commands for managing the deployed resources"
  value = {
    view_service = "gcloud run services describe ${google_cloud_run_v2_service.multi_container_app.name} --region=${var.region}"
    view_logs    = "gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=${google_cloud_run_v2_service.multi_container_app.name}' --limit=50"
    connect_db   = "gcloud sql connect ${google_sql_database_instance.postgres.name} --user=${var.database_user}"
    get_secret   = "gcloud secrets versions access latest --secret=${google_secret_manager_secret.db_password.secret_id}"
  }
}

# Docker Commands for Container Management
output "docker_commands" {
  description = "Docker commands for building and pushing container images"
  value = {
    configure_auth = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"
    build_frontend = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/frontend:latest ./frontend"
    build_backend  = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/backend:latest ./backend"
    build_proxy    = "docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/proxy:latest ./proxy"
    push_frontend  = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/frontend:latest"
    push_backend   = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/backend:latest"
    push_proxy     = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_repo.repository_id}/proxy:latest"
  }
}

# Monitoring and Debugging
output "monitoring_urls" {
  description = "URLs for monitoring and debugging the deployed resources"
  value = {
    cloud_run_console = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_v2_service.multi_container_app.name}/metrics?project=${var.project_id}"
    sql_console       = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.postgres.name}/overview?project=${var.project_id}"
    logs_console      = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${google_cloud_run_v2_service.multi_container_app.name}%22?project=${var.project_id}"
  }
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Information about cost optimization for the deployed resources"
  value = {
    cloud_run_pricing = "Cloud Run charges based on actual resource usage (CPU, memory, requests)"
    sql_pricing       = "Cloud SQL charges for the allocated instance size and storage"
    scaling_notes     = "Min instances: ${var.min_scale}, Max instances: ${var.max_scale}"
    storage_cleanup   = "Artifact Registry has cleanup policies to manage storage costs"
  }
}

# Security Information
output "security_notes" {
  description = "Security configuration information for the deployment"
  value = {
    database_access     = "Database is accessible only through Cloud SQL proxy"
    secret_management   = "Sensitive data is stored in Secret Manager"
    service_account     = "Dedicated service account with minimal required permissions"
    public_access       = var.allow_unauthenticated ? "Service allows public access" : "Service requires authentication"
    ssl_enforcement     = "Cloud SQL requires SSL connections"
    private_networking  = var.vpc_connector_name != "" ? "Using VPC connector for private networking" : "Using public networking"
  }
}