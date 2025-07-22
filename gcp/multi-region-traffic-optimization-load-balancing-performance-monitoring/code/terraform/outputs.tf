# Global Load Balancer Outputs
output "global_load_balancer_ip" {
  description = "Global external IP address of the load balancer"
  value       = google_compute_global_forwarding_rule.global_http_rule.ip_address
}

output "global_load_balancer_url" {
  description = "Global URL for accessing the load balanced application"
  value       = "http://${google_compute_global_forwarding_rule.global_http_rule.ip_address}"
}

output "https_load_balancer_ip" {
  description = "Global external IP address for HTTPS traffic (if SSL enabled)"
  value       = length(google_compute_global_forwarding_rule.global_https_rule) > 0 ? google_compute_global_forwarding_rule.global_https_rule[0].ip_address : null
}

output "https_load_balancer_url" {
  description = "Global HTTPS URL for accessing the load balanced application (if SSL enabled)"
  value       = length(google_compute_global_forwarding_rule.global_https_rule) > 0 ? "https://${google_compute_global_forwarding_rule.global_https_rule[0].ip_address}" : null
}

# Backend Service Information
output "backend_service_id" {
  description = "ID of the global backend service"
  value       = google_compute_backend_service.global_backend.id
}

output "backend_service_name" {
  description = "Name of the global backend service"
  value       = google_compute_backend_service.global_backend.name
}

output "cdn_enabled" {
  description = "Whether Cloud CDN is enabled on the backend service"
  value       = google_compute_backend_service.global_backend.enable_cdn
}

# Regional Instance Groups
output "instance_groups" {
  description = "Information about regional managed instance groups"
  value = {
    for region, group in google_compute_instance_group_manager.regional_groups : region => {
      name           = group.name
      instance_group = group.instance_group
      zone           = group.zone
      target_size    = group.target_size
      status         = group.status
    }
  }
}

# Network Infrastructure
output "vpc_network_id" {
  description = "ID of the global VPC network"
  value       = google_compute_network.global_vpc.id
}

output "vpc_network_name" {
  description = "Name of the global VPC network"
  value       = google_compute_network.global_vpc.name
}

output "regional_subnets" {
  description = "Information about regional subnets"
  value = {
    for region, subnet in google_compute_subnetwork.regional_subnets : region => {
      name        = subnet.name
      ip_range    = subnet.ip_cidr_range
      region      = subnet.region
      self_link   = subnet.self_link
      gateway_ip  = subnet.gateway_address
    }
  }
}

# Health Check Information
output "health_check_id" {
  description = "ID of the global health check"
  value       = google_compute_health_check.app_health_check.id
}

output "health_check_name" {
  description = "Name of the global health check"
  value       = google_compute_health_check.app_health_check.name
}

# Service Account Information
output "service_account_email" {
  description = "Email of the service account used by application instances"
  value       = google_service_account.app_service_account.email
}

# Monitoring and Observability
output "uptime_check_id" {
  description = "ID of the global uptime check (if monitoring enabled)"
  value       = length(google_monitoring_uptime_check_config.global_app_uptime) > 0 ? google_monitoring_uptime_check_config.global_app_uptime[0].uptime_check_id : null
}

output "alert_policy_id" {
  description = "ID of the high latency alert policy (if monitoring enabled)"
  value       = length(google_monitoring_alert_policy.high_latency_alert) > 0 ? google_monitoring_alert_policy.high_latency_alert[0].name : null
}

# Network Intelligence Center
output "connectivity_tests" {
  description = "Information about Network Intelligence Center connectivity tests"
  value = var.enable_network_intelligence ? {
    for test_name, test in google_network_management_connectivity_test.inter_region_tests : test_name => {
      name   = test.name
      source = test.source
      destination = test.destination
    }
  } : {}
}

# Cloud NAT Information
output "cloud_nat_routers" {
  description = "Information about Cloud NAT routers in each region"
  value = {
    for region, router in google_compute_router.regional_routers : region => {
      name   = router.name
      region = router.region
    }
  }
}

output "cloud_nat_gateways" {
  description = "Information about Cloud NAT gateways in each region"
  value = {
    for region, nat in google_compute_router_nat.regional_nat : region => {
      name   = nat.name
      region = nat.region
    }
  }
}

# URL Map and Proxy Information
output "url_map_id" {
  description = "ID of the global URL map"
  value       = google_compute_url_map.global_url_map.id
}

output "http_proxy_id" {
  description = "ID of the target HTTP proxy"
  value       = google_compute_target_http_proxy.global_http_proxy.id
}

output "https_proxy_id" {
  description = "ID of the target HTTPS proxy (if SSL enabled)"
  value       = length(google_compute_target_https_proxy.global_https_proxy) > 0 ? google_compute_target_https_proxy.global_https_proxy[0].id : null
}

# Configuration Summary
output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_id       = var.project_id
    resource_prefix  = var.resource_prefix
    resource_suffix  = local.resource_suffix
    regions_deployed = keys(local.regions)
    total_instances  = var.instance_group_size * length(local.regions)
    load_balancer_ip = google_compute_global_forwarding_rule.global_http_rule.ip_address
    cdn_enabled      = google_compute_backend_service.global_backend.enable_cdn
    monitoring_enabled = var.enable_monitoring
    network_intelligence_enabled = var.enable_network_intelligence
  }
}

# Testing and Validation URLs
output "validation_commands" {
  description = "Commands for testing and validating the deployment"
  value = {
    curl_test = "curl http://${google_compute_global_forwarding_rule.global_http_rule.ip_address}"
    cdn_test  = "curl -I http://${google_compute_global_forwarding_rule.global_http_rule.ip_address}"
    load_test = "for i in {1..10}; do curl http://${google_compute_global_forwarding_rule.global_http_rule.ip_address} | grep 'Serving from'; sleep 1; done"
  }
}

# Console URLs for Monitoring
output "console_urls" {
  description = "Google Cloud Console URLs for monitoring and management"
  value = {
    load_balancer = "https://console.cloud.google.com/net-services/loadbalancing/loadBalancers/list?project=${var.project_id}"
    monitoring    = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
    network_intelligence = "https://console.cloud.google.com/net-intelligence?project=${var.project_id}"
    cdn           = "https://console.cloud.google.com/net-services/cdn/list?project=${var.project_id}"
    compute       = "https://console.cloud.google.com/compute/instances?project=${var.project_id}"
  }
}

# Resource Names for External Tools
output "resource_names" {
  description = "Names of created resources for use with external tools"
  value = {
    vpc_network      = google_compute_network.global_vpc.name
    backend_service  = google_compute_backend_service.global_backend.name
    url_map         = google_compute_url_map.global_url_map.name
    health_check    = google_compute_health_check.app_health_check.name
    instance_template = google_compute_instance_template.app_template.name
    instance_groups = {
      for region, group in google_compute_instance_group_manager.regional_groups : region => group.name
    }
  }
}