# Output values for the Immersive XR Content Delivery platform
# These outputs provide important information for accessing and managing the deployed resources

# Project and Region Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were deployed"
  value       = var.zone
}

# Storage Resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket containing XR assets"
  value       = google_storage_bucket.xr_assets.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.xr_assets.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.xr_assets.self_link
}

# CDN and Load Balancing
output "cdn_ip_address" {
  description = "Global IP address for the CDN endpoint"
  value       = google_compute_global_forwarding_rule.cdn.ip_address
}

output "cdn_endpoint_http" {
  description = "HTTP endpoint for accessing XR content through CDN"
  value       = "http://${google_compute_global_forwarding_rule.cdn.ip_address}"
}

output "cdn_endpoint_https" {
  description = "HTTPS endpoint for accessing XR content through CDN (if SSL enabled)"
  value = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? (
    "https://${google_compute_global_forwarding_rule.cdn_https[0].ip_address}"
  ) : "SSL not configured"
}

output "web_app_url" {
  description = "URL to access the sample XR web application"
  value       = "http://${google_compute_global_forwarding_rule.cdn.ip_address}/app/"
}

output "app_config_url" {
  description = "URL to access the application configuration"
  value       = "http://${google_compute_global_forwarding_rule.cdn.ip_address}/configs/app-config.json"
}

# XR Streaming Service Information
output "xr_service_account_email" {
  description = "Email address of the XR streaming service account"
  value       = google_service_account.xr_streaming.email
}

output "xr_service_account_id" {
  description = "Unique ID of the XR streaming service account"
  value       = google_service_account.xr_streaming.unique_id
}

output "xr_service_account_key" {
  description = "Base64 encoded private key for the XR streaming service account"
  value       = google_service_account_key.xr_streaming_key.private_key
  sensitive   = true
}

# Backend Services
output "cdn_backend_bucket_name" {
  description = "Name of the Cloud CDN backend bucket"
  value       = google_compute_backend_bucket.cdn_backend.name
}

output "xr_backend_service_name" {
  description = "Name of the XR streaming backend service"
  value       = google_compute_backend_service.xr_streaming.name
}

output "xr_backend_service_id" {
  description = "ID of the XR streaming backend service"
  value       = google_compute_backend_service.xr_streaming.id
}

# URL Mapping and Routing
output "url_map_name" {
  description = "Name of the URL map for routing traffic"
  value       = google_compute_url_map.unified_urlmap.name
}

output "url_map_self_link" {
  description = "Self-link of the URL map"
  value       = google_compute_url_map.unified_urlmap.self_link
}

# SSL Certificate Information (if enabled)
output "ssl_certificate_name" {
  description = "Name of the managed SSL certificate (if SSL enabled)"
  value = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? (
    google_compute_managed_ssl_certificate.cdn_ssl[0].name
  ) : "SSL not configured"
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = var.ssl_certificate_domains
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate (if SSL enabled)"
  value = var.enable_ssl && length(var.ssl_certificate_domains) > 0 ? (
    google_compute_managed_ssl_certificate.cdn_ssl[0].managed[0].status
  ) : "SSL not configured"
}

# Health Check Information
output "health_check_name" {
  description = "Name of the HTTP health check for XR streaming"
  value       = google_compute_http_health_check.xr_health_check.name
}

output "health_check_self_link" {
  description = "Self-link of the HTTP health check"
  value       = google_compute_http_health_check.xr_health_check.self_link
}

# Monitoring and Logging
output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "xr_session_starts_metric" {
  description = "Name of the XR session starts custom metric (if monitoring enabled)"
  value = var.enable_monitoring ? (
    google_logging_metric.xr_session_starts[0].name
  ) : "Monitoring not enabled"
}

output "xr_session_duration_metric" {
  description = "Name of the XR session duration custom metric (if monitoring enabled)"
  value = var.enable_monitoring ? (
    google_logging_metric.xr_session_duration[0].name
  ) : "Monitoring not enabled"
}

output "gpu_utilization_alert_policy" {
  description = "Name of the GPU utilization alert policy (if monitoring enabled)"
  value = var.enable_monitoring ? (
    google_monitoring_alert_policy.xr_gpu_utilization[0].name
  ) : "Monitoring not enabled"
}

# Security Policy
output "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = google_compute_security_policy.xr_security_policy.name
}

output "security_policy_self_link" {
  description = "Self-link of the Cloud Armor security policy"
  value       = google_compute_security_policy.xr_security_policy.self_link
}

# Configuration Information
output "xr_gpu_configuration" {
  description = "GPU configuration for XR streaming instances"
  value = {
    gpu_class                = var.xr_gpu_class
    gpu_count               = var.xr_gpu_count
    session_timeout         = var.xr_session_timeout
    max_concurrent_sessions = var.xr_max_concurrent_sessions
  }
}

output "autoscaling_configuration" {
  description = "Autoscaling configuration for XR streaming service"
  value = {
    enabled             = var.enable_autoscaling
    min_capacity        = var.autoscaling_min_capacity
    max_capacity        = var.autoscaling_max_capacity
    target_utilization  = var.autoscaling_target_utilization
  }
}

output "cdn_configuration" {
  description = "CDN caching configuration"
  value = {
    cache_mode    = var.cdn_cache_mode
    default_ttl   = var.cdn_default_ttl
    max_ttl       = var.cdn_max_ttl
  }
}

# Resource Identifiers
output "resource_prefix" {
  description = "Prefix used for resource names"
  value       = var.resource_prefix
}

output "random_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = random_id.suffix.hex
}

output "environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# Deployment Information
output "deployment_timestamp" {
  description = "Timestamp when the resources were deployed"
  value       = timestamp()
}

output "terraform_version" {
  description = "Terraform version used for deployment"
  value       = "~> 1.5"
}

# API Services Status
output "enabled_apis" {
  description = "List of Google Cloud APIs enabled for this project"
  value       = var.enable_apis
}

# Access Instructions
output "access_instructions" {
  description = "Instructions for accessing the XR platform"
  value = {
    web_application = "Open ${google_compute_global_forwarding_rule.cdn.ip_address}/app/ in your browser"
    api_endpoints   = "XR streaming API available at ${google_compute_global_forwarding_rule.cdn.ip_address}/stream/"
    asset_storage   = "XR assets stored in gs://${google_storage_bucket.xr_assets.name}"
    monitoring      = var.enable_monitoring ? "View metrics in Google Cloud Console > Monitoring" : "Monitoring not enabled"
  }
}