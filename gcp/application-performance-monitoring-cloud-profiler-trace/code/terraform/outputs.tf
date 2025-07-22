# Outputs for Application Performance Monitoring with Cloud Profiler and Cloud Trace

# Project information
output "project_id" {
  description = "The Google Cloud project ID"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources are deployed"
  value       = var.region
}

output "resource_prefix" {
  description = "The prefix used for naming resources"
  value       = local.resource_prefix
}

output "resource_suffix" {
  description = "The random suffix used for unique resource naming"
  value       = local.resource_suffix
}

# Service account information
output "service_account_email" {
  description = "Email address of the service account used by Cloud Run services"
  value       = google_service_account.profiler_trace_sa.email
}

output "service_account_name" {
  description = "Name of the service account used by Cloud Run services"
  value       = google_service_account.profiler_trace_sa.name
}

# Artifact Registry information
output "artifact_registry_repository" {
  description = "Name of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_registry.name
}

output "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  value       = google_artifact_registry_repository.container_registry.location
}

output "docker_repository_url" {
  description = "Docker repository URL for pushing container images"
  value       = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}"
}

# Cloud Run service information
output "cloud_run_services" {
  description = "Cloud Run service information including names and URLs"
  value = {
    for k, v in google_cloud_run_v2_service.services : k => {
      name     = v.name
      url      = v.uri
      location = v.location
    }
  }
}

output "cloud_run_service_urls" {
  description = "URLs of all Cloud Run services"
  value = {
    for k, v in google_cloud_run_v2_service.services : k => v.uri
  }
}

output "frontend_service_url" {
  description = "URL of the frontend service"
  value       = google_cloud_run_v2_service.services["frontend"].uri
}

output "api_gateway_service_url" {
  description = "URL of the API gateway service"
  value       = google_cloud_run_v2_service.services["api-gateway"].uri
}

output "auth_service_url" {
  description = "URL of the authentication service"
  value       = google_cloud_run_v2_service.services["auth-service"].uri
}

output "data_service_url" {
  description = "URL of the data service"
  value       = google_cloud_run_v2_service.services["data-service"].uri
}

# Monitoring information
output "monitoring_dashboard_id" {
  description = "ID of the Cloud Monitoring dashboard"
  value       = var.monitoring_dashboard_enabled ? google_monitoring_dashboard.performance_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value       = var.monitoring_dashboard_enabled ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.performance_dashboard[0].id}?project=${var.project_id}" : null
}

# Alert policy information
output "high_latency_alert_policy_id" {
  description = "ID of the high latency alert policy"
  value       = var.alert_policies_enabled ? google_monitoring_alert_policy.high_latency_alert[0].id : null
}

output "high_error_rate_alert_policy_id" {
  description = "ID of the high error rate alert policy"
  value       = var.alert_policies_enabled ? google_monitoring_alert_policy.high_error_rate_alert[0].id : null
}

# Observability URLs
output "cloud_profiler_url" {
  description = "URL to access Cloud Profiler"
  value       = "https://console.cloud.google.com/profiler?project=${var.project_id}"
}

output "cloud_trace_url" {
  description = "URL to access Cloud Trace"
  value       = "https://console.cloud.google.com/traces?project=${var.project_id}"
}

output "cloud_monitoring_url" {
  description = "URL to access Cloud Monitoring"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

output "cloud_logging_url" {
  description = "URL to access Cloud Logging"
  value       = "https://console.cloud.google.com/logs?project=${var.project_id}"
}

# Configuration values
output "cloud_profiler_enabled" {
  description = "Whether Cloud Profiler is enabled"
  value       = var.cloud_profiler_enabled
}

output "cloud_trace_enabled" {
  description = "Whether Cloud Trace is enabled"
  value       = var.cloud_trace_enabled
}

output "cloud_trace_sample_rate" {
  description = "Cloud Trace sampling rate"
  value       = var.cloud_trace_sample_rate
}

# Log-based metric information
output "application_performance_metric_name" {
  description = "Name of the custom application performance metric"
  value       = google_logging_metric.application_performance_metric.name
}

# Resource labels
output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Container image build commands
output "container_build_commands" {
  description = "Commands to build and push container images"
  value = {
    for k, v in local.services : k => {
      build_command = "gcloud builds submit ${k}/ --tag ${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}/${v.image_name}:latest"
      image_url     = "${var.artifact_registry_location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.container_registry.repository_id}/${v.image_name}:latest"
    }
  }
}

# Load testing information
output "load_testing_commands" {
  description = "Commands for load testing the deployed services"
  value = {
    frontend_load_test = "for i in {1..50}; do curl -s ${google_cloud_run_v2_service.services["frontend"].uri} > /dev/null & done; wait"
    health_check_all   = "for service in ${join(" ", [for k, v in google_cloud_run_v2_service.services : v.uri])}; do echo \"Testing $service/health\"; curl -s \"$service/health\" | jq .; done"
  }
}

# Deployment verification commands
output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_services = "gcloud run services list --region=${var.region} --filter=\"metadata.name~'${local.resource_prefix}-.*'\""
    check_logs     = "gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name~'${local.resource_prefix}-.*' AND textPayload:Profiler\" --limit=10"
    check_traces   = "gcloud logging read \"resource.type=cloud_run_revision AND jsonPayload.trace_id!=''\" --limit=5"
  }
}

# Next steps information
output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Build and push container images using the commands in 'container_build_commands' output",
    "2. Test the services using the URLs in 'cloud_run_service_urls' output",
    "3. Generate load using the commands in 'load_testing_commands' output",
    "4. Monitor performance using the Cloud Profiler URL: ${output.cloud_profiler_url.value}",
    "5. View distributed traces using the Cloud Trace URL: ${output.cloud_trace_url.value}",
    "6. Check the monitoring dashboard: ${var.monitoring_dashboard_enabled ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.performance_dashboard[0].id}?project=${var.project_id}" : "Dashboard not enabled"}",
    "7. Review logs and metrics in Cloud Monitoring: ${output.cloud_monitoring_url.value}"
  ]
}