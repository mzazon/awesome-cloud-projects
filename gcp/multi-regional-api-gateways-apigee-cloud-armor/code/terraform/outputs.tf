# Project and infrastructure information
output "project_id" {
  description = "The Google Cloud project ID where resources were created"
  value       = var.project_id
}

output "resource_suffix" {
  description = "The generated suffix used for resource naming"
  value       = local.resource_suffix
}

# Network infrastructure outputs
output "network_id" {
  description = "The ID of the created VPC network"
  value       = google_compute_network.apigee_network.id
}

output "network_name" {
  description = "The name of the created VPC network"
  value       = google_compute_network.apigee_network.name
}

output "network_self_link" {
  description = "The self-link of the created VPC network"
  value       = google_compute_network.apigee_network.self_link
}

output "subnet_us_id" {
  description = "The ID of the US region subnet"
  value       = google_compute_subnetwork.apigee_subnet_us.id
}

output "subnet_us_cidr" {
  description = "The CIDR range of the US region subnet"
  value       = google_compute_subnetwork.apigee_subnet_us.ip_cidr_range
}

output "subnet_eu_id" {
  description = "The ID of the EU region subnet"
  value       = google_compute_subnetwork.apigee_subnet_eu.id
}

output "subnet_eu_cidr" {
  description = "The CIDR range of the EU region subnet"
  value       = google_compute_subnetwork.apigee_subnet_eu.ip_cidr_range
}

# Apigee infrastructure outputs
output "apigee_organization_name" {
  description = "The name of the Apigee organization"
  value       = google_apigee_organization.main.name
}

output "apigee_organization_id" {
  description = "The ID of the Apigee organization"
  value       = google_apigee_organization.main.id
}

output "apigee_organization_runtime_type" {
  description = "The runtime type of the Apigee organization"
  value       = google_apigee_organization.main.runtime_type
}

output "apigee_organization_billing_type" {
  description = "The billing type of the Apigee organization"
  value       = google_apigee_organization.main.billing_type
}

output "apigee_instance_us_id" {
  description = "The ID of the Apigee instance in the US region"
  value       = google_apigee_instance.us_instance.id
}

output "apigee_instance_us_host" {
  description = "The host address of the Apigee instance in the US region"
  value       = google_apigee_instance.us_instance.host
}

output "apigee_instance_us_service_attachment" {
  description = "The service attachment of the Apigee instance in the US region"
  value       = google_apigee_instance.us_instance.service_attachment
}

output "apigee_instance_eu_id" {
  description = "The ID of the Apigee instance in the EU region"
  value       = google_apigee_instance.eu_instance.id
}

output "apigee_instance_eu_host" {
  description = "The host address of the Apigee instance in the EU region"
  value       = google_apigee_instance.eu_instance.host
}

output "apigee_instance_eu_service_attachment" {
  description = "The service attachment of the Apigee instance in the EU region"
  value       = google_apigee_instance.eu_instance.service_attachment
}

output "apigee_environment_us_name" {
  description = "The name of the Apigee environment in the US region"
  value       = google_apigee_environment.production_us.name
}

output "apigee_environment_eu_name" {
  description = "The name of the Apigee environment in the EU region"
  value       = google_apigee_environment.production_eu.name
}

output "apigee_envgroup_us_hostnames" {
  description = "The hostnames configured for the US environment group"
  value       = google_apigee_envgroup.prod_us.hostnames
}

output "apigee_envgroup_eu_hostnames" {
  description = "The hostnames configured for the EU environment group"
  value       = google_apigee_envgroup.prod_eu.hostnames
}

# Load balancer and networking outputs
output "global_ip_address" {
  description = "The global static IP address for the load balancer"
  value       = google_compute_global_address.api_ip.address
}

output "global_ip_name" {
  description = "The name of the global static IP address"
  value       = google_compute_global_address.api_ip.name
}

output "load_balancer_url_map_id" {
  description = "The ID of the load balancer URL map"
  value       = google_compute_url_map.api_url_map.id
}

output "backend_service_us_id" {
  description = "The ID of the US region backend service"
  value       = google_compute_backend_service.apigee_backend_us.id
}

output "backend_service_eu_id" {
  description = "The ID of the EU region backend service"
  value       = google_compute_backend_service.apigee_backend_eu.id
}

# Security and SSL outputs
output "cloud_armor_policy_id" {
  description = "The ID of the Cloud Armor security policy"
  value       = google_compute_security_policy.api_security_policy.id
}

output "cloud_armor_policy_name" {
  description = "The name of the Cloud Armor security policy"
  value       = google_compute_security_policy.api_security_policy.name
}

output "cloud_armor_policy_fingerprint" {
  description = "The fingerprint of the Cloud Armor security policy"
  value       = google_compute_security_policy.api_security_policy.fingerprint
}

output "ssl_certificate_id" {
  description = "The ID of the managed SSL certificate (if created)"
  value       = length(var.domain_names) > 0 ? google_compute_managed_ssl_certificate.api_ssl_cert[0].id : null
}

output "ssl_certificate_name" {
  description = "The name of the managed SSL certificate (if created)"
  value       = length(var.domain_names) > 0 ? google_compute_managed_ssl_certificate.api_ssl_cert[0].name : null
}

output "ssl_certificate_domains" {
  description = "The domains covered by the SSL certificate"
  value       = length(var.domain_names) > 0 ? google_compute_managed_ssl_certificate.api_ssl_cert[0].managed[0].domains : []
}

output "ssl_policy_id" {
  description = "The ID of the SSL policy"
  value       = google_compute_ssl_policy.api_ssl_policy.id
}

output "ssl_policy_name" {
  description = "The name of the SSL policy"
  value       = google_compute_ssl_policy.api_ssl_policy.name
}

# Health check outputs
output "health_check_id" {
  description = "The ID of the health check"
  value       = google_compute_health_check.api_health_check.id
}

output "health_check_self_link" {
  description = "The self-link of the health check"
  value       = google_compute_health_check.api_health_check.self_link
}

# DNS configuration guidance
output "dns_configuration" {
  description = "DNS configuration instructions for the deployed domains"
  value = length(var.domain_names) > 0 ? {
    for domain in var.domain_names : domain => {
      type    = "A"
      name    = domain
      value   = google_compute_global_address.api_ip.address
      ttl     = 300
      message = "Create an A record for ${domain} pointing to ${google_compute_global_address.api_ip.address}"
    }
  } : {
    message = "No domains configured. Use the global IP address: ${google_compute_global_address.api_ip.address}"
  }
}

# API endpoint URLs
output "api_endpoints" {
  description = "The API endpoint URLs for testing"
  value = {
    global_ip = "https://${google_compute_global_address.api_ip.address}"
    us_domain = length(var.domain_names) > 0 ? "https://${var.domain_names[0]}" : "Configure domain and update DNS"
    eu_domain = length(var.domain_names) > 1 ? "https://${var.domain_names[1]}" : "Configure domain and update DNS"
    
    # Test endpoints
    test_endpoints = {
      health_check = length(var.domain_names) > 0 ? "https://${var.domain_names[0]}${var.health_check_path}" : "https://${google_compute_global_address.api_ip.address}${var.health_check_path}"
      api_v1       = length(var.domain_names) > 0 ? "https://${var.domain_names[0]}/api/v1" : "https://${google_compute_global_address.api_ip.address}/api/v1"
      eu_api       = length(var.domain_names) > 1 ? "https://${var.domain_names[1]}/eu/api/v1" : "https://${google_compute_global_address.api_ip.address}/eu/api/v1"
    }
  }
}

# Deployment status and next steps
output "deployment_status" {
  description = "Deployment status and next steps"
  value = {
    status = "Deployment completed successfully"
    next_steps = [
      "Configure DNS records for your domains (see dns_configuration output)",
      "Wait for SSL certificate provisioning to complete (may take up to 60 minutes)",
      "Deploy API proxies to the Apigee environments",
      "Test the endpoints using the api_endpoints output",
      "Monitor security events in Cloud Armor logs",
      "Review and adjust Cloud Armor security rules as needed"
    ]
    documentation = [
      "Apigee Console: https://apigee.google.com/",
      "Cloud Armor documentation: https://cloud.google.com/armor/docs",
      "Load Balancing documentation: https://cloud.google.com/load-balancing/docs"
    ]
  }
}

# Resource monitoring and management
output "monitoring_dashboard_urls" {
  description = "URLs for monitoring dashboards"
  value = {
    cloud_monitoring = "https://console.cloud.google.com/monitoring/dashboards?project=${var.project_id}"
    cloud_logging    = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    apigee_analytics = "https://apigee.google.com/analytics"
    cloud_armor      = "https://console.cloud.google.com/net-security/securitypolicies/list?project=${var.project_id}"
    load_balancing   = "https://console.cloud.google.com/net-services/loadbalancing/list/loadBalancers?project=${var.project_id}"
  }
}

# Cost optimization recommendations
output "cost_optimization" {
  description = "Cost optimization recommendations"
  value = {
    recommendations = [
      "Monitor Apigee API call volumes and adjust billing plan if needed",
      "Review Cloud Armor rules regularly to ensure efficiency",
      "Use budget alerts to monitor spending",
      "Consider using reserved instances for predictable workloads",
      "Review and optimize health check frequency"
    ]
    estimated_monthly_cost = "Varies based on API traffic volume. Review Apigee pricing for estimates."
  }
}