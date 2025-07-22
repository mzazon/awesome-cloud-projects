# Output Values for Continuous Performance Optimization Infrastructure
# This file defines the output values that will be displayed after deployment

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "The suffix used for resource naming"
  value       = local.resource_suffix
}

# Cloud Source Repository Outputs
output "source_repository_name" {
  description = "Name of the created Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.name
}

output "source_repository_url" {
  description = "URL of the Cloud Source Repository"
  value       = google_sourcerepo_repository.app_repo.url
}

output "source_repository_clone_url" {
  description = "Clone URL for the Cloud Source Repository"
  value       = "https://source.developers.google.com/p/${var.project_id}/r/${google_sourcerepo_repository.app_repo.name}"
}

# Cloud Build Outputs
output "build_trigger_name" {
  description = "Name of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.performance_trigger.name
}

output "build_trigger_id" {
  description = "ID of the Cloud Build trigger"
  value       = google_cloudbuild_trigger.performance_trigger.trigger_id
}

output "build_trigger_webhook_url" {
  description = "Webhook URL for the Cloud Build trigger"
  value       = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/triggers/${google_cloudbuild_trigger.performance_trigger.trigger_id}:webhook"
}

# Cloud Run Outputs
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_service.app_service.name
}

output "cloud_run_service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_service.app_service.status[0].url
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_service.app_service.location
}

output "cloud_run_service_account" {
  description = "Service account email for the Cloud Run service"
  value       = google_service_account.cloud_run_sa.email
}

# Container Registry Outputs
output "container_image_base" {
  description = "Base URL for container images in GCR"
  value       = "gcr.io/${var.project_id}/${local.service_name}"
}

output "container_image_latest" {
  description = "Latest container image URL"
  value       = "gcr.io/${var.project_id}/${local.service_name}:latest"
}

# Monitoring Outputs
output "response_time_alert_policy_name" {
  description = "Name of the response time alert policy"
  value       = google_monitoring_alert_policy.response_time_alert.display_name
}

output "memory_alert_policy_name" {
  description = "Name of the memory alert policy"
  value       = google_monitoring_alert_policy.memory_alert.display_name
}

output "monitoring_dashboard_url" {
  description = "URL to the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.performance_dashboard.id)[3]}?project=${var.project_id}"
}

# Notification Outputs
output "email_notification_channel" {
  description = "Email notification channel name (if created)"
  value       = var.notification_email != "" ? google_monitoring_notification_channel.email[0].name : "No email notification channel created"
}

output "webhook_notification_channel" {
  description = "Webhook notification channel name"
  value       = google_monitoring_notification_channel.webhook.name
}

# Logging Outputs
output "performance_log_sink_name" {
  description = "Name of the performance metrics log sink"
  value       = google_logging_project_sink.performance_sink.name
}

output "performance_log_sink_writer_identity" {
  description = "Writer identity for the performance log sink"
  value       = google_logging_project_sink.performance_sink.writer_identity
}

output "response_time_metric_name" {
  description = "Name of the custom response time metric"
  value       = google_logging_metric.response_time_metric.name
}

# Configuration Outputs
output "cloud_run_configuration" {
  description = "Cloud Run service configuration summary"
  value = {
    memory              = var.cloud_run_memory
    cpu                 = var.cloud_run_cpu
    concurrency         = var.cloud_run_concurrency
    min_instances       = var.cloud_run_min_instances
    max_instances       = var.cloud_run_max_instances
    service_account     = google_service_account.cloud_run_sa.email
  }
}

output "monitoring_configuration" {
  description = "Monitoring configuration summary"
  value = {
    response_time_threshold = var.response_time_threshold
    memory_threshold       = var.memory_threshold
    alert_duration         = var.alert_duration
    notification_email     = var.notification_email != "" ? var.notification_email : "None configured"
  }
}

# API Status Outputs
output "enabled_apis" {
  description = "List of enabled Google Cloud APIs"
  value = var.enable_apis ? [
    "cloudbuild.googleapis.com",
    "monitoring.googleapis.com",
    "sourcerepo.googleapis.com",
    "run.googleapis.com",
    "containerregistry.googleapis.com",
    "logging.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ] : []
}

# Usage Instructions
output "next_steps" {
  description = "Instructions for using the deployed infrastructure"
  value = <<-EOT
    
    🚀 Continuous Performance Optimization Infrastructure Deployed Successfully!
    
    📋 Next Steps:
    
    1. Clone the source repository:
       git clone ${google_sourcerepo_repository.app_repo.url}
    
    2. Add your application code to the repository and push to trigger the first build:
       cd ${google_sourcerepo_repository.app_repo.name}
       # Add your application files (app.js, Dockerfile, cloudbuild.yaml)
       git add .
       git commit -m "Initial application deployment"
       git push origin master
    
    3. Monitor your application:
       - Service URL: ${google_cloud_run_service.app_service.status[0].url}
       - Health Check: ${google_cloud_run_service.app_service.status[0].url}/health
       - Monitoring Dashboard: https://console.cloud.google.com/monitoring/dashboards/custom/${split("/", google_monitoring_dashboard.performance_dashboard.id)[3]}?project=${var.project_id}
    
    4. Test performance optimization:
       - Generate load to trigger alerts: curl "${google_cloud_run_service.app_service.status[0].url}/load-test"
       - Monitor build triggers: gcloud builds list --ongoing
    
    5. Configure additional monitoring:
       - Set up custom metrics in Cloud Monitoring
       - Configure additional notification channels
       - Adjust alert thresholds based on your requirements
    
    📊 Key Resources Created:
    - Cloud Run Service: ${google_cloud_run_service.app_service.name}
    - Cloud Build Trigger: ${google_cloudbuild_trigger.performance_trigger.name}
    - Source Repository: ${google_sourcerepo_repository.app_repo.name}
    - Alert Policies: Response Time & Memory Usage
    - Monitoring Dashboard: Performance Metrics
    
    🔧 Configuration:
    - Memory: ${var.cloud_run_memory}
    - CPU: ${var.cloud_run_cpu}
    - Concurrency: ${var.cloud_run_concurrency}
    - Min Instances: ${var.cloud_run_min_instances}
    - Max Instances: ${var.cloud_run_max_instances}
    
    For detailed setup instructions, refer to the recipe documentation.
    
  EOT
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD)"
  value = {
    cloud_run_minimum = "~$5-15 (depending on traffic)"
    cloud_build       = "~$5-20 (120 minutes/month included)"
    cloud_monitoring  = "~$1-5 (basic monitoring)"
    cloud_logging     = "~$1-3 (basic logging)"
    storage          = "~$1-2 (container registry)"
    total_estimated  = "~$13-45 per month"
    note            = "Actual costs depend on usage patterns, traffic volume, and optimization frequency"
  }
}

# Security Information
output "security_notes" {
  description = "Security configuration summary"
  value = {
    service_account        = "Dedicated service account with minimal permissions"
    public_access         = "Cloud Run service allows public access (as configured)"
    container_security    = "Container runs as non-root user (configure in Dockerfile)"
    network_security      = "HTTPS-only communication enforced"
    iam_recommendations   = "Review and adjust IAM permissions based on your security requirements"
  }
}

# Troubleshooting Information
output "troubleshooting_urls" {
  description = "Useful URLs for troubleshooting"
  value = {
    cloud_build_history   = "https://console.cloud.google.com/cloud-build/builds?project=${var.project_id}"
    cloud_run_service     = "https://console.cloud.google.com/run/detail/${var.region}/${google_cloud_run_service.app_service.name}/metrics?project=${var.project_id}"
    monitoring_alerts     = "https://console.cloud.google.com/monitoring/alerting?project=${var.project_id}"
    logging_dashboard     = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    source_repositories   = "https://console.cloud.google.com/source/repos?project=${var.project_id}"
  }
}