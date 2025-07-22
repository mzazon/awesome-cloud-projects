# Output Values for Secure API Gateway Architecture
# These outputs provide important information for testing and integration

# Basic Infrastructure Information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "zone" {
  description = "The GCP zone where zonal resources were created"
  value       = var.zone
}

# API Gateway Access Information
output "gateway_ip_address" {
  description = "Static IP address of the API gateway load balancer"
  value       = google_compute_global_address.esp_gateway_ip.address
}

output "api_gateway_url_http" {
  description = "HTTP URL for accessing the API gateway"
  value       = "http://${google_compute_global_address.esp_gateway_ip.address}"
}

output "api_gateway_url_https" {
  description = "HTTPS URL for accessing the API gateway (only available if SSL is enabled)"
  value       = var.enable_ssl ? "https://${google_compute_global_address.esp_gateway_ip.address}" : "HTTPS not enabled"
}

output "custom_domain_url" {
  description = "Custom domain URL for the API gateway (only available if custom domain is configured)"
  value       = var.custom_domain != "" ? (var.enable_ssl ? "https://${var.custom_domain}" : "http://${var.custom_domain}") : "Custom domain not configured"
}

# API Configuration and Authentication
output "endpoints_service_name" {
  description = "Cloud Endpoints service name for the API"
  value       = google_endpoints_service.api_service.service_name
}

output "api_key" {
  description = "API key for authenticating requests to the API gateway"
  value       = google_apikeys_key.api_key.key_string
  sensitive   = true
}

output "api_config_id" {
  description = "Configuration ID for the deployed API service"
  value       = google_endpoints_service.api_service.config_id
}

# Security Configuration
output "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = google_compute_security_policy.api_security_policy.name
}

output "security_policy_id" {
  description = "ID of the Cloud Armor security policy"
  value       = google_compute_security_policy.api_security_policy.id
}

output "rate_limit_configuration" {
  description = "Rate limiting configuration applied by Cloud Armor"
  value = {
    threshold_per_minute = var.rate_limit_threshold
    ban_duration_seconds = var.ban_duration_sec
  }
}

output "blocked_countries" {
  description = "List of country codes blocked by geographic restriction rules"
  value       = var.enable_geo_restriction ? var.blocked_countries : []
}

# Backend Infrastructure
output "backend_service_name" {
  description = "Name of the backend service VM instance"
  value       = google_compute_instance.backend_service.name
}

output "backend_service_internal_ip" {
  description = "Internal IP address of the backend service"
  value       = google_compute_instance.backend_service.network_interface[0].network_ip
}

output "esp_proxy_name" {
  description = "Name of the ESP proxy VM instance"
  value       = google_compute_instance.esp_proxy.name
}

output "esp_proxy_external_ip" {
  description = "External IP address of the ESP proxy"
  value       = google_compute_instance.esp_proxy.network_interface[0].access_config[0].nat_ip
}

# Load Balancer Configuration
output "backend_service_id" {
  description = "ID of the load balancer backend service"
  value       = google_compute_backend_service.esp_backend_service.id
}

output "url_map_id" {
  description = "ID of the load balancer URL map"
  value       = google_compute_url_map.esp_url_map.id
}

output "health_check_name" {
  description = "Name of the health check for backend services"
  value       = google_compute_health_check.esp_health_check.name
}

# SSL/TLS Configuration (if enabled)
output "ssl_certificate_name" {
  description = "Name of the managed SSL certificate (only if SSL is enabled)"
  value       = var.enable_ssl && var.custom_domain != "" ? google_compute_managed_ssl_certificate.esp_ssl_cert[0].name : "SSL not enabled or custom domain not configured"
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate (only if SSL is enabled)"
  value       = var.enable_ssl && var.custom_domain != "" ? google_compute_managed_ssl_certificate.esp_ssl_cert[0].managed[0].status : "SSL not enabled or custom domain not configured"
}

# Testing and Validation Information
output "test_endpoints" {
  description = "Available API endpoints for testing"
  value = {
    health_check     = "${google_compute_global_address.esp_gateway_ip.address}/health"
    authenticated_users = "${google_compute_global_address.esp_gateway_ip.address}/api/v1/users?key=YOUR_API_KEY"
    authenticated_data  = "${google_compute_global_address.esp_gateway_ip.address}/api/v1/data?key=YOUR_API_KEY"
  }
}

output "curl_test_commands" {
  description = "Example curl commands for testing the API gateway"
  value = {
    unauthenticated = "curl -w '%{http_code}\\n' -o /dev/null -s http://${google_compute_global_address.esp_gateway_ip.address}/api/v1/users"
    authenticated   = "curl -w '%{http_code}\\n' -s 'http://${google_compute_global_address.esp_gateway_ip.address}/api/v1/users?key=${google_apikeys_key.api_key.key_string}'"
    health_check    = "curl -s http://${google_compute_global_address.esp_gateway_ip.address}/health"
    rate_limit_test = "for i in {1..110}; do curl -s -o /dev/null -w '%{http_code} ' 'http://${google_compute_global_address.esp_gateway_ip.address}/health?key=${google_apikeys_key.api_key.key_string}'; done"
  }
  sensitive = true
}

# Service Account Information
output "backend_service_account_email" {
  description = "Email of the service account used by the backend service"
  value       = google_service_account.backend_service.email
}

output "esp_proxy_service_account_email" {
  description = "Email of the service account used by the ESP proxy"
  value       = google_service_account.esp_proxy.email
}

# Resource Labels and Tags
output "resource_labels" {
  description = "Labels applied to all resources for management and billing"
  value       = local.common_labels
}

# Monitoring and Logging
output "monitoring_enabled" {
  description = "Whether Cloud Monitoring and logging are enabled"
  value       = var.enable_monitoring
}

output "log_configuration" {
  description = "Load balancer logging configuration"
  value = var.enable_monitoring ? {
    enabled     = true
    sample_rate = 1.0
  } : {
    enabled = false
  }
}

# Cost and Resource Summary
output "resource_summary" {
  description = "Summary of created resources for cost estimation"
  value = {
    compute_instances = {
      backend_service = {
        machine_type = var.backend_machine_type
        zone         = var.zone
      }
      esp_proxy = {
        machine_type = var.esp_machine_type
        zone         = var.zone
      }
    }
    load_balancer = {
      type                = "Global HTTP(S) Load Balancer"
      security_policy     = "Cloud Armor WAF"
      health_checks       = 1
      backend_services    = 1
    }
    networking = {
      static_ip_addresses = 1
      firewall_rules      = 1
    }
    apis = {
      endpoints_service = 1
      api_keys         = 1
    }
  }
}