# ==========================================
# Output Values for Dynamic Content Delivery Infrastructure
# ==========================================
# This file defines all output values that provide important information
# about the deployed infrastructure for integration and verification

# ==========================================
# Firebase Hosting Outputs
# ==========================================

output "firebase_hosting_site_id" {
  description = "The site ID of the Firebase Hosting site"
  value       = google_firebase_hosting_site.default.site_id
}

output "firebase_hosting_url" {
  description = "The default URL for the Firebase Hosting site"
  value       = google_firebase_hosting_site.default.default_url
}

output "firebase_project_id" {
  description = "The Firebase project ID"
  value       = google_firebase_project.default.project
}

output "firebase_web_app_id" {
  description = "The Firebase web app ID (if created)"
  value       = var.enable_firebase_web_app ? google_firebase_web_app.default[0].app_id : null
}

output "firebase_web_app_config" {
  description = "Firebase web app configuration object"
  value = var.enable_firebase_web_app ? {
    app_id      = google_firebase_web_app.default[0].app_id
    project_id  = var.project_id
    site_id     = google_firebase_hosting_site.default.site_id
    hosting_url = google_firebase_hosting_site.default.default_url
  } : null
}

# ==========================================
# Cloud Functions Outputs
# ==========================================

output "products_function_url" {
  description = "The trigger URL for the products Cloud Function"
  value       = google_cloudfunctions2_function.get_products.service_config[0].uri
}

output "recommendations_function_url" {
  description = "The trigger URL for the recommendations Cloud Function"
  value       = google_cloudfunctions2_function.get_recommendations.service_config[0].uri
}

output "products_function_name" {
  description = "The name of the products Cloud Function"
  value       = google_cloudfunctions2_function.get_products.name
}

output "recommendations_function_name" {
  description = "The name of the recommendations Cloud Function"
  value       = google_cloudfunctions2_function.get_recommendations.name
}

output "function_service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_region" {
  description = "The region where Cloud Functions are deployed"
  value       = var.region
}

# ==========================================
# Cloud Storage Outputs
# ==========================================

output "media_bucket_name" {
  description = "Name of the Cloud Storage bucket for media assets"
  value       = google_storage_bucket.media_bucket.name
}

output "media_bucket_url" {
  description = "Public URL for the media storage bucket"
  value       = google_storage_bucket.media_bucket.url
}

output "source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.source_bucket.name
}

output "log_bucket_name" {
  description = "Name of the Cloud Storage bucket for access logs (if logging enabled)"
  value       = var.enable_logging ? google_storage_bucket.access_logs[0].name : null
}

output "storage_location" {
  description = "Location of the Cloud Storage buckets"
  value       = var.storage_location
}

# ==========================================
# CDN and Load Balancer Outputs
# ==========================================

output "cdn_backend_bucket_name" {
  description = "Name of the CDN backend bucket"
  value       = google_compute_backend_bucket.media_backend.name
}

output "cdn_enabled" {
  description = "Whether Cloud CDN is enabled for the backend bucket"
  value       = google_compute_backend_bucket.media_backend.enable_cdn
}

output "load_balancer_ip" {
  description = "External IP address of the global load balancer"
  value       = google_compute_global_forwarding_rule.main.ip_address
}

output "url_map_name" {
  description = "Name of the URL map for routing configuration"
  value       = google_compute_url_map.main.name
}

output "http_proxy_name" {
  description = "Name of the HTTP target proxy"
  value       = google_compute_target_http_proxy.main.name
}

output "forwarding_rule_name" {
  description = "Name of the global forwarding rule"
  value       = google_compute_global_forwarding_rule.main.name
}

# ==========================================
# Monitoring Outputs
# ==========================================

output "monitoring_enabled" {
  description = "Whether monitoring and alerting are enabled"
  value       = var.enable_monitoring
}

output "uptime_check_id" {
  description = "ID of the uptime check for Firebase Hosting (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_uptime_check_config.firebase_hosting[0].uptime_check_id : null
}

output "alert_policy_id" {
  description = "ID of the alert policy for function errors (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.function_errors[0].name : null
}

output "notification_channel_id" {
  description = "ID of the email notification channel (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_notification_channel.email[0].name : null
}

# ==========================================
# Security and Access Outputs
# ==========================================

output "cors_configuration" {
  description = "CORS configuration for the media storage bucket"
  value = {
    origins         = var.cors_origins
    methods         = var.cors_methods
    max_age_seconds = var.cors_max_age_seconds
  }
}

output "uniform_bucket_level_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_level_access
}

output "iap_enabled" {
  description = "Whether Identity-Aware Proxy (IAP) is enabled"
  value       = var.enable_iap
}

# ==========================================
# Resource Management Outputs
# ==========================================

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "deployment_id" {
  description = "Unique deployment identifier"
  value       = local.suffix
}

output "environment" {
  description = "Environment name for the deployment"
  value       = var.environment
}

output "application_name" {
  description = "Name of the application"
  value       = var.application_name
}

# ==========================================
# API Integration Outputs
# ==========================================

output "api_endpoints" {
  description = "Complete API endpoints for the dynamic content delivery system"
  value = {
    products_api = {
      url    = google_cloudfunctions2_function.get_products.service_config[0].uri
      method = "GET"
      cors   = true
      cache_headers = "public, max-age=300, s-maxage=600"
    }
    recommendations_api = {
      url    = google_cloudfunctions2_function.get_recommendations.service_config[0].uri
      method = "GET"
      cors   = true
      cache_headers = "private, max-age=300"
    }
    media_cdn = {
      url         = "https://${google_compute_global_forwarding_rule.main.ip_address}"
      bucket_url  = google_storage_bucket.media_bucket.url
      cdn_enabled = google_compute_backend_bucket.media_backend.enable_cdn
    }
  }
}

# ==========================================
# Configuration Summary
# ==========================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure configuration"
  value = {
    project_id           = var.project_id
    region              = var.region
    firebase_site_id    = google_firebase_hosting_site.default.site_id
    firebase_url        = google_firebase_hosting_site.default.default_url
    load_balancer_ip    = google_compute_global_forwarding_rule.main.ip_address
    media_bucket        = google_storage_bucket.media_bucket.name
    functions_deployed  = 2
    cdn_enabled         = var.enable_cdn
    monitoring_enabled  = var.enable_monitoring
    environment         = var.environment
    deployment_id       = local.suffix
  }
}

# ==========================================
# Next Steps and Integration Guide
# ==========================================

output "integration_guide" {
  description = "Next steps and integration information for developers"
  value = {
    firebase_hosting = {
      site_url     = google_firebase_hosting_site.default.default_url
      deploy_command = "firebase deploy --project ${var.project_id} --only hosting"
      config_note  = "Configure firebase.json to route API calls to Cloud Functions"
    }
    api_integration = {
      products_endpoint      = "${google_cloudfunctions2_function.get_products.service_config[0].uri}"
      recommendations_endpoint = "${google_cloudfunctions2_function.get_recommendations.service_config[0].uri}"
      cors_enabled          = "true"
      authentication        = "none"
    }
    cdn_optimization = {
      media_base_url    = "https://${google_compute_global_forwarding_rule.main.ip_address}"
      cache_control     = "Automatic caching enabled with ${var.cdn_default_ttl}s default TTL"
      compression       = var.enable_compression ? "Enabled" : "Disabled"
      global_distribution = "Available across Google's global edge network"
    }
    monitoring = var.enable_monitoring ? {
      uptime_monitoring = "Configured for Firebase Hosting"
      error_alerting   = "Configured for Cloud Functions"
      notification_method = "Email"
    } : {
      status = "Monitoring disabled - enable with var.enable_monitoring = true"
    }
  }
}