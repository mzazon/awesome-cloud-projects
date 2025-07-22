# Output Values for GCP Edge Caching Performance Recipe
# This file defines all output values that provide important information
# about the deployed infrastructure

# Network Infrastructure Outputs
output "network_id" {
  description = "ID of the VPC network created for CDN infrastructure"
  value       = google_compute_network.cdn_network.id
}

output "network_name" {
  description = "Name of the VPC network created for CDN infrastructure"
  value       = google_compute_network.cdn_network.name
}

output "network_self_link" {
  description = "Self-link of the VPC network created for CDN infrastructure"
  value       = google_compute_network.cdn_network.self_link
}

output "subnet_id" {
  description = "ID of the subnet created for cache infrastructure"
  value       = google_compute_subnetwork.cdn_subnet.id
}

output "subnet_name" {
  description = "Name of the subnet created for cache infrastructure"
  value       = google_compute_subnetwork.cdn_subnet.name
}

output "subnet_cidr" {
  description = "CIDR block of the subnet created for cache infrastructure"
  value       = google_compute_subnetwork.cdn_subnet.ip_cidr_range
}

# Redis Cache Outputs
output "redis_instance_id" {
  description = "ID of the Redis instance created for caching"
  value       = google_redis_instance.cache_instance.id
}

output "redis_instance_name" {
  description = "Name of the Redis instance created for caching"
  value       = google_redis_instance.cache_instance.name
}

output "redis_host" {
  description = "IP address of the Redis instance for connection"
  value       = google_redis_instance.cache_instance.host
  sensitive   = true
}

output "redis_port" {
  description = "Port number of the Redis instance for connection"
  value       = google_redis_instance.cache_instance.port
}

output "redis_auth_string" {
  description = "Auth string for Redis instance (if auth is enabled)"
  value       = google_redis_instance.cache_instance.auth_string
  sensitive   = true
}

output "redis_memory_size_gb" {
  description = "Memory size in GB of the Redis instance"
  value       = google_redis_instance.cache_instance.memory_size_gb
}

output "redis_tier" {
  description = "Service tier of the Redis instance"
  value       = google_redis_instance.cache_instance.tier
}

output "redis_version" {
  description = "Version of the Redis instance"
  value       = google_redis_instance.cache_instance.redis_version
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket created for origin content"
  value       = google_storage_bucket.origin_content.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket created for origin content"
  value       = google_storage_bucket.origin_content.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket created for origin content"
  value       = google_storage_bucket.origin_content.self_link
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.origin_content.location
}

output "storage_bucket_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.origin_content.storage_class
}

# CDN and Load Balancer Outputs
output "cdn_ip_address" {
  description = "Static IP address for the CDN endpoint"
  value       = google_compute_global_address.cdn_ip_address.address
}

output "cdn_endpoint_url" {
  description = "Primary URL endpoint for accessing the CDN"
  value       = var.enable_ssl ? "https://${google_compute_global_address.cdn_ip_address.address}" : "http://${google_compute_global_address.cdn_ip_address.address}"
}

output "backend_service_id" {
  description = "ID of the backend service created for CDN"
  value       = google_compute_backend_service.cdn_backend_service.id
}

output "backend_service_name" {
  description = "Name of the backend service created for CDN"
  value       = google_compute_backend_service.cdn_backend_service.name
}

output "backend_service_self_link" {
  description = "Self-link of the backend service created for CDN"
  value       = google_compute_backend_service.cdn_backend_service.self_link
}

output "url_map_id" {
  description = "ID of the URL map created for traffic routing"
  value       = google_compute_url_map.cdn_url_map.id
}

output "url_map_name" {
  description = "Name of the URL map created for traffic routing"
  value       = google_compute_url_map.cdn_url_map.name
}

output "health_check_id" {
  description = "ID of the health check created for backend services"
  value       = google_compute_health_check.cdn_health_check.id
}

output "health_check_name" {
  description = "Name of the health check created for backend services"
  value       = google_compute_health_check.cdn_health_check.name
}

# SSL Certificate Outputs (conditional)
output "ssl_certificate_id" {
  description = "ID of the SSL certificate (if SSL is enabled)"
  value       = var.enable_ssl ? google_compute_managed_ssl_certificate.cdn_ssl_cert[0].id : null
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate (if SSL is enabled)"
  value       = var.enable_ssl ? google_compute_managed_ssl_certificate.cdn_ssl_cert[0].name : null
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate (if SSL is enabled)"
  value       = var.enable_ssl ? google_compute_managed_ssl_certificate.cdn_ssl_cert[0].managed[0].domains : null
}

# Forwarding Rule Outputs
output "forwarding_rule_http_id" {
  description = "ID of the HTTP forwarding rule"
  value       = google_compute_global_forwarding_rule.cdn_forwarding_rule_http.id
}

output "forwarding_rule_http_name" {
  description = "Name of the HTTP forwarding rule"
  value       = google_compute_global_forwarding_rule.cdn_forwarding_rule_http.name
}

output "forwarding_rule_https_id" {
  description = "ID of the HTTPS forwarding rule (if SSL is enabled)"
  value       = var.enable_ssl ? google_compute_global_forwarding_rule.cdn_forwarding_rule_https[0].id : null
}

output "forwarding_rule_https_name" {
  description = "Name of the HTTPS forwarding rule (if SSL is enabled)"
  value       = var.enable_ssl ? google_compute_global_forwarding_rule.cdn_forwarding_rule_https[0].name : null
}

# Monitoring Outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_monitoring_dashboard.cdn_performance_dashboard[0].id : null
}

output "alert_policy_id" {
  description = "ID of the cache hit ratio alert policy (if monitoring is enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.low_cache_hit_ratio[0].name : null
}

output "logging_sink_id" {
  description = "ID of the logging sink (if logging is enabled)"
  value       = var.enable_logging ? google_logging_project_sink.cdn_logs_sink[0].id : null
}

output "logging_sink_destination" {
  description = "Destination of the logging sink (if logging is enabled)"
  value       = var.enable_logging ? google_logging_project_sink.cdn_logs_sink[0].destination : null
}

# Firewall Rules Outputs
output "firewall_health_check_id" {
  description = "ID of the firewall rule for health checks"
  value       = google_compute_firewall.allow_health_check.id
}

output "firewall_cdn_traffic_id" {
  description = "ID of the firewall rule for CDN traffic"
  value       = google_compute_firewall.allow_cdn_traffic.id
}

# Router and NAT Outputs
output "router_id" {
  description = "ID of the Cloud Router created for NAT"
  value       = google_compute_router.cdn_router.id
}

output "router_name" {
  description = "Name of the Cloud Router created for NAT"
  value       = google_compute_router.cdn_router.name
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway created for outbound access"
  value       = google_compute_router_nat.cdn_nat.id
}

output "nat_gateway_name" {
  description = "Name of the NAT gateway created for outbound access"
  value       = google_compute_router_nat.cdn_nat.name
}

# Sample Content Outputs
output "sample_content_urls" {
  description = "URLs for accessing sample content through the CDN"
  value = {
    index_html      = "${var.enable_ssl ? "https" : "http"}://${google_compute_global_address.cdn_ip_address.address}/index.html"
    api_response    = "${var.enable_ssl ? "https" : "http"}://${google_compute_global_address.cdn_ip_address.address}/api-response.json"
  }
}

# Infrastructure Metadata
output "deployment_id" {
  description = "Unique deployment identifier for this infrastructure"
  value       = local.resource_suffix
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

output "project_id" {
  description = "GCP project ID where resources are deployed"
  value       = var.project_id
}

output "region" {
  description = "GCP region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "GCP zone where resources are deployed"
  value       = var.zone
}

# Connection Information
output "redis_connection_info" {
  description = "Redis connection information for applications"
  value = {
    host                = google_redis_instance.cache_instance.host
    port                = google_redis_instance.cache_instance.port
    auth_enabled        = google_redis_instance.cache_instance.auth_enabled
    transit_encryption  = google_redis_instance.cache_instance.transit_encryption_mode
    memory_size_gb      = google_redis_instance.cache_instance.memory_size_gb
    tier               = google_redis_instance.cache_instance.tier
  }
  sensitive = true
}

output "cdn_cache_configuration" {
  description = "CDN cache configuration details"
  value = {
    cache_mode   = google_compute_backend_service.cdn_backend_service.cdn_policy[0].cache_mode
    default_ttl  = google_compute_backend_service.cdn_backend_service.cdn_policy[0].default_ttl
    max_ttl      = google_compute_backend_service.cdn_backend_service.cdn_policy[0].max_ttl
    client_ttl   = google_compute_backend_service.cdn_backend_service.cdn_policy[0].client_ttl
  }
}

# Validation Commands
output "validation_commands" {
  description = "Commands to validate the deployed infrastructure"
  value = {
    test_cdn_endpoint = "curl -I ${var.enable_ssl ? "https" : "http"}://${google_compute_global_address.cdn_ip_address.address}/"
    test_cache_hit    = "curl -v ${var.enable_ssl ? "https" : "http"}://${google_compute_global_address.cdn_ip_address.address}/ | grep -i 'x-cache'"
    check_redis       = "gcloud redis instances describe ${google_redis_instance.cache_instance.name} --region ${var.region}"
    check_bucket      = "gsutil ls -b gs://${google_storage_bucket.origin_content.name}"
  }
}

# Performance Monitoring URLs
output "monitoring_urls" {
  description = "URLs for monitoring and observability dashboards"
  value = var.enable_monitoring ? {
    dashboard_url = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.cdn_performance_dashboard[0].id}?project=${var.project_id}"
    metrics_url   = "https://console.cloud.google.com/monitoring/metrics-explorer?project=${var.project_id}"
    logs_url      = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  } : {}
}

# Cost Estimation Information
output "cost_estimation" {
  description = "Estimated monthly costs for the deployed infrastructure"
  value = {
    note = "Actual costs may vary based on usage patterns and data transfer volumes"
    components = {
      redis_instance    = "~$${var.redis_memory_size_gb * 0.049} per GB/month"
      cloud_storage     = "~$0.020 per GB/month for ${var.storage_class} class"
      cdn_traffic       = "~$0.08-0.20 per GB for egress traffic"
      load_balancer     = "~$18 per month base cost"
      monitoring        = "Free tier available, $0.258 per MB for custom metrics"
    }
  }
}

# Security Information
output "security_features" {
  description = "Security features enabled in the deployment"
  value = {
    redis_auth_enabled           = google_redis_instance.cache_instance.auth_enabled
    redis_transit_encryption     = google_redis_instance.cache_instance.transit_encryption_mode
    bucket_uniform_access        = google_storage_bucket.origin_content.uniform_bucket_level_access
    ssl_enabled                  = var.enable_ssl
    private_google_access        = google_compute_subnetwork.cdn_subnet.private_ip_google_access
    firewall_rules_configured    = true
    nat_gateway_configured       = true
  }
}