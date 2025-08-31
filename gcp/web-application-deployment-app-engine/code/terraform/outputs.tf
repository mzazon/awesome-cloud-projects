# Output values for the App Engine web application deployment
# These outputs provide important information about the deployed resources

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "application_id" {
  description = "The App Engine application ID"
  value       = google_app_engine_application.app.app_id
}

output "application_url" {
  description = "The URL where the application is accessible"
  value       = "https://${var.project_id}.appspot.com"
}

output "application_version" {
  description = "The deployed application version ID"
  value       = google_app_engine_standard_app_version.app_version.version_id
}

output "application_name" {
  description = "The name of the deployed application"
  value       = var.application_name
}

output "service_name" {
  description = "The App Engine service name"
  value       = google_app_engine_standard_app_version.app_version.service
}

output "runtime" {
  description = "The runtime environment used for the application"
  value       = google_app_engine_standard_app_version.app_version.runtime
}

output "region" {
  description = "The region where the App Engine application is deployed"
  value       = var.region
}

output "scaling_configuration" {
  description = "Automatic scaling configuration details"
  value = {
    min_instances          = var.min_instances
    max_instances          = var.max_instances
    target_cpu_utilization = var.target_cpu_utilization
  }
}

output "source_bucket" {
  description = "The Cloud Storage bucket containing the application source code"
  value       = google_storage_bucket.app_source.name
}

output "source_object" {
  description = "The Cloud Storage object containing the application source code"
  value       = google_storage_bucket_object.app_source.name
}

output "health_check_url" {
  description = "URL for the application health check endpoint"
  value       = "https://${var.project_id}.appspot.com/health"
}

output "console_url" {
  description = "URL to view the application in the Google Cloud Console"
  value       = "https://console.cloud.google.com/appengine?project=${var.project_id}"
}

output "logs_url" {
  description = "URL to view application logs in the Google Cloud Console"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22gae_app%22?project=${var.project_id}"
}

output "monitoring_url" {
  description = "URL to view application monitoring in the Google Cloud Console"
  value       = "https://console.cloud.google.com/monitoring/dashboards/resourceList/appengine_application?project=${var.project_id}"
}

output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this deployment"
  value = [
    "appengine.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]
}

output "environment_variables" {
  description = "Environment variables configured for the application"
  value       = var.environment_variables
  sensitive   = true
}

output "deployment_info" {
  description = "Comprehensive deployment information"
  value = {
    project_id         = var.project_id
    application_url    = "https://${var.project_id}.appspot.com"
    version_id         = google_app_engine_standard_app_version.app_version.version_id
    service_name       = google_app_engine_standard_app_version.app_version.service
    runtime           = google_app_engine_standard_app_version.app_version.runtime
    region            = var.region
    instance_class    = "F1"
    scaling_type      = "automatic"
    traffic_split     = "100%"
  }
}