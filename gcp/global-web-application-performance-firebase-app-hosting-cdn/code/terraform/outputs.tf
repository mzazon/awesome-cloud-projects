# Outputs for Global Web Application Performance with Firebase App Hosting and Cloud CDN
#
# These outputs provide essential information for accessing and managing
# the deployed infrastructure components.

# =============================================================================
# NETWORK AND LOAD BALANCER OUTPUTS
# =============================================================================

output "global_ip_address" {
  description = "Global static IP address for the web application"
  value       = google_compute_global_address.web_app.address
  sensitive   = false
}

output "global_ip_name" {
  description = "Name of the global static IP address resource"
  value       = google_compute_global_address.web_app.name
  sensitive   = false
}

output "load_balancer_url_http" {
  description = "HTTP URL for accessing the web application (will redirect to HTTPS)"
  value       = "http://${google_compute_global_address.web_app.address}"
  sensitive   = false
}

output "load_balancer_url_https" {
  description = "HTTPS URL for accessing the web application"
  value       = "https://${google_compute_global_address.web_app.address}"
  sensitive   = false
}

output "custom_domain_url" {
  description = "Custom domain URL (if domain name is configured)"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : null
  sensitive   = false
}

# =============================================================================
# CDN AND BACKEND OUTPUTS
# =============================================================================

output "cdn_backend_bucket_name" {
  description = "Name of the CDN backend bucket for static assets"
  value       = google_compute_backend_bucket.web_assets.name
  sensitive   = false
}

output "cdn_cache_mode" {
  description = "CDN cache mode configuration"
  value       = var.cdn_cache_mode
  sensitive   = false
}

output "cdn_default_ttl" {
  description = "CDN default TTL configuration in seconds"
  value       = var.cdn_default_ttl
  sensitive   = false
}

output "backend_service_name" {
  description = "Name of the backend service for dynamic content"
  value       = google_compute_backend_service.web_app.name
  sensitive   = false
}

output "url_map_name" {
  description = "Name of the URL map for traffic routing"
  value       = google_compute_url_map.web_app.name
  sensitive   = false
}

# =============================================================================
# CLOUD STORAGE OUTPUTS
# =============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for web assets"
  value       = google_storage_bucket.web_assets.name
  sensitive   = false
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.web_assets.url
  sensitive   = false
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.web_assets.location
  sensitive   = false
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.web_assets.self_link
  sensitive   = false
}

# =============================================================================
# SSL CERTIFICATE OUTPUTS
# =============================================================================

output "ssl_certificate_name" {
  description = "Name of the managed SSL certificate (if configured)"
  value       = var.domain_name != "" ? google_compute_managed_ssl_certificate.web_app[0].name : null
  sensitive   = false
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = var.domain_name != "" ? google_compute_managed_ssl_certificate.web_app[0].managed[0].domains : []
  sensitive   = false
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate"
  value       = var.domain_name != "" ? google_compute_managed_ssl_certificate.web_app[0].managed[0].status : null
  sensitive   = false
}

# =============================================================================
# SERVICE ACCOUNT OUTPUTS
# =============================================================================

output "app_hosting_service_account_email" {
  description = "Email address of the Firebase App Hosting service account"
  value       = google_service_account.app_hosting.email
  sensitive   = false
}

output "functions_service_account_email" {
  description = "Email address of the Cloud Functions service account"
  value       = google_service_account.functions.email
  sensitive   = false
}

# =============================================================================
# CLOUD FUNCTIONS OUTPUTS
# =============================================================================

output "performance_optimizer_function_name" {
  description = "Name of the performance optimizer Cloud Function"
  value       = google_cloudfunctions2_function.performance_optimizer.name
  sensitive   = false
}

output "performance_optimizer_function_url" {
  description = "URL of the performance optimizer Cloud Function"
  value       = google_cloudfunctions2_function.performance_optimizer.service_config[0].uri
  sensitive   = false
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for performance metrics"
  value       = google_pubsub_topic.performance_metrics.name
  sensitive   = false
}

output "cloud_scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for triggering optimization"
  value       = google_cloud_scheduler_job.performance_optimization.name
  sensitive   = false
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "monitoring_enabled" {
  description = "Whether Cloud Monitoring is enabled"
  value       = var.enable_monitoring
  sensitive   = false
}

output "notification_channel_email" {
  description = "Email address for monitoring notifications"
  value       = var.enable_monitoring && var.notification_email != "" ? var.notification_email : null
  sensitive   = true
}

output "uptime_check_name" {
  description = "Name of the uptime check configuration"
  value       = var.enable_monitoring && var.domain_name != "" ? google_monitoring_uptime_check_config.web_app[0].name : null
  sensitive   = false
}

output "alert_policies" {
  description = "Names of the configured alert policies"
  value = var.enable_monitoring ? {
    high_latency    = google_monitoring_alert_policy.high_latency[0].name
    high_error_rate = google_monitoring_alert_policy.high_error_rate[0].name
  } : {}
  sensitive = false
}

# =============================================================================
# HEALTH CHECK OUTPUTS
# =============================================================================

output "health_check_name" {
  description = "Name of the health check for backend services"
  value       = google_compute_health_check.web_app.name
  sensitive   = false
}

output "health_check_path" {
  description = "Path used for health checks"
  value       = var.uptime_check_path
  sensitive   = false
}

# =============================================================================
# RESOURCE NAMING OUTPUTS
# =============================================================================

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
  sensitive   = false
}

output "resource_suffix" {
  description = "Suffix used for resource naming"
  value       = local.suffix
  sensitive   = false
}

output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

# =============================================================================
# PROJECT AND ENVIRONMENT OUTPUTS
# =============================================================================

output "project_id" {
  description = "Google Cloud project ID"
  value       = var.project_id
  sensitive   = false
}

output "region" {
  description = "Primary region for resource deployment"
  value       = var.region
  sensitive   = false
}

output "environment" {
  description = "Environment name (dev, staging, prod)"
  value       = var.environment
  sensitive   = false
}

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure configuration"
  value = {
    # Network configuration
    global_ip         = google_compute_global_address.web_app.address
    network_tier      = var.network_tier
    
    # CDN configuration
    cdn_enabled       = var.enable_cdn
    cdn_cache_mode    = var.cdn_cache_mode
    
    # SSL configuration
    ssl_enabled       = var.domain_name != ""
    domain_name       = var.domain_name
    
    # Storage configuration
    bucket_name       = google_storage_bucket.web_assets.name
    storage_location  = var.storage_location
    
    # Function configuration
    function_runtime  = var.function_runtime
    function_memory   = var.function_memory
    
    # Monitoring configuration
    monitoring_enabled = var.enable_monitoring
    alert_email       = var.notification_email != "" ? "configured" : "not_configured"
    
    # Environment
    environment       = var.environment
    region           = var.region
  }
  sensitive = false
}

# =============================================================================
# NEXT STEPS OUTPUT
# =============================================================================

output "next_steps" {
  description = "Next steps for completing the web application deployment"
  value = {
    instructions = [
      "1. If using a custom domain, update DNS records to point to: ${google_compute_global_address.web_app.address}",
      "2. Upload your web application assets to the bucket: ${google_storage_bucket.web_assets.name}",
      "3. Configure Firebase App Hosting to deploy your application code",
      "4. Test the application using: https://${google_compute_global_address.web_app.address}",
      "5. Monitor performance using Cloud Monitoring dashboard",
      "6. Review CDN cache hit rates and optimize as needed"
    ]
    
    useful_commands = [
      "# Upload static assets to bucket",
      "gsutil -m cp -r ./dist/* gs://${google_storage_bucket.web_assets.name}/",
      "",
      "# Check CDN cache status",
      "curl -I https://${google_compute_global_address.web_app.address}",
      "",
      "# View Cloud Function logs",
      "gcloud functions logs read ${local.function_name} --region=${var.region}",
      "",
      "# Monitor uptime checks",
      "gcloud monitoring policies list --filter='displayName:\"Web App Uptime Check\"'"
    ]
  }
  sensitive = false
}