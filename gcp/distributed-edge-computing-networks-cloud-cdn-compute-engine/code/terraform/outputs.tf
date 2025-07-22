# Output Values for Distributed Edge Computing Network
# This file defines outputs that provide important information about the deployed infrastructure

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "network_name" {
  description = "Name of the global VPC network"
  value       = google_compute_network.edge_network.name
}

output "network_id" {
  description = "Full resource ID of the global VPC network"
  value       = google_compute_network.edge_network.id
}

output "global_ip_address" {
  description = "Global static IP address for the edge computing network"
  value       = google_compute_global_address.edge_global_ip.address
}

output "load_balancer_url" {
  description = "URL to access the global load balancer"
  value       = "http://${google_compute_global_address.edge_global_ip.address}"
}

output "domain_url" {
  description = "URL using the configured domain name (if DNS is enabled)"
  value       = var.enable_dns ? "http://${var.domain_name}" : "N/A - DNS not enabled"
}

output "regional_subnets" {
  description = "Map of regional subnets created for edge computing clusters"
  value = {
    for region, subnet in google_compute_subnetwork.regional_subnets : 
    region => {
      name       = subnet.name
      cidr_range = subnet.ip_cidr_range
      region     = subnet.region
      id         = subnet.id
    }
  }
}

output "edge_clusters" {
  description = "Information about regional edge computing clusters"
  value = {
    for region, cluster in google_compute_region_instance_group_manager.edge_clusters :
    region => {
      name           = cluster.name
      instance_group = cluster.instance_group
      target_size    = cluster.target_size
      region         = cluster.region
      base_instance_name = cluster.base_instance_name
    }
  }
}

output "backend_service_name" {
  description = "Name of the backend service with CDN enabled"
  value       = google_compute_backend_service.edge_backend_service.name
}

output "backend_service_id" {
  description = "Full resource ID of the backend service"
  value       = google_compute_backend_service.edge_backend_service.id
}

output "cdn_configuration" {
  description = "CDN configuration details"
  value = {
    enabled       = google_compute_backend_service.edge_backend_service.enable_cdn
    cache_mode    = var.cdn_cache_mode
    default_ttl   = var.cdn_default_ttl
    max_ttl      = var.cdn_max_ttl
    client_ttl   = var.cdn_client_ttl
  }
}

output "health_check_name" {
  description = "Name of the health check used by the backend service"
  value       = google_compute_health_check.edge_health_check.name
}

output "health_check_path" {
  description = "Health check endpoint path"
  value       = var.health_check_path
}

output "autoscaling_configuration" {
  description = "Autoscaling configuration for edge clusters"
  value = {
    min_replicas              = var.min_replicas
    max_replicas              = var.max_replicas
    target_cpu_utilization    = var.target_cpu_utilization
    regions                   = var.regions
  }
}

output "storage_buckets" {
  description = "Cloud Storage buckets created as content origins (if enabled)"
  value = var.enable_storage_origins ? {
    for region, bucket in google_storage_bucket.content_origins :
    region => {
      name         = bucket.name
      url          = bucket.url
      location     = bucket.location
      storage_class = bucket.storage_class
    }
  } : {}
}

output "dns_configuration" {
  description = "DNS configuration details (if enabled)"
  value = var.enable_dns ? {
    zone_name    = google_dns_managed_zone.edge_zone[0].name
    dns_name     = google_dns_managed_zone.edge_zone[0].dns_name
    name_servers = google_dns_managed_zone.edge_zone[0].name_servers
    domain       = var.domain_name
  } : null
}

output "firewall_rules" {
  description = "Firewall rules created for edge computing network"
  value = {
    web_traffic = {
      name   = google_compute_firewall.allow_web_traffic.name
      ports  = ["80", "443", "8080"]
      source = "0.0.0.0/0"
    }
    health_checks = {
      name   = google_compute_firewall.allow_health_checks.name
      ports  = ["80", "443", "8080"]
      source = "Google Cloud Load Balancing"
    }
    internal = {
      name   = google_compute_firewall.allow_internal.name
      ports  = "All"
      source = "10.0.0.0/8"
    }
  }
}

output "machine_type" {
  description = "Machine type used for edge computing instances"
  value       = var.machine_type
}

output "regions_deployed" {
  description = "List of regions where edge clusters are deployed"
  value       = var.regions
}

output "resource_suffix" {
  description = "Random suffix used for unique resource naming"
  value       = local.resource_suffix
}

output "deployment_info" {
  description = "Summary of the deployed edge computing infrastructure"
  value = {
    total_regions       = length(var.regions)
    global_ip          = google_compute_global_address.edge_global_ip.address
    cdn_enabled        = google_compute_backend_service.edge_backend_service.enable_cdn
    dns_enabled        = var.enable_dns
    storage_enabled    = var.enable_storage_origins
    logging_enabled    = var.enable_logging
    deployment_id      = local.resource_suffix
  }
}

output "testing_endpoints" {
  description = "Endpoints for testing the edge computing network"
  value = {
    load_balancer = "curl -H 'Host: ${var.domain_name}' http://${google_compute_global_address.edge_global_ip.address}/"
    health_check  = "curl -H 'Host: ${var.domain_name}' http://${google_compute_global_address.edge_global_ip.address}/health"
    domain_test   = var.enable_dns ? "curl http://${var.domain_name}/" : "N/A - DNS not enabled"
    cache_test    = "curl -I -H 'Host: ${var.domain_name}' http://${google_compute_global_address.edge_global_ip.address}/"
  }
}

output "management_commands" {
  description = "Useful gcloud commands for managing the infrastructure"
  value = {
    view_instances = "gcloud compute instances list --filter='tags.items:edge-server'"
    check_health   = "gcloud compute backend-services get-health ${google_compute_backend_service.edge_backend_service.name} --global"
    view_logs      = var.enable_logging ? "gcloud logging read 'resource.type=\"http_load_balancer\"'" : "Logging not enabled"
    cdn_cache_invalidate = "gcloud compute url-maps invalidate-cdn-cache ${google_compute_url_map.edge_url_map.name} --path '/*'"
  }
}

output "cost_optimization_tips" {
  description = "Tips for optimizing costs of the edge computing infrastructure"
  value = [
    "Monitor autoscaling metrics to adjust min/max replicas based on actual usage",
    "Use preemptible instances for non-critical workloads to reduce costs",
    "Optimize CDN cache TTL values to reduce origin server load",
    "Consider using Committed Use Discounts for predictable workloads",
    "Review storage class for content origins based on access patterns",
    "Enable detailed monitoring only when needed to reduce logging costs"
  ]
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "Configure SSL certificates for HTTPS support",
    "Set up Cloud Monitoring dashboards for performance tracking",
    "Implement Cloud Armor security policies for DDoS protection",
    "Configure log-based metrics for detailed traffic analysis",
    "Set up alerting policies for health check failures",
    "Consider implementing cache warming strategies for improved performance"
  ]
}