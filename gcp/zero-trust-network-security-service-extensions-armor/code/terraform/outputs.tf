# Outputs for zero-trust network security infrastructure

# Network Information
output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.zero_trust_vpc.id
}

output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.zero_trust_vpc.name
}

output "subnet_id" {
  description = "ID of the private subnet"
  value       = google_compute_subnetwork.private_subnet.id
}

output "subnet_cidr" {
  description = "CIDR block of the private subnet"
  value       = google_compute_subnetwork.private_subnet.ip_cidr_range
}

# Load Balancer Information
output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = google_compute_global_address.default.address
}

output "load_balancer_url" {
  description = "HTTPS URL of the load balancer"
  value       = "https://${google_compute_global_address.default.address}"
}

output "ssl_certificate_domains" {
  description = "Domains covered by the SSL certificate"
  value       = google_compute_managed_ssl_certificate.default.managed[0].domains
}

# Security Configuration
output "security_policy_id" {
  description = "ID of the Cloud Armor security policy"
  value       = google_compute_security_policy.zero_trust_policy.id
}

output "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = google_compute_security_policy.zero_trust_policy.name
}

output "security_policy_fingerprint" {
  description = "Fingerprint of the Cloud Armor security policy"
  value       = google_compute_security_policy.zero_trust_policy.fingerprint
}

# Service Extension Information
output "service_extension_url" {
  description = "URL of the Cloud Run service extension"
  value       = google_cloud_run_v2_service.service_extension.uri
}

output "service_extension_name" {
  description = "Name of the Cloud Run service extension"
  value       = google_cloud_run_v2_service.service_extension.name
}

# Backend Service Information
output "backend_service_id" {
  description = "ID of the backend service"
  value       = google_compute_backend_service.default.id
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_backend_service.default.name
}

output "instance_group_manager_id" {
  description = "ID of the managed instance group"
  value       = google_compute_instance_group_manager.backend_mig.id
}

output "instance_group_url" {
  description = "URL of the instance group"
  value       = google_compute_instance_group_manager.backend_mig.instance_group
}

# IAP Configuration
output "iap_oauth_client_id" {
  description = "OAuth client ID for IAP (sensitive)"
  value       = var.oauth_client_id != "" ? var.oauth_client_id : "Not configured - manual setup required"
  sensitive   = true
}

output "iap_backend_service_name" {
  description = "Backend service name for IAP configuration"
  value       = google_compute_backend_service.default.name
}

# Health Check Information
output "health_check_id" {
  description = "ID of the health check"
  value       = google_compute_health_check.default.id
}

output "health_check_name" {
  description = "Name of the health check"
  value       = google_compute_health_check.default.name
}

# Service Accounts
output "backend_service_account_email" {
  description = "Email of the backend service account"
  value       = google_service_account.backend_sa.email
}

output "service_extension_service_account_email" {
  description = "Email of the service extension service account"
  value       = google_service_account.service_extension_sa.email
}

# Monitoring and Logging
output "log_sink_id" {
  description = "ID of the security log sink"
  value       = google_logging_project_sink.security_sink.id
}

output "monitoring_notification_channel_id" {
  description = "ID of the monitoring notification channel"
  value       = google_monitoring_notification_channel.email.id
}

output "alert_policy_id" {
  description = "ID of the security alert policy"
  value       = google_monitoring_alert_policy.security_alerts.id
}

# Security Recommendations
output "security_recommendations" {
  description = "Important security configuration recommendations"
  value = {
    oauth_setup = var.oauth_client_id == "" ? "Configure OAuth client credentials for IAP" : "OAuth client configured"
    ssl_domains = "Update SSL certificate domains to match your actual domains: ${join(", ", var.ssl_domains)}"
    iap_users   = length(var.iap_users) == 0 ? "Add authorized users to IAP access list" : "IAP users configured: ${length(var.iap_users)} users"
    dns_setup   = "Configure DNS records to point your domains to: ${google_compute_global_address.default.address}"
    monitoring  = "Review and configure monitoring notification email: ${var.notification_email}"
  }
}

# Resource Tags
output "resource_tags" {
  description = "Tags applied to resources"
  value       = local.common_tags
}

# Architecture URLs for Testing
output "testing_urls" {
  description = "URLs for testing different aspects of the zero-trust architecture"
  value = {
    load_balancer_ip    = "https://${google_compute_global_address.default.address}"
    health_check        = "https://${google_compute_global_address.default.address}/health"
    rate_limit_test     = "Use curl or load testing tools against the load balancer IP to test rate limiting"
    geo_blocking_test   = "Test from blocked countries or use VPN to verify geo-blocking rules"
    service_extension   = "Service extension processes requests at: ${google_cloud_run_v2_service.service_extension.uri}"
  }
}

# Cost Optimization Information
output "cost_optimization_notes" {
  description = "Information about resource costs and optimization recommendations"
  value = {
    instance_count     = "Current backend instances: ${var.backend_instance_count}"
    machine_type       = "Using machine type: ${var.machine_type}"
    regions           = "Resources deployed in: ${var.region}"
    log_retention     = "Log retention period: ${var.log_retention_days} days"
    recommendations   = "Consider reducing instance count and machine types for dev/test environments"
  }
}

# Deployment Status
output "deployment_status" {
  description = "Status of the zero-trust architecture deployment"
  value = {
    network_ready      = "VPC and subnet configured with private Google access"
    security_enabled   = "Cloud Armor policy active with rate limiting and geo-blocking"
    load_balancer      = "Global HTTPS load balancer deployed with SSL termination"
    backend_healthy    = "Backend instances deployed in managed instance group"
    service_extension  = "Service extension deployed on Cloud Run"
    monitoring_active  = "Security monitoring and alerting configured"
    iap_status        = var.oauth_client_id != "" ? "IAP configured and active" : "IAP requires OAuth client setup"
  }
}